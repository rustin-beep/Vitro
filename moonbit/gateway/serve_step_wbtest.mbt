// 蓝本注记：文内 Rust 源引用（`*.rs` 路径/行号/符号）均为档案态蓝本——tag rust-oracle-freeze（2026-10-05 删区），现为本仓自主基线。

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
  // 修锚史：A2 批（审阅 v2 / M26 W1）把恒真断言 assert_false(nx.contains(
  // "error"))（响应 schema 无 error 键）换发布帧 + finished 双断言；
  // #430（B7 批，M26 A2）再翻面——seek 成功即清发布缓冲（旧 pending
  // 帧不属于 seek 后时间轴），续跑**首调回到空帧形态**（帧入缓冲），
  // 第二调起发布帧且 step_index 严格递增。
  let (nx1, _) = serve_handle(s, "{\"id\":22,\"method\":\"step.next\"}")
  assert_true(
    nx1.contains("\"payloads\":[]"),
    msg="#430：seek 清缓冲后续跑首调为空帧形态（帧入缓冲）",
  )
  assert_true(
    nx1.contains("\"finished\":false"),
    msg="seek 回退后 is_finished 复位",
  )
  let (nx2, _) = serve_handle(s, "{\"id\":23,\"method\":\"step.next\"}")
  assert_true(
    nx2.contains("\"step_index\""),
    msg="第二调发布缓冲帧（发布流恢复）",
  )
  assert_true(nx2.contains("\"finished\":false"), msg="程序未终结")
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

// ─────────────────────────────────────────────────────────────────────
// #430 锚族（B7 批，2026-11-04）：seek 族四形态 serve 面红锚——
// 断点被 restore 覆写（M26 A1）/ 发布流编号倒挂（M26 A2）/ seek(-1)
// 毁帧窗（M26 A3）/ 终态 seek 幽灵帧（M31 A-2）+ breakpoints.set
// fail loud（M26 C1）。修前全红（M26 探针 P20/P2/P15、M31 批 C 端到端
// 重建形态）。
// ─────────────────────────────────────────────────────────────────────

///|
/// 长循环程序（~3500 步 > 默认窗口 2000——批推后窗口滑走，越窗 seek 可达）。
fn longloop_compile_json() -> String {
  "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"" +
  "int main() {\\n" +
  "  int a = 0;\\n" +
  "  while (a < 500) {\\n" +
  "    a = a + 1;\\n" +
  "  }\\n" +
  "  return a;\\n" +
  "}\\n" +
  "\"}}"
}

///|
/// #430-A（M26 A1 P1，探针 P20 形态）：越窗 seek 把断点当执行状态回滚
/// ——批推滑窗后设断点、越窗 seek（restore 检查点），断点须保留且续跑
/// 再命中（旧形态 BP 清空、续跑永不 paused）。
test "serve_seek_overwindow_breakpoint_survives_b7" {
  let s = @session.Session::new()
  let (cresp, _) = serve_handle(s, longloop_compile_json())
  assert_true(
    cresp.contains("\"ok\":true"),
    msg="编译须成功（假绿防线）",
  )
  ignore(serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}"))
  // 批推 2600 步（窗口滑走——start_step > 0 即越窗可达）
  ignore(
    serve_handle(
      s, "{\"id\":3,\"method\":\"step.next\",\"params\":{\"frames\":2600}}",
    ),
  )
  guard s.unified is Some(engine) else { fail("engine 必在") }
  assert_true(engine.frames.start_step() > 0, msg="前置：窗口已滑走")
  // 设断点行 4（循环体 a = a + 1）
  let (bresp, _) = serve_handle(
    s, "{\"id\":4,\"method\":\"breakpoints.set\",\"params\":{\"lines\":[4]}}",
  )
  assert_true(bresp.contains("\"lines\":[4]"), msg="断点回显")
  // 越窗 seek(100)（100 < 窗口起点 → 重放臂 restore 检查点）
  let (skresp, _) = serve_handle(
    s, "{\"id\":5,\"method\":\"seek\",\"params\":{\"step\":100}}",
  )
  assert_true(skresp.contains("\"success\":true"), msg="seek 成功")
  // 断点保留（旧形态被快照覆写清空）
  assert_true(
    s.vm.breakpoints_sorted().contains(4),
    msg="#430：断点=会话配置，越窗 seek 不得清空",
  )
  // 续跑再命中：批=1 逐帧，断点行 4 每 ~7 步一次——12 批内必中
  let mut hit = false
  for k = 0; k < 12; k = k + 1 {
    let (r, _) = serve_handle(s, "{\"id\":\{20 + k},\"method\":\"step.next\"}")
    if r.contains("\"paused\":true") {
      assert_true(
        r.contains("\"current_line\":4"),
        msg="#430：暂停行须为断点行（防重放残留假暂停）",
      )
      hit = true
      break
    }
    if r.contains("\"finished\":true") {
      break
    }
  }
  assert_true(
    hit,
    msg="#430：越窗 seek 后断点须再命中（旧形态永不命中）",
  )
}

