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
  ignore(install_texts(j0))
  let j1 = texts_json()
  inspect(j1, content=j0)
}

///|
/// 覆盖可见：改一条 suggestion、改一条 trap → 查表即时反映；恢复原载荷
/// → 全量回位（可覆盖化的正向与逆向双证——装载不是一次性烧死）。
test "install_texts_override_visible_and_restorable" {
  // lean 基态（批③a：suggestions/builtin 空载体 + trap 烘焙 45）——
  // 覆盖语义探针自带 fixture 键（bubble_sort），不依赖烘焙建议表
  let saved = texts_json()
  let orig_tpl = trap_messages.get("E3061_double_free").unwrap().template
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
  // 改写 trap 条目（#323 起段级合并语义——单键覆盖即可，此处改写
  // E3061_double_free 模板文本、占位符集原样保持 {freed_line}{alloc_line}）
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
  ignore(install_texts(j.stringify()))
  // 覆盖正向：改写值可见
  assert_eq(
    suggestion_map.get("bubble_sort"),
    Some("覆盖语义探针——若可见即装载门生效"),
  )
  // trap 改写可见（合并覆盖后键仍在、文本已换）
  assert_eq(
    trap_messages.get("E3061_double_free").unwrap().template,
    "覆盖探针 {freed_line} 行 {alloc_line} 行（占位符集原样）",
  )
  // 其余键不受连坐（抽检一枚未动 trap 键——lean 基态建议表为空）
  assert_true(trap_messages.get("hint_uaf") is Some(_))
  // 恢复：trap 全段回装（合并覆盖回原文）+ 建议表显式清空（#323 起
  // 空段=不覆盖，清场须 __clear__ 显式形态）
  let _ = install_texts(saved) catch { _ => fail("恢复装载失败") }
  let cleared = install_texts("{\"suggestions\":{\"__clear__\":true}}") catch {
    _ => fail("清空段装载失败")
  }
  assert_eq(cleared, ["suggestions"], msg="清空段须回告段名")
  assert_true(suggestion_map.get("bubble_sort") is None)
  assert_eq(
    trap_messages.get("E3061_double_free").unwrap().template,
    orig_tpl,
    msg="trap 全段回装须恢复原文",
  )
}

