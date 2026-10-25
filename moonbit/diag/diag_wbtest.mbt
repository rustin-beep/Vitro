///|
/// T2 覆盖率断言基线：146 臂 / 105 卡片 / 41 无卡片（105 + 41 = 146，
/// #50 批③：77/60→102/35（+25）；病 15：+W3068；病 19：+H3069；#96：
/// +E3073（105 卡，清单互斥互补）；#144/#151：+E3074/E3075；#145：+E3076；
/// #154/#156/#157：+E3077/E3078/E3079（均无卡）；#174：+E3080；#182：+E3081/E3082（无卡）；#178：+E3083（有卡 106）。
/// 源漂移由 gen_diag fail loud 兜底。
test "coverage_baseline_137_77_60" {
  let all = ErrorCode::all()
  assert_eq(all.length(), 119) // #214：150→152（W3084/W3085）；#212：152→153（W1023）；#261：153→156（运行期 trap 立码 E3086/E3087/E3088）；#223/#233 批：156→119（+E3089 已声明未定义立码；−38 条 4xxx C++ 死臂全数摘除——4001–4031 NotSupported 族 + 4100–4106 Cpp 族，C only 裁定后零生产点）
  assert_eq(catalog_codes().length(), 115) // #214：106→108（W3084/W3085 卡）；PR #284 审阅 P3：108→109（W1023 卡）；#256/#261 闭合批：109→113（+E0/E3074–E3082/E3086–E3088，退役 E1022/E2001/E3026/W3056/E4100–E4104）；闭合闸摸底 +E1012（活码无卡同族缺口）；#223：+E3089 卡
  assert_eq(codes_without_catalog().length(), 4) // 119-115（#223/#233 前 156-114=42，−38 死臂全数无卡）
  // 互补无交集
  let set : Map[Int32, Bool] = Map([])
  for c in catalog_codes() {
    set[c] = true
  }
  for c in codes_without_catalog() {
    assert_false(set.contains(c))
  }
}

///|
/// catalog_presence_per_code / catalog_content_escape_probe 已随
/// #130 批③b 拆包迁 content_data/contract_wbtest.mbt（数据面测试随
/// 数据包走；本包 lean 载体默认空表）。

///|
/// P3 段位前缀红锚同形（Rust test_code_prefix_* 的 MoonBit 侧镜像）：
/// W/H 码显示串与 severity 一致；E 码与未知默认 E。
test "display_code_prefix_alignment" {
  assert_eq(W3053_ImplicitScalarConversion.display_code(), "W3053")
  assert_eq(W1018_MacroShadowing.display_code(), "W1018")
  assert_eq(E3067_PointerTypeMismatch.display_code(), "E3067")
  assert_eq(H3057_ImplicitConversionHint.display_code(), "H3057")
  assert_eq(E1006_UnsupportedFeature.display_code(), "E1006")
  assert_eq(E3060_UseAfterFree.display_code(), "E3060")
  // #233：E4022 等模板族死臂已摘——E 前缀样例换新臂 E3089（#223 立码）
  assert_eq(E3089_FunctionDeclaredNotDefined.display_code(), "E3089")
  assert_eq(Unknown.display_code(), "E0")
}

///|
/// severity 与 display 首字母互证（两侧独立来源：severity 来自白名单
/// 分类，display 首字母来自生成时前缀拼接——单源漂移即红）。
test "severity_display_first_char_agree" {
  for code in ErrorCode::all() {
    let expected = match code.severity() {
      Error => "E"
      Warning => "W"
      Hint => "H"
    }
    let d = code.display_code()
    assert_true(d.has_prefix(expected))
  }
}

///|
/// lang 段位：4xxx 全 Cpp（38 条），其余 C（99 条），CSharp 0（5xxx 预留空置）。
test "lang_segment_4xxx_cpp" {
  let mut cpp = 0
  let mut c_lang = 0
  let mut csharp = 0
  for code in ErrorCode::all() {
    match code.lang() {
      Cpp => {
        cpp += 1
        assert_true(code.code() >= 4000)
      }
      CSharp => {
        csharp += 1
        assert_true(code.code() >= 5000)
      }
      C => c_lang += 1
    }
  }
  assert_eq(cpp, 0) // #233：4xxx 段 38 条 C++ 死臂全数摘除——Cpp 臂零在位（lang 派生仍按号段区间，5xxx CSharp 同理空置）
  assert_eq(c_lang, 119) // #214 +W3084/W3085（C 段 3xxx）；#212 +W1023（C 段 1xxx）；#261 +E3086/E3087/E3088（运行期 trap 立码，C 段 3xxx）；#223 +E3089；前史见 CHANGELOG
  assert_eq(csharp, 0) // 5xxx 段空置（CSharp 变体先行落位——P2-3）
  assert_eq(SourceLang::CSharp.to_str(), "csharp")
}

///|
/// from_code 与 code 互逆（全量 137）；未知编号 None。
test "from_code_roundtrip_all" {
  for code in ErrorCode::all() {
    assert_eq(ErrorCode::from_code(code.code()).unwrap(), code)
  }
  assert_true(ErrorCode::from_code(9999) is None)
  assert_true(ErrorCode::from_code(3068).unwrap() is W3068_FilePointerIntArg) // 病 15 批 A 落位
  assert_true(ErrorCode::from_code(3069).unwrap() is H3069_LoopLeOffByOneHint) // 病 19 落位
}

///|
/// 编号升序与唯一（all() 顺序契约——差分遍历确定性）。
test "all_codes_sorted_unique" {
  let mut prev = -1
  let seen : Map[Int32, Bool] = Map([])
  for code in ErrorCode::all() {
    assert_true(code.code() > prev)
    assert_false(seen.contains(code.code()))
    seen[code.code()] = true
    prev = code.code()
  }
}

///|
/// Severity / SourceLang 契约（to_str / prefix 显示面）。
test "severity_source_lang_display" {
  assert_eq(Severity::Error.to_str(), "error")
  assert_eq(Severity::Warning.to_str(), "warning")
  assert_eq(Severity::Hint.to_str(), "hint")
  assert_eq(SourceLang::C.to_str(), "c")
  assert_eq(SourceLang::Cpp.to_str(), "cpp")
}
