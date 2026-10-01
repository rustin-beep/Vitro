// serve step 族白盒锚（S8 批一号接线批，2026-10-01）：五方法协议面 +
// U1#1 一帧发布缓冲（R2 首调空帧语义）+ seek 往返 + trap 帧。编排本体
// 的行为锚在 time_travel/engine_wbtest（九锚）；本族锁 serve 层帧结构、
// 错误分支与 emitter 字段序（serde 序关键邻接形态）。

///|
test "serve_step_begin_not_compiled_state_error" {
  let s = @session.Session::new()
  let (resp, _) = serve_handle(s, "{\"id\":1,\"method\":\"step.begin\"}")
  assert_true(resp.contains("\"kind\":\"state\""))
  assert_true(resp.contains("需先编译成功"))
}

///|
test "serve_step_next_without_begin_state_error" {
  let s = @session.Session::new()
  let (resp, _) = serve_handle(s, "{\"id\":1,\"method\":\"step.next\"}")
  assert_true(resp.contains("\"kind\":\"state\""))
  assert_true(resp.contains("统一模式会话未初始化"))
}

///|
test "serve_step_flow_begin_next_first_call_empty" {
  let s = @session.Session::new()
  let (cresp, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int main() { int a = 1; a = a + 1; return a; }\\n\"}}",
  )
  assert_true(cresp.contains("\"ok\":true"), msg="编译须成功")
  let (bresp, _) = serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}")
  assert_true(bresp.contains("\"ready\":true"))
  assert_true(bresp.contains("\"max_collected_step\":-1"))
  // R2 滞后一帧语义：首调只建缓冲、返回空 payloads（修复前形态 = 首调
  // 发布克隆 → 同步重复投递 0,0,1 序列，spec 附录 A 违例）
  let (r1, _) = serve_handle(s, "{\"id\":3,\"method\":\"step.next\"}")
  assert_true(r1.contains("\"payloads\":[]"), msg="首调必空帧")
  // 第二调起发布上一帧：step_index 0 起
  let (r2, _) = serve_handle(s, "{\"id\":4,\"method\":\"step.next\"}")
  assert_true(r2.contains("\"step_index\":0"))
  // emitter 插入序形态锚（本侧写死序；Rust serde Value 是字典序——键序
  // 分叉已登记已知限制 ④-6，serve 帧比较一律经 canonicalize）
  assert_true(r2.contains("\"step_index\":0,\"code_line\":"))
  // 帧 0 = 全局初始化帧（未进 main——call_stack 空、func_name 空串是
  // 正确语义，Rust 同形）；main 内帧的 func_name 由 finished 冲刷锚覆盖
  assert_true(r2.contains("\"func_name\":\"\""))
  // 引擎已挂会话
  assert_true(s.unified is Some(_), msg="engine 须挂 Session")
}

///|
test "serve_step_run_to_finished_flush" {
  let s = @session.Session::new()
  ignore(
    serve_handle(
      s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int main() { int a = 1; return a; }\\n\"}}",
    ),
  )
  ignore(serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}"))
  // 跑到终结：finished 冲刷缓冲（末帧发布 + finished:true）
  let mut finished = false
  let mut last = ""
  for i = 0; i < 40 && !finished; i = i + 1 {
    let (r, _) = serve_handle(s, "{\"id\":10,\"method\":\"step.next\"}")
    if r.contains("\"finished\":true") {
      finished = true
      last = r
    }
  }
  assert_true(finished, msg="40 步内须到 finished")
  // 冲刷帧带 step_index（非空 payloads）
  assert_true(last.contains("\"step_index\""))
  // 终结后再 step.next：粘性空帧（坑 ⑥-6——不重放末帧）
  let (again, _) = serve_handle(s, "{\"id\":11,\"method\":\"step.next\"}")
  assert_true(again.contains("\"payloads\":[]"))
  assert_true(again.contains("\"finished\":true"))
}

