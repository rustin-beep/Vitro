///| 字符串/内存族 19 个 handler（Rust `host/string.rs` 照搬，勘察 §1.7 族 E）。
///
/// **读侧口径（位置 B，既定接纳方案）**：oracle 的读路径是**裸读**——
/// `read_cbytes`（`host/utils.rs:4-11`）只查下界，NULL 区静默读零（坑 16
/// `strlen(NULL)=0`）、已释放块静默读内容、越界当 0 软夹紧（坑 18）。本实现
/// 一律走 `memory` 包受检单入口（NULL → UAF → 上界），**该 trap 的现在会
/// trap**——合法输入（NUL 终止、指针有效）行为逐字节一致；分叉只出现在
/// oracle 的绕检形状上，逐条登记（memory 包 `check_access` 同款先例）。
///
/// **写侧口径**：oracle 分两态——`strcpy`/`strcat`/`strncpy`/`strncat` 走
/// `store_i8`（**受检**），`memset`/`memcpy`/`memmove` 走裸切片（**无检**，
/// U5#1 缺陷）。本实现统一受检（段级 `fill`/`copy`/`write_bytes`），后者与
/// oracle 的分叉（写已释放块 oracle 静默、此处 E3060）按勘察 §4.2-2
/// 「直接按目标架构实现」登记——oracle 侧两侧同修候选。
///
/// **软夹紧的界内保留**：oracle 的 `min(n, 剩余空间)` 截断凡能在界内表达的
/// 照搬（`memset` 超长截断到内存尾、`strncpy` 负 `n` 补零到内存尾——U5#3
/// 形状），不做"更正确"的改写——对拍等价优先，形状差异走台账。
///
/// **参数形态照搬 oracle 的取数宽度**：`memset` 的 `value`/`size` 取**原始
/// u64 栈字**（`string.rs:148-149`），`strncpy`/`memcpy`/`strncmp`/`memcmp`/
/// `memchr` 取 **i32 再扩**（负数 → 巨值 → 截断到界内），`strncat`/`strchr`
/// 族按各自 `as` 目标注明——**vm 接线时不得统一**。

///|
/// 栈缓冲区描述（V-P1-6：`strcpy`/`strcat` 的栈上容量校验输入）。
///
/// oracle 的 `check_stack_buffer_capacity`（`host/utils.rs:501-526`）遍历
/// `vm.call_stack`（**逆序——最内层帧优先**）的 `local_buffers`，命中第一个
/// 包含 `dest` 的缓冲区即判容量。VM 耦合数据由 vm 侧展平传入：按内层到外层
/// 顺序 append，命中即停的语义与本数组迭代一致。空数组 = 无栈缓冲（等价
/// oracle 空调用栈）。
pub(all) struct StackBufferSpan {
  /// 缓冲区绝对地址（`frame.locals_base + buf.offset`）。
  base : UInt
  /// 缓冲区容量（字节）。
  size : Int
  /// 源码里的缓冲区名（E3070 文案用）。
  name : String
} derive(Debug, Eq)

///|
/// 受检读 C 字符串（到 NUL，不含 NUL）——oracle `read_cbytes` 的受检形态。
///
/// oracle 裸读三缺口（NULL 静默零/UAF 静默读/越界当 0）在此全部转为
/// `MemFault`；字符串无 NUL 直抵内存尾时，最后一次越界读自然 fault——
/// 不需要专门的长度上限。
fn read_cstring(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  addr : UInt,
) -> Result[Bytes, @memory.MemFault] {
  let buf : Array[Byte] = []
  let mut i = 0
  let mut fault : @memory.MemFault? = None
  while true {
    match mem.load_i8(map, addr + i.reinterpret_as_uint()) {
      Ok(b) => {
        if b == 0 {
          break
        }
        buf.push(b.to_byte())
        i = i + 1
      }
      Err(f) => {
        fault = Some(f)
        break
      }
    }
  }
  match fault {
    Some(f) => Err(f)
    None => Ok(Bytes::from_array(buf))
  }
}

///|
/// `Bytes` 含字节判定（`strpbrk`/`strspn`/`strcspn` 的集合查询）。
fn bytes_contains(hay : Bytes, b : Byte) -> Bool {
  let n = hay.length()
  let mut i = 0
  while i < n {
    if hay[i] == b {
      return true
    }
    i = i + 1
  }
  false
}

