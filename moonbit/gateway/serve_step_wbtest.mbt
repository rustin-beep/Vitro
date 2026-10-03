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
test "serve_step_trap_terminal_next_terminates" {
  // issue #29：trap 后 step.next 可终止——终态短路空批 + trapped 照报 +
  // 死因恒定（此前每批 rollback→重执行→再 Trap 无限循环，消费方无法
  // 感知"已 trap"；oracle 侧同病，mb 终态语义差异台账登记随退役收敛）
  let s = @session.Session::new()
  ignore(
    serve_handle(
      s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int main() { int z = 0; return 10 / z; }\\n\"}}",
    ),
  )
  ignore(serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}"))
  let mut trapped_resp = ""
  for i = 0; i < 40; i = i + 1 {
    let (r, _) = serve_handle(s, "{\"id\":10,\"method\":\"step.next\"}")
    if r.contains("\"trapped\":true") {
      trapped_resp = r
      break
    }
  }
  assert_false(trapped_resp == "", msg="须先到 trap 批")
  // 终态首批（滞后一帧语义：冲刷发布缓冲——至多 1 帧上批缓冲的 trap
  // 帧）+ trapped=true + 死因照报
  let (r2, _) = serve_handle(s, "{\"id\":11,\"method\":\"step.next\"}")
  assert_true(r2.contains("\"trapped\":true"), msg="终态批照报 trapped")
  assert_true(
    r2.contains("\"trap_message\":") && !r2.contains("\"trap_message\":null"),
    msg="死因照报",
  )
  // 终态次批：完全空（缓冲已冲尽、不重执行）
  let (r3, _) = serve_handle(s, "{\"id\":12,\"method\":\"step.next\"}")
  assert_true(
    r3.contains("\"trapped\":true") && r3.contains("\"payloads\":[]"),
    msg="终态次批空 payloads（不重执行）",
  )
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
/// 批四号接线锚二（反向）：**判据不命中的函数**帧 algorithm_step 恒
/// null（None 降级是协议合法形态）。素材随批翻新至终结：批四号=gcd、
/// 批五号=static_list_insert、批六号 structures 迁移后 43/43 全量——
/// 「未迁移族」语义终结，素材改为无任何算法特征的普通函数 compute。
test "serve_step_unmigrated_family_stays_null" {
  let s = @session.Session::new()
  let jsrc = "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"" +
    "int compute(int a, int b) {\\n" +
    "  int t = a + b;\\n" +
    "  return t * 2;\\n" +
    "}\\n" +
    "int main() { return compute(3, 4); }\\n" +
    "\"}}"
  let (cresp, _) = serve_handle(s, jsrc)
  assert_true(cresp.contains("\"ok\":true"), msg="编译须成功")
  assert_eq(
    s.compile.algorithm_matches.length(),
    0,
    msg="普通函数——全部判据不命中（detect 面零标注；42/42 后语义）",
  )
  ignore(serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}"))
  for k = 0; k < 20; k = k + 1 {
    let (r, _) = serve_handle(s, "{\"id\":\{30 + k},\"method\":\"step.next\"}")
    assert_false(
      r.contains("\"algorithm_name\""),
      msg="无匹配函数帧不得带标注（帧长 \{r.length()}）",
    )
  }
}

///|
/// 审阅销项锚（2026-10-02）：同会话二次 step.begin 的标注链路——审阅
/// 读码发现本侧 set_algorithm_matches 复位三状态而 Rust 对应 session
/// 字段不复位，理论差异形态「同会话不重编译、连续两次 step.begin 后
/// 残留 prev_vars 影响标注」探针未复现（判据不足未报缺陷）；本锚把该
/// 面从「未覆盖」变「已覆盖」：二次 begin（新引擎 + matches 重注入 +
/// 状态复位）后跑到带标注帧，标注链路须完好。
test "serve_step_second_begin_reannotates" {
  let s = @session.Session::new()
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
  ignore(serve_handle(s, "{\"id\":9,\"method\":\"run\"}"))
  // 首段：begin → 推进 → 出现标注
  let (b1, _) = serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}")
  assert_true(b1.contains("\"ready\":true"), msg="首次 begin")
  let mut first = false
  for k = 0; k < 64; k = k + 1 {
    let (r, _) = serve_handle(s, "{\"id\":\{100 + k},\"method\":\"step.next\"}")
    if r.contains("\"algorithm_name\":\"bubble_sort\"") {
      first = true
    }
  }
  assert_true(first, msg="首段应出现标注")
  // 二次 begin（同会话不重编译）：新引擎 + matches 重注入 + 三状态复位
  let (b2, _) = serve_handle(s, "{\"id\":3,\"method\":\"step.begin\"}")
  assert_true(b2.contains("\"ready\":true"), msg="二次 begin 须可用")
  let mut second = false
  for k = 0; k < 64; k = k + 1 {
    let (r, _) = serve_handle(s, "{\"id\":\{200 + k},\"method\":\"step.next\"}")
    if r.contains("\"algorithm_name\":\"bubble_sort\"") {
      second = true
    }
  }
  assert_true(
    second,
    msg="二次 begin 后标注链路须完好（复位语义回归即红）",
  )
}

