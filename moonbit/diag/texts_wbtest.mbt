///|
/// #130 批③b 诊断卡片装载门红锚（2026-10-17；#323 起段级合并语义，
/// 2026-10-27）：catalog_texts 可覆盖化——段发射/装载往返 + 值域闸
///（码 ⊆ catalog_codes）+ 段级合并保留 + __clear__ 显式清空 + fail
/// loud + lean 查表语义（catalog() miss = None——与「无卡片码登记
/// 缺口」同语义，消费面 push_one/error_catalog 天然 None-safe）。
/// 恢复纪律：测尾显式 __clear__ 回 lean 初始态（#323 起空段=不覆盖）。

///|
/// 往返幂等：段发射 → 装载 → 再发射逐字节不变。
test "catalog_texts_roundtrip_idempotent" {
  let _ = install_catalog_texts(catalog_texts_json()) catch {
    _ => fail("空段装载失败")
  }
  let j0 = catalog_texts_json()
  let _ = install_catalog_texts(j0) catch { _ => fail("回装失败") }
  inspect(catalog_texts_json(), content=j0)
}

///|
/// 装载可见 + catalog() 查表贯通 + 段级合并保留（#323）：装 fixture
///（E1001）→ catalog() 取到同码卡片；再装仅含另一码（E1002）的段 →
/// 既有码保留（旧整表替换语义 = E1001 消失——本断言在该语义下红）；
/// 值域外键装载被拒（值域闸 = catalog_codes）。
test "catalog_texts_install_and_lookup" {
  let fixture = "{\"1001\":{\"icon\":\"unknown-char\",\"title\":\"未知字符探针\",\"explanation\":\"装载门探针正文。\",\"common_causes\":[\"探针原因一\",\"探针原因二\"]}}"
  let _ = install_catalog_texts(fixture) catch {
    _ => fail("fixture 装载失败")
  }
  let e = ErrorCode::from_code(1001).unwrap()
  let card = e.catalog()
  assert_true(card is Some(_), msg="装载后 catalog() 须命中")
  let c = card.unwrap()
  assert_eq(c.title, "未知字符探针")
  assert_eq(c.code, 1001)
  // 段级合并保留（#323 治②）：单码段装载 → 两码并存
  let fixture2 = "{\"1002\":{\"icon\":\"info\",\"title\":\"合并探针\",\"explanation\":\"段级合并正文。\",\"common_causes\":[]}}"
  let _ = install_catalog_texts(fixture2) catch {
    _ => fail("第二段装载失败")
  }
  assert_true(
    ErrorCode::from_code(1001).unwrap().catalog() is Some(_),
    msg="合并语义下既有码须保留（旧整表替换=消失）",
  )
  assert_true(
    ErrorCode::from_code(1002).unwrap().catalog() is Some(_),
    msg="新码装载须可见",
  )
  // lean 语义：未装载码 = None（与 codes_without_catalog 同语义）
  assert_true(ErrorCode::from_code(1003).unwrap().catalog() is None)
  // 显式清空回 lean 初始态（#323 起空段=不覆盖，清场须 __clear__）
  let cleared = Ok(install_catalog_texts("{\"__clear__\":true}")) catch {
    e2 => Err(e2)
  }
  assert_true(cleared is Ok(_), msg="__clear__ 单键形态须合法")
  assert_eq(cleared.unwrap(), true, msg="清空须回告 true（可观测）")
  assert_true(e.catalog() is None)
}

///|
/// fail loud 三态 + __clear__ 混用拒（#323）：坏 JSON / 值域外码 /
/// 字段形态错 / __clear__ 混数据键——拒绝且不落半装。
test "catalog_texts_rejects_bad_payloads" {
  // ① 坏 JSON
  let r1 = Ok(install_catalog_texts("{not json")) catch { e => Err(e) }
  assert_true(r1 is Err(_), msg="坏 JSON 须拒")
  // ② 值域外码（9999 不在 catalog_codes——码域闸）
  let r2 = Ok(
    install_catalog_texts(
      "{\"9999\":{\"icon\":\"x\",\"title\":\"t\",\"explanation\":\"e\",\"common_causes\":[]}}",
    ),
  ) catch {
    e => Err(e)
  }
  assert_true(r2 is Err(_), msg="值域外码须拒")
  // ③ 字段形态错（title 非字符串）
  let r3 = Ok(
    install_catalog_texts(
      "{\"1001\":{\"icon\":\"x\",\"title\":42,\"explanation\":\"e\",\"common_causes\":[]}}",
    ),
  ) catch {
    e => Err(e)
  }
  assert_true(r3 is Err(_), msg="字段形态错须拒")
  // ④ __clear__ 混数据键（半清空歧义形态——#323 与 assets 段同款闸）
  let r4 = Ok(
    install_catalog_texts(
      "{\"__clear__\":true,\"1001\":{\"icon\":\"x\",\"title\":\"t\",\"explanation\":\"e\",\"common_causes\":[]}}",
    ),
  ) catch {
    e => Err(e)
  }
  assert_true(r4 is Err(_), msg="__clear__ 混数据键须拒")
  // 不落半装：表保持空
  assert_eq(catalog_texts.length(), 0)
}
