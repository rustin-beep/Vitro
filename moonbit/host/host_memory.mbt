///| 宿主内存族：`malloc` / `calloc` / `realloc` / `free` 的语义实现。
///
/// **本层不碰值栈**（与 Rust 现版的关键结构差异）：Rust 的 handler 把"弹参数 /
/// 分配 / 压返回值 / trap"四件事混在一个函数里（`host_memory.rs:5-366`），导致
/// **内存语义无法脱离 VM 测试**。本实现把它拆开——handler 只产出
/// [`HostMemReply`]（`value?` / `note?` / `trap?` 三件结构化事实），压栈与发 trap
/// 由执行器执行。收益：内存族的行为可以纯函数式锚定（`host_memory_wbtest.mbt`
/// 全部用例不起 VM），且"同一语义在 host 与 core 两处各写一遍"的病灶（Rust
/// `host_memory` vs `VitroVM::free_memory` 双份）在结构上只剩一处。
///
/// **受检访问一律经 `memory` 包的单一入口**（勘察 §9.2 约束 #1）：本文件不出现
/// 裸字节读写；`calloc` 的置零走 `Memory::fill`（段级一次判定 + 载体原生填充），
/// `realloc` 的搬运走 `Memory::copy`（memmove 语义）——即勘察 §5.1 的
/// "无检查快路径 + 一次前置检查"。Rust 现版在这两处是**逐字节 `store_i8` 循环**
/// （`host/memory.rs:240-247`、`:331-333`），每条字节重跑一次 NULL/上界/UAF 判定。
///
/// **两条 oracle 存量缺陷（S6 建包时发现并照搬固化，2026-09-23 审阅批两侧同修）**：
/// ① `calloc` 的置零原发生在清理 freed_logs 之前（Rust `host/memory.rs:330-336`
/// 的顺序）——`allocate_raw` 从 `free_list` 复用刚驱逐的块时，其窗口未清，置零的
/// 受检写撞自己的 UAF 检测 → **误报**（触发条件：隔离区超预算，默认 256KB）。
/// 修复 = 清理提前到置零之前（一行换位），与 malloc/realloc 次序对齐；
/// ② `calloc` 尺寸链 `saturating_mul` 后 `align4` 仍会 32 位回绕（饱和值
/// 0xFFFFFFFF + 3 → 0）→ `allocate_raw(0)` 短路成功，超大尺寸不失败，反登记
/// `addr=0`/`size=-1` 垃圾区域。修复 = 对齐前 `total > MEM_SIZE` 预检走堆耗尽
/// 分支。两条的红→绿锚：`calloc_reuse_after_eviction_no_uaf` /
/// `calloc_oversize_reports_heap_exhausted`（翻转自原固化锚）。

///|
/// 宿主 handler 的**统一结构化结果**（内存族首建，S6 余量批一号起扩为
/// 全 host 族共用——`value` 同时是 `UInt64`：vm 值栈是 u64 位模式，
/// `strtol`/`strtod`/`llabs` 等要压 64 位值；0.6.0 面变更，登记 CHANGELOG）。
///
/// 三个字段对应 handler 在 Rust 侧的三种副作用，顺序无关（压栈与 trap 是两条
/// 独立通道）：
/// - `value`：要压栈的值（`free` 等无返回值时为 `None`）；
/// - `note`：教学附注文本（调用方负责去重后写入 note 通道——去重口径是
///   `OutputLog::has_note`）；
/// - `trap`：要发的 trap 文本（`Some` 时调用方按 vm 的 trap 路径处理）。
pub(all) struct HostMemReply {
  value : UInt64?
  note : String?
  trap : String?
} derive(Debug, Eq)

///|
/// 无事发生的回复（`free(NULL)` / 释放成功等）。
fn no_reply() -> HostMemReply {
  HostMemReply::{ value: None, note: None, trap: None, }
}

///|
/// 只压一个值。
fn value_only(v : UInt64) -> HostMemReply {
  HostMemReply::{ value: Some(v), note: None, trap: None, }
}

///|
/// 压 NULL 并附教学附注。
fn null_with_note(note : String) -> HostMemReply {
  HostMemReply::{ value: Some(0UL), note: Some(note), trap: None, }
}

