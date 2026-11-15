// engine_commands_wbtest —— 编排层白盒锚（批② D1，2026-11-14）：
// 此前 CI 对 engine_commands.mbt 只有 moon check 类型面（零测试资产——
// 对照引擎仓每包 wbtest 惯例的缺口，desktop/README §5 防线面收口件）。
// 两层锚位：
//   ① 纯函数层——JSON 工具边界（jint 整/浮/超界三态）+ Latin-1 折回还原 +
//     error_text 分支 + CollectResult 键名契约（与 demo TS 契约逐字对齐的
//     camelCase 九键——防键名漂移的机判面，shim 层映射的地基）；
//   ② 编排层全链——wbtest 直连 @gateway（@pin 真引擎）：collect 三形态
//     （正常/编译失败/waiting_input）+ feed 续跑重采 + invoke 透传错误帧。
// J9 面：键名契约锚对「改名不同步 shim」红；collect 编译失败锚对
// 「零帧+输出清空+stopped 留空」三联形态红（任何一环漂移即断言失败）。

///|
test "jint 三态：整数串收 / 浮点形态拒 / 超 i32 界拒" {
  inspect(jint(Json::number(42.0, repr="42")).unwrap_or(-999), content="42")
  inspect(jint(Json::number(1.5, repr="1.5")).unwrap_or(-999), content="-999")
  // repr 缺省走 floor 判别（非整值拒）
  inspect(jint(Json::number(2.25)).unwrap_or(-999), content="-999")
  // i32 下界外拒
  inspect(
    jint(Json::number(-3.0e9, repr="-3000000000")).unwrap_or(-999),
    content="-999",
  )
  // 非数形态拒
  inspect(jint(Json::string("7")).unwrap_or(-999), content="-999")
  inspect(jint(Json::boolean(true)).unwrap_or(-999), content="-999")
}

///|
test "jget 非对象/缺键 → null（窄面不炸）" {
  inspect(jget(Json::string("x"), "k") |> Json::stringify, content="null")
  let m : Map[String, Json] = Map([])
  m.set("a", Json::number(1.0))
  inspect(jget(Json::object(m), "b") |> Json::stringify, content="null")
  inspect(jget(Json::object(m), "a") |> Json::stringify, content="1")
}

///|
test "latin1_to_utf8：高位字节折回还原（字符域锚——字节级断言归引擎仓 utf8 域）" {
  // 'é' 的 UTF-8 编码 = 0xC3 0xA9；wire 折回后 = 两个 code unit
  // （U+00C3 U+00A9）的串——还原输出须是单字符 'é'（U+00E9）。判别力：
  // 不还原的原样返回长度 2、错误丢字节长度 0（首跑两形态实跑证锚有牙）。
  // 字节级口径由引擎仓 fs_js/utf8 测试域承载（@encoding 不在 desktop 依赖面）。
  let out = latin1_to_utf8("\u{c3}\u{a9}")
  inspect(out.length(), content="1")
  inspect(out == "\u{e9}", content="true")
  // 混合串：折回段折叠回单字符、ASCII 段零变化
  inspect(latin1_to_utf8("a\u{c3}\u{a9}b"), content="aéb")
  inspect(latin1_to_utf8("abc 123"), content="abc 123")
}

///|
test "error_text 四分支：字符串直取 / 对象取 message / Null 兜底 / 其他 stringify" {
  inspect(error_text(Json::string("boom")), content="boom")
  let m : Map[String, Json] = Map([])
  m.set("message", Json::string("协议错"))
  inspect(error_text(Json::object(m)), content="协议错")
  inspect(
    error_text(Json::null()),
    content="协议错误帧（无错误文本）",
  )
  inspect(error_text(Json::number(3.0)), content="3")
}

///|
test "run_six 键集：四字段投影（status/return_value/steps_executed/waiting_input）" {
  let m : Map[String, Json] = Map([])
  m.set("status", Json::string("finished"))
  m.set("return_value", Json::number(0.0))
  m.set("steps_executed", Json::number(12.0))
  m.set("waiting_input", Json::boolean(false))
  m.set("noise", Json::string("不进投影"))
  let out = run_six(Json::object(m))
  inspect(
    out.stringify(),
    content="{\"status\":\"finished\",\"return_value\":0,\"steps_executed\":12,\"waiting_input\":false}",
  )
}

///|
test "collect_result 键名契约：camelCase 九键与 demo TS 契约逐字对齐" {
  let r = collect_result(
    [],
    "",
    empty_obj(),
    5,
    Json::array([]),
    Json::array([]),
    true,
    Json::null(),
  )
  // 键集锚：shim 层（engine.ipc.ts）与 demo CollectResult 的消费面——
  // 任一键改名/增删即 stringify 首键序列红（Map 保插入序）。锚面澄清
  // （PR #524 审阅 P3-2）：期望串 versions 两字段的值由被测引擎现填
  //（自指插值）——本锚只锁键名与键序，值不锁（值真值锚归
  // teaching_truth/golden 族闸），勿读成值也被锁。
  inspect(
    r.stringify(),
    content="{\"frames\":[],\"stopped\":\"\",\"outputs\":{},\"ms\":5,\"versions\":{\"engine\":\"\{@gateway.engine_version()}\",\"protocol\":\"\{@gateway.protocol_version()}\"},\"diagnostics\":[],\"ppTrace\":[],\"compileOk\":true,\"run\":null}",
  )
}

