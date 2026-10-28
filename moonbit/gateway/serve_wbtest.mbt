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
/// #318（2026-10-26）：NDJSON 首行 UTF-8 BOM（U+FEFF）剥离——PowerShell
/// 管道默认加 BOM，此前首帧整帧判「非法 JSON」被吞（id:null 错误帧
/// 顶替，下游按 id 匹配永远等不到）+ 级联 not_compiled。两锚：BOM+合法
/// 帧正常解析回 id（不被吞）/ BOM+真坏帧仍报非法 JSON（剥 BOM 不是放水）。
test "serve_ndjson_bom_first_frame_issue318" {
  let bom = Int32::unsafe_to_char(0xFEFF).to_string()
  let s = @session.Session::new()
  let (resp, stop) = serve_handle(s, bom + "{\"id\":1,\"method\":\"ping\"}")
  assert_false(stop)
  assert_true(
    resp.contains("\"id\":1"),
    msg="BOM 首帧不得被吞（id 回填）",
  )
  assert_true(resp.contains("\"pong\":true"), msg="剥 BOM 后帧正常解析")
  // 剥 BOM 不是放水：真坏帧仍报非法 JSON
  let (resp2, _) = serve_handle(s, bom + "{not json")
  assert_true(resp2.contains("非法 JSON"))
}

///|
test "serve_missing_method_rejected" {
  let s = @session.Session::new()
  let (resp, _) = serve_handle(s, "{\"id\":7}")
  assert_true(resp.contains("缺少 method"))
  // #68（2026-10-11）：缺 method 帧也带形状（请求顶层字段非 params）
  assert_true(
    resp.contains("\"expected\":\"method:string\""),
    msg="缺 method 帧 expected 字段",
  )
}

///|
test "serve_error_frame_keys_gated" {
  // #68 键集闸（2026-10-11）：错误帧 error 对象键集 ⊆
  // @protocol.error_frame_fields_v0_1()（protocol 包白名单，先建闸再上帧
  // ——防野生键第二套手拼面）。白名单扩键须先改 schema 再上帧，本闸连坐。
  let frame = serve_param_err(
    Json::number(1),
    "x 需要 params.y:string",
    "y:string",
  )
  let j = @util.json_parse(frame.stringify()) catch {
    _ => {
      fail("自产参数错误帧必须可解析")
      return
    }
  }
  match j {
    Object(top) =>
      match top.get("error") {
        Some(Object(e)) => {
          for k in e.keys() {
            assert_true(
              @protocol.error_frame_fields_v0_1().contains(k),
              msg="错误帧野生键（须先进 error_frame_fields_v0_1() 白名单）: \{k}",
            )
          }
          assert_true(
            e.contains("expected"),
            msg="参数错误帧必须携带 expected（机器可读形状）",
          )
        }
        _ => {
          fail("error 字段必须为对象")
          return
        }
      }
    _ => {
      fail("帧必须为对象")
      return
    }
  }
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
  // 帧结构锚（2026-09-28 批四号双宿主对拍实锤补）：响应必须是
  // serve_ok 帧（id 回填 + ok:true + result 承载 config）——一段写成
  // 裸 config 对象（无帧包装），serve_smoke MoonBit 臂「id 一一对应/
  // 帧同构」两断言红后修复；contains 数字形态的旧锚不锁帧结构故未暴露
  assert_true(
    resp.has_prefix("{\"id\":9,\"ok\":true,\"result\":{"),
    msg="serve_ok 帧包装",
  )
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
  let v = @util.json_parse(src)
  let out = v.stringify()
  // 再解析回等值（往返稳定性）
  let v2 = @util.json_parse(out)
  assert_true(v == v2, msg="parse→stringify→parse 必须等值")
}

///|
test "json_parse_number_repr_fidelity" {
  // repr 保真：42 不 stringify 成 42.0（core Json repr~ 通道）
  let v = @util.json_parse("{\"n\":42}")
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
  let bs = Int32::unsafe_to_char(92).to_string()
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
  let v = @util.json_parse(json_in)
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
      ignore(@util.json_parse(s))
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
  let v = @util.json_parse("[-0,1e-3,2E+4,3.14]")
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
  for _ in 0..<200 {
    deep = deep + "["
  }
  for _ in 0..<200 {
    deep = deep + "]"
  }
  let r : Result[Json, @util.JsonParseError] = Ok(@util.json_parse(deep)) catch {
    e => Err(e)
  }
  assert_true(r is Err(_), msg="200 层深嵌套必须被拒（超 128 限）")
}

