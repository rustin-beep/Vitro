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

///| ── 批 E：ViewDoc v0.1.1 声明文法与出口 ─────────────────────────────

///|
test "parse_series_decl_basic_and_opts" {
  match parse_series_decl("series re im -> polar gain=2 group=0") {
    Err(m) => assert_true(false, msg="合法声明被拒：\{m}")
    Ok(d) => {
      assert_eq(d.series, ["re", "im"])
      assert_eq(d.projector, "polar")
      assert_eq(d.opts.length(), 2)
      assert_eq(d.opts[0], ("gain", "2"))
      assert_eq(d.opts[1], ("group", "0"))
    }
  }
  // 多余空白 / 制表符 / 行首尾 trim
  match parse_series_decl("  series\ta\t ->\tbars  ") {
    Err(m) => assert_true(false, msg="空白形态被拒：\{m}")
    Ok(d) => {
      assert_eq(d.series, ["a"])
      assert_eq(d.projector, "bars")
      assert_eq(d.opts.length(), 0)
    }
  }
}

///|
test "parse_series_decl_errors_fail_loud" {
  assert_true(parse_series_decl("") is Err(_), msg="空行红")
  assert_true(parse_series_decl("series a") is Err(_), msg="缺 -> 红")
  assert_true(
    parse_series_decl("curve a -> bars") is Err(_),
    msg="缺 series 前缀红",
  )
  assert_true(
    parse_series_decl("series -> bars") is Err(_),
    msg="无序列名红",
  )
  assert_true(
    parse_series_decl("series 1a -> bars") is Err(_),
    msg="非标识符序列名红",
  )
  assert_true(
    parse_series_decl("series a -> ") is Err(_),
    msg="缺投影器红",
  )
  assert_true(
    parse_series_decl("series a -> bars gain") is Err(_),
    msg="非 k=v 选项红",
  )
  assert_true(
    parse_series_decl("series a -> bars =2") is Err(_),
    msg="空选项键红",
  )
  assert_true(
    parse_series_decl("series a -> bars gain=") is Err(_),
    msg="空选项值红",
  )
}

///|
test "parse_series_decl_block_skips_comments_and_numbers_lines" {
  let text = "// 课程注释\nseries a -> bars\n\nseries re im -> polar gain=2\n"
  match parse_series_decl_block(text) {
    Err(m) => assert_true(false, msg="块解析被拒：\{m}")
    Ok(ds) => {
      assert_eq(ds.length(), 2)
      assert_eq(ds[0].projector, "bars")
      assert_eq(ds[1].series, ["re", "im"])
    }
  }
  match parse_series_decl_block("// 只有注释\n\n") {
    Ok(ds) => assert_eq(ds.length(), 0, msg="全注释块 = 零声明")
    Err(m) => assert_true(false, msg="全注释块不该报错：\{m}")
  }
  match parse_series_decl_block("series a -> bars\nseries b ->\n") {
    Err(m) =>
      assert_true(
        m.has_prefix("第 2 行："),
        msg="错误须带 1 起行号：\{m}",
      )
    Ok(_) => assert_true(false, msg="坏行未判红")
  }
}

///|
test "doc_value_pv_default_and_full_family" {
  let doc = doc_value([
    { series: ["a"], projector: "bars", opts: [("gain", "2")], },
  ])
  let m = match doc {
    Object(m) => m
    _ => {
      assert_true(false, msg="doc 须为对象")
      Map([])
    }
  }
  assert_eq(m.get("pv"), Some(Json::string("0.1.1")), msg="pv 钉 0.1.1")
  assert_eq(
    m.get("default"),
    Some(Json::string("cells")),
    msg="默认投影器",
  )
  match m.get("projectors") {
    Some(Array(ps)) => {
      assert_eq(ps.length(), 6, msg="全族 6 条（禁抽样）")
      let ids : Array[String] = []
      for p in ps {
        match p {
          Object(pm) =>
            match pm.get("id") {
              Some(String(s)) => ids.push(s)
              _ => assert_true(false, msg="projector.id 缺失")
            }
          _ => assert_true(false, msg="projector 项非对象")
        }
      }
      assert_eq(ids, projector_ids(), msg="doc 词表 ≡ projectors()")
    }
    _ => assert_true(false, msg="projectors 缺失")
  }
  match m.get("series_decl") {
    Some(Array(ds)) => {
      assert_eq(ds.length(), 1)
      match ds[0] {
        Object(dm) => {
          assert_eq(dm.get("projector"), Some(Json::string("bars")))
          assert_eq(
            dm.get("opts"),
            Some(Json::object({ "gain": Json::string("2") })),
            msg="opts 对象化",
          )
        }
        _ => assert_true(false, msg="series_decl 项非对象")
      }
    }
    _ => assert_true(false, msg="series_decl 缺失")
  }
}

///|
test "doc_json_roundtrip_and_determinism" {
  let decls : Array[SeriesDecl] = [
    {
      series: ["z", "a"],
      projector: "line",
      opts: [("gain", "3"), ("axis", "y")],
    },
  ]
  let s1 = doc_json(decls)
  let s2 = doc_json(decls)
  assert_eq(s1, s2, msg="同输入字节确定")
  // opts 键字节序（axis 在 gain 前）
  assert_true(
    s1.find("\"axis\":\"y\"") is Some(_),
    msg="opts 键序错：\{s1}",
  )
  let back = @util.json_parse(s1) catch { _ => Json::null() }
  match back {
    Object(m) => {
      assert_eq(m.get("pv"), Some(Json::string("0.1.1")))
      match m.get("series_decl") {
        Some(Array(ds)) =>
          match ds[0] {
            Object(dm) =>
              assert_eq(
                dm.get("series"),
                Some(Json::array([Json::string("z"), Json::string("a")])),
                msg="序列序保持声明序",
              )
            _ => assert_true(false, msg="series_decl 项非对象")
          }
        _ => assert_true(false, msg="series_decl 缺失")
      }
    }
    _ => assert_true(false, msg="doc_json 不可解析：\{s1}")
  }
}

///|
test "doc_empty_decls_is_stable" {
  let doc = doc_value([])
  match doc {
    Object(m) =>
      match m.get("series_decl") {
        Some(Array(ds)) => assert_eq(ds.length(), 0)
        _ =>
          assert_true(
            false,
            msg="空声明须发空数组（宿主键恒在）",
          )
      }
    _ => assert_true(false, msg="doc 须为对象")
  }
}
