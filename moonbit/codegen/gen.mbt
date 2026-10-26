///|
/// BytecodeGen 状态机（S5 骨架，C only 裁剪）——Rust `vitro_codegen::lib.rs`
/// 的 `BytecodeGen` 照搬：**形态等价优先**（S4 同款纪律），47 字段中剔除
/// C++ 专属 7 项（顶层 6：class_defs/class_sizes/class_vtables/
/// lambda_by_ref_fields/loop_scope_depths/loop_break_has_init_frame，加嵌套 1：
/// ScopeFrame.class_vars——砍 C++ 裁定 F-2 后零活跃路径；47→41 顶层 + 1 嵌套）；保留字段名/语义/惰性分配次序逐项一致。
///
/// **槽位策略 v1 = 逐位兼容**：temp_slot0..3 / temp_slot_64 / init_base_slot /
/// assign_addr_slots 的惰性 bump 分配语义与 Rust 完全一致（A 级产物
/// code 段逐位 diff 的前提——槽 offset 是指令立即数）。作用域化 LIFO 池
/// （勘察 §⑤-2 / U3#1 必做项）是 v2，待迁移期 diff 转绿后切换，届时以
/// "策略版本"常量区分。八条槽位事故回归随 v2 落地。
/// **mut 语义**：只有重新绑定的字段标 mut（Map 重建/游标 += /槽位重置）；
/// 纯容器字段（Array push / Map set）不加 mut——MoonBit mut 只管重新
/// 赋值（分区手册 #1）。
/// 槽位分配策略版本（勘察 §8.2 三冻第一条——显式版本化契约）：
/// v1 = 逐位兼容 Rust 现行策略（固定四槽惰性 bump，保 A 级 code 段
/// 逐位 diff）；v2 = 作用域化 LIFO 池（勘察 §⑤-2 / U3#1 必做项，
/// 切换时八条槽位事故回归必挂，diff 锚按本常量分档）。
pub const SLOT_STRATEGY_VERSION : Int32 = 1

///|
priv struct BytecodeGen {
  code : Array[@opcode.Instruction]
  errors : Array[String]
  func_table : Map[String, @bytecode.FuncMeta]
  func_index : Map[String, Int32]
  /// 纯原型声明名（body=None，无定义体）——调用/取值 miss func_index
  /// 后据此区分「已声明但未定义」（如实文案）vs「未声明」（#205）
  declared_only : Map[String, Bool]
  mut next_func_idx : Int32
  mut current_func : String
  mut current_func_arg_bytes : Int32
  global_indices : Map[String, Int32]
  global_types : Map[String, @ast.Type]
  mut local_indices : Map[String, Int32]
  mut local_types : Map[String, @ast.Type]
  mut static_local_indices : Map[String, Int32]
  mut static_local_types : Map[String, @ast.Type]
  mut next_local_offset : Int32
  mut local_scope_stack : Array[ScopeFrame]
  mut temp_slot0 : Int32
  mut temp_slot1 : Int32
  mut temp_slot2 : Int32
  mut temp_slot3 : Int32
  /// 8 字节临时槽（double/long long 的读-改-写中间值）。普通槽位只有
  /// 4 字节空间，64 位位模式写入会踩踏相邻槽/局部变量。
  mut temp_slot_64 : Int32
  /// 初始化路径专用基址槽（U1#3 止血）：数组/结构体初始化的基址独占
  /// 此槽，初始化列表元素的 gen_expr 不会覆盖它。
  mut init_base_slot : Int32
  /// 赋值目标地址槽的嵌套深度计数（gen_assign 入口递增；T-P0-6）。
  mut assign_nest_depth : Int32
  /// 按嵌套深度缓存分配的地址槽（下标 = 深度-1），同层顺序复用。
  mut assign_addr_slots : Array[Int32]
  globals_init_32 : Array[(UInt32, Int32)]
  globals_init_64 : Array[(UInt32, UInt64)]
  mut next_global_offset : Int32
  f64_constants : Array[Double]
  i64_constants : Array[Int64]
  symbols : Array[@bytecode.Symbol]
  sym_index : Map[String, Int32]
  struct_defs : Map[String, Array[@ast.StructField]]
  union_defs : Map[String, Array[@ast.StructField]]
  string_data : Array[(UInt32, String)]
  /// 全局变量初始化中遇到的字符串字面量，Pass 1 结束后统一分配地址并
  /// 回填——避免字符串区与全局变量区重叠（事故 #12）。
  mut pending_string_inits : Array[(UInt32, String)]
  /// #264（2026-10-22）：静态初始化器的**地址常量前向引用**（数组名/
  /// &g 形态，`static const S s = { X };` 而 X 声明在 s 之后）——展开时
  /// 目标 offset 未定，延迟到 Pass 1/3 尾统一回填（同字符串字面量时机）
  mut pending_addr_inits : Array[(UInt32, String)]
  /// #304（2026-10-26）：地址常量**链形态**（&s.x / &sa[1].x——Member/
  /// Index 链）的前向引用——链整体延迟重求值（flatten 时 base 符号
  /// 未登记），回填时机与 pending_addr_inits 同轮
  mut pending_addr_chain_inits : Array[(UInt32, @ast.Expr)]
  /// 字面量池（value → 已分配地址；病 120 修，2026-10-16）：相同内容
  /// 的字符串字面量合并同址（clang 实测合并——`a=="twin" && b=="twin"`
  /// 的指针相等形态；C 标准不要求合但主流实现全合，教学对照避免分叉）
  string_pool : Map[String, UInt32]
  source_map : Array[(UInt32, @source.SourceLoc)]
  break_patches : Array[Int32]
  continue_patches : Array[Int32]
  loop_start_ips : Array[Int32]
  mut goto_patches : Map[String, Array[Int32]]
  mut label_ips : Map[String, Int32]
}

