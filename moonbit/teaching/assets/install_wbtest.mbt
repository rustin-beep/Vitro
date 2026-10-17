///|
/// #130 批① 装载门契约红锚（2026-10-17）：三表可覆盖化——
/// texts_json/install_texts 往返与覆盖语义 + fail loud 判据 +
/// 值域对账（名单↔烘焙表锚已随批③a 迁 content_data——本包 lean 载体
/// 默认空两表 + trap 烘焙）。语言包 js 形态（浏览器懒加载注入）的
/// 引擎侧半边：payload 形态 = 本包发射的 texts_json 同 schema。
///
/// 恢复纪律：install_texts 原地改三表（包级单例），凡变异表的单测
/// **先快照后恢复**（测试尾 install 回原载荷）——MoonBit 同包测试共享
/// 状态，泄漏即污染后续测试（contract_wbtest 依赖全量表）。

///|
/// 往返幂等：texts_json → install_texts → texts_json 逐字节不变
///（发射排序 + 装载保持 = 规范形态自洽；发射器/解析器任一侧漂移即红）。
test "install_texts_roundtrip_idempotent" {
  let j0 = texts_json()
  install_texts(j0)
  let j1 = texts_json()
  inspect(j1, content=j0)
}

///|
/// 覆盖可见：改一条 suggestion、删一条 trap → 查表即时反映；恢复原载荷
/// → 全量回位（可覆盖化的正向与逆向双证——装载不是一次性烧死）。
test "install_texts_override_visible_and_restorable" {
  // lean 基态（批③a：suggestions/builtin 空载体 + trap 烘焙 45）——
  // 覆盖语义探针自带 fixture 键（bubble_sort），不依赖烘焙建议表
  let saved = texts_json()
  // 载荷手术：bubble_sort 文案改写 + E3061_double_free 条目剔除
  let j = @util.json_parse(saved) catch { _ => fail("原载荷解析失败") }
  let top = match j {
    Object(t) => t
    _ => fail("顶层形态异常")
  }
  match top.get("suggestions") {
    Some(Object(sugg)) =>
      sugg.set(
        "bubble_sort",
        Json::string("覆盖语义探针——若可见即装载门生效"),
      )
    _ => fail("suggestions 形态异常")
  }
  // 改写 trap 条目（二轮审阅 P2 起 trap 段为整表替换语义——键集须
  // 全等，删键形态迁 rejects 测试负向锚；此处改写 E3061_double_free
  // 模板文本、占位符集原样保持 {freed_line}{alloc_line}）
  match top.get("trap_messages") {
    Some(Object(traps)) =>
      match traps.get("E3061_double_free") {
        Some(Object(entry)) => {
          entry.set(
            "template",
            Json::string(
              "覆盖探针 {freed_line} 行 {alloc_line} 行（占位符集原样）",
            ),
          )
          traps.set("E3061_double_free", Json::object(entry))
        }
        _ => fail("E3061_double_free 条目形态异常")
      }
    _ => fail("trap_messages 形态异常")
  }
  install_texts(j.stringify())
  // 覆盖正向：改写值可见
  assert_eq(
    suggestion_map.get("bubble_sort"),
    Some("覆盖语义探针——若可见即装载门生效"),
  )
  // trap 改写可见（整表替换后键仍在、文本已换）
  assert_eq(
    trap_messages.get("E3061_double_free").unwrap().template,
    "覆盖探针 {freed_line} 行 {alloc_line} 行（占位符集原样）",
  )
  // 其余键不受连坐（抽检一枚未动 trap 键——lean 基态建议表为空）
  assert_true(trap_messages.get("hint_uaf") is Some(_))
  // 恢复：原载荷回装 → 基态回位（建议表回空、trap 回全量原文）
  install_texts(saved)
  assert_true(suggestion_map.get("bubble_sort") is None)
  assert_true(trap_messages.get("E3061_double_free") is Some(_))
}

///|
/// 审阅 P2（2026-10-17 二轮）：两类坏载荷加固证红——
/// ① 顶层未知键（junk 键须拒——旧只判键数 2||3，junk 顶替 trap 段位
///   静默通过）；② trap 段部分条目（键集须与现表全等——host 侧 20+ 处
///   unwrap 消费，部分替换 = 运行期 panic 面；语言包 texts_json 全量
///   段天然全等不受影响）。
test "install_texts_rejects_unknown_key_and_partial_trap" {
  let saved = texts_json()
  // ① 顶层未知键：junk 顶位
  let bad1 = "{\"suggestions\":{},\"builtin_notes\":{},\"junk\":{}}"
  let r1 = try? install_texts(bad1)
  assert_true(r1 is Err(_), msg="顶层未知键须 raise")
  // ② trap 段部分条目：删任一现表键（E3061_double_free）→ 键集不全等
  let j = @util.json_parse(saved) catch { _ => fail("原载荷解析失败") }
  match j {
    Object(top) =>
      match top.get("trap_messages") {
        Some(Object(traps)) => {
          ignore(traps.remove("E3061_double_free"))
          let r2 = try? install_texts(j.stringify())
          assert_true(
            r2 is Err(_),
            msg="trap 部分条目须 raise（host unwrap 消费面）",
          )
        }
        _ => fail("trap 段形态异常")
      }
    _ => fail("顶层形态异常")
  }
  // 空表装载（合法 lean 态）不受连坐：trap 段缺席路径
  let r3 = try? install_texts("{\"suggestions\":{},\"builtin_notes\":{}}")
  assert_true(r3 is Ok(_), msg="两键合法载荷不受新闸误伤")
  install_texts(saved)
}

///|
/// fail loud 三态（J9 同族：判据自身先证红——坏载荷必须 raise 而非
/// 静默 default / 半装）：坏 JSON / suggestions 未知键（值域闸）/
/// trap 占位符声明与模板不符（装载面复用 contract 同判据）。
test "install_texts_rejects_bad_payloads" {
  let saved = texts_json()
  // ① 坏 JSON
  let raised1 = try? install_texts("{not json")
  assert_true(raised1 is Err(_), msg="坏 JSON 须 raise")
  // ② suggestions 未知键（值域：引擎侧 43 名单外一律拒——防 strng-typo
  // 类拼写漂移静默入表）
  let bad2 = "{\"suggestions\":{\"strng_typo_probe\":\"x\"},\"builtin_notes\":{},\"trap_messages\":{}}"
  let raised2 = try? install_texts(bad2)
  assert_true(raised2 is Err(_), msg="未知 suggestion 键须 raise")
  // ③ trap 占位符声明与模板不符（声明了 {name} 模板没有）
  let bad3 = "{\"suggestions\":{},\"builtin_notes\":{},\"trap_messages\":{\"E3061_probe\":{\"template\":\"无占位符正文\",\"placeholders\":[\"name\"]}}}"
  let raised3 = try? install_texts(bad3)
  assert_true(raised3 is Err(_), msg="占位符不符须 raise")
  // fail loud 不落半装：三次拒绝后表仍基态（trap 抽检——lean 基态
  // 建议表为空，无从抽检）
  assert_true(trap_messages.get("E3061_double_free") is Some(_))
  ignore(saved)
}
