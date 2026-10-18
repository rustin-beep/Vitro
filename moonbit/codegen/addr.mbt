///|
/// 地址生成与结构体拷贝（S5 扩展批·VarDecl 依赖）——Rust `expr.rs` 的
/// `gen_addr` / `gen_nested_init` / `gen_struct_copy_common` /
/// `gen_struct_copy_to_local` 的 C only 子集照搬：
/// - gen_addr 最小集 = Identifier + Deref + 复合字面量/struct 返回调用
///   透传（VarDecl 的 struct 拷贝初始化右端所需的全部形态）；Index/
///   Member 地址生成随二元/赋值批接线（report_error fail loud）；
/// - reference 自动解引用 / std::move / lambda / MemberCall 分支不迁移
///   （C++ 专有，C 输入零出现）；
/// - gen_struct_copy_common 的 Rust 闭包 dst_emit 展开为 to_local 单
///   形态（指令序逐条等价；通用双形态版随赋值批的 gen_struct_copy 接线）。

///|
fn BytecodeGen::gen_addr(
  self : BytecodeGen,
  expr : @ast.Expr,
  loc : @source.SourceLoc,
) -> Unit {
  match expr {
    Identifier(name, _, _) =>
      match self.local_indices.get(name) {
        Some(offset) => {
          self.emit(@opcode.OpCode::GetFrameBase, 0, loc)
          self.emit(@opcode.OpCode::PushConst, offset, loc)
          self.emit(@opcode.OpCode::Add, 0, loc)
        }
        None =>
          match self.global_indices.get(name) {
            Some(offset) =>
              self.emit(
                @opcode.OpCode::PushConst,
                @bytecode.GLOBAL_START.reinterpret_as_int() + offset,
                loc,
              )
            None =>
              match self.static_local_indices.get(name) {
                Some(offset) =>
                  // static local 地址通路（DIFF-CODEGEN-STATIC-ADDR-01 销案，
                  // 批四 2026-10-07——Rust gen_addr 同位无此分支照搬；static
                  // 落全局数据段，地址形态同 global）
                  self.emit(
                    @opcode.OpCode::PushConst,
                    @bytecode.GLOBAL_START.reinterpret_as_int() + offset,
                    loc,
                  )
                None => self.report_error("未声明的变量", loc)
              }
          }
      }
    Unary(@ast.UnaryOp::Deref, operand, _, _) => self.gen_expr(operand)
    Index(array, index, _, ty) => self.gen_index(array, index, ty, loc, true)
    Member(object, member_name, _, _, _) =>
      self.gen_member_addr(object, member_name, loc)
    // 函数按值返回结构体 / 复合字面量：gen_expr 已在栈顶留下地址
    CallPtr(_, _, _, ty) =>
      if ty.kind() is TK_Struct {
        self.gen_expr(expr)
      } else {
        self.report_error("不支持的地址生成", loc)
      }
    CompoundLiteral(_, _, _, _) => self.gen_expr(expr)
    _ => self.report_error("不支持的地址生成", loc)
  }
}

