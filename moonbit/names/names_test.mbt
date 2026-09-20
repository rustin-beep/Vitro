///|
/// type_mangle_suffix 的 Auto/Typeof/TExpr 三变体（黑盒——SourceLoc 构造
/// 需 source 包，wbtest 不携带 for "test" import，陷阱 26；跨包构造器
/// 全限定，陷阱 16）。
test "type_mangle_suffix_typeof_and_texpr" {
  assert_eq(@names.type_mangle_suffix(@ast.Type::Auto), "a")
  let loc = @source.SourceLoc::new(1, 1)
  assert_eq(
    @names.type_mangle_suffix(
      @ast.Type::Typeof(
        @ast.Expr::Literal(1, loc, @ast.Type::Int(false, false)),
        false,
        false,
      ),
    ),
    "y",
  )
  assert_eq(
    @names.type_mangle_suffix(
      @ast.Type::TemplateId(
        "vec",
        [
          @ast.TemplateArg::TArg(@ast.Type::Int(false, false)),
          @ast.TemplateArg::TExpr(
            @ast.Expr::Literal(1, loc, @ast.Type::Int(false, false)),
          ),
        ],
        false,
      ),
    ),
    "TveciE",
  )
}
