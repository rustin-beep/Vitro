///| L7 执行层·VM 域：**增量快照原语**——批四号二段照搬 Rust
/// `core/snapshot.rs:38-78`（脏页 Delta）；S8 批一号一段（2026-09-30）
/// CheckpointManager **迁出**至 L9 `time_travel`（落点裁定：智能判据是
/// 教学语义词汇，不应由 VM 拥有——修复 Rust 侧分层破损，详见
/// time_travel/moon.pkg 头注）。本文件只保留**无策略**快照原语：
/// `snapshot_incremental`（脏页 Delta）与 `MemoryImage::apply_to`（页应用）。
///
/// **门 3 验收锚**：全量往返/增量脏页/淘汰不变量/step-0 锚点/隔离区
/// 三件套六锚已随 CheckpointManager 迁至
/// `time_travel/checkpoint_wbtest.mbt`（wbtest 跨包 import 限制下随类型
/// 迁移；断言与构造原样）。

///|
/// **增量快照**（脏页 Delta——照搬 `core/snapshot.rs:38-78`）：脏页位图
/// 逐位枚举，命中的 4KB 页整页拷入 `pages`；其余字段与全量同集。
pub fn VitroVM::snapshot_incremental(
  self : VitroVM,
  base_step : Int,
) -> VMSnapshot {
  let pages : Array[(Int, FixedArray[Byte])] = []
  for word = 0; word < @memory.DIRTY_WORD_COUNT; word = word + 1 {
    let mut bitmap = self.memory.dirty_word(word)
    while bitmap != 0UL {
      let bit = bitmap.ctz()
      bitmap = bitmap & (18446744073709551615UL ^ (1UL << bit))
      let page_idx = word * 64 + bit
      if page_idx >= @memory.PAGE_COUNT {
        continue
      }
      // 整页拷贝（page 原语返回拷贝——快照独立性）
      pages.push((page_idx, self.memory.page(page_idx)))
    }
  }
  // 其余字段与全量同集（复用 snapshot 的字段集——两端单点纪律：
  // snapshot_incremental 与 snapshot 的字段集必须同源。此处采用
  // 「先全量后替换 memory 为 Delta」形态，保证字段集零漂移）
  let full = self.snapshot()
  { ..full, memory: Delta(base_step, pages), }
}

///|
/// MemoryImage 应用到内存（Delta 的页覆盖——`nearest` 重建与 restore 用）。
pub fn MemoryImage::apply_to(self : MemoryImage, vm : VitroVM) -> Unit {
  match self {
    Full(bytes) => vm.memory.restore_raw(clone_byte_array(bytes))
    Delta(_, pages) =>
      for pair in pages {
        vm.memory.write_page(pair.0, pair.1)
      }
  }
}
