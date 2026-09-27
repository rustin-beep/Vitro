// G-3 raise 桥（总计划 §10.5，2026-09-27）：host 侧受检访问的 raise 化
// ——「Err(f) => [return] fault_reply」4 行短路样板收口为 1 行调用 +
// handler 顶层 catch（cond.mbt:29-38 桥接形态的成品先例）。
//
// **落点裁定**：桥与 catch 均落 host 包（handler 内 try/catch 消化，
// handler 签名不变 ⇒ vm 的 CallHost 分发面零扰动；memory 公共 Result 面
// 不动 ⇒ 快照/其它消费者零扰动）。§10.5 原文「memory 侧补 *_raise 变体」
// 按消费侧收口执行——raise 形态只有 host 一个消费者，memory 面不扩张。
//
// MemFault 是 enum 不可直接 raise（MoonBit raise 类型须 suberror）——
// AccessFault 单变体包装，catch 处解包转 fault_reply，语义零变化。

///|
priv suberror AccessFault {
  Fault(f~ : @memory.MemFault)
}

///|
/// read_cstring 的 raise 形态。
fn read_cstring_raise(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  addr : UInt,
) -> Bytes raise AccessFault {
  match read_cstring(mem, map, addr) {
    Ok(s) => s
    Err(f) => raise AccessFault::Fault(f~)
  }
}

///|
/// Memory::write_bytes 的 raise 形态。
fn write_bytes_raise(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  addr : UInt,
  bytes : Bytes,
) -> Unit raise AccessFault {
  match mem.write_bytes(map, addr, bytes) {
    Ok(_) => ()
    Err(f) => raise AccessFault::Fault(f~)
  }
}

///|
/// Memory::store_i8 的 raise 形态。
fn store_i8_raise(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  addr : UInt,
  value : Int,
) -> Unit raise AccessFault {
  match mem.store_i8(map, addr, value) {
    Ok(_) => ()
    Err(f) => raise AccessFault::Fault(f~)
  }
}

///|
/// Memory::store_u32 的 raise 形态。
fn store_u32_raise(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  addr : UInt,
  value : UInt,
) -> Unit raise AccessFault {
  match mem.store_u32(map, addr, value) {
    Ok(_) => ()
    Err(f) => raise AccessFault::Fault(f~)
  }
}

///|
/// Memory::load_i8 的 raise 形态。
fn load_i8_raise(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  addr : UInt,
) -> Int raise AccessFault {
  match mem.load_i8(map, addr) {
    Ok(v) => v
    Err(f) => raise AccessFault::Fault(f~)
  }
}

///|
/// read_fd（哨兵流 + load_u32）的 raise 形态。
fn read_fd_raise(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  stream : UInt,
) -> UInt raise AccessFault {
  match read_fd(mem, map, stream) {
    Ok(v) => v
    Err(f) => raise AccessFault::Fault(f~)
  }
}

///|
/// Memory::copy 的 raise 形态。
fn copy_raise(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  dst : UInt,
  src : UInt,
  len : Int,
) -> Unit raise AccessFault {
  match mem.copy(map, dst, src, len) {
    Ok(_) => ()
    Err(f) => raise AccessFault::Fault(f~)
  }
}

///|
/// Memory::load_u32 的 raise 形态。
fn load_u32_raise(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  addr : UInt,
) -> UInt raise AccessFault {
  match mem.load_u32(map, addr) {
    Ok(v) => v
    Err(f) => raise AccessFault::Fault(f~)
  }
}

///|
/// Memory::fill 的 raise 形态。
fn fill_raise(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  addr : UInt,
  len : Int,
  byte : Byte,
) -> Unit raise AccessFault {
  match mem.fill(map, addr, len, byte) {
    Ok(_) => ()
    Err(f) => raise AccessFault::Fault(f~)
  }
}
