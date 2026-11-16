// timeline.plan 白盒锚（TimelinePlan v0.1 批一，2026-11-15，refs #470）：
// 只读帧区间 → {pv,steps[]} 零基同构 + 归属真名 + 区间参数 fail loud。
// 语料 = bubble_sort 单行形态（真实数组名 a；semantic_label 展示名 arr——
// #469 分叉面，归属必须按 vis_events context 落到 a）。

///|
fn timeline_probe_source() -> String {
  "int main() { int a[5] = {5,3,4,1,2}; for (int i = 0; i < 4; i++) for (int j = 0; j < 4-i; j++) if (a[j] > a[j+1]) { int t = a[j]; a[j] = a[j+1]; a[j+1] = t; } return a[0]; }"
}

///|
test "serve_timeline_plan_requires_step_begin" {
  let s = @session.Session::new()
  let (resp, _) = serve_handle(s, "{\"id\":1,\"method\":\"timeline.plan\"}")
  assert_true(resp.contains("\"kind\":\"state\""))
  assert_true(resp.contains("请先调用 vitro_step_begin"))
}

///|
test "serve_timeline_plan_range_param_fail_loud" {
  let s = @session.Session::new()
  ignore(
    serve_handle(
      s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int main() { return 0; }\\n\"}}",
    ),
  )
  ignore(serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}"))
  let (neg, _) = serve_handle(
    s, "{\"id\":3,\"method\":\"timeline.plan\",\"params\":{\"start\":-1}}",
  )
  assert_true(neg.contains("\"kind\":\"protocol\""))
  assert_true(neg.contains("start:int>=0"))
  let (rev, _) = serve_handle(
    s, "{\"id\":4,\"method\":\"timeline.plan\",\"params\":{\"start\":5,\"end\":2}}",
  )
  assert_true(rev.contains("\"kind\":\"protocol\""))
  assert_true(rev.contains("end:int>=start"))
  let (bad, _) = serve_handle(
    s, "{\"id\":5,\"method\":\"timeline.plan\",\"params\":{\"start\":1.5}}",
  )
  assert_true(bad.contains("\"kind\":\"protocol\""))
}

///|
test "serve_timeline_plan_alignment_and_real_name" {
  let s = @session.Session::new()
  let (c, _) = serve_handle(
    s,
    "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"\{timeline_probe_source()}\"}}",
  )
  assert_true(c.contains("\"ok\":true"), msg="编译须成功")
  ignore(serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}"))
  // 推进到出现若干交换帧（bubble_sort 单行形态首交换在 step 2/3）
  for i = 0; i < 80; i = i + 1 {
    ignore(serve_handle(s, "{\"id\":10,\"method\":\"step.next\"}"))
  }
  // 同区间双取：payload.get 是帧真值，timeline.plan 的 steps 必须与之等长
  let (pg, _) = serve_handle(
    s, "{\"id\":20,\"method\":\"payload.get\",\"params\":{\"start\":0}}",
  )
  let (tp, _) = serve_handle(
    s, "{\"id\":21,\"method\":\"timeline.plan\",\"params\":{\"start\":0}}",
  )
  assert_true(tp.contains("\"ok\":true"), msg="plan 成功帧")
  let pj = @util.json_parse(tp) catch { _ => abort("plan 帧非 JSON") }
  let res = json_field(pj, "result")
  assert_eq(json_field(res, "pv").as_int(), Some(2), msg="pv=2（v0.2）")
  let steps = match json_field(res, "steps") {
    Array(a) => a
    _ => abort("steps 非数组")
  }
  let payloads = match
    json_field(
      @util.json_parse(pg) catch {
        _ => abort("payload 帧非 JSON")
      },
      "result",
    ) {
    Object(m) =>
      match m.get("payloads") {
        Some(Array(a)) => a
        _ => abort("payloads 非数组")
      }
    _ => abort("payload result 非对象")
  }
  assert_eq(
    steps.length(),
    payloads.length(),
    msg="steps 与区间帧零基同构",
  )
  // 归属真名：至少一个 step 的 sw.name = "a"（字幕展示名是 arr）
  let mut sw_name = ""
  let mut sw_i = -1
  let mut sw_j = -1
  let mut sw_at = -1
  for k = 0; k < steps.length(); k = k + 1 {
    match json_field(steps[k], "sw") {
      Object(_) as sw =>
        if sw_name == "" {
          sw_name = jstr_or_like(json_field(sw, "name"))
          sw_i = json_field(sw, "i").as_int().unwrap_or(-1)
          sw_j = json_field(sw, "j").as_int().unwrap_or(-1)
          sw_at = k
        }
      _ => ()
    }
  }
  assert_eq(
    sw_name,
    "a",
    msg="sw.name = 真实数组名（非字幕展示名 arr）",
  )
  assert_true(sw_i >= 0 && sw_i < sw_j, msg="sw 下标升序合法")
  // cap.t 与同帧 semantic_label 同源（字幕文本不变）
  let cap_t = match json_field(steps[sw_at], "cap") {
    Object(_) as cap => jstr_or_like(json_field(cap, "t"))
    _ => ""
  }
  let label = jstr_or_like(json_field(payloads[sw_at], "semantic_label"))
  assert_eq(cap_t, label, msg="cap.t 同帧 semantic_label")
  // v0.2（批四）：首帧恒有 cam（初始镜头 fit=calltree）；交换帧 bar 在场
  let cam0 = json_field(steps[0], "cam")
  assert_eq(
    jstr_or_like(json_field(cam0, "fit")),
    "calltree",
    msg="首帧 cam.fit=calltree",
  )
  let bar_j = json_field(steps[sw_at], "bar")
  assert_true(bar_j is Object(_), msg="数值数组帧 bar 对象在场")
}

