///| L9 time_travel·**帧窗口（FrameWindow）**——StepPayload 帧缓存的自带
/// 不变量类型（S8 批一号二段，2026-10-01）。
///
/// **结构消除两类事故形态**（勘察 O4 / 坑 2）：
/// - Rust 侧 `frame_cache: Vec<StepPayload>` 是 pub 字段、`split_off` 裁剪
///   O(len) memmove 且只在 run_batch 路径调用——重放循环忘了裁 = 63.6GB
///   事故（坑 2 复发形态）。本类型**只有 push 一种写入口**，超窗自动裁
///   （U2#1 修复形态"push 后立即 trim"由类型保证，某个 return 分支忘裁
///   在结构上不可表达）；
/// - 窗口起点（start_step）与缓存长度必须自洽——内聚为字段 + 单一推进
///   点（trim 内部），外部不可拆开改。
///
/// **窗口语义逐字保留（⑤-5.3，协议锚定不可改）**：window_size = 2_000、
/// trim_ratio = 0.2、discard = ceil(len × ratio) clamp [1, len]、
/// start_step += discard——61 条回放断言 S3 A14（2050 步后
/// cache_start_step > 0）锚定"窗口外静默丢弃是设计"（schema §8 #6）。
///
/// **承载形态（⑤-5.2 v1）**：`@deque.Deque`（两端 O(1) 摊还）替代 Vec
/// split_off 的 O(n) memmove；"持久差分帧"（帧间未变子结构共享）是
/// spike S2 验证 GC 回收性后的升级项，非本段。

///|
/// 帧窗口：StepPayload 的有界滑动缓存。
pub struct FrameWindow {
  /// 窗口内帧（队首 = 最老帧）。pub(all) 的 StepPayload 经 protocol 消费。
  frames : @deque.Deque[@protocol.StepPayload]
  /// 窗口首帧对应的全局步号（窗口外历史不可查——静默丢弃是设计）。
  mut start_step : Int
  /// 窗口上限（协议锚定 2_000——改此值即改协议，见模块头注）。
  window_size : Int
  /// 超窗丢弃比例（协议锚定 0.2）。
  trim_ratio : Double
}

///|
/// 协议默认窗口（window_size = 2_000 / trim_ratio = 0.2——⑤-5.3 逐字保留）。
pub fn FrameWindow::new() -> FrameWindow {
  {
    frames: @deque.Deque([]),
    start_step: 0,
    window_size: 2_000,
    trim_ratio: 0.2,
  }
}

///|
/// 自定义窗口参数（会话级配置入口；教学长程序可放宽 window_size）。
pub fn FrameWindow::with_limits(
  window_size : Int,
  trim_ratio : Double,
) -> FrameWindow {
  guard window_size > 0 else {
    abort(
      "FrameWindow::with_limits: window_size 须 > 0，得到 \{window_size}",
    )
  }
  guard trim_ratio > 0.0 && trim_ratio <= 1.0 else {
    abort(
      "FrameWindow::with_limits: trim_ratio 须 ∈ (0, 1]，得到 \{trim_ratio}",
    )
  }
  { frames: @deque.Deque([]), start_step: 0, window_size, trim_ratio, }
}

///|
/// 推入一帧（**唯一写入口**——超窗自动裁，不变量 len ≤ window_size 在
/// 每次 push 后成立）。步号由调用方保证严格递增（spec 附录 A），本方法
/// 不重复校验（热路径）。
pub fn FrameWindow::push(
  self : FrameWindow,
  payload : @protocol.StepPayload,
) -> Unit {
  self.frames.push_back(payload)
  self.trim()
}

///|
/// 滑动窗口截断（照搬 trim_frame_cache 语义：discard = ceil(len × ratio)
/// clamp [1, len]；start_step += discard）。私有——裁剪时机是类型不变量
/// 的一部分，不外包给调用方。
fn FrameWindow::trim(self : FrameWindow) -> Unit {
  let len = self.frames.length()
  if len <= self.window_size {
    return
  }
  // discard = ceil(len × ratio) clamp [1, len]（Rust `(len as f64 * ratio)
  // .ceil()`）。**不用浮点→整数转换**（Double::to_int 语义未文档化——
  // 陷阱 #25 同族）：从 1 递增找首个 ≥ 积的最小整数，数学上恰为 ceil
  // （raw ≤ 1 时落在 clamp 下限 1）；量级 ≤ window_size，摊还可忽略。
  let product = len.to_double() * self.trim_ratio
  let mut discard = 1
  while discard.to_double() < product && discard < len {
    discard = discard + 1
  }
  let mut k = 0
  while k < discard {
    ignore(self.frames.pop_front())
    k = k + 1
  }
  self.start_step = self.start_step + discard
}

