///|
/// 运算符类型解析（照搬 Rust `expr/ops.rs` 的 C 部分——二元/三目/一元/
/// 赋值/_Generic；函数式重建：返回定型类型与重建节点）。
///
/// 剔除登记（C++ 分支，C AST 不产即等价）：resolve_assign 的
/// MemberCall 左值与 Class const 成员检查（保留 Identifier/Index/Member/
/// Deref 四形态左值判定与指针 pointee-const E3065）。

///|
fn type_is_int_or_ll(t : @ast.Type) -> Bool {
  t.kind() is TK_Int || t.kind() is TK_Char || t.kind() is TK_LongLong
}

///|
/// 二元运算（19 op：算术 promote / 指针±整数 / 比较 int / 逻辑 / 位 /
/// 移位左提升 / 逗号右值）。
fn TypeChecker::resolve_binary(
  self : TypeChecker,
  op : @ast.BinaryOp,
  left : @ast.Expr,
  right : @ast.Expr,
  loc : @source.SourceLoc,
) -> (@ast.Type, @ast.Expr) {
  let (left_type, new_left) = self.resolve_expr_type(left)
  let (right_type, new_right) = self.resolve_expr_type(right)
  let ty : @ast.Type = match op {
    Add | Sub => {
      let left_is_ptrlike = left_type.kind() is TK_Pointer ||
        left_type.is_array()
      let right_is_ptrlike = right_type.kind() is TK_Pointer ||
        right_type.is_array()
      if self.is_scalar(left_type) && self.is_scalar(right_type) {
        promote_type(left_type, right_type)
      } else if left_is_ptrlike && self.is_int(right_type) {
        if left_type.is_array() {
          @ast.Type::pointer_to(left_type.subscript_type())
        } else {
          left_type
        }
      } else if self.is_int(left_type) && right_is_ptrlike && op is Add {
        if right_type.is_array() {
          @ast.Type::pointer_to(right_type.subscript_type())
        } else {
          right_type
        }
      } else if left_is_ptrlike && right_is_ptrlike && op is Sub {
        @ast.Type::int()
      } else {
        self.report_error(
          "算术运算要求两边都是 int 类型，或指针与整数",
          loc,
          E3016_ArithmeticTypeError,
        )
        @ast.Type::int()
      }
    }
    Mul | Div => {
      if !self.is_scalar(left_type) || !self.is_scalar(right_type) {
        self.report_error(
          "乘除运算要求两边都是 int 或 float 类型",
          loc,
          E3016_ArithmeticTypeError,
        )
      }
      promote_type(left_type, right_type)
    }
    Mod => {
      if !type_is_int_or_ll(left_type) || !type_is_int_or_ll(right_type) {
        self.report_error(
          "取模运算要求两边都是 int 类型",
          loc,
          E3016_ArithmeticTypeError,
        )
      }
      promote_type(left_type, right_type)
    }
    Eq | Ne => {
      if !self.is_comparable(left_type, right_type) {
        self.report_error(
          "类型不兼容，无法比较",
          loc,
          E3017_ComparisonTypeError,
        )
      }
      @ast.Type::int()
    }
    Lt | Le | Gt | Ge => {
      let left_is_ptrlike = left_type.kind() is TK_Pointer ||
        left_type.kind() is TK_Array
      let right_is_ptrlike = right_type.kind() is TK_Pointer ||
        right_type.kind() is TK_Array
      if !((self.is_scalar(left_type) && self.is_scalar(right_type)) ||
        (left_is_ptrlike && right_is_ptrlike)) {
        self.report_error(
          "关系运算要求两边都是 int/float 类型或同类型指针",
          loc,
          E3018_RelationTypeError,
        )
      }
      @ast.Type::int()
    }
    And | Or => {
      let left_ok = self.is_scalar(left_type) ||
        left_type.kind() is TK_Pointer ||
        left_type.is_array()
      let right_ok = self.is_scalar(right_type) ||
        right_type.kind() is TK_Pointer ||
        right_type.is_array()
      if !left_ok || !right_ok {
        self.report_error(
          "逻辑运算要求两边都是标量、指针或数组类型",
          loc,
          E3019_LogicTypeError,
        )
      }
      @ast.Type::int()
    }
    BitAnd | BitOr | BitXor => {
      // E1 B 档：放行 long long（E3048 半成品缺陷照搬——typeck 拒绝但
      // 算术族已有 Q 系列，属系统性误拒的一半）
      if !type_is_int_or_ll(left_type) || !type_is_int_or_ll(right_type) {
        self.report_error(
          "位运算要求两边都是整数类型",
          loc,
          E3048_BitOpTypeError,
        )
      }
      promote_type(left_type, right_type)
    }
    Shl | Shr => {
      if !type_is_int_or_ll(left_type) || !type_is_int_or_ll(right_type) {
        self.report_error(
          "位运算要求两边都是整数类型",
          loc,
          E3048_BitOpTypeError,
        )
      }
      // 结果 = 提升后的左操作数类型（C 语义：char 提升 int）
      if left_type.kind() is TK_Char {
        Int(left_type.is_unsigned(), false)
      } else {
        left_type
      }
    }
    Comma => right_type // 求值左侧弃结果，取右侧类型
  }
  (ty, Binary(op, new_left, new_right, loc, ty))
}