///|
/// 4 位补零大写十六进制（memset 的 NULL trap 文案口径 `0x{:04X}`）。
fn hex04_upper(v : UInt) -> String {
  let h = hex_upper(v)
  let mut out = "0x"
  let pad = 4 - h.length()
  if pad > 0 {
    let mut i = 0
    while i < pad {
      out = out + "0"
      i = i + 1
    }
  }
  out + h
}

///|
/// 受检故障 → trap 回复。
fn fault_reply(f : @memory.MemFault) -> HostMemReply {
  trap_only(access_fault_text(f))
}

///|
/// 堆区域 E3070 检查的公共查找：第一个**包含 `dest` 的存活堆块**
/// （`>= 起始`——dest 常为块起点，与 oracle `string.rs:85-99` 的
/// `dest >= r.addr && dest < r.addr + r.size` 同口径；注意区别于 memory 包
/// `find_live_region_containing` 的严格大于——那是 free 内部地址诊断口径）。
fn live_region_at_or_containing(
  map : @memory.MemoryMap,
  dest : UInt,
) -> (UInt, Int, String)? {
  for pa in map.regions_to_array() {
    let base = pa.0
    let r = pa.1
    if !r.is_freed && dest >= base && dest < base + r.size.reinterpret_as_uint() {
      return Some((base, r.size, r.name))
    }
  }
  None
}

///|
/// 栈缓冲区容量校验（V-P1-6 照搬）：`dest` 落在某缓冲区内时，`needed`
/// 超容量即 E3070 trap（返回文本）；命中且容量足够则**停止查找**（oracle
/// `check_stack_buffer_capacity` 的命中即停语义——第一个包含 dest 的缓冲区
/// 说了算）。未命中任何缓冲区返回 `None` 继续。
fn stack_buffer_check(
  stack_buffers : Array[StackBufferSpan],
  dest : UInt,
  needed : Int,
  op : String,
) -> String? {
  for buf in stack_buffers {
    if dest >= buf.base && dest < buf.base + buf.size.reinterpret_as_uint() {
      let available = buf.size - (dest - buf.base).reinterpret_as_int()
      if needed > available {
        return Some(
          "💥 Buffer Overflow (E3070)：\{op} 写入栈上缓冲区 '\{buf.name}' 溢出。需要写入 \{needed} 字节，但该缓冲区从当前写入位置起仅剩 \{available} 字节（总大小 \{buf.size} 字节）。\n\n💡 原因：\{op} 不检查目标缓冲区大小，栈上数组越界会破坏相邻局部变量。\n✅ 解决方法：增大数组大小，或改用带长度限制的版本（如 strncpy/fgets）。",
        )
      }
      return None
    }
  }
  None
}

///|
/// `strlen(s)`（oracle `string.rs:4-8`；读侧受检化——`strlen(NULL)` 从
/// oracle 的静默 0 改为 NULL trap，坑 16 既定方向）。
pub fn host_strlen(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  addr : UInt,
) -> HostMemReply {
  match read_cstring(mem, map, addr) {
    Ok(s) => value_only(s.length().to_uint64())
    Err(f) => fault_reply(f)
  }
}

///|
/// `strdup(s)`（oracle `string.rs:10-71`）。分配三步契约与 malloc 同构
/// （allocate_raw → 清 freed_logs → register_alloc「复位或 push」）。
///
/// 堆耗尽**静默压 NULL、无附注**（oracle `:20-26` 同——与 malloc 的附注
/// 行为不一致，oracle 已知不一致点，照搬并登记两侧同修候选）。
pub fn host_strdup(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  src : UInt,
  alloc_line : Int,
) -> HostMemReply {
  let src_bytes = match read_cstring(mem, map, src) {
    Ok(s) => s
    Err(f) => return fault_reply(f)
  }
  let len = src_bytes.length()
  let size = len + 1
  if size <= 0 {
    return null_silent()
  }
  let aligned = @bytecode.align4(size.reinterpret_as_uint())
  let addr = match map.allocate_raw(aligned, @bytecode.MEM_SIZE) {
    Some(a) => a
    None => return null_silent()
  }
  map.freed_logs_remove_overlapping(addr, addr + aligned)
  // 复制内容 + 终止符（oracle 是截断到内存尾的 store_i8 循环；受检批量写
  // 在合法形状下等价，越界/NUL 落点故障转 trap）
  match mem.write_bytes(map, addr, src_bytes) {
    Ok(_) => ()
    Err(f) => return fault_reply(f)
  }
  match mem.store_i8(map, addr + len.reinterpret_as_uint(), 0) {
    Ok(_) => ()
    Err(f) => return fault_reply(f)
  }
  map.register_alloc(addr, size, alloc_line, "strdup", true)
  value_only(addr.to_uint64())
}