///|
/// 测试内轻量字符串取值（Json 非 String 时返 ""）。
fn jstr_or_like(v : Json) -> String {
  match v {
    String(s) => s
    _ => ""
  }
}

///|
/// P1-1 回归锚（PR #530 审阅）：同名数组快照（全局数组 + 数组形参解引用
/// 视图双发 `arr`）不得被当成归属歧义——plan 必须与 MCP 面一样点亮交换。
test "serve_timeline_plan_same_name_snapshots_deduped" {
  let s = @session.Session::new()
  let src = "int arr[4] = {4,3,2,1}; void sort(int arr[], int n) { for (int i = 0; i < n - 1; i++) for (int j = 0; j < n - 1 - i; j++) if (arr[j] > arr[j + 1]) { int t = arr[j]; arr[j] = arr[j + 1]; arr[j + 1] = t; } } int main(void) { sort(arr, 4); return arr[0]; }"
  let (c, _) = serve_handle(
    s,
    "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"\{src}\"}}",
  )
  assert_true(c.contains("\"ok\":true"), msg="编译须成功")
  ignore(serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}"))
  // 固定推进 200 步（首交换在 step 30 附近；语料交换事件 9 个）——不追求
  // 终局，窗口内确定性即可（2300+ 指令全跑会让四 target 测试过慢）。
  for i = 0; i < 200; i = i + 1 {
    ignore(serve_handle(s, "{\"id\":10,\"method\":\"step.next\"}"))
  }
  let (tp, _) = serve_handle(
    s, "{\"id\":20,\"method\":\"timeline.plan\",\"params\":{\"start\":0}}",
  )
  let (pg, _) = serve_handle(
    s, "{\"id\":21,\"method\":\"payload.get\",\"params\":{\"start\":0}}",
  )
  let steps = match
    json_field(
      @util.json_parse(tp) catch {
        _ => abort("plan 帧非 JSON")
      },
      "result",
    ) {
    Object(_) as res =>
      match json_field(res, "steps") {
        Array(a) => a
        _ => abort("steps 非数组")
      }
    _ => abort("plan result 非对象")
  }
  let payloads = match
    json_field(
      @util.json_parse(pg) catch {
        _ => abort("payload 帧非 JSON")
      },
      "result",
    ) {
    Object(_) as res =>
      match json_field(res, "payloads") {
        Array(a) => a
        _ => abort("payloads 非数组")
      }
    _ => abort("payload result 非对象")
  }
  assert_eq(steps.length(), payloads.length(), msg="steps 与帧零基同构")
  let mut dup_frames = 0
  let mut sw_frames = 0
  for k = 0; k < payloads.length(); k = k + 1 {
    let p = payloads[k]
    let snaps = match json_field(p, "array_snapshots") {
      Array(a) => a
      _ => []
    }
    let names : Array[String] = []
    for sn in snaps {
      names.push(jstr_or_like(json_field(sn, "name")))
    }
    if names.length() != unique_count(names) {
      dup_frames += 1
    }
    match json_field(steps[k], "sw") {
      Object(_) as sw => {
        sw_frames += 1
        assert_eq(
          jstr_or_like(json_field(sw, "name")),
          "arr",
          msg="重名折叠后的归属真名",
        )
      }
      _ => ()
    }
  }
  assert_true(
    dup_frames > 0,
    msg="语料须覆盖同名快照形态（否则锚空转）",
  )
  assert_true(
    sw_frames > 0,
    msg="同名双发不得丢光交换归属（修前恒 0）",
  )
}

///|
fn unique_count(names : Array[String]) -> Int32 {
  let seen : Array[String] = []
  for n in names {
    if !seen.contains(n) {
      seen.push(n)
    }
  }
  seen.length()
}
