///| L9 time_travel·**检查点管理器（CheckpointManager）**——S8 批一号一段
/// 自 `vm/checkpoint.mbt` 迁入（2026-09-30，落点裁定见 moon.pkg 头注：
/// 智能判据是教学语义，不应由 VM 拥有——修复 Rust 侧 ①-1.4 分层破损）。
/// 照搬源：Rust `snapshot.rs:161-331`；**本批纯迁移零语义变更**（判据字符
/// 串形态照搬，enum 化随 collector 批）。
///
/// **设计照搬与升级并存**（S6 批四号二段原注保留）：
/// - 淘汰不变量三件套逐字照搬（含 U2#5 修复形态）：step-0 锚点永不裁 /
///   删 Full 级联 drain 到下一个 Full（悬空 Delta = seek 静默错内存——
///   最坏调试器缺陷）/ 删 Delta 不级联；
/// - `nearest` 重建（Delta 链逐个 apply 到 base Full）照搬。
///
/// **门 3 验收锚**（seek 往返五类相等）：checkpoint_wbtest.mbt——全量/
/// 增量/淘汰后 seek/step-0 锚点/隔离区三件套随行（六锚自 vm_wbtest 迁入）。
/// **#87 几何化淘汰**（2026-10-27）：`evict_over_limit` 从 FIFO 改最小
/// 左间隙合并（淘汰不变量三件套不动——见 evict_at）。

///|
/// 检查点管理器。
pub struct CheckpointManager {
  /// (step, snapshot) 序列。
  checkpoints : Array[(Int32, @vm.VMSnapshot)]
  /// 固定间隔（步数）保底策略。
  interval : Int32
  /// 智能检查点：控制流边界（调用/返回/循环/交换/内存操作）额外保存。
  mut smart_mode : Bool
  /// 最大检查点数量（防长程序内存无限增长）。
  mut max_checkpoints : Int32
  /// 每 N 个检查点强制一个全量基准。
  full_every : Int32
}

///|
/// 检查点保留数缺省（#87 批暴露会话级旋钮——session/gateway 消费的
/// 单源；内存账：每约 5 个检查点一个 Full = 1MB 内存整拷）。
pub const DEFAULT_MAX_CHECKPOINTS : Int32 = 50

///|
pub fn CheckpointManager::new(interval : Int32) -> CheckpointManager {
  {
    checkpoints: [],
    interval,
    smart_mode: true,
    max_checkpoints: DEFAULT_MAX_CHECKPOINTS,
    full_every: 5,
  }
}

///|
/// 当前步是否需保存检查点（固定间隔保底 + 智能模式在控制流边界触发）。
/// **判据字符串形态照搬**（词汇单源 = protocol vocabulary；enum 化随
/// collector 批走红→绿——迁移与改形分离）。
pub fn CheckpointManager::should_checkpoint(
  self : CheckpointManager,
  step : Int32,
  semantic_label : String,
) -> Bool {
  if step % self.interval == 0 {
    return true
  }
  if !self.smart_mode {
    return false
  }
  // 智能策略：函数调用、返回、循环边界、数组交换、内存操作
  let is_significant = semantic_label.has_prefix("调用 ") ||
    semantic_label == "返回" ||
    semantic_label == "内存分配" ||
    semantic_label == "释放内存" ||
    semantic_label.contains("交换") ||
    semantic_label.has_prefix("循环")
  if !is_significant {
    return false
  }
  // 避免过密：距上一检查点至少 interval/4 步
  let min_gap = (if self.interval > 4 { self.interval } else { 4 }) / 4
  match self.checkpoints.last() {
    Some(pair) => step - pair.0 >= min_gap
    None => true
  }
}

///|
/// 保存检查点（超上限自动淘汰——`evict_over_limit`）。调用者经
/// `should_checkpoint` 判定后调用。全量/Delta 交替：`len % full_every == 0`
/// 取全量（清脏页后 snapshot），否则增量（基于链中最近 Full）。
pub fn CheckpointManager::save(
  self : CheckpointManager,
  step : Int32,
  vm : @vm.VitroVM,
) -> Unit {
  let is_full = self.checkpoints.is_empty() ||
    self.checkpoints.length() % self.full_every == 0
  let snap = if is_full {
    vm.memory.clear_dirty()
    vm.snapshot()
  } else {
    // 找最近 Full 的 step 作为增量基
    let mut base_step = 0
    for i = self.checkpoints.length() - 1; i >= 0; i = i - 1 {
      if self.checkpoints[i].1.memory is @vm.Full(_) {
        base_step = self.checkpoints[i].0
        break
      }
    }
    vm.snapshot_incremental(base_step)
  }
  self.checkpoints.push((step, snap))
  self.evict_over_limit()
}