///|
/// `strcpy(dest, src)`（oracle `string.rs:73-116`）——路由表**改判回 Host**
/// 的两个函数之一（`is_host_rerouted`），存在理由就是 E3070 双重校验：
/// 堆块容量 → 栈缓冲容量。
pub fn host_strcpy(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  dest : UInt,
  src : UInt,
  stack_buffers : Array[StackBufferSpan],
) -> HostMemReply {
  let src_bytes = match read_cstring(mem, map, src) {
    Ok(s) => s
    Err(f) => return fault_reply(f)
  }
  let src_len = src_bytes.length()
  // E3070 堆块容量检查（第一个包含 dest 的存活块）
  match live_region_at_or_containing(map, dest) {
    Some(triple) => {
      let base = triple.0
      let rsize = triple.1
      let rname = triple.2
      let offset = (dest - base).reinterpret_as_int()
      let available = rsize - offset
      if src_len + 1 > available {
        return trap_only(
          "💥 Buffer Overflow (E3070)：strcpy 目标缓冲区溢出。源字符串长度 \{src_len} 字节（含终止符 \{src_len + 1} 字节），但目标区域 '\{rname}' 从偏移 \{offset} 开始仅剩 \{available} 字节。\n\n💡 原因：strcpy 不会检查目标缓冲区大小。\n✅ 解决方法：使用 strncpy 或确保目标缓冲区足够大（至少 \{src_len + 1} 字节）。",
        )
      }
    }
    None => ()
  }
  // V-P1-6 栈缓冲容量检查
  match stack_buffer_check(stack_buffers, dest, src_len + 1, "strcpy") {
    Some(t) => return trap_only(t)
    None => ()
  }
  // 写入（受检批量；oracle 是截断 store_i8 循环）
  match mem.write_bytes(map, dest, src_bytes) {
    Ok(_) => ()
    Err(f) => return fault_reply(f)
  }
  match mem.store_i8(map, dest + src_len.reinterpret_as_uint(), 0) {
    Ok(_) => ()
    Err(f) => return fault_reply(f)
  }
  value_only(dest.to_uint64())
}

///|
/// `strcmp(s1, s2)`（oracle `string.rs:118-143`）——逐字节**有符号**差
/// （`(a as i8).wrapping_sub(b as i8) as i32 as u64`——负差符号扩展压栈）。
pub fn host_strcmp(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  addr1 : UInt,
  addr2 : UInt,
) -> HostMemReply {
  let mut i = 0
  while true {
    let a = match mem.load_i8(map, addr1 + i.to_uint()) {
      Ok(v) => v
      Err(f) => return fault_reply(f)
    }
    let b = match mem.load_i8(map, addr2 + i.to_uint()) {
      Ok(v) => v
      Err(f) => return fault_reply(f)
    }
    if a != b {
      return value_only((a - b).to_int64().reinterpret_as_uint64())
    }
    if a == 0 {
      return value_only(0UL)
    }
    i = i + 1
  }
  abort_unreachable()
}

