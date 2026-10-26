///| C 字符串字节通道已上提为 bytecode 包单源（S6 vm 批一号——vm 片 argv
/// 装载需要同一字节口径，跨 L6/L7 复用须独立单源）：本包消费
/// `@bytecode.cstring_bytes` / `@bytecode.cstring_len`，禁再私写。

///|
/// 字面量的数值形态：整数走 Int64（f64 只有 53 位尾数丢精度），浮点走 Double。
priv enum LitNum {
  LN_I(Int64)
  LN_F(Double)
}

///|
fn lit_num(expr : @ast.Expr) -> LitNum? {
  match expr {
    // typeck 的 insert_implicit_cast 会把初始化元素包装为 Cast{Literal}，
    // 剥开后按内层字面量取值（Cast 语义 = 转换为目标类型，与本函数编码一致）
    Cast(inner, _, _, _) => lit_num(inner)
    Literal(value, _, _) => Some(LN_I(value.to_int64()))
    LongLiteral(value, _, _) => Some(LN_I(value))
    FloatLiteral(value, _, _) => Some(LN_F(value))
    Unary(@ast.UnaryOp::Neg, operand, _, _) =>
      match lit_num(operand) {
        Some(LN_I(v)) => Some(LN_I(v.neg()))
        Some(LN_F(v)) => Some(LN_F(-v))
        None => None
      }
    _ => None
  }
}

///|
/// T-P0-1/T-P0-2：初始化字面量按**目标类型**编码为全局初始化位模式。
/// 返回 `(位模式, 是否 8 字节槽)`；非字面量返回 None。
///
/// Rust 侧 `(v as i64) as u64` / `(v as f64).to_bits()` 等位模式转换，
/// MoonBit 对应：Int64→UInt64 位重解释 `reinterpret_as_uint64`；Double
/// →UInt64 `reinterpret_as_uint64`；f32 位模式 Float::from_double +
/// reinterpret_as_uint。
fn literal_init_bits(
  expr : @ast.Expr,
  target_kind : @ast.TypeKind,
) -> (UInt64, Bool)? {
  let num = match lit_num(expr) {
    Some(n) => n
    None => return None
  }
  Some(
    match (num, target_kind) {
      (LN_I(v), TK_Double) => (v.to_double().reinterpret_as_uint64(), true)
      (LN_I(v), TK_Float) =>
        (f32_bits_u64(Float::from_double(v.to_double())), false)
      // T-P0-2 根因：long long 目标必须写 i64 位模式，而非 f64 位模式
      (LN_I(v), TK_LongLong) => (v.reinterpret_as_uint64(), true)
      (LN_I(v), _) =>
        (v.to_int32_bits().reinterpret_as_uint().to_uint64(), false)
      (LN_F(v), TK_Double) => (v.reinterpret_as_uint64(), true)
      (LN_F(v), TK_Float) => (f32_bits_u64(Float::from_double(v)), false)
      (LN_F(v), TK_LongLong) => (v.to_int64().reinterpret_as_uint64(), true)
      (LN_F(v), _) => (v.to_int().reinterpret_as_uint().to_uint64(), false)
    },
  )
}

///|
/// Float 位模式 → UInt64（低 32 位）。
fn f32_bits_u64(f : Float) -> UInt64 {
  Float::reinterpret_as_uint(f).to_uint64()
}

///|
/// Int64 → 低 32 位 i32 截断（符号解释）——parser/decl.mbt `i64_to_i32_bits`
/// 同款语义；Rust `v as i32`。位模式：先重解释为 UInt64 取低 32 位。
fn Int64::to_int32_bits(v : Int64) -> Int32 {
  let low = v.reinterpret_as_uint64() & 0xFFFFFFFFUL
  if low >= 0x80000000UL {
    (low.reinterpret_as_int64() - 0x100000000L).to_int()
  } else {
    low.reinterpret_as_int64().to_int()
  }
}

///|
/// （Double→Int64 用 core 内置 `Double::to_int64`——js/wasm 后端实现；
/// 与 Rust `as i64` 的饱和语义在越界/NaN 边界可能有差，本函数仅服务
/// LN_F→TK_LongLong 罕见路径（double 字面量初始化 long long，值域小），/// 差异随差分对拍暴露再登记。）

///|
fn BytecodeGen::push_literal_init(
  self : BytecodeGen,
  offset : UInt32,
  expr : @ast.Expr,
  target_ty : @ast.Type,
) -> Bool {
  match literal_init_bits(expr, target_ty.kind()) {
    Some(pair) => {
      let (bits, is64) = pair
      if is64 {
        self.globals_init_64.push((offset, bits))
      } else {
        self.globals_init_32.push(
          (offset, bits.reinterpret_as_int64().to_int()),
        )
      }
      true
    }
    None => false
  }
}

