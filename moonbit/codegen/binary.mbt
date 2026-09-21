///|
/// 二元运算生成（S5 表达式核心批·二元——剩余首错第 1 位 72 例）——Rust
/// `expr/binary.rs` 全量照搬：隐式数值提升链（int→float/double/long long
/// 的 CastI2x 与 F2D/Q2D/I2Q 桥接，比较运算按操作数侧判定而非结果侧）/
/// 指针算术（Add/Sub 的步长缩放与指针差除步长）/ U 族 unsigned 分派 /
/// &&/|| 短路结构 + T-P1-1 结果规范化（PushConst 0 + Ne）/ Comma 的
/// Swap+Pop。19 运算符穷尽 match。
fn BytecodeGen::gen_binary(
  self : BytecodeGen,
  op : @ast.BinaryOp,
  left : @ast.Expr,
  right : @ast.Expr,
  ty : @ast.Type,
  loc : @source.SourceLoc,
) -> Unit {
  let left_is_ptr = left.ty().kind() is TK_Pointer || left.ty().is_array()
  let right_is_ptr = right.ty().kind() is TK_Pointer || right.ty().is_array()
  let result_is_double = ty.kind() is TK_Double
  let result_is_float = ty.kind() is TK_Float
  let result_is_long_long = ty.kind() is TK_LongLong
  let any_fp = result_is_double || result_is_float
  // 比较运算结果恒 int——提升判定看操作数侧
  let is_comparison = op is Eq ||
    op is Ne ||
    op is Lt ||
    op is Le ||
    op is Gt ||
    op is Ge
  let lk = left.ty().kind()
  let rk = right.ty().kind()
  let op_is_double = if is_comparison {
    lk is TK_Double || rk is TK_Double
  } else {
    result_is_double
  }
  let op_is_float = if is_comparison {
    !op_is_double && (lk is TK_Float || rk is TK_Float)
  } else {
    result_is_float
  }
  let op_is_long_long = if is_comparison {
    !op_is_double && !op_is_float && (lk is TK_LongLong || rk is TK_LongLong)
  } else {
    result_is_long_long
  }
  let any_op_fp = op_is_double || op_is_float
  let is_unsigned = if is_comparison {
    ((lk is TK_Int || lk is TK_Char) && left.ty().is_unsigned()) ||
    ((rk is TK_Int || rk is TK_Char) && right.ty().is_unsigned())
  } else {
    (ty.kind() is TK_Int || ty.kind() is TK_Char) && ty.is_unsigned()
  }
  // && / || 短路求值
  if op is And || op is Or {
    self.gen_expr(left)
    match lk {
      TK_Float => self.emit(@opcode.OpCode::CastF2I, 0, loc)
      TK_Double => self.emit(@opcode.OpCode::CastD2I, 0, loc)
      TK_LongLong => self.emit(@opcode.OpCode::CastQ2I, 0, loc)
      _ => ()
    }
    self.emit(@opcode.OpCode::Dup, 0, loc)
    let end_jump = self.current_ip()
    if op is And {
      self.emit(@opcode.OpCode::JumpIfZero, 0, loc)
    } else {
      self.emit(@opcode.OpCode::JumpIfNotZero, 0, loc)
    }
    self.emit(@opcode.OpCode::Pop, 0, loc)
    self.gen_expr(right)
    match rk {
      TK_Float => self.emit(@opcode.OpCode::CastF2I, 0, loc)
      TK_Double => self.emit(@opcode.OpCode::CastD2I, 0, loc)
      TK_LongLong => self.emit(@opcode.OpCode::CastQ2I, 0, loc)
      _ => ()
    }
    let end_ip = self.current_ip()
    self.patch_jump(end_jump, end_ip)
    // T-P1-1：C 标准要求 &&/|| 结果规范化 0/1（此前把操作数原始值留作
    // 结果：5&&3 得 3）
    self.emit(@opcode.OpCode::PushConst, 0, loc)
    self.emit(@opcode.OpCode::Ne, 0, loc)
    return
  }
  self.gen_expr(left)
  let any_fp_for_cast = if is_comparison { any_op_fp } else { any_fp }
  let cast_is_double = if is_comparison {
    op_is_double
  } else {
    result_is_double
  }
  let cast_is_long_long = if is_comparison {
    op_is_long_long
  } else {
    result_is_long_long
  }
  // 左操作数隐式提升
  if any_fp_for_cast &&
    !left_is_ptr &&
    !(lk is TK_Float) &&
    !(lk is TK_Double) &&
    !(lk is TK_LongLong) {
    if cast_is_double {
      self.emit(@opcode.OpCode::CastI2D, 0, loc)
    } else {
      self.emit(@opcode.OpCode::CastI2F, 0, loc)
    }
  } else if cast_is_double && lk is TK_Float {
    self.emit(@opcode.OpCode::CastF2D, 0, loc)
  } else if cast_is_double && lk is TK_LongLong {
    self.emit(@opcode.OpCode::CastQ2D, 0, loc)
  } else if cast_is_long_long && lk is TK_Int {
    self.emit(@opcode.OpCode::CastI2Q, 0, loc)
  }
  self.gen_expr(right)
  // 右操作数隐式提升
  if any_fp_for_cast &&
    !right_is_ptr &&
    !(rk is TK_Float) &&
    !(rk is TK_Double) &&
    !(rk is TK_LongLong) {
    if cast_is_double {
      self.emit(@opcode.OpCode::CastI2D, 0, loc)
    } else {
      self.emit(@opcode.OpCode::CastI2F, 0, loc)
    }
  } else if cast_is_double && rk is TK_Float {
    self.emit(@opcode.OpCode::CastF2D, 0, loc)
  } else if cast_is_double && rk is TK_LongLong {
    self.emit(@opcode.OpCode::CastQ2D, 0, loc)
  } else if cast_is_long_long && rk is TK_Int {
    self.emit(@opcode.OpCode::CastI2Q, 0, loc)
  }
  match op {
    Add =>
      if left_is_ptr && !right_is_ptr {
        let step = self.ptr_step_size(left.ty())
        self.emit(@opcode.OpCode::PushConst, step, loc)
        self.emit(@opcode.OpCode::Mul, 0, loc)
        self.emit(@opcode.OpCode::Add, 0, loc)
      } else if !left_is_ptr && right_is_ptr {
        let step = self.ptr_step_size(right.ty())
        self.emit(@opcode.OpCode::Swap, 0, loc)
        self.emit(@opcode.OpCode::PushConst, step, loc)
        self.emit(@opcode.OpCode::Mul, 0, loc)
        self.emit(@opcode.OpCode::Swap, 0, loc)
        self.emit(@opcode.OpCode::Add, 0, loc)
      } else if result_is_double {
        self.emit(@opcode.OpCode::AddD, 0, loc)
      } else if result_is_float {
        self.emit(@opcode.OpCode::AddF, 0, loc)
      } else if result_is_long_long {
        self.emit(@opcode.OpCode::AddQ, 0, loc)
      } else if is_unsigned {
        self.emit(@opcode.OpCode::UAdd, 0, loc)
      } else {
        self.emit(@opcode.OpCode::Add, 0, loc)
      }
    Sub =>
      if left_is_ptr && right_is_ptr {
        // 指针差：减后除步长
        let step = self.ptr_step_size(left.ty())
        self.emit(@opcode.OpCode::Sub, 0, loc)
        self.emit(@opcode.OpCode::PushConst, step, loc)
        self.emit(@opcode.OpCode::Div, 0, loc)
      } else if left_is_ptr && !right_is_ptr {
        let step = self.ptr_step_size(left.ty())
        self.emit(@opcode.OpCode::PushConst, step, loc)
        self.emit(@opcode.OpCode::Mul, 0, loc)
        self.emit(@opcode.OpCode::Sub, 0, loc)
      } else if result_is_double {
        self.emit(@opcode.OpCode::SubD, 0, loc)
      } else if result_is_float {
        self.emit(@opcode.OpCode::SubF, 0, loc)
      } else if result_is_long_long {
        self.emit(@opcode.OpCode::SubQ, 0, loc)
      } else if is_unsigned {
        self.emit(@opcode.OpCode::USub, 0, loc)
      } else {
        self.emit(@opcode.OpCode::Sub, 0, loc)
      }
    Mul =>
      if result_is_double {
        self.emit(@opcode.OpCode::MulD, 0, loc)
      } else if result_is_float {
        self.emit(@opcode.OpCode::MulF, 0, loc)
      } else if result_is_long_long {
        self.emit(@opcode.OpCode::MulQ, 0, loc)
      } else if is_unsigned {
        self.emit(@opcode.OpCode::UMul, 0, loc)
      } else {
        self.emit(@opcode.OpCode::Mul, 0, loc)
      }
    Div =>
      if result_is_double {
        self.emit(@opcode.OpCode::DivD, 0, loc)
      } else if result_is_float {
        self.emit(@opcode.OpCode::DivF, 0, loc)
      } else if result_is_long_long {
        self.emit(@opcode.OpCode::DivQ, 0, loc)
      } else if is_unsigned {
        self.emit(@opcode.OpCode::UDiv, 0, loc)
      } else {
        self.emit(@opcode.OpCode::Div, 0, loc)
      }
    Mod =>
      if result_is_long_long {
        self.emit(@opcode.OpCode::ModQ, 0, loc)
      } else if is_unsigned {
        self.emit(@opcode.OpCode::UMod, 0, loc)
      } else {
        self.emit(@opcode.OpCode::Mod, 0, loc)
      }
    Eq =>
      if op_is_double {
        self.emit(@opcode.OpCode::EqD, 0, loc)
      } else if op_is_float {
        self.emit(@opcode.OpCode::EqF, 0, loc)
      } else if op_is_long_long {
        self.emit(@opcode.OpCode::EqQ, 0, loc)
      } else {
        self.emit(@opcode.OpCode::Eq, 0, loc)
      }
    Ne =>
      if op_is_double {
        self.emit(@opcode.OpCode::NeD, 0, loc)
      } else if op_is_float {
        self.emit(@opcode.OpCode::NeF, 0, loc)
      } else if op_is_long_long {
        self.emit(@opcode.OpCode::NeQ, 0, loc)
      } else {
        self.emit(@opcode.OpCode::Ne, 0, loc)
      }
    Lt =>
      if op_is_double {
        self.emit(@opcode.OpCode::LtD, 0, loc)
      } else if op_is_float {
        self.emit(@opcode.OpCode::LtF, 0, loc)
      } else if op_is_long_long {
        self.emit(@opcode.OpCode::LtQ, 0, loc)
      } else if is_unsigned {
        self.emit(@opcode.OpCode::ULt, 0, loc)
      } else {
        self.emit(@opcode.OpCode::Lt, 0, loc)
      }
    Le =>
      if op_is_double {
        self.emit(@opcode.OpCode::LeD, 0, loc)
      } else if op_is_float {
        self.emit(@opcode.OpCode::LeF, 0, loc)
      } else if op_is_long_long {
        self.emit(@opcode.OpCode::LeQ, 0, loc)
      } else if is_unsigned {
        self.emit(@opcode.OpCode::ULe, 0, loc)
      } else {
        self.emit(@opcode.OpCode::Le, 0, loc)
      }
    Gt =>
      if op_is_double {
        self.emit(@opcode.OpCode::GtD, 0, loc)
      } else if op_is_float {
        self.emit(@opcode.OpCode::GtF, 0, loc)
      } else if op_is_long_long {
        self.emit(@opcode.OpCode::GtQ, 0, loc)
      } else if is_unsigned {
        self.emit(@opcode.OpCode::UGt, 0, loc)
      } else {
        self.emit(@opcode.OpCode::Gt, 0, loc)
      }
    Ge =>
      if op_is_double {
        self.emit(@opcode.OpCode::GeD, 0, loc)
      } else if op_is_float {
        self.emit(@opcode.OpCode::GeF, 0, loc)
      } else if op_is_long_long {
        self.emit(@opcode.OpCode::GeQ, 0, loc)
      } else if is_unsigned {
        self.emit(@opcode.OpCode::UGe, 0, loc)
      } else {
        self.emit(@opcode.OpCode::Ge, 0, loc)
      }
    BitAnd =>
      // E1 B 档：long long 位运算走 64 位指令
      if result_is_long_long {
        self.emit(@opcode.OpCode::BitAndQ, 0, loc)
      } else {
        self.emit(@opcode.OpCode::BitAnd, 0, loc)
      }
    BitOr =>
      if result_is_long_long {
        self.emit(@opcode.OpCode::BitOrQ, 0, loc)
      } else {
        self.emit(@opcode.OpCode::BitOr, 0, loc)
      }
    BitXor =>
      if result_is_long_long {
        self.emit(@opcode.OpCode::BitXorQ, 0, loc)
      } else {
        self.emit(@opcode.OpCode::BitXor, 0, loc)
      }
    Shl =>
      if result_is_long_long {
        self.emit(@opcode.OpCode::ShlQ, 0, loc)
      } else {
        self.emit(@opcode.OpCode::Shl, 0, loc)
      }
    Shr =>
      if result_is_long_long {
        // unsigned long long 用逻辑右移
        if ty.is_unsigned() {
          self.emit(@opcode.OpCode::LShrQ, 0, loc)
        } else {
          self.emit(@opcode.OpCode::ShrQ, 0, loc)
        }
      } else if is_unsigned {
        self.emit(@opcode.OpCode::LShr, 0, loc)
      } else {
        self.emit(@opcode.OpCode::Shr, 0, loc)
      }
    // And/Or 已在上方短路结构处理，到不了这里（穷尽 match 的占位臂）
    And => ()
    Or => ()
    Comma => {
      // 丢弃左值保留右值
      self.emit(@opcode.OpCode::Swap, 0, loc)
      self.emit(@opcode.OpCode::Pop, 0, loc)
    }
  }
}
