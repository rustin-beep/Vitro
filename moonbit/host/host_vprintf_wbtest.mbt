///|
/// #338 批三（2026-10-27）：vprintf 族（vprintf/vfprintf/vsnprintf）白盒
/// 锚点——此前整文件 0/131 零单测域执行（行为只经 vm 对拍域间接走）。
///
/// 断言值锚 = 同参 printf 既有锚（`host_io_wbtest::printf_pipeline_mixed_specs`
/// 的 oracle 实测值）+ C 语义真值：v 族的输出管线与 printf 共享
/// `format_printf_string`，差异面只在 **va_list 游标预取层**
/// （`va_args_from_cursor`）——按 fmt 逐 spec 宽度步进（d/i/o/u/x/X→4、
/// `ll`→8、f/e/E/g/G→8、c→4 提升、s/p→4；`*` 宽度/精度各先吃一个 int，
/// 消费序 width* → precision* → 值）。本文件的主职责 = 锁死步进与消费序
/// （步进错位即错值，红锚直读）。

///|
/// 小端装填（与 vm 参数栈布局 / `va_read_word` 同构）：取 v 低 w 字节。
fn va_le(v : UInt64, w : Int32) -> Array[Byte] {
  let a : Array[Byte] = []
  let mut i = 0
  while i < w {
    a.push(((v >> (i * 8)) & 0xFFUL).to_byte())
    i = i + 1
  }
  a
}

///|
/// 变参区拼接（连续无 padding——与调用者栈帧变参区布局同构）。
fn va_pack(parts : Array[Array[Byte]]) -> Bytes {
  let a : Array[Byte] = []
  for p in parts {
    for b in p {
      a.push(b)
    }
  }
  Bytes::from_array(a)
}

///|
/// 便捷：fmt 落 0x6000、变参区落 0x7000，跑 stdout 通道。
fn vprintf_run(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  fmt : String,
  va : Bytes,
) -> (OutputLog, HostMemReply) raise {
  let fmt_addr = 0x6000U
  put_bytes(mem, map, fmt_addr, @utf8.encode(fmt), true)
  let ap = 0x7000U
  put_bytes(mem, map, ap, va, false)
  let log = OutputLog::new()
  let r = host_vprintf_n(map, mem, log, fmt_addr, ap)
  (log, r)
}

///|
test "vprintf_mixed_specs_va_cursor" {
  let (map, mem) = fresh()
  put_cstr(mem, map, 0x6800U, "hi")
  let (log, r) = vprintf_run(
    map,
    mem,
    "%d|%s|%c|%x|%5.2f",
    va_pack([
      va_le((42).to_uint64(), 4),
      va_le(0x6800U.to_uint64(), 4),
      va_le((65).to_uint64(), 4),
      va_le((255).to_uint64(), 4),
      va_le(3.14.reinterpret_as_uint64(), 8),
    ]),
  )
  assert_eq(r.trap, None)
  // 返回值 = 输出字节数（与 printf N3 口径一致）
  let out = log.join(OutputKind::Stdout)
  assert_eq(r.value, Some(out.length().to_uint64()))
  assert_eq(out, b"42|hi|A|ff| 3.14")
}

///|
test "vprintf_ll_width_step_alignment" {
  let (map, mem) = fresh()
  // %lld 吃 8 字节；若步进错成 4，后续 %d 读到高半字 0 → 错值直读红锚
  let (log, r) = vprintf_run(
    map,
    mem,
    "%lld|%d",
    va_pack([
      va_le((-1).to_uint64(), 8), // -1 的 64 位补码（符号扩展 = 全 1）
      va_le((7).to_uint64(), 4),
    ]),
  )
  assert_eq(r.trap, None)
  assert_eq(log.join(OutputKind::Stdout), b"-1|7")
}

///|
test "vprintf_star_slots_consumption_order" {
  let (map, mem) = fresh()
  // 消费序锚：width* → precision* → 值（与 formatter 消费序一致）
  let (log, _) = vprintf_run(
    map,
    mem,
    "%*d",
    va_pack([va_le((6).to_uint64(), 4), va_le((42).to_uint64(), 4)]),
  )
  assert_eq(log.join(OutputKind::Stdout), b"    42")
  let (log2, _) = vprintf_run(
    map,
    mem,
    "%.*d",
    va_pack([va_le((5).to_uint64(), 4), va_le((42).to_uint64(), 4)]),
  )
  assert_eq(log2.join(OutputKind::Stdout), b"00042")
  let (log3, _) = vprintf_run(
    map,
    mem,
    "%*.*d",
    va_pack([
      va_le((7).to_uint64(), 4),
      va_le((3).to_uint64(), 4),
      va_le((42).to_uint64(), 4),
    ]),
  )
  assert_eq(log3.join(OutputKind::Stdout), b"    042")
}