///|
test "json_parse_number_grammar_rfc8259" {
  // RFC 8259 禁止形态：前导零（01）/ 裸点（.5 / 1.）/ 悬空指数（1e / 1e+）
  fn rejects(s : String) -> Bool {
    try {
      ignore(@util.json_parse(s))
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

// ── openseek 对照纪律批 ②（总计划批四号段排期）：serve 帧 golden 锚 ──
// 单编码者原则「同一帧两个书写者不得有两种拼法」——serve_ok/serve_err
// 结构钉死（字段序 + null id 形态），批四号双宿主对拍的帧契约基线；
// MoonBit 出口与 gen_protocol_ts 生成器是 Vitro 的双写面（openseek
// 实证：双写漂移直到穷举解码才被发现）。

///|
test "serve_ok_frame_golden_shape" {
  let m : Map[String, Json] = Map([])
  m.set("pong", Json::boolean(true))
  let frame = serve_ok(Json::number(7), Json::object(m))
  assert_eq(
    frame.stringify(),
    "{\"id\":7,\"ok\":true,\"result\":{\"pong\":true}}",
    msg="serve_ok 帧 golden（字段序：id/ok/result）",
  )
  // 字符串 id 原样回填（异步竞态对账场景）
  let frame2 = serve_ok(Json::string("abc"), Json::object(m))
  assert_eq(
    frame2.stringify(),
    "{\"id\":\"abc\",\"ok\":true,\"result\":{\"pong\":true}}",
    msg="字符串 id golden",
  )
}

///|
test "serve_err_frame_golden_shape" {
  let frame = serve_err(Json::null(), "protocol", "未知方法：x")
  assert_eq(
    frame.stringify(),
    "{\"id\":null,\"ok\":false,\"error\":{\"kind\":\"protocol\",\"message\":\"未知方法：x\"}}",
    msg="serve_err 帧 golden（kind/message 字段序 + null id 形态）",
  )
}

///|
/// #133 止血包锚（2026-10-16）：preset 三档语义——algo 档展开值、显式键
/// 覆盖（custom 推断）、非法档名 fail loud、max_steps 超域 fail loud
/// （静默跳过旧 bug——as_int()=None 走缺省分支响应 ok 配置不变）。
test "config_preset_algo_expands" {
  let s = @session.Session::new()
  let (resp, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"config.set\",\"params\":{\"preset\":\"algo\"}}",
  )
  assert_true(resp.contains("\"ok\":true"), msg="algo 档应 ok")
  let (g, _) = serve_handle(s, "{\"id\":2,\"method\":\"config.get\"}")
  assert_true(g.contains("\"max_steps\":2000000000"), msg="algo 档步数 2e9")
  assert_true(
    g.contains("\"call_depth_limit\":100000"),
    msg="algo 档深度 100K",
  )
  assert_true(
    g.contains("\"max_checkpoints\":200"),
    msg="algo 档检查点保留数 200（#87 批——大搜索时间轴采样密度）",
  )
  assert_true(
    g.contains("\"preset\":\"algo\""),
    msg="config.get 回显 algo 档",
  )
}

///|
test "config_preset_explicit_key_overrides_to_custom" {
  let s = @session.Session::new()
  let (_, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"config.set\",\"params\":{\"preset\":\"algo\",\"max_steps\":500000000}}",
  )
  let (g, _) = serve_handle(s, "{\"id\":2,\"method\":\"config.get\"}")
  assert_true(
    g.contains("\"max_steps\":500000000"),
    msg="显式键覆盖 preset 值",
  )
  assert_true(
    g.contains("\"preset\":\"custom\""),
    msg="覆盖后档名诚实推断 custom（非记名）",
  )
  assert_true(
    g.contains("\"call_depth_limit\":100000"),
    msg="未覆盖键保持档值",
  )
}

///|
test "config_preset_unknown_name_fails_loud" {
  let s = @session.Session::new()
  let (resp, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"config.set\",\"params\":{\"preset\":\"bogus\"}}",
  )
  assert_true(
    resp.contains("\"ok\":false") &&
    resp.contains("preset 值 'bogus' 不存在"),
    msg="非法档名 param_err（静默忽略=开关形同虚设）",
  )
}

///|
test "config_max_steps_overflow_fails_loud" {
  let s = @session.Session::new()
  // #131 实锤形态：3e9 超 Int32 域曾静默跳过（响应 ok 配置不变）
  let (resp, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"config.set\",\"params\":{\"max_steps\":3000000000}}",
  )
  assert_true(resp.contains("\"ok\":false"), msg="超域必须 fail loud")
  assert_true(
    resp.contains("值 3000000000 超出可表示上限"),
    msg="报错含值与范围（报错即文档）",
  )
  // 配置保持原值（未被静默改动）
  let (g, _) = serve_handle(s, "{\"id\":2,\"method\":\"config.get\"}")
  assert_true(g.contains("\"max_steps\":10000000"), msg="配置未被改动")
}

///|
test "config_preset_default_resets" {
  let s = @session.Session::new()
  let (_, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"config.set\",\"params\":{\"preset\":\"algo\"}}",
  )
  let (_, _) = serve_handle(
    s, "{\"id\":2,\"method\":\"config.set\",\"params\":{\"preset\":\"default\"}}",
  )
  let (g, _) = serve_handle(s, "{\"id\":3,\"method\":\"config.get\"}")
  assert_true(
    g.contains("\"max_steps\":10000000") && g.contains("\"preset\":\"default\""),
    msg="default 档拉回缺省（档内显式展开非空操作）",
  )
}

///|
/// #87 批锚：config.set max_checkpoints 全生命周期——写入/回显/preset
/// 推断、step.begin 建 engine 应用、现存 engine 即时应用、低下界钳制
/// （clamped 显式）、上界 1000 fail loud（内存防线）。
test "config_max_checkpoints_lifecycle" {
  let s = @session.Session::new()
  // 写入 + 回显（其余键全缺省 ⇒ preset 诚实推断 custom）
  let (r1, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"config.set\",\"params\":{\"max_checkpoints\":200}}",
  )
  assert_true(r1.contains("\"ok\":true"), msg="合法值应 ok")
  assert_true(r1.contains("\"clamped\":[]"), msg="200 无钳制")
  let (g1, _) = serve_handle(s, "{\"id\":2,\"method\":\"config.get\"}")
  assert_true(g1.contains("\"max_checkpoints\":200"), msg="get 回显 200")
  assert_true(
    g1.contains("\"preset\":\"custom\""),
    msg="单键改档名诚实推断 custom",
  )
  // compile + step.begin：建 engine 时应用会话值
  let (c, _) = serve_handle(
    s, "{\"id\":3,\"method\":\"compile\",\"params\":{\"source\":\"int main() { int a = 1; a = a + 1; return a; }\\n\"}}",
  )
  assert_true(c.contains("\"ok\":true"), msg="编译须成功")
  ignore(serve_handle(s, "{\"id\":4,\"method\":\"step.begin\"}"))
  guard s.unified is Some(e1) else { fail("engine 须挂 Session") }
  assert_eq(
    e1.checkpoints.max_checkpoints,
    200,
    msg="step.begin 应用会话值",
  )
  // 现存 engine 即时应用（不等下次 step.begin）
  let (r2, _) = serve_handle(
    s, "{\"id\":5,\"method\":\"config.set\",\"params\":{\"max_checkpoints\":300}}",
  )
  assert_true(r2.contains("\"ok\":true"))
  guard s.unified is Some(e2) else { fail("engine 存活") }
  assert_eq(
    e2.checkpoints.max_checkpoints,
    300,
    msg="现存 engine 即时应用",
  )
  // 低下界钳 1 + clamped 显式（engine 与回显同步钳）
  let (r3, _) = serve_handle(
    s, "{\"id\":6,\"method\":\"config.set\",\"params\":{\"max_checkpoints\":0}}",
  )
  assert_true(
    r3.contains("\"clamped\":[\"max_checkpoints\"]"),
    msg="钳制显式",
  )
  guard s.unified is Some(e3) else { fail("engine 存活") }
  assert_eq(e3.checkpoints.max_checkpoints, 1, msg="engine 同步钳 1")
  let (g3, _) = serve_handle(s, "{\"id\":7,\"method\":\"config.get\"}")
  assert_true(g3.contains("\"max_checkpoints\":1"), msg="get 回显钳后值")
  // 上界 1000 fail loud（内存防线：每约 5 个检查点 1MB Full 快照）
  let (r4, _) = serve_handle(
    s, "{\"id\":8,\"method\":\"config.set\",\"params\":{\"max_checkpoints\":1001}}",
  )
  assert_true(
    r4.contains("\"ok\":false") && r4.contains("max_checkpoints 值不可用"),
    msg="超上界 fail loud（静默钳制=内存防线缺口）",
  )
  guard s.unified is Some(e4) else { fail("engine 存活") }
  assert_eq(e4.checkpoints.max_checkpoints, 1, msg="失败帧不改变现值")
  // P3-3（PR #342 审阅处置）：收缩即时淘汰——放宽存 8 锚后收紧到 5，
  // 内存防线不等下次 save 当场回收
  let (r6, _) = serve_handle(
    s, "{\"id\":9,\"method\":\"config.set\",\"params\":{\"max_checkpoints\":10}}",
  )
  assert_true(r6.contains("\"ok\":true"))
  guard s.unified is Some(e5) else { fail("engine 存活") }
  e5.checkpoints.clear()
  for st in [1, 2, 3, 4, 5, 6, 7, 8] {
    e5.checkpoints.save(st, s.vm)
  }
  assert_eq(e5.checkpoints.length(), 8, msg="K=10 下 8 锚全保留")
  ignore(
    serve_handle(
      s, "{\"id\":10,\"method\":\"config.set\",\"params\":{\"max_checkpoints\":5}}",
    ),
  )
  assert_true(
    e5.checkpoints.length() <= 5,
    msg="收缩即时淘汰（不等下次 save 回收）",
  )
}
