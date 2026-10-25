///|
/// #130 批③b fixture（lean 载体默认空——wbtest 不可 import
/// content_data）：三条已知卡（1001 首位字节锚 / 3051 W 前缀 / 3086
/// 运行期 trap 码〔#261 立码；原 4100 探针随 #256 C++ 死卡退役换锚〕），
/// 内容 = 真源逐字节；测尾显式 __clear__ 恢复 lean 态（#323 起空段=
/// 不覆盖，清场须 __clear__）。
fn e4_install_fixture() -> Unit raise {
  let _ = install_catalog_texts(
    "{\"1001\":{\"icon\":\"unknown-char\",\"title\":\"未知字符\",\"explanation\":\"探针\",\"common_causes\":[]},\"3051\":{\"icon\":\"x\",\"title\":\"W 前缀探针\",\"explanation\":\"探针\",\"common_causes\":[]},\"3086\":{\"icon\":\"index\",\"title\":\"数组越界（运行期）\",\"explanation\":\"探针\",\"common_causes\":[]}}",
  ) catch {
    _ => fail("fixture 装载失败")
  }
}

///|
fn e4_restore_lean() -> Unit raise {
  let _ = install_catalog_texts("{\"__clear__\":true}") catch { _ => false }
}

///|
/// E4 出口形状：包裹结构 + 条目数（每条必含一个 common_causes 键）。
/// 批③b 起 = fixture 三条（全量 105 计数锚随数据迁 content_data）。
test "e4_export_shape_and_count" {
  e4_install_fixture()
  let json = export_catalog_json()
  assert_true(json.has_prefix("{\"catalog\":["))
  assert_true(json.has_suffix("]}"))
  let hits = json.split("common_causes").count() - 1
  assert_eq(hits, 3)
  e4_restore_lean() catch {
    _ => ()
  }
}

///|
/// E4 首条逐字节锚（#50 批③后最小码 1001——原 1002 首位被新增 unknown-char
/// 条目取代）：字段序 / lang="c" / category="词法" / 转义形态。
test "e4_export_first_entry_bytes" {
  e4_install_fixture()
  let json = export_catalog_json()
  // 首条即最小码 1001（catalog_codes 升序首位；#50 批③新增）
  let expect_head = "{\"catalog\":[{\"code\":1001,\"code_str\":\"E1001\",\"lang\":\"c\",\"category\":\"词法\",\"icon\":\"unknown-char\",\"title\":\"未知字符\","
  assert_true(json.has_prefix(expect_head))
}

///|
/// 4xxx 段退役锚终态（#256 卡退役 → #233 臂摘除）：E4001–E4031
/// NotSupported 族 + E4100–E4106 Cpp 族共 38 条 C++ 死臂已从枚举
/// 真源整体摘除（C only 裁定 2026-09-20 后零生产点）——from_code 不再
/// 命中，全量导出不得含 4xxx 条目（下游预渲染错误清单不列永不触发
/// 码；E4 号段腾空 = #38 codegen 立码段的候选号段）。
test "e4_export_cpp_segment" {
  e4_install_fixture()
  let json = export_catalog_json()
  assert_true(
    ErrorCode::from_code(4100) is None,
    msg="E4100 死臂已摘（from_code 不命中）",
  )
  assert_true(
    ErrorCode::from_code(4001) is None,
    msg="E4001 死臂已摘（from_code 不命中）",
  )
  assert_false(json.contains("\"code\":4100"))
  assert_false(json.contains("\"code\":410"))
  assert_false(json.contains("\"code\":4001"))
  e4_restore_lean() catch {
    _ => ()
  }
}

///|
/// W/H 码卡片码串前缀（P3 段位单源在 E4 出口的体现）：
/// W3051 有卡片（ArrayBoundOffByOne 在 catalog_codes 内），导出 code_str="W3051"。
test "e4_export_warn_prefix" {
  e4_install_fixture()
  let json = export_catalog_json()
  assert_true(catalog_codes().contains(3051))
  let frag = "\"code\":3051,\"code_str\":\"W3051\""
  assert_true(json.contains(frag))
}

///|
/// E4 出口 JSON 合法性锚（issue #55 收口后）：全量 catalog 输出不得含
/// U+0000–001F 裸控制字节（控制字符必须已是 \u00XX 转义文本——转义单源
/// @util.json_escape，原本地副本只转五字符的缺口由此在出口面钉死）。
test "e4_export_no_raw_control_bytes" {
  e4_install_fixture()
  let json = export_catalog_json()
  for c in json {
    if c.to_int() < 0x20 {
      fail("E4 出口含裸控制字节 U+\{c.to_int()}")
    }
  }
}

///|
/// P2-2 加牙锚（审阅 2026-10-09）：出口转义单点对控制字节的转义行为。
/// 上一锚扫静态 catalog 输出——数据面不含 <0x20 非 \n\r\t 字节，突变
/// （emitter 拆 @util.json_escape 接线回直拼形态）下仍绿＝空转；本锚
/// 直测 e4_json_str 单点，接线被拆即红（J9 突变已证）。
test "e4_json_str_escapes_control_bytes" {
  // \t 走短转义；U+0001 走 \u00XX（小写 hex，serde_json 口径）
  inspect(e4_json_str("tab\there"), content="\"tab\\there\"")
  inspect(e4_json_str("a\u{01}b"), content="\"a\\u0001b\"")
  inspect(e4_json_str("q\"q\\q"), content="\"q\\\"q\\\\q\"")
  // 引号包裹职责在本单点（四字段共用）
  inspect(e4_json_str("plain"), content="\"plain\"")
}

///|
/// lang/category 四值探针（P2-3：防 5xxx 落地静默错——白盒直测私有派生）。
/// PR #346 审阅 P3-2 登记（2026-10-28）：export_lang_of(4001)="c++" 等
/// 4xxx 区间断言是**号段区间派生**的历史语义冻结——E4 号段已腾空给 #38
/// （C 立码段），真启用时须连坐改派生与本锚（否则 C 码被错标 c++）。
test "e4_lang_category_four_values" {
  inspect(export_lang_of(1001), content="c")
  inspect(export_lang_of(3999), content="c")
  inspect(export_lang_of(4001), content="c++")
  inspect(export_lang_of(4999), content="c++")
  inspect(export_lang_of(5000), content="csharp")
  inspect(export_lang_of(5999), content="csharp")
  inspect(export_lang_of(0), content="unknown")
  inspect(export_lang_of(9999), content="unknown")
  inspect(category_of(1001), content="词法")
  inspect(category_of(2001), content="语法")
  inspect(category_of(3001), content="语义")
  inspect(category_of(4001), content="C++")
  inspect(category_of(5000), content="C#")
  inspect(category_of(0), content="其它")
}
