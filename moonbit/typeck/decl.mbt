///|
/// 函数体检查（照搬 Rust `decl.rs` 的 visit_func_decl/dispatch_stmt/
/// check_user_func 族 + `decl_types.rs` 的 auto/typeof 推导 + `cpp_auto.rs`
/// deduce_auto_type 的 **C 子集** + `convert.rs` 的
/// expr_involves_array_or_pointer）。**函数式重建**：Stmt/FuncDecl 值进
/// 值出（VarDecl 的类型替换与数组尺寸推断经返回值回传，E4 面对齐）。
///
/// C++ 分支剔除登记（C AST 不产对应节点/条件恒 false，分支不命中即
/// 等价；S9 C++ 片随批补）：try_process_ctor_init 全函数（`__ctor__` 名
/// 与 is_class() 判据 C 恒 false——VarDecl 巨臂的 is_ctor_init 恒 false，
/// declare_var 因此恒在 init 处理后执行）；resolve_template_id；
/// check_user_func 第三级模板隐式实例化；deduce_auto_type 的 New/Lambda/
/// MemberCall 臂；visit_func_decl_with_fields（类字段预注册版本）；
/// evaluate_constexpr（非类型模板参数求值）；check_and_adjust_call_args
/// 的引用绑定段（Reference 形参 C 不产）。VarDecl 巨臂的 Call-init 分支
/// 与 else 分支对 C 面等价（唯一差异 `__ctor__ && is_class` 恒
/// false）——合并为单一 else 路径。

///|
/// 函数声明检查：形参登记 + 函数体 dispatch + goto/label 闭合检查。
/// 返回改写后的 FuncDecl（body 内 lowering 回传）。
fn TypeChecker::visit_func_decl(
  self : TypeChecker,
  node : @ast.FuncDecl,
) -> @ast.FuncDecl {
  self.current_file = node.source_file
  self.current_func_return = Some(node.return_type)
  self.current_func_params.clear()
  self.func_labels.clear()
  self.pending_gotos.clear()
  self.enter_scope()
  for p in node.params {
    self.current_func_params.add(p.name)
    self.declare_var(
      p.name,
      p.ty,
      is_global=false,
      is_extern=false,
      is_static=false,
    )
  }
  let new_body : @ast.Stmt? = match node.body {
    Some(body) => Some(self.dispatch_stmt(body))
    None => None
  }
  let unresolved : Array[(String, @source.SourceLoc)] = []
  for pair in self.pending_gotos {
    if !self.func_labels.contains(pair.0) {
      unresolved.push(pair)
    }
  }
  for pair in unresolved {
    self.report_error(
      "goto 目标标签 '\{pair.0}' 未定义",
      pair.1,
      E3071_UndefinedLabel,
    )
  }
  self.pending_gotos.clear()
  self.func_labels.clear()
  self.exit_scope()
  self.current_func_params.clear()
  { ..node, body: new_body, }
}