///|
/// 窗口内帧数。
pub fn FrameWindow::length(self : FrameWindow) -> Int {
  self.frames.length()
}

///|
pub fn FrameWindow::is_empty(self : FrameWindow) -> Bool {
  self.frames.length() == 0
}

///|
/// 窗口首帧步号（cache_start_step——serve 出口字段单源）。
pub fn FrameWindow::start_step(self : FrameWindow) -> Int {
  self.start_step
}

///|
/// 窗口上限（配置读口——U2#1 测试断言同款）。
pub fn FrameWindow::window_limit(self : FrameWindow) -> Int {
  self.window_size
}

///|
/// 窗口末帧（发布缓冲/终态帧读口；空窗口返回 None）。
pub fn FrameWindow::last(self : FrameWindow) -> @protocol.StepPayload? {
  let len = self.frames.length()
  if len == 0 {
    return None
  }
  Some(self.frames[len - 1])
}

///|
/// 按步号区间取窗口内帧（payload.get 的引擎侧形态）。
///
/// **钳位纪律（坑 ⑥-4/5 同族防线——三次事故均在"先算下标再切"）**：
/// 先把 [start, end) 钳到 [start_step, start_step + len) 再换算下标；
/// 负参 / 越窗 / start ≥ end 一律返回空数组——**禁止**有符号差值做
/// 下标（坑 ⑥-1 的 usize 绕回 63.6GB 形态）。
pub fn FrameWindow::slice(
  self : FrameWindow,
  start : Int,
  end : Int,
) -> Array[@protocol.StepPayload] {
  let len = self.frames.length()
  if len == 0 || start >= end {
    return []
  }
  // 钳位：start ← max(start, start_step)；end ← min(end, start_step + len)
  let lo = if start > self.start_step { start } else { self.start_step }
  let hi_bound = self.start_step + len
  let hi = if end < hi_bound { end } else { hi_bound }
  if lo >= hi {
    return []
  }
  let out : Array[@protocol.StepPayload] = []
  let mut i = lo - self.start_step
  let last = hi - self.start_step
  while i < last {
    out.push(self.frames[i])
    i = i + 1
  }
  out
}

///|
/// 清空窗口并复位起点（reset 通道——与 UnifiedEngine::reset 连坐）。
pub fn FrameWindow::clear(self : FrameWindow) -> Unit {
  while self.frames.length() > 0 {
    ignore(self.frames.pop_front())
  }
  self.start_step = 0
}

// ─────────────────────────────────────────────────────────────────────
// 三段-c 增补（2026-10-01）：run_batch/seek_to 的窗口操作面。写入口仍唯一
// 走 push 家族（push / push_batch / push_or_replace_at——后两者内部收敛
// 到 push 语义 + 超窗自动裁不变量），读口 frame_at，seek 专用 reset_to /
// finish_replay。
// ─────────────────────────────────────────────────────────────────────

///|
/// 按全局步号取窗口内帧（engine.rs:410-420 frame_cache_index 照搬：
/// step < start_step 或 ≥ start_step + len → None）。
pub fn FrameWindow::frame_at(
  self : FrameWindow,
  step : Int,
) -> @protocol.StepPayload? {
  if step < self.start_step {
    return None
  }
  let idx = step - self.start_step
  let len = self.frames.length()
  if idx < len {
    Some(self.frames[idx])
  } else {
    None
  }
}

///|
/// 批收尾入窗（engine.rs:248-261 finalize_batch 照搬）：行末帧标注去重
/// （U1#1 P0-1——同一源码行的多帧只有行末帧携带 algorithm_step；当前
/// teaching 未接恒 None，逻辑照搬为 teaching 就绪）+ 逐帧入窗（超窗自动
/// 裁由 push 保证——U2#1 的"push 后立即 trim"结构化）。
///
/// 去重两段：①批内相邻同 code_line → 前帧降级；②窗口尾帧与批首帧同
/// code_line → 窗口尾帧降级（批边界切在语句中间时上批尾帧不再是行末）。
pub fn FrameWindow::push_batch(
  self : FrameWindow,
  batch : Array[@protocol.StepPayload],
) -> Unit {
  // 批内相邻同 code_line → 前帧降级（StepPayload 字段不可变——结构展开
  // 重建整帧替换，语义等价 Rust 就地置 None）
  for i in 1..<batch.length() {
    if batch[i].code_line == batch[i - 1].code_line {
      batch[i - 1] = { ..batch[i - 1], algorithm_step: None, }
    }
  }
  // 窗口尾帧与批首帧同 code_line → 尾帧降级（批边界切在语句中间时）
  let len = self.frames.length()
  if len > 0 && batch.length() > 0 {
    let tail = self.frames[len - 1]
    if tail.code_line == batch[0].code_line {
      self.frames.set(len - 1, { ..tail, algorithm_step: None, })
    }
  }
  for p in batch {
    self.push(p)
  }
}

