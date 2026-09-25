///|
/// 局部变量声明语句生成（S5 扩展批·VarDecl——baseline 363 归因首要阻塞
/// 245 例）——Rust `stmt/var_decl.rs` 全量照搬 + C only 裁剪：
/// - lambda 闭包槽 4 字节特判（Issue B2）不迁移——`is_lambda_closure_type`
///   是 class 前缀启发式（砍 C++ 后零活跃），恒走 `type_size`；
/// - `try_gen_cpp_class_init` / `try_gen_cpp_class_default_ctor` /
///   `gen_cpp_reference_init` 不迁移——class 判定并入 struct 同路径 /
///   Reference C 输入零出现（typeck 不产）；
/// - struct 拷贝初始化的 dtor 分支不迁移（C only 无析构）。
/// 指令序逐条对齐（A 级 code 段 diff 前提）。
fn BytecodeGen::gen_var_decl(
  self : BytecodeGen,
  var_type : @ast.Type,
  name : String,
  init : @ast.Expr?,
  extra_vars : Array[@ast.VarDeclExtra],
  is_static : Bool,
  loc : @source.SourceLoc,
) -> Unit {
  self.emit_single_var(var_type, name, init, loc, is_static)
  for extra in extra_vars {
    self.emit_single_var(extra.var_type, extra.name, extra.init, loc, is_static)
  }
}

///|
fn BytecodeGen::emit_single_var(
  self : BytecodeGen,
  vty : @ast.Type,
  n : String,
  init : @ast.Expr?,
  loc : @source.SourceLoc,
  is_static : Bool,
) -> Unit {
  if is_static {
    self.emit_static_var(vty, n, init, loc)
    return
  }
  let sz = self.type_size(vty)
  let aligned_sz = if sz % 4 == 0 { sz } else { sz + 4 - sz % 4 }
  let local_offset = self.next_local_offset
  self.next_local_offset += aligned_sz
  self.record_scope_var(n)
  // V-P1-6：登记栈上数组缓冲区，供 strcpy/strcat/scanf("%s") 做容量校验
  // （参数区数组已退化为指针，不登记；VLA 运行时分配，不登记）
  if vty.is_array() &&
    !vty.is_vla() &&
    local_offset >= self.current_func_arg_bytes {
    match self.func_table.get(self.current_func) {
      Some(meta) =>
        meta.local_buffers.push({ offset: local_offset, size: sz, name: n, })
      None => ()
    }
  }
  self.local_indices.set(n, local_offset)
  self.local_types.set(n, vty)
  self.sym_index.set(n, self.symbols.length())
  self.symbols.push({
    name: n,
    addr: local_offset.reinterpret_as_uint(),
    is_local: true,
    ty: vty,
    scope_depth: 1,
    func_name: self.current_func,
    decl_line: loc.line,
  })
  if vty.is_vla() {
    self.emit_vla_alloc(vty, local_offset, loc)
    match init {
      Some(InitList(_, _, _)) =>
        self.report_error("变长数组(VLA)不支持初始化列表", loc)
      _ => ()
    }
  } else {
    match init {
      Some(e) => self.emit_local_init(vty, e, local_offset, loc)
      // C++ 栈对象默认构造不迁移（class C only 零出现）
      None => self.emit_zero_init(vty, local_offset, loc)
    }
  }
}

///|
fn BytecodeGen::emit_static_var(
  self : BytecodeGen,
  vty : @ast.Type,
  n : String,
  init : @ast.Expr?,
  loc : @source.SourceLoc,
) -> Unit {
  if vty.is_vla() {
    self.report_error("static 变量不支持变长数组(VLA)", loc)
    return
  }
  if self.static_local_indices.contains(n) {
    return
  }
  let sz = self.type_size(vty)
  let aligned_sz = if sz % 4 == 0 { sz } else { sz + 4 - sz % 4 }
  let global_offset = match
    self.bump_global_offset(aligned_sz, "静态局部变量 '\{n}'", loc) {
    Some(o) => o
    None => return
  }
  self.static_local_indices.set(n, global_offset)
  self.static_local_types.set(n, vty)
  self.sym_index.set(n, self.symbols.length())
  self.symbols.push({
    name: n,
    addr: u32_of(@bytecode.GLOBAL_START.reinterpret_as_int() + global_offset),
    is_local: false,
    ty: vty,
    scope_depth: 0,
    func_name: self.current_func,
    decl_line: loc.line,
  })
  match init {
    Some(e) => self.emit_static_init(vty, e, global_offset, loc)
    None => ()
  }
}