///|
/// 语句分派（C 子集 14 变体；RangeFor 为 C++ 剔除登记直通，Try 照搬
/// E4001 拒绝——reserved-for-csharp，C 解析路径不产）。
fn TypeChecker::dispatch_stmt(
  self : TypeChecker,
  stmt : @ast.Stmt,
) -> @ast.Stmt {
  match stmt {
    Block(stmts, loc) => {
      self.enter_scope()
      for i in 0..<stmts.length() {
        stmts[i] = self.dispatch_stmt(stmts[i])
      }
      self.exit_scope()
      Block(stmts, loc)
    }
    VarDecl(var_type, name, init, extra_vars, is_static, loc) => {
      let (new_ty, new_init) = self.process_var_decl(
        var_type,
        name,
        init,
        loc,
        is_static~,
      )
      // extra_vars 逐个处理（同主路径；declare 无 static 轨——Rust 同形）
      let processed_extras : Array[@ast.VarDeclExtra] = []
      for extra in extra_vars {
        let (ety, einit) = self.process_var_decl(
          extra.var_type,
          extra.name,
          extra.init,
          loc,
          is_static=false,
        )
        processed_extras.push({ var_type: ety, name: extra.name, init: einit, })
      }
      VarDecl(new_ty, name, new_init, processed_extras, is_static, loc)
    }
    Expr(expr, loc) => {
      let (_, new_expr) = self.resolve_expr_type(expr)
      Expr(new_expr, loc)
    }
    If(cond, then_stmt, else_stmt, loc) => {
      let new_cond = self.check_condition(cond, "if 条件", loc)
      let new_then = self.dispatch_stmt(then_stmt)
      let new_else = match else_stmt {
        Some(e) => Some(self.dispatch_stmt(e))
        None => None
      }
      If(new_cond, new_then, new_else, loc)
    }
    While(cond, body, loc) => {
      let new_cond = self.check_condition(cond, "while 条件", loc)
      self.loop_depth += 1
      let new_body = self.dispatch_stmt(body)
      self.loop_depth -= 1
      While(new_cond, new_body, loc)
    }
    DoWhile(body, cond, loc) => {
      self.loop_depth += 1
      let new_body = self.dispatch_stmt(body)
      self.loop_depth -= 1
      let new_cond = self.check_condition(cond, "do...while 条件", loc)
      DoWhile(new_body, new_cond, loc)
    }
    For(init, cond, step, body, loc) => {
      self.enter_scope()
      let new_init : @ast.Stmt? = match init {
        Some(i) => Some(self.dispatch_stmt(i))
        None => None
      }
      let new_cond : @ast.Expr? = match cond {
        Some(c) => {
          let nc = self.check_condition(c, "for 条件", loc)
          // W3051：for 条件 Le + 数组/指针参与 → off-by-one 提示
          match nc {
            Binary(Le, left, right, _, _) =>
              if self.expr_involves_array_or_pointer(left) ||
                self.expr_involves_array_or_pointer(right) {
                self.report_warning(
                  "循环条件中使用了 '<='，如果用于数组索引，可能导致越界（off-by-one 错误）。你是否想使用 '<'？",
                  loc,
                  W3051_ArrayBoundOffByOne,
                )
              }
            _ => ()
          }
          Some(nc)
        }
        None => None
      }
      for i in 0..<step.length() {
        let (_, s) = self.resolve_expr_type(step[i])
        step[i] = s
      }
      self.loop_depth += 1
      let new_body = self.dispatch_stmt(body)
      self.loop_depth -= 1
      self.exit_scope()
      For(new_init, new_cond, step, new_body, loc)
    }
    Return(value, loc) => {
      // current_func_return 在 visit_func_decl 必先设值（None 不可达，
      // 兜底按非 void 处理）
      let is_void = match self.current_func_return {
        Some(t) => t.kind() is TK_Void
        None => false
      }
      let new_value : @ast.Expr? = if is_void {
        if value is Some(_) {
          self.report_error(
            "void 函数不能有返回值",
            loc,
            E3012_VoidFuncReturnValue,
          )
        }
        value
      } else {
        match value {
          Some(v) => {
            let (val_type, new_v) = self.resolve_expr_type(v)
            let expected = match self.current_func_return {
              Some(t) => t
              None => @ast.Type::int()
            }
            if !self.check_assignable(expected, val_type, loc) {
              let shown = match self.current_func_return {
                Some(t) => t.to_c_string()
                None => "int"
              }
              self.report_error(
                "返回类型不匹配：期望 '\{shown}'，实际 '\{val_type.to_c_string()}'",
                loc,
                E3014_ReturnTypeMismatch,
              )
              Some(new_v)
            } else {
              Some(insert_implicit_cast(new_v, expected))
            }
          }
          None => {
            self.report_error(
              "非 void 函数必须返回一个值",
              loc,
              E3013_MissingReturnValue,
            )
            None
          }
        }
      }
      Return(new_value, loc)
    }
    Break(loc) => {
      if self.loop_depth <= 0 && self.switch_depth <= 0 {
        self.report_error(
          "break 只能在循环或 switch 体内使用",
          loc,
          E3010_BreakOutsideLoop,
        )
      }
      Break(loc)
    }
    Continue(loc) => {
      if self.loop_depth <= 0 {
        self.report_error(
          "continue 只能在循环体内使用",
          loc,
          E3011_ContinueOutsideLoop,
        )
      }
      Continue(loc)
    }
    Switch(cond, body, loc) => {
      self.switch_depth += 1
      let (cond_type, new_cond) = self.resolve_expr_type(cond)
      if !self.is_int(cond_type) {
        self.report_error(
          "switch 条件必须是整数类型",
          loc,
          E3046_SwitchCondType,
        )
      }
      let new_body = self.dispatch_stmt(body)
      self.switch_depth -= 1
      Switch(new_cond, new_body, loc)
    }
    Case(label, stmt, loc) => {
      let new_label : @ast.Expr? = match label {
        Some(l) => {
          let (label_type, new_l) = self.resolve_expr_type(l)
          if !self.is_int(label_type) {
            self.report_error(
              "case 标签必须是整数常量",
              loc,
              E3047_CaseNotConstant,
            )
          }
          Some(new_l)
        }
        None => None
      }
      let new_stmt = self.dispatch_stmt(stmt)
      Case(new_label, new_stmt, loc)
    }
    Goto(label, loc) => {
      if !self.func_labels.contains(label) {
        self.pending_gotos.push((label, loc))
      }
      Goto(label, loc)
    }
    Label(label, stmt, loc) => {
      if self.func_labels.contains(label) {
        self.report_error(
          "标签 '\{label}' 重复定义",
          loc,
          E3001_VarRedeclared,
        )
      } else {
        self.func_labels.set(label, loc)
      }
      let new_stmt = self.dispatch_stmt(stmt)
      Label(label, new_stmt, loc)
    }
    RangeFor(_, _, _, _, _) =>
      // C++ 范围 for——C AST 不产（剔除登记，S9）；直通
      stmt
    Try(_, _, loc) => {
      self.report_error(
        "try/catch 异常处理不被支持",
        loc,
        E4001_ExceptionNotSupported,
      )
      stmt
    }
  }
}

