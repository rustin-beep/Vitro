///| 投影器语义白盒锚（数据面由 scripts/gen_view_projectors 生成；本文件锁契约面）。

///|
test "projector_ids_full_family" {
  // 全族枚举（禁抽样、禁 grep 出结论）：新增投影器不改此锚即红。
  assert_eq(projector_ids(), [
    "bars", "cells", "grid2d", "line", "polar", "spectrum",
  ])
  assert_eq(projectors().length(), 6)
  assert_eq(default_projector(), "cells")
}

///|
test "projector_lookup_unknown_fails_loud" {
  assert_true(projector("nope") is None, msg="未知名不回落默认")
  assert_true(projector("") is None, msg="空名不回落默认")
  assert_true(projector("polar") is Some(_), msg="合法名可命中")
}

///|
test "projector_polar_and_grid2d_spec" {
  match projector("polar") {
    None => assert_true(false, msg="polar 缺失")
    Some(p) => {
      assert_eq(p.series_min, 2)
      assert_eq(p.series_max, 2)
      assert_eq(p.min_dims, 0)
      assert_eq(p.opts.length(), 2)
      assert_eq(p.opts[0], "group")
      assert_eq(p.opts[1], "gain")
    }
  }
  match projector("grid2d") {
    None => assert_true(false, msg="grid2d 缺失")
    Some(p) => {
      assert_eq(p.min_dims, 2, msg="grid2d 必须有 dims")
      assert_eq(p.opts.length(), 0)
    }
  }
}

///|
test "check_decl_series_bounds" {
  assert_true(check_decl("polar", 2, 1) is None, msg="re+im 两条合法")
  assert_true(
    check_decl("polar", 1, 1) is Some(_),
    msg="少一条实部/虚部即红",
  )
  assert_true(check_decl("polar", 3, 1) is Some(_), msg="多一条也红")
  assert_true(check_decl("line", 1, 1) is None, msg="line 单序列合法")
  assert_true(check_decl("line", 4, 1) is None, msg="line 条数不限")
  assert_true(check_decl("nope", 1, 1) is Some(_), msg="未知 id 红")
}

///|
test "check_decl_dims_gate" {
  assert_true(check_decl("grid2d", 1, 2) is None, msg="二维合法")
  assert_true(check_decl("grid2d", 1, 1) is Some(_), msg="缺 dims 即红")
  assert_true(check_decl("cells", 1, 1) is None, msg="一维索引格合法")
}

///|
test "known_opt_unknown_key_is_soft" {
  assert_true(known_opt("polar", "group"))
  assert_true(known_opt("polar", "gain"))
  assert_false(
    known_opt("polar", "future_key"),
    msg="未知键不判错、只报未登记",
  )
  assert_false(known_opt("nope", "group"))
}

///|
test "projector_digest_shape" {
  assert_eq(projector_digest().length(), 71, msg="sha256: + 64 hex")
}