///|
/// 压 NULL，无附注。
fn null_silent() -> HostMemReply {
  HostMemReply::{ value: Some(0UL), note: None, trap: None, }
}

///|
/// 发 trap（不压值）。
fn trap_only(text : String) -> HostMemReply {
  HostMemReply::{ value: None, note: None, trap: Some(text), }
}

///|
/// 32 位无符号饱和乘（尺寸链防溢出：勘察坑 9「`nmemb * size` 溢出致 ~32GB
/// 申请后 OOM」在 64 位中间量下不可能回绕，饱和只是把"超大尺寸"统一成
/// "必然超过 MEM_SIZE"，与 Rust 侧 `checked_mul` 在本域判定等价）。
fn sat_mul_u32(a : UInt, b : UInt) -> UInt {
  let p = a.to_uint64() * b.to_uint64()
  if p > 0xFFFFFFFFUL {
    0xFFFFFFFFU
  } else {
    p.to_uint()
  }
}

///|
/// 大写十六进制（`0x{:X}` 口径：无 `0x` 前缀、无前导零、A–F 大写）。
fn hex_upper(v : UInt) -> String {
  if v == 0U {
    return "0"
  }
  let digits = "0123456789ABCDEF"
  let mut out = ""
  let mut x = v
  while x > 0U {
    let d = (x & 15U).reinterpret_as_int()
    out = digits[d:d + 1].to_owned() + out
    x = x >> 4
  }
  out
}

///|
/// 堆耗尽的引擎附注（**返回文本而非直接写入**——输出通道归调用方）。
///
/// 数值从常量格式化（`MEM_SIZE / 1024` KB 与隔离预算 KB），不硬编码 1MB/256KB
/// ——Rust 侧曾有"文本双写常量"的漂移（R3 已收）。末尾必须带换行：note 通道的
/// 后续输出会续接最后一个元素，缺换行会让教学提示与程序输出粘成一行。
pub fn heap_exhausted_note() -> String {
  let total_kb = @bytecode.MEM_SIZE.reinterpret_as_int() / 1024
  let quar_kb = @memory.DEFAULT_QUARANTINE_BUDGET / 1024
  "[堆] 内存耗尽：malloc/calloc/realloc 返回 NULL（Vitro 堆上限 \{total_kb}KB，其中 \{quar_kb}KB 为隔离区预算）。常见原因是「只分配不释放」——请确认每条 malloc 路径都有对应的 free。\n"
}

///|
/// `malloc(0)` 的引擎附注（C 标准下实现定义，Vitro 取"返回 NULL + 提示"）。
pub fn malloc_zero_note() -> String {
  "[warning] malloc(0) 返回 NULL。在 C 标准中，malloc(0) 的行为是实现定义的，可能返回 NULL 也可能返回一个不可解引用的非空指针。"
}

///|
/// `malloc(size)` 的宿主侧实现（Rust `host_malloc` 的内存侧，`host/memory.rs:5-58`）。
///
/// **失败不 trap**：C 标准要求分配失败返回 NULL，Clang 同样返回 NULL；trap 会让
/// Vitro 偏离"检查 malloc 返回值"这一必须建立的编程习惯。故堆耗尽时压 NULL +
/// 教学附注（与决议 §5"教学 trap"措辞的差异，Rust 侧已诚实记录）。
pub fn host_malloc(
  map : @memory.MemoryMap,
  size : Int,
  alloc_line : Int,
) -> HostMemReply {
  if size == 0 {
    return null_with_note(malloc_zero_note())
  }
  if size < 0 {
    return null_silent()
  }
  let aligned = @bytecode.align4(size.reinterpret_as_uint())
  let addr = match map.allocate_raw(aligned, @bytecode.MEM_SIZE) {
    Some(a) => a
    None => return null_with_note(heap_exhausted_note())
  }
  // 清理被新分配重用的 freed_logs（**必须在写入新内存之前**，否则紧随的写入
  // 会误报 UAF——Rust `host/memory.rs:229-232` 明文）
  map.freed_logs_remove_overlapping(addr, addr + aligned)
  map.register_alloc(addr, size, alloc_line, "malloc", true)
  value_only(addr.to_uint64())
}