///|
/// 条件检查：标量/指针/数组合法性 E3015 + 赋值表达式 W3050（直接
/// 赋值 / 二元运算两侧赋值两形态）。
fn TypeChecker::check_condition(
  self : TypeChecker,
  cond : @ast.Expr,
  ctx : String,
  loc : @source.SourceLoc,
) -> @ast.Expr {
  let (ty, new_cond) = self.resolve_expr_type(cond)
  if !self.is_scalar(ty) &&
    !(ty.kind() is TK_Pointer) &&
    !(ty.kind() is TK_Array) {
    self.report_error(
      "\{ctx} 必须是整数、浮点数或指针类型",
      loc,
      E3015_InvalidCondition,
    )
  }
  match new_cond {
    Assign(@ast.AssignOp::Assign, _, _, _, _) =>
      self.report_warning(
        "条件中使用了赋值运算符 '='，你是否想使用比较运算符 '=='？",
        loc,
        W3050_AssignInCondition,
      )
    Binary(_, left, right, _, _) =>
      if left is Assign(@ast.AssignOp::Assign, _, _, _, _) ||
        right is Assign(@ast.AssignOp::Assign, _, _, _, _) {
        self.report_warning(
          "条件中包含了赋值表达式，你是否想使用比较运算符 '=='？",
          loc,
          W3050_AssignInCondition,
        )
      }
    _ => ()
  }
  new_cond
}

