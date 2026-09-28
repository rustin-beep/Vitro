// serve 协议层白盒锚（S7 批三号一段）：serve_handle 纯函数直测——帧同构
// /id 回填/非法 JSON/session 生命周期/config echo/shutdown 停。
// serve_smoke 全量对拍随批四号接线（Go 驱动加 MoonBit 臂）。

///|
test "serve_ping_frame_isomorphism" {
  let s = @session.Session::new()
  let (resp, stop) = serve_handle(s, "{\"id\":1,\"method\":\"ping\"}")
  assert_false(stop)
  // 帧同构：id 回填 + ok:true + result.pong
  assert_true(resp.has_prefix("{\"id\":"))
  assert_true(resp.contains("\"ok\":true"))
  assert_true(resp.contains("\"pong\":true"))
}

///|
test "serve_id_echo_preserves_value" {
  let s = @session.Session::new()
  // 字符串 id（异步竞态对账场景）
  let (resp, _) = serve_handle(s, "{\"id\":\"abc\",\"method\":\"ping\"}")
  assert_true(
    resp.contains("\"id\":\"abc\""),
    msg="字符串 id 必须原样回填",
  )
  // 数字 id
  let (resp2, _) = serve_handle(s, "{\"id\":42,\"method\":\"ping\"}")
  assert_true(resp2.contains("\"id\":42"))
}

///|
test "serve_illegal_json_error_frame" {
  let s = @session.Session::new()
  let (resp, stop) = serve_handle(s, "{not json")
  assert_false(
    stop,
    msg="非法 JSON 不退出（Rust 同——false 继续读）",
  )
  assert_true(resp.contains("\"ok\":false"))
  assert_true(resp.contains("\"kind\":\"protocol\""))
}

///|
test "serve_missing_method_rejected" {
  let s = @session.Session::new()
  let (resp, _) = serve_handle(s, "{\"id\":7}")
  assert_true(resp.contains("缺少 method"))
}

///|
test "serve_unknown_method_error" {
  let s = @session.Session::new()
  let (resp, _) = serve_handle(s, "{\"id\":2,\"method\":\"no_such\"}")
  assert_true(resp.contains("未知方法"))
  assert_true(resp.contains("\"ok\":false"))
}

///|
test "serve_session_lifecycle_preserves_config" {
  // create → set config → reset：会话级配置必须保留（R3 单源语义）
  let s = @session.Session::new()
  let (_, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"config.set\",\"params\":{\"max_steps\":2000,\"call_depth_limit\":48}}",
  )
  let (resp2, _) = serve_handle(s, "{\"id\":2,\"method\":\"session.reset\"}")
  assert_true(resp2.contains("\"reset\":true"))
  assert_true(
    resp2.contains("\"max_steps\":2000"),
    msg="reset 必须保留会话级配置",
  )
  assert_true(resp2.contains("\"call_depth_limit\":48"))
  // VM 侧同步保留（单一写入口双达语义的 reset 对偶）
  assert_eq(s.vm.max_steps, 2000)
  assert_eq(s.config.max_steps, 2000)
}

///|
test "serve_config_set_before_compile_effective" {
  // session_config_test 第四锚的 serve 通道版：无编译态时设置必须生效
  //（Rust capi 曾静默丢弃的形态——本侧 serve_handle 经 SessionConfig
  // 单一写入口，结构上不可丢弃；锚锁行为）
  let s = @session.Session::new()
  let (resp, _) = serve_handle(
    s, "{\"id\":9,\"method\":\"config.set\",\"params\":{\"max_steps\":777}}",
  )
  assert_true(resp.contains("\"max_steps\":777"), msg="config.set 回显")
  assert_eq(s.vm.max_steps, 777, msg="VM 侧生效（编译前设置不丢）")
}

///|
test "serve_shutdown_stops" {
  let s = @session.Session::new()
  let (resp, stop) = serve_handle(s, "{\"id\":3,\"method\":\"shutdown\"}")
  assert_true(stop, msg="shutdown 必须置停旗")
  assert_true(resp.contains("\"shutdown\":true"))
}

// ── json_parse 锚（自写标准 JSON 解析器——依赖清除批的替代实现）──

///|
test "json_parse_roundtrip_value_family" {
  // 值全族往返：对象/数组/字符串/数字（repr 保真）/布尔/null/嵌套
  let src = "{\"id\":42,\"method\":\"ping\",\"params\":{\"a\":[1,-2.5,3e2],\"b\":\"hi\\n\",\"c\":true,\"d\":false,\"e\":null}}"
  let v = json_parse(src)
  let out = v.stringify()
  // 再解析回等值（往返稳定性）
  let v2 = json_parse(out)
  assert_true(v == v2, msg="parse→stringify→parse 必须等值")
}

