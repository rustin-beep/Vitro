///|
/// #142 连坐（2026-10-18）：静态初始化器面的枚举常量 Ident 叶折叠。
///
/// 动机：文件作用域 / 函数内 static 的初始化器是常量表达式域
/// （C11 §6.6），枚举常量（§6.4.4.3）是合法叶子；但枚举成员落全局
/// VarDecl 后与普通 int 全局在 AST 上同形不可区分（#135 case 面同款
/// 结论），typeck 求值器查不了枚举表——在此（解析时点，作用域信息
/// 在手）折成 Literal，typeck 只见字面量。
///
/// 边界（照 #135 收窄教训）：**只折纯 Ident 叶子**（树形不变只换叶），
/// 不压平复合形态；`parsed_var_types` 已有同名（局部遮蔽——函数内
/// `int B = 3; static int x = B + 1;` 的 B 是变量）不折，防静默错值。
/// 文件作用域调用点天然无遮蔽（同名=重定义由 typeck 报）。

///|
/// 折一棵初始化器表达式树里的枚举常量 Ident 叶。
fn Parser::fold_enum_leaves(self : Parser, expr : @ast.Expr) -> @ast.Expr {
  match expr {
    Identifier(name, _, _) =>
      // 遮蔽判定：parsed_var_types 含外层+当前块的全部已声明名
      //（block 边界 rollback，parser.mbt/stmt.mbt:219 作用域屏障）；
      // 同名（局部变量或先前全局遮蔽 enum 常量）不折——折了=静默错值；
      // 不折则 typeck diagnose 按「Ident 命中变量」报 E3075，与 clang
      // 同口径（遮蔽名不是常量表达式）。
      if self.parsed_var_types.exists(t => t.0 == name) {
        expr
      } else {
        match self.enum_const_values.get(name) {
          Some(v) =>
            if v >= -2147483648 && v <= 2147483647 {
              @ast.Expr::Literal(
                @util.i64_to_i32_bits(v),
                expr.loc(),
                @ast.Type::int(),
              )
            } else {
              // 超 i32 域：LongLiteral（与 push_enum_member_global 同款）
              @ast.Expr::LongLiteral(v, expr.loc(), @ast.Type::long_long())
            }
          None => expr
        }
      }
    Binary(op, l, r, loc, ty) =>
      @ast.Expr::Binary(
        op,
        self.fold_enum_leaves(l),
        self.fold_enum_leaves(r),
        loc,
        ty,
      )
    Unary(op, inner, loc, ty) =>
      @ast.Expr::Unary(op, self.fold_enum_leaves(inner), loc, ty)
    Ternary(c, t, e, loc, ty) =>
      @ast.Expr::Ternary(
        self.fold_enum_leaves(c),
        self.fold_enum_leaves(t),
        self.fold_enum_leaves(e),
        loc,
        ty,
      )
    Cast(inner, target, loc, ty) =>
      @ast.Expr::Cast(self.fold_enum_leaves(inner), target, loc, ty)
    Assign(op, l, r, loc, ty) =>
      @ast.Expr::Assign(
        op,
        self.fold_enum_leaves(l),
        self.fold_enum_leaves(r),
        loc,
        ty,
      )
    Call(name, args, loc, ty) => {
      let folded : Array[@ast.Expr] = []
      for a in args {
        folded.push(self.fold_enum_leaves(a))
      }
      @ast.Expr::Call(name, folded, loc, ty)
    }
    CallPtr(callee, args, loc, ty) => {
      let folded_args : Array[@ast.Expr] = []
      for a in args {
        folded_args.push(self.fold_enum_leaves(a))
      }
      @ast.Expr::CallPtr(self.fold_enum_leaves(callee), folded_args, loc, ty)
    }
    Index(arr, idx, loc, ty) =>
      @ast.Expr::Index(
        self.fold_enum_leaves(arr),
        self.fold_enum_leaves(idx),
        loc,
        ty,
      )
    InitList(elements, loc, ty) => {
      let folded : Array[@ast.InitElement] = []
      for elem in elements {
        folded.push({ ..elem, value: self.fold_enum_leaves(elem.value), })
      }
      @ast.Expr::InitList(folded, loc, ty)
    }
    // 字面量 / Sizeof（类型面无 Ident 叶）/ Member·Addr·Deref（含
    // 地址常量子树——折里面的 Ident 会破坏 `&g` 形态，不动）等：原样
    _ => expr
  }
}

///|
/// 静态初始化器入口（Option 包装）：非 static 声明不折（局部运行时
/// 求值现状已正确——enum 物化全局运行时读值，探针 m142c 实证）。
/// 遮蔽判定：`parsed_var_types` 当前作用域快照已有同名时不折该叶。
fn Parser::fold_enum_in_static_init(
  self : Parser,
  init : @ast.Expr?,
  is_static : Bool,
) -> @ast.Expr? {
  if !is_static {
    return init
  }
  match init {
    Some(e) => Some(self.fold_enum_leaves(e))
    None => None
  }
}