///|
/// 三目（条件标量/指针 E3020；分支 decay 后三判据一致——kind/name/
/// 判等，任一不一致 E3004；`" "` 与 `""` 统一 char* 的 decay 语义）。
fn TypeChecker::resolve_ternary(
  self : TypeChecker,
  cond : @ast.Expr,
  then_branch : @ast.Expr,
  else_branch : @ast.Expr,
  loc : @source.SourceLoc,
) -> (@ast.Type, @ast.Expr) {
  let (cond_type, new_cond) = self.resolve_expr_type(cond)
  if !self.is_scalar(cond_type) &&
    !(cond_type.kind() is TK_Pointer || cond_type.kind() is TK_Array) {
    self.report_error(
      "三目运算符条件必须是 int、float 或指针类型",
      loc,
      E3020_UnaryTypeError,
    )
  }
  let (then_type, new_then) = self.resolve_expr_type(then_branch)
  let (else_type, new_else) = self.resolve_expr_type(else_branch)
  // 数组在大多数表达式中退化为指向首元素的指针
  fn decay(t : @ast.Type) -> @ast.Type {
    match t {
      Array(element, _, _, _, _, _) => @ast.Type::pointer_to(element)
      _ => t
    }
  }
  let then_decayed = decay(then_type)
  let else_decayed = decay(else_type)
  if then_decayed.kind() != else_decayed.kind() ||
    then_decayed.name() != else_decayed.name() ||
    !@ast.type_eq(then_decayed, else_decayed) {
    self.report_error(
      "三目运算符分支类型不匹配",
      loc,
      E3004_TypeMismatch,
    )
  }
  (then_decayed, Ternary(new_cond, new_then, new_else, loc, then_decayed))
}