///|
/// 嵌套 InitList → globals_init_32/64 递归展开（全局变量初始化）。
/// C only：class 分支不迁移（Rust init.rs:74-89 对应段）。
fn BytecodeGen::flatten_global_init(
  self : BytecodeGen,
  target_ty : @ast.Type,
  init : @ast.Expr,
  base_offset : UInt32,
) -> Unit {
  match init {
    InitList(elements, _, _) => {
      // #270（2026-10-22）：子层 designated（嵌套聚合的 `.field=`/`[i]=`
      // 指派——`.in = {.b=7, .a=6}` 的内层）分流到 designated 展开单源
      //（数组 Index 分支 + struct/union Field 分支）——旧按位置序无视
      // designator 致元素错位（乱序指派的 a/b 对调）
      let has_desig = elements.exists(e => e.designators.length() > 0)
      if has_desig &&
        (
          target_ty.kind() is TK_Struct ||
          target_ty.kind() is TK_Union ||
          target_ty.is_array()
        ) {
        let g_decl : @ast.GlobalDecl = {
          ..Default::default(),
          ty: target_ty,
          name: "",
        }
        self.flatten_designated_global(
          g_decl,
          elements,
          base_offset.reinterpret_as_int(),
        )
        return
      }
      if target_ty.kind() is TK_Struct || target_ty.kind() is TK_Union {
        // issue #19 连带：union 全局 init（成员偏移恒 0——union_defs 表）
        let fields = match self.struct_defs.get(target_ty.name()) {
          Some(f) => f
          None =>
            match self.union_defs.get(target_ty.name()) {
              Some(f) => f
              None => []
            }
        }
        for i, elem in elements {
          if i >= fields.length() {
            break
          }
          let mut field_offset = 0
          for j in 0..<i {
            field_offset += self.type_size(fields[j].ty)
          }
          self.flatten_global_init(
            fields[i].ty,
            elem.value,
            base_offset + field_offset.reinterpret_as_uint(),
          )
        }
      } else if target_ty.is_array() {
        let inner_ty = target_ty.subscript_type()
        let elem_size = self.type_size(inner_ty)
        for i, elem in elements {
          self.flatten_global_init(
            inner_ty,
            elem.value,
            base_offset + (i * elem_size).reinterpret_as_uint(),
          )
        }
      } else if elements.length() > 0 {
        self.flatten_global_init(target_ty, elements[0].value, base_offset)
      }
    }
    StringLiteral(value, _, _) =>
      if target_ty.is_array() && target_ty.base_element_type().kind() is TK_Char {
        // #75 缺口 3 全局层（2026-10-12，C11 6.7.9p14）：char[] 目标的
        // 字符串字面量按**字节直写**入 globals_init（含尾 NUL 与零填）；
        // 此前落 `_` 兜底 pending_string_inits 把池址当指针回填——
        // `struct S a = {"Hi"}` 的 a.s 变指针值（printf %s 读垃圾）。
        let bytes = @bytecode.cstring_bytes(value)
        let total = target_ty.array_size()
        for i in 0..<total {
          let byte = if i < bytes.length() { bytes[i].to_int() } else { 0 }
          self.globals_init_32.push(
            (base_offset + i.reinterpret_as_uint(), byte),
          )
        }
      } else {
        // 非 char[] 目标的字符串字面量：维持指针回填路径（char* 等）
        self.pending_string_inits.push((base_offset, value))
      }
    _ =>
      // T-P0-1/T-P0-2：标量字面量（含负字面量）统一按目标类型编码位模式
      if !self.push_literal_init(base_offset, init, target_ty) {
        match init {
          Identifier(name, _, _) =>
            match self.func_index.get(name) {
              Some(idx) => self.globals_init_32.push((base_offset, idx))
              // #264（2026-10-22）：数组名地址常量（C23 §6.6p9——数组右值
              // 退化指向首元素，静态规格表互引用标准写法）——旧形态
              // func_index 未命中静默置 0（运行期 NULL 解引用 trap）；
              // 地址模型同取址：GLOBAL_START + offset；前向引用 pending
              None => ignore(self.push_global_addr_init(base_offset, name))
            }
          // #264 同族：&g 地址常量——诊断面 typeck 已放行（Addr 臂），
          // 值回填此前静默置 0
          Unary(@ast.UnaryOp::Addr, Identifier(name, _, _), _, _) =>
            ignore(self.push_global_addr_init(base_offset, name))
          // #304（2026-10-26）：地址常量**链形态**（&s.x / &sa[1].x /
          // &go.in.b / &garr[1]——Member/Index 链 + 末端静态符号）。
          // 旧只认裸 Identifier（上一分支），链形态落 _ 臂静默不回填
          // ⇒ 全零区运行期 E3083 NULL 解引用（typeck 侧整族放行）。
          // 求值与前向引用挂起单源 eval_global_addr_chain
          Unary(@ast.UnaryOp::Addr, chain, _, _) =>
            match self.eval_global_addr_chain(chain) {
              AddrResolved(addr) =>
                self.globals_init_32.push((base_offset, addr))
              AddrDeferred =>
                self.pending_addr_chain_inits.push((base_offset, chain))
              AddrUnsupported =>
                // 动态指针基座 / 非字面量下标：值依赖运行期，静态不可求
                // ——维持旧静默 0 行为（诊断面收口前不恶化）
                ()
            }
          // #304 审阅 P2-1（2026-10-26）：cast 包裹的地址常量链
          //（`int *m4 = (int *)&garr[1]`）——旧落 _ 臂静默 0 ⇒ 运行期
          // E3083；cast 是类型包装非地址偏移，穿透后走同一单源求值
          Cast(_, _, _, _) => {
            let _ = self.try_cast_addr_init(base_offset, init)
            ()
          }
          StringLiteral(value, _, _) =>
            // 延迟到 Pass 1 结束后分配地址，确保字符串区位于全局变量区之后
            self.pending_string_inits.push((base_offset, value))
          _ => ()
        }
      }
  }
}

