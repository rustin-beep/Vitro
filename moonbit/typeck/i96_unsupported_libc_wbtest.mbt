// #96（2026-10-15）：libc 缺口诊断路由锚——引擎已知不支持的标准库函数
// （getenv/system/strtok/atexit/frexp/ldexp/modf/scalbn——支持矩阵 5.5
// 排除项）不得走「未定义函数」路径：E3036 的 fix_suggestion「添加原型
// 声明」对该类缺口无效（加了原型照样编译不过——函数体不存在），且
// int 兜底返回类型级联出与真因无关的 E3054/E3004 假阳性（issue 实测
// 三条诊断只有第一条与 getenv 相关）。修法：独立码 E3073 + libc
// unsupported_libc_sig 真实签名表（返回真实类型——级联自然消失，
// #8 单错口径延伸）。

///|
test "i96_unsupported_libc_env_getenv_single_error" {
  // issue 原例形态：const char *p = getenv("PATH"); p ? p : "null"
  // ——修后 E3073 单错（无 E3054 int→指针 / E3004 三目级联）
  let loc = @source.SourceLoc::new(2, 5)
  let call_getenv : @ast.Expr = @ast.Expr::CallPtr(
    @ast.Expr::Identifier("getenv", loc, @ast.Type::void_type()),
    [@ast.Expr::StringLiteral("PATH", loc, @ast.Type::void_type())],
    loc,
    @ast.Type::void_type(),
  )
  let decl : @ast.Stmt = @ast.Stmt::VarDecl(
    @ast.Type::Pointer(@ast.Type::Char(false, true), false),
    "p",
    Some(call_getenv),
    [],
    false,
    false,
    loc,
  )
  let cond : @ast.Expr = @ast.Expr::Ternary(
    @ast.Expr::Identifier("p", loc, @ast.Type::void_type()),
    @ast.Expr::Identifier("p", loc, @ast.Type::void_type()),
    @ast.Expr::StringLiteral("null", loc, @ast.Type::void_type()),
    loc,
    @ast.Type::void_type(),
  )
  let body : @ast.Stmt = @ast.Stmt::Block(
    [
      decl,
      @ast.Stmt::Expr(
        @ast.Expr::Call(
          "printf",
          [@ast.Expr::StringLiteral("%s", loc, @ast.Type::void_type()), cond],
          loc,
          @ast.Type::void_type(),
        ),
        loc,
      ),
    ],
    loc,
  )
  let main = func_of("main", [], Some(body), loc)
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(prog_of([main], []))
  assert_eq(errs.length(), 1, msg="E3073 单错（无 E3054/E3004 级联）")
  assert_true(errs[0].code == 3073, msg="独立码 3073")
  assert_true(
    errs[0].message.contains("未实现"),
    msg="措辞走「未实现」不走「未定义」",
  )
}

///|
test "i96_unsupported_libc_table_members_and_undefined_unchanged" {
  // 表内各族一员 + 表外未定义函数仍走 E3036 原路径（不误伤拼错名/
  // 真未定义的既有诊断）
  let loc = @source.SourceLoc::new(3, 5)
  fn call_stmt(name : String) -> @ast.Stmt {
    @ast.Stmt::Expr(
      @ast.Expr::CallPtr(
        @ast.Expr::Identifier(name, loc, @ast.Type::void_type()),
        [@ast.Expr::StringLiteral("x", loc, @ast.Type::void_type())],
        loc,
        @ast.Type::void_type(),
      ),
      loc,
    )
  }
  let body : @ast.Stmt = @ast.Stmt::Block(
    [call_stmt("system"), call_stmt("strtok"), call_stmt("xyzzy")],
    loc,
  )
  let main = func_of("main", [], Some(body), loc)
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(prog_of([main], []))
  assert_eq(errs.length(), 3)
  assert_true(errs[0].code == 3073, msg="system 表内 E3073")
  assert_true(errs[1].code == 3073, msg="strtok 表内 E3073")
  assert_true(errs[2].code == 3036, msg="xyzzy 表外仍 E3036")
}