///|
/// `memset(ptr, value, size)`（oracle `string.rs:146-168`）——`value`/`size`
/// 取**原始 u64 栈字**（oracle `as` 链原样）。NULL 区前置检查**保留 oracle
/// 的专属文案**（`0x{:04X}` 四位补零口径）；超长 `size` 照搬截断到内存尾。
///
/// 与 oracle 的分叉（登记）：oracle 裸 `fill` **不查 UAF**（U5#1）——此处
/// 受检 `fill`，写已释放块报 E3060。
pub fn host_memset(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  ptr : UInt,
  value : UInt64,
  size : UInt64,
) -> HostMemReply {
  let mem_size = @bytecode.MEM_SIZE
  // 超界起点：剩余空间为 0 → 空操作原样返回（oracle `ptr >= mem_size` 早退）
  let max_write = if ptr >= mem_size { 0U } else { mem_size - ptr }
  let size_u = if size > 0xFFFFFFFFUL { 0xFFFFFFFFUL } else { size }
  let write_len = if size_u.to_uint() > max_write {
    max_write
  } else {
    size_u.to_uint()
  }
  if ptr < @bytecode.NULL_TRAP_SIZE && write_len > 0U {
    return trap_only(
      "向 NULL 指针区域写入（地址 \{hex04_upper(ptr)}）。请确认指针已被正确初始化。",
    )
  }
  if write_len > 0U {
    match
      mem.fill(
        map,
        ptr,
        write_len.reinterpret_as_int(),
        (value & 0xFFUL).to_byte(),
      ) {
      Ok(_) => ()
      Err(f) => return fault_reply(f)
    }
  }
  value_only(ptr.to_uint64())
}

///|
/// `strcat(dest, src)`（oracle `string.rs:170-217`）——先受检扫 dest 尾，
/// 再 E3070 双重校验（所需容量 = 已有 + 源 + 终止符）。
pub fn host_strcat(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  dest : UInt,
  src : UInt,
  stack_buffers : Array[StackBufferSpan],
) -> HostMemReply {
  // 扫 dest 已有内容的末尾（NUL 前一字节；oracle 扫到内存尾兜底，此处
  // 无 NUL 直抵内存尾时自然 fault）
  let mut end = dest
  while true {
    match mem.load_i8(map, end) {
      Ok(b) => {
        if b == 0 {
          break
        }
        end = end + 1U
      }
      Err(f) => return fault_reply(f)
    }
  }
  let dest_len = (end - dest).reinterpret_as_int()
  let src_bytes = match read_cstring(mem, map, src) {
    Ok(s) => s
    Err(f) => return fault_reply(f)
  }
  let src_len = src_bytes.length()
  // E3070 堆块容量检查
  match live_region_at_or_containing(map, dest) {
    Some(triple) => {
      let base = triple.0
      let rsize = triple.1
      let rname = triple.2
      let offset = (dest - base).reinterpret_as_int()
      let available = rsize - offset
      let total = dest_len + src_len + 1
      if total > available {
        return trap_only(
          "💥 Buffer Overflow (E3070)：strcat 目标缓冲区溢出。已有 \{dest_len} 字节 + 源字符串 \{src_len} 字节 + 终止符 1 字节 = \{total} 字节，但目标区域 '\{rname}' 从偏移 \{offset} 开始仅剩 \{available} 字节。\n\n💡 原因：strcat 不会检查目标缓冲区剩余容量。\n✅ 解决方法：使用 strncat 或确保目标缓冲区足够大。",
        )
      }
    }
    None => ()
  }
  // V-P1-6 栈缓冲容量检查（end 为 dest 起已有内容末尾——oracle 以 dest 查块）
  match
    stack_buffer_check(stack_buffers, dest, dest_len + src_len + 1, "strcat") {
    Some(t) => return trap_only(t)
    None => ()
  }
  // 追加 + 终止符（受检批量；oracle 是截断 store_i8 循环）
  match mem.write_bytes(map, end, src_bytes) {
    Ok(_) => ()
    Err(f) => return fault_reply(f)
  }
  match mem.store_i8(map, end + src_len.reinterpret_as_uint(), 0) {
    Ok(_) => ()
    Err(f) => return fault_reply(f)
  }
  value_only(dest.to_uint64())
}