///|
fn BytecodeGen::emit_static_init(
  self : BytecodeGen,
  vty : @ast.Type,
  init : @ast.Expr,
  global_offset : Int,
  loc : @source.SourceLoc,
) -> Unit {
  match init {
    InitList(elements, _, _) => {
      let has_designators = elements.exists(e => e.designators.length() > 0)
      if has_designators {
        self.report_error(
          "静态局部变量的 designated initializer 暂不支持", loc,
        )
        return
      }
      let is_char_array = match vty {
        Array(element, _, _, _, _, _) => element.kind() is TK_Char
        _ => false
      }
      if is_char_array {
        let values = flatten_init_list(elements, self.errors)
        for i in 0..<self.type_size(vty) {
          let v = if i < values.length() { values[i] } else { 0 }
          self.globals_init_32.push(
            (global_offset.reinterpret_as_uint() + i.reinterpret_as_uint(), v),
          )
        }
      } else {
        self.emit_static_scalar_array_init(vty, elements, global_offset, loc)
      }
    }
    StringLiteral(value, _, _) => {
      // P2：与全局路径同构——char 数组字节直写；指针目标立即取址分配
      // （本函数在 Pass 3 执行，pending_string_inits 已回填，须直接 bump）
      let is_char_array = match vty {
        Array(element, _, _, _, _, _) => element.kind() is TK_Char
        _ => false
      }
      if is_char_array {
        let bytes = @bytecode.cstring_bytes(value)
        for i in 0..<self.type_size(vty) {
          let byte = if i < bytes.length() { bytes[i].to_int() } else { 0 }
          self.globals_init_32.push(
            (
              global_offset.reinterpret_as_uint() + i.reinterpret_as_uint(),
              byte,
            ),
          )
        }
      } else {
        let aligned = (
            (@bytecode.cstring_len(value) + 1).reinterpret_as_uint() + 3
          ) &
          @bytecode.ALIGN4_MASK
        let str_offset = match
          self.bump_global_offset(
            aligned.reinterpret_as_int(),
            "静态初始化字符串",
            loc,
          ) {
          Some(o) => o
          None => return
        }
        let str_addr = @bytecode.GLOBAL_START + str_offset.reinterpret_as_uint()
        self.string_data.push((str_addr, value))
        self.globals_init_32.push(
          (global_offset.reinterpret_as_uint(), str_addr.reinterpret_as_int()),
        )
      }
    }
    Literal(_, _, _) | LongLiteral(_, _, _) | FloatLiteral(_, _, _) => {
      // T-P0-1：static 局部标量初始化按目标类型编码位模式（与全局路径同构）
      let _ = self.push_literal_init(
        global_offset.reinterpret_as_uint(),
        init,
        vty,
      )
    }
    Unary(@ast.UnaryOp::Neg, operand, _, _) =>
      // 负数字面量（如 static double d = -2;）与全局路径同构处理。
      // （guard 须与模式同行——手册 #23；条件改 arm 内 if）
      if operand is Literal(_, _, _) ||
        operand is LongLiteral(_, _, _) ||
        operand is FloatLiteral(_, _, _) {
        let _ = self.push_literal_init(
          global_offset.reinterpret_as_uint(),
          init,
          vty,
        )
      }
    Identifier(id_name, _, _) =>
      match self.func_index.get(id_name) {
        Some(idx) =>
          self.globals_init_32.push((global_offset.reinterpret_as_uint(), idx))
        None => ()
      }
    _ => {
      self.gen_expr(init)
      if vty.kind() is TK_Double {
        self.emit(@opcode.OpCode::StoreGlobalD, global_offset, loc)
      } else if vty.kind() is TK_LongLong {
        self.emit(@opcode.OpCode::StoreGlobalQ, global_offset, loc)
      } else {
        self.emit(@opcode.OpCode::StoreGlobal, global_offset, loc)
      }
    }
  }
}