///|
test "serve_step_next_waiting_input_flag" {
  // issue #29 #5：step 流的 waiting_input 上报——scanf 未喂入时 step.next
  // 须出 waiting_input=true（消费方据此 input.feed；此前 step.begin 重建
  // VM 漏设 InputState，vm.new 默认 batch=true ⇒ scanf 直达 EOF 不等待，
  // 与 oracle 会话默认 Interactive 相反——run 通道被 serve_run 的模式
  // 同步掩盖、step 流独缺）
  let s = @session.Session::new()
  let (rc, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"#include <stdio.h>\\nint main(){ int a; if (scanf(\\\"%d\\\", &a) == 1) printf(\\\"got=%d\\\", a * 2); return 0; }\"}}",
  )
  assert_true(
    rc.contains("\"ok\":true"),
    msg="compile 须成功，实得：\{rc}",
  )
  ignore(serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}"))
  let mut waiting = false
  for i = 0; i < 20 && !waiting; i = i + 1 {
    let (r, _) = serve_handle(s, "{\"id\":10,\"method\":\"step.next\"}")
    if r.contains("\"waiting_input\":true") {
      waiting = true
    }
  }
  assert_true(waiting, msg="scanf 等待点须上报 waiting_input=true")
  // feed 后续跑完成 + 输出（交互闭环）
  let _ = serve_handle(
    s, "{\"id\":11,\"method\":\"input.feed\",\"params\":{\"text\":\"21\\n\"}}",
  )
  let mut finished = false
  for i = 0; i < 20 && !finished; i = i + 1 {
    let (r, _) = serve_handle(s, "{\"id\":12,\"method\":\"step.next\"}")
    if r.contains("\"finished\":true") {
      finished = true
    }
  }
  assert_true(finished, msg="feed 后续跑可完成")
  let (out, _) = serve_handle(
    s, "{\"id\":13,\"method\":\"output.delta\",\"params\":{\"cursor\":0}}",
  )
  assert_true(out.contains("got=42"), msg="scanf 读入 feed 值")
}

///|
test "serve_step_vis_events_from_algorithm_matches" {
  // issue #29 #4 红锚：compile 管线第 9 步（algorithm_matches.vis_events
  // → vm.set_vis_event_lines，oracle compile_pipeline.rs:357-364 对应物）
  // ——未接线时 StepPayload.vis_events 恒空（demo 可视化侧栏数据源缺失）。
  // bubble_sort 命名命中判据族；a[j] > a[j+1] 比较行进 compare_lines
  //（features walk 收集，两侧同形）→ VM 执行到该行时 vis 事件进帧。
  let s = @session.Session::new()
  let (cresp, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"void bubble_sort(int a[3]) {\\n  int i = 0;\\n  while (i < 2) {\\n    int j = 0;\\n    while (j < 2 - i) {\\n      if (a[j] > a[j + 1]) {\\n        int t = a[j];\\n        a[j] = a[j + 1];\\n        a[j + 1] = t;\\n      }\\n      j = j + 1;\\n    }\\n    i = i + 1;\\n  }\\n}\\nint main() {\\n  int a[3];\\n  a[0] = 3;\\n  a[1] = 1;\\n  a[2] = 2;\\n  bubble_sort(a);\\n  return a[0];\\n}\\n\"}}",
  )
  assert_true(
    cresp.contains("\"ok\":true"),
    msg="compile 须成功，实得：\{cresp}",
  )
  ignore(serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}"))
  let mut acc = ""
  let mut finished = false
  for i = 0; i < 400 && !finished; i = i + 1 {
    let (r, _) = serve_handle(s, "{\"id\":10,\"method\":\"step.next\"}")
    acc = acc + r
    if r.contains("\"finished\":true") {
      finished = true
    }
  }
  assert_true(finished, msg="程序须跑完（400 批内）")
  // 非空 vis_events：emitter 形态 \"vis_events\":[{（恒空时为 []）
  assert_true(
    acc.contains("\"vis_events\":[{"),
    msg="比较行命中须产出 vis 事件（第 9 步接线缺失则恒空）",
  )
}