///|
/// 嵌套初始化递归（Rust expr.rs:177 照搬；class 分支剔除——struct 同构）。
fn BytecodeGen::gen_nested_init(
  self : BytecodeGen,
  base_temp : Int32,
  offset : Int32,
  target_ty : @ast.Type,
  init : @ast.Expr,
  loc : @source.SourceLoc,
) -> Unit {
  match init {
    // #137 缺陷 1（2026-10-17，C11 §6.7.9p14）：char[N] 子数组层的
    // 字符串字面量字节直写（含尾 NUL 与零填）——旧落 _ 臂 gen_expr
    // 发字符串池址再 StoreMem（把指针当行数据）。offset 基址 + i 字节
    // 推进与全局层 flatten_global_init 的 char[] 臂同口径
    StringLiteral(value, _, _) =>
      // guard 不能换行（MoonBit match guard 同行约束）——条件收进臂体
      if target_ty.is_array() && target_ty.base_element_type().kind() is TK_Char {
        let byte_count = target_ty.array_size()
        let bytes = @bytecode.cstring_bytes(value)
        for i in 0..<byte_count {
          self.emit(@opcode.OpCode::LoadLocal, base_temp, loc)
          let addr = offset + i
          if addr != 0 {
            self.emit(@opcode.OpCode::PushConst, addr, loc)
            self.emit(@opcode.OpCode::Add, 0, loc)
          }
          let byte = if i < bytes.length() { bytes[i].to_int() } else { 0 }
          self.emit(@opcode.OpCode::PushConst, byte, loc)
          self.emit(@opcode.OpCode::StoreMemByte, 0, loc)
        }
      } else {
        // 非 char[] 目标的字符串（罕见嵌套层）：维持 _ 臂指针语义
        self.emit(@opcode.OpCode::LoadLocal, base_temp, loc)
        if offset != 0 {
          self.emit(@opcode.OpCode::PushConst, offset, loc)
          self.emit(@opcode.OpCode::Add, 0, loc)
        }
        self.gen_expr(init)
        self.emit(@opcode.OpCode::StoreMem, 0, loc)
      }
    InitList(elements, _, _) =>
      if target_ty.kind() is TK_Struct {
        let fields = match self.struct_defs.get(target_ty.name()) {
          Some(f) => f
          None => []
        }
        for i, elem in elements {
          if i >= fields.length() {
            break
          }
          let field_offset = self.struct_fields_prefix_offset(fields, i)
          self.gen_nested_init(
            base_temp,
            offset + field_offset,
            fields[i].ty,
            elem.value,
            loc,
          )
        }
      } else if target_ty.is_array() {
        let elem_size = self.elem_type_size(target_ty)
        let inner_ty = target_ty.subscript_type()
        for i, elem in elements {
          let elem_offset = offset + i * elem_size
          self.gen_nested_init(
            base_temp,
            elem_offset,
            inner_ty,
            elem.value,
            loc,
          )
        }
      } else if elements.length() > 0 {
        self.gen_nested_init(
          base_temp,
          offset,
          target_ty,
          elements[0].value,
          loc,
        )
      }
    _ => {
      // #143 连坐：嵌套层（数组元素/深层字段）的 struct 变量值——与
      // emit_field_init 同款整体拷贝（旧形态落本兜底臂：gen_expr 压首
      // 字段 StoreMem 4 字节，`pts[1] = my_pt` 只拷 (7,0)）
      if target_ty.kind() is TK_Struct &&
        init.ty().kind() is TK_Struct &&
        !(init is InitList(_, _, _)) {
        self.emit_struct_value_copy(base_temp, offset, init, target_ty, loc)
        return
      }
      self.emit(@opcode.OpCode::LoadLocal, base_temp, loc)
      if offset != 0 {
        self.emit(@opcode.OpCode::PushConst, offset, loc)
        self.emit(@opcode.OpCode::Add, 0, loc)
      }
      self.gen_expr(init)
      match target_ty.kind() {
        TK_Double => self.emit(@opcode.OpCode::StoreMemD, 0, loc)
        TK_LongLong => self.emit(@opcode.OpCode::StoreMemQ, 0, loc)
        TK_Char => self.emit(@opcode.OpCode::StoreMemByte, 0, loc)
        _ => self.emit(@opcode.OpCode::StoreMem, 0, loc)
      }
    }
  }
}

