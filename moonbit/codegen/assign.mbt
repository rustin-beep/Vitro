///|
/// 赋值与三目生成（S5 扩展批三号·赋值——剩余首错第 1 位 67 例 + 三目
/// 10 例）——Rust `expr/assign.rs` 的 C only 子集照搬：
/// - Identifier 三路（static/local/global）+ 复合赋值 11 运算符分派
///   （emit_compound 闭包展开）+ T-P0-6 嵌套深度（gen_assign 入口
///   assign_nest_depth ±1——mut 随本批回加）；
/// - Deref 左值（*p = x 全形态）；
/// - struct 整体赋值（gen_struct_copy——本批补全双形态版）；
/// - reference 两段（ref 返回调用左值 / Identifier ref 判定）不迁移
///   （C 零出现）；Index/Member 左值随其批接线（fail loud）；
/// - 赋值后回读（store 后同型 load 回栈）保持 Rust 指令序逐条一致。
fn BytecodeGen::gen_ternary_expr(
  self : BytecodeGen,
  cond : @ast.Expr,
  then_branch : @ast.Expr,
  else_branch : @ast.Expr,
  loc : @source.SourceLoc,
) -> Unit {
  self.gen_expr(cond)
  let else_jump = self.current_ip()
  self.emit(@opcode.OpCode::JumpIfZero, 0, loc)
  self.gen_expr(then_branch)
  let end_jump = self.current_ip()
  self.emit(@opcode.OpCode::Jump, 0, loc)
  let else_ip = self.current_ip()
  self.patch_jump(else_jump, else_ip)
  self.gen_expr(else_branch)
  let end_ip = self.current_ip()
  self.patch_jump(end_jump, end_ip)
}

///|
/// T-P0-6：入口递增嵌套深度，各层赋值的目标地址槽互不冲突。
fn BytecodeGen::gen_assign(
  self : BytecodeGen,
  op : @ast.AssignOp,
  left : @ast.Expr,
  right : @ast.Expr,
  loc : @source.SourceLoc,
) -> Unit {
  self.assign_nest_depth += 1
  self.gen_assign_inner(op, left, right, loc)
  self.assign_nest_depth -= 1
}