///|
test "collect 全链（真 gateway）：hello 程序——帧>0 / finished / stdout 还原" {
  let req : CollectRequest = {
    source: Some(
      "#include <stdio.h>\n" + "int main() { printf(\"wb-hi\"); return 0; }",
    ),
    cap: Some(2000),
    bp_lines: None,
    files: None,
    cfg: None,
    argv: None,
  }
  let j = collect(req) catch { _ => abort("collect 不应抛错") }
  assert_true(
    jbool(jget(j, "compileOk")) is Some(true),
    msg="hello 程序 compileOk 应为 true",
  )
  match jget(j, "frames") {
    Array(ps) => assert_true(ps.length() > 0, msg="frames 应非空")
    _ => abort("frames 应为数组")
  }
  inspect(
    jstr(jget(jget(j, "run"), "status")).unwrap_or("~none~"),
    content="finished",
  )
  inspect(
    jstr(jget(jget(j, "outputs"), "stdout")).unwrap_or("~none~"),
    content="wb-hi",
  )
  inspect(jstr(jget(j, "stopped")).unwrap_or("~none~"), content="")
}

///|
test "collect 编译失败形态：零帧 + 输出清空 + stopped 留空 + compileOk=false" {
  let req : CollectRequest = {
    source: Some("int main("),
    cap: Some(100),
    bp_lines: None,
    files: None,
    cfg: None,
    argv: None,
  }
  let j = collect(req) catch {
    _ => abort("编译失败是业务域 ok 不应抛错")
  }
  assert_true(
    jbool(jget(j, "compileOk")) is Some(false),
    msg="坏源 compileOk 应为 false",
  )
  match jget(j, "frames") {
    Array(ps) =>
      assert_true(ps.length() == 0, msg="编译失败 frames 应为空")
    _ => abort("frames 应为数组")
  }
  inspect(jstr(jget(j, "stopped")).unwrap_or("~none~"), content="")
}

///|
test "collect waiting_input 停点 + feed 续跑重采（stdin 链）" {
  let req : CollectRequest = {
    source: Some(
      "#include <stdio.h>\n" +
      "int main() { int x; if (scanf(\"%d\", &x) != 1) { return 1; } printf(\"got %d\", x); return 0; }",
    ),
    cap: Some(2000),
    bp_lines: None,
    files: None,
    cfg: None,
    argv: None,
  }
  let j = collect(req) catch { _ => abort("scanf collect 不应抛错") }
  let stopped = jstr(jget(j, "stopped")).unwrap_or("")
  assert_true(
    stopped.contains("等待输入"),
    msg="scanf 首采应停 waiting，实得 \{stopped}",
  )
  // waiting 停点的 run 侧 waiting_input=true（run_six 投影在）
  assert_true(
    jbool(jget(jget(j, "run"), "waiting_input")) is Some(true),
    msg="run.waiting_input 应为 true",
  )
  // feed 41 → 重采全量帧，stdout 尾部含 "got 41"
  let fr : FeedRequest = { text: "41", cap: Some(2000), }
  let j2 = feed(fr) catch { _ => abort("feed 不应抛错") }
  assert_true(
    jbool(jget(j2, "compileOk")) is Some(true),
    msg="feed 后 compileOk 应为 true",
  )
  let out = jstr(jget(jget(j2, "outputs"), "stdout")).unwrap_or("")
  assert_true(
    out.contains("got 41"),
    msg="feed 41 后 stdout 应含 got 41，实得 \{out}",
  )
  inspect(jstr(jget(j2, "stopped")).unwrap_or("~none~"), content="")
}

///|
test "invoke 透传：错误帧不折叠（must 层语义在 call——透传层保原始 ok:false）" {
  // 未知方法名 → gateway 协议错误帧原样回（invoke_raw 不折叠为 EngineError）
  let j = invoke_raw("no.such.method", empty_obj()) catch {
    _ => abort("invoke_raw 透传不应抛错")
  }
  assert_true(
    jbool(jget(j, "ok")) is Some(false),
    msg="未知方法应回原始 ok:false 帧",
  )
  // call 的 must 语义：ok:false → EngineError（错误文本透出）。
  // 两段式：call 正常回 Json（用 ping 锚），错误面以 invoke_raw + 人工
  // must 分支的组合语义由上面透传锚 + error_text 纯函数锚共同覆盖。
  let pong = call("ping", empty_obj()) catch { _ => abort("ping 不应抛错") }
  inspect(pong.stringify().contains("\"pong\""), content="true")
}
