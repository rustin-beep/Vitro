///| S6 执行层·内存域：**1MB 线性内存载体（`Memory`）**。
///
/// **载体选择（勘察 §7.1 已判定，非本批自选）**：`FixedArray[Byte]`。
/// 同批报告实测：`Bytes` **不可变**（"直接排除作内存本体"，仅可作快照/输出
/// 载体）；`FixedArray[Byte]` 可写（`arr[3] = b'A'` → 65）。批量走
/// `fill` / `blit_from_bytes` / `unsafe_blit`；u32/u64 写入走内建
/// `unsafe_write_uint32_le` / `unsafe_write_uint64_le`（`bytes_unsafe.mbt`）。
/// **读侧没有 FixedArray 版原语**（`bytes_unsafe.mbt` 的读原语是 `Bytes`
/// 类型），故手工索引拼装——与 Rust 现版
/// `i32::from_le_bytes([m[a], m[a+1], m[a+2], m[a+3]])` 同形同价。
///
/// **单入口（勘察 §5.1 建议 + §9.2 约束 #1 的结构要求）**：
/// `bytes` / `dirty` 是 **priv 字段**，本包之外拿不到裸字节；所有读写都必须
/// 经 `MemoryMap::check_access` + 本类型的受检方法。现版 host 层 10+ 处
/// 裸切片绕过 UAF 检查（`host/string.rs:165/166/252/275`）在结构上不可能
/// 发生——"host 层绕过检测"从"要记得别绕"变成"没有路可绕"。
///
/// 第 4 级脏页标记紧跟判定之后（写路径），页号用**移位**而非除法
/// （勘察 §5.1：wasm-gc 无硬件除法指令；Rust 现版是 `addr as usize / PAGE_SIZE`）。

///|
/// 1MB 线性内存载体 + 脏页位图。
pub struct Memory {
  /// 1MB 字节（`MEM_SIZE`），零初始化。priv——唯一的读写路径见上。
  bytes : FixedArray[Byte]
  /// 脏页位图（`DIRTY_WORD_COUNT` 个字，每字 64 页）——增量快照的输入。
  dirty : FixedArray[UInt64]
}

///|
/// 1MB 零初始化载体（Rust `vec![0; 1MB]`，`state.rs:151`）。
pub fn Memory::new() -> Memory {
  Memory::{
    bytes: FixedArray::make(@bytecode.MEM_SIZE.reinterpret_as_int(), b'\x00'),
    dirty: FixedArray::make(DIRTY_WORD_COUNT, 0UL),
  }
}

///|
/// 载体字节数（= `MEM_SIZE`）。
pub fn Memory::length(self : Memory) -> Int {
  self.bytes.length()
}

///|
/// 全量清零 + 脏页复位（Rust `reset()` 的 `memory.fill(0)`）。
pub fn Memory::reset(self : Memory) -> Unit {
  self.bytes.fill(b'\x00')
  self.clear_dirty()
}

///|
/// 整块快照：克隆 1MB。
///
/// 这是「通道 4 · 最终内存映像」与 Full 快照的共同出口（Rust
/// `VitroVM::memory_ref() -> &[u8]`，`core/state.rs:618-620`；capi 无直接
/// 导出口）。**它是只读拷贝，不构成受检访问的绕过**——拿到的副本无论如何
/// 改动都不回写载体。登记为对外面：导入/导出与对拍驱动需要整块取像。
pub fn Memory::clone_raw(self : Memory) -> FixedArray[Byte] {
  let n = self.bytes.length()
  let out : FixedArray[Byte] = FixedArray::make(n, b'\x00')
  out.unsafe_blit(0, self.bytes, 0, n)
  out
}

///|
/// 从整块映像恢复（Full 快照 apply / 载体重置）。长度不符时 **min 部分覆盖**
/// （照搬 Rust `snapshot.rs::apply_to` Full 分支 `min(v.len, dst.len)`：
/// 前缀覆盖、余部保留——静默 return 会叫短于载体的快照恢复悄悄全丢，
/// clone_snapshot_deep 往返正确性不再隐式依赖长度相等；六轮审阅顺带修）。
pub fn Memory::restore_raw(self : Memory, data : FixedArray[Byte]) -> Unit {
  let n = if data.length() < self.bytes.length() {
    data.length()
  } else {
    self.bytes.length()
  }
  if n > 0 {
    self.bytes.unsafe_blit(0, data, 0, n)
  }
}

///|
/// 单页字节快照（增量快照的页载体，Rust `memory[off..off+4096].to_vec()`）。
pub fn Memory::page(self : Memory, page_idx : Int) -> FixedArray[Byte] {
  let off = page_idx * PAGE_SIZE
  let out : FixedArray[Byte] = FixedArray::make(PAGE_SIZE, b'\x00')
  out.unsafe_blit(0, self.bytes, off, PAGE_SIZE)
  out
}

