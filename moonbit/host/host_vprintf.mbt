///|
/// #10 P1 批（2026-10-10）：`difftime` + vprintf 族（vprintf/vfprintf/
/// vsnprintf）。v 族的参数**不来自 CallHost 参数组**，而来自 `va_list`
/// 游标——`va_start` 展开所得、指向调用者栈帧变参区，布局与
/// `host_va_arg` 的 `current + size` 同构（参数连续、步进 = 类型宽度、
/// 无 padding）。预取层 `va_args_from_cursor` 按 fmt 逐 spec 宽度从游标
/// 读内存装 `Array[UInt64]`，经既有格式化管线输出——**照搬物
/// `host_format.mbt` 零改动**（只复用 `parse_format_spec`）。
///
/// 与 printf 的行为差异登记：printf 有「格式要求的参数多于实际提供」
/// 守卫 trap（pipeline guard），v 族的等价形态 = 游标读越界走 MemFault
/// ——va_list 本身不带参数计数，C 语义同样无法静态守卫。
///
/// 存根差异登记（stdio.h）：v 族声明的形参写作 `char*` 而非 `va_list`
/// ——本仓 `va_list ≡ char*`（stdarg.h 存根 typedef），类型同构且免去
/// 跨头 typedef 的 include 顺序依赖；与真 C 头的 `va_list` 写法等价。

///|
/// `difftime(time1, time0)`——纯 bits 运算（time_t = long long），
/// `(double)(time1 − time0)`。
pub fn host_difftime(a_bits : UInt64, b_bits : UInt64) -> UInt64 {
  let a = a_bits.reinterpret_as_int64().to_double()
  let b = b_bits.reinterpret_as_int64().to_double()
  (a - b).reinterpret_as_uint64()
}

///|
/// 逐 spec 的变参字节宽度（与 vm 参数栈布局 / `host_va_arg` 步进一致）：
/// d/i/o/u/x/X → int（4，`ll` 时 8）；c → int 提升（4）；
/// f/e/E/g/G → double（8）；s/p → 指针（4）。
fn va_spec_width(spec : Int, is_ll : Bool) -> Int? {
  match spec {
    100 | 105 | 111 | 117 | 120 | 88 => Some(if is_ll { 8 } else { 4 })
    // d i o u x X
    99 => Some(4)
    // c
    102 | 101 | 69 | 103 | 71 => Some(8)
    // f e E g G
    115 | 112 => Some(4)
    // s p
    _ => None
  }
}

///|
/// 从游标读一个 w 字节小端参数（w ∈ {4, 8}）。
fn va_read_word(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  addr : UInt,
  w : Int,
) -> Result[UInt64, @memory.MemFault] {
  if w == 8 {
    mem.load_u64(map, addr)
  } else {
    match mem.load_u32(map, addr) {
      Ok(v) => Ok(v.to_uint64())
      Err(e) => Err(e)
    }
  }
}

///|
/// 预取层：按 fmt 的逐 spec 宽度从 va_list 游标读参数装数组。
/// `*` 宽度/精度按出现序各先吃一个 int（与 formatter 消费序一致：
/// width* → precision* → 值）；未知转换符不取参（格式错误由管线自报）。
fn va_args_from_cursor(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  fmt : Array[Int],
  cursor : UInt,
) -> Result[Array[UInt64], @memory.MemFault] {
  let args : Array[UInt64] = []
  let mut cur = cursor
  let scan = FmtScan::{ s: fmt, i: 0, }
  while true {
    match scan.peek() {
      Some(ch) => {
        scan.advance()
        if ch == 37 {
          match scan.peek() {
            Some(n) =>
              if n == 37 {
                scan.advance() // %% 不取参
              } else {
                match parse_format_spec(scan) {
                  Some((spec, is_ll, _, _, _, star_w, star_p)) => {
                    if star_w {
                      match va_read_word(mem, map, cur, 4) {
                        Ok(v) => args.push(v)
                        Err(e) => return Err(e)
                      }
                      cur = cur + 4U
                    }
                    if star_p {
                      match va_read_word(mem, map, cur, 4) {
                        Ok(v) => args.push(v)
                        Err(e) => return Err(e)
                      }
                      cur = cur + 4U
                    }
                    match va_spec_width(spec, is_ll) {
                      Some(w) =>
                        match va_read_word(mem, map, cur, w) {
                          Ok(v) => args.push(v)
                          Err(e) => return Err(e)
                        }
                      None => ()
                    }
                    match va_spec_width(spec, is_ll) {
                      Some(w) => cur = cur + w.reinterpret_as_uint()
                      None => ()
                    }
                  }
                  None => break // 尾部裸 %——格式错误由管线自报
                }
              }
            None => break
          }
        }
      }
      None => break
    }
  }
  Ok(args)
}