///|
/// 重放过程中的帧放入（engine.rs:435-468 push_or_replace_in_replay 照搬）：
/// 顺序追加（idx == len → push，超窗自动裁）；同步覆盖（重放重复步）；
/// 中间缺口占位填充（code_line=0 空帧——正常重放不应出现的防御分支）。
/// 追加后对尾段行末标注降级（demote_row_annotations——teaching 就绪）。
pub fn FrameWindow::push_or_replace_at(
  self : FrameWindow,
  step : Int,
  payload : @protocol.StepPayload,
) -> Unit {
  // 目标步早于窗口起点：越窗重放路径已 reset_to，此为防御分支（坑 ⑥-1
  // 的负差下标绕回形态在类型层不可达——Int 差直接比较，无绕回）
  if step < self.start_step {
    return
  }
  let idx = step - self.start_step
  let len = self.frames.length()
  if idx == len {
    self.push(payload)
    self.demote_tail(len)
  } else if idx < len {
    self.frames.set(idx, payload)
  } else {
    while self.frames.length() < idx {
      let filler_step = self.start_step + self.frames.length()
      self.frames.push_back(blank_payload(filler_step))
    }
    self.push(payload)
    self.demote_tail(self.frames.length() - 1)
  }
}

///|
/// 尾段行末标注降级（engine.rs:426-432 demote_row_annotations 的 from=
/// len-1 段——与前一帧同 code_line 的帧不是行末，前帧降级）。algorithm_step
/// 当前恒 None（teaching 批接入），逻辑照搬为零开销 no-op。
fn FrameWindow::demote_tail(self : FrameWindow, from : Int) -> Unit {
  let len = self.frames.length()
  if from >= 1 && from < len {
    let cur = self.frames[from]
    let prev = self.frames[from - 1]
    if cur.code_line == prev.code_line {
      self.frames.set(from - 1, { ..prev, algorithm_step: None, })
    }
  }
}

///|
/// 越窗重放的窗口重置（engine.rs:299-300 照搬）：清窗 + 起点置检查点步。
/// 不 reset_to 的旧窗口残留会让 step - start_step 为负（坑 2 的 63.6GB
/// 事故形态）——reset_to 是 seek 越窗路径的强制前置。
pub fn FrameWindow::reset_to(self : FrameWindow, step : Int) -> Unit {
  while self.frames.length() > 0 {
    ignore(self.frames.pop_front())
  }
  self.start_step = step
}

///|
/// 重放收尾窗口（engine.rs:471-485 finish_replay_window 照搬）：只保留
/// 目标步及其之前 window_size-1 帧——`want_start = max(0, target -
/// window_size + 1)`；discard 钳到实际长度（坑 ⑥-4：seek 目标远超已有
/// 步数时理论 discard > len，直接切会越界——钳位后按实际推进量记账）；
/// 再截断 target 之后的多余帧。
pub fn FrameWindow::finish_replay(self : FrameWindow, target : Int) -> Unit {
  let want_start = target - self.window_size + 1
  let want_start = if want_start > 0 { want_start } else { 0 }
  let len = self.frames.length()
  if self.start_step < want_start && len > 0 {
    let discard = want_start - self.start_step
    let discard = if discard < len { discard } else { len }
    let mut k = 0
    while k < discard {
      ignore(self.frames.pop_front())
      k = k + 1
    }
    self.start_step = self.start_step + discard
  }
  // 截断 target 之后的多余帧（expected_len = target - start + 1，钳非负）
  let expected = target - self.start_step + 1
  let expected = if expected > 0 { expected } else { 0 }
  while self.frames.length() > expected {
    ignore(self.frames.pop_back())
  }
}

///|
/// 空帧占位（push_or_replace_at 缺口防御——Rust 占位帧 14 字段全零形态）。
fn blank_payload(step : Int) -> @protocol.StepPayload {
  {
    step_index: step,
    code_line: 0,
    func_name: "",
    semantic_label: "",
    algorithm_step: None,
    local_vars: [],
    call_stack: [],
    vis_events: [],
    heatmap_line: 0,
    heatmap_count: 0UL,
    accessed_vars: [],
    array_snapshots: [],
    pointer_snapshots: [],
    root_cause_hint: None,
  }
}