///|
/// `calloc(nmemb, size)` 的宿主侧实现（Rust `host_calloc`，`host/memory.rs:313-366`）。
///
/// `nmemb <= 0 || size <= 0` → 静默 NULL（Rust 同，无提示）；尺寸链用**饱和乘**
/// （勘察 §1.7 坑 9：`nmemb * size` 溢出曾致 `qsort(base,2^32,2^32,cmp)` 申请
/// ~32GB 后 OOM；Rust 侧修法是 `checked_mul`，此处取饱和乘——两者在本域
/// （`saturating_mul` 后必然 > MEM_SIZE）判定等价：都不会分配成功）。
///
/// **置零与清理的次序照搬 Rust（已知误报，见模块头）**。
pub fn host_calloc(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  nmemb : Int,
  size : Int,
  alloc_line : Int,
) -> HostMemReply {
  if size <= 0 || nmemb <= 0 {
    return null_silent()
  }
  let total = sat_mul_u32(
    size.reinterpret_as_uint(),
    nmemb.reinterpret_as_uint(),
  )
  // 尺寸链防回绕（oracle 存量缺陷②修复，2026-09-23）：饱和值 0xFFFFFFFF 在
  // `align4` 的 32 位加法下回绕成 0，`allocate_raw(0)` 按"零尺寸分配"短路成功，
  // 于是超大尺寸不失败，反登记 `addr=0`/`size=-1` 的垃圾区域（静默元数据损坏，
  // 原 Rust `host/memory.rs:320-321`）。对齐**之前**先与堆上限比较，超限直接走
  // 堆耗尽分支——与 `host/misc.rs` 坑 9 的 `checked_mul` 判定目的对齐。
  if total > @bytecode.MEM_SIZE {
    return null_with_note(heap_exhausted_note())
  }
  let aligned = @bytecode.align4(total)
  let addr = match map.allocate_raw(aligned, @bytecode.MEM_SIZE) {
    Some(a) => a
    None => return null_with_note(heap_exhausted_note())
  }
  // 清理被新分配重用的 freed_logs（**必须在置零之前**——oracle 存量缺陷①修复，
  // 2026-09-23：复用驱逐块时其窗口未清，置零的受检写会撞自己的 UAF 检测 → 误报。
  // Rust 侧原顺序是置零在前（`host/memory.rs:330-336`），本批两侧同修换位，
  // 与 malloc/realloc 的次序对齐）
  map.freed_logs_remove_overlapping(addr, addr + aligned)
  // 置零（段级一次判定 + 载体原生填充；Rust 侧是逐字节 store_i8）
  //
  // `aligned == 0` 的跳过是**防御性**保留：尺寸链已在前置 `total > MEM_SIZE`
  // 拦截（total ≥ 1 时 aligned ≥ 4），理论不可达；保留是为防未来路径变化时
  // `Memory::fill` 即便 len=0 也走 `check_access`（addr=0 落 NULL 陷阱区）。
  let mut fault : String? = None
  if aligned != 0U {
    match mem.fill(map, addr, aligned.reinterpret_as_int(), b'\x00') {
      Ok(_) => ()
      Err(f) => fault = Some(access_fault_text(f))
    }
  }
  map.register_alloc(
    addr,
    total.reinterpret_as_int(),
    alloc_line,
    "calloc",
    true,
  )
  // Rust 的 `trap()` **不中断 handler**（首错优先，`core/trap.rs:145-156`），
  // 故 trap 之后仍照常清理、登记、压地址——本实现保持同序，只把文案交给调用方。
  match fault {
    Some(t) =>
      HostMemReply::{
        value: Some(addr.to_uint64()),
        note: None,
        trap: Some(t),
      }
    None => value_only(addr.to_uint64())
  }
}