///|
/// 作用域帧：退出作用域时恢复被 shadow 的外部变量（事故 #19——此前
/// 只恢复 local_indices 一张表，遮蔽全局数组出作用域后假边界陷阱）。
priv struct ScopeFrame {
  shadows : Array[ShadowEntry]
}

///|
priv struct ShadowEntry {
  name : String
  old_offset : Int32?
  old_type : @ast.Type?
  old_sym_idx : Int32?
  // #277（2026-10-23）：static 局部两张表纳入遮蔽/恢复链——同名 static
  // 在不同块/不同函数是**独立对象**（C11 6.2.1），退出作用域须恢复外层
  // 映射；普通局部声明这两项恒 None（不碰 static 表）
  old_static_offset : Int32?
  old_static_type : @ast.Type?
}

///|
fn BytecodeGen::with_mode(is_library_mode : Bool) -> BytecodeGen {
  let func_index : Map[String, Int32] = Map([])
  let next_func_idx = if is_library_mode {
    0
  } else {
    // 预注册 Bytecode Libc 函数到固定索引段。
    // V-P1-6 例外：strcpy/strcat 分发回 Host 路径——Host 实现带 E3070
    // 栈缓冲区容量检测（教学 IDE 的核心安全检测），Bytecode Libc 版
    // 逐字节 StoreMem 无法在拷贝边界做整体容量校验。libc 索引表与预编译
    // 产物保持不变，仅用户侧调用分发回 Host。
    // 例外清单单源 = `@bytecode.is_host_rerouted`（2026-09-23 审阅批 P3 接线，
    // 此前此处硬编码两名字）：新增改判名只改 route.mbt 一处，本跳过自动生效；
    // call.mbt 不需要例外知识——例外经 func_index（此处跳过）流入，其
    // "func_index ∪ 非 host 名"判定自动落 CallHost。
    for name in @bytecode.bytecode_libc_all_funcs {
      if @bytecode.is_host_rerouted(name) {
        continue
      }
      match @bytecode.bytecode_libc_index(name) {
        Some(idx) => func_index.set(name, idx)
        None => ()
      }
    }
    @bytecode.BYTECODE_LIBC_BASE_INDEX + @bytecode.BYTECODE_LIBC_FUNC_COUNT + 1
  }
  {
    code: [],
    errors: [],
    func_table: {},
    func_index,
    declared_only: Map([]),
    next_func_idx,
    current_func: "",
    current_func_arg_bytes: 0,
    global_indices: {},
    global_types: {},
    local_indices: {},
    local_types: {},
    static_local_indices: {},
    static_local_types: {},
    next_local_offset: 0,
    local_scope_stack: [],
    temp_slot0: -1,
    temp_slot1: -1,
    temp_slot2: -1,
    temp_slot3: -1,
    temp_slot_64: -1,
    init_base_slot: -1,
    assign_nest_depth: 0,
    assign_addr_slots: [],
    globals_init_32: [],
    globals_init_64: [],
    // 预编译 Bytecode Libc 自身（library mode）时全局/字符串数据从 0 起
    // 分配（Rust 同款自指闭环规避——事故 #13：若也用 RESERVED，
    // globals_size 回算 reserved 每次重生成膨胀 1KB）。
    next_global_offset: if is_library_mode {
      0
    } else {
      @bytecode.BYTECODE_LIBC_GLOBALS_RESERVED.reinterpret_as_int()
    },
    f64_constants: [],
    i64_constants: [],
    symbols: [],
    sym_index: {},
    struct_defs: {},
    union_defs: {},
    string_data: [],
    pending_string_inits: [],
    pending_addr_inits: [],
    pending_addr_chain_inits: [],
    string_pool: Map([]),
    source_map: [],
    break_patches: [],
    continue_patches: [],
    loop_start_ips: [],
    goto_patches: {},
    label_ips: {},
  }
}

///|
fn BytecodeGen::new() -> BytecodeGen {
  BytecodeGen::with_mode(false)
}

///|
/// 错误形态照搬 Rust：文本 `Vec<String>`（`第 N 行：文本`）——结构化
/// 诊断改造是 S8 台账项，迁移期两侧文本一致优先。

