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
              // static local（Rust gen_addr 此处无 static 分支——勘察 #29
              // 登记的既有缺陷照搬：`static struct S s1; struct S s2 = s1;`
              // 报"未声明的变量"；差异随 S8 台账裁定，迁移期不私改）
              self.report_error("未声明的变量", loc)
          }
      }
    Unary(@ast.UnaryOp::Deref, operand, _, _) => self.gen_expr(operand)
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
  base_temp : Int,
  offset : Int,
  target_ty : @ast.Type,
  init : @ast.Expr,
  loc : @source.SourceLoc,
) -> Unit {
  match init {
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
          let mut field_offset = 0
          for j in 0..<i {
            field_offset += self.type_size(fields[j].ty)
          }
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
/// struct 按值初始化局部（`struct S s2 = s1;`）——Rust expr.rs:508 的
/// 无 dtor 路径照搬（C only 无析构；dtor 分支属 C++ 临时对象语义）。
/// dst_emit 闭包展开为 to_local 单形态（指令序等价）。
fn BytecodeGen::gen_struct_copy_to_local(
  self : BytecodeGen,
  local_offset : Int,
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
}