///|
/// `strncpy(dest, src, n)`（oracle `string.rs:219-239`）——`n` 取 **i32 再
/// 符号扩为巨量**（负 `n` → 补零到内存尾，U5#3 缺陷形状照搬）；拷贝段后
/// `[copy_len, write_len)` 补零（C 语义）。
pub fn host_strncpy(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  dest : UInt,
  src : UInt,
  n : Int,
) -> HostMemReply {
  let src_bytes = match read_cstring(mem, map, src) {
    Ok(s) => s
    Err(f) => return fault_reply(f)
  }
  let mem_size = @bytecode.MEM_SIZE
  let max_write = if dest >= mem_size { 0U } else { mem_size - dest }
  // 负 n：i32 as usize 符号扩展恒大于 max_write → 全额补零（oracle 缺陷形状）
  let write_len = if n < 0 || n.reinterpret_as_uint() > max_write {
    max_write
  } else {
    n.reinterpret_as_uint()
  }
  let copy_len = if src_bytes.length().reinterpret_as_uint() > write_len {
    write_len.reinterpret_as_int()
  } else {
    src_bytes.length()
  }
  // 拷贝段
  if copy_len > 0 {
    let head : Array[Byte] = []
    let mut i = 0
    while i < copy_len {
      head.push(src_bytes[i])
      i = i + 1
    }
    match mem.write_bytes(map, dest, Bytes::from_array(head)) {
      Ok(_) => ()
      Err(f) => return fault_reply(f)
    }
  }
  // 补零段
  let zero_len = write_len.reinterpret_as_int() - copy_len
  if zero_len > 0 {
    match
      mem.fill(map, dest + copy_len.reinterpret_as_uint(), zero_len, b'\x00') {
      Ok(_) => ()
      Err(f) => return fault_reply(f)
    }
  }
  value_only(dest.to_uint64())
}

///|
/// `memcpy(dest, src, n)` / `memmove(dest, src, n)`（oracle `:241-285` 两函数
/// 逐字同型——`to_vec` 中转即重叠安全，故二者行为相同；`Memory::copy` 本就是
/// memmove 语义，一实现两用）。`n` 取 i32 符号扩（负 → 巨量 → 截断到界内，
/// 与 oracle 同式）。
///
/// 与 oracle 的分叉（登记）：oracle 裸拷**无 NULL/UAF 检查**（U5#1）——
/// 此处受检 `copy`，已释放块报 E3060。
pub fn host_memcpy(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  dest : UInt,
  src : UInt,
  n : Int,
) -> HostMemReply {
  host_memmove(map, mem, dest, src, n)
}

///|
/// `memmove`（见 `host_memcpy`——oracle 两函数同型，此处同实现）。
pub fn host_memmove(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  dest : UInt,
  src : UInt,
  n : Int,
) -> HostMemReply {
  let mem_size = @bytecode.MEM_SIZE
  let cap = if dest >= mem_size || src >= mem_size {
    0U
  } else {
    let cap_d = mem_size - dest
    let cap_s = mem_size - src
    if cap_d < cap_s {
      cap_d
    } else {
      cap_s
    }
  }
  let copy_len = if n < 0 || n.reinterpret_as_uint() > cap {
    cap
  } else {
    n.reinterpret_as_uint()
  }
  if copy_len > 0U {
    match mem.copy(map, dest, src, copy_len.reinterpret_as_int()) {
      Ok(_) => ()
      Err(f) => return fault_reply(f)
    }
  }
  value_only(dest.to_uint64())
}

///|
/// `strncat(dest, src, n)`（oracle `string.rs:287-309`）——`n` 取**原始
/// u64 栈字**（与 strncpy 的 i32 不同，oracle 原样）。
pub fn host_strncat(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  dest : UInt,
  src : UInt,
  n : UInt64,
) -> HostMemReply {
  // 扫 dest 末尾（同 strcat）
  let mut end = dest
  while true {
    match mem.load_i8(map, end) {
      Ok(b) => {
        if b == 0 {
          break
        }
        end = end + 1U
      }
      Err(f) => return fault_reply(f)
    }
  }
  let src_bytes = match read_cstring(mem, map, src) {
    Ok(s) => s
    Err(f) => return fault_reply(f)
  }
  let mem_size = @bytecode.MEM_SIZE
  let want = if src_bytes.length().to_uint64() > n {
    n
  } else {
    src_bytes.length().to_uint64()
  }
  // 尾部至少留 1 字节给终止符（oracle `saturating_sub(1)` 同式）
  let room = if end >= mem_size {
    0UL
  } else {
    (mem_size - end).to_uint64() - 1UL
  }
  let actual = if want > room { room } else { want }
  if actual > 0UL {
    let head : Array[Byte] = []
    let mut i = 0
    while i < actual.to_int() {
      head.push(src_bytes[i])
      i = i + 1
    }
    match mem.write_bytes(map, end, Bytes::from_array(head)) {
      Ok(_) => ()
      Err(f) => return fault_reply(f)
    }
  }
  match mem.store_i8(map, end + actual.to_uint(), 0) {
    Ok(_) => ()
    Err(f) => return fault_reply(f)
  }
  value_only(dest.to_uint64())
}