///|
fn BytecodeGen::gen_assign_inner(
  self : BytecodeGen,
  op : @ast.AssignOp,
  left : @ast.Expr,
  right : @ast.Expr,
  loc : @source.SourceLoc,
) -> Unit {
  let left_ty = left.ty()
  let left_is_double = left_ty.kind() is TK_Double
  let left_is_long_long = left_ty.kind() is TK_LongLong
  let left_is_char = left_ty.kind() is TK_Char
  let left_is_unsigned = left_ty.is_unsigned()
  let left_is_ptr = left_ty.kind() is TK_Pointer
  let is_ptr_compound = op is AddAssign || op is SubAssign
  let ptr_step = if left_is_ptr {
    match left_ty {
      Pointer(pointee, _) =>
        if pointee.kind() is TK_Void {
          1
        } else {
          self.ptr_step_size(left_ty)
        }
      _ => self.ptr_step_size(left_ty)
    }
  } else {
    0
  }
  // struct 整体赋值（s1 = s2）走拷贝循环
  if left_ty.kind() is TK_Struct && op is Assign {
    self.gen_struct_copy(left, right, loc)
    return
  }
  match left {
    Identifier(name, _, _) => {
      // reference 判定分支不迁移（C 零出现）
      match self.static_local_indices.get(name) {
        Some(static_offset) => {
          if !(op is Assign) {
            if left_is_double {
              self.emit(@opcode.OpCode::LoadGlobalD, static_offset, loc)
            } else if left_is_long_long {
              self.emit(@opcode.OpCode::LoadGlobalQ, static_offset, loc)
            } else {
              self.emit(@opcode.OpCode::LoadGlobal, static_offset, loc)
            }
            self.gen_right(right, left_ty, left_is_ptr, is_ptr_compound, loc)
            self.emit_compound(
              op,
              left_is_double,
              left_ty.kind() is TK_Float,
              left_is_long_long,
              left_is_unsigned,
              ptr_step,
              left_is_ptr,
              loc,
            )
          } else {
            self.gen_right(right, left_ty, left_is_ptr, is_ptr_compound, loc)
          }
          if left_is_double {
            self.emit(@opcode.OpCode::StoreGlobalD, static_offset, loc)
          } else if left_is_long_long {
            self.emit(@opcode.OpCode::StoreGlobalQ, static_offset, loc)
          } else {
            self.emit(@opcode.OpCode::StoreGlobal, static_offset, loc)
          }
          if left_is_double {
            self.emit(@opcode.OpCode::LoadGlobalD, static_offset, loc)
          } else if left_is_long_long {
            self.emit(@opcode.OpCode::LoadGlobalQ, static_offset, loc)
          } else {
            self.emit(@opcode.OpCode::LoadGlobal, static_offset, loc)
          }
          return
        }
        None => ()
      }
      let local_offset = self.resolve_local(name)
      if local_offset >= 0 {
        if !(op is Assign) {
          if left_is_double {
            self.emit(@opcode.OpCode::LoadLocalD, local_offset, loc)
          } else if left_is_long_long {
            self.emit(@opcode.OpCode::LoadLocalQ, local_offset, loc)
          } else {
            self.emit(@opcode.OpCode::LoadLocal, local_offset, loc)
          }
          self.gen_right(right, left_ty, left_is_ptr, is_ptr_compound, loc)
          self.emit_compound(
            op,
            left_is_double,
            left_ty.kind() is TK_Float,
            left_is_long_long,
            left_is_unsigned,
            ptr_step,
            left_is_ptr,
            loc,
          )
        } else {
          self.gen_right(right, left_ty, left_is_ptr, is_ptr_compound, loc)
        }
        if left_is_double {
          self.emit(@opcode.OpCode::StoreLocalD, local_offset, loc)
        } else if left_is_long_long {
          self.emit(@opcode.OpCode::StoreLocalQ, local_offset, loc)
        } else {
          self.emit(@opcode.OpCode::StoreLocal, local_offset, loc)
        }
        if left_is_double {
          self.emit(@opcode.OpCode::LoadLocalD, local_offset, loc)
        } else if left_is_long_long {
          self.emit(@opcode.OpCode::LoadLocalQ, local_offset, loc)
        } else {
          self.emit(@opcode.OpCode::LoadLocal, local_offset, loc)
        }
        return
      }
      let global_offset = self.resolve_global(name)
      if global_offset >= 0 {
        if !(op is Assign) {
          if left_is_double {
            self.emit(@opcode.OpCode::LoadGlobalD, global_offset, loc)
          } else if left_is_long_long {
            self.emit(@opcode.OpCode::LoadGlobalQ, global_offset, loc)
          } else {
            self.emit(@opcode.OpCode::LoadGlobal, global_offset, loc)
          }
          self.gen_right(right, left_ty, left_is_ptr, is_ptr_compound, loc)
          self.emit_compound(
            op,
            left_is_double,
            left_ty.kind() is TK_Float,
            left_is_long_long,
            left_is_unsigned,
            ptr_step,
            left_is_ptr,
            loc,
          )
        } else {
          self.gen_right(right, left_ty, left_is_ptr, is_ptr_compound, loc)
        }
        if left_is_double {
          self.emit(@opcode.OpCode::StoreGlobalD, global_offset, loc)
        } else if left_is_long_long {
          self.emit(@opcode.OpCode::StoreGlobalQ, global_offset, loc)
        } else {
          self.emit(@opcode.OpCode::StoreGlobal, global_offset, loc)
        }
        if left_is_double {
          self.emit(@opcode.OpCode::LoadGlobalD, global_offset, loc)
        } else if left_is_long_long {
          self.emit(@opcode.OpCode::LoadGlobalQ, global_offset, loc)
        } else {
          self.emit(@opcode.OpCode::LoadGlobal, global_offset, loc)
        }
        return
      }
    }
    Index(array, index, _, result_ty) => {
      self.gen_index(array, index, result_ty, loc, true)
      self.assign_mem_op(
        op,
        right,
        left_ty,
        left_is_ptr,
        is_ptr_compound,
        ptr_step,
        loc,
        result_ty.kind(),
      )
      return
    }
    Unary(@ast.UnaryOp::Deref, operand, _, _) => {
      // *p = x（左值解引用）
      self.gen_expr(operand)
      if !(op is Assign) {
        self.emit(@opcode.OpCode::Dup, 0, loc)
        if left_is_char {
          self.emit(@opcode.OpCode::LoadMemByte, 0, loc)
        } else if left_is_double {
          self.emit(@opcode.OpCode::LoadMemD, 0, loc)
        } else if left_is_long_long {
          self.emit(@opcode.OpCode::LoadMemQ, 0, loc)
        } else {
          self.emit(@opcode.OpCode::LoadMem, 0, loc)
        }
        self.emit(@opcode.OpCode::Swap, 0, loc)
        let addr_temp = self.get_assign_addr_slot()
        self.emit(@opcode.OpCode::StoreLocal, addr_temp, loc)
        self.gen_right(right, left_ty, left_is_ptr, is_ptr_compound, loc)
        self.emit_compound(
          op,
          left_is_double,
          left_ty.kind() is TK_Float,
          left_is_long_long,
          left_is_unsigned,
          ptr_step,
          left_is_ptr,
          loc,
        )
        self.emit(@opcode.OpCode::LoadLocal, addr_temp, loc)
        self.emit(@opcode.OpCode::Swap, 0, loc)
        if left_is_char {
          self.emit(@opcode.OpCode::StoreMemByte, 0, loc)
        } else if left_is_double {
          self.emit(@opcode.OpCode::StoreMemD, 0, loc)
        } else if left_is_long_long {
          self.emit(@opcode.OpCode::StoreMemQ, 0, loc)
        } else {
          self.emit(@opcode.OpCode::StoreMem, 0, loc)
        }
        self.emit(@opcode.OpCode::LoadLocal, addr_temp, loc)
        if left_is_char {
          self.emit(@opcode.OpCode::LoadMemByte, 0, loc)
        } else if left_is_double {
          self.emit(@opcode.OpCode::LoadMemD, 0, loc)
        } else if left_is_long_long {
          self.emit(@opcode.OpCode::LoadMemQ, 0, loc)
        } else {
          self.emit(@opcode.OpCode::LoadMem, 0, loc)
        }
      } else {
        self.emit(@opcode.OpCode::Dup, 0, loc)
        let addr_temp = self.get_assign_addr_slot()
        self.emit(@opcode.OpCode::StoreLocal, addr_temp, loc)
        self.gen_right(right, left_ty, left_is_ptr, is_ptr_compound, loc)
        if left_is_char {
          self.emit(@opcode.OpCode::StoreMemByte, 0, loc)
        } else if left_is_double {
          self.emit(@opcode.OpCode::StoreMemD, 0, loc)
        } else if left_is_long_long {
          self.emit(@opcode.OpCode::StoreMemQ, 0, loc)
        } else {
          self.emit(@opcode.OpCode::StoreMem, 0, loc)
        }
        self.emit(@opcode.OpCode::LoadLocal, addr_temp, loc)
        if left_is_char {
          self.emit(@opcode.OpCode::LoadMemByte, 0, loc)
        } else if left_is_double {
          self.emit(@opcode.OpCode::LoadMemD, 0, loc)
        } else if left_is_long_long {
          self.emit(@opcode.OpCode::LoadMemQ, 0, loc)
        } else {
          self.emit(@opcode.OpCode::LoadMem, 0, loc)
        }
      }
      return
    }
    Member(object, mname, _, _) => {
      self.gen_member_addr(object, mname, loc)
      // lambda by-ref 捕获指针解引用段不迁移（C only）
      let elem_kind = self.member_elem_kind(object, mname)
      self.assign_mem_op(
        op, right, left_ty, left_is_ptr, is_ptr_compound, ptr_step, loc, elem_kind,
      )
      return
    }
    _ => ()
  }
  self.report_error("赋值目标不支持", loc)
  self.gen_right(right, left_ty, left_is_ptr, is_ptr_compound, loc)
  self.emit(@opcode.OpCode::Pop, 0, loc)
  self.emit(@opcode.OpCode::PushConst, 0, loc)
}