///|
test "serve_step_seek_roundtrip_and_payload_get" {
  let s = @session.Session::new()
  ignore(
    serve_handle(
      s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int main() { int a = 0; while (a < 3) { a = a + 1; } return a; }\\n\"}}",
    ),
  )
  ignore(serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}"))
  // 推进若干步（>一帧）
  for i = 0; i < 12; i = i + 1 {
    ignore(serve_handle(s, "{\"id\":10,\"method\":\"step.next\"}"))
  }
  // payload.get：区间帧 + 窗口元数据
  let (pg, _) = serve_handle(
    s, "{\"id\":20,\"method\":\"payload.get\",\"params\":{\"start\":0,\"end\":3}}",
  )
  assert_true(pg.contains("\"cache_start_step\":0"))
  assert_true(pg.contains("\"max_collected_step\""))
  assert_true(pg.contains("\"step_index\":0"))
  // seek 回 0（窗口内直返路径——帧可再取）
  let (sk, _) = serve_handle(
    s, "{\"id\":21,\"method\":\"seek\",\"params\":{\"step\":0}}",
  )
  assert_true(sk.contains("\"success\":true"))
  assert_true(sk.contains("\"step_index\":0"))
  // seek 后 step.next 续跑（is_finished 复位 + 帧连续）
  let (nx, _) = serve_handle(s, "{\"id\":22,\"method\":\"step.next\"}")
  assert_false(nx.contains("\"error\""))
}

///|
test "serve_step_seek_missing_step_param" {
  let s = @session.Session::new()
  let (resp, _) = serve_handle(s, "{\"id\":1,\"method\":\"seek\"}")
  assert_true(resp.contains("\"kind\":\"protocol\""))
  assert_true(resp.contains("seek 需要 params.step"))
}

///|
test "serve_step_breakpoints_set_and_clear" {
  let s = @session.Session::new()
  ignore(
    serve_handle(
      s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int main() { int i = 0; while (i < 5) { i = i + 1; } return i; }\\n\"}}",
    ),
  )
  ignore(serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}"))
  let (b1, _) = serve_handle(
    s, "{\"id\":3,\"method\":\"breakpoints.set\",\"params\":{\"lines\":[4,-2,7]}}",
  )
  // 非正行号过滤（Rust 同款）；回显含设置值
  assert_true(
    b1.contains("\"lines\":[4,-2,7]"),
    msg="回显含原始 lines 数组",
  )
  // 清空 = 两层恢复 + 空回显
  let (b2, _) = serve_handle(
    s, "{\"id\":4,\"method\":\"breakpoints.set\",\"params\":{\"lines\":[]}}",
  )
  assert_true(b2.contains("\"lines\":[]"))
}

///|
test "serve_step_trap_frame_trapped_flag" {
  let s = @session.Session::new()
  ignore(
    serve_handle(
      s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int main() { int z = 0; return 10 / z; }\\n\"}}",
    ),
  )
  ignore(serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}"))
  let mut trapped = false
  let mut trap_resp = ""
  for i = 0; i < 40 && !trapped; i = i + 1 {
    let (r, _) = serve_handle(s, "{\"id\":10,\"method\":\"step.next\"}")
    if r.contains("\"trapped\":true") {
      trapped = true
      trap_resp = r
    }
  }
  assert_true(trapped, msg="除零程序须出 trap 帧")
  // trap_message 非空串（回滚前抓取——⑤-5.1 分叉②）
  assert_false(trap_resp.contains("\"trap_message\":null"))
  assert_true(trap_resp.contains("\"trap_message\":\""))
}

///|
test "serve_step_reset_invalidates_engine" {
  let s = @session.Session::new()
  ignore(
    serve_handle(
      s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int main() { return 0; }\\n\"}}",
    ),
  )
  ignore(serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}"))
  assert_true(s.unified is Some(_))
  ignore(serve_handle(s, "{\"id\":3,\"method\":\"session.reset\"}"))
  // reset 作废引擎（分叉登记：保守作废语义——旧引擎与 reset 后 vm 失配）
  assert_true(s.unified is None)
  let (resp, _) = serve_handle(s, "{\"id\":4,\"method\":\"step.next\"}")
  assert_true(resp.contains("统一模式会话未初始化"))
}