///|
/// v 族公共管道：读 fmt → 游标预取 → 预算闸 → 格式化（无参数计数守卫
/// ——va_list 无计数可守，读越界走 MemFault，见文件头注差异登记）。
fn vprintf_pipeline(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  fmt_addr : UInt,
  ap_cursor : UInt,
) -> Result[Bytes, HostMemReply] {
  let fmt_bytes = match read_cstring(mem, map, fmt_addr) {
    Ok(b) => b
    Err(f) => return Err(fault_reply(f))
  }
  let fmt = lossy_codes(fmt_bytes)
  let args = match va_args_from_cursor(mem, map, fmt, ap_cursor) {
    Ok(a) => a
    Err(f) => return Err(fault_reply(f))
  }
  match validate_format_field_budget(fmt) {
    Some(msg) => return Err(trap_only(msg))
    None => ()
  }
  match format_printf_string(mem, map, fmt, args) {
    Ok(out) => Ok(out)
    Err(f) => Err(fault_reply(f))
  }
}

///|
/// `vprintf(fmt, ap)`（stdout 通道）——返回输出字节数（int，N3 口径）。
pub fn host_vprintf_n(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  log : OutputLog,
  fmt_addr : UInt,
  ap_cursor : UInt,
) -> HostMemReply {
  match vprintf_pipeline(map, mem, fmt_addr, ap_cursor) {
    Ok(out) => {
      log.push_stdout(out)
      value_only(out.length().to_uint64())
    }
    Err(r) => r
  }
}

///|
/// `vfprintf(stream, fmt, ap)`——三通道分流同 `host_fprintf_n`
///（stderr / stdout / 自定义 FILE* 落盘 VFS）。
pub fn host_vfprintf_n(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  log : OutputLog,
  vfs : VirtualFileSystem,
  stream : UInt64,
  fmt_addr : UInt,
  ap_cursor : UInt,
) -> HostMemReply {
  match vprintf_pipeline(map, mem, fmt_addr, ap_cursor) {
    Ok(out) => {
      if stream == 2UL {
        log.push_stderr(out)
      } else if stream == 1UL {
        log.push_stdout(out)
      } else {
        let fd = read_fd_raise(mem, map, stream.to_uint()) catch {
          AccessFault::Fault(f~) => return fault_reply(f)
        }
        let n = vfs.write_direct(map, mem, fd, out)
        if n < 0 {
          return trap_only(
            "vfprintf: stream 指向未打开的文件或文件不可写（FILE\\* 读取或写入失败）。",
          )
        }
      }
      value_only(out.length().to_uint64())
    }
    Err(r) => r
  }
}

///|
/// `vsnprintf(buf, size, fmt, ap)`——截断到 `size-1` + NUL、返回**完整**
/// 格式化长度（C 语义），同 `host_snprintf`；`size <= 0` 不写。
pub fn host_vsnprintf(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  buf_addr : UInt,
  size : Int,
  fmt_addr : UInt,
  ap_cursor : UInt,
) -> HostMemReply {
  let bytes = match vprintf_pipeline(map, mem, fmt_addr, ap_cursor) {
    Ok(o) => o
    Err(r) => return r
  }
  if size > 0 {
    let room = size - 1
    let n = if bytes.length() < room { bytes.length() } else { room }
    let head : Array[Byte] = []
    let mut i = 0
    while i < n {
      head.push(bytes[i])
      i = i + 1
    }
    if n > 0 {
      write_bytes_raise(mem, map, buf_addr, Bytes::from_array(head)) catch {
        AccessFault::Fault(f~) => return fault_reply(f)
      }
    }
    store_i8_raise(mem, map, buf_addr + n.reinterpret_as_uint(), 0) catch {
      AccessFault::Fault(f~) => return fault_reply(f)
    }
  }
  value_only(bytes.length().to_uint64())
}