///|
/// #430-B（M26 A2，探针 P2 形态）：发布流编号倒挂——越窗 seek 后旧
/// pending「未来帧」不属于新时间轴，须随 seek 清缓冲（旧形态首批发布
/// step_index=2599 旧帧再跳回 4→5→6，违反 spec §7「step_index 严格
/// 递增」）。
test "serve_seek_pending_reset_b7" {
  let s = @session.Session::new()
  let (cresp, _) = serve_handle(s, longloop_compile_json())
  assert_true(cresp.contains("\"ok\":true"), msg="编译须成功")
  ignore(serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}"))
  ignore(
    serve_handle(
      s, "{\"id\":3,\"method\":\"step.next\",\"params\":{\"frames\":2600}}",
    ),
  )
  // 越窗 seek(3)：重放臂重建时间轴 [0..3]
  let (skresp, _) = serve_handle(
    s, "{\"id\":4,\"method\":\"seek\",\"params\":{\"step\":3}}",
  )
  assert_true(skresp.contains("\"success\":true"), msg="seek 成功")
  // 批=1 逐帧 6 次，收集发布流 step_index——全部须在小值域单调推进
  //（旧形态首个发布帧 step_index=2599 倒挂）
  let mut prev : Int32 = -1
  for k = 0; k < 6; k = k + 1 {
    let (r, _) = serve_handle(s, "{\"id\":\{10 + k},\"method\":\"step.next\"}")
    let v = @util.json_parse(r) catch { _ => Json::object(Map([])) }
    let payloads = json_field(json_field(v, "result"), "payloads")
    guard payloads.as_array() is Some(arr) else { continue }
    for p in arr {
      let idx = json_field(p, "step_index").as_int().unwrap_or(-1)
      assert_true(
        idx <= 12,
        msg="#430：发布帧 \{idx} 超出 seek 后新时间轴（旧未来帧倒挂）",
      )
      assert_true(
        idx > prev,
        msg="#430：发布流 step_index 须严格递增（\{prev} → \{idx}）",
      )
      prev = idx
    }
  }
  assert_true(prev >= 4, msg="须有新帧发布（seek 后续跑 4 起）")
}