///|
/// #143（2026-10-18）：struct 变量值整体拷贝到 base_temp+offset 目标
///（逐 4 字节 + 尾字节——gen_struct_copy_to_local 的字段偏移形态；
/// emit_field_init 与 gen_nested_init 两消费点共用）。
fn BytecodeGen::emit_struct_value_copy(
  self : BytecodeGen,
  base_temp : Int32,
  offset : Int32,
  src : @ast.Expr,
  field_ty : @ast.Type,
  loc : @source.SourceLoc,
) -> Unit {
  let size = self.type_size(field_ty)
  if size <= 0 {
    return
  }
  let src_temp = self.get_temp_slot(0)
  self.gen_addr(src, loc)
  self.emit(@opcode.OpCode::StoreLocal, src_temp, loc)
  for i in 0..<(size / 4) {
    self.emit(@opcode.OpCode::LoadLocal, base_temp, loc)
    let dst_off = offset + i * 4
    if dst_off > 0 {
      self.emit(@opcode.OpCode::PushConst, dst_off, loc)
      self.emit(@opcode.OpCode::Add, 0, loc)
    }
    self.emit(@opcode.OpCode::LoadLocal, src_temp, loc)
    if i > 0 {
      self.emit(@opcode.OpCode::PushConst, i * 4, loc)
      self.emit(@opcode.OpCode::Add, 0, loc)
    }
    self.emit(@opcode.OpCode::LoadMem, 0, loc)
    self.emit(@opcode.OpCode::StoreMem, 0, loc)
  }
  // 尾字节（size%4）——同 gen_struct_copy_to_local 病 35 修正
  for b in 0..<(size % 4) {
    let dst_off = offset + size / 4 * 4 + b
    let src_off = size / 4 * 4 + b
    self.emit(@opcode.OpCode::LoadLocal, base_temp, loc)
    if dst_off > 0 {
      self.emit(@opcode.OpCode::PushConst, dst_off, loc)
      self.emit(@opcode.OpCode::Add, 0, loc)
    }
    self.emit(@opcode.OpCode::LoadLocal, src_temp, loc)
    if src_off > 0 {
      self.emit(@opcode.OpCode::PushConst, src_off, loc)
      self.emit(@opcode.OpCode::Add, 0, loc)
    }
    self.emit(@opcode.OpCode::LoadMemByte, 0, loc)
    self.emit(@opcode.OpCode::StoreMemByte, 0, loc)
  }
}

///|
/// struct 按值初始化局部（`struct S s2 = s1;`）——Rust expr.rs:508 的
/// 无 dtor 路径照搬（C only 无析构；dtor 分支属 C++ 临时对象语义）。
/// dst_emit 闭包展开为 to_local 单形态（指令序等价）。
fn BytecodeGen::gen_struct_copy_to_local(
  self : BytecodeGen,
  local_offset : Int32,
  right : @ast.Expr,
  loc : @source.SourceLoc,
) -> Unit {
  let size = self.type_size(right.ty())
  if size <= 0 {
    return
  }
  let src_temp = self.get_temp_slot(0)
  self.gen_addr(right, loc)
  self.emit(@opcode.OpCode::StoreLocal, src_temp, loc)
  for i in 0..<(size / 4) {
    self.emit(@opcode.OpCode::GetFrameBase, 0, loc)
    self.emit(@opcode.OpCode::PushConst, local_offset + i * 4, loc)
    self.emit(@opcode.OpCode::Add, 0, loc)
    self.emit(@opcode.OpCode::LoadLocal, src_temp, loc)
    if i > 0 {
      self.emit(@opcode.OpCode::PushConst, i * 4, loc)
      self.emit(@opcode.OpCode::Add, 0, loc)
    }
    self.emit(@opcode.OpCode::LoadMem, 0, loc)
    self.emit(@opcode.OpCode::StoreMem, 0, loc)
  }
  // 病 35 修正（#71 第三梯队）：size%4 尾字节补拷（同 gen_struct_copy）
  for b in 0..<(size % 4) {
    let off = size / 4 * 4 + b
    self.emit(@opcode.OpCode::GetFrameBase, 0, loc)
    self.emit(@opcode.OpCode::PushConst, local_offset + off, loc)
    self.emit(@opcode.OpCode::Add, 0, loc)
    self.emit(@opcode.OpCode::LoadLocal, src_temp, loc)
    if off > 0 {
      self.emit(@opcode.OpCode::PushConst, off, loc)
      self.emit(@opcode.OpCode::Add, 0, loc)
    }
    self.emit(@opcode.OpCode::LoadMemByte, 0, loc)
    self.emit(@opcode.OpCode::StoreMemByte, 0, loc)
  }
}