///|
/// **oracle 存量缺陷②（已修，2026-09-23）**：`calloc` 的尺寸链饱和后曾会
/// **回绕**——`saturating_mul` 把溢出钳到 `0xFFFFFFFF`，而 `align4(0xFFFFFFFF)`
/// = `(0xFFFFFFFF + 3) & 0xFFFFFFFC` 在 32 位加法的回绕下得 **0**；`allocate_raw(0)`
/// 又按"零尺寸分配"短路返回 `Some(0)`。修复（见 `host_calloc` 内预检）：
/// `total` 先与 `MEM_SIZE` 比较，超限直接走堆耗尽分支。锚
/// `calloc_oversize_reports_heap_exhausted`（翻转自原固化锚）。
///
/// `realloc(ptr, new_size)` 的宿主侧实现（Rust `host_realloc`，`host/memory.rs:158-311`）。
///
/// 三分支照搬：
/// - `new_size <= 0` 且 `ptr != 0` → **等价 free**（块进隔离区，结果为 NULL；
///   无效指针走 E3027/E3061 诊断）；
/// - `ptr == 0` → **等价 malloc**（结果为新地址或 NULL）；
/// - 否则：**恒为新块拷贝**（决议 §3，与 glibc 常见路径一致）。
///
/// **恒搬移的两个理由（决议 §3 原文）**：原实现的"堆顶原地收缩"与"优先复用旧
/// 地址"两个特例都会破坏"隔离窗口内地址不复用"的保证——收缩把 `heap_offset`
/// 回退进隔离区，原地复用让刚 free 的地址立即重新生效（UAF 检测窗口失效）。
///
/// **零填充尾部是 oracle 行为**（C 标准不要求 `realloc` 清零新增字节）：Rust
/// `host/memory.rs:244-247` 显式把 `[copy_size, aligned_new_size)` 置零，照搬以保
/// 产物等价，并在此登记为与 C 标准的偏差。
pub fn host_realloc(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  ptr : UInt,
  new_size : Int,
  alloc_line : Int,
  freed_line : Int,
  freed_step : Int,
) -> HostMemReply {
  if new_size <= 0 {
    if ptr == 0U {
      return null_silent()
    }
    // 等价 free：**结果恒为 NULL**（Rust `:163-194` 在 free 之后无条件 push(0)）。
    // oracle 此分支是**内联**释放且不查 Double-Free（`host/memory.rs:166-192`）：
    // 对已释放指针，`trap_invalid_free` 的 freed_logs 分支被 `log.addr != addr`
    // 滤掉，落兜底 E3027（真机实测 2026-09-23）。故不走 `host_free`——它的
    // Double-Free 前置会把这条路径改报 E3061，与 oracle 不符（P1 修复，
    // 红→绿锚 `realloc_zero_size_on_freed_ptr_matches_oracle`）。
    let r = match map.release(ptr, freed_line, freed_step) {
      Some(_) => no_reply()
      None => trap_only(invalid_free_message(map, ptr))
    }
    return HostMemReply::{ value: Some(0UL), note: None, trap: r.trap, }
  }
  if ptr == 0U {
    // 等价 malloc
    host_malloc(map, new_size, alloc_line)
  } else {
    let old_region = match map.region(ptr) {
      Some(r) => if r.is_freed { None } else { Some(r.size) }
      None => None
    }
    let old_size = match old_region {
      Some(s) => s
      None => return null_silent()
    }
    let aligned_new = @bytecode.align4(new_size.reinterpret_as_uint())
    let new_addr = match map.allocate_raw(aligned_new, @bytecode.MEM_SIZE) {
      Some(a) => a
      None => return null_with_note(heap_exhausted_note())
    }
    // 清理被新分配重用的 freed_logs（**在写入新内存之前**）
    map.freed_logs_remove_overlapping(new_addr, new_addr + aligned_new)
    // 搬移旧数据（截断到新大小；memmove 语义的段级拷贝）
    let copy_size = if old_size < aligned_new.reinterpret_as_int() {
      old_size
    } else {
      aligned_new.reinterpret_as_int()
    }
    let mut fault : String? = None
    match mem.copy(map, new_addr, ptr, copy_size) {
      Ok(_) => ()
      Err(f) => fault = Some(access_fault_text(f))
    }
    // 尾部置零（oracle 行为，见文档）
    let tail = aligned_new.reinterpret_as_int() - copy_size
    if tail > 0 {
      match
        mem.fill(map, new_addr + copy_size.reinterpret_as_uint(), tail, b'\x00') {
        Ok(_) => ()
        Err(f) =>
          match fault {
            Some(_) => ()
            None => fault = Some(access_fault_text(f))
          }
      }
    }
    // 旧块进隔离区（登记以对齐后的旧大小为准）
    match map.release(ptr, freed_line, freed_step) {
      Some(_) => ()
      None => ()
    }
    // 若新块恰复用旧地址（heap_offset 回退等），清理刚添加的 freed_log
    map.freed_logs_remove_overlapping(new_addr, new_addr + aligned_new)
    map.register_alloc(new_addr, new_size, alloc_line, "realloc", false)
    match fault {
      Some(t) =>
        HostMemReply::{
          value: Some(new_addr.to_uint64()),
          note: None,
          trap: Some(t),
        }
      None => value_only(new_addr.to_uint64())
    }
  }
}

