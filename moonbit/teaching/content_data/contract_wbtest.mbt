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
/// 与 icon 语义 id 原样 + 基数 115（#214 +W3084/W3085；PR #284 审阅
/// P3 +W1023 卡；#256/#261 闭合批 +E0/E3074–E3082/E3086–E3088、
/// 退役 E1022/E2001/E3026/W3056/E4100–E4104；闭合闸摸底 +E1012；#223 +E3089）。
test "catalog_content_escape_probe" {
  install_baked()
  assert_eq(@diag.catalog_texts.length(), 115, msg="115 卡基线")
  let e2 = @diag.ErrorCode::from_code(1002).unwrap().catalog().unwrap()
  assert_eq(e2.title, "字符串未闭合")
  assert_eq(e2.icon, "string")
  let e3007 = @diag.ErrorCode::from_code(3007).unwrap().catalog().unwrap()
  assert_true(e3007.explanation.contains("char"))
}

///|
/// #409 N1 红→绿锚（2026-11-01）：E0 兜底卡中性化。E0 是 codegen 无码错误
/// 的统一兜底（#38 立码前：容量超限 / 级联未声明等**用户代码错误**全落
/// 此卡），旧 explanation 断言「而不是你的代码有明确的语义错误」+ title
/// 「内部错误」——与 message「请减小全局数组」自相矛盾，对学生撒谎
///（#409 深挖实证：static 局部 400KB 超限五条 E0 全挂此文案）。锚锁四件：
/// 不含旧断言句 / 含「以上方错误信息为准」引导句 / common_causes 含容量
/// 上限与级联未声明两条用户侧成因 / **explanation 不得把「未声明」列为
/// 「指向你的代码」的举例**（PR #411 审阅 P2-1：级联伪错误归用户账 =
/// 半撒谎——级联语义只许落 causes 第 2 条）。
///
/// 连坐登记（PR #411 审阅 P3③）：causes 第 2 条「前一条错误使标识符未能
/// 登记，带出连锁未声明」描述的是 #38 立码前 `bump_global_offset` 返 None
/// 后符号未登记的**引擎级联缺陷行为**——#38 修级联抑制/符号登记后本条
/// 文案随之失真，须连坐改写（本锚 `has_cascade` 断言届时同步调整）。
test "e0_fallback_card_neutral_not_blaming_compiler" {
  install_baked()
  let e0 = @diag.ErrorCode::from_code(0).unwrap().catalog().unwrap()
  assert_false(
    e0.explanation.contains("而不是你的代码有明确的语义错误"),
    msg="E0 兜底不得断言『不是你的代码问题』",
  )
  assert_false(
    e0.title.contains("内部错误"),
    msg="E0 title 不得预设『内部错误』",
  )
  assert_true(
    e0.explanation.contains("以上方错误信息为准"),
    msg="E0 兜底须引导读上方错误信息",
  )
  assert_false(
    e0.explanation.contains("未声明"),
    msg="explanation 不得把级联『未声明』列为指向用户代码的举例（P2-1）",
  )
  let mut has_cap = false
  let mut has_cascade = false
  for c in e0.common_causes {
    if c.contains("容量上限") {
      has_cap = true
    }
    if c.contains("未声明") {
      has_cascade = true
    }
  }
  assert_true(has_cap, msg="common_causes 须含容量上限成因")
  assert_true(has_cascade, msg="common_causes 须含级联未声明成因")
}
