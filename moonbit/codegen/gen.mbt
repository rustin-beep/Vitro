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
pub const SLOT_STRATEGY_VERSION : Int = 1

struct BytecodeGen {
  code : Array[@opcode.Instruction]
  errors : Array[String]
  func_table : Map[String, @bytecode.FuncMeta]
  func_index : Map[String, Int]
  mut next_func_idx : Int
  mut current_func : String
  mut current_func_arg_count : Int
  mut current_func_arg_bytes : Int
  global_indices : Map[String, Int]
  global_types : Map[String, @ast.Type]
  mut local_indices : Map[String, Int]
  mut local_types : Map[String, @ast.Type]
  mut static_local_indices : Map[String, Int]
  mut static_local_types : Map[String, @ast.Type]
  mut next_local_offset : Int
  mut local_scope_stack : Array[ScopeFrame]
  mut temp_slot0 : Int
  mut temp_slot1 : Int
  mut temp_slot2 : Int
  mut temp_slot3 : Int
  /// 8 字节临时槽（double/long long 的读-改-写中间值）。普通槽位只有
  /// 4 字节空间，64 位位模式写入会踩踏相邻槽/局部变量。
  mut temp_slot_64 : Int
  /// 初始化路径专用基址槽（U1#3 止血）：数组/结构体初始化的基址独占
  /// 此槽，初始化列表元素的 gen_expr 不会覆盖它。
  mut init_base_slot : Int
  /// 赋值目标地址槽的嵌套深度计数（gen_assign 入口递增；T-P0-6）。
  /// （mut 随 gen_assign 扩展批回加——本骨架批无写入点，unused_mut 即 error）
  assign_nest_depth : Int
  /// 按嵌套深度缓存分配的地址槽（下标 = 深度-1），同层顺序复用。
  mut assign_addr_slots : Array[Int]
  globals_init_32 : Array[(UInt, Int)]
  globals_init_64 : Array[(UInt, UInt64)]
  mut next_global_offset : Int
  f64_constants : Array[Double]
  i64_constants : Array[Int64]
  symbols : Array[@bytecode.Symbol]
  sym_index : Map[String, Int]
  struct_defs : Map[String, Array[@ast.StructField]]
  union_defs : Map[String, Array[@ast.StructField]]
  string_data : Array[(UInt, String)]
  /// 全局变量初始化中遇到的字符串字面量，Pass 1 结束后统一分配地址并
  /// 回填——避免字符串区与全局变量区重叠（事故 #12）。
  mut pending_string_inits : Array[(UInt, String)]
  source_map : Array[(UInt, @source.SourceLoc)]
  break_patches : Array[Int]
  continue_patches : Array[Int]
  loop_start_ips : Array[Int]
  mut goto_patches : Map[String, Array[Int]]
  mut label_ips : Map[String, Int]
}

///|
/// 作用域帧：退出作用域时恢复被 shadow 的外部变量（事故 #19——此前
/// 只恢复 local_indices 一张表，遮蔽全局数组出作用域后假边界陷阱）。
struct ScopeFrame {
  shadows : Array[ShadowEntry]
}

///|
struct ShadowEntry {
  name : String
  old_offset : Int?
  old_type : @ast.Type?
  old_sym_idx : Int?
}