///|
fn BytecodeGen::generate(
  self : BytecodeGen,
  program : @ast.ProgramNode,
) -> (@bytecode.CompileOutput?, Array[String]) {
  self.code.push(
    @opcode.Instruction::new(@opcode.OpCode::Nop, 0, default_loc()),
  )
  for s in program.structs {
    self.struct_defs.set(s.name, s.fields)
  }
  for u in program.unions {
    self.union_defs.set(u.name, u.fields)
  }
  // C++ 类注册/尺寸拓扑/builtin 容器映射：砍 C++ 裁定后零活跃（F-2），
  // 不迁移（Rust lib.rs:220-313 对应段）。
  // 预填 func_index：全局初始化器可解析函数名（函数指针初始化）。
  // #205（2026-10-21）：纯原型声明（body=None）收集进 declared_only——
  // 调用点 miss 后区分「已声明但未定义」（C 语义：声明合法、定义缺席
  // 是链接期错；Vitro 一体化如实报）vs「未声明」。
  for f in program.funcs {
    if f.body is None {
      self.declared_only.set(f.name, true)
      continue
    }
    self.func_index.set(f.name, self.next_func_idx)
    self.next_func_idx += 1
  }
  // Pass 1：注册全局变量（字节偏移）——先非 extern 定义，后 extern 占位。
  for g in program.globals {
    if g.is_extern {
      continue
    }
    self.pass1_register_global(g)
  }
  for g in program.globals {
    if g.is_extern {
      if self.global_indices.contains(g.name) {
        continue
      }
      let sz = if self.type_size(g.ty) > 4 { self.type_size(g.ty) } else { 4 }
      match self.bump_global_offset(sz, "extern 声明 '\{g.name}'", g.loc) {
        Some(offset) => {
          self.global_indices.set(g.name, offset)
          self.global_types.set(g.name, g.ty)
          self.push_symbol(g.name, offset, g.ty, g.loc.line)
        }
        None => ()
      }
    }
  }
  // vtable 分配（C++ 虚派发）：不迁移（F-2）。
  // 回填全局变量初始化中的字符串字面量地址（Pass 1 后统一分配——
  // 字符串区位于全局变量区之后）。#264：地址常量前向引用同时机回填。
  self.flush_pending_string_inits()
  self.flush_pending_addr_inits()
  // Pass 2：函数元数据（func_index 已预填）。
  for f in program.funcs {
    if f.body is None {
      continue
    }
    let param_sizes = f.params.map(p => self.type_size(p.ty))
    self.func_table.set(f.name, {
      ip: 0,
      arg_count: 0,
      param_count: 0,
      local_count: 0,
      param_sizes,
      return_type: f.return_type,
      is_variadic: false,
      local_buffers: [],
    })
  }
  // Pass 3：函数体（S5 骨架：最小语句集——Block/Expr/Return；其余语句
  // 族 report_error fail loud，扩展批逐族接线）。
  for f in program.funcs {
    if f.body is None {
      continue
    }
    let func_ip = self.current_ip()
    match self.func_table.get(f.name) {
      Some(meta) => {
        meta.ip = func_ip
        ()
      }
      None => ()
    }
    self.enter_function(f.name, f.params, f.is_variadic)
    match f.body {
      Some(body) => self.gen_stmt(body)
      None => ()
    }
    if f.return_type.kind() is TK_Void {
      self.emit(@opcode.OpCode::RetVoid, 0, f.loc)
    } else {
      self.emit(@opcode.OpCode::PushConst, 0, f.loc)
      self.emit(@opcode.OpCode::Ret, 0, f.loc)
    }
    self.exit_function()
  }
  // Pass 3 尾再回填一次：static 局部聚合的字符串指针成员初值在函数体
  // 生成时（Pass 3）经 flatten_global_init 压入 pending——首轮回填在
  // Pass 1 尾已过，无人消费即丢值（①表 9 号①：解引用 TRAP NULL，
  // 批五 2026-10-07 收口）。幂等：pending 空则无操作。#264：静态局部
  // 的地址常量（&sl / sl 数组名）同批 bump 后此处才可命中，同时机回填。
  self.flush_pending_string_inits()
  self.flush_pending_addr_inits()
  // 入口 wrapper：code[0] = Jump wrapper_ip；PushArgv/PushArgc + Call main + Ret。
  let wrapper_ip = self.current_ip()
  match self.func_index.get("main") {
    Some(main_idx) => {
      // 支持 `main(int argc, char *argv[])`：按 C 调用约定从右到左入栈，
      // VM do_call 先 pop 第一个参数，因此栈顶必须是 argc，下面是 argv。
      match self.func_table.get("main") {
        Some(main_meta) =>
          if main_meta.param_sizes.length() == 2 {
            self.emit(@opcode.OpCode::PushArgv, 0, default_loc())
            self.emit(@opcode.OpCode::PushArgc, 0, default_loc())
          }
        None => ()
      }
      self.emit(
        @opcode.OpCode::Call,
        main_idx,
        @source.SourceLoc::with_file(0, 0, 0),
      )
      self.emit(@opcode.OpCode::Ret, 0, @source.SourceLoc::with_file(0, 0, 0))
      self.code[0] = @opcode.Instruction::new(
        @opcode.OpCode::Jump,
        wrapper_ip,
        default_loc(),
      )
    }
    None => self.errors.push("缺少 main 函数入口")
  }
  if self.errors.length() > 0 {
    return (None, self.errors)
  }
  let end = @bytecode.GLOBAL_START +
    @bytecode.align4(self.next_global_offset_clamped().reinterpret_as_uint())
  (
    Some({
      code: self.code,
      globals_init_32: self.globals_init_32,
      globals_init_64: self.globals_init_64,
      func_table: self.func_table,
      func_index: self.func_index,
      string_data: self.string_data,
      source_map: self.source_map,
      symbols: self.symbols,
      struct_defs: self.struct_defs,
      union_defs: self.union_defs,
      f64_constants: self.f64_constants,
      i64_constants: self.i64_constants,
      global_data_end: end,
    }),
    [],
  )
}

///|
/// `max(0, next_global_offset)` 照搬（Rust `self.next_global_offset.max(0)`）。

///|
/// 回填 pending_string_inits（字符串字面量地址 → globals_init_32；字符串
/// 区位于全局变量区之后）。双调用点：Pass 1 尾（全局初值）+ Pass 3 尾
///（static 局部聚合的字符串指针成员——批五 ①表 9 号①收口）。幂等。
fn BytecodeGen::flush_pending_string_inits(self : BytecodeGen) -> Unit {
  let pending = self.pending_string_inits
  self.pending_string_inits = []
  for entry in pending {
    let (base_offset, value) = entry
    // 病 120 修（2026-10-16）：池命中复用同址（clang 同款合并——同内容
    // 字面量指针相等；未命中才分配入池）
    match self.string_pool.get(value) {
      Some(str_addr) =>
        self.globals_init_32.push((base_offset, str_addr.reinterpret_as_int()))
      None => {
        let aligned = (
            (@bytecode.cstring_len(value) + 1).reinterpret_as_uint() + 3
          ) &
          @bytecode.ALIGN4_MASK
        match
          self.bump_global_offset(
            aligned.reinterpret_as_int(),
            "全局初始化字符串",
            default_loc(),
          ) {
          Some(str_offset) => {
            let str_addr = @bytecode.GLOBAL_START +
              str_offset.reinterpret_as_uint()
            self.string_data.push((str_addr, value))
            self.string_pool.set(value, str_addr)
            self.globals_init_32.push(
              (base_offset, str_addr.reinterpret_as_int()),
            )
          }
          None => ()
        }
      }
    }
  }
}