///|
/// #304（2026-10-26）：文件作用域地址常量链形态的静态求值结果。
priv enum AddrChainEval {
  /// GLOBAL_START + 总偏移（含 base 符号偏移与链上 Member/Index 偏移）
  AddrResolved(Int32)
  /// 链合法但 base 符号未登记（前向引用）——挂 pending 尾轮回填
  AddrDeferred
  /// 非静态可求形态（动态指针基座 / 负或非字面量下标 / 链外表达式）
  /// ——调用方维持旧静默 0 路径
  AddrUnsupported
}

///|
/// #304：地址常量链形态静态求值单点（`&s.x` / `&sa[1].x` / `&go.in.b`
/// / `&garr[1]`——Member/Index 链 + 末端 global/static 符号）。偏移语义
/// 对齐运行期 gen_member_addr / gen_index：节点 ty 定型推进 +
/// get_member_offset/struct_fields_prefix_offset 单源；迭代剥链（深结构
/// 纪律，不递归）。base 符号序 static local → global（对齐
/// push_global_addr_init 的 #283 前置）。指针基座（`p[i]`/`ps->x` 的
/// p——值运行期才有）与非常量下标 Unsupported：get_member_offset 的
/// Pointer 一步解引用臂是运行期语义，静态复用必错值，宁缺勿错。
fn BytecodeGen::eval_global_addr_chain(
  self : BytecodeGen,
  inner : @ast.Expr,
) -> AddrChainEval {
  // 外→内剥链；steps[k] 的内邻 = steps[k+1]（链尾的内邻是 base 节点）
  let steps : Array[@ast.Expr] = []
  let mut cur = inner
  let mut base : @ast.Expr? = None
  while true {
    match cur {
      Member(obj, _, _, _, _) => {
        steps.push(cur)
        cur = obj
      }
      Index(arr, _, _, _) => {
        steps.push(cur)
        cur = arr
      }
      Identifier(_, _, _) => {
        base = Some(cur)
        break
      }
      _ => break
    }
  }
  // 链不合法（含非 Member/Index/Identifier 节点）时 base 保持 None
  let base = match base {
    Some(b) => b
    None => return AddrUnsupported
  }
  // base 符号：#283 序（static local 前置——文件作用域与函数内 static
  // 聚合初始化器共用本通路）；全局指针 base（&p[0]——值动态）拦截
  let base_name = match base {
    Identifier(n, _, _) => n
    _ => return AddrUnsupported
  }
  if base.ty().kind() is TK_Pointer {
    return AddrUnsupported
  }
  let mut offset = match self.static_local_indices.get(base_name) {
    Some(o) => o
    None =>
      match self.global_indices.get(base_name) {
        Some(o) => o
        None => return AddrDeferred
      }
  }
  // 内→外应用：Index 步长 = 下标后类型尺寸（gen_index 的 result_ty 同
  // 源）；Member 偏移 = 内邻节点 ty 的成员偏移（gen_member_addr 的
  // object.ty() 同源）；内邻为 Pointer（ps->x 的 ps）拦截
  let mut k = steps.length() - 1
  while k >= 0 {
    let inner_node : @ast.Expr = if k + 1 < steps.length() {
      steps[k + 1]
    } else {
      base
    }
    match steps[k] {
      Index(_, idx, _, result_ty) =>
        match lit_num(idx) {
          Some(LN_I(v)) =>
            if v >= 0L {
              offset = offset + v.to_int() * self.type_size(result_ty)
            } else {
              return AddrUnsupported
            }
          _ => return AddrUnsupported
        }
      Member(_, mname, _, _, _) => {
        if inner_node.ty().kind() is TK_Pointer {
          return AddrUnsupported
        }
        offset = offset + self.get_member_offset(inner_node.ty(), mname)
      }
      _ => return AddrUnsupported
    }
    k = k - 1
  }
  AddrResolved(@bytecode.GLOBAL_START.reinterpret_as_int() + offset)
}