///|
/// 超上限淘汰——**几何化淘汰（issue #87，2026-10-27）**：淘汰「左间隙
/// 最小」的检查点（平手取最老），取代 FIFO 逐老淘汰。FIFO 只保 step-0 +
/// 最近 max-1 个 ⇒ 长程序中段锚点全空洞（78M 步实测 nearest(1M) 只能落
/// step-0 全程重放 = seek 13.8s / 500× 病灶）；最小左间隙合并在均匀到达
/// 下自平衡为近似等距分布（node 模拟器：4000 步 K=50 最大重放距离 140 ≈
/// 1.7×N/K，FIFO 为 3020；78M 步最坏 2.86M ≈ 1.8×N/K）。头锚（i=0）恒
/// 不在候选（step-0 pinned）。三不变量照旧（模块头注）：删 Full 级联
/// drain / 删 Delta 不级联 / 链头 Full 防御。
fn CheckpointManager::evict_over_limit(self : CheckpointManager) -> Unit {
  while self.checkpoints.length() > self.max_checkpoints {
    let n = self.checkpoints.length()
    if n <= 1 {
      break
    }
    // 贪心：候选 [1, n-1]，argmin 左间隙；平手取最老（小下标）——旧区
    // 密度优先稀释（等距化），尾部密度靠后续 save 自然补充
    let mut remove_idx = 1
    let mut best_gap = self.checkpoints[1].0 - self.checkpoints[0].0
    for i = 2; i < n; i = i + 1 {
      let gap = self.checkpoints[i].0 - self.checkpoints[i - 1].0
      if gap < best_gap {
        remove_idx = i
        best_gap = gap
      }
    }
    self.evict_at(remove_idx)
  }
}

///|
/// 按链规则淘汰下标 remove_idx 的检查点（U2#5 修复形态照搬——三条不变
/// 量见模块头注）：删 Full 级联删其后 Delta 到下一个 Full（悬空 Delta =
/// seek 静默错内存）；删 Delta 不级联；删链头 Delta（防御）drain 到
/// Full 维持链头不变量。
fn CheckpointManager::evict_at(
  self : CheckpointManager,
  remove_idx : Int32,
) -> Unit {
  if remove_idx < 0 || remove_idx >= self.checkpoints.length() {
    return
  }
  let removed_is_full = self.checkpoints[remove_idx].1.memory is @vm.Full(_)
  ignore(self.checkpoints.remove(remove_idx))
  if removed_is_full {
    // 删 Full：级联删其后 Delta 到下一个 Full
    let mut next_full = self.checkpoints.length()
    for i = remove_idx; i < self.checkpoints.length(); i = i + 1 {
      if self.checkpoints[i].1.memory is @vm.Full(_) {
        next_full = i
        break
      }
    }
    // drain remove_idx..next_full
    for k = 0; k < next_full - remove_idx; k = k + 1 {
      ignore(self.checkpoints.remove(remove_idx))
    }
  } else if remove_idx == 0 {
    // 删链头 Delta（防御）：删到 Full 维持链头不变量。**几何化后不可达**
    //（PR #342 审阅 P3-6 注记：淘汰 argmin 的候选 i ≥ 1 ⇒ 链头恒不被选；
    // 保留为白盒直调 evict_at(0) 的链不变量自洽通道 + FIFO 时代防御遗产）
    while self.checkpoints.length() > 0 &&
          !(self.checkpoints[0].1.memory is @vm.Full(_)) {
      ignore(self.checkpoints.remove(0))
    }
  }
}

///|
/// 找不超过 target 的最近检查点，Delta 链重建为可直接恢复的全量快照。
pub fn CheckpointManager::nearest(
  self : CheckpointManager,
  target : Int32,
) -> (Int32, @vm.VMSnapshot)? {
  let idx = match last_le(self.checkpoints, target) {
    Some(i) => i
    None => return None
  }
  self.rebuild_at(idx)
}

///|
/// 带回看窗口下限的取锚（PR #342 审阅 P2-1 处置，2026-10-28）：seek 的
/// 重放区间 = [cp..target]，窗口宽度 = target−cp+1——**恰命中锚点**
///（target−cp < window−1，几何化把锚铺满全程后非罕见）时窗口塌缩
///（极端 1 帧）。本方法按 `min(target, target−window+1)` 取锚（下探更早
/// 锚，恒有 step-0 兜底）：窗口恒满，代价是至多 window−1 步快道重放
///（µs 级——快道段免 collect）。快道门与 finish_replay 语义不受影响
///（cp < dense_from 恒成立 ⇒ 快道段非空）。
pub fn CheckpointManager::nearest_for_window(
  self : CheckpointManager,
  target : Int32,
  window : Int32,
) -> (Int32, @vm.VMSnapshot)? {
  let floor = target - window + 1
  let effective = if floor > 0 { floor } else { 0 }
  let idx = match last_le(self.checkpoints, effective) {
    Some(i) => i
    None => return None
  }
  self.rebuild_at(idx)
}