///|
/// 字符串字面量驻留（病 120 修，2026-10-16）：同内容字面量合并同址
///（clang 实测合并——`a=="twin" && b=="twin"` 指针相等；C 标准不要求
/// 但主流实现全合）。全仓字面量分配单源（此前七处各自 bump 互不知情）
/// ——池命中返回既有地址；未命中 bump + 登记 string_data + 入池。
fn BytecodeGen::intern_string_literal(
  self : BytecodeGen,
  value : String,
  region : String,
  loc : @source.SourceLoc,
) -> UInt32? {
  match self.string_pool.get(value) {
    Some(addr) => Some(addr)
    None => {
      let aligned = (
          (@bytecode.cstring_len(value) + 1).reinterpret_as_uint() + 3
        ) &
        @bytecode.ALIGN4_MASK
      match self.bump_global_offset(aligned.reinterpret_as_int(), region, loc) {
        Some(str_offset) => {
          let str_addr = @bytecode.GLOBAL_START +
            str_offset.reinterpret_as_uint()
          self.string_data.push((str_addr, value))
          self.string_pool.set(value, str_addr)
          Some(str_addr)
        }
        None => None
      }
    }
  }
}

///|
fn BytecodeGen::next_global_offset_clamped(self : BytecodeGen) -> Int32 {
  if self.next_global_offset > 0 {
    self.next_global_offset
  } else {
    0
  }
}