///|
/// Rust `gen_right` 闭包展开：指针复合赋值直传右值，其余经隐式转换收口。
fn BytecodeGen::gen_right(
  self : BytecodeGen,
  right : @ast.Expr,
  left_ty : @ast.Type,
  left_is_ptr : Bool,
  is_ptr_compound : Bool,
  loc : @source.SourceLoc,
) -> Unit {
  if left_is_ptr && is_ptr_compound {
    self.gen_expr(right)
  } else {
    self.gen_expr_with_cast(right, left_ty, loc)
  }
}

///|
/// Rust `emit_compound` 闭包展开：11 复合赋值运算符的 opcode 分派。
fn BytecodeGen::emit_compound(
  self : BytecodeGen,
  op : @ast.AssignOp,
  is_double : Bool,
  is_float : Bool,
  is_long_long : Bool,
  is_unsigned : Bool,
  ptr_step : Int,
  left_is_ptr : Bool,
  loc : @source.SourceLoc,
) -> Unit {
  match op {
    AddAssign =>
      if left_is_ptr {
        self.emit(@opcode.OpCode::PushConst, ptr_step, loc)
        self.emit(@opcode.OpCode::Mul, 0, loc)
        self.emit(@opcode.OpCode::Add, 0, loc)
      } else if is_double {
        self.emit(@opcode.OpCode::AddD, 0, loc)
      } else if is_float {
        self.emit(@opcode.OpCode::AddF, 0, loc)
      } else if is_long_long {
        self.emit(@opcode.OpCode::AddQ, 0, loc)
      } else if is_unsigned {
        self.emit(@opcode.OpCode::UAdd, 0, loc)
      } else {
        self.emit(@opcode.OpCode::Add, 0, loc)
      }
    SubAssign =>
      if left_is_ptr {
        self.emit(@opcode.OpCode::PushConst, ptr_step, loc)
        self.emit(@opcode.OpCode::Mul, 0, loc)
        self.emit(@opcode.OpCode::Sub, 0, loc)
      } else if is_double {
        self.emit(@opcode.OpCode::SubD, 0, loc)
      } else if is_float {
        self.emit(@opcode.OpCode::SubF, 0, loc)
      } else if is_long_long {
        self.emit(@opcode.OpCode::SubQ, 0, loc)
      } else if is_unsigned {
        self.emit(@opcode.OpCode::USub, 0, loc)
      } else {
        self.emit(@opcode.OpCode::Sub, 0, loc)
      }
    MulAssign =>
      if is_double {
        self.emit(@opcode.OpCode::MulD, 0, loc)
      } else if is_float {
        self.emit(@opcode.OpCode::MulF, 0, loc)
      } else if is_long_long {
        self.emit(@opcode.OpCode::MulQ, 0, loc)
      } else if is_unsigned {
        self.emit(@opcode.OpCode::UMul, 0, loc)
      } else {
        self.emit(@opcode.OpCode::Mul, 0, loc)
      }
    DivAssign =>
      if is_double {
        self.emit(@opcode.OpCode::DivD, 0, loc)
      } else if is_float {
        self.emit(@opcode.OpCode::DivF, 0, loc)
      } else if is_long_long {
        self.emit(@opcode.OpCode::DivQ, 0, loc)
      } else if is_unsigned {
        self.emit(@opcode.OpCode::UDiv, 0, loc)
      } else {
        self.emit(@opcode.OpCode::Div, 0, loc)
      }
    ModAssign =>
      if is_long_long {
        self.emit(@opcode.OpCode::ModQ, 0, loc)
      } else if is_unsigned {
        self.emit(@opcode.OpCode::UMod, 0, loc)
      } else {
        self.emit(@opcode.OpCode::Mod, 0, loc)
      }
    AndAssign => self.emit(@opcode.OpCode::BitAnd, 0, loc)
    OrAssign => self.emit(@opcode.OpCode::BitOr, 0, loc)
    XorAssign => self.emit(@opcode.OpCode::BitXor, 0, loc)
    ShlAssign => self.emit(@opcode.OpCode::Shl, 0, loc)
    ShrAssign =>
      if is_unsigned {
        self.emit(@opcode.OpCode::LShr, 0, loc)
      } else {
        self.emit(@opcode.OpCode::Shr, 0, loc)
      }
    Assign => () // 纯赋值无复合运算（调用点不达）
  }
}

