///|
/// #130 批③a 烘焙数据面契约锚（2026-10-17）：自 assets 迁入的两条
/// 基线锚（12 臂 builtin 契约 + 43 键基数）+ 名单↔烘焙表双向对账
///（原 assets/install_wbtest 锚随拆包迁此——本包持有数据本尊）+
/// install_baked 装载功能性锚。

///|
/// builtin_notes 契约锚（#60 批三段二，随批③a 迁入）：键集 = 12 个
/// FILE/mem 特判臂名单；param_notes 与该函数参数位对位。
test "builtin_notes_contract" {
  assert_eq(builtin_notes.length(), 12, msg="12 臂名单基线")
  for pair in builtin_notes {
    let (name, note) = pair
    assert_true(
      note.count_note.length() > 0 || note.param_notes.length() > 0,
      msg="\{name} 至少一项非空",
    )
  }
}

///|
/// suggestions 键基数锚（审阅处置批二 2026-10-10 P3，随批③a 迁入）。
test "suggestions_key_cardinality" {
  let m = build_suggestion_map()
  assert_eq(m.length(), 43, msg="43 算法键基线")
}

///|
/// 名单 ↔ 烘焙表双向对账（原 assets/install_wbtest 锚迁此）：
/// known_suggestion_keys 与 build_suggestion_map 键集相等——增删族
/// 不同步两侧即红（steps catalog 锚对名单、本锚对数据，链式锁三方）。
test "known_suggestion_keys_match_baked_table" {
  let baked : Array[String] = []
  for k, _v in build_suggestion_map() {
    baked.push(k)
  }
  let known = @assets.known_suggestion_keys.copy()
  known.sort_by(@util.str_cmp)
  baked.sort_by(@util.str_cmp)
  assert_eq(known.length(), baked.length())
  for i in 0..<known.length() {
    assert_eq(known[i], baked[i])
  }
}

///|
/// install_baked 装载功能性锚：装载后 assets 两载体表计数与抽样值
/// 就位（幂等——二次装载同态）；trap 表非本包装载面（assets 烘焙，
/// 不动断言其计数只断不归零）。
test "install_baked_fills_carrier_tables" {
  install_baked()
  assert_eq(@assets.suggestion_map.length(), 43)
  assert_eq(@assets.builtin_notes.length(), 12)
  assert_true(@assets.suggestion_map.get("bubble_sort") is Some(_))
  assert_true(@assets.builtin_notes.get("fread") is Some(_))
  // 幂等
  install_baked()
  assert_eq(@assets.suggestion_map.length(), 43)
  assert_eq(@assets.builtin_notes.length(), 12)
}

///|
/// 无卡片码全部 None；有卡片码全部 Some 且内容非空（原 diag_wbtest 锚
/// 随批③b 迁入——装载后全量语义）。
test "catalog_presence_per_code" {
  install_baked()
  for c in @diag.codes_without_catalog() {
    assert_true(@diag.ErrorCode::from_code(c).unwrap().catalog() is None)
  }
  for c in @diag.catalog_codes() {
    let e = @diag.ErrorCode::from_code(c).unwrap().catalog().unwrap()
    assert_true(e.title.length() > 0)
    assert_true(e.explanation.length() > 0)
  }
}

///|
/// 卡片内容抽查（转义正确性锚——原 diag_wbtest 锚迁入）：E1002 中文
/// 与 icon 语义 id 原样 + 基数 109（#214 +W3084/W3085；PR #284 审阅
/// P3 +W1023 卡）。
test "catalog_content_escape_probe" {
  install_baked()
  assert_eq(@diag.catalog_texts.length(), 109, msg="109 卡基线")
  let e2 = @diag.ErrorCode::from_code(1002).unwrap().catalog().unwrap()
  assert_eq(e2.title, "字符串未闭合")
  assert_eq(e2.icon, "string")
  let e3007 = @diag.ErrorCode::from_code(3007).unwrap().catalog().unwrap()
  assert_true(e3007.explanation.contains("char"))
}