///|
/// 写回单页（增量快照 apply）。
pub fn Memory::write_page(
  self : Memory,
  page_idx : Int,
  data : FixedArray[Byte],
) -> Unit {
  if data.length() != PAGE_SIZE {
    return
  }
  self.bytes.unsafe_blit(page_idx * PAGE_SIZE, data, 0, PAGE_SIZE)
}

// ── 脏页追踪 ────────────────────────────────────────────────────────────────

///|
/// 标记 `[addr, addr + len)` 覆盖的页为脏。
///
/// 页号 = `addr >> PAGE_SHIFT`（Rust 是 `/ PAGE_SIZE`）。`len == 0` 直接返回
/// （Rust `mark_dirty_page` 同款守卫——否则 `addr + len - 1` 回绕到极大页号）。
pub fn Memory::mark_dirty(self : Memory, addr : UInt, len : UInt) -> Unit {
  if len == 0U {
    return
  }
  let start = (addr.to_uint64() >> PAGE_SHIFT).to_int()
  let end = ((addr.to_uint64() + len.to_uint64() - 1UL) >> PAGE_SHIFT).to_int()
  for p = start; p <= end; p = p + 1 {
    if p < PAGE_COUNT {
      let w = p >> 6
      let bit = p & 63
      self.dirty[w] = self.dirty[w] | (1UL << bit)
    }
  }
}

///|
/// 清空脏页记录（检查点落盘后调用）。
pub fn Memory::clear_dirty(self : Memory) -> Unit {
  self.dirty.fill(0UL)
}

///|
/// 脏页位图字数。
pub fn Memory::dirty_word_count(self : Memory) -> Int {
  self.dirty.length()
}

///|
/// 第 `w` 个脏页字（增量快照按位扫描的输入，Rust `dirty_pages[word]`）。
pub fn Memory::dirty_word(self : Memory, w : Int) -> UInt64 {
  self.dirty[w]
}

///|
/// 置位脏页号的升序列表（word 升序 → bit 升序，与 Rust
/// `snapshot_incremental` 的双层扫描同序——快照页序影响 Delta 的确定性，
/// 而 `Hasher` 种子在 wasm 与 native 下不同，任何依赖哈希迭代序的写法都是
/// 非确定源，见总计划 F6）。
pub fn Memory::dirty_pages(self : Memory) -> Array[Int] {
  let out : Array[Int] = []
  for w = 0; w < DIRTY_WORD_COUNT; w = w + 1 {
    let bits = self.dirty[w]
    if bits == 0UL {
      continue
    }
    for b = 0; b < 64; b = b + 1 {
      if ((bits >> b) & 1UL) == 1UL {
        out.push((w << 6) + b)
      }
    }
  }
  out
}

// ── 受检访问（唯一入口）──────────────────────────────────────────────────────

///|
/// 单字节的 i8 语义（Rust `b as i8 as i32`）。
fn byte_to_i32(b : Byte) -> Int {
  let v = b.to_int()
  if v >= 128 {
    v - 256
  } else {
    v
  }
}

///|
/// 尾部四字节的 u32 拼装（小端）。
fn Memory::u32_at(self : Memory, off : Int) -> UInt {
  @util.le_u32_at(self.bytes, off)
}

///|
/// 尾部八字节的 u64 拼装（小端）。
fn Memory::u64_at(self : Memory, off : Int) -> UInt64 {
  @util.le_u64_at(self.bytes, off)
}

///|
/// 受检单字节读（i8 符号扩展后的 `Int`）。
pub fn Memory::load_i8(
  self : Memory,
  map : MemoryMap,
  addr : UInt,
) -> Result[Int, MemFault] {
  match map.check_access(addr, 1U, AccessKind::Read) {
    Ok(_) => Ok(byte_to_i32(self.bytes[addr.reinterpret_as_int()]))
    Err(e) => Err(e)
  }
}

///|
/// 受检单字节写（取低 8 位，Rust `val as u8`）。
pub fn Memory::store_i8(
  self : Memory,
  map : MemoryMap,
  addr : UInt,
  val : Int,
) -> Result[Unit, MemFault] {
  match map.check_access(addr, 1U, AccessKind::Write) {
    Ok(_) => {
      self.bytes[addr.reinterpret_as_int()] = val.to_byte()
      self.mark_dirty(addr, 1U)
      Ok(())
    }
    Err(e) => Err(e)
  }
}

///|
/// 受检 u32 读（i32 / f32 / 指针位模式同为 4 字节，位模式由调用方重解释）。
pub fn Memory::load_u32(
  self : Memory,
  map : MemoryMap,
  addr : UInt,
) -> Result[UInt, MemFault] {
  match map.check_access(addr, 4U, AccessKind::Read) {
    Ok(_) => Ok(self.u32_at(addr.reinterpret_as_int()))
    Err(e) => Err(e)
  }
}