///|
/// Pass 1 单个全局变量注册（非 extern 定义路径）——Rust lib.rs:326-459
/// 照搬：VLA 拒绝 / 尺寸 bump / InitList 分派（char 数组 / struct·嵌套
/// 数组 / 字符串元素数组 / 标量数组 8 字节位模式）/ StringLiteral（char
/// 数组直写 vs pending 取址）/ 标量字面量（含负）/ 函数指针。
fn BytecodeGen::pass1_register_global(
  self : BytecodeGen,
  g : @ast.GlobalDecl,
) -> Unit {
  if g.ty.is_vla() {
    self.errors.push("全局作用域不支持变长数组(VLA) '\{g.name}'")
    return
  }
  let sz = self.type_size(g.ty)
  let offset = match
    self.bump_global_offset(sz, "全局变量 '\{g.name}'", g.loc) {
    Some(o) => o
    None => return
  }
  self.global_indices.set(g.name, offset)
  self.global_types.set(g.name, g.ty)
  match g.init {
    Some(init) =>
      match init {
        InitList(elements, _, _) => {
          let has_designators = elements.exists(e => e.designators.length() > 0)
          if has_designators {
            // #76 缺口 4（2026-10-13）：文件作用域指定初始化器——Index
            // designator 标量数组按 C11 6.7.9 稀疏展开（块作用域同款写法
            // 本就支持，仅全局路径缺）；Field designator/嵌套聚合形态
            // 维持 fail loud（诚实收窄）。旧形态 fail loud 无诊断码出口
            //（#38 登记的活体）。
            // 审阅 P1-b（2026-10-14）：return 跳过函数尾 push_symbol——
            // designated 全局不进 symbols 表（sym_index 缺项 → 运行期越界
            // 教学文案降级为无变量名形态）；改走尾部统一 push。
            self.flatten_designated_global(g, elements, offset)
          } else {
            let is_char_array = match g.ty {
              // #193 a10（2026-10-21）：一维限定——多维 char（dims=[3,8]
              // 单节点 element=char）误进本路径后 flatten_init_list 对
              // StringLiteral 元素静默 0（全局静默错值实锤）；多维落到
              // 下方「字符串元素数组」分支走 flatten_global_init 字节
              // 直写（static 局部路径 #137 连坐当年已加同款限定，全局
              // 路径漏了连坐）
              Array(element, _, dims, _, _, _) =>
                element.kind() is TK_Char && dims.length() == 1
              _ => false
            }
            if is_char_array {
              let values = flatten_init_list(elements, self.errors)
              for i in 0..<sz {
                let v = if i < values.length() { values[i] } else { 0 }
                self.globals_init_32.push(
                  (offset.reinterpret_as_uint() + i.reinterpret_as_uint(), v),
                )
              }
            } else if g.ty.kind() is TK_Struct ||
              (
                g.ty.is_array() &&
                elements.exists(e => e.value is InitList(_, _, _))
              ) ||
              // P2：含字符串字面量元素的数组（`char *arr[2] = {"a","b"}`）
              // 同走递归展开——元素级路径对字面量取不到值（NULL 指针静默）。
              (
                g.ty.is_array() &&
                elements.exists(e => e.value is StringLiteral(_, _, _))
              ) {
              // struct / 嵌套数组 / 字符串元素数组：递归展开
              self.flatten_global_init(g.ty, init, offset.reinterpret_as_uint())
            } else {
              // 非字符数组：逐元素
              let elem_size = self.elem_type_size(g.ty)
              let count = g.ty.total_elements()
              if elem_size == 8 {
                // T-P0-2：8 字节元素按元素类型编码位模式
                let elem_ty = g.ty.base_element_type()
                for i in 0..<count {
                  let addr = offset.reinterpret_as_uint() +
                    i.reinterpret_as_uint() * elem_size.reinterpret_as_uint()
                  let val64 = match elements.get(i) {
                    Some(elem) =>
                      match literal_init_bits(elem.value, elem_ty.kind()) {
                        Some(pair) => pair.0
                        None => 0
                      }
                    None => 0
                  }
                  self.globals_init_64.push((addr, val64))
                }
              } else {
                let values = flatten_init_list(elements, self.errors)
                for i in 0..<count {
                  let addr = offset.reinterpret_as_uint() +
                    i.reinterpret_as_uint() * elem_size.reinterpret_as_uint()
                  // #201-B（2026-10-21）：函数指针元素（`AF fns[3] = {a1,
                  // a2}`）——flatten_init_list 只折叠字面量，函数名元素
                  // 静默落 0（判空恒假 + CallPtr「索引 0 越界」TRAP；
                  // 全局标量臂 `AF g = a1` 走 func_index 编码一直正确）。
                  // 与标量臂同源查 func_index，非函数名元素照旧取折叠值。
                  // #201-B/#264：元素为函数名（func_index 编码）/数组名
                  //（地址常量——#264 直写或前向 pending，handled 时跳过
                  // 默认 push 防覆盖）；其余取 flatten_init_list 折叠值
                  let mut addr_handled = false
                  let v = match elements.get(i) {
                    Some(e) =>
                      match e.value {
                        Identifier(name, _, _) =>
                          match self.func_index.get(name) {
                            Some(idx) => idx
                            None => {
                              addr_handled = self.push_global_addr_init(
                                addr, name,
                              )
                              if addr_handled || i >= values.length() {
                                0
                              } else {
                                values[i]
                              }
                            }
                          }
                        // P1-4（审阅批 2026-10-23）：`&f` 取址元素——与裸
                        // 名同源（push_global_addr_init 已补 func_index 查
                        // 询：函数名落 func_index 编码 / 数组名落地址 /
                        // 前向 pending）；旧落 flatten 折叠 0 ⇒ CallPtr
                        // 索引越界 TRAP
                        Unary(@ast.UnaryOp::Addr, Identifier(aname, _, _), _, _) => {
                          addr_handled = self.push_global_addr_init(addr, aname)
                          if addr_handled || i >= values.length() {
                            0
                          } else {
                            values[i]
                          }
                        }
                        // #304（2026-10-26）：聚合元素的地址常量**链形态**
                        //（`int *arr[2] = {&gm.v, &later.x}`）——旧落 _ 臂
                        // 取 flatten_init_list 折叠值（链形态折不出 ⇒ 0）
                        // ⇒ 运行期 E3083；与顶层/flatten 两路径同款单源
                        Unary(@ast.UnaryOp::Addr, chain, _, _) => {
                          match self.eval_global_addr_chain(chain) {
                            AddrResolved(a) => {
                              self.globals_init_32.push((addr, a))
                              addr_handled = true
                            }
                            AddrDeferred => {
                              self.pending_addr_chain_inits.push((addr, chain))
                              addr_handled = true
                            }
                            AddrUnsupported => ()
                          }
                          if addr_handled || i >= values.length() {
                            0
                          } else {
                            values[i]
                          }
                        }
                        _ => if i < values.length() { values[i] } else { 0 }
                      }
                    None => 0
                  }
                  if !addr_handled {
                    self.globals_init_32.push((addr, v))
                  }
                }
              }
            }
          }
        } // else 臂闭（审阅 P1-b：非 designated 原逻辑）
        StringLiteral(value, _, _) => {
          // P2：char 数组目标保持字节直写；其余走 pending_string_inits
          // 取址路径（Pass 1 结束后回填）。此前无条件按 sz 逐字节写，
          // `char *p = "hi"` 指针槽被写成 'h','i',0,0（★A）。
          let is_char_array = match g.ty {
            Array(element, _, _, _, _, _) => element.kind() is TK_Char
            _ => false
          }
          if is_char_array {
            let bytes = @bytecode.cstring_bytes(value)
            for i in 0..<sz {
              let byte = if i < bytes.length() { bytes[i].to_int() } else { 0 }
              self.globals_init_32.push(
                (offset.reinterpret_as_uint() + i.reinterpret_as_uint(), byte),
              )
            }
          } else {
            self.pending_string_inits.push(
              (offset.reinterpret_as_uint(), value),
            )
          }
        }
        Literal(_, _, _) | LongLiteral(_, _, _) | FloatLiteral(_, _, _) => {
          // T-P0-1：全局标量初始化按目标类型编码位模式
          let _ = self.push_literal_init(
            offset.reinterpret_as_uint(),
            init,
            g.ty,
          )
        }
        Unary(@ast.UnaryOp::Neg, operand, _, _) =>
          // 负数字面量（如 double g = -2;）此前落入 _ 分支被静默丢弃。
          // （guard 须与模式同行——手册 #23；跨行条件改 arm 内 if，非字面量
          // 落空等价 Rust guard 不匹配走 _ => ()）
          if operand is Literal(_, _, _) ||
            operand is LongLiteral(_, _, _) ||
            operand is FloatLiteral(_, _, _) {
            let _ = self.push_literal_init(
              offset.reinterpret_as_uint(),
              init,
              g.ty,
            )
          }
        Identifier(name, _, _) =>
          // 全局函数指针初始化：int (*fp)(int) = myFunc;
          match self.func_index.get(name) {
            Some(idx) =>
              self.globals_init_32.push((offset.reinterpret_as_uint(), idx))
            // #264（2026-10-22）：数组名地址常量（顶层标量 char* = ARR——
            // 旧 None => () 静默置 0）；函数名/数组名双查同 flatten 路径
            None => {
              let _ = self.push_global_addr_init(
                offset.reinterpret_as_uint(),
                name,
              )
              ()
            }
          }
        // #264 同族：&g 顶层标量地址常量（旧落 _ => () 静默置 0）
        Unary(@ast.UnaryOp::Addr, Identifier(name, _, _), _, _) => {
          let _ = self.push_global_addr_init(offset.reinterpret_as_uint(), name)
          ()
        }
        // #304（2026-10-26）：顶层标量地址常量**链形态**（int *p = &s.x
        // / &sa[1].x / &go.in.b / &garr[1]）——旧落 _ => () 静默置 0 ⇒
        // 运行期 E3083；与聚合内 flatten_global_init 同款单源求值
        Unary(@ast.UnaryOp::Addr, chain, _, _) => {
          match self.eval_global_addr_chain(chain) {
            AddrResolved(addr) =>
              self.globals_init_32.push((offset.reinterpret_as_uint(), addr))
            AddrDeferred =>
              self.pending_addr_chain_inits.push(
                (offset.reinterpret_as_uint(), chain),
              )
            AddrUnsupported => ()
          }
          ()
        }
        _ => ()
      }
    None => ()
  }
  self.push_symbol(g.name, offset, g.ty, g.loc.line)
}