///|
/// #430-C（M26 A3，探针 P15 形态）：seek 负数目标——参数层 param_err
///（step:int>=0，#133 分类文案同款）+ 帧窗零副作用（旧形态
/// success:false 误导文案 + 已收集帧窗全毁 + VM 静默回滚）。
test "serve_seek_negative_param_err_b7" {
  let s = @session.Session::new()
  ignore(
    serve_handle(
      s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int main() { int a = 0; a = a + 1; return a; }\\n\"}}",
    ),
  )
  ignore(serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}"))
  // 推 3 帧（首帧入缓冲，max_collected_step = 2）
  for i = 0; i < 3; i = i + 1 {
    ignore(serve_handle(s, "{\"id\":\{10 + i},\"method\":\"step.next\"}"))
  }
  let (pg0, _) = serve_handle(
    s, "{\"id\":20,\"method\":\"payload.get\",\"params\":{\"start\":0,\"end\":10}}",
  )
  assert_true(pg0.contains("\"max_collected_step\":2"), msg="前置帧窗")
  // seek(-1)：param_err（旧形态 success:false + 帧窗毁）
  let (sk, _) = serve_handle(
    s, "{\"id\":21,\"method\":\"seek\",\"params\":{\"step\":-1}}",
  )
  assert_true(sk.contains("\"kind\":\"protocol\""), msg="参数域错误分类")
  assert_true(
    sk.contains("seek 的 params.step 不能为负数"),
    msg="负数目标 = 参数错误（旧形态误导文案「无法获取目标步的 payload」）",
  )
  assert_true(
    sk.contains("\"expected\":\"step:int>=0\""),
    msg="#68 机器可读形状",
  )
  // 帧窗零副作用
  let (pg1, _) = serve_handle(
    s, "{\"id\":22,\"method\":\"payload.get\",\"params\":{\"start\":0,\"end\":10}}",
  )
  assert_true(
    pg1.contains("\"max_collected_step\":2"),
    msg="#430：seek(-1) 不得毁帧窗（旧形态 BEFORE=[0,1,2] → AFTER=[]）",
  )
}

///|
/// #430-D（M31 A-2 证据一，端到端批 C 形态）：程序终结后窗口内 seek
///（直返臂——VM 不动、无时间旅行）终态粘性保持——后续 step.next 空批
/// + finished（旧形态复位后续跑产 step_index=终步+1 幽灵终帧，违反
/// 「每真实步恰投递一次」）。
test "serve_seek_inwindow_finished_no_ghost_frame_b7" {
  let s = @session.Session::new()
  ignore(
    serve_handle(
      s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int main() { int a = 0; while (a < 3) { a = a + 1; } return a; }\\n\"}}",
    ),
  )
  ignore(serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}"))
  // 跑至终结（程序 ~30+ 步；批=1 逐帧）
  let mut finished = false
  for k = 0; k < 80; k = k + 1 {
    let (r, _) = serve_handle(s, "{\"id\":\{10 + k},\"method\":\"step.next\"}")
    if r.contains("\"finished\":true") {
      finished = true
      break
    }
  }
  assert_true(finished, msg="前置：程序已终结")
  // 窗口内 seek(0)：直返臂（帧在窗口、VM 不动）
  let (sk, _) = serve_handle(
    s, "{\"id\":60,\"method\":\"seek\",\"params\":{\"step\":0}}",
  )
  assert_true(sk.contains("\"success\":true"), msg="直返 seek 成功")
  // 续跑：空批 + finished（旧形态回幽灵帧 step_index=终步+1）
  let (nx, _) = serve_handle(s, "{\"id\":61,\"method\":\"step.next\"}")
  assert_true(
    nx.contains("\"payloads\":[]"),
    msg="#430：终态 seek 后不得产幽灵帧",
  )
  assert_true(nx.contains("\"finished\":true"), msg="终态保持")
}