///|
/// `strncmp(s1, s2, n)`（oracle `string.rs:311-340`）——`n` 取 **usize 原始
/// u64**（oracle `as usize`）；i ≥ n 即等（0）。
pub fn host_strncmp(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  addr1 : UInt,
  addr2 : UInt,
  n : UInt64,
) -> HostMemReply {
  let mut i = 0UL
  while i < n {
    let a = match mem.load_i8(map, addr1 + i.to_uint()) {
      Ok(v) => v
      Err(f) => return fault_reply(f)
    }
    let b = match mem.load_i8(map, addr2 + i.to_uint()) {
      Ok(v) => v
      Err(f) => return fault_reply(f)
    }
    if a != b {
      return value_only((a - b).to_int64().reinterpret_as_uint64())
    }
    if a == 0 {
      return value_only(0UL)
    }
    i = i + 1UL
  }
  value_only(0UL)
}

///|
/// `memcmp(s1, s2, n)`（oracle `string.rs:342-365`）——与 `strncmp` 差异
/// 仅在：**不因 NUL 停**，只比 `n` 个字节（有符号字节差）。
pub fn host_memcmp(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  addr1 : UInt,
  addr2 : UInt,
  n : UInt64,
) -> HostMemReply {
  let mut i = 0UL
  while i < n {
    let a = match mem.load_i8(map, addr1 + i.to_uint()) {
      Ok(v) => v
      Err(f) => return fault_reply(f)
    }
    let b = match mem.load_i8(map, addr2 + i.to_uint()) {
      Ok(v) => v
      Err(f) => return fault_reply(f)
    }
    if a != b {
      return value_only((a - b).to_int64().reinterpret_as_uint64())
    }
    i = i + 1UL
  }
  value_only(0UL)
}

///|
/// `strchr(s, c)`（oracle `string.rs:367-387`）——**无符号字节**与 `c`
/// （i32）比较（`b as i32 == c`；负 `c` 恒不中——与 oracle 同）；`c == 0`
/// 命中终止符（先查匹配再查 NUL，与 oracle 分支序一致）。
pub fn host_strchr(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  addr : UInt,
  c : Int,
) -> HostMemReply {
  let mut i = 0
  while true {
    let b = match mem.load_i8(map, addr + i.reinterpret_as_uint()) {
      Ok(v) => v
      Err(f) => return fault_reply(f)
    }
    if (b & 0xFF) == c {
      return value_only((addr + i.reinterpret_as_uint()).to_uint64())
    }
    if b == 0 {
      return value_only(0UL)
    }
    i = i + 1
  }
  abort_unreachable()
}

///|
/// `strrchr(s, c)`（oracle `string.rs:389-406`）——记录**最后一次**命中
/// （先查匹配再查 NUL——`c == 0` 时命中终止符）。
pub fn host_strrchr(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  addr : UInt,
  c : Int,
) -> HostMemReply {
  let mut result = 0U
  let mut i = 0
  while true {
    let b = match mem.load_i8(map, addr + i.reinterpret_as_uint()) {
      Ok(v) => v
      Err(f) => return fault_reply(f)
    }
    if (b & 0xFF) == c {
      result = addr + i.reinterpret_as_uint()
    }
    if b == 0 {
      break
    }
    i = i + 1
  }
  value_only(result.to_uint64())
}

///|
/// `strstr(haystack, needle)`（oracle `string.rs:408-424`）——首次出现位置；
/// 空 needle 返回 haystack 本身。
pub fn host_strstr(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  haystack : UInt,
  needle : UInt,
) -> HostMemReply {
  let hay = match read_cstring(mem, map, haystack) {
    Ok(s) => s
    Err(f) => return fault_reply(f)
  }
  let nd = match read_cstring(mem, map, needle) {
    Ok(s) => s
    Err(f) => return fault_reply(f)
  }
  if nd.length() == 0 {
    return value_only(haystack.to_uint64())
  }
  let hl = hay.length()
  let nl = nd.length()
  let mut pos : Int? = None
  let mut i = 0
  while i + nl <= hl {
    let mut j = 0
    let mut matched = true
    while j < nl {
      if hay[i + j] != nd[j] {
        matched = false
        break
      }
      j = j + 1
    }
    if matched {
      pos = Some(i)
      break
    }
    i = i + 1
  }
  match pos {
    Some(p) => value_only((haystack + p.reinterpret_as_uint()).to_uint64())
    None => value_only(0UL)
  }
}