///|
/// #323 合并语义契约（2026-10-27，治②/④）：段全可选（单段/空对象
/// 合法）、段内逐键合并（未提供键保持）、幽灵 trap 键拒（值域=现表
/// 键集——host 侧 unwrap 消费面防护换形态保留：合并只增改不删）、
/// `{"__clear__":true}` 显式清空且回告段名、__clear__ 混数据键拒。
/// 旧「顶层两必填 + trap 键集全等」两闸在本测试下红（红锚形态见
/// issue #323 实测表）。
test "install_texts_merge_and_gates" {
  let saved = texts_json()
  // ① 顶层未知键：junk 顶位（闸保持）
  let bad1 = "{\"suggestions\":{},\"builtin_notes\":{},\"junk\":{}}"
  let r1 = Ok(install_texts(bad1)) catch { e => Err(e) }
  assert_true(r1 is Err(_), msg="顶层未知键须 raise")
  // ② 单段载荷合法（旧拒「顶层须含 suggestions/builtin_notes，实得 1 键」）
  let r2 = Ok(
    install_texts("{\"suggestions\":{\"bubble_sort\":\"单段探针\"}}"),
  ) catch {
    e => Err(e)
  }
  assert_true(r2 is Ok(_), msg="单段载荷须合法（#323 治②）")
  assert_eq(suggestion_map.get("bubble_sort"), Some("单段探针"))
  // ③ 空段对象 = 不覆盖（旧 = 静默清空 43 条教学表——#323 硬伤②）
  let r3 = Ok(install_texts("{\"suggestions\":{},\"builtin_notes\":{}}")) catch {
    e => Err(e)
  }
  assert_true(r3 is Ok(_), msg="空段载荷须合法")
  assert_eq(
    suggestion_map.get("bubble_sort"),
    Some("单段探针"),
    msg="空段不得清空（静默清空硬伤）",
  )
  // ④ trap 部分键：单键覆盖合法 + 未提供键保持 + 幽灵键拒
  let r4 = Ok(
    install_texts(
      "{\"trap_messages\":{\"E3061_double_free\":{\"template\":\"部分表探针 {freed_line}{alloc_line}\",\"placeholders\":[\"freed_line\",\"alloc_line\"]}}}",
    ),
  ) catch {
    e => Err(e)
  }
  assert_true(
    r4 is Ok(_),
    msg="trap 部分键须合法（合并非整表替换）",
  )
  assert_eq(
    trap_messages.get("E3061_double_free").unwrap().template,
    "部分表探针 {freed_line}{alloc_line}",
  )
  assert_true(
    trap_messages.get("hint_uaf") is Some(_),
    msg="未提供键保持",
  )
  let r5 = Ok(
    install_texts(
      "{\"trap_messages\":{\"ghost_key_probe\":{\"template\":\"x\",\"placeholders\":[]}}}",
    ),
  ) catch {
    e => Err(e)
  }
  assert_true(
    r5 is Err(_),
    msg="幽灵 trap 键须拒（值域=现表键集）",
  )
  // ⑤ __clear__：恰单键 true = 显式清空 + 回告；混数据键 = 拒
  let c1 = Ok(install_texts("{\"suggestions\":{\"__clear__\":true}}")) catch {
    e => Err(e)
  }
  assert_true(c1 is Ok(_), msg="__clear__ 单键形态须合法")
  assert_eq(
    c1.unwrap(),
    ["suggestions"],
    msg="清空须回告段名（可观测）",
  )
  assert_true(suggestion_map.get("bubble_sort") is None)
  let r6 = Ok(
    install_texts(
      "{\"suggestions\":{\"__clear__\":true,\"bubble_sort\":\"x\"}}",
    ),
  ) catch {
    e => Err(e)
  }
  assert_true(
    r6 is Err(_),
    msg="__clear__ 混数据键须拒（半清空歧义形态）",
  )
  // ⑥ 顶层空对象 = 全 no-op（读-改-写闭环的零动作形态）
  let r7 = Ok(install_texts("{}")) catch { e => Err(e) }
  assert_true(r7 is Ok(_), msg="空对象须 no-op 合法")
  // 恢复：trap 全段回装 + 建议表已清（幂等再清无害）
  let _ = install_texts(saved) catch { _ => fail("恢复装载失败") }
  let _ = install_texts("{\"suggestions\":{\"__clear__\":true}}") catch {
    _ => fail("清空段装载失败")
  }
  assert_true(trap_messages.get("E3061_double_free") is Some(_))
}

///|
/// fail loud 三态（J9 同族：判据自身先证红——坏载荷必须 raise 而非
/// 静默 default / 半装）：坏 JSON / suggestions 未知键（值域闸）/
/// trap 占位符声明与模板不符（装载面复用 contract 同判据；#323 起
/// 用**现表既有键**锚契约——幽灵键拒是另一闸，勿再借幽灵键形态锚）。
test "install_texts_rejects_bad_payloads" {
  let saved = texts_json()
  // ① 坏 JSON
  let raised1 = Ok(install_texts("{not json")) catch { e => Err(e) }
  assert_true(raised1 is Err(_), msg="坏 JSON 须 raise")
  // ② suggestions 未知键（值域：引擎侧 43 名单外一律拒——防 strng-typo
  // 类拼写漂移静默入表）
  let bad2 = "{\"suggestions\":{\"strng_typo_probe\":\"x\"}}"
  let raised2 = Ok(install_texts(bad2)) catch { e => Err(e) }
  assert_true(raised2 is Err(_), msg="未知 suggestion 键须 raise")
  // ③ trap 占位符声明与模板不符（声明了 {name} 模板没有——既有键上锚
  // 契约判据）
  let bad3 = "{\"trap_messages\":{\"E3061_double_free\":{\"template\":\"无占位符正文\",\"placeholders\":[\"name\"]}}}"
  let raised3 = Ok(install_texts(bad3)) catch { e => Err(e) }
  assert_true(raised3 is Err(_), msg="占位符不符须 raise")
  // fail loud 不落半装：三次拒绝后表仍基态（trap 抽检——lean 基态
  // 建议表为空，无从抽检）
  assert_true(trap_messages.get("E3061_double_free") is Some(_))
  ignore(saved)
}