///|
/// #430-E（M26 C1，探针 P8 形态）：breakpoints.set 参数域 fail loud——
/// 缺 lines / lines 非数组 / 元素非整数一律 param_err（与 step.next 的
/// frames/every 分类文案纪律对齐；旧形态静默当空 = 清空断点并恢复运行，
/// 一次手滑即静默改变执行语义）。空数组仍是显式清空（合法语义）。
test "serve_breakpoints_set_fail_loud_domain_b7" {
  let s = @session.Session::new()
  ignore(
    serve_handle(
      s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int main() { int a = 0; a = a + 1; return a; }\\n\"}}",
    ),
  )
  ignore(serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}"))
  // 缺 lines（旧形态静默当空清空）
  let (r1, _) = serve_handle(s, "{\"id\":3,\"method\":\"breakpoints.set\"}")
  assert_true(r1.contains("\"kind\":\"protocol\""), msg="缺 lines = param_err")
  assert_true(r1.contains("\"expected\":\"lines:int[]\""))
  // lines 非数组
  let (r2, _) = serve_handle(
    s, "{\"id\":4,\"method\":\"breakpoints.set\",\"params\":{\"lines\":\"4\"}}",
  )
  assert_true(
    r2.contains("\"kind\":\"protocol\""),
    msg="lines 非数组 = param_err",
  )
  // 元素非整数（旧形态静默丢弃）
  let (r3, _) = serve_handle(
    s, "{\"id\":5,\"method\":\"breakpoints.set\",\"params\":{\"lines\":[4,\"x\",7]}}",
  )
  assert_true(
    r3.contains("\"kind\":\"protocol\""),
    msg="非整数元素 = param_err（旧形态静默丢弃只留 [4,7]）",
  )
  // 合法面：空数组 = 显式清空（两层恢复语义保留）
  let (r4, _) = serve_handle(
    s, "{\"id\":6,\"method\":\"breakpoints.set\",\"params\":{\"lines\":[]}}",
  )
  assert_true(r4.contains("\"ok\":true"), msg="空数组 = 合法显式清空")
  assert_true(r4.contains("\"lines\":[]"))
}

///|
/// #430-B7b-1（M31 A-2 证据二，端到端批 A 形态）：窗口内 seek（直返——
/// 只移动视口不动 VM）后续跑的**视口连续性**——step.next 前检测 VM 位置
/// 与窗口尾帧脱节即自动重放对齐，发布流从视口后继连续推进（教学播放器
/// 语义：seek=拖进度条、下一步=视口下一帧）。旧形态 VM 在原位置续跑，
/// 用户 seek(100) 后点下一步拿到 step_index=1000（「瞬移」）。
test "serve_seek_viewport_next_continuity_b7b" {
  let s = @session.Session::new()
  let (cresp, _) = serve_handle(s, longloop_compile_json())
  assert_true(cresp.contains("\"ok\":true"), msg="编译须成功")
  ignore(serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}"))
  // 批推 1000 步（窗口 [0..999] 未滑——帧全在窗）
  ignore(
    serve_handle(
      s, "{\"id\":3,\"method\":\"step.next\",\"params\":{\"frames\":1000}}",
    ),
  )
  guard s.unified is Some(engine) else { fail("engine 必在") }
  assert_eq(
    engine.frames.start_step(),
    0,
    msg="前置：窗口未滑（帧全在窗）",
  )
  // seek(100)：帧在窗口内 → 直返臂（VM 仍在 1000——视口回看）
  let (skresp, _) = serve_handle(
    s, "{\"id\":4,\"method\":\"seek\",\"params\":{\"step\":100}}",
  )
  assert_true(skresp.contains("\"success\":true"), msg="直返 seek 成功")
  // 续跑批=1 ×5：发布流须从视口后继 101 连续推进（旧形态从 1000 瞬移）
  let mut prev : Int32 = 100
  for k = 0; k < 5; k = k + 1 {
    let (r, _) = serve_handle(s, "{\"id\":\{10 + k},\"method\":\"step.next\"}")
    let v = @util.json_parse(r) catch { _ => Json::object(Map([])) }
    let payloads = json_field(json_field(v, "result"), "payloads")
    guard payloads.as_array() is Some(arr) else { continue }
    for p in arr {
      let idx = json_field(p, "step_index").as_int().unwrap_or(-1)
      assert_eq(
        idx,
        prev + 1,
        msg="#430-B7b：发布帧须为视口后继（期望 \{prev + 1}，实得 \{idx}——旧形态 VM 原位置瞬移）",
      )
      prev = idx
    }
  }
  assert_true(prev >= 104, msg="须有连续新帧发布（101..105）")
}

