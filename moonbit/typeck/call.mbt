///|
/// 调用表达式解析（照搬 Rust `expr/call.rs` 的 C 面；**函数式重建**：
/// args 引用语义原地改写，callee/Call 节点由总入口重建）。
///
/// C++ 分支剔除登记（C AST 不产对应节点，分支不命中即等价；S9 C++ 片
/// 随批补）：resolve_call 的 `try_resolve_unqualified_method_call` 前段；
/// resolve_call_ptr 的方法解析 / 模板隐式实例化（CallPtr→Call 改写）/
/// lambda 变量调用 / lambda 立即调用四段；`resolve_member_call`/
/// `rewrite_lambda_call` 整函数（MemberCall/Lambda 为 C++ 变体）。

///|
/// 具名调用 `f(args)`：直接走 visit_call 分派（builtin 臂优先，兜底
/// check_user_func 四级回退）。
fn TypeChecker::resolve_call(
  self : TypeChecker,
  name : String,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  self.visit_call(name, args, loc)
}

///|
/// 指针调用 `fp(args)`：callee 是已知函数名 → visit_call 定型（CallPtr
/// 节点保留只定型 ty）；否则解析 callee——Pointer(Function)/Function
/// 直接做参数检查，通用指针 W3055 放行，非函数 E3066。
fn TypeChecker::resolve_call_ptr(
  self : TypeChecker,
  callee : @ast.Expr,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> (@ast.Type, @ast.Expr) {
  // 具名函数调用：identifier 是已知函数（funcs / static / builtin 放行集 /
  // std__ 前缀——C++ 糖名，C 模式不产但判据照搬）
  match callee {
    Identifier(name, _, _) => {
      let known = self.funcs.contains(name) ||
        self.static_func_sigs.contains(name) ||
        @libc.is_libc_func(name) ||
        (name.length() >= 5 && name[:5] == "std__")
      if known {
        let ty = self.visit_call(name, args, loc)
        return (ty, callee)
      }
    }
    _ => ()
  }
  // C++ method / 模板实例化 / lambda 三段剔除登记（见文件头）
  // 兜底：callee 按表达式解析
  let (callee_ty, new_callee) = self.resolve_expr_type(callee)
  let func_info : (Array[@ast.Type], @ast.Type)? = match callee_ty {
    Pointer(pointee, _) =>
      match pointee {
        Function(_, param_types, _, _) => {
          // Rust 语义：return_type 在 Pointer(Function) 臂由 pointee 取
          let ret = match pointee {
            Function(r, _, _, _) => r
            _ => @ast.Type::void_type()
          }
          Some((param_types, ret))
        }
        _ => {
          // Allow calling through generic pointer (with warning)
          self.report_warning(
            "通过通用指针调用函数，建议显式转换为函数指针",
            loc,
            W3055_VoidPointerCast,
          )
          for i in 0..<args.length() {
            let (_, new_arg) = self.resolve_expr_type(args[i])
            args[i] = new_arg
          }
          None
        }
      }
    Function(ret, param_types, _, _) =>
      // Support (*fp)(args) where callee type is Function directly
      Some((param_types, ret))
    _ => {
      self.report_error(
        "不能对非函数类型进行调用",
        loc,
        E3066_CallNonFunction,
      )
      for i in 0..<args.length() {
        let (_, new_arg) = self.resolve_expr_type(args[i])
        args[i] = new_arg
      }
      None
    }
  }
  let ty : @ast.Type = match func_info {
    Some((param_types, return_type)) => {
      if args.length() != param_types.length() {
        self.report_error(
          "函数指针调用参数数量不匹配：期望 \{param_types.length()}，实际 \{args.length()}",
          loc,
          E3037_FuncArgCount,
        )
      } else {
        for i in 0..<args.length() {
          let (arg_type, new_arg) = self.resolve_expr_type(args[i])
          args[i] = new_arg
          if !self.check_assignable(param_types[i], arg_type, loc) {
            self.report_error(
              "函数指针调用第 \{i + 1} 个参数类型不匹配",
              loc,
              E3038_FuncArgType,
            )
          } else {
            args[i] = insert_implicit_cast(new_arg, param_types[i])
          }
        }
      }
      return_type
    }
    None => @ast.Type::int()
  }
  (ty, new_callee)
}
