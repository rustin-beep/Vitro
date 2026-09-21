///|
/// 函数进出与帧原语（Rust `vitro_codegen/src/func.rs` + lib.rs:710-759
/// 槽位段照搬；C only 剔除 class 判定中的 is_class 伴生分支——is_struct
/// 判定保留，C 的 struct 返回值同走 __ret_ptr）。
fn BytecodeGen::enter_function(
  self : BytecodeGen,
  name : String,
  params : Array[@ast.Param],
  is_variadic : Bool,
) -> Unit {
  self.current_func = name
  self.local_indices = {}
  self.local_types = {}
  // T-P0-7：static 局部变量表按函数隔离。此前以裸变量名跨函数共享，
  // 两个函数各有一个 `static int x` 时后者复用前者的地址与初始化。
  self.static_local_indices = {}
  self.static_local_types = {}
  self.goto_patches = {}
  self.label_ips = {}
  self.local_scope_stack = []
  self.next_local_offset = 0
  let mut offset = 0
  let param_sizes : Array[Int] = []
  let returns_struct = match self.func_table.get(name) {
    Some(m) => m.return_type.kind() is TK_Struct
    None => false
  }
  if returns_struct {
    param_sizes.push(1)
    self.local_indices.set("__ret_ptr", offset)
    self.local_types.set("__ret_ptr", @ast.Type::pointer_to(@ast.Type::int()))
    offset += 4
  }
  for p in params {
    let sz = self.type_size(p.ty)
    let aligned_sz = if sz % 4 == 0 { sz } else { sz + 4 - sz % 4 }
    let words = (sz + 3) / 4
    param_sizes.push(words)
    self.local_indices.set(p.name, offset)
    self.local_types.set(p.name, p.ty)
    self.sym_index.set(p.name, self.symbols.length())
    self.symbols.push({
      name: p.name,
      addr: offset.reinterpret_as_uint(),
      is_local: true,
      ty: p.ty,
      scope_depth: 1,
      func_name: self.current_func,
      decl_line: p.loc.line,
    })
    offset += aligned_sz
  }
  // 变参函数预留变参区域（最多 16 个 int / 64 字节）——U3#7 未修形态
  // 照搬（固定 64 字节，>16 words 静默覆写被调函数局部变量的已知缺陷，
  // 登记在案待目标架构批修复，迁移期不私改）。
  if is_variadic {
    offset += 64
  }
  self.next_local_offset = offset
  self.current_func_arg_bytes = offset - (if is_variadic { 64 } else { 0 })
  self.current_func_arg_count = params.length()
  if returns_struct {
    self.current_func_arg_count += 1
  }
  self.temp_slot0 = -1
  self.temp_slot1 = -1
  self.temp_slot2 = -1
  self.temp_slot3 = -1
  // 与 temp_slot0~3 同理：按函数重新惰性分配，跨函数复用 offset 会在
  // 小帧函数越界踩踏（曾致链表/队列类 baseline 用例回归）
  self.temp_slot_64 = -1
  self.init_base_slot = -1
  self.assign_addr_slots = []
  match self.func_table.get(name) {
    Some(meta) => {
      meta.param_sizes = param_sizes
      meta.is_variadic = is_variadic
      ()
    }
    None => ()
  }
}

///|
fn BytecodeGen::exit_function(self : BytecodeGen) -> Unit {
  if self.current_func != "" {
    match self.func_table.get(self.current_func) {
      Some(meta) => {
        meta.local_count = self.next_local_offset
        // arg_count = 参数总 word 数（供 Call 指令弹栈）
        let mut total = 0
        for w in meta.param_sizes {
          total += w
        }
        meta.arg_count = total
        // param_count = 参数个数（供 call_user_function 使用）
        meta.param_count = meta.param_sizes.length()
        ()
      }
      None => ()
    }
  }
  self.current_func = ""
  self.local_indices = {}
  self.local_types = {}
  self.local_scope_stack = []
}

///|
/// 固定临时槽（v1 逐位兼容策略）：惰性分配。**越界 index fail loud**——
/// Rust `_ => &mut self.temp_slot0` 的静默回退（勘察 §⑥ 静默失败模式）
/// 不继承：合法调用域只有 0..=3（四槽机制的天花板是 8 条槽位事故的
/// 根因），越界即缺陷，报错优于静默共享 slot0。
fn BytecodeGen::get_temp_slot(self : BytecodeGen, index : Int) -> Int {
  let mut idx = index
  if idx < 0 || idx > 3 {
    self.report_error(
      "内部错误：临时槽位索引 \{idx} 越界（合法域 0..=3，v1 固定四槽）",
      default_loc(),
    )
    idx = 0
  }
  let slot = match idx {
    0 => self.temp_slot0
    1 => self.temp_slot1
    2 => self.temp_slot2
    _ => self.temp_slot3
  }
  if slot < 0 {
    let new_slot = self.next_local_offset
    self.next_local_offset += 4
    match idx {
      0 => self.temp_slot0 = new_slot
      1 => self.temp_slot1 = new_slot
      2 => self.temp_slot2 = new_slot
      _ => self.temp_slot3 = new_slot
    }
    new_slot
  } else {
    slot
  }
}