///|
/// #76 缺口 4（2026-10-13）：文件作用域指定初始化器稀疏展开——顶层
/// Index designator 指位（C11 6.7.9：designator 定位后，后续无
/// designator 的元素按 prev+1 续位），未提及位置保持静态零（不产生写
/// 记录）。仅收标量元素数组（位模式经 literal_init_bits 单源，4/8 字节
/// 两路与顺序路径同构）；Field designator（struct 成员指派）/嵌套
/// InitList 元素/多维下标链维持 fail loud（诚实收窄——本批只销 #76
/// 命中形态）。
fn BytecodeGen::flatten_designated_global(
  self : BytecodeGen,
  g : @ast.GlobalDecl,
  elements : Array[@ast.InitElement],
  offset : Int32,
) -> Unit {
  // #270（2026-10-22，C99 §6.7.8 designator 的 .field 形态）：struct/
  // union 目标的成员指派——按名定位（含匿名成员穿透）递归 flatten，
  // 未提及位置保持静态零；designator 后裸项按 prev+1 续位（数组语义
  // 同构）；局部 static 聚合同经本函数自动受益
  if g.ty.kind() is TK_Struct || g.ty.kind() is TK_Union {
    self.flatten_struct_designated_global(g, elements, offset)
    return
  }
  guard g.ty.is_array() else {
    self.report_error(
      "designated initializer 仅支持数组或结构体目标（'\{g.name}' 为 \{g.ty.to_c_string()}）",
      g.loc,
    )
    return
  }
  let elem_size = self.elem_type_size(g.ty)
  let elem_ty_kind = g.ty.base_element_type().kind()
  let mut next_index : Int32 = 0
  for elem in elements {
    // 单层 Index designator（[i][j] 链与 .field 形态收窄拒绝）
    match elem.designators.length() {
      0 => ()
      1 =>
        match elem.designators[0] {
          Index(idx_expr) => {
            // 下标常量求值复用 lit_num（Literal/LongLiteral/Neg/Cast 剥壳）
            let idx = match lit_num(idx_expr) {
              Some(LN_I(v)) =>
                if v < -2147483648L || v > 2147483647L {
                  None
                } else {
                  Some(v.to_int())
                }
              _ => None
            }
            match idx {
              Some(v) =>
                if v < 0 || v >= g.ty.total_elements() {
                  self.report_error(
                    "designated initializer 下标 \{v} 越界（'\{g.name}' 共 \{g.ty.total_elements()} 元素）",
                    g.loc,
                  )
                  return
                } else {
                  next_index = v
                }
              None => {
                self.report_error(
                  "designated initializer 下标须为整型常量表达式",
                  g.loc,
                )
                return
              }
            }
          }
          Field(_) => {
            self.report_error(
              "designated initializer 的成员指派（.field=）暂不支持（数组下标 [i]= 支持）",
              g.loc,
            )
            return
          }
        }
      _ => {
        self.report_error(
          "designated initializer 的多级指派链暂不支持（单级 [i]= 支持）",
          g.loc,
        )
        return
      }
    }
    if elem.value is InitList(_, _, _) {
      self.report_error(
        "designated initializer 的嵌套聚合元素暂不支持",
        g.loc,
      )
      return
    }
    match literal_init_bits(elem.value, elem_ty_kind) {
      Some((bits, _)) => {
        let addr = offset.reinterpret_as_uint() +
          next_index.reinterpret_as_uint() * elem_size.reinterpret_as_uint()
        if elem_size == 8 {
          self.globals_init_64.push((addr, bits))
        } else {
          self.globals_init_32.push(
            (addr, bits.reinterpret_as_int64().to_int32_bits()),
          )
        }
      }
      None =>
        self.report_error(
          "designated initializer 元素须为标量常量（'\{g.name}'）",
          g.loc,
        )
    }
    next_index = next_index + 1
  }
}