///|
fn BytecodeGen::emit_static_scalar_array_init(
  self : BytecodeGen,
  vty : @ast.Type,
  elements : Array[@ast.InitElement],
  global_offset : Int,
  _loc : @source.SourceLoc,
) -> Unit {
  let elem_size = self.elem_type_size(vty)
  let count = vty.total_elements()
  if elem_size == 8 {
    // T-P0-2 同构修复：按元素类型编码 8 字节位模式
    let elem_ty = vty.base_element_type()
    for i in 0..<count {
      let addr = global_offset.reinterpret_as_uint() +
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
    for i, elem in elements {
      let addr = global_offset.reinterpret_as_uint() +
        i.reinterpret_as_uint() * elem_size.reinterpret_as_uint()
      match elem.value {
        StringLiteral(value, _, _) => {
          let aligned = (
              (@bytecode.cstring_len(value) + 1).reinterpret_as_uint() + 3
            ) &
            @bytecode.ALIGN4_MASK
          let str_offset = match
            self.bump_global_offset(
              aligned.reinterpret_as_int(),
              "静态初始化字符串",
              _loc,
            ) {
            Some(o) => o
            None => continue
          }
          let str_addr = @bytecode.GLOBAL_START +
            str_offset.reinterpret_as_uint()
          self.string_data.push((str_addr, value))
          self.globals_init_32.push((addr, str_addr.reinterpret_as_int()))
        }
        FloatLiteral(value, _, _) =>
          self.globals_init_32.push(
            (addr, f32_bits_i32(Float::from_double(value))),
          )
        LongLiteral(value, _, _) =>
          self.globals_init_32.push((addr, value.to_int()))
        Literal(value, _, _) => self.globals_init_32.push((addr, value))
        Unary(@ast.UnaryOp::Neg, operand, _, _) =>
          match operand {
            Literal(value, _, _) => self.globals_init_32.push((addr, -value))
            _ => self.globals_init_32.push((addr, 0))
          }
        _ => {
          let sub = flatten_init_list([elem], self.errors)
          let val = if sub.length() > 0 { sub[0] } else { 0 }
          self.globals_init_32.push((addr, val))
        }
      }
    }
    for i in elements.length()..<count {
      let addr = global_offset.reinterpret_as_uint() +
        i.reinterpret_as_uint() * elem_size.reinterpret_as_uint()
      self.globals_init_32.push((addr, 0))
    }
  }
}

///|
fn BytecodeGen::emit_vla_alloc(
  self : BytecodeGen,
  vty : @ast.Type,
  local_offset : Int,
  loc : @source.SourceLoc,
) -> Unit {
  match vty {
    // Array(element, array_size, dims, is_const, is_vla, vla_dims)
    Array(_, _, dims, _, _, vla_dims) => {
      let mut vla_idx = 0
      let elem_size = self.elem_type_size(vty)
      if dims.length() == 0 {
        self.emit(@opcode.OpCode::PushConst, 0, loc)
      } else {
        for dim in dims {
          if dim > 0 {
            self.emit(@opcode.OpCode::PushConst, dim, loc)
          } else {
            match vla_dims.get(vla_idx) {
              Some(dim_expr) => {
                self.gen_expr(dim_expr)
                vla_idx += 1
              }
              None => self.emit(@opcode.OpCode::PushConst, 0, loc)
            }
          }
        }
        for _j in 1..<dims.length() {
          self.emit(@opcode.OpCode::Mul, 0, loc)
        }
        if elem_size > 1 {
          self.emit(@opcode.OpCode::PushConst, elem_size, loc)
          self.emit(@opcode.OpCode::Mul, 0, loc)
        }
      }
      self.emit(@opcode.OpCode::StackAlloc, 0, loc)
      self.emit(@opcode.OpCode::StoreLocal, local_offset, loc)
    }
    _ => ()
  }
}

///|
fn BytecodeGen::emit_local_init(
  self : BytecodeGen,
  vty : @ast.Type,
  init : @ast.Expr,
  local_offset : Int,
  loc : @source.SourceLoc,
) -> Unit {
  // class 并入 struct 同路径（C only 下 typeck 不产 class）；reference
  // 分支不迁移（C 输入零出现）
  if vty.is_array() && init is InitList(_, _, _) {
    self.emit_local_array_init(vty, init, local_offset, loc)
  } else if vty.is_array() && init is CompoundLiteral(_, inner, _, _) {
    self.emit_local_array_init(vty, inner, local_offset, loc)
  } else if vty.kind() is TK_Struct && init is InitList(_, _, _) {
    self.emit_local_struct_init(vty, init, local_offset, loc)
  } else if vty.kind() is TK_Struct && init is CompoundLiteral(_, _, _, _) {
    self.gen_struct_copy_to_local(local_offset, init, loc)
  } else if vty.kind() is TK_Struct {
    self.gen_struct_copy_to_local(local_offset, init, loc)
  } else if vty.is_array() && init is StringLiteral(_, _, _) {
    self.emit_local_string_array_init(vty, init, local_offset, loc)
  } else if init is CompoundLiteral(target_type, _, _, _) {
    // 标量复合字面量：gen_expr 留下临时对象地址，加载值后存入变量槽位
    let scalar_kind = target_type.kind()
    self.gen_expr(init)
    match scalar_kind {
      TK_Double => {
        self.emit(@opcode.OpCode::LoadMemD, 0, loc)
        self.emit(@opcode.OpCode::StoreLocalD, local_offset, loc)
      }
      TK_LongLong => {
        self.emit(@opcode.OpCode::LoadMemQ, 0, loc)
        self.emit(@opcode.OpCode::StoreLocalQ, local_offset, loc)
      }
      _ => {
        self.emit(@opcode.OpCode::LoadMem, 0, loc)
        self.emit(@opcode.OpCode::StoreLocal, local_offset, loc)
      }
    }
  } else {
    self.gen_expr(init)
    self.emit_scalar_cast_store(vty, init, local_offset, loc)
  }
}

///|
fn BytecodeGen::emit_scalar_cast_store(
  self : BytecodeGen,
  vty : @ast.Type,
  init : @ast.Expr,
  local_offset : Int,
  loc : @source.SourceLoc,
) -> Unit {
  let ik = init.ty().kind()
  if vty.kind() is TK_Float &&
    !(ik is TK_Float) &&
    !(ik is TK_Double) &&
    !(ik is TK_LongLong) {
    self.emit(@opcode.OpCode::CastI2F, 0, loc)
  }
  if vty.kind() is TK_Double &&
    !(ik is TK_Float) &&
    !(ik is TK_Double) &&
    !(ik is TK_LongLong) {
    self.emit(@opcode.OpCode::CastI2D, 0, loc)
  }
  if vty.kind() is TK_LongLong &&
    !(ik is TK_LongLong) &&
    !(ik is TK_Double) &&
    !(ik is TK_Float) {
    self.emit(@opcode.OpCode::CastI2Q, 0, loc)
  }
  if vty.kind() is TK_Double {
    self.emit(@opcode.OpCode::StoreLocalD, local_offset, loc)
  } else if vty.kind() is TK_LongLong {
    self.emit(@opcode.OpCode::StoreLocalQ, local_offset, loc)
  } else {
    self.emit(@opcode.OpCode::StoreLocal, local_offset, loc)
  }
}

///|
fn BytecodeGen::emit_local_string_array_init(
  self : BytecodeGen,
  vty : @ast.Type,
  init : @ast.Expr,
  local_offset : Int,
  loc : @source.SourceLoc,
) -> Unit {
  match init {
    StringLiteral(value, _, _) => {
      let base_temp = self.get_init_base_slot()
      self.emit(@opcode.OpCode::GetFrameBase, 0, loc)
      self.emit(@opcode.OpCode::PushConst, local_offset, loc)
      self.emit(@opcode.OpCode::Add, 0, loc)
      self.emit(@opcode.OpCode::StoreLocal, base_temp, loc)
      let byte_count = vty.array_size()
      let bytes = @bytecode.cstring_bytes(value)
      for i in 0..<byte_count {
        self.emit(@opcode.OpCode::LoadLocal, base_temp, loc)
        self.emit(@opcode.OpCode::PushConst, i, loc)
        self.emit(@opcode.OpCode::Add, 0, loc)
        let byte = if i < bytes.length() { bytes[i].to_int() } else { 0 }
        self.emit(@opcode.OpCode::PushConst, byte, loc)
        self.emit(@opcode.OpCode::StoreMemByte, 0, loc)
      }
    }
    _ => ()
  }
}

///|
fn BytecodeGen::emit_local_array_init(
  self : BytecodeGen,
  vty : @ast.Type,
  init : @ast.Expr,
  local_offset : Int,
  loc : @source.SourceLoc,
) -> Unit {
  match init {
    InitList(elements, _, _) => {
      let base_temp = self.get_init_base_slot()
      self.emit(@opcode.OpCode::GetFrameBase, 0, loc)
      self.emit(@opcode.OpCode::PushConst, local_offset, loc)
      self.emit(@opcode.OpCode::Add, 0, loc)
      self.emit(@opcode.OpCode::StoreLocal, base_temp, loc)
      let is_char_array = match vty {
        Array(element, _, _, _, _, _) => element.kind() is TK_Char
        _ => false
      }
      if is_char_array {
        let values = flatten_init_list(elements, self.errors)
        let byte_count = vty.array_size()
        for i in 0..<byte_count {
          self.emit(@opcode.OpCode::LoadLocal, base_temp, loc)
          self.emit(@opcode.OpCode::PushConst, i, loc)
          self.emit(@opcode.OpCode::Add, 0, loc)
          let byte = if i < values.length() { values[i] } else { 0 }
          self.emit(@opcode.OpCode::PushConst, byte, loc)
          self.emit(@opcode.OpCode::StoreMemByte, 0, loc)
        }
        return
      }
      let inner_ty = vty.subscript_type()
      let has_nested_init = elements.exists(e => e.value is InitList(_, _, _))
      if has_nested_init &&
        (inner_ty.kind() is TK_Struct || inner_ty.is_array()) {
        let elem_stride = self.type_size(inner_ty)
        for i, elem in elements {
          let addr_offset = i * elem_stride
          self.gen_nested_init(
            base_temp,
            addr_offset,
            inner_ty,
            elem.value,
            loc,
          )
        }
        let expected_count = if vty.dims().length() > 0 && vty.dims()[0] > 0 {
          vty.dims()[0]
        } else {
          elements.length()
        }
        for k in elements.length()..<expected_count {
          let idx = elements.length() + k
          let addr_offset = idx * elem_stride
          self.emit(@opcode.OpCode::LoadLocal, base_temp, loc)
          if addr_offset > 0 {
            self.emit(@opcode.OpCode::PushConst, addr_offset, loc)
            self.emit(@opcode.OpCode::Add, 0, loc)
          }
          self.emit(@opcode.OpCode::PushConst, 0, loc)
          if inner_ty.kind() is TK_Double {
            self.emit(@opcode.OpCode::StoreMemD, 0, loc)
          } else if inner_ty.kind() is TK_LongLong {
            self.emit(@opcode.OpCode::StoreMemQ, 0, loc)
          } else {
            self.emit(@opcode.OpCode::StoreMem, 0, loc)
          }
        }
      } else {
        self.emit_flat_array_init(vty, elements, base_temp, loc)
      }
    }
    _ => ()
  }
}

///|
fn BytecodeGen::emit_flat_array_init(
  self : BytecodeGen,
  vty : @ast.Type,
  elements : Array[@ast.InitElement],
  base_temp : Int,
  loc : @source.SourceLoc,
) -> Unit {
  let elem_size = self.elem_type_size(vty)
  let count = vty.total_elements()
  let has_designators = elements.exists(e => e.designators.length() > 0)
  if has_designators {
    // Zero-fill entire array before designated init
    self.emit(@opcode.OpCode::PushConst, count * elem_size, loc)
    self.emit(@opcode.OpCode::PushConst, 0, loc)
    self.emit(@opcode.OpCode::LoadLocal, base_temp, loc)
    self.emit(@opcode.OpCode::Memset, 0, loc)
    for elem in elements {
      if elem.designators.length() == 0 {
        continue
      }
      let idx = match elem.designators[0] {
        Index(idx_expr) =>
          match idx_expr {
            Literal(value, _, _) => value
            _ => {
              self.report_error(
                "数组 designated initializer 的索引必须是编译期常量",
                loc,
              )
              continue
            }
          }
        Field(_) => {
          self.report_error(
            "数组初始化只能使用 [index] 形式的 designator", loc,
          )
          continue
        }
      }
      if idx < 0 || idx >= count {
        self.report_error(
          "数组 designated initializer 索引超出范围", loc,
        )
        continue
      }
      let addr_offset = idx * elem_size
      self.emit(@opcode.OpCode::LoadLocal, base_temp, loc)
      if addr_offset > 0 {
        self.emit(@opcode.OpCode::PushConst, addr_offset, loc)
        self.emit(@opcode.OpCode::Add, 0, loc)
      }
      self.gen_expr(elem.value)
      if elem_size == 8 {
        self.emit(@opcode.OpCode::StoreMemD, 0, loc)
      } else {
        self.emit(@opcode.OpCode::StoreMem, 0, loc)
      }
    }
  } else {
    // U1#2：flatten 调用保留——副作用仍上报 designated 上下文错误——但
    // **不再用它的值**：全部走 gen_expr（`int a[2]={f(),3}` 的 a[0] 此前
    // 落 flatten 值 unwrap_or(0) 静默变 0）
    let _ = flatten_init_list(elements, self.errors)
    for i in 0..<count {
      let addr_offset = i * elem_size
      self.emit(@opcode.OpCode::LoadLocal, base_temp, loc)
      if addr_offset > 0 {
        self.emit(@opcode.OpCode::PushConst, addr_offset, loc)
        self.emit(@opcode.OpCode::Add, 0, loc)
      }
      match elements.get(i) {
        Some(elem) => {
          self.gen_expr(elem.value)
          if elem_size == 8 {
            self.emit(@opcode.OpCode::StoreMemD, 0, loc)
          } else {
            self.emit(@opcode.OpCode::StoreMem, 0, loc)
          }
        }
        None => self.emit_zero_elem(elem_size, loc)
      }
    }
  }
}

///|
fn BytecodeGen::emit_zero_elem(
  self : BytecodeGen,
  elem_size : Int,
  loc : @source.SourceLoc,
) -> Unit {
  if elem_size == 8 {
    self.emit(@opcode.OpCode::PushConst, 0, loc)
    self.emit(@opcode.OpCode::CastI2D, 0, loc)
    self.emit(@opcode.OpCode::StoreMemD, 0, loc)
  } else {
    self.emit(@opcode.OpCode::PushConst, 0, loc)
    self.emit(@opcode.OpCode::StoreMem, 0, loc)
  }
}

///|
fn BytecodeGen::emit_local_struct_init(
  self : BytecodeGen,
  vty : @ast.Type,
  init : @ast.Expr,
  local_offset : Int,
  loc : @source.SourceLoc,
) -> Unit {
  match init {
    InitList(elements, _, _) => {
      let base_temp = self.get_init_base_slot()
      self.emit(@opcode.OpCode::GetFrameBase, 0, loc)
      self.emit(@opcode.OpCode::PushConst, local_offset, loc)
      self.emit(@opcode.OpCode::Add, 0, loc)
      self.emit(@opcode.OpCode::StoreLocal, base_temp, loc)
      let fields = match self.struct_defs.get(vty.name()) {
        Some(f) => f
        None => []
      }
      let has_designators = elements.exists(e => e.designators.length() > 0)
      if has_designators {
        // Zero-fill entire struct before designated init
        self.emit(@opcode.OpCode::PushConst, self.type_size(vty), loc)
        self.emit(@opcode.OpCode::PushConst, 0, loc)
        self.emit(@opcode.OpCode::LoadLocal, base_temp, loc)
        self.emit(@opcode.OpCode::Memset, 0, loc)
        for elem in elements {
          if elem.designators.length() == 0 {
            continue
          }
          let field_idx = match elem.designators[0] {
            Field(fname) => {
              let mut found = -1
              for j, f in fields {
                if f.name == fname {
                  found = j
                  break
                }
              }
              if found >= 0 && found < fields.length() {
                found
              } else {
                continue
              }
            }
            _ => {
              self.report_error(
                "结构体初始化只能使用 .field 形式的 designator", loc,
              )
              continue
            }
          }
          let mut offset = 0
          for j in 0..<field_idx {
            offset += self.type_size(fields[j].ty)
          }
          self.emit_field_init(
            base_temp,
            offset,
            fields[field_idx].ty,
            elem.value,
            loc,
          )
        }
      } else {
        for i, elem in elements {
          if i >= fields.length() {
            break
          }
          let mut offset = 0
          for j in 0..<i {
            offset += self.type_size(fields[j].ty)
          }
          self.emit_field_init(base_temp, offset, fields[i].ty, elem.value, loc)
        }
      }
    }
    _ => ()
  }
}

///|
fn BytecodeGen::emit_field_init(
  self : BytecodeGen,
  base_temp : Int,
  offset : Int,
  field_ty : @ast.Type,
  value : @ast.Expr,
  loc : @source.SourceLoc,
) -> Unit {
  if value is InitList(_, _, _) &&
    (field_ty.kind() is TK_Struct || field_ty.is_array()) {
    self.gen_nested_init(base_temp, offset, field_ty, value, loc)
  } else {
    self.emit(@opcode.OpCode::LoadLocal, base_temp, loc)
    if offset > 0 {
      self.emit(@opcode.OpCode::PushConst, offset, loc)
      self.emit(@opcode.OpCode::Add, 0, loc)
    }
    self.gen_expr(value)
    // T-P0-4：char 字段按 1 字节写，避免 4 字节 StoreMem 破坏相邻字段
    if field_ty.kind() is TK_Char {
      self.emit(@opcode.OpCode::StoreMemByte, 0, loc)
    } else if field_ty.kind() is TK_Double {
      self.emit(@opcode.OpCode::StoreMemD, 0, loc)
    } else if field_ty.kind() is TK_LongLong {
      self.emit(@opcode.OpCode::StoreMemQ, 0, loc)
    } else {
      self.emit(@opcode.OpCode::StoreMem, 0, loc)
    }
  }
}

///|
fn BytecodeGen::emit_zero_init(
  self : BytecodeGen,
  vty : @ast.Type,
  local_offset : Int,
  loc : @source.SourceLoc,
) -> Unit {
  let sz = self.type_size(vty)
  if sz == 0 {
    // 零尺寸类型无操作
    ()
  } else if sz == 8 && vty.kind() is TK_Double {
    self.emit(@opcode.OpCode::PushConst, 0, loc)
    self.emit(@opcode.OpCode::CastI2D, 0, loc)
    self.emit(@opcode.OpCode::StoreLocalD, local_offset, loc)
  } else if sz <= 4 {
    self.emit(@opcode.OpCode::PushConst, 0, loc)
    self.emit(@opcode.OpCode::StoreLocal, local_offset, loc)
  } else {
    // U1#5：Memset 单指令（旧逐字节 StoreMemByte 5 指令/字节，循环体指令
    // 数轻易超过 JIT MAX_TRACE_LEN=256 → 半截 trace 重放栈溢出）；返回值
    // Pop 平衡
    self.emit(@opcode.OpCode::PushConst, sz, loc)
    self.emit(@opcode.OpCode::PushConst, 0, loc)
    self.emit(@opcode.OpCode::GetFrameBase, 0, loc)
    self.emit(@opcode.OpCode::PushConst, local_offset, loc)
    self.emit(@opcode.OpCode::Add, 0, loc)
    self.emit(@opcode.OpCode::Memset, 0, loc)
    self.emit(@opcode.OpCode::Pop, 0, loc)
  }
}

///|
/// i32 → u32 位重解释（Rust `as u32`）。
fn u32_of(v : Int) -> UInt {
  v.reinterpret_as_uint()
}