///|
/// #430-B7b-2：等待输入态不重复投递——scanf 等待帧已收集（首 waiting 批
/// 一次投递），续调 step.next 空批 + waiting_input=true（等待步 ip/步数
/// 双回退语义下旧形态每次续调重新 collect 同号帧再发布——同一帧反复
/// 投递，违反「每真实步恰投递一次」）；input.feed 清等待位后续跑正常。
test "serve_step_next_waiting_no_redelivery_b7b" {
  let s = @session.Session::new()
  ignore(
    serve_handle(
      s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"#include <stdio.h>\\nint main(){ int a; if (scanf(\\\"%d\\\", &a) == 1) printf(\\\"got=%d\\\", a * 2); return 0; }\"}}",
    ),
  )
  ignore(serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}"))
  // 推到等待点（waiting_input=true 批——等待帧一次投递）
  let mut waiting = false
  for i = 0; i < 20 && !waiting; i = i + 1 {
    let (r, _) = serve_handle(s, "{\"id\":10,\"method\":\"step.next\"}")
    if r.contains("\"waiting_input\":true") {
      waiting = true
    }
  }
  assert_true(
    waiting,
    msg="前置：scanf 等待点须上报 waiting_input=true",
  )
  // 等待态续调 next ×3：等待帧至多投递一次（首个 waiting 批帧入 serve
  // 发布缓冲、第二次 next 冲刷即首次投递、其后恒空批——serve「滞后一
  // 帧发布」与 engine 零 collect 的合成形态；旧形态 engine 每批重新
  // collect 同号帧 → 发布缓冲滚动重发——3 次续调投 2-3 帧同号帧）
  let mut delivered = 0
  for k = 0; k < 3; k = k + 1 {
    let (w, _) = serve_handle(s, "{\"id\":\{20 + k},\"method\":\"step.next\"}")
    assert_true(
      w.contains("\"waiting_input\":true"),
      msg="等待态照报（消费方据此 input.feed）",
    )
    let v = @util.json_parse(w) catch { _ => Json::object(Map([])) }
    let payloads = json_field(json_field(v, "result"), "payloads")
    if payloads.as_array() is Some(arr) {
      delivered = delivered + arr.length()
    }
  }
  assert_true(
    delivered <= 1,
    msg="#430-B7b：等待帧至多投递一次（实得 \{delivered}——旧形态每批重发同号帧）",
  )
  // feed 清等待位 → 续跑正常完成（守卫不得拦已恢复的会话）
  let _ = serve_handle(
    s, "{\"id\":21,\"method\":\"input.feed\",\"params\":{\"text\":\"21\\n\"}}",
  )
  let mut finished = false
  for i = 0; i < 20 && !finished; i = i + 1 {
    let (r, _) = serve_handle(s, "{\"id\":30,\"method\":\"step.next\"}")
    if r.contains("\"finished\":true") {
      finished = true
    }
  }
  assert_true(finished, msg="feed 后续跑可完成（清位闭环）")
}

// ── REHOST 批 3（step 态切换）锚族 ──────────────────────────────────
// 设计单 §3.2 批 3：step 态装载走 wasm 载体往返（帧参数 wasm_rehost——
// 与批 2b run 帧独立并行的 flag）；单步=组、断点判定经组表侧车 loc、
// VMSnapshot gip 换名不换义、StepPayload/帧流发射零变化（协议面冻结）。

///|
/// 批 3 锚一：step.begin 帧参数 `wasm_rehost` 的状态字段——flag on 返回帧
/// 携带 `"wasm_rehost":"ok groups=N"`（装载往返成功——折叠重建产物驱动
/// 取指）；flag off 帧不带该字段（帧面冻结：老消费者零感知，前缀只增
/// 不改）。J9：接线前（params 忽略形态）flag on 帧无字段即红。
test "serve_step_begin_wasm_rehost_status_field_b3" {
  let s = @session.Session::new()
  let (cresp, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int main() { int a = 1; return a; }\\n\"}}",
  )
  assert_true(cresp.contains("\"ok\":true"), msg="编译须成功")
  // flag off：帧不带 wasm_rehost 字段（零扰动——批 3 前形态原样）
  let (b0, _) = serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}")
  assert_true(b0.contains("\"ready\":true"))
  assert_false(
    b0.contains("\"wasm_rehost\""),
    msg="flag off 帧面冻结（实得 \{b0}）",
  )
  // flag on：状态串字段（ok groups=N——组表装载往返成功）
  let (b1, _) = serve_handle(
    s, "{\"id\":3,\"method\":\"step.begin\",\"params\":{\"wasm_rehost\":true}}",
  )
  assert_true(
    b1.contains("\"wasm_rehost\":\"ok groups="),
    msg="flag on 状态字段（实得 \{b1}）",
  )
  assert_true(b1.contains("\"ready\":true"), msg="step.begin 语义原样")
}

