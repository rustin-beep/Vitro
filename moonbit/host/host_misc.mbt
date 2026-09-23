///| 杂项族 9 个 handler（Rust `host/misc.rs` + `host_funcs.rs` 的
/// VM 无耦合子集，勘察 §1.7 族 I）。
///
/// **本文件刻意不含**（VM 耦合，vm 片接线）：`exit`/`abort`/
/// `assert_fail`（`set_finished` 是 VM 状态迁移）、`qsort`/`bsearch`
/// （`call_user_function` 宿主回调哨兵）、`STEP`/`OUTPUT`（引擎内建）、
/// `set/clear_array_guard`（`pending_array_construction` + 栈深）。
///
/// 确定性口径：`time`/`clock` 在 `deterministic` 下恒 0（oracle
/// `misc.rs:521-543`——判分确定性 Phase 1 最小形态）；非确定性时钟由
/// vm 接线侧传入（host 侧不触系统时间，测试可锚定）。

///|
/// LCG 随机态（oracle `session.runtime.rand_seed` 的宿主侧承载——
/// vm 持有并随快照往返）。
///
/// 算法照搬 `misc.rs:4-14`：`next = seed * 1103515245 + 12345`（u32 回绕，
/// MoonBit `UInt` 四则静默回绕，F1）、取 `next & 0x7fff`。**初值由 vm
/// 接线时对齐 oracle `RuntimeState` 缺省（vm 片义务）**。
pub(all) struct RandState {
  mut seed : UInt
} derive(Debug, Eq)

///|
/// 以指定种子构造（vm 接线用缺省种子调用）。
pub fn RandState::new(seed : UInt) -> RandState {
  RandState::{ seed, }
}

///|
/// `rand()`——推进种子并返回 `next & 0x7fff`。
pub fn host_rand(state : RandState) -> Int {
  let next = state.seed * 1103515245U + 12345U
  state.seed = next
  (next & 0x7FFFU).reinterpret_as_int()
}

///|
/// `srand(seed)`——oracle 弹参后 `as u32` 截断，接线侧先截断再传入。
pub fn host_srand(state : RandState, seed : UInt) -> Unit {
  state.seed = seed
}

///|
/// `time(tloc)`——deterministic 恒 0；否则 `now_millis / 1000`
///（oracle 只压秒值，**不写 `*tloc`**——`misc.rs:522-530` 的 `_tloc` 未用）。
pub fn host_time(deterministic : Bool, now_millis : UInt64) -> UInt64 {
  if deterministic {
    0UL
  } else {
    now_millis / 1000UL
  }
}

///|
/// `clock()`——deterministic 恒 0；否则微秒近似（`now_millis * 1000`）。
pub fn host_clock(deterministic : Bool, now_millis : UInt64) -> UInt64 {
  if deterministic {
    0UL
  } else {
    now_millis * 1000UL
  }
}

///|
/// C23 `unreachable()`（oracle `misc.rs:594-599`）——执行到即教学 trap；
/// 返回 trap 文本（vm 接 `HostMemReply.trap` 同通道）。
pub fn host_unreachable() -> String {
  "执行了标注为不可达的代码（unreachable）。请检查分支条件是否覆盖了这条路径——这不是防御式编程的兜底，而是逻辑错误的信号。"
}

///|
/// `va_start(ap, last)`（oracle `misc.rs:566-574`）——`ap` 指向最后一个
/// 命名参数之后（`last_addr + last_size`，i32 回绕加法）。
///
/// 参数语义（宏展开形态，oracle 弹参序 = `ap_addr`/`last_addr`/`last_size`
/// 三连）：`__vitro_va_start(&ap, last_named_var)` 由 codegen 按布局展开。
pub fn host_va_start(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  ap_addr : UInt,
  last_addr : Int,
  last_size : Int,
) -> HostMemReply {
  let va_base = last_addr + last_size
  match mem.store_u32(map, ap_addr, va_base.reinterpret_as_uint()) {
    Ok(_) => no_reply()
    Err(f) => fault_reply(f)
  }
}

///|
/// `va_arg(ap, size)`（oracle `misc.rs:576-585`）——读当前游标、前进
/// `size`、压**旧游标**（返回 `void*` 指向当前变参的地址）。
pub fn host_va_arg(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  ap_addr : UInt,
  size : Int,
) -> HostMemReply {
  let current = match mem.load_u32(map, ap_addr) {
    Ok(v) => v.reinterpret_as_int()
    Err(f) => return fault_reply(f)
  }
  match mem.store_u32(map, ap_addr, (current + size).reinterpret_as_uint()) {
    Ok(_) => value_only(current.to_int64().reinterpret_as_uint64())
    Err(f) => fault_reply(f)
  }
}

///|
/// `va_end(ap)`（oracle `misc.rs:587-590`）——无操作（接口完备性保留）。
pub fn host_va_end(ap_addr : UInt) -> HostMemReply {
  let _ = ap_addr
  no_reply()
}

///|
/// `va_copy(dst, src)`（oracle `misc.rs:603-609`）——复制游标值
///（本实现中 va_list 即 `char*` 游标）。
pub fn host_va_copy(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  dst_addr : UInt,
  src_addr : UInt,
) -> HostMemReply {
  let value = match mem.load_u32(map, src_addr) {
    Ok(v) => v
    Err(f) => return fault_reply(f)
  }
  match mem.store_u32(map, dst_addr, value) {
    Ok(_) => no_reply()
    Err(f) => fault_reply(f)
  }
}
