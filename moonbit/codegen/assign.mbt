// 蓝本注记：文内 Rust 源引用（`*.rs` 路径/行号/符号）均为档案态蓝本——tag rust-oracle-freeze（2026-10-05 删区），现为本仓自主基线。

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
/// - 赋值后回读（store 后同型 load 回栈）沿用历史蓝本指令序（golden 冻结锁定）。
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
  // struct/union 整体赋值（s1 = s2）走拷贝循环——#136 缺陷 2（2026-10-17）：
  // 旧只判 TK_Struct，union 类型的成员整体赋值（c.data = arr[0]）落标量
  // 路径半拷/丢数据（读回 0 实锤）；C11 §6.5.16.3 同类型 union 赋值语义
  // = 成员存储逐字节拷贝
  if (left_ty.kind() is TK_Struct || left_ty.kind() is TK_Union) && op is Assign {
    self.gen_struct_copy(left, right, loc)
    return
  }
  match left {
    Identifier(name, _, _) => {
      // reference 判定分支不迁移（C 零出现）
      let local_offset = self.resolve_local(name)
      if local_offset >= 0 {
        if !(op is Assign) {
          if left_is_double {
            self.emit(@opcode.OpCode::LoadLocalD, local_offset, loc)
          } else if left_is_long_long {
            self.emit(@opcode.OpCode::LoadLocalQ, local_offset, loc)
          } else {
            self.emit(@opcode.OpCode::LoadLocal, local_offset, loc)
            // #198：复合赋值运算基值归位字节域（局部 char 4 字节槽可能
            // 残留未窄化值）；幂等
            if left_is_char {
              if left_is_unsigned {
                self.emit(@opcode.OpCode::TruncUByte, 0, loc)
              } else {
                self.emit(@opcode.OpCode::TruncByte, 0, loc)
              }
            }
          }
          // #425 B2：复合路径——左提升到运算域 + 右原样（不预收口）+
          // 域运算 + 窄化回左类型（单源 emit_compound_rhs）
          self.emit_compound_promote_left(
            left_ty,
            right.ty(),
            left_is_ptr,
            is_ptr_compound,
            loc,
          )
          self.emit_compound_rhs(
            right, left_ty, left_is_ptr, is_ptr_compound, ptr_step, op, loc,
          )
        } else {
          self.gen_right(right, left_ty, left_is_ptr, is_ptr_compound, loc)
        }
        if left_is_double {
          self.emit(@opcode.OpCode::StoreLocalD, local_offset, loc)
        } else if left_is_long_long {
          self.emit(@opcode.OpCode::StoreLocalQ, local_offset, loc)
        } else {
          // #198：算术结果回窄字节域再入槽（b=127;b+=1 → -128）；
          // 普通 Assign 路径 gen_right 已带 char 窄化链，此处幂等
          if left_is_char {
            if left_is_unsigned {
              self.emit(@opcode.OpCode::TruncUByte, 0, loc)
            } else {
              self.emit(@opcode.OpCode::TruncByte, 0, loc)
            }
          }
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
      // static local 前置（#283）：无块形态 static 遮蔽同名文件作用域
      // global——旧序 local → global → static 垫底，global 抢先命中
      // （clang 8 / vitro 501 静默错值）。病 37 修正（#71）的 local 居首
      // 保持不变（块内 local 遮蔽 static 的 b37c 探针面），本批只把
      // static 提到 global 之前。
      match self.static_local_indices.get(name) {
        Some(static_offset) => {
          if !(op is Assign) {
            if left_is_double {
              self.emit(@opcode.OpCode::LoadGlobalD, static_offset, loc)
            } else if left_is_long_long {
              self.emit(@opcode.OpCode::LoadGlobalQ, static_offset, loc)
            } else if left_is_char {
              if left_is_unsigned {
                self.emit(@opcode.OpCode::LoadGlobalUByte, static_offset, loc)
              } else {
                self.emit(@opcode.OpCode::LoadGlobalByte, static_offset, loc)
              }
            } else {
              self.emit(@opcode.OpCode::LoadGlobal, static_offset, loc)
            }
            // #425 B2：复合路径——左提升到运算域 + 右原样（不预收口）+
            // 域运算 + 窄化回左类型（单源 emit_compound_rhs）
            self.emit_compound_promote_left(
              left_ty,
              right.ty(),
              left_is_ptr,
              is_ptr_compound,
              loc,
            )
            self.emit_compound_rhs(
              right, left_ty, left_is_ptr, is_ptr_compound, ptr_step, op, loc,
            )
          } else {
            self.gen_right(right, left_ty, left_is_ptr, is_ptr_compound, loc)
          }
          if left_is_double {
            self.emit(@opcode.OpCode::StoreGlobalD, static_offset, loc)
          } else if left_is_long_long {
            self.emit(@opcode.OpCode::StoreGlobalQ, static_offset, loc)
          } else if left_is_char {
            self.emit(@opcode.OpCode::StoreGlobalByte, static_offset, loc)
          } else {
            self.emit(@opcode.OpCode::StoreGlobal, static_offset, loc)
          }
          if left_is_double {
            self.emit(@opcode.OpCode::LoadGlobalD, static_offset, loc)
          } else if left_is_long_long {
            self.emit(@opcode.OpCode::LoadGlobalQ, static_offset, loc)
          } else if left_is_char {
            if left_is_unsigned {
              self.emit(@opcode.OpCode::LoadGlobalUByte, static_offset, loc)
            } else {
              self.emit(@opcode.OpCode::LoadGlobalByte, static_offset, loc)
            }
          } else {
            self.emit(@opcode.OpCode::LoadGlobal, static_offset, loc)
          }
          return
        }
        None => ()
      }
      let global_offset = self.resolve_global(name)
      if global_offset >= 0 {
        if !(op is Assign) {
          if left_is_double {
            self.emit(@opcode.OpCode::LoadGlobalD, global_offset, loc)
          } else if left_is_long_long {
            self.emit(@opcode.OpCode::LoadGlobalQ, global_offset, loc)
          } else if left_is_char {
            // #177：char 全局 1 字节紧排，32 位读卷右侧邻居
            if left_is_unsigned {
              self.emit(@opcode.OpCode::LoadGlobalUByte, global_offset, loc)
            } else {
              self.emit(@opcode.OpCode::LoadGlobalByte, global_offset, loc)
            }
          } else {
            self.emit(@opcode.OpCode::LoadGlobal, global_offset, loc)
          }
          // #425 B2：复合路径——左提升到运算域 + 右原样（不预收口）+
          // 域运算 + 窄化回左类型（单源 emit_compound_rhs）
          self.emit_compound_promote_left(
            left_ty,
            right.ty(),
            left_is_ptr,
            is_ptr_compound,
            loc,
          )
          self.emit_compound_rhs(
            right, left_ty, left_is_ptr, is_ptr_compound, ptr_step, op, loc,
          )
        } else {
          self.gen_right(right, left_ty, left_is_ptr, is_ptr_compound, loc)
        }
        if left_is_double {
          self.emit(@opcode.OpCode::StoreGlobalD, global_offset, loc)
        } else if left_is_long_long {
          self.emit(@opcode.OpCode::StoreGlobalQ, global_offset, loc)
        } else if left_is_char {
          // #177：char 全局 1 字节紧排，4 字节写越权抹右侧池串/变量
          self.emit(@opcode.OpCode::StoreGlobalByte, global_offset, loc)
        } else {
          self.emit(@opcode.OpCode::StoreGlobal, global_offset, loc)
        }
        if left_is_double {
          self.emit(@opcode.OpCode::LoadGlobalD, global_offset, loc)
        } else if left_is_long_long {
          self.emit(@opcode.OpCode::LoadGlobalQ, global_offset, loc)
        } else if left_is_char {
          if left_is_unsigned {
            self.emit(@opcode.OpCode::LoadGlobalUByte, global_offset, loc)
          } else {
            self.emit(@opcode.OpCode::LoadGlobalByte, global_offset, loc)
          }
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
        if left_is_char && left_is_unsigned {
          self.emit(@opcode.OpCode::LoadMemUByte, 0, loc)
        } else if left_is_char {
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
        // #425 B2：复合路径——左提升 + 右原样 + 域运算 + 窄化（单源）。
        // #467 P3-4：left_is_ptr 恒 false——Deref 路径左是 pointee 标量
        //（*p 复合），非指针左值形态
        self.emit_compound_promote_left(
          left_ty,
          right.ty(),
          false,
          is_ptr_compound,
          loc,
        )
        self.emit_compound_rhs(
          right, left_ty, left_is_ptr, is_ptr_compound, ptr_step, op, loc,
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
        if left_is_char && left_is_unsigned {
          self.emit(@opcode.OpCode::LoadMemUByte, 0, loc)
        } else if left_is_char {
          self.emit(@opcode.OpCode::LoadMemByte, 0, loc)
        } else if left_is_double {
          self.emit(@opcode.OpCode::LoadMemD, 0, loc)
        } else if left_is_long_long {
          self.emit(@opcode.OpCode::LoadMemQ, 0, loc)
        } else {
          self.emit(@opcode.OpCode::LoadMem, 0, loc)
        }
      } else {
        // 病 108 同款（Deref 臂内联纯 Assign 段——Dup 前置纯栈序）
        self.emit(@opcode.OpCode::Dup, 0, loc)
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
        if left_is_char && left_is_unsigned {
          self.emit(@opcode.OpCode::LoadMemUByte, 0, loc)
        } else if left_is_char {
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
    Member(object, mname, _, _, _) => {
      self.gen_member_addr(object, mname, loc)
      // lambda by-ref 捕获指针解引用段不迁移（C only）
      // P1-1：left.ty() 即成员类型（typeck 后 Member 携带结果类型），
      // 与 Rust assign.rs 的 left_ty 同构——此前反查 struct_defs 只覆盖
      // struct，union 成员恒落 4 字节（u.d 截断/u.c 越界，审阅实证）
      self.assign_mem_op(
        op,
        right,
        left_ty,
        left_is_ptr,
        is_ptr_compound,
        ptr_step,
        loc,
        left_ty.kind(),
      )
      return
    }
    CompoundLiteral(_, _, _, _) => {
      // #267（2026-10-22，C99 6.5.2.5p3 可修改左值）：gen_expr 的
      // CompoundLiteral 臂按「临时槽物化 + 栈顶留地址」的 lvalue 形态
      // 发射——直接取地址走内存赋值单源（同 Member/Index 臂模式）；
      // `*(int[]){1,2} = 3` 的 Deref 左值经其 operand 物化自动覆盖
      self.gen_expr(left)
      self.assign_mem_op(
        op,
        right,
        left_ty,
        left_is_ptr,
        is_ptr_compound,
        ptr_step,
        loc,
        left_ty.kind(),
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
/// #425 B2（2026-11-03，审阅 v2 / M12-A1）：复合赋值运算域（C11
/// 6.5.16.2p3 常规算术转换——Vitro 无 2 字节整型，域序 int/char <
/// long long < float < double）。返回 (is_double, is_float,
/// is_long_long, is_unsigned)；unsigned 位取病 30/34 口径——char 级
/// unsigned 不参与（提升 int 后消失），LL 域任一 ULL / int 域任一
/// uint 即无符号。
fn compound_domain(
  left_ty : @ast.Type,
  right_ty : @ast.Type,
) -> (Bool, Bool, Bool, Bool) {
  let lk = left_ty.kind()
  let rk = right_ty.kind()
  let d = lk is TK_Double || rk is TK_Double
  let f = !d && (lk is TK_Float || rk is TK_Float)
  let q = !d && !f && (lk is TK_LongLong || rk is TK_LongLong)
  let u = if q {
    (lk is TK_LongLong && left_ty.is_unsigned()) ||
    (rk is TK_LongLong && right_ty.is_unsigned())
  } else if !d && !f {
    (lk is TK_Int && left_ty.is_unsigned()) ||
    (rk is TK_Int && right_ty.is_unsigned())
  } else {
    false
  }
  (d, f, q, u)
}

///|
/// #425 B2：栈顶值按源 kind 提升到复合赋值运算域（左 load 后 / 右
/// gen_expr 后各调一次）。缺直连指令的两形态走双跳（CastQ2F/CastF2Q
/// 不存在——Q→F 经 CastQ2D+CastD2F、F→Q 经 CastF2D+CastD2Q，与
/// (float)ll 直转在尾数舍入上可差 1ulp——缺指令面登记 M12-A2 族）。
fn BytecodeGen::emit_promote_to_compound_domain(
  self : BytecodeGen,
  from_ty : @ast.Type,
  is_double : Bool,
  is_float : Bool,
  is_long_long : Bool,
  loc : @source.SourceLoc,
) -> Unit {
  // #467 P1（2026-11-04 审阅处置）：三轴判源（源 kind x 源 signedness x
  // 目标域）——无符号源走 U 对偶指令（CastU2Q/U2D/U2F/UQ2D/UQ2F），旧
  // 形态一律 signed Cast，跨符号位取值即错（u=4294967295u 提升 LL/D 得
  // -1；与 binary.mbt 提升链 / cast.mbt / var_decl.mbt 同款口径）。
  // unsigned char 源 load 已零扩展（值域 0..255 正 i32）两系指令等价，
  // 按三轴统一走 U 系。
  let from = from_ty.kind()
  let u = from_ty.is_unsigned()
  if is_double {
    if u {
      match from {
        TK_LongLong => self.emit(@opcode.OpCode::CastUQ2D, 0, loc)
        TK_Int | TK_Char => self.emit(@opcode.OpCode::CastU2D, 0, loc)
        _ => ()
      }
    } else {
      match from {
        TK_Float => self.emit(@opcode.OpCode::CastF2D, 0, loc)
        TK_LongLong => self.emit(@opcode.OpCode::CastQ2D, 0, loc)
        TK_Int | TK_Char => self.emit(@opcode.OpCode::CastI2D, 0, loc)
        _ => ()
      }
    }
  } else if is_float {
    if u {
      match from {
        // ULL→f32 直连（#345 批 CastUQ2F 在位）；u32→f32 零扩展转宽
        TK_LongLong => self.emit(@opcode.OpCode::CastUQ2F, 0, loc)
        TK_Int | TK_Char => self.emit(@opcode.OpCode::CastU2F, 0, loc)
        _ => ()
      }
    } else {
      match from {
        TK_LongLong => {
          self.emit(@opcode.OpCode::CastQ2D, 0, loc)
          self.emit(@opcode.OpCode::CastD2F, 0, loc)
        }
        TK_Int | TK_Char => self.emit(@opcode.OpCode::CastI2F, 0, loc)
        _ => ()
      }
    }
  } else if is_long_long {
    match from {
      TK_Int | TK_Char =>
        if u {
          self.emit(@opcode.OpCode::CastU2Q, 0, loc)
        } else {
          self.emit(@opcode.OpCode::CastI2Q, 0, loc)
        }
      _ => ()
    }
  }
}

///|
/// #425 B2：运算域结果窄化回左类型（emit_compound 之后、store 之前）。
/// char 目标的字节窄化不由本函数做（store 段 #198 Trunc 幂等接力——
/// 本函数只负责域级回 int）。
/// #471（2026-11-05）：fp 域 → **无符号**整型左值（uint/ULL——uchar
/// 域 [0,256) ⊆ CastD2I 饱和域内段不走此分）改走 CastD2UQ 链（域内
/// [0,2^64) 无损；旧 CastD2Q/D2I 饱和把 3e9 截 2147483647、1.8e19 截
/// INT64_MAX——C11 6.3.1.4 域内定义行为被破坏，四路径同错之复合臂）。
fn BytecodeGen::emit_compound_narrow(
  self : BytecodeGen,
  left_ty : @ast.Type,
  is_double : Bool,
  is_float : Bool,
  is_long_long : Bool,
  loc : @source.SourceLoc,
) -> Unit {
  let lk = left_ty.kind()
  // #471：无符号左值判据（char 排除——域小零饱和损耗）
  let lu_int = left_ty.is_unsigned() && lk is TK_Int
  let lu_ll = left_ty.is_unsigned() && lk is TK_LongLong
  if is_double {
    if lk is TK_LongLong {
      if lu_ll {
        self.emit(@opcode.OpCode::CastD2UQ, 0, loc)
      } else {
        self.emit(@opcode.OpCode::CastD2Q, 0, loc)
      }
    } else if lk is TK_Float {
      self.emit(@opcode.OpCode::CastD2F, 0, loc)
    } else if lk is TK_Int || lk is TK_Char {
      if lu_int {
        self.emit(@opcode.OpCode::CastD2UQ, 0, loc)
        self.emit(@opcode.OpCode::CastQ2I, 0, loc)
      } else {
        self.emit(@opcode.OpCode::CastD2I, 0, loc)
      }
    } else {
      ()
    }
  } else if is_float {
    if lk is TK_LongLong {
      if lu_ll {
        self.emit(@opcode.OpCode::CastF2D, 0, loc)
        self.emit(@opcode.OpCode::CastD2UQ, 0, loc)
      } else {
        self.emit(@opcode.OpCode::CastF2D, 0, loc)
        self.emit(@opcode.OpCode::CastD2Q, 0, loc)
      }
    } else if lk is TK_Int || lk is TK_Char {
      if lu_int {
        self.emit(@opcode.OpCode::CastF2D, 0, loc)
        self.emit(@opcode.OpCode::CastD2UQ, 0, loc)
        self.emit(@opcode.OpCode::CastQ2I, 0, loc)
      } else {
        self.emit(@opcode.OpCode::CastF2I, 0, loc)
      }
    } else {
      ()
    }
  } else if is_long_long {
    if lk is TK_LongLong {
      ()
    } else {
      self.emit(@opcode.OpCode::CastQ2I, 0, loc)
    }
  }
}

///|
/// #425 B2：复合路径右值发射 + 域提升 + 运算 + 窄化（五调用点单源——
/// 替代旧「gen_right 预收口 + emit_compound 左域参」形态）。指针复合
/// （左是指针的 +=/-=）不走域路径（右保持整型原样，步长由
/// emit_compound 的 ptr 分支处理）。
fn BytecodeGen::emit_compound_rhs(
  self : BytecodeGen,
  right : @ast.Expr,
  left_ty : @ast.Type,
  left_is_ptr : Bool,
  is_ptr_compound : Bool,
  ptr_step : Int32,
  op : @ast.AssignOp,
  loc : @source.SourceLoc,
) -> Unit {
  let (d, f, q, u) = if left_is_ptr && is_ptr_compound {
    self.gen_expr(right)
    (false, false, false, false)
  } else {
    self.gen_expr(right)
    let (d, f, q, u) = compound_domain(left_ty, right.ty())
    self.emit_promote_to_compound_domain(right.ty(), d, f, q, loc)
    (d, f, q, u)
  }
  self.emit_compound(op, d, f, q, u, ptr_step, left_is_ptr, loc)
  self.emit_compound_narrow(left_ty, d, f, q, loc)
}

///|
/// #425 B2：复合路径左值提升（load 段尾调用——栈顶=左值）。指针复合
/// 不提升。
fn BytecodeGen::emit_compound_promote_left(
  self : BytecodeGen,
  left_ty : @ast.Type,
  right_ty : @ast.Type,
  left_is_ptr : Bool,
  is_ptr_compound : Bool,
  loc : @source.SourceLoc,
) -> Unit {
  // is_ptr_compound 只表「op 是 +=/-=」，真指针复合还须左是指针
  if left_is_ptr && is_ptr_compound {
    return
  }
  let (d, f, q, _) = compound_domain(left_ty, right_ty)
  self.emit_promote_to_compound_domain(left_ty, d, f, q, loc)
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
  ptr_step : Int32,
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
      } else if is_long_long && is_unsigned {
        // 病 34：ULL 复合除走无符号 Q 域
        self.emit(@opcode.OpCode::UDivQ, 0, loc)
      } else if is_long_long {
        self.emit(@opcode.OpCode::DivQ, 0, loc)
      } else if is_unsigned {
        self.emit(@opcode.OpCode::UDiv, 0, loc)
      } else {
        self.emit(@opcode.OpCode::Div, 0, loc)
      }
    ModAssign =>
      if is_long_long && is_unsigned {
        self.emit(@opcode.OpCode::UModQ, 0, loc)
      } else if is_long_long {
        self.emit(@opcode.OpCode::ModQ, 0, loc)
      } else if is_unsigned {
        self.emit(@opcode.OpCode::UMod, 0, loc)
      } else {
        self.emit(@opcode.OpCode::Mod, 0, loc)
      }
    // 病 34：Q 域位运算/移位复合赋值此前恒走 32 位指令（x<<=40 trap /
    // y&=…LL 高位丢）；按 is_long_long 分派 Q 版
    AndAssign =>
      if is_long_long {
        self.emit(@opcode.OpCode::BitAndQ, 0, loc)
      } else {
        self.emit(@opcode.OpCode::BitAnd, 0, loc)
      }
    OrAssign =>
      if is_long_long {
        self.emit(@opcode.OpCode::BitOrQ, 0, loc)
      } else {
        self.emit(@opcode.OpCode::BitOr, 0, loc)
      }
    XorAssign =>
      if is_long_long {
        self.emit(@opcode.OpCode::BitXorQ, 0, loc)
      } else {
        self.emit(@opcode.OpCode::BitXor, 0, loc)
      }
    ShlAssign =>
      if is_long_long {
        self.emit(@opcode.OpCode::ShlQ, 0, loc)
      } else {
        self.emit(@opcode.OpCode::Shl, 0, loc)
      }
    ShrAssign =>
      if is_long_long && is_unsigned {
        self.emit(@opcode.OpCode::LShrQ, 0, loc)
      } else if is_long_long {
        self.emit(@opcode.OpCode::ShrQ, 0, loc)
      } else if is_unsigned {
        self.emit(@opcode.OpCode::LShr, 0, loc)
      } else {
        self.emit(@opcode.OpCode::Shr, 0, loc)
      }
    Assign => () // 纯赋值无复合运算（调用点不达）
  }
}

///|
/// struct 整体赋值（s1 = s2）——Rust `gen_struct_copy` 照搬：dst 地址经
/// gen_addr 存 dst 槽，src 经 copy_common 循环逐字拷贝。
/// #424（2026-11-02，审阅 v2 B1 / M12-A4）：dst 槽按赋值嵌套深度分层
/// （get_assign_addr_slot，T-P0-6 机制接入）——旧固定 temp_slot1 在求值
/// 右侧**之前**存入，内层 struct 赋值（call 实参位置 `a = id(b = c)`）
/// 复用同槽覆写 → 外层拷贝写错目标（a 未更新）。src 槽无此问题（在
/// gen_addr(right) 之后存入，拷贝循环内无嵌套发射）。
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
  let dst_temp = self.get_assign_addr_slot()
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
  // 病 35 修正（#71 第三梯队，2026-10-11）：size%4 尾字节补拷——此前
  // 纯 size/4 循环漏尾（size=1 整体零拷贝、size=5 丢第 5 字节）。
  for b in 0..<(size % 4) {
    let off = size / 4 * 4 + b
    self.emit(@opcode.OpCode::LoadLocal, dst_temp, loc)
    if off > 0 {
      self.emit(@opcode.OpCode::PushConst, off, loc)
      self.emit(@opcode.OpCode::Add, 0, loc)
    }
    self.emit(@opcode.OpCode::LoadLocal, src_temp, loc)
    if off > 0 {
      self.emit(@opcode.OpCode::PushConst, off, loc)
      self.emit(@opcode.OpCode::Add, 0, loc)
    }
    self.emit(@opcode.OpCode::LoadMemByte, 0, loc)
    self.emit(@opcode.OpCode::StoreMemByte, 0, loc)
  }
  // 病 36 连坐（#71 第二梯队）：struct 表达式统一「留 1 地址槽」约定
  //（与 Call 返回 struct 的 sret 地址对齐）——赋值表达式值 = 左值地址；
  // 表达式语句侧 gen_expr_stmt 统一弹。此前留 0 槽，与 Call 臂不一致。
  self.emit(@opcode.OpCode::LoadLocal, dst_temp, loc)
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
  ptr_step : Int32,
  loc : @source.SourceLoc,
  elem_kind : @ast.TypeKind,
) -> Unit {
  let is_char = elem_kind is TK_Char
  let is_double = elem_kind is TK_Double
  let is_long_long = elem_kind is TK_LongLong
  // #467 P3-1（2026-11-04 审阅处置）：left_is_double/left_is_long_long
  // 随复合段改接 emit_compound_rhs（域参内算）后无消费方——删
  let left_is_unsigned = left_ty.is_unsigned()
  if !(op is Assign) {
    self.emit(@opcode.OpCode::Dup, 0, loc)
    if is_char && left_is_unsigned {
      self.emit(@opcode.OpCode::LoadMemUByte, 0, loc)
    } else if is_char {
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
    // #425 B2：复合路径——左提升 + 右原样 + 域运算 + 窄化（单源）。
    // #467 P3-4：left_is_ptr 恒 false——assign_mem_op 路径左是
    // Index/Member 的元素/字段标量（非指针复合）
    self.emit_compound_promote_left(
      left_ty,
      right.ty(),
      false,
      is_ptr_compound,
      loc,
    )
    self.emit_compound_rhs(
      right, left_ty, left_is_ptr, is_ptr_compound, ptr_step, op, loc,
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
    if is_char && left_is_unsigned {
      self.emit(@opcode.OpCode::LoadMemUByte, 0, loc)
    } else if is_char {
      self.emit(@opcode.OpCode::LoadMemByte, 0, loc)
    } else if is_double {
      self.emit(@opcode.OpCode::LoadMemD, 0, loc)
    } else if is_long_long {
      self.emit(@opcode.OpCode::LoadMemQ, 0, loc)
    } else {
      self.emit(@opcode.OpCode::LoadMem, 0, loc)
    }
  } else {
    // 病 108 修正（#71 P1 批，2026-10-12）：纯赋值臂改 Dup 前置纯栈序
    //——旧序 StoreLocal 暂存地址供 StoreMem 后回读，当写目标（p[i]=v
    // 的 p+i）恰落暂存槽时地址被写入值污染（登记 pd_idx.c 假 trap 形态：
    // 写 7 报「地址 0x7」）。Dup 前置后地址全程在值栈上，与内存槽零
    // 交叠——同址冲突形态上不可能（回读经栈上保留份 LoadMem）。
    self.emit(@opcode.OpCode::Dup, 0, loc)
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
    if is_char && left_is_unsigned {
      self.emit(@opcode.OpCode::LoadMemUByte, 0, loc)
    } else if is_char {
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