///|
/// #270（2026-10-22，C99 §6.7.8p35 designator 的 .field 形态）：
/// struct/union 目标的 designated 全局展开——按名定位（含 #266 匿名
/// 成员穿透）+ flatten_global_init 递归（标量位模式/嵌套聚合/字符串
/// 直写全复用既有单源）；designator 后裸项按 prev+1 续位；未提及位置
/// 保持静态零（全局区零填语义）。
fn BytecodeGen::flatten_struct_designated_global(
  self : BytecodeGen,
  g : @ast.GlobalDecl,
  elements : Array[@ast.InitElement],
  offset : Int32,
) -> Unit {
  let fields = match g.ty.kind() {
    TK_Struct => self.struct_defs.get(g.ty.name())
    _ => self.union_defs.get(g.ty.name())
  }
  let fields : Array[@ast.StructField] = match fields {
    Some(f) => f
    None => {
      self.report_error(
        "designated initializer 目标 '\{g.name}' 字段表缺失",
        g.loc,
      )
      return
    }
  }
  let is_union = g.ty.kind() is TK_Union
  let mut cursor = 0
  for elem in elements {
    if elem.designators.length() == 0 {
      // 裸项续位（designator 后 prev+1——C11 6.7.9 current object）
      if cursor >= fields.length() {
        continue
      }
      let cur = cursor
      cursor = cur + 1
      let mut o = 0
      if !is_union {
        for j = 0; j < cur; j = j + 1 {
          o += self.type_size(fields[j].ty)
        }
      }
      self.flatten_global_init(
        fields[cur].ty,
        elem.value,
        (offset + o).reinterpret_as_uint(),
      )
      continue
    }
    match elem.designators[0] {
      Field(fname) => {
        let mut found = -1
        for j, f in fields {
          if f.name == fname {
            found = j
            break
          }
        }
        if found >= 0 {
          cursor = found + 1
          let mut o = 0
          if !is_union {
            for j = 0; j < found; j = j + 1 {
              o += self.type_size(fields[j].ty)
            }
          }
          self.flatten_global_init(
            fields[found].ty,
            elem.value,
            (offset + o).reinterpret_as_uint(),
          )
        } else {
          // #266：匿名成员穿透（.a 命中匿名 union/struct 内部）
          match self.anon_promote_lookup(fields, fname) {
            Some((outer_idx, inner_off, member_ty)) => {
              cursor = outer_idx + 1
              let mut o = inner_off
              if !is_union {
                for j = 0; j < outer_idx; j = j + 1 {
                  o += self.type_size(fields[j].ty)
                }
              }
              self.flatten_global_init(
                member_ty,
                elem.value,
                (offset + o).reinterpret_as_uint(),
              )
            }
            None =>
              self.report_error(
                "结构体 '\{g.ty.name()}' 没有字段 '\{fname}'（'\{g.name}'）",
                g.loc,
              )
          }
        }
      }
      _ => {
        self.report_error(
          "结构体目标的 designated initializer 只支持 .field 指派（'\{g.name}'）",
          g.loc,
        )
        return
      }
    }
  }
}

///|
fn BytecodeGen::push_symbol(
  self : BytecodeGen,
  name : String,
  offset : Int32,
  ty : @ast.Type,
  decl_line : Int32,
) -> Unit {
  self.sym_index.set(name, self.symbols.length())
  self.symbols.push({
    name,
    addr: offset.reinterpret_as_uint(),
    is_local: false,
    ty,
    scope_depth: 0,
    func_name: "",
    decl_line,
  })
}

///|
fn default_loc() -> @source.SourceLoc {
  @source.SourceLoc::with_file(0, 0, 0)
}

///|
fn BytecodeGen::emit(
  self : BytecodeGen,
  op : @opcode.OpCode,
  operand : Int32,
  loc : @source.SourceLoc,
) -> Unit {
  let ip = self.code.length()
  let vm_loc = @source.SourceLoc::with_file(loc.line, loc.column, 0)
  self.code.push(@opcode.Instruction::new(op, operand, vm_loc))
  if loc.line > 0 {
    self.source_map.push((ip.reinterpret_as_uint(), vm_loc))
  }
}

///|
fn BytecodeGen::current_ip(self : BytecodeGen) -> Int32 {
  self.code.length()
}

///|
fn BytecodeGen::patch_jump(
  self : BytecodeGen,
  ip : Int32,
  target : Int32,
) -> Unit {
  if ip < self.code.length() {
    // Instruction.operand 不可变（opcode 包已发布契约）——整条替换等价改写
    let old_ins = self.code[ip]
    self.code[ip] = @opcode.Instruction::new(old_ins.op, target, old_ins.loc)
  }
}

///|
fn BytecodeGen::report_error(
  self : BytecodeGen,
  msg : String,
  loc : @source.SourceLoc,
) -> Unit {
  self.errors.push("第 \{loc.line} 行：\{msg}")
}

///|
/// R1 ②：全局数据区 bump 的唯一入口。越过 `GLOBAL_REGION_LIMIT` 时报错
/// 并返回 None（错误已入 errors，generate 终将失败返回）；成功时推进
/// `next_global_offset` 并返回分配基偏移。`size` 是否对齐由调用方决定
/// （全局地址是行为锚，不顺手改变布局）。
fn BytecodeGen::bump_global_offset(
  self : BytecodeGen,
  size : Int32,
  what : String,
  loc : @source.SourceLoc,
) -> Int32? {
  let offset = self.next_global_offset
  let end = offset.to_int64() + size.to_int64()
  let limit = (@bytecode.GLOBAL_REGION_LIMIT - @bytecode.GLOBAL_START).to_int64()
  if end > limit {
    self.report_error(
      "\{what}：全局数据区容量不足（已用 \{offset} 字节，还需 \{size} 字节，上限 \{limit} 字节）。请减小全局数组或字符串的规模",
      loc,
    )
    return None
  }
  self.next_global_offset = end.to_int()
  Some(offset)
}

///|
fn BytecodeGen::enter_scope(self : BytecodeGen) -> Unit {
  self.local_scope_stack.push({ shadows: [], })
}