///|
/// `free(addr)` 的宿主侧实现（Rust `host_free`，`host/memory.rs:60-103`）。
///
/// 判定顺序照搬：`NULL` 静默 → Double-Free（E3061）→ 释放 → 无效 free（E3027）。
/// 释放走 `memory` 包的**单一出口** `MemoryMap::release`（置 `is_freed` + 登记
/// freed_logs + 进 FIFO 隔离区，三步原子）——Rust 侧同一语义在 `host_free` /
/// `realloc(p,0)` / `VitroVM::free_memory` 三处各写一遍。
///
/// **一条实测出来的"非承重"结论（J9 等价变异留痕）**：把 Double-Free 判定从
/// "释放之前"挪到"释放失败之后"（即删掉前置分支、在 `release` 返回 `None` 时
/// 再查 `freed_logs_get`），**全部 27 条锚仍绿**——因为 `release` 对已释放块
/// 本就无副作用地返回 `None`，两序可观测行为相同。⇒ 该顺序**不是语义承重**，
/// 保留前置分支的理由是"诊断路径更短 + 与 Rust 同形"，而非正确性。
/// （判据：本轮 J9 第 3 路首选注入即此形态，实测零红，遂改用
/// "禁用 `free(NULL)` 守卫"与"折叠无效 free 三分支"两路取红。）
pub fn host_free(
  map : @memory.MemoryMap,
  addr : UInt,
  freed_line : Int,
  freed_step : Int,
) -> HostMemReply {
  if addr == 0U {
    // C 标准：free(NULL) 是安全的空操作
    return no_reply()
  }
  match map.freed_logs_get(addr) {
    Some(info) => return trap_only(double_free_message(info))
    None => ()
  }
  match map.release(addr, freed_line, freed_step) {
    Some(_) => no_reply()
    None => trap_only(invalid_free_message(map, addr))
  }
}

///|
/// Double-Free 教学文案（E3061，逐字照搬 Rust `host/memory.rs:67`）。
pub fn double_free_message(info : @memory.FreedRegionInfo) -> String {
  "🔁 Double-Free (E3061)：你正在 free 一块已经在第 \{info.freed_line} 行被释放过的内存（由第 \{info.alloc_line} 行的 malloc/realloc 分配）。\n\n💡 原因：同一块内存被释放了两次，这通常是因为 free(p) 后没有将 p 置为 NULL，或者两个指针指向同一块内存且都被释放了。\n✅ 解决方法：每次 free(p) 后立刻写 p = NULL;。对 NULL 指针重复 free 是安全的。"
}

///|
/// 无效 free 教学文案（E3027 / E3061 变体），三分支照搬 Rust
/// `trap_invalid_free`（`host/memory.rs:106-137`）：
/// ① 落在**存活**块内部的地址（E3027「不是起始地址」）；
/// ② 落在**已释放**块内部的地址（E3061 变体）；
/// ③ 不指向任何分配块起始地址（E3027 兜底：栈地址 / 全局地址 / 垃圾值）。
pub fn invalid_free_message(map : @memory.MemoryMap, addr : UInt) -> String {
  match map.find_live_region_containing(addr) {
    Some(block) => {
      let base = block.0
      let r = block.1
      "🚫 无效 free (E3027)：free 的地址 0x\{hex_upper(addr)} 是第 \{r.alloc_line} 行 malloc 块（起始 0x\{hex_upper(base)}，\{r.size} 字节）的内部地址，不是起始地址。\n\n💡 原因：free 只能释放 malloc/calloc/realloc 返回的原始指针。\n✅ 解决方法：保存分配返回的原始指针用于 free；需要偏移访问时使用单独的指针变量，不要 free 偏移后的指针。"
    }
    None =>
      match map.freed_logs_find_overlapping(addr, 1U) {
        Some(log) =>
          if log.addr != addr {
            "🔁 无效 free (E3061)：地址 0x\{hex_upper(addr)} 位于第 \{log.freed_line} 行已释放块（起始 0x\{hex_upper(log.addr)}）的内部。free 只能释放 malloc 返回的原始指针。"
          } else {
            // 已释放块的**精确起点**：host_free 走不进这里（Double-Free 前置
            // 拦下）；但 `realloc(p, 0)` 走 release 单出口（无前置），oracle 的
            // `trap_invalid_free` 恰把精确命中滤掉 → 兜底 E3027（P1 修复路径）
            unknown_free_message(addr)
          }
        None => unknown_free_message(addr)
      }
  }
}

