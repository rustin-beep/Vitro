///|
/// 产名黄金串（形状冻结——Rust parser/typeck 现状口径逐字对齐；
/// 改一字符即 S4+ 差分锚红：C++ 片 E3 名集合锚的直接消费面）。
test "ctor_dtor_name_shapes" {
  assert_eq(ctor_def_name("Point"), "__ctor__Point")
  assert_eq(ctor_call_name("Point", 2), "__ctor__Point__2")
  assert_eq(ctor_copy_name("Point"), "__ctor__Point__copy")
  assert_eq(dtor_name("Point"), "__dtor__Point")
  assert_true(is_ctor_name("__ctor__Point__2"))
  assert_true(is_ctor_name(ctor_def_name("Vec")))
  assert_false(is_ctor_name("__ctor_"))
  assert_true(is_dtor_name("__dtor__Point"))
  assert_false(is_dtor_name("__ctor__Point"))
}

///|
/// type_mangle_suffix 全 17 变体快照（照搬不私改——Rust cpp/methods.rs
/// D1 修复后的编码表；每变体一断言，变体增删必改此处）。
test "type_mangle_suffix_all_variants" {
  assert_eq(type_mangle_suffix(Void(false)), "v")
  assert_eq(type_mangle_suffix(Int(false, false)), "i")
  assert_eq(type_mangle_suffix(Int(true, false)), "u")
  assert_eq(type_mangle_suffix(Char(false, false)), "c")
  assert_eq(type_mangle_suffix(Float(false)), "f")
  assert_eq(type_mangle_suffix(Double(false)), "d")
  assert_eq(type_mangle_suffix(LongLong(false, false)), "l")
  // const 不参与（顶层 const 不影响重载决议）
  assert_eq(type_mangle_suffix(Int(false, true)), "i")
  assert_eq(type_mangle_suffix(Pointer(Int(false, false), false)), "Pi")
  assert_eq(type_mangle_suffix(Reference(Int(false, false), false)), "Ri")
  assert_eq(type_mangle_suffix(RValueRef(Int(false, false))), "Ri")
  assert_eq(
    type_mangle_suffix(Array(Char(false, false), 2, [2], false, false, [])),
    "Ac",
  )
  assert_eq(type_mangle_suffix(Struct("S", false)), "SS")
  assert_eq(type_mangle_suffix(Union("U", false)), "SU")
  assert_eq(type_mangle_suffix(Class("C", false)), "SC")
  assert_eq(
    type_mangle_suffix(
      Function(
        Int(false, false),
        [Double(false), Pointer(Char(false, false), false)],
        false,
        false,
      ),
    ),
    "FidPc",
  )
  assert_eq(
    type_mangle_suffix(
      TemplateId("vec", [TArg(Int(false, false)), TInt(3)], false),
    ),
    "TveciI3",
  )
  assert_eq(type_mangle_suffix(Auto), "a")
  // Typeof/TExpr 两变体在黑盒（SourceLoc 构造需 source 包——wbtest 不
  // 携带 for "test" import，陷阱 26）：见 names_test.mbt
}

///|
/// method_mangled_name 两形态（单签名短名兼容 / 多签名类型编码后缀——
/// D1 事故的防回归锚：`show(int)`/`show(double)` 必须不同名）。
test "method_mangled_name_overload_encoding" {
  assert_eq(
    method_mangled_name("Point", "show", [Int(false, false)], false),
    "Point__show",
  )
  assert_eq(
    method_mangled_name("Point", "show", [Int(false, false)], true),
    "Point__show__i",
  )
  assert_eq(
    method_mangled_name("Point", "show", [Double(false)], true),
    "Point__show__d",
  )
  // 同 arity 异类型（D1 事故形状）：编码后必然不同名
  let a = method_mangled_name(
    "C",
    "f",
    [Int(false, false), Char(false, false)],
    true,
  )
  let b = method_mangled_name(
    "C",
    "f",
    [Char(false, false), Int(false, false)],
    true,
  )
  assert_false(a == b)
}

///|
/// 单源锚：ctor/dtor 产名族各共享前缀常量（改前缀只动常量一处——
/// 本测试锁定两族内一致性；dtor 族同锁，审阅 F8② 补）。
test "ctor_dtor_family_single_prefix" {
  assert_true(ctor_def_name("X").has_prefix(CTOR_PREFIX))
  assert_true(ctor_call_name("X", 1).has_prefix(CTOR_PREFIX))
  assert_true(ctor_copy_name("X").has_prefix(CTOR_PREFIX))
  assert_eq(CTOR_PREFIX, "__ctor__")
  assert_true(dtor_name("X").has_prefix(DTOR_PREFIX))
  assert_true(is_dtor_name(dtor_name("X")))
  assert_eq(DTOR_PREFIX, "__dtor__")
}