///|
/// 单个变量声明处理（VarDecl 巨臂主体：auto/typeof 推导 → dims 检查 →
/// 初始化器四分支 → declare_var）。返回 (替换后类型, 改写后 init)。
/// extra_vars 不在此处理（dispatch_stmt 逐个调本函数——同主路径语义）。
fn TypeChecker::process_var_decl(
  self : TypeChecker,
  var_type : @ast.Type,
  name : String,
  init : @ast.Expr?,
  loc : @source.SourceLoc,
  is_static~ : Bool,
) -> (@ast.Type, @ast.Expr?) {
  ignore(name)
  // Auto type deduction（C++ auto / C 语法兼容路径照搬）
  let var_type_1 : @ast.Type = if type_has_auto(var_type) {
    match init {
      Some(init_expr) => {
        let deduced = self.deduce_auto_type(init_expr)
        replace_auto_in_type(var_type, deduced)
      }
      None => {
        self.report_error(
          "auto 类型变量必须有初始化表达式",
          loc,
          E4025_AutoRequiresInitializer,
        )
        replace_auto_in_type(var_type, @ast.Type::int())
      }
    }
  } else {
    var_type
  }
  // resolve_template_id：C++ 模板实例化（剔除登记，S9）
  // typeof type deduction
  let var_type_2 : @ast.Type = if type_has_typeof(var_type_1) {
    match init {
      Some(init_expr) => {
        let (deduced, _) = self.resolve_expr_type(init_expr)
        resolve_typeof_in_type(var_type_1, deduced)
      }
      None =>
        match var_type_1 {
          Typeof(expr, _, _) => {
            // 需要临时取出表达式来推断类型（resolve 改写丢弃——Typeof
            // 节点内的 expr 不更新，Rust 同形）
            let (deduced, _) = self.resolve_expr_type(expr)
            resolve_typeof_in_type(var_type_1, deduced)
          }
          _ => resolve_typeof_in_type(var_type_1, @ast.Type::int())
        }
    }
  } else {
    var_type_1
  }
  // 只有 C++ 构造函数初始化需要提前声明变量（try_process_ctor_init——
  // 剔除登记，C 恒 false：普通变量（尤其数组）必须在初始化处理后声明，
  // 否则符号表类型无法反映 check_array_initializer 推断的尺寸）
  // U1#12：数组尺寸合法性（负/零/缺尺寸且无初始化器）——has_init_list
  // = true 时允许 `int t[]={...}` 推断尺寸；StringLiteral（char s[]=
  // "..."）同样可推断，不得误拒
  if var_type_2.is_array() {
    let has_init_list = init is Some(InitList(_, _, _)) ||
      init is Some(StringLiteral(_, _, _))
    self.check_array_dims_legality(var_type_2, has_init_list, loc)
  }
  // 初始化器四分支（Call-init 分支与 else 对 C 等价合并——文件头登记）
  let (final_ty, new_init) : (@ast.Type, @ast.Expr?) = match init {
    Some(init_expr) =>
      if var_type_2.is_array() {
        let (t, i) = self.check_array_initializer(var_type_2, init_expr, loc)
        (t, Some(i))
      } else if var_type_2.kind() is TK_Struct && init_expr is InitList(_, _, _) {
        let i = self.check_struct_initializer(var_type_2, init_expr, loc)
        (var_type_2, Some(i))
      } else {
        // W0-4：char 变量的字符常量/值域内整常量初始化是 C 惯用写法，豁免窄化警告
        let (init_type, resolved) = self.resolve_expr_type(init_expr)
        let suppress = var_type_2.kind() is TK_Char &&
          is_char_safe_initializer(resolved)
        if suppress {
          self.char_narrow_suppress = true
        }
        let assignable = self.check_assignable(var_type_2, init_type, loc)
        if suppress {
          self.char_narrow_suppress = false
        }
        if !assignable {
          self.report_error(
            "类型不匹配：无法将 '\{init_type.to_c_string()}' 赋值给 '\{var_type_2.to_c_string()}'",
            loc,
            E3004_TypeMismatch,
          )
          (var_type_2, Some(resolved))
        } else {
          // C++ reference binding lvalue check（剔除登记——Reference C 不产）
          (var_type_2, Some(insert_implicit_cast(resolved, var_type_2)))
        }
      }
    None => (var_type_2, None)
  }
  self.declare_var(name, final_ty, is_global=false, is_extern=false, is_static~)
  (final_ty, new_init)
}

