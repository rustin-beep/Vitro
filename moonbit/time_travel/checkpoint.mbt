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

///|
/// 检查点管理器。
pub struct CheckpointManager {
  /// (step, snapshot) 序列。
  checkpoints : Array[(Int, @vm.VMSnapshot)]
  /// 固定间隔（步数）保底策略。
  interval : Int
  /// 智能检查点：控制流边界（调用/返回/循环/交换/内存操作）额外保存。
  mut smart_mode : Bool
  /// 最大检查点数量（防长程序内存无限增长）。
  mut max_checkpoints : Int
  /// 每 N 个检查点强制一个全量基准。
  pub full_every : Int
}

///|
pub fn CheckpointManager::new(interval : Int) -> CheckpointManager {
  {
    checkpoints: [],
    interval,
    smart_mode: true,
    max_checkpoints: 50,
    full_every: 5,
  }
}

///|
/// 当前步是否需保存检查点（固定间隔保底 + 智能模式在控制流边界触发）。
/// **判据字符串形态照搬**（词汇单源 = protocol vocabulary；enum 化随
/// collector 批走红→绿——迁移与改形分离）。
pub fn CheckpointManager::should_checkpoint(
  self : CheckpointManager,
  step : Int,
  semantic_label : String,
) -> Bool {
  if step % self.interval == 0 {
    return true
  }
  if !self.smart_mode {
    return false
  }
  // 智能策略：函数调用、返回、循环边界、数组交换、内存操作
  let is_significant = semantic_label.starts_with("调用 ") ||
    semantic_label == "返回" ||
    semantic_label == "内存分配" ||
    semantic_label == "释放内存" ||
    semantic_label.contains("交换") ||
    semantic_label.starts_with("循环")
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
  step : Int,
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
/// 超上限淘汰（U2#5 修复形态照搬——三条不变量见模块头注）。
fn CheckpointManager::evict_over_limit(self : CheckpointManager) -> Unit {
  while self.checkpoints.length() > self.max_checkpoints {
    let pinned = self.checkpoints[0].0 == 0
    let remove_idx = if pinned { 1 } else { 0 }
    if remove_idx >= self.checkpoints.length() {
      break
    }
    let removed_is_full = self.checkpoints[remove_idx].1.memory is @vm.Full(_)
    ignore(self.checkpoints.remove(remove_idx))
    ignore(removed_is_full)
    if removed_is_full {
      // 删 Full：级联删其后 Delta 到下一个 Full（悬空 Delta = seek 静默
      // 错内存——U2#5）
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
      // 删链头 Delta（防御）：删到 Full 维持链头不变量
      while self.checkpoints.length() > 0 &&
            !(self.checkpoints[0].1.memory is @vm.Full(_)) {
        ignore(self.checkpoints.remove(0))
      }
    }
  }
}

///|
/// 找不超过 target 的最近检查点，Delta 链重建为可直接恢复的全量快照。
pub fn CheckpointManager::nearest(
  self : CheckpointManager,
  target : Int,
) -> (Int, @vm.VMSnapshot)? {
  let idx = match last_le(self.checkpoints, target) {
    Some(i) => i
    None => return None
  }
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
      let mut base_idx : Int? = None
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
  checkpoints : Array[(Int, @vm.VMSnapshot)],
  base_idx : Int,
  target_idx : Int,
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
  checkpoints : Array[(Int, @vm.VMSnapshot)],
  target : Int,
) -> Int? {
  let mut found : Int? = None
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
  page_idx : Int,
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
pub fn CheckpointManager::length(self : CheckpointManager) -> Int {
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
/// 设置最大检查点数（同上）。
pub fn CheckpointManager::set_max_checkpoints(
  self : CheckpointManager,
  n : Int,
) -> Unit {
  self.max_checkpoints = n
}

///|
pub fn CheckpointManager::get_interval(self : CheckpointManager) -> Int {
  self.interval
}