///|
/// 一元（9 op：取负宽度保留 / 逻辑非 / 按位取反随宽 / 取址 / 解引用 /
/// 自增自减左值同型——T-P0-3 放行 long long/char/double/float/指针）。
fn TypeChecker::resolve_unary(
  self : TypeChecker,
  op : @ast.UnaryOp,
  operand : @ast.Expr,
  loc : @source.SourceLoc,
) -> (@ast.Type, @ast.Expr) {
  let (operand_type, new_operand) = self.resolve_expr_type(operand)
  let ty : @ast.Type = match op {
    Neg => {
      if !self.is_scalar(operand_type) {
        self.report_error(
          "取负运算要求操作数是 int 或 float 类型",
          loc,
          E3020_UnaryTypeError,
        )
      }
      if operand_type.kind() is TK_Double {
        @ast.Type::double()
      } else if operand_type.kind() is TK_Float {
        @ast.Type::float()
      } else if operand_type.kind() is TK_LongLong {
        @ast.Type::long_long()
      } else if operand_type.is_unsigned() {
        @ast.Type::unsigned_int()
      } else {
        @ast.Type::int()
      }
    }
    Not => {
      if !self.is_scalar(operand_type) &&
        !(operand_type.kind() is TK_Pointer) &&
        !operand_type.is_array() {
        self.report_error(
          "逻辑非要求操作数是标量、指针或数组类型",
          loc,
          E3020_UnaryTypeError,
        )
      }
      @ast.Type::int()
    }
    BitNot => {
      // E1 B 档：放行 long long（同 E3048 半成品缺陷照搬）；结果随操作数宽度
      if !type_is_int_or_ll(operand_type) {
        self.report_error(
          "按位取反要求操作数是整数类型",
          loc,
          E3020_UnaryTypeError,
        )
      }
      if operand_type.kind() is TK_LongLong {
        operand_type
      } else {
        @ast.Type::int()
      }
    }
    Addr => @ast.Type::pointer_to(operand_type)
    Deref =>
      if !(operand_type.kind() is TK_Pointer) && !operand_type.is_array() {
        self.report_error(
          "解引用要求指针类型",
          loc,
          E3021_DerefNonPointer,
        )
        @ast.Type::int()
      } else {
        match operand_type {
          Pointer(pointee, _) => pointee
          Array(element, _, _, _, _, _) => element
          _ => @ast.Type::int()
        }
      }
    PreInc | PreDec | PostInc | PostDec => {
      // T-P0-3/T-P1-3：允许 long long（is_int 不含 LongLong 曾系统性
      // 误拒）；char 数组元素/成员自增的元素类型是 Char，同样按整数放行
      if !self.is_int(operand_type) &&
        !(operand_type.kind() is TK_Char) &&
        !(operand_type.kind() is TK_Float) &&
        !(operand_type.kind() is TK_Double) &&
        !(operand_type.kind() is TK_LongLong) &&
        !(operand_type.kind() is TK_Pointer) {
        self.report_error(
          "自增/自减要求数值类型或指针类型",
          loc,
          E3022_IncDecTypeError,
        )
      }
      match new_operand {
        @ast.Expr::Identifier(name, _, _) =>
          match self.lookup_var(name) {
            Some(sym) =>
              if sym.ty.is_const() {
                self.report_error(
                  "不能修改常量变量 '\{name}'",
                  loc,
                  E3049_AssignToConst,
                )
              }
            None => ()
          }
        _ => ()
      }
      // C 语义：++/-- 的结果是左值，类型与操作数相同（此前非指针一律
      // int，导致 ++doubleVar 作为 printf %f 实参被误报）
      operand_type
    }
  }
  (ty, Unary(op, new_operand, loc, ty))
}