///|
test "vprintf_percent_literal_no_arg_advance" {
  let (map, mem) = fresh()
  // %% 不取参：两 %d 各读各自槽位；若 %% 误取参，第二 %d 游标偏移错值
  let (log, r) = vprintf_run(
    map,
    mem,
    "%d|%%|%d",
    va_pack([va_le((1).to_uint64(), 4), va_le((2).to_uint64(), 4)]),
  )
  assert_eq(r.trap, None)
  assert_eq(log.join(OutputKind::Stdout), b"1|%|2")
}

///|
test "vprintf_cursor_fault_paths" {
  let (map, mem) = fresh()
  // 游标落 NULL 陷阱区 → MemFault（v 族无参数计数守卫，越界即 fault——
  // 文件头登记的与 printf 守卫的行为差异，此处锁差异面本身）
  let fmt_addr = 0x6000U
  put_bytes(mem, map, fmt_addr, @utf8.encode("%d"), true)
  let r = host_vprintf_n(map, mem, OutputLog::new(), fmt_addr, 0x100U)
  assert_true(r.value is None, msg="NULL 区游标不得返回值")
  assert_true(r.trap is Some(_), msg="NULL 区游标必须 fault")
  // 游标 +4 越 1MB 上界 → 同 fault 面
  let r2 = host_vprintf_n(map, mem, OutputLog::new(), fmt_addr, 0xFFFFFFFCU)
  assert_true(r2.trap is Some(_), msg="上界越界游标必须 fault")
}

///|
test "vfprintf_stream_channel_split" {
  let (map, mem) = fresh()
  let fmt_addr = 0x6000U
  put_bytes(mem, map, fmt_addr, @utf8.encode("%d"), true)
  let ap = 0x7000U
  put_bytes(mem, map, ap, va_pack([va_le((7).to_uint64(), 4)]), false)
  // stream=1 → stdout
  let log1 = OutputLog::new()
  let r1 = host_vfprintf_n(
    map,
    mem,
    log1,
    VirtualFileSystem::new(),
    1UL,
    fmt_addr,
    ap,
  )
  assert_eq(r1.trap, None)
  assert_eq(log1.join(OutputKind::Stdout), b"7")
  assert_true(
    log1.join(OutputKind::Stderr).length() == 0,
    msg="stdout 流不得写 stderr 通道",
  )
  // stream=2 → stderr
  let log2 = OutputLog::new()
  let r2 = host_vfprintf_n(
    map,
    mem,
    log2,
    VirtualFileSystem::new(),
    2UL,
    fmt_addr,
    ap,
  )
  assert_eq(r2.trap, None)
  assert_eq(log2.join(OutputKind::Stderr), b"7")
}

///|
test "vsnprintf_truncation_c_semantics" {
  let (map, mem) = fresh()
  let fmt_addr = 0x6000U
  put_bytes(mem, map, fmt_addr, @utf8.encode("%d"), true)
  let ap = 0x7000U
  put_bytes(mem, map, ap, va_pack([va_le((42517).to_uint64(), 4)]), false)
  // size=4：buf 只装 size-1=3 字符 + NUL，返回**完整**长度 5（C 语义）
  let buf = 0x8000U
  let r = host_vsnprintf(map, mem, buf, 4, fmt_addr, ap)
  assert_eq(r.trap, None)
  assert_eq(
    r.value,
    Some((5).to_uint64()),
    msg="返回完整格式化长度而非截断长度",
  )
  let back = read_cstring(mem, map, buf)
  assert_eq(back, Ok(@utf8.encode("425")), msg="截断到 size-1 + NUL")
}

///|
test "vsnprintf_size_zero_no_write" {
  let (map, mem) = fresh()
  let fmt_addr = 0x6000U
  put_bytes(mem, map, fmt_addr, @utf8.encode("%d"), true)
  let ap = 0x7000U
  put_bytes(mem, map, ap, va_pack([va_le((42).to_uint64(), 4)]), false)
  // 预填哨兵：size<=0 不写，buf 原样
  let buf = 0x8000U
  put_bytes(mem, map, buf, b"\xaa\xaa\xaa\xaa", false)
  let r = host_vsnprintf(map, mem, buf, 0, fmt_addr, ap)
  assert_eq(r.trap, None)
  assert_eq(r.value, Some((2).to_uint64()), msg="size=0 仍返回完整长度")
  assert_eq(mem.load_u32(map, buf), Ok(0xAAAAAAAAU), msg="size=0 不得写 buf")
}