///|
/// 批四号接线锚一：serve 通道端到端出算法标注——compile（检测）→
/// step.begin（matches 注入引擎）→ step.next（帧带 algorithm_step）。
/// 冒泡源码（bubble 命名分支双命中）；回归形态 = matches 恒空 /
/// AlgoInferCtx 未接线时该锚必红（标注全 null）。
test "serve_step_algorithm_step_annotated" {
  let s = @session.Session::new()
  // 多行源码（行级判据依赖每语句独立行——starts_with("for ") 等在单行
  // 源码上全失效；JSON \n 转义经 json_parse 还原。main 须逐语句分行：
  // 一行多语句形态 VM 帧行号不前进（code_line 恒同一行），标注面合法
  // 零命中——非接线缺陷，此处不测该形态）
  let jsrc = "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"" +
    "void bubbleSort(int arr[], int n) {\\n" +
    "  int i, j, temp;\\n" +
    "  for (i = 0; i < n - 1; i++) {\\n" +
    "    for (j = 0; j < n - i - 1; j++) {\\n" +
    "      if (arr[j] > arr[j + 1]) {\\n" +
    "        temp = arr[j];\\n" +
    "        arr[j] = arr[j + 1];\\n" +
    "        arr[j + 1] = temp;\\n" +
    "      }\\n" +
    "    }\\n" +
    "  }\\n" +
    "}\\n" +
    "int main() {\\n" +
    "  int arr[3] = {3, 1, 2};\\n" +
    "  int n = 3;\\n" +
    "  bubbleSort(arr, n);\\n" +
    "  return arr[0];\\n" +
    "}\\n" +
    "\"}}"
  let (cresp, _) = serve_handle(s, jsrc)
  assert_true(cresp.contains("\"ok\":true"), msg="编译须成功")
  // 检测面：compile 产物 matches 含 bubble_sort（serve_compile 接线）
  let mut hit = false
  for m in s.compile.algorithm_matches {
    if m.name == "bubble_sort" {
      hit = true
    }
  }
  assert_true(hit, msg="compile 须检出 bubble_sort")
  // run 先行（Rust golden test 提取序照搬：compile → run → step.begin →
  // step.next——run 建立会话运行态）
  ignore(serve_handle(s, "{\"id\":9,\"method\":\"run\"}"))
  let (bresp, _) = serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}")
  assert_true(bresp.contains("\"ready\":true"))
  // 推断面：逐帧推进，交换行帧应带 bubble_sort 标注
  let mut annotated = false
  for k = 0; k < 64; k = k + 1 {
    let (r, _) = serve_handle(s, "{\"id\":\{10 + k},\"method\":\"step.next\"}")
    if r.contains("\"algorithm_name\":\"bubble_sort\"") {
      annotated = true
    }
  }
  assert_true(
    annotated,
    msg="64 帧内应出现 bubble_sort 标注（接线回归 = 全 null）",
  )
}

///|
/// 批四号接线锚二（反向）：未迁移族（gcd）判据不命中——帧 algorithm_step
/// 恒 null（None 降级是协议合法形态；分派表未迁移段）。
test "serve_step_unmigrated_family_stays_null" {
  let s = @session.Session::new()
  let jsrc = "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"" +
    "int gcd(int a, int b) {\\n" +
    "  while (b != 0) { int t = a % b; a = b; b = t; }\\n" +
    "  return a;\\n" +
    "}\\n" +
    "int main() { return gcd(48, 18); }\\n" +
    "\"}}"
  let (cresp, _) = serve_handle(s, jsrc)
  assert_true(cresp.contains("\"ok\":true"), msg="编译须成功")
  let mut detected = false
  for m in s.compile.algorithm_matches {
    if m.name == "gcd" {
      detected = true
    }
  }
  assert_false(
    detected,
    msg="gcd 未迁移——判据不命中（detect 面零标注）",
  )
  ignore(serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}"))
  for k = 0; k < 20; k = k + 1 {
    let (r, _) = serve_handle(s, "{\"id\":\{30 + k},\"method\":\"step.next\"}")
    assert_false(
      r.contains("\"algorithm_name\""),
      msg="未迁移族帧不得带标注（帧长 \{r.length()}）",
    )
  }
}