///|
test "json_parse_number_repr_fidelity" {
  // repr 保真：42 不 stringify 成 42.0（core Json repr~ 通道）
  let v = json_parse("{\"n\":42}")
  match v {
    Object(m) =>
      match m.get("n") {
        Some(Number(_, repr~)) => assert_eq(repr, Some("42"))
        _ => fail("应为 Number")
      }
    _ => fail("应为 Object")
  }
  assert_true(v.stringify().contains("\"n\":42"))
}

///|
test "json_parse_string_escapes" {
  // JSON 输入含全套转义（源码字面量经 chr(92) 构造防 bash/heredoc
  // 转义吃层——单反斜杠+t 会被 MoonBit 词法吃成真 TAB，陷阱 #37 族）
  let bs = Char::from_int(92).to_string()
  let json_in = "{\"s\":\"a" +
    bs +
    "tb" +
    bs +
    "nc" +
    bs +
    "u4e2d" +
    bs +
    bs +
    bs +
    "\"/\"}"
  let v = json_parse(json_in)
  match v {
    Object(m) =>
      match m.get("s") {
        Some(String(s)) => {
          assert_true(s.contains("a	b"))
          assert_true(s.contains("中"))
          assert_true(s.contains("\\"))
        }
        _ => fail("应为 String")
      }
    _ => fail("应为 Object")
  }
}

///|
test "json_parse_error_surface" {
  // 错误面：尾随内容/未闭合串/非法字面量/空对象数组合法
  fn fails(s : String) -> Bool {
    try {
      ignore(json_parse(s))
      false
    } catch {
      _ => true
    }
  }
  assert_true(fails("{\"a\":1} xx"), msg="尾随内容")
  assert_true(fails("{\"s\":\"unclosed"), msg="未闭合串")
  assert_true(
    fails("{a:1}"),
    msg="无引号键（JSON5 扩展——协议面外，必须拒）",
  )
  assert_true(fails("[1,]"), msg="尾逗号（JSON5 扩展——必须拒）")
  assert_false(fails("{}"), msg="空对象合法")
  assert_false(fails("[]"), msg="空数组合法")
  assert_false(fails("  {\"a\" : 1 }  "), msg="空白容忍")
}

///|
test "json_parse_negative_and_exp" {
  let v = json_parse("[-0,1e-3,2E+4,3.14]")
  match v {
    Array(a) => {
      assert_eq(a.length(), 4)
      let out = v.stringify()
      assert_true(out.contains("-0"))
      assert_true(out.contains("1e-3"))
      assert_true(out.contains("3.14"))
    }
    _ => fail("应为 Array")
  }
}

// ── 审阅八轮 P2②/P3③ 补锚（先证红后修）──

///|
test "json_parse_depth_limit_128" {
  // 深嵌套必须有界（serde_json 默认 128 层——serve 长驻进程的 DoS 面；
  // 审阅实测 20000 层栈溢出 0xc00000fd 不可捕获）
  // 合法闭合的深嵌套（200 开 + 200 闭——未闭合串会被语法错先拦，测不到深度）
  let mut deep = ""
  for i in 0..<200 {
    deep = deep + "["
  }
  for i in 0..<200 {
    deep = deep + "]"
  }
  let r : Result[Json, JsonParseError] = Ok(json_parse(deep)) catch {
    e => Err(e)
  }
  assert_true(r is Err(_), msg="200 层深嵌套必须被拒（超 128 限）")
}

///|
test "json_parse_number_grammar_rfc8259" {
  // RFC 8259 禁止形态：前导零（01）/ 裸点（.5 / 1.）/ 悬空指数（1e / 1e+）
  fn rejects(s : String) -> Bool {
    try {
      ignore(json_parse(s))
      false
    } catch {
      _ => true
    }
  }
  assert_true(rejects("01"), msg="前导零禁止（RFC 8259 number 文法）")
  assert_true(rejects("1."), msg="裸尾点禁止")
  assert_true(rejects(".5"), msg="裸前导点禁止")
  assert_true(rejects("1e"), msg="悬空指数禁止")
  assert_true(rejects("1e+"), msg="指数缺数字禁止")
  // 合法形态不误伤
  assert_false(rejects("0"))
  assert_false(rejects("0.5"))
  assert_false(rejects("1e5"))
  assert_false(rejects("-1.5e-3"))
}