///|
/// 函数调用实参检查（类型检查 + 隐式转换插入；引用参数隐式取地址为
/// C++ 剔除登记）。
fn TypeChecker::check_and_adjust_call_args(
  self : TypeChecker,
  name : String,
  param_types : Array[@ast.Type],
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> Unit {
  let count = if args.length() < param_types.length() {
    args.length()
  } else {
    param_types.length()
  }
  for i in 0..<count {
    let (arg_type, new_arg) = self.resolve_expr_type(args[i])
    args[i] = new_arg
    if !self.check_assignable(param_types[i], arg_type, loc) {
      self.report_error(
        "函数 '\{name}' 第 \{i + 1} 个参数类型不匹配",
        loc,
        E3038_FuncArgType,
      )
    } else {
      args[i] = insert_implicit_cast(new_arg, param_types[i])
    }
  }
}

///|
/// 用户函数检查四级回退（Rust `check_user_func` 同构；第三级模板隐式
/// 实例化为 C++ 剔除登记）：funcs → static_func_sigs（E3058 跨文件
/// 可见性）→ bytecode_libc_sig 表 → E3036。
fn TypeChecker::check_user_func(
  self : TypeChecker,
  name : String,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  match self.funcs.get(name) {
    Some(sym) => {
      let filled = self.try_fill_default_args(args, sym.param_defaults)
      if !filled ||
        args.length() < sym.param_types.length() ||
        (args.length() != sym.param_types.length() && !sym.is_variadic) {
        self.report_error(
          "函数 '\{name}' 参数数量不匹配：期望 \{sym.param_types.length()}，实际 \{args.length()}",
          loc,
          E3037_FuncArgCount,
        )
      } else {
        self.check_and_adjust_call_args(name, sym.param_types, args, loc)
        if sym.is_variadic {
          for i in sym.param_types.length()..<args.length() {
            let (_, new_arg) = self.resolve_expr_type(args[i])
            args[i] = apply_default_argument_promotions(new_arg)
          }
        }
      }
      sym.return_type
    }
    None =>
      match self.static_func_sigs.get(name) {
        Some(sym) => {
          match self.static_func_files.get(name) {
            Some(files) =>
              if !files.contains(self.current_file) {
                self.report_error(
                  "static 函数 '\{name}' 在其他文件中不可见",
                  loc,
                  E3058_StaticFuncAccess,
                )
                return @ast.Type::void_type()
              }
            None => ()
          }
          let filled = self.try_fill_default_args(args, sym.param_defaults)
          if !filled ||
            args.length() < sym.param_types.length() ||
            (args.length() != sym.param_types.length() && !sym.is_variadic) {
            self.report_error(
              "函数 '\{name}' 参数数量不匹配：期望 \{sym.param_types.length()}，实际 \{args.length()}",
              loc,
              E3037_FuncArgCount,
            )
          } else {
            self.check_and_adjust_call_args(name, sym.param_types, args, loc)
            if sym.is_variadic {
              for i in sym.param_types.length()..<args.length() {
                let (_, new_arg) = self.resolve_expr_type(args[i])
                args[i] = apply_default_argument_promotions(new_arg)
              }
            }
          }
          sym.return_type
        }
        None =>
          // 模板隐式实例化（第三级）——C++ 剔除登记
          // 第四级：Bytecode Libc 函数在 codegen 期预注册（表照搬自
          // Rust bytecode_libc_sig——N4 漂移登记见 libc 包）
          match @libc.bytecode_libc_sig(name) {
            Some((ret_ty, param_types)) => {
              if args.length() != param_types.length() {
                self.report_error(
                  "函数 '\{name}' 参数数量不匹配：期望 \{param_types.length()}，实际 \{args.length()}",
                  loc,
                  E3037_FuncArgCount,
                )
              } else {
                for i in 0..<param_types.length() {
                  let (arg_type, new_arg) = self.resolve_expr_type(args[i])
                  args[i] = new_arg
                  if !self.check_assignable(param_types[i], arg_type, loc) {
                    self.report_error(
                      "函数 '\{name}' 第 \{i + 1} 个参数类型不匹配",
                      loc,
                      E3038_FuncArgType,
                    )
                  } else {
                    args[i] = insert_implicit_cast(new_arg, param_types[i])
                  }
                }
              }
              ret_ty
            }
            None => {
              self.report_error(
                "未定义的函数 '\{name}'",
                loc,
                E3036_UndefinedFunc,
              )
              @ast.Type::void_type()
            }
          }
      }
  }
}

///|
/// 若 args 长度不足且缺失的尾部参数均有默认值，则把默认参数表达式
/// 追加到 args 中（C 子集 param_defaults 恒空——照搬通用形态）。
fn TypeChecker::try_fill_default_args(
  self : TypeChecker,
  args : Array[@ast.Expr],
  param_defaults : Array[@ast.Expr?],
) -> Bool {
  ignore(self)
  if args.length() >= param_defaults.length() {
    return true
  }
  // 只允许尾部缺失，中间缺失视为不匹配
  for d in param_defaults[args.length():] {
    if d is None {
      return false
    }
  }
  for d in param_defaults[args.length():] {
    match d {
      Some(expr) => args.push(expr)
      None => continue // D14：尾部默认参数必有值——跳过而非 panic
    }
  }
  true
}

// ---------- auto / typeof 类型推导（Rust decl_types.rs 照搬）----------

///|
/// 类型树中含 Auto（指针/数组包裹递归；Reference/RValueRef 为 C++ 变体
/// 剔除——C 类型不产）。
fn type_has_auto(ty : @ast.Type) -> Bool {
  match ty {
    Auto => true
    Pointer(pointee, _) => type_has_auto(pointee)
    Array(element, _, _, _, _, _) => type_has_auto(element)
    _ => false
  }
}

///|
/// 类型树中含 Typeof。
fn type_has_typeof(ty : @ast.Type) -> Bool {
  match ty {
    Typeof(_, _, _) => true
    Pointer(pointee, _) => type_has_typeof(pointee)
    Array(element, _, _, _, _, _) => type_has_typeof(element)
    _ => false
  }
}

///|
/// C23 typeof_unqual：剥离**顶层**限定符（const/volatile 语义在教学
/// 子集仅建模 is_const）；嵌套层保持不变——typeof_unqual 与 typeof 的
/// 唯一区别。
fn strip_top_level_qualifiers(ty : @ast.Type) -> @ast.Type {
  ty.set_const(false)
}

///|
/// 将类型树中的 Typeof 节点替换为 replacement（嵌套递归；unqual 先剥
/// 顶层限定符再套 is_const——C23 typeof_unqual）。
fn resolve_typeof_in_type(ty : @ast.Type, replacement : @ast.Type) -> @ast.Type {
  match ty {
    Typeof(_, is_const, unqual) => {
      let mut t = replacement
      if unqual {
        t = strip_top_level_qualifiers(t)
      }
      t.set_const(is_const)
    }
    Pointer(pointee, is_const) =>
      Pointer(resolve_typeof_in_type(pointee, replacement), is_const)
    Array(element, array_size, dims, is_const, is_vla, vla_dims) =>
      Array(
        resolve_typeof_in_type(element, replacement),
        array_size,
        dims,
        is_const,
        is_vla,
        vla_dims,
      )
    _ => ty
  }
}

///|
/// 将类型树中的 Auto 节点替换为 replacement（嵌套递归）。
fn replace_auto_in_type(ty : @ast.Type, replacement : @ast.Type) -> @ast.Type {
  match ty {
    Auto => replacement
    Pointer(pointee, is_const) =>
      Pointer(replace_auto_in_type(pointee, replacement), is_const)
    Array(element, array_size, dims, is_const, is_vla, vla_dims) =>
      Array(
        replace_auto_in_type(element, replacement),
        array_size,
        dims,
        is_const,
        is_vla,
        vla_dims,
      )
    _ => ty
  }
}

///|
/// 推导 auto 初始化表达式的具体类型（Rust `cpp_auto.rs` 的 **C 子集**
/// 照搬：New/Lambda/MemberCall 臂剔除——C AST 不产；推导为纯定型，
/// 不改写表达式）。
fn TypeChecker::deduce_auto_type(
  self : TypeChecker,
  init : @ast.Expr,
) -> @ast.Type {
  match init {
    Literal(_, _, _) => @ast.Type::int()
    // E1：auto 按字面量后缀定型（无后缀 double，f/F 后缀 float）
    FloatLiteral(_, _, ty) =>
      if ty.kind() is TK_Double {
        @ast.Type::double()
      } else {
        @ast.Type::float()
      }
    LongLiteral(_, _, _) => @ast.Type::long_long()
    StringLiteral(_, _, _) => @ast.Type::pointer_to(@ast.Type::char())
    Identifier(name, loc, _) =>
      match self.lookup_var(name) {
        Some(sym) => sym.ty
        None => {
          self.report_error(
            "auto 推导失败：未找到变量 '\{name}'",
            loc,
            E3004_TypeMismatch,
          )
          @ast.Type::int()
        }
      }
    Call(_, _, _, ty) => ty
    Unary(op, operand, loc, _) =>
      match op {
        Addr => @ast.Type::pointer_to(self.deduce_auto_type(operand))
        Deref => {
          let inner = self.deduce_auto_type(operand)
          match inner {
            Pointer(pointee, _) => pointee
            _ => {
              self.report_error(
                "auto 推导失败：解引用非指针类型",
                loc,
                E3004_TypeMismatch,
              )
              @ast.Type::int()
            }
          }
        }
        Neg | BitNot | Not | PostInc | PostDec | PreInc | PreDec =>
          self.deduce_auto_type(operand)
      }
    Binary(_, left, right, _, _) => {
      let left_ty = self.deduce_auto_type(left)
      let right_ty = self.deduce_auto_type(right)
      // Prefer the wider of the two scalar types
      if left_ty.kind() is TK_Double || right_ty.kind() is TK_Double {
        @ast.Type::double()
      } else if left_ty.kind() is TK_Float || right_ty.kind() is TK_Float {
        @ast.Type::float()
      } else if left_ty.kind() is TK_LongLong || right_ty.kind() is TK_LongLong {
        @ast.Type::long_long()
      } else {
        left_ty
      }
    }
    Cast(_, target_type, _, _) => target_type
    Ternary(_, then_branch, _, _, _) => self.deduce_auto_type(then_branch)
    Member(_, _, _, ty) => ty
    Index(_, _, _, ty) => ty
    InitList(_, loc, _) => {
      self.report_error(
        "auto 推导失败：初始化列表需要显式类型",
        loc,
        E3004_TypeMismatch,
      )
      @ast.Type::int()
    }
    _ => {
      self.report_error(
        "auto 推导失败：不支持的初始化表达式",
        init.loc(),
        E3004_TypeMismatch,
      )
      @ast.Type::int()
    }
  }
}

///|
/// 表达式是否涉及数组或指针（W3051 for-条件 Le off-by-one 判据；
/// Rust convert.rs 同构）。
fn TypeChecker::expr_involves_array_or_pointer(
  self : TypeChecker,
  expr : @ast.Expr,
) -> Bool {
  match expr {
    Index(_, _, _, _) => true
    Identifier(name, _, _) =>
      match self.lookup_var(name) {
        Some(sym) => sym.ty.is_array() || sym.ty.kind() is TK_Pointer
        None => false
      }
    Binary(_, left, right, _, _) =>
      self.expr_involves_array_or_pointer(left) ||
      self.expr_involves_array_or_pointer(right)
    Unary(_, operand, _, _) => self.expr_involves_array_or_pointer(operand)
    Assign(_, left, right, _, _) =>
      self.expr_involves_array_or_pointer(left) ||
      self.expr_involves_array_or_pointer(right)
    Ternary(cond, then_branch, else_branch, _, _) =>
      self.expr_involves_array_or_pointer(cond) ||
      self.expr_involves_array_or_pointer(then_branch) ||
      self.expr_involves_array_or_pointer(else_branch)
    _ => false
  }
}