///|
/// 按下标重建可直接恢复的全量快照（nearest / nearest_for_window 公共段：
/// Full 深拷 / Delta 链回放 + 字段集独立性克隆）。
fn CheckpointManager::rebuild_at(
  self : CheckpointManager,
  idx : Int32,
) -> (Int32, @vm.VMSnapshot)? {
  let step = self.checkpoints[idx].0
  let snap = self.checkpoints[idx].1
  match snap.memory {
    @vm.Full(_) => {
      // Full 检查点直接深拷返回（快照独立性）
      let rebuilt = clone_snapshot_deep(snap)
      Some((step, rebuilt))
    }
    @vm.Delta(base_step, _) => {
      // 找 base_step 之前最近的 Full（倒序找）
      let mut base_idx : Int32? = None
      for i = idx; i >= 0; i = i - 1 {
        if self.checkpoints[i].0 <= base_step &&
          self.checkpoints[i].1.memory is @vm.Full(_) {
          base_idx = Some(i)
          break
        }
      }
      guard base_idx is Some(bi) else { return None }
      guard self.checkpoints[bi].1.memory is @vm.Full(base_bytes) else {
        return None
      }
      // 从 base 到 target 之间的所有增量应用到基础内存
      let full_memory = rebuild_full_from_base(
        base_bytes,
        self.checkpoints,
        bi,
        idx,
      )
      // 字段集克隆：对 Delta 快照的**非 memory 字段**做独立性拷贝——
      // 借临时 restore（用重建后的 Full 替换 memory 再走 clone_snapshot_deep）
      let with_full : @vm.VMSnapshot = {
        ..snap,
        memory: @vm.Full(full_memory),
      }
      Some((step, clone_snapshot_deep(with_full)))
    }
  }
}

///|
/// 从 base Full + Delta 链重建全量内存。
fn rebuild_full_from_base(
  base : FixedArray[Byte],
  checkpoints : Array[(Int32, @vm.VMSnapshot)],
  base_idx : Int32,
  target_idx : Int32,
) -> FixedArray[Byte] {
  let mem = clone_byte_array(base)
  for i = base_idx + 1; i <= target_idx; i = i + 1 {
    match checkpoints[i].1.memory {
      @vm.Delta(_, pages) =>
        for pair in pages {
          write_page_into(mem, pair.0, pair.1)
        }
      @vm.Full(_) => ()
    }
  }
  mem
}

///|
/// last_le： checkpoints 中最后一个 step <= target 的下标。
fn last_le(
  checkpoints : Array[(Int32, @vm.VMSnapshot)],
  target : Int32,
) -> Int32? {
  let mut found : Int32? = None
  for i = 0; i < checkpoints.length(); i = i + 1 {
    if checkpoints[i].0 <= target {
      found = Some(i)
    } else {
      break
    }
  }
  found
}

///|
/// 深拷整个快照（字段集与 snapshot/restore 同源——独立性纪律）。
fn clone_snapshot_deep(snap : @vm.VMSnapshot) -> @vm.VMSnapshot {
  let vm = @vm.VitroVM::new()
  vm.restore(snap)
  vm.snapshot()
}

///|
/// 字节数组深拷（**孪生登记**：vm/snapshot.mbt 同名 priv——跨包无权
/// import；字节拷贝零语义机械件，上提 L0 util 随 G 表批统一收口）。
fn clone_byte_array(src : FixedArray[Byte]) -> FixedArray[Byte] {
  let dst : FixedArray[Byte] = FixedArray::make(src.length(), b'\x00')
  for i = 0; i < src.length(); i = i + 1 {
    dst[i] = src[i]
  }
  dst
}

///|
/// 页写入内存数组（nearest 重建专用——直接 FixedArray 层）。
fn write_page_into(
  mem : FixedArray[Byte],
  page_idx : Int32,
  page : FixedArray[Byte],
) -> Unit {
  let offset = page_idx * @memory.PAGE_SIZE
  for i = 0; i < page.length(); i = i + 1 {
    mem[offset + i] = page[i]
  }
}

///|
pub fn CheckpointManager::clear(self : CheckpointManager) -> Unit {
  self.checkpoints.clear()
}

///|
pub fn CheckpointManager::length(self : CheckpointManager) -> Int32 {
  self.checkpoints.length()
}

///|
pub fn CheckpointManager::is_empty(self : CheckpointManager) -> Bool {
  self.checkpoints.length() == 0
}

///|
/// 关闭/开启智能检查点（会话级配置——wbtest/上层经此入口，字段只读纪律）。
pub fn CheckpointManager::set_smart_mode(
  self : CheckpointManager,
  v : Bool,
) -> Unit {
  self.smart_mode = v
}

///|
/// 设置最大检查点数（同上）。**收缩即时淘汰**（PR #342 审阅 P3-3 处置，
/// 2026-10-28）：内存防线不等下次 save——收紧上限当场把超额锚淘汰掉。
pub fn CheckpointManager::set_max_checkpoints(
  self : CheckpointManager,
  n : Int32,
) -> Unit {
  self.max_checkpoints = n
  self.evict_over_limit()
}

///|
pub fn CheckpointManager::get_interval(self : CheckpointManager) -> Int32 {
  self.interval
}