///|
/// 赋值（左值四形态判定 E3043 + const 三面 E3049/E3065 + 指针复合赋值
/// 特判 + check_assignable/insert_implicit_cast——右先解析再左，Rust 序）。
fn TypeChecker::resolve_assign(
  self : TypeChecker,
  op : @ast.AssignOp,
  left : @ast.Expr,
  right : @ast.Expr,
  loc : @source.SourceLoc,
) -> (@ast.Type, @ast.Expr) {
  let (right_type, new_right_pre) = self.resolve_expr_type(right)
  let (left_type, new_left) = self.resolve_expr_type(left)
  // 左值判定（C++ 的 Call/CallPtr/MemberCall 引用返回剔除登记）
  let is_lvalue = match new_left {
    Identifier(_, _, _) => true
    Index(_, _, _, _) => true
    Member(_, _, _, _) => true
    Unary(Deref, _, _, _) => true
    _ => false
  }
  if !is_lvalue {
    self.report_error(
      "赋值左边必须是可修改的左值",
      loc,
      E3043_AssignToRValue,
    )
  }
  match new_left {
    @ast.Expr::Identifier(name, _, _) =>
      match self.lookup_var(name) {
        Some(sym) =>
          if sym.ty.is_const() {
            self.report_error(
              "不能给常量变量 '\{name}' 赋值",
              loc,
              E3049_AssignToConst,
            )
          }
        None => ()
      }
    _ => ()
  }
  match new_left {
    Unary(Deref, operand, _, _) =>
      match operand.ty() {
        Pointer(pointee, _) =>
          if pointee.is_const() {
            self.report_error(
              "不能通过非 const 指针修改 const 数据",
              loc,
              E3065_ConstViolation,
            )
          }
        _ => ()
      }
    _ => ()
  }
  //（Member 的 Class const 成员检查为 C++ 剔除登记）
  let is_ptr_compound = op is AddAssign || op is SubAssign
  let left_is_ptr = left_type.kind() is TK_Pointer
  let left_is_func_ptr = is_function_pointer(left_type)
  let right_is_int = self.is_int(right_type) || right_type.kind() is TK_LongLong
  let ptr_compound_ok = is_ptr_compound &&
    left_is_ptr &&
    !left_is_func_ptr &&
    right_is_int
  let new_right : @ast.Expr = if ptr_compound_ok {
    // 指针 +=/-= 整数：跳过普通赋值兼容性检查，右侧保持整数类型
    new_right_pre
  } else if !self.check_assignable(left_type, right_type, loc) {
    self.report_error(
      "类型不匹配：无法将 '\{right_type.to_c_string()}' 赋值给 '\{left_type.to_c_string()}'",
      loc,
      E3044_AssignTypeMismatch,
    )
    new_right_pre
  } else {
    insert_implicit_cast(new_right_pre, left_type)
  }
  if !(op is Assign) {
    if ptr_compound_ok {
      // 指针与整数的 +=/-= 已允许
      ()
    } else if left_is_ptr {
      let msg = if is_ptr_compound && left_is_func_ptr {
        "函数指针不支持算术运算"
      } else if is_ptr_compound && !right_is_int {
        "指针的复合赋值要求右侧为整数类型"
      } else {
        "指针不支持此复合赋值运算符"
      }
      self.report_error(msg, loc, E3045_CompoundAssignType)
    } else if !self.is_scalar(left_type) || !self.is_scalar(right_type) {
      self.report_error(
        "复合赋值要求两边都是标量类型（int、float、double 或 long long）",
        loc,
        E3045_CompoundAssignType,
      )
    }
  }
  (left_type, Assign(op, new_left, new_right, loc, left_type))
}

///|
/// _Generic（控制表达式 decay 后按判等选关联；无匹配走 default；双缺
/// E3004——数组退化使字符串字面量能匹配 char* 关联）。
fn TypeChecker::resolve_generic(
  self : TypeChecker,
  control : @ast.Expr,
  associations : Array[(@ast.Type, @ast.Expr)],
  default : @ast.Expr?,
  loc : @source.SourceLoc,
) -> (@ast.Type, @ast.Expr) {
  let (control_type, new_control) = self.resolve_expr_type(control)
  let control_decayed : @ast.Type = match control_type {
    Array(element, _, _, _, _, _) => @ast.Type::pointer_to(element)
    _ => control_type
  }
  // 选中的关联（判等命中即止——未选中的**不解析**，Rust iter_mut 同构；
  // 选中的 resolve 后写回数组元素）
  let mut hit : Int = -1
  for i in 0..<associations.length() {
    if @ast.type_eq(associations[i].0, control_decayed) {
      hit = i
      break
    }
  }
  let (result_ty, new_default) : (@ast.Type, @ast.Expr?) = if hit >= 0 {
    let (t, e) = self.resolve_expr_type(associations[hit].1)
    associations[hit] = (associations[hit].0, e)
    (t, default)
  } else {
    match default {
      Some(d) => {
        let (t, e) = self.resolve_expr_type(d)
        (t, Some(e))
      }
      None => {
        self.report_error(
          "_Generic 控制表达式类型无匹配关联且无 default 分支",
          loc,
          E3004_TypeMismatch,
        )
        (@ast.Type::int(), None)
      }
    }
  }
  (result_ty, Generic(new_control, associations, new_default, loc, result_ty))
}