///|
/// struct 整体赋值（s1 = s2）——Rust `gen_struct_copy` 照搬：dst 地址经
/// gen_addr 存 temp_slot1，src 经 copy_common 循环逐字拷贝。
fn BytecodeGen::gen_struct_copy(
  self : BytecodeGen,
  left : @ast.Expr,
  right : @ast.Expr,
  loc : @source.SourceLoc,
) -> Unit {
  let size = self.type_size(left.ty())
  if size <= 0 {
    return
  }
  let dst_temp = self.get_temp_slot(1)
  self.gen_addr(left, loc)
  self.emit(@opcode.OpCode::StoreLocal, dst_temp, loc)
  let src_temp = self.get_temp_slot(0)
  self.gen_addr(right, loc)
  self.emit(@opcode.OpCode::StoreLocal, src_temp, loc)
  for i in 0..<(size / 4) {
    self.emit(@opcode.OpCode::LoadLocal, dst_temp, loc)
    if i > 0 {
      self.emit(@opcode.OpCode::PushConst, i * 4, loc)
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
}

///|
/// 内存位置赋值公共体（Index/Member 左值共用——Rust assign.rs 两臂的
/// 同构指令序）：Dup →(复合) load → Swap → addr_temp → right →
/// (复合) compound → 回写 → 回读。elem_kind 决定 load/store 宽度。
fn BytecodeGen::assign_mem_op(
  self : BytecodeGen,
  op : @ast.AssignOp,
  right : @ast.Expr,
  left_ty : @ast.Type,
  left_is_ptr : Bool,
  is_ptr_compound : Bool,
  ptr_step : Int,
  loc : @source.SourceLoc,
  elem_kind : @ast.TypeKind,
) -> Unit {
  let is_char = elem_kind is TK_Char
  let is_double = elem_kind is TK_Double
  let is_long_long = elem_kind is TK_LongLong
  let left_is_double = left_ty.kind() is TK_Double
  let left_is_long_long = left_ty.kind() is TK_LongLong
  let left_is_unsigned = left_ty.is_unsigned()
  if !(op is Assign) {
    self.emit(@opcode.OpCode::Dup, 0, loc)
    if is_char {
      self.emit(@opcode.OpCode::LoadMemByte, 0, loc)
    } else if is_double {
      self.emit(@opcode.OpCode::LoadMemD, 0, loc)
    } else if is_long_long {
      self.emit(@opcode.OpCode::LoadMemQ, 0, loc)
    } else {
      self.emit(@opcode.OpCode::LoadMem, 0, loc)
    }
    self.emit(@opcode.OpCode::Swap, 0, loc)
    let addr_temp = self.get_assign_addr_slot()
    self.emit(@opcode.OpCode::StoreLocal, addr_temp, loc)
    self.gen_right(right, left_ty, left_is_ptr, is_ptr_compound, loc)
    self.emit_compound(
      op,
      left_is_double,
      left_ty.kind() is TK_Float,
      left_is_long_long,
      left_is_unsigned,
      ptr_step,
      left_is_ptr,
      loc,
    )
    self.emit(@opcode.OpCode::LoadLocal, addr_temp, loc)
    self.emit(@opcode.OpCode::Swap, 0, loc)
    if is_char {
      self.emit(@opcode.OpCode::StoreMemByte, 0, loc)
    } else if is_double {
      self.emit(@opcode.OpCode::StoreMemD, 0, loc)
    } else if is_long_long {
      self.emit(@opcode.OpCode::StoreMemQ, 0, loc)
    } else {
      self.emit(@opcode.OpCode::StoreMem, 0, loc)
    }
    self.emit(@opcode.OpCode::LoadLocal, addr_temp, loc)
    if is_char {
      self.emit(@opcode.OpCode::LoadMemByte, 0, loc)
    } else if is_double {
      self.emit(@opcode.OpCode::LoadMemD, 0, loc)
    } else if is_long_long {
      self.emit(@opcode.OpCode::LoadMemQ, 0, loc)
    } else {
      self.emit(@opcode.OpCode::LoadMem, 0, loc)
    }
  } else {
    self.emit(@opcode.OpCode::Dup, 0, loc)
    let addr_temp = self.get_assign_addr_slot()
    self.emit(@opcode.OpCode::StoreLocal, addr_temp, loc)
    self.gen_right(right, left_ty, left_is_ptr, is_ptr_compound, loc)
    if is_char {
      self.emit(@opcode.OpCode::StoreMemByte, 0, loc)
    } else if is_double {
      self.emit(@opcode.OpCode::StoreMemD, 0, loc)
    } else if is_long_long {
      self.emit(@opcode.OpCode::StoreMemQ, 0, loc)
    } else {
      self.emit(@opcode.OpCode::StoreMem, 0, loc)
    }
    self.emit(@opcode.OpCode::LoadLocal, addr_temp, loc)
    if is_char {
      self.emit(@opcode.OpCode::LoadMemByte, 0, loc)
    } else if is_double {
      self.emit(@opcode.OpCode::LoadMemD, 0, loc)
    } else if is_long_long {
      self.emit(@opcode.OpCode::LoadMemQ, 0, loc)
    } else {
      self.emit(@opcode.OpCode::LoadMem, 0, loc)
    }
  }
}

///|
/// Member 左值的元素宽度键：经 struct_defs 查成员字段类型。
fn BytecodeGen::member_elem_kind(
  self : BytecodeGen,
  object : @ast.Expr,
  mname : String,
) -> @ast.TypeKind {
  let obj_ty = object.ty()
  let base = if obj_ty.kind() is TK_Pointer {
    match obj_ty {
      Pointer(pointee, _) => pointee
      _ => obj_ty
    }
  } else {
    obj_ty
  }
  if base.kind() is TK_Struct {
    match self.struct_defs.get(base.name()) {
      Some(fields) =>
        for f in fields {
          if f.name == mname {
            return f.ty.kind()
          }
        }
      None => ()
    }
  }
  base.kind()
}