///|
/// 8 字节临时槽：double/long long 位模式读写必须独占 8 字节空间，
/// 复用 4 字节槽会踩踏相邻槽/局部变量（曾致 9 个 baseline 链表用例回归）。
fn BytecodeGen::get_temp_slot_64(self : BytecodeGen) -> Int {
  if self.temp_slot_64 < 0 {
    self.temp_slot_64 = self.next_local_offset
    // 保持后续 4 字节槽 8 字节对齐，避免非对齐 64 位访问
    self.next_local_offset += 8
  }
  self.temp_slot_64
}

///|
/// 初始化路径专用基址槽（U1#3 止血）：数组/结构体初始化的写入基址
/// 独占此槽。惰性分配，enter_function 时重置（与 temp_slot0~3 同生命周期）。
fn BytecodeGen::get_init_base_slot(self : BytecodeGen) -> Int {
  if self.init_base_slot < 0 {
    self.init_base_slot = self.next_local_offset
    self.next_local_offset += 4
  }
  self.init_base_slot
}

///|
/// T-P0-6：按当前赋值嵌套深度分配"赋值目标地址"槽。同层顺序复用，
/// 更深一层拿不同槽位（`a[0] += (b[0] = 5)` 内外层地址不互相覆盖）。
fn BytecodeGen::get_assign_addr_slot(self : BytecodeGen) -> Int {
  let depth = if self.assign_nest_depth > 1 {
    self.assign_nest_depth
  } else {
    1
  }
  while self.assign_addr_slots.length() < depth {
    let slot = self.next_local_offset
    self.next_local_offset += 4
    self.assign_addr_slots.push(slot)
  }
  self.assign_addr_slots[depth - 1]
}

///|
/// f64 常量池：位模式去重（Rust `to_bits()` 比较；F9——f64 池化语义）。
fn BytecodeGen::push_f64_constant(self : BytecodeGen, val : Double) -> Int {
  let val_bits = val.reinterpret_as_uint64()
  for i, v in self.f64_constants {
    if v.reinterpret_as_uint64() == val_bits {
      return i
    }
  }
  let idx = self.f64_constants.length()
  self.f64_constants.push(val)
  idx
}

///|
/// i64 常量池：值比较去重（与 f64 的位模式口径不同——Rust 照搬）。
fn BytecodeGen::push_i64_constant(self : BytecodeGen, val : Int64) -> Int {
  for i, v in self.i64_constants {
    if v == val {
      return i
    }
  }
  let idx = self.i64_constants.length()
  self.i64_constants.push(val)
  idx
}

///|
/// 类型尺寸（`@ast.compute_type_size` 单源——S4 已迁；class_sizes 在
/// C only 下恒空表）。
fn BytecodeGen::type_size(self : BytecodeGen, ty : @ast.Type) -> Int {
  @ast.compute_type_size(ty, self.struct_defs, self.union_defs, {})
}

///|
/// 数组元素尺寸（Rust lib.rs:842-865 照搬）。
fn BytecodeGen::elem_type_size(self : BytecodeGen, arr_type : @ast.Type) -> Int {
  let (elem_kind, elem_type) = match arr_type {
    Array(element, _, _, _, _, _) => (element.kind(), element)
    _ => (base_kind(arr_type), arr_type)
  }
  match elem_kind {
    TK_Char => 1
    TK_Int | TK_Pointer | TK_Float => 4
    TK_Double | TK_LongLong => 8
    TK_Struct =>
      match self.struct_defs.get(elem_type.name()) {
        Some(fields) => {
          let mut total = 0
          for field in fields {
            total += self.type_size(field.ty)
          }
          total
        }
        None => 4
      }
    // class 布局表已随砍 C++ 裁定退役（F-2）——此臂理论不可达（C 输入
    // 下 typeck 不产 Class 类型），可达即上游分叉，fail loud 优于静默
    // 4 兜底（禁静默 default 纪律）
    TK_Class => {
      self.report_error(
        "内部错误：class 类型 '\{elem_type.name()}' 进入 C only codegen（砍 C++ 裁定后不可达）",
        default_loc(),
      )
      4
    }
    TK_Union =>
      match self.union_defs.get(elem_type.name()) {
        Some(fields) => {
          let mut max = 0
          for field in fields {
            let sz = self.type_size(field.ty)
            if sz > max {
              max = sz
            }
          }
          if max == 0 {
            4
          } else {
            max
          }
        }
        None => 4
      }
    _ => 4
  }
}

///|
/// 指针步长（Rust lib.rs:828-840 照搬）。
fn BytecodeGen::ptr_step_size(self : BytecodeGen, ty : @ast.Type) -> Int {
  match ty.kind() {
    TK_Pointer =>
      match ty {
        Pointer(pointee, _) => self.type_size(pointee)
        _ => 4
      }
    TK_Array => compute_stride(ty, self.elem_type_size(ty))
    _ => 1
  }
}

///|
/// `base_kind`：解引用到底层（Rust `vitro_runtime::type_utils::base_kind`
/// 照搬——对 Array/Pointer 递归剥层直到非派生类型）。
fn base_kind(ty : @ast.Type) -> @ast.TypeKind {
  match ty {
    Array(element, _, _, _, _, _) => base_kind(element)
    Pointer(pointee, _) => base_kind(pointee)
    _ => ty.kind()
  }
}