///|
/// `memchr(s, c, n)`（oracle `string.rs:426-442`）——**无符号字节**在
/// `[addr, addr+n)` 内首次出现的地址；未命中返 0；`n` 取原始 u64 栈字。
///
/// **登记分叉**：oracle 扫描越过内存尾时静默 break，此处受检读 trap
/// （读侧受检化同族，批一号口径）。
pub fn host_memchr(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  addr : UInt,
  c : Int,
  n : UInt64,
) -> HostMemReply {
  let mut i = 0UL
  while i < n {
    let b = match mem.load_i8(map, addr + i.to_uint()) {
      Ok(v) => v
      Err(f) => return fault_reply(f)
    }
    if (b & 0xFF) == c {
      return value_only((addr + i.to_uint()).to_uint64())
    }
    i = i + 1UL
  }
  value_only(0UL)
}

///|
/// `strpbrk(s, accept)`（oracle `string.rs:446-458`）——s 中**首个**出现在
/// accept 集的字节位置。
///
/// **字节语义（与 oracle 的登记分叉）**：oracle 经 `read_cstring` 的
/// `from_utf8_lossy` 走 **char** 语义（`s.char_indices()` + `contains(c)`），
/// 非 ASCII 输入下 `i` 是 lossy 串的字节偏移、与原内存错位（坑 8 同族，
/// 静默错值形状）。此处按 **C 字节语义**实现——ASCII 输入与 oracle 逐字节
/// 一致，非 ASCII 输入 oracle 侧缺陷登记两侧同修候选。
pub fn host_strpbrk(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  s_addr : UInt,
  accept_addr : UInt,
) -> HostMemReply {
  let s = match read_cstring(mem, map, s_addr) {
    Ok(v) => v
    Err(f) => return fault_reply(f)
  }
  let accept = match read_cstring(mem, map, accept_addr) {
    Ok(v) => v
    Err(f) => return fault_reply(f)
  }
  let n = s.length()
  let mut i = 0
  while i < n {
    if bytes_contains(accept, s[i]) {
      return value_only((s_addr + i.reinterpret_as_uint()).to_uint64())
    }
    i = i + 1
  }
  value_only(0UL)
}

///|
/// `strspn(s, accept)`（oracle `string.rs:460-474`）——s 开头连续落在
/// accept 集的字节数（字节语义同 `host_strpbrk` 注记）。
pub fn host_strspn(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  s_addr : UInt,
  accept_addr : UInt,
) -> HostMemReply {
  let s = match read_cstring(mem, map, s_addr) {
    Ok(v) => v
    Err(f) => return fault_reply(f)
  }
  let accept = match read_cstring(mem, map, accept_addr) {
    Ok(v) => v
    Err(f) => return fault_reply(f)
  }
  let n = s.length()
  let mut count = 0
  while count < n {
    if bytes_contains(accept, s[count]) {
      count = count + 1
    } else {
      break
    }
  }
  value_only(count.to_uint64())
}

///|
/// `strcspn(s, reject)`（oracle `string.rs:476-489`）——s 开头连续**不在**
/// reject 集的字节数。
pub fn host_strcspn(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  s_addr : UInt,
  reject_addr : UInt,
) -> HostMemReply {
  let s = match read_cstring(mem, map, s_addr) {
    Ok(v) => v
    Err(f) => return fault_reply(f)
  }
  let reject = match read_cstring(mem, map, reject_addr) {
    Ok(v) => v
    Err(f) => return fault_reply(f)
  }
  let n = s.length()
  let mut count = 0
  while count < n {
    if bytes_contains(reject, s[count]) {
      break
    }
    count = count + 1
  }
  value_only(count.to_uint64())
}

///|
/// 穷尽 while-true 的类型出口（MoonBit 要求函数尾类型可达；`abort()` 是
/// 副作用原语，语义上不可达——与 oracle `loop {}` 的 `!` 型对应）。
fn abort_unreachable() -> HostMemReply {
  abort("unreachable")
}