///|
/// 作用域退出：恢复被 shadow 的外部变量（offset/type/sym_idx 三元组，
/// Rust 照搬——事故 #19 的结构体回滚形态；C++ class_vars 析构不迁移）。
fn BytecodeGen::exit_scope(self : BytecodeGen) -> Unit {
  match self.local_scope_stack.pop() {
    Some(frame) =>
      for entry in frame.shadows {
        match entry.old_offset {
          Some(old) => self.local_indices.set(entry.name, old)
          None => self.local_indices.remove(entry.name)
        }
        match entry.old_type {
          Some(old) => self.local_types.set(entry.name, old)
          None => self.local_types.remove(entry.name)
        }
        match entry.old_sym_idx {
          Some(old) => self.sym_index.set(entry.name, old)
          None => self.sym_index.remove(entry.name)
        }
        // #277：static 两张表同款恢复（PR #282 审阅 P1 后 old_ 全为登记
        // 时真值——同名字在另一族表有条目时恢复之，无条目（None）才 remove）
        match entry.old_static_offset {
          Some(old) => self.static_local_indices.set(entry.name, old)
          None => self.static_local_indices.remove(entry.name)
        }
        match entry.old_static_type {
          Some(old) => self.static_local_types.set(entry.name, old)
          None => self.static_local_types.remove(entry.name)
        }
      }
    None => ()
  }
}

///|
fn BytecodeGen::record_scope_var(self : BytecodeGen, name : String) -> Unit {
  if self.local_scope_stack.length() > 0 {
    let frame = self.local_scope_stack[self.local_scope_stack.length() - 1]
    // PR #282 审阅 P1（2026-10-23）：五张表 old_ 一律取真值——同名字被
    // 另一族（static/普通）登记过时，硬编码 None 会在 exit_scope 把另一张
    // 表的同名条目 remove（跨族同名遮蔽退出即「未声明的标识符」误拒；
    // 解析链里 static_local 排 global 后时退化静默错指 global）
    let old_static = self.static_local_indices.get(name)
    frame.shadows.push({
      name,
      old_offset: self.local_indices.get(name),
      old_type: self.local_types.get(name),
      old_sym_idx: self.sym_index.get(name),
      old_static_offset: old_static,
      old_static_type: self.static_local_types.get(name),
    })
    // P1 补丁二段（处方实测后补）：普通声明遮蔽外层 static 时同步
    // remove static 表同名条目——块内解析链（local→global→static_local）
    // 才会命中本声明；退出由恢复链 set 回（对称）。不 remove 则块内
    // 读错指外层静态槽（探针 p1b/p1c 实测：修误拒后显形为静默错值）
    if old_static is Some(_) {
      self.static_local_indices.remove(name)
    }
  }
}

///|
/// #277（2026-10-23）：static 局部声明的遮蔽登记——static 两表 + 共享的
/// sym_index 记旧值。须在 set 新映射**之前**调用。函数级作用域起点清空
/// scope 栈（func.mbt），跨函数同名 static 各自分配、互不残留。
/// PR #282 审阅 P1：old_ 全取真值（同 record_scope_var 注）。
fn BytecodeGen::record_scope_static(self : BytecodeGen, name : String) -> Unit {
  if self.local_scope_stack.length() > 0 {
    let frame = self.local_scope_stack[self.local_scope_stack.length() - 1]
    let old_local = self.local_indices.get(name)
    frame.shadows.push({
      name,
      old_offset: old_local,
      old_type: self.local_types.get(name),
      old_sym_idx: self.sym_index.get(name),
      old_static_offset: self.static_local_indices.get(name),
      old_static_type: self.static_local_types.get(name),
    })
    // P1 补丁二段：static 声明遮蔽外层普通局部/参数时同步 remove local
    // 表同名条目（对称理由同 record_scope_var——不 remove 则块内读错指
    // 外层普通槽，探针 p1b 块内读 5≠2、p1c 参数形 ret 5≠4 实测）
    if old_local is Some(_) {
      self.local_indices.remove(name)
    }
  }
}

///|
fn BytecodeGen::resolve_local(self : BytecodeGen, name : String) -> Int32 {
  match self.local_indices.get(name) {
    Some(o) => o
    None => -1
  }
}

///|
fn BytecodeGen::resolve_global(self : BytecodeGen, name : String) -> Int32 {
  match self.global_indices.get(name) {
    Some(o) => o
    None => -1
  }
}

///|
fn BytecodeGen::resolve_symbol_index(
  self : BytecodeGen,
  name : String,
) -> Int32 {
  match self.sym_index.get(name) {
    Some(o) => o
    None => -1
  }
}

///|
/// 公共编译入口：类型检查后的 ProgramNode → CompileOutput（S5 骨架——
/// 语句/表达式族按扩展批逐族接线，未接线族 fail loud 见 gen_stmt/gen_expr）。
/// 错误为 Rust 同款文本数组（`第 N 行：…`）。
pub fn compile(
  program : @ast.ProgramNode,
) -> (@bytecode.CompileOutput?, Array[String]) {
  let gen = BytecodeGen::new()
  gen.generate(program)
}

///|
/// library mode 编译入口（预编译 Bytecode Libc 自身用）——与 `compile` 的
/// 唯一差别是初始化按 library mode 走：不预注册 `BYTECODE_LIBC_ALL_FUNCS`
/// 固定索引段（`next_func_idx` 自 0 起）、全局偏移自 0 起（不预留
/// `BYTECODE_LIBC_GLOBALS_RESERVED`）。语义与 Rust `BytecodeGen::with_mode(true)`
/// 逐项同构（Rust 侧该标志也**只改这两个初值**）。
///
/// **main 检查不豁免**（有意与 Rust 同构）：Rust 侧 `generate` 的「缺少 main
/// 函数入口」检查同样无 library 分支——`vitro_cli export` 是靠**注入 stub
/// main 再过滤**（`__export_main_stub.c` + code 截断 + func_table/func_index
/// 删 main）绕过的，而非在 codegen 内放行。故本入口也要求调用方自带 main
/// （libc 自举的 stub 口径见 `scripts/libc_boot_diff`）。
pub fn compile_library(
  program : @ast.ProgramNode,
) -> (@bytecode.CompileOutput?, Array[String]) {
  let gen = BytecodeGen::with_mode(true)
  gen.generate(program)
}