///|
/// 受检 u32 写（小端四字节）。
pub fn Memory::store_u32(
  self : Memory,
  map : MemoryMap,
  addr : UInt,
  val : UInt,
) -> Result[Unit, MemFault] {
  match map.check_access(addr, 4U, AccessKind::Write) {
    Ok(_) => {
      let off = addr.reinterpret_as_int()
      self.bytes[off] = val.to_byte()
      self.bytes[off + 1] = (val >> 8).to_byte()
      self.bytes[off + 2] = (val >> 16).to_byte()
      self.bytes[off + 3] = (val >> 24).to_byte()
      self.mark_dirty(addr, 4U)
      Ok(())
    }
    Err(e) => Err(e)
  }
}

///|
/// 受检 u64 读（i64 / f64 位模式）。
pub fn Memory::load_u64(
  self : Memory,
  map : MemoryMap,
  addr : UInt,
) -> Result[UInt64, MemFault] {
  match map.check_access(addr, 8U, AccessKind::Read) {
    Ok(_) => Ok(self.u64_at(addr.reinterpret_as_int()))
    Err(e) => Err(e)
  }
}

///|
/// 受检 u64 写（小端八字节）。
pub fn Memory::store_u64(
  self : Memory,
  map : MemoryMap,
  addr : UInt,
  val : UInt64,
) -> Result[Unit, MemFault] {
  match map.check_access(addr, 8U, AccessKind::Write) {
    Ok(_) => {
      let off = addr.reinterpret_as_int()
      self.bytes[off] = val.to_uint().to_byte()
      self.bytes[off + 1] = (val >> 8).to_uint().to_byte()
      self.bytes[off + 2] = (val >> 16).to_uint().to_byte()
      self.bytes[off + 3] = (val >> 24).to_uint().to_byte()
      self.bytes[off + 4] = (val >> 32).to_uint().to_byte()
      self.bytes[off + 5] = (val >> 40).to_uint().to_byte()
      self.bytes[off + 6] = (val >> 48).to_uint().to_byte()
      self.bytes[off + 7] = (val >> 56).to_uint().to_byte()
      self.mark_dirty(addr, 8U)
      Ok(())
    }
    Err(e) => Err(e)
  }
}

// ── 批量（"无检查快路径 + 一次前置检查"，勘察 §5.1）────────────────────────────

///|
/// 受检批量写（`Bytes` 源）。
///
/// 现版 Rust 的批量写分两态：`write_memory` 用 `copy_from_slice`（快），
/// `OpCode::Memcpy` 与 `host_malloc` 的 zero-init 却**逐字节 `store_i8` 循环**
/// （`executor/memory.rs:225-227`、`host/memory.rs:240-247/331-333`）——
/// 每条字节都重跑一次 NULL/上界/UAF 判定。这里统一为"段级判定一次 + 载体原生
/// `blit_from_bytes`"：**纯收益且不损语义**（边界已在段级验证）。
pub fn Memory::write_bytes(
  self : Memory,
  map : MemoryMap,
  addr : UInt,
  data : Bytes,
) -> Result[Unit, MemFault] {
  let len = data.length()
  match map.check_access(addr, len.reinterpret_as_uint(), AccessKind::Write) {
    Ok(_) => {
      self.bytes.blit_from_bytes(addr.reinterpret_as_int(), data, 0, len)
      self.mark_dirty(addr, len.reinterpret_as_uint())
      Ok(())
    }
    Err(e) => Err(e)
  }
}

///|
/// 受检批量填充（`Memset` 的载体原语，Rust `slice.fill`）。
pub fn Memory::fill(
  self : Memory,
  map : MemoryMap,
  addr : UInt,
  len : Int,
  byte : Byte,
) -> Result[Unit, MemFault] {
  match map.check_access(addr, len.reinterpret_as_uint(), AccessKind::Write) {
    Ok(_) => {
      let off = addr.reinterpret_as_int()
      self.bytes.fill(byte, start=off, end=off + len)
      self.mark_dirty(addr, len.reinterpret_as_uint())
      Ok(())
    }
    Err(e) => Err(e)
  }
}

///|
/// 受检重叠安全拷贝（`memmove` 语义）。
///
/// 两端都判定：目标按**写**、源按**读**（Rust `copy_memory` 的两路 `check_uaf`
/// 同款）。经临时缓冲实现重叠安全（Rust 用 `to_vec()` 避重叠，
/// `core/memory.rs:81-83`）。
pub fn Memory::copy(
  self : Memory,
  map : MemoryMap,
  dst : UInt,
  src : UInt,
  len : Int,
) -> Result[Unit, MemFault] {
  match map.check_access(dst, len.reinterpret_as_uint(), AccessKind::Write) {
    Ok(_) =>
      match map.check_access(src, len.reinterpret_as_uint(), AccessKind::Read) {
        Ok(_) => {
          let tmp : FixedArray[Byte] = FixedArray::make(len, b'\x00')
          tmp.unsafe_blit(0, self.bytes, src.reinterpret_as_int(), len)
          self.bytes.unsafe_blit(dst.reinterpret_as_int(), tmp, 0, len)
          self.mark_dirty(dst, len.reinterpret_as_uint())
          Ok(())
        }
        Err(e) => Err(e)
      }
    Err(e) => Err(e)
  }
}