///|
/// #304 审阅 P2-1（2026-10-26）：cast 包裹的地址常量初始化器统一接线点
/// ——剥外层 Cast（`（int *)&garr[1]`——cast 是类型包装非地址偏移，可
/// 多层）后命中 Unary(Addr) 则走 eval_global_addr_chain 单源求值：
/// Resolved 直写 / Deferred 挂 pending / Unsupported 或非 Addr 形态
/// 返回 false（调用方维持旧路径）。三消费点（flatten 兜底臂 / 顶层
/// 标量臂 / 数组逐元素臂）共用，消三份分支重复。
fn BytecodeGen::try_cast_addr_init(
  self : BytecodeGen,
  slot : UInt32,
  init : @ast.Expr,
) -> Bool {
  let mut inner = init
  while true {
    match inner {
      Cast(e, _, _, _) => {
        inner = e
        continue
      }
      _ => break
    }
  }
  match inner {
    Unary(@ast.UnaryOp::Addr, chain, _, _) =>
      match self.eval_global_addr_chain(chain) {
        AddrResolved(addr) => {
          self.globals_init_32.push((slot, addr))
          true
        }
        AddrDeferred => {
          self.pending_addr_chain_inits.push((slot, chain))
          true
        }
        AddrUnsupported => false
      }
    _ => false
  }
}

///|
/// #264：地址常量回填单点——目标已登记直接写 GLOBAL_START + offset
///（指针 4 字节槽）；前向引用/静态局部（Pass 3 才 bump）落 pending，
/// flush_pending_addr_inits 在 Pass 1/3 尾统一回填（同字符串字面量时机）。
/// 返回 true = 已处置（直写或挂 pending，调用方跳过默认回填防覆盖）；
/// false = 未声明符号（诊断层 E3023 已报，调用方走原路径）。
fn BytecodeGen::push_global_addr_init(
  self : BytecodeGen,
  base_offset : UInt32,
  name : String,
) -> Bool {
  // static local 前置（#283）：静态局部初始化器引用同名 global 时
  // （`static int c = …; static int *p = &c;`）应取 static 槽——
  // 旧序 global 先命中会回填文件作用域地址；flush 侧复用本函数自动继承
  let offset = match self.static_local_indices.get(name) {
    Some(o) => o
    None =>
      match self.global_indices.get(name) {
        Some(o) => o
        None => -1
      }
  }
  if offset >= 0 {
    self.globals_init_32.push(
      (
        base_offset,
        (@bytecode.GLOBAL_START + offset.reinterpret_as_uint()).reinterpret_as_int(),
      ),
    )
    true
  } else {
    // P1-4（审阅批 2026-10-23）：`&f` 函数取址初始化器——func_index 编码
    // 与裸名 Identifier 路径同源（gen.mbt 顶层标量臂先查函数表）；旧只查
    // 变量表，pending 最终丢弃 ⇒ 落 0，运行期 CallPtr「索引 0 越界」TRAP
    match self.func_index.get(name) {
      Some(idx) => {
        self.globals_init_32.push((base_offset, idx))
        true
      }
      None => {
        self.pending_addr_inits.push((base_offset, name))
        true
      }
    }
  }
}