///|
/// 批 3 锚二：flag on/off 两会话**帧流逐位同构**（单步=组语义冻结的
/// serve 层最强锚——INV3a step_index 严格 +1 的 wbtest 投影：任意一批
/// 响应串逐位相等 = 帧流发射零变化）。断点行为经组表侧车 loc 同构
/// （breakpoints.set 同行 → Paused 帧一致——StepEvent 的 operand 行号
/// 来自折叠重建产物 = 组表侧车）。
test "serve_step_begin_rehost_frameflow_isomorphic_b3" {
  // src 行 4 含循环体赋值（StepEvent 行锚——断点行域内）
  let src = "int main() {\\n  int a = 0;\\n  while (a < 3) {\\n    a = a + 1;\\n  }\\n  return a;\\n}\\n"
  //（drive 不做断言——test 内嵌 fn 无 raise 面，编译/终止判定外层判）
  fn drive(flag_on : Bool, id0 : Int32) -> (Array[String], Bool, Bool) {
    let s = @session.Session::new()
    let (cresp, _) = serve_handle(
      s,
      "{\"id\":\{id0},\"method\":\"compile\",\"params\":{\"source\":\"\{src}\"}}",
    )
    let compile_ok = cresp.contains("\"ok\":true")
    let begin = if flag_on {
      "{\"id\":\{id0 + 1},\"method\":\"step.begin\",\"params\":{\"wasm_rehost\":true}}"
    } else {
      "{\"id\":\{id0 + 1},\"method\":\"step.begin\"}"
    }
    let _ = serve_handle(s, begin)
    // 行 4（a = a + 1）断点——flag on 装载后断点判定经组表侧车 loc/operand
    let _ = serve_handle(
      s,
      "{\"id\":\{id0 + 2},\"method\":\"breakpoints.set\",\"params\":{\"lines\":[4]}}",
    )
    let out : Array[String] = []
    let mut done = false
    for i = 0; i < 60 && !done; i = i + 1 {
      let (r, _) = serve_handle(
        s,
        "{\"id\":\{id0 + 3},\"method\":\"step.next\"}",
      )
      out.push(r)
      if r.contains("\"finished\":true") ||
        r.contains("\"trapped\":true") ||
        r.contains("\"paused\":true") {
        done = true
      }
    }
    (out, compile_ok, done)
  }
  let (legacy, cok0, done0) = drive(false, 1)
  //（id 段与 legacy 相同——响应帧含 id 字段，逐位比较须同 id；两会话
  // 各自独立，id 复用无冲突）
  let (rehost, cok1, done1) = drive(true, 1)
  assert_true(cok0 && cok1, msg="编译须成功")
  assert_true(done0 && done1, msg="帧流须三态终止（flag on/off）")
  assert_eq(
    rehost.length(),
    legacy.length(),
    msg="批数同构（断点暂停点一致）",
  )
  for i = 0; i < legacy.length(); i = i + 1 {
    assert_eq(
      rehost[i],
      legacy[i],
      msg="帧流第 \{i} 批逐位同构（单步=组语义冻结）",
    )
  }
  // 断点确已命中（非平凡通过：末批 paused=true——行 4 StepEvent 暂停）
  assert_true(
    legacy.length() > 0 &&
    legacy[legacy.length() - 1].contains("\"paused\":true"),
    msg="断点行 4 须命中 Paused（锚非平凡化）",
  )
}