///|
/// E3027 兜底文案（不指向任何分配块起始地址）。
fn unknown_free_message(addr : UInt) -> String {
  "🚫 无效 free (E3027)：free 的地址 0x\{hex_upper(addr)} 不指向任何 malloc/calloc/realloc 分配的内存块起始地址（可能是栈地址、全局变量地址或未初始化指针的垃圾值）。\n\n💡 原因：只有 malloc 系列函数返回的指针才能被 free。\n✅ 解决方法：检查该指针是否来自 malloc 分配，且未经过指针算术运算。"
}

///|
/// 受检访问失败（[`@memory.MemFault`]）的 trap 文本。
///
/// **与 oracle 完整文案（`core/memory.rs:199-205` `format_uaf_message`）的
/// 已登记差距**，按"host 能否自渲染"分两档：
/// - **已渲染**：动作词（`写入`/`读取`——`AccessKind` 就在 `MemFault` 载荷里，
///   2026-09-23 审阅批 P2 补上，此前被 `_` 丢弃写成中性「访问」）与
///   `alloc_line` / `freed_line` / `freed_step` 行号步号段；
/// - **vm 接线义务**：时间轴行 `⏱️ 分配 → 释放（第 N 步）→ 继续访问（第 M 步）`
///   里的**当前步 M** 是 access 时刻的 VM 状态（oracle 取 `step_count`），host
///   拿不到，故整行不在此渲染——vm 消费 `HostMemReply.trap` 接线时须按
///   oracle 逐字口径补齐。同理 `NullDeref` 的写侧变体（「向 NULL 指针区域写入」，
///   `check_mem_access` 的 `is_write` 分支）与 `OutOfBounds` 的符号表增强文案
///   （`trap.rs:6-61` 找最近数组名）也超出 host 能力，登记在案。
///
/// 本函数只用于 host 自身发起的受检访问（`calloc` 置零 / `realloc` 搬运）；
/// calloc 误报缺陷修复（先清理 freed_logs 再置零）后，`UseAfterFree` 分支在
/// host 内部为防御性保留（新分配块的窗口已清，不可达）。
fn access_fault_text(fault : @memory.MemFault) -> String {
  match fault {
    @memory.MemFault::NullDeref(addr, _) =>
      "访问了 NULL 指针区域（地址 0x\{hex_upper(addr)}）。NULL 指针不能解引用。请确认指针已被正确初始化。"
    @memory.MemFault::OutOfBounds(addr, _) =>
      "内存访问越界（地址 0x\{hex_upper(addr)}）。请检查数组下标或指针运算是否超出分配范围。"
    @memory.MemFault::UseAfterFree(info, kind) => {
      let action = match kind {
        @memory.AccessKind::Read => "读取"
        @memory.AccessKind::Write => "写入"
      }
      "💥 Use-After-Free (E3060)：你正在向一块已经在第 \{info.freed_line} 行（第 \{info.freed_step} 步）被 free 的内存\{action}（由第 \{info.alloc_line} 行的 malloc/realloc 分配）。\n\n💡 原因：指针在 free 后没有置为 NULL，或者存在别名指针（另一个指针也指向同一块内存）。\n✅ 解决方法：free(p) 后立即写 p = NULL;，并确保不再通过其他指针访问这块内存。"
    }
  }
}
