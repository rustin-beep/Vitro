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
  // #68 连坐：expected 字段（机器可读形状——下游可编程重试面）存在断言
  assert_true(resp.contains("\"expected\":\"step:int\""))
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
  // 非正行号过滤；回显 = 生效集（病 7 翻转锚，#47 2026-10-09——旧锚固化
  // 「回显原始数组（Rust 同款）」的病行为，-2 未生效不回显）
  assert_true(
    b1.contains("\"lines\":[4,7]"),
    msg="回显须为生效集（过滤后）",
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
/// 行末不变量锚素材：3 元素冒泡（#225 原锚同款源码）。
fn bubble3_compile_json() -> String {
  "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"" +
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
}

///|
/// 建立已完成 compile → run → step.begin 的冒泡步进会话（run 先行 =
/// Rust golden test 提取序照搬，run 建立会话运行态）。返回编译响应供
/// 调用侧断言（编译失败后续全空的假绿防线）。
fn bubble3_step_session() -> (@session.Session, String) {
  let s = @session.Session::new()
  let (cresp, _) = serve_handle(s, bubble3_compile_json())
  ignore(serve_handle(s, "{\"id\":9,\"method\":\"run\"}"))
  ignore(serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}"))
  (s, cresp)
}

///|
/// 按给定 step.next params 段形态收集**发布流**到终结，返回
///（code_line 流, 标注在位流, 是否终结）。params_seg 形态示例：
/// `,"params":{"frames":50}`（批推进）/ `,"params":{}`（批=1 逐帧，
/// frames 缺省 1——demo 前端 worker 真实口径）。响应解析失败/形状异常
/// 的批次静默跳帧、finished 不置位——调用侧以「终结 + 帧数下限」断言
/// 兜假绿（哨兵惯例：辅助函数无断言）。
fn step_collect_published(
  s : @session.Session,
  params_seg : String,
  max_calls : Int32,
) -> (Array[Int32], Array[Bool], Bool) {
  let lines : Array[Int32] = []
  let annos : Array[Bool] = []
  let mut finished = false
  for k = 0; k < max_calls; k = k + 1 {
    let (r, _) = serve_handle(
      s,
      "{\"id\":\{100 + k},\"method\":\"step.next\"\{params_seg}}",
    )
    let v = @util.json_parse(r) catch { _ => Json::object(Map([])) }
    let result = json_field(v, "result")
    let payloads = json_field(result, "payloads")
    match payloads.as_array() {
      Some(arr) =>
        for p in arr {
          let cl = json_field(p, "code_line").as_int().unwrap_or(-1)
          let anno = match json_field(p, "algorithm_step") {
            Null => false
            _ => true
          }
          lines.push(cl)
          annos.push(anno)
        }
      None => ()
    }
    let fin = json_field(result, "finished").as_bool().unwrap_or(false)
    if fin {
      finished = true
      break
    }
  }
  (lines, annos, finished)
}

///|
/// 行末不变量检查：返回首个违例描述（None = 通过）——同一 code_line
/// 连续段内非段尾帧不得带标注（拼接后的全发布流上判定）。
fn line_end_violation(lines : Array[Int32], annos : Array[Bool]) -> String? {
  let mut i = 0
  while i < lines.length() {
    let mut j = i
    while j + 1 < lines.length() && lines[j + 1] == lines[i] {
      j = j + 1
    }
    let seg = j - i + 1
    if seg > 1 {
      let mut k = i
      while k < j {
        if annos[k] {
          return Some(
            "行中间帧带标注（line=\{lines[i]} 段长 \{seg} 第 \{k - i + 1} 帧）——行末语义破坏",
          )
        }
        k = k + 1
      }
    }
    i = j + 1
  }
  None
}

///|
/// 标注在位帧计数（密度下限断言的提取件）。
fn annotated_count(annos : Array[Bool]) -> Int32 {
  let mut n = 0
  for a in annos {
    if a {
      n = n + 1
    }
  }
  n
}

///|
/// #225 行末不变量锚：step.next 发布流中 algorithm_step 是**行末帧语义**
/// （behavior_contracts 第 7 条契约的可执行判据）——同一 code_line 的
/// 连续帧段内，非段尾帧标注必为 null（serve 层一帧发布缓冲的同行清标注
/// 机制：行执行完毕、变量为行末态才携带标注）。防两种退化：清不足
///（行中间帧带标注 = 半执行态宣称语义）与塌零（全程无标注帧）。
/// 同时锚密度下限：3 元素冒泡全程标注帧 ≥ 6（compare×3 + swap×2×2 +
/// 趟/循环帧——#225 实测 8，下限留余量防文案/判据微调的零余量假红）。
///
/// #399（2026-10-31）锚参数化双形态：原锚只跑 frames=50 批形态，批=1
/// 逐帧形态（params:{}——demo 前端 worker 真实口径）零锚——修复前批=1
/// 下跨批 pending 的清标注判据（pop 后判 payloads 空）恒跳过，行中间
/// 帧带标注漏出（demo/e08 bubble.c 实测 79.9% 帧带标注、密度过密 20
/// 倍）。**锚只在一种批量下绿 ≠ 不变量成立**——双形态各自全程收集与
/// 断言，并断言两形态行号流与标注流逐位一致（「跨批拼接与单帧流
/// 同构」契约的可执行判据）。
test "serve_step_algorithm_step_line_end_invariant" {
  // 形态一（#225 原锚口径）：frames=50 批推进
  let (s1, c1) = bubble3_step_session()
  assert_true(c1.contains("\"ok\":true"), msg="批形态：编译须成功")
  let (l1, a1, f1) = step_collect_published(
    s1, ",\"params\":{\"frames\":50}", 40,
  )
  assert_true(f1, msg="批形态：40×50 帧应跑完 3 元素冒泡")
  assert_true(
    l1.length() > 100,
    msg="批形态：帧流非空（实得 \{l1.length()}）",
  )
  guard line_end_violation(l1, a1) is None else {
    fail("批形态 frames=50：" + line_end_violation(l1, a1).unwrap_or(""))
  }
  assert_true(
    annotated_count(a1) >= 6,
    msg="批形态：全程标注帧 ≥ 6（实得 \{annotated_count(a1)}）",
  )
  // 形态二（#399 修复锚）：批=1 逐帧推进——params:{} = frames 缺省 1
  let (s2, c2) = bubble3_step_session()
  assert_true(c2.contains("\"ok\":true"), msg="批=1 形态：编译须成功")
  let (l2, a2, f2) = step_collect_published(s2, ",\"params\":{}", 2100)
  assert_true(
    f2,
    msg="批=1 形态：2100 次调用应跑完 3 元素冒泡（实得 \{l2.length()} 帧）",
  )
  assert_true(
    l2.length() > 100,
    msg="批=1 形态：帧流非空（实得 \{l2.length()}）",
  )
  guard line_end_violation(l2, a2) is None else {
    fail("批=1 逐帧形态：" + line_end_violation(l2, a2).unwrap_or(""))
  }
  assert_true(
    annotated_count(a2) >= 6,
    msg="批=1 形态：全程标注帧 ≥ 6（实得 \{annotated_count(a2)}）",
  )
  // 同构判据：同一程序的发布流（code_line 序列 + 标注在位）不因批参数
  // 而变——批参数只改发布分批粒度，不改帧序列与行末语义
  assert_eq(
    l1.length(),
    l2.length(),
    msg="双形态帧数应一致（实得 \{l1.length()} vs \{l2.length()}）",
  )
  for idx, cl in l1 {
    assert_eq(
      cl,
      l2[idx],
      msg="双形态行号流第 \{idx} 帧不一致——同构破坏",
    )
  }
  for idx, a in a1 {
    assert_eq(
      a,
      a2[idx],
      msg="双形态标注在位流第 \{idx} 帧不一致——同构破坏",
    )
  }
}

///|
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

///|
/// issue #35 红锚：UAF step 流 root_cause_hint 须亮（wire 链装配——
/// trap 帧 root_cause_hint 非 null 且类目 UseAfterFree）。issue 立项时的
/// 断点（trap 文案缺分配行段）已随文案迭代消失；本锚锁**端到端**链路
/// （serve 滞后一帧缓冲冲刷 + engine 装配 + analyzer）不再回退为恒 null。
test "serve_step_uaf_root_cause_hint_wire" {
  let s = @session.Session::new()
  ignore(
    serve_handle(
      s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"#include <stdlib.h>\\nint main() { int *p = malloc(sizeof(int)); *p = 42; free(p); return *p; }\\n\"}}",
    ),
  )
  ignore(serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}"))
  let mut trapped = false
  let mut trap_resp = ""
  for i = 0; i < 60 && !trapped; i = i + 1 {
    let (r, _) = serve_handle(s, "{\"id\":10,\"method\":\"step.next\"}")
    if r.contains("\"trapped\":true") {
      trapped = true
      trap_resp = r
    }
  }
  assert_true(trapped, msg="UAF 程序须出 trap")
  assert_true(trap_resp.contains("Use-After-Free"), msg="trap 文案须为 UAF")
  assert_true(
    trap_resp.contains("\"root_cause_hint\":{"),
    msg="trap 帧 root_cause_hint 须装配（恒 null = wire 链断——issue #35）",
  )
  assert_true(trap_resp.contains("\"category\":\"UseAfterFree\""))
}

///|
/// #89 稀疏出帧（2026-10-17）：params.every 参数面——① 越界/非整数
/// fail loud（参数错误帧 + expected 形状，禁静默退化 1）；② every=3
/// 时采样帧数 ≈ 步数/3（稀疏生效；全量形态帧数 = 步数+1）。
/// 帧内容断言不在此解析文本——走 engine 公开查询面 get_payloads。
test "serve_step_next_every_param" {
  let s = @session.Session::new()
  let (cresp, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int main() { int a = 1; a = a + 1; a = a + 2; return a; }\\n\"}}",
  )
  assert_true(cresp.contains("\"ok\":true"), msg="编译须成功")
  ignore(serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}"))
  // ① 参数校验 fail loud
  let (bad, _) = serve_handle(
    s, "{\"id\":3,\"method\":\"step.next\",\"params\":{\"every\":0}}",
  )
  assert_true(
    bad.contains("\"kind\":\"protocol\""),
    msg="every=0 须参数错误帧",
  )
  assert_true(bad.contains("every:int"))
  let (bad2, _) = serve_handle(
    s, "{\"id\":4,\"method\":\"step.next\",\"params\":{\"every\":\"x\"}}",
  )
  assert_true(
    bad2.contains("\"kind\":\"protocol\""),
    msg="every 非整数须参数错误帧",
  )
  // ② every=3 稀疏节奏
  for i = 0; i < 5; i = i + 1 {
    ignore(
      serve_handle(
        s, "{\"id\":5,\"method\":\"step.next\",\"params\":{\"every\":3}}",
      ),
    )
  }
  guard s.unified is Some(engine) else { fail("step.begin 后 engine 必在") }
  let steps = s.vm.step_count
  let frames = engine.get_payloads(0, 2147483647)
  assert_true(
    steps >= 9,
    msg="every=3 须真执行 3 条/次（已执行 \{steps}）",
  )
  assert_true(frames.length() >= 1, msg="采样帧须有产出")
  // 稀疏判据：帧数显著小于步数（全量 = 步数+1；采样 ≈ 步数/3 + 终帧）
  assert_true(
    frames.length() <= steps / 3 + 2,
    msg="采样帧数须 ≈ 步数/3（实得 \{frames.length()} 帧 / \{steps} 步）",
  )
}

///|
/// 病 76 frames 三面锚（2026-10-17 审阅 P2-⑤ 补锚；合并批随 #89 对齐）：
/// ①在场非整数（浮点/字符串/超 Int32 域）fail loud 且带**分类文案**
/// （#133 单源预检——config.set 口径同款；#89 的 0 哨兵是第二道防线，
/// 分类文案归预检层）②frames=20 批量推进（一批跑完小程序——突变回
/// 「恒 1 步」时一调跑不完，本断言红）③超会话 max_steps 预算钳到预算
/// （frames=1000 配 max_steps=3，长程序两调内不得 finished——钳制口径
/// 已写入 api help rules.json brief）。缺省 1 = 既有锚的恒单步形态。
test "serve_step_next_frames_domain_b76" {
  let s = @session.Session::new()
  let (cresp, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int main() { int a = 1; a = a + 1; return a; }\\n\"}}",
  )
  assert_true(cresp.contains("\"ok\":true"), msg="编译须成功")
  ignore(serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}"))
  // ①在场非整数 fail loud——三形态各带分类文案（#133 单源预检复用）
  let bads : Array[(String, String)] = [
    ("1.5", "浮点形态"),
    ("\"3\"", "收到字符串"),
    ("2147483648", "超出可表示上限"),
  ]
  for t in bads {
    let (r, _) = serve_handle(
      s,
      "{\"id\":3,\"method\":\"step.next\",\"params\":{\"frames\":" + t.0 + "}}",
    )
    assert_true(
      r.contains("\"kind\":\"protocol\""),
      msg="frames=\{t.0} 须 param_err",
    )
    assert_true(r.contains("须为正整数"), msg="frames=\{t.0} 文案")
    assert_true(r.contains(t.1), msg="frames=\{t.0} 分类：\{r}")
    assert_true(r.contains("\"expected\":\"frames:int>=1\""))
  }
  // every 同款分类（预检双键）
  let (er, _) = serve_handle(
    s, "{\"id\":4,\"method\":\"step.next\",\"params\":{\"every\":2.5}}",
  )
  assert_true(er.contains("浮点形态"), msg="every=2.5 分类文案：\{er}")
  // ②合法批量：frames=20 一批跑完小程序——首调即冲刷 finished（批量
  // 跑完走 finished 冲刷臂非空帧缓冲臂；突变回「恒 1 步」时一调跑不完）
  let (r1, _) = serve_handle(
    s, "{\"id\":5,\"method\":\"step.next\",\"params\":{\"frames\":20}}",
  )
  assert_true(
    r1.contains("\"finished\":true"),
    msg="frames=20 须一调跑完程序：\{r1}",
  )
  // 终结后粘性空帧（恒带 finished:true——坑 ⑥-6 同款）
  let (r2, _) = serve_handle(
    s, "{\"id\":6,\"method\":\"step.next\",\"params\":{\"frames\":20}}",
  )
  assert_true(r2.contains("\"payloads\":[]"), msg="终结后须粘性空帧")
  // ③超预算钳制：max_steps=3 + frames=1000，~250 步长程序两调仅 ~6 步
  let s2 = @session.Session::new()
  let (c2, _) = serve_handle(
    s2, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int main() { int a = 0; while (a < 50) { a = a + 1; } return a; }\\n\"}}",
  )
  assert_true(c2.contains("\"ok\":true"), msg="长程序编译须成功")
  let _ = serve_handle(
    s2, "{\"id\":2,\"method\":\"config.set\",\"params\":{\"max_steps\":3}}",
  )
  let _ = serve_handle(s2, "{\"id\":3,\"method\":\"step.begin\"}")
  let _ = serve_handle(
    s2, "{\"id\":4,\"method\":\"step.next\",\"params\":{\"frames\":1000}}",
  )
  let (r4, _) = serve_handle(
    s2, "{\"id\":5,\"method\":\"step.next\",\"params\":{\"frames\":1000}}",
  )
  assert_true(
    r4.contains("\"finished\":false"),
    msg="frames=1000 须钳到预算 3（两调 ~6 步，长程序不得 finished）：\{r4}",
  )
}

///|
/// #231 semantic_label_id 帧面锚（2026-10-27）：步帧 payload 须带
/// `semantic_label_id`（受控词汇表 id——classify 单源映射〔protocol 包〕；
/// 空串 = 无标签）。消费方按 id 聚合/过滤/着色，不再对渲染文本做
/// 脆弱前缀匹配（「循环 n=5, i=0」无法反查是 loop 的硬伤）。
test "serve_step_semantic_label_id_frame_field" {
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
  let (bresp, _) = serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}")
  assert_true(bresp.contains("\"ready\":true"))
  let mut saw_loop = false
  let mut saw_swap = false
  let mut field_every_frame = true
  let mut sample = "（无帧）"
  // 400 帧覆盖 main 序段 + bubbleSort 全程（3 元素冒泡 ~200 步——64 帧
  // 只到 main 调用前后，交换行不在窗内）
  for k = 0; k < 400; k = k + 1 {
    let (r, _) = serve_handle(s, "{\"id\":\{30 + k},\"method\":\"step.next\"}")
    // 只对含帧响应断言字段（payloads:[] 的发布缓冲响应是合法形态——
    // 一帧发布缓冲语义下非末帧批不发布）
    if r.contains("\"payloads\":[{") && !r.contains("\"semantic_label_id\":") {
      field_every_frame = false
      if sample == "（无帧）" && r.length() > 2 {
        sample = r
      }
    }
    if r.contains("\"semantic_label_id\":\"loop\"") {
      saw_loop = true
    }
    if r.contains("\"semantic_label_id\":\"swap\"") {
      saw_swap = true
    }
  }
  assert_true(
    field_every_frame,
    msg="每帧须带 semantic_label_id 字段（#231）样例帧：\{sample}",
  )
  assert_true(saw_loop, msg="循环帧须带 semantic_label_id=loop（#231）")
  assert_true(saw_swap, msg="交换帧须带 semantic_label_id=swap（#231）")
}