///|
/// 回填 pending_addr_inits（前向引用的地址常量——Pass 1/3 尾调用，幂等；
/// 此时全局与静态局部均已登记，仍 miss = 未声明符号，再挂 pending 至
/// 终轮后丢弃，置 0 由诊断层承接）。
fn BytecodeGen::flush_pending_addr_inits(self : BytecodeGen) -> Unit {
  let pending = self.pending_addr_inits
  self.pending_addr_inits = []
  for entry in pending {
    let (base_offset, name) = entry
    let _ = self.push_global_addr_init(base_offset, name)
  }
  // #304（2026-10-26）：链形态 pending 同轮重求（幂等——仍 Deferred
  // 的条目保留至下一轮，终轮后丢弃语义与裸名 pending 一致）
  let chains = self.pending_addr_chain_inits
  self.pending_addr_chain_inits = []
  for entry in chains {
    let (slot, chain) = entry
    match self.eval_global_addr_chain(chain) {
      AddrResolved(addr) => self.globals_init_32.push((slot, addr))
      AddrDeferred => self.pending_addr_chain_inits.push(entry)
      AddrUnsupported => ()
    }
  }
}

///|
/// 扁平化初始化列表为 i32 数组（char 数组 / 简单数组路径）。
/// **照搬含静默 0 兜底**（`_ => push(0)`——勘察事故 #17 登记的反模式，
/// Rust 现状如此，迁移期不私改；S5 后续批随"无条件 gen_expr"改造收口）。
fn flatten_init_list(
  elements : Array[@ast.InitElement],
  errors : Array[String],
) -> Array[Int32] {
  let result : Array[Int32] = []
  for elem in elements {
    if elem.designators.length() > 0 {
      errors.push("Designated initializer 不支持在此上下文中扁平化")
    }
    match elem.value {
      Literal(value, _, _) => result.push(value)
      // #153（2026-10-18）：超 int32 常量不再上报拒绝——范围判断发生在
      // 无目标类型上下文（long long → unsigned int 隐式转换合法，typeck
      // check_assignable 已放行），上报与全局标量路径 LongLiteral
      // `value.to_int()` 位模式截断（var_decl.mbt）自相矛盾；此处同款
      // 截断 = 模 2^32 的 C 转换语义
      LongLiteral(value, _, _) => result.push(value.to_int())
      FloatLiteral(value, _, _) =>
        result.push(
          Float::from_double(value)
          |> Float::reinterpret_as_uint
          |> UInt32::reinterpret_as_int,
        )
      InitList(inner, _, _) => {
        let sub = flatten_init_list(inner, errors)
        for v in sub {
          result.push(v)
        }
      }
      Unary(@ast.UnaryOp::Neg, operand, _, _) =>
        match operand {
          Literal(value, _, _) => result.push(-value)
          LongLiteral(value, _, _) => result.push((-value).to_int())
          _ => result.push(0)
        }
      _ => result.push(0)
    }
  }
  result
}

///|
/// 数组 stride 计算（Rust init.rs:200 照搬：i32 溢出返 0 哨兵）。
fn compute_stride(arr_type : @ast.Type, elem_size : Int32) -> Int32 {
  if arr_type.is_array() && arr_type.dims().length() > 0 {
    let mut stride = elem_size
    let dims = arr_type.dims()
    for i in 1..<dims.length() {
      let dim = dims[i]
      if dim <= 0 {
        // 非正维度 = VLA（运行时处理）或损坏 AST：0 哨兵
        return 0
      }
      let mul = stride.to_int64() * dim.to_int64()
      if mul > 2147483647L || mul < -2147483648L || mul == 0 {
        return 0
      }
      stride = mul.to_int()
    }
    stride
  } else {
    match arr_type {
      Pointer(pointee, _) =>
        if pointee.is_array() && pointee.dims().length() > 0 {
          let mut stride = elem_size
          let dims = pointee.dims()
          for i in 0..<dims.length() {
            let dim = dims[i]
            if dim <= 0 {
              return 0
            }
            let mul = stride.to_int64() * dim.to_int64()
            if mul > 2147483647L || mul < -2147483648L || mul == 0 {
              return 0
            }
            stride = mul.to_int()
          }
          stride
        } else {
          elem_size
        }
      _ => elem_size
    }
  }
}

///|
/// 语句源位置（Rust init.rs:131 照搬；C++ 变体在 C only 下走默认值）。
fn stmt_loc(stmt : @ast.Stmt) -> @source.SourceLoc {
  match stmt {
    Block(_, loc) => loc
    VarDecl(_, _, _, _, _, _, loc) => loc
    Expr(_, loc) => loc
    If(_, _, _, loc) => loc
    While(_, _, loc) => loc
    DoWhile(_, _, loc) => loc
    For(_, _, _, _, loc) => loc
    Return(_, loc) => loc
    Break(loc) => loc
    Continue(loc) => loc
    Switch(_, _, loc) => loc
    Case(_, _, loc) => loc
    Goto(_, loc) => loc
    Label(_, _, loc) => loc
    _ => default_loc()
  }
}