///|
fn BytecodeGen::with_mode(is_library_mode : Bool) -> BytecodeGen {
  let func_index : Map[String, Int] = {}
  let next_func_idx = if is_library_mode {
    0
  } else {
    // 预注册 Bytecode Libc 函数到固定索引段。
    // V-P1-6 例外：strcpy/strcat 分发回 Host 路径——Host 实现带 E3070
    // 栈缓冲区容量检测（教学 IDE 的核心安全检测），Bytecode Libc 版
    // 逐字节 StoreMem 无法在拷贝边界做整体容量校验。libc 索引表与预编译
    // 产物保持不变，仅用户侧调用分发回 Host。
    for name in @bytecode.bytecode_libc_all_funcs {
      if name == "strcpy" || name == "strcat" {
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
    next_func_idx,
    current_func: "",
    current_func_arg_count: 0,
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
      @bytecode.BYTECODE_LIBC_GLOBALS_RESERVED.to_int()
    },
    f64_constants: [],
    i64_constants: [],
    symbols: [],
    sym_index: {},
    struct_defs: {},
    union_defs: {},
    string_data: [],
    pending_string_inits: [],
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
  for f in program.funcs {
    if f.body is None {
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
      let sz = if self.type_size(g.ty) > 4 {
        self.type_size(g.ty)
      } else {
        4
      }
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
  // 字符串区位于全局变量区之后）。
  let pending = self.pending_string_inits
  self.pending_string_inits = []
  for entry in pending {
    let (base_offset, value) = entry
    let aligned = ((cstring_len(value) + 1).reinterpret_as_uint() + 3) & @bytecode.ALIGN4_MASK
    match self.bump_global_offset(aligned.to_int(), "全局初始化字符串", default_loc()) {
      Some(str_offset) => {
        let str_addr = @bytecode.GLOBAL_START + str_offset.reinterpret_as_uint()
        self.string_data.push((str_addr, value))
        self.globals_init_32.push((base_offset, str_addr.to_int()))
      }
      None => ()
    }
  }
  // Pass 2：函数元数据（func_index 已预填）。
  for f in program.funcs {
    if f.body is None {
      continue
    }
    let param_sizes = f.params.map(p => self.type_size(p.ty))
    self.func_table.set(
      f.name,
      {
        ip: 0,
        arg_count: 0,
        param_count: 0,
        local_count: 0,
        param_sizes,
        return_type: f.return_type,
        is_variadic: false,
        local_buffers: [],
      },
    )
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
      self.emit(
        @opcode.OpCode::Ret,
        0,
        @source.SourceLoc::with_file(0, 0, 0),
      )
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
    Some(
      {
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
      },
    ),
    [],
  )
}

///|
/// `max(0, next_global_offset)` 照搬（Rust `self.next_global_offset.max(0)`）。
fn BytecodeGen::next_global_offset_clamped(self : BytecodeGen) -> Int {
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
fn BytecodeGen::pass1_register_global(self : BytecodeGen, g : @ast.GlobalDecl) -> Unit {
  if g.ty.is_vla() {
    self.errors.push("全局作用域不支持变长数组(VLA) '\{g.name}'")
    return
  }
  let sz = self.type_size(g.ty)
  let offset = match self.bump_global_offset(
      sz,
      "全局变量 '\{g.name}'",
      g.loc,
    ) {
    Some(o) => o
    None => return
  }
  self.global_indices.set(g.name, offset)
  self.global_types.set(g.name, g.ty)
  match g.init {
    Some(init) =>
      match init {
        InitList(elements, _, _) => {
          let has_designators = elements.exists(
              e => e.designators.length() > 0,
            )
          if has_designators {
            self.report_error("全局变量的 designated initializer 暂不支持", g.loc)
            return
          }
          let is_char_array = match g.ty {
            Array(element, _, _, _, _, _) =>
              element.kind() is TK_Char
            _ => false
          }
          if is_char_array {
            let values = flatten_init_list(elements, self.errors)
            for i in 0..<sz {
              let v = if i < values.length() { values[i] } else { 0 }
              self.globals_init_32.push((offset.reinterpret_as_uint() + i.reinterpret_as_uint(), v))
            }
          } else if g.ty.kind() is TK_Struct ||

            (g.ty.is_array() &&
              elements.exists(e => e.value is InitList(_, _, _))) ||
            // P2：含字符串字面量元素的数组（`char *arr[2] = {"a","b"}`）
            // 同走递归展开——元素级路径对字面量取不到值（NULL 指针静默）。
            (g.ty.is_array() &&
              elements.exists(e => e.value is StringLiteral(_, _, _))) {
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
                let addr = offset.reinterpret_as_uint() + i.reinterpret_as_uint() * elem_size.reinterpret_as_uint()
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
                let addr = offset.reinterpret_as_uint() + i.reinterpret_as_uint() * elem_size.reinterpret_as_uint()
                let v = if i < values.length() { values[i] } else { 0 }
                self.globals_init_32.push((addr, v))
              }
            }
          }
        }
        StringLiteral(value, _, _) => {
          // P2：char 数组目标保持字节直写；其余走 pending_string_inits
          // 取址路径（Pass 1 结束后回填）。此前无条件按 sz 逐字节写，
          // `char *p = "hi"` 指针槽被写成 'h','i',0,0（★A）。
          let is_char_array = match g.ty {
            Array(element, _, _, _, _, _) => element.kind() is TK_Char
            _ => false
          }
          if is_char_array {
            let bytes = cstring_bytes(value)
            for i in 0..<sz {
              let byte = if i < bytes.length() {
                bytes[i].to_int()
              } else {
                0
              }
              self.globals_init_32.push((offset.reinterpret_as_uint() + i.reinterpret_as_uint(), byte))
            }
          } else {
            self.pending_string_inits.push((offset.reinterpret_as_uint(), value))
          }
        }
        Literal(_, _, _) | LongLiteral(_, _, _) | FloatLiteral(_, _, _) => {
          // T-P0-1：全局标量初始化按目标类型编码位模式
          let _ = self.push_literal_init(offset.reinterpret_as_uint(), init, g.ty)
        }
        Unary(@ast.UnaryOp::Neg, operand, _, _) => {
          // 负数字面量（如 double g = -2;）此前落入 _ 分支被静默丢弃。
          // （guard 须与模式同行——手册 #23；跨行条件改 arm 内 if，非字面量
          // 落空等价 Rust guard 不匹配走 _ => ()）
          if operand is Literal(_, _, _) ||
            operand is LongLiteral(_, _, _) ||
            operand is FloatLiteral(_, _, _) {
            let _ = self.push_literal_init(offset.reinterpret_as_uint(), init, g.ty)
          }
        }
        Identifier(name, _, _) => {
          // 全局函数指针初始化：int (*fp)(int) = myFunc;
          match self.func_index.get(name) {
            Some(idx) => self.globals_init_32.push((offset.reinterpret_as_uint(), idx))
            None => ()
          }
        }
        _ => ()
      }
    None => ()
  }
  self.push_symbol(g.name, offset, g.ty, g.loc.line)
}

///|
fn BytecodeGen::push_symbol(
  self : BytecodeGen,
  name : String,
  offset : Int,
  ty : @ast.Type,
  decl_line : Int,
) -> Unit {
  self.sym_index.set(name, self.symbols.length())
  self.symbols.push(
    {
      name,
      addr: offset.reinterpret_as_uint(),
      is_local: false,
      ty,
      scope_depth: 0,
      func_name: "",
      decl_line,
    },
  )
}

///|
fn default_loc() -> @source.SourceLoc {
  @source.SourceLoc::with_file(0, 0, 0)
}

///|
fn BytecodeGen::emit(
  self : BytecodeGen,
  op : @opcode.OpCode,
  operand : Int,
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
fn BytecodeGen::current_ip(self : BytecodeGen) -> Int {
  self.code.length()
}

///|
fn BytecodeGen::patch_jump(self : BytecodeGen, ip : Int, target : Int) -> Unit {
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
  size : Int,
  what : String,
  loc : @source.SourceLoc,
) -> Int? {
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
  self.local_scope_stack.push({ shadows: [] })
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
      }
    None => ()
  }
}

///|
fn BytecodeGen::record_scope_var(self : BytecodeGen, name : String) -> Unit {
  if self.local_scope_stack.length() > 0 {
    let frame = self.local_scope_stack[self.local_scope_stack.length() - 1]
    frame.shadows.push(
      {
        name,
        old_offset: self.local_indices.get(name),
        old_type: self.local_types.get(name),
        old_sym_idx: self.sym_index.get(name),
      },
    )
  }
}

///|
fn BytecodeGen::resolve_local(self : BytecodeGen, name : String) -> Int {
  match self.local_indices.get(name) {
    Some(o) => o
    None => -1
  }
}

///|
fn BytecodeGen::resolve_global(self : BytecodeGen, name : String) -> Int {
  match self.global_indices.get(name) {
    Some(o) => o
    None => -1
  }
}

///|
fn BytecodeGen::resolve_symbol_index(self : BytecodeGen, name : String) -> Int {
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
