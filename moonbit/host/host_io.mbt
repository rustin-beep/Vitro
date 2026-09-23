///| printf/scanf/字符 IO 族 10 个 handler（Rust `host/io.rs` 照搬，勘察
/// §1.7 族 C）。
///
/// **输入状态机 [`InputState`]**：oracle `RuntimeState` 的输入域（`input_lines`
/// / `input_index` / `input_char_offset` / `stdin_eof` 粘滞 / `ungetc_char` /
/// `input_mode`）整块搬来——vm 持有、随快照往返（`RuntimeSnapshot` 的对应
/// 字段）。Batch/Interactive 双模式：Batch 输入耗尽 → 返回 EOF(-1) 并粘滞；
/// Interactive → [`InputOutcome::Waiting`]（vm 置 `waiting_input` + ip 回退
/// + 参数回推，`StepResult::WaitingInput` 语义）。
///
/// **scanf 流式游标（V-P1-13 照搬）**：从 `(index, char_offset)` 起拼虚拟
/// 字节流（行间补 `\n`，映射表记补位），按实际消费量推进游标——"每行整行
/// 消费"的旧缺陷不复刻。
///
/// **栈深守卫的族内不一致（坑 17，照搬不修）**：printf/fprintf/scanf 有
/// 参数计数守卫（教学文案 trap）；**sprintf/snprintf/sscanf 没有**——参数
/// 不足时落到 format 引擎的"实参耗尽即原样输出"路径（`%d` 字面透传）。
///
/// **登记分叉**：fmt/`%s` 实参/`%c` 的读侧受检化（oracle 裸读）；sscanf
/// 的源串按字节扫描（oracle 经 lossy char——非 ASCII 的 `%c` 落点与空白
/// 判定不同，A-10 族）；scanf `%s` 的栈缓冲校验保留（V-P1-6）。

///|
/// 输入函数的三种结果：压栈值 / 等待输入（Interactive 模式输入耗尽）/ trap。
pub(all) enum InputOutcome {
  Value(UInt64)
  Waiting
  Trap(String)
} derive(Debug, Eq)

///|
/// 会话输入态（oracle `RuntimeState` 输入域 + 模式）。
pub(all) struct InputState {
  /// 输入行（oracle `input_lines : Vec<String>`——此处按字节承载，语义同
  /// 其 `as_bytes()` 消费面）。
  lines : Array[Bytes]
  mut index : Int
  mut char_offset : Int
  /// stdin EOF 粘滞位（A1：置位后 getchar 恒 -1、scanf 恒 EOF）。
  mut eof : Bool
  /// ungetc 缓存（Some = 已回退一字节）。
  mut ungetc : Int?
  /// true = Batch（判分/批量），false = Interactive（等待学生键入）。
  batch : Bool
}

///|
pub fn InputState::new(lines : Array[Bytes], batch : Bool) -> InputState {
  InputState::{
    lines,
    index: 0,
    char_offset: 0,
    eof: false,
    ungetc: None,
    batch,
  }
}

///|
/// 置位 EOF 粘滞并把游标推到底（oracle `set_stdin_eof`：否则未消费的尾部
/// 空白会被后续 getchar 当普通字符读出）。
fn InputState::set_eof(self : InputState) -> Unit {
  self.eof = true
  self.index = self.lines.length()
  self.char_offset = 0
}

///|
/// 字节流首非空白字节是否存在（scanf 的"流已无可用内容"判据）。
fn stream_has_content(stream : Array[Byte]) -> Bool {
  for b in stream {
    if !is_ascii_ws_byte(b) {
      return true
    }
  }
  false
}

///|
/// fmt 字节 → 码点数组（lossy——与 oracle `read_cstring` 的 String 管道
/// 同构；非 ASCII 字节经 U+FFFD，输出侧再编码回 UTF-8，字节守恒）。
fn lossy_codes(bytes : Bytes) -> Array[Int] {
  let s = @utf8.decode_lossy(bytes)
  let codes : Array[Int] = []
  for c in s {
    codes.push(Char::to_int(c))
  }
  codes
}

///|
/// printf 族的公共管道：读 fmt → 守卫 → 预算 → 格式化。
/// `guard_name` 为 `Some` 时做参数计数守卫（printf/fprintf/scanf 有、
/// sprintf/snprintf/sscanf 无——坑 17 照搬）。
fn printf_pipeline(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  fmt_addr : UInt,
  args : Array[UInt64],
  guard_name : String?,
) -> Result[String, HostMemReply] {
  let fmt_bytes = match read_cstring(mem, map, fmt_addr) {
    Ok(b) => b
    Err(f) => return Err(fault_reply(f))
  }
  let fmt = lossy_codes(fmt_bytes)
  match guard_name {
    Some(name) => {
      let specs = parse_format_specs(fmt)
      if specs.length() > args.length() {
        return Err(
          trap_only(
            "\{name}: 格式字符串要求的参数多于实际提供的参数。",
          ),
        )
      }
    }
    None => ()
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
/// `printf(fmt, ...)`（oracle `io.rs:4-23`）——输出走 stdout 通道。
pub fn host_printf_n(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  log : OutputLog,
  fmt_addr : UInt,
  args : Array[UInt64],
) -> HostMemReply {
  match printf_pipeline(map, mem, fmt_addr, args, Some("printf")) {
    Ok(out) => {
      log.push_stdout(@utf8.encode(out))
      no_reply()
    }
    Err(r) => r
  }
}

///|
/// `fprintf(stream, fmt, ...)`（oracle `io.rs:349-374`）——`stream == 2`
/// 分流 stderr（E-P1-5），其余（含 `stdout` 与自定义 `FILE*`）走 stdout
/// 通道；**fprintf 到自定义 FILE\* 不落盘**是既有偏差（照搬，VFS 批裁定）。
pub fn host_fprintf_n(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  log : OutputLog,
  stream : UInt64,
  fmt_addr : UInt,
  args : Array[UInt64],
) -> HostMemReply {
  match printf_pipeline(map, mem, fmt_addr, args, Some("fprintf")) {
    Ok(out) => {
      if stream == 2UL {
        log.push_stderr(@utf8.encode(out))
      } else {
        log.push_stdout(@utf8.encode(out))
      }
      no_reply()
    }
    Err(r) => r
  }
}

///|
/// `sprintf(buf, fmt, ...)`（oracle `io.rs:383-403`）——写入目标缓冲 +
/// NUL，返回字节数（**无参数守卫**——坑 17 照搬）。
pub fn host_sprintf(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  buf_addr : UInt,
  fmt_addr : UInt,
  args : Array[UInt64],
) -> HostMemReply {
  let out = match printf_pipeline(map, mem, fmt_addr, args, None) {
    Ok(o) => o
    Err(r) => return r
  }
  let bytes = @utf8.encode(out)
  match mem.write_bytes(map, buf_addr, bytes) {
    Ok(_) => ()
    Err(f) => return fault_reply(f)
  }
  match mem.store_i8(map, buf_addr + bytes.length().reinterpret_as_uint(), 0) {
    Ok(_) => ()
    Err(f) => return fault_reply(f)
  }
  value_only(bytes.length().to_uint64())
}

///|
/// `snprintf(buf, n, fmt, ...)`（oracle `io.rs:405-429`）——截断到
/// `n-1` + NUL，返回**完整**长度（C 语义）；`n <= 0` 不写。
pub fn host_snprintf(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  buf_addr : UInt,
  size : Int,
  fmt_addr : UInt,
  args : Array[UInt64],
) -> HostMemReply {
  let out = match printf_pipeline(map, mem, fmt_addr, args, None) {
    Ok(o) => o
    Err(r) => return r
  }
  let bytes = @utf8.encode(out)
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
      match mem.write_bytes(map, buf_addr, Bytes::from_array(head)) {
        Ok(_) => ()
        Err(f) => return fault_reply(f)
      }
    }
    match mem.store_i8(map, buf_addr + n.reinterpret_as_uint(), 0) {
      Ok(_) => ()
      Err(f) => return fault_reply(f)
    }
  }
  value_only(bytes.length().to_uint64())
}

///|
/// `puts(s)`（oracle `io.rs:376-381`）——串 + 换行入 stdout，返回 1。
pub fn host_puts(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  log : OutputLog,
  s_addr : UInt,
) -> HostMemReply {
  let s = match read_cstring(mem, map, s_addr) {
    Ok(b) => b
    Err(f) => return fault_reply(f)
  }
  log.push_stdout(@utf8.encode(@utf8.decode_lossy(s) + "\n"))
  value_only(1UL)
}

///|
/// `putchar(c)`（oracle `io.rs:344-347`）——低字节经 char 通道（`200` →
/// U+00C8 → UTF-8 两字节 `C3 88`，oracle 实测；DIFF-LIB-PRINTF 族照搬），
/// 无返回值。
pub fn host_putchar(log : OutputLog, val : UInt64) -> Unit {
  log.push_stdout(
    @utf8.encode(Int::unsafe_to_char((val & 0xFFUL).to_int()).to_string()),
  )
}

///|
/// `ungetc(c, stream)`（oracle `io.rs:279-284`）——缓存一字节（stream
/// 实参不解析），返回 `c`（符号扩展压栈）。
pub fn host_ungetc(input : InputState, ch : Int) -> UInt64 {
  input.ungetc = Some(ch)
  ch.to_int64().reinterpret_as_uint64()
}

///|
/// `getchar()`（oracle `io.rs:286-342`）——ungetc 优先 → EOF 粘滞 →
/// 可用性检查 → 逐字节读；Batch 耗尽返 EOF(-1) 并粘滞，Interactive 等
/// 待。
pub fn host_getchar(input : InputState) -> InputOutcome {
  match input.ungetc {
    Some(ch) => {
      input.ungetc = None
      return InputOutcome::Value(ch.to_int64().reinterpret_as_uint64())
    }
    None => ()
  }
  if input.eof {
    if input.batch {
      return InputOutcome::Value(0xFFFFFFFFFFFFFFFFUL)
    }
    return InputOutcome::Waiting
  }
  // 可用性检查（跨行扫描）
  let mut idx = input.index
  let mut off = input.char_offset
  let mut found = false
  while idx < input.lines.length() {
    if off < input.lines[idx].length() {
      found = true
      break
    }
    idx = idx + 1
    off = 0
  }
  if !found {
    if input.batch {
      input.set_eof()
      return InputOutcome::Value(0xFFFFFFFFFFFFFFFFUL)
    }
    return InputOutcome::Waiting
  }
  let mut result = -1
  while input.index < input.lines.length() {
    let line = input.lines[input.index]
    if input.char_offset < line.length() {
      result = line[input.char_offset].to_int()
      input.char_offset = input.char_offset + 1
      break
    } else {
      input.index = input.index + 1
      input.char_offset = 0
    }
  }
  InputOutcome::Value(result.to_int64().reinterpret_as_uint64())
}

///|
/// scanf 格式串解析项（oracle `utils.rs:347-359` 的 `ScanfItem`）。
priv enum ScanfItem {
  /// `%` 转换符：(格式字母码, 长度修饰级别 0=无 1=l/h 2=ll)
  Spec(Int, Int)
  /// 空白指令：匹配任意数量（含零）空白
  Whitespace
  /// 普通字符指令（含 `%%` 展开的 `%`）：精确匹配
  Literal(Int)
}

///|
/// 解析 scanf 格式串（oracle `parse_scanf_specs` 照搬；非 ASCII 字面字符
/// 忽略——oracle 同：`ch.is_ascii()` 才入 Literal）。
fn parse_scanf_specs(fmt : Array[Int]) -> Array[ScanfItem] {
  let specs : Array[ScanfItem] = []
  let scan = FmtScan::{ s: fmt, i: 0, }
  while true {
    let ch = match scan.peek() {
      Some(c) => {
        scan.advance()
        c
      }
      None => break
    }
    if ch == 37 {
      match scan.peek() {
        Some(n) =>
          if n == 37 {
            specs.push(ScanfItem::Literal(37))
            scan.advance()
          } else {
            // 跳 flags
            while true {
              match scan.peek() {
                Some(c) =>
                  if c == 45 || c == 43 || c == 32 || c == 35 || c == 48 {
                    scan.advance()
                  } else {
                    break
                  }
                None => break
              }
            }
            // 跳 width
            while true {
              match scan.peek() {
                Some(c) =>
                  if (c >= 48 && c <= 57) || c == 42 {
                    scan.advance()
                  } else {
                    break
                  }
                None => break
              }
            }
            // 跳 precision
            match scan.peek() {
              Some(46) => {
                scan.advance()
                while true {
                  match scan.peek() {
                    Some(c) =>
                      if (c >= 48 && c <= 57) || c == 42 {
                        scan.advance()
                      } else {
                        break
                      }
                    None => break
                  }
                }
              }
              _ => ()
            }
            // 长度修饰
            let mut len_mod = 0
            match scan.peek() {
              Some(c) =>
                if c == 108 {
                  len_mod = 1
                  scan.advance()
                  match scan.peek() {
                    Some(108) => {
                      len_mod = 2
                      scan.advance()
                    }
                    _ => ()
                  }
                } else if c == 104 {
                  len_mod = 1
                  scan.advance()
                  match scan.peek() {
                    Some(104) => scan.advance()
                    _ => ()
                  }
                } else if c == 76 {
                  scan.advance()
                }
              None => ()
            }
            // 格式字母
            match scan.peek() {
              Some(spec) => {
                specs.push(ScanfItem::Spec(spec, len_mod))
                scan.advance()
              }
              None => ()
            }
          }
        None => ()
      }
    } else if is_ws_code(ch) {
      specs.push(ScanfItem::Whitespace)
    } else if ch < 128 {
      specs.push(ScanfItem::Literal(ch))
    }
    // 非 ASCII：忽略（oracle 同）
  }
  specs
}

///|
/// 码点空白判定（Rust `char::is_whitespace` 的 ASCII 子集；fmt 层非 ASCII
/// 空白（NBSP 等）oracle 会入空白指令、此处忽略——登记微差）。
fn is_ws_code(c : Int) -> Bool {
  (c >= 9 && c <= 13) || c == 32
}

///|
/// 读浮点 token（oracle `read_float_token` 照搬：自跳前导空白 → 可选符号
/// → 数字/点连续段）。
fn read_float_token(chars : Array[Byte], pos0 : Int) -> (Array[Byte], Int) {
  let n = chars.length()
  let mut pos = pos0
  while pos < n && is_ascii_ws_byte(chars[pos]) {
    pos = pos + 1
  }
  if pos >= n {
    return ([], pos)
  }
  let start = pos
  if chars[pos] == 43 || chars[pos] == 45 {
    pos = pos + 1
  }
  while pos < n {
    let c = chars[pos]
    if (c >= 48 && c <= 57) || c == 46 {
      pos = pos + 1
    } else {
      break
    }
  }
  let token : Array[Byte] = []
  let mut i = start
  while i < pos {
    token.push(chars[i])
    i = i + 1
  }
  (token, pos)
}

///|
/// token → Int（oracle `parse().unwrap_or(0)`：溢出/空/孤立符号 → 0）。
fn parse_int_or_zero(token : Array[Byte]) -> Int {
  @string.parse_int(@utf8.decode_lossy(Bytes::from_array(token))) catch {
    _ => 0
  }
}

///|
fn parse_int64_or_zero(token : Array[Byte]) -> Int64 {
  @string.parse_int64(@utf8.decode_lossy(Bytes::from_array(token))) catch {
    _ => 0L
  }
}

///|
fn parse_uint64_or_zero(token : Array[Byte]) -> UInt64 {
  @string.parse_uint64(@utf8.decode_lossy(Bytes::from_array(token))) catch {
    _ => 0UL
  }
}

///|
fn parse_uint_or_zero(token : Array[Byte]) -> UInt {
  @string.parse_uint(@utf8.decode_lossy(Bytes::from_array(token))) catch {
    _ => 0U
  }
}

///|
fn parse_double_or_zero(token : Array[Byte]) -> Double {
  @string.parse_double(@utf8.decode_lossy(Bytes::from_array(token))) catch {
    _ => 0.0
  }
}

///|
/// `scanf(fmt, ...)`（oracle `io.rs:25-277` 照搬——含 V-P1-13 流式游标
/// 与映射表推进、A1 EOF 粘滞、C11 返回值语义）。
///
/// `ptrs` 为按转换符序弹出的目标地址（vm 接线）；`%s` 带栈缓冲容量校验
/// （V-P1-6，`stack_buffers` 同 strcpy 口径）。
pub fn host_scanf_n(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  input : InputState,
  stack_buffers : Array[StackBufferSpan],
  fmt_addr : UInt,
  ptrs : Array[UInt],
) -> InputOutcome {
  let fmt_bytes = match read_cstring(mem, map, fmt_addr) {
    Ok(b) => b
    Err(f) => return InputOutcome::Trap(access_fault_text(f))
  }
  let spec_types = parse_scanf_specs(lossy_codes(fmt_bytes))
  let mut arg_count = 0
  for it in spec_types {
    match it {
      ScanfItem::Spec(_, _) => arg_count = arg_count + 1
      _ => ()
    }
  }
  if ptrs.length() < arg_count {
    return InputOutcome::Trap(
      "scanf: 格式字符串要求的参数多于实际提供的参数。",
    )
  }
  // 虚拟字节流 + 映射表（V-P1-13）
  let stream : Array[Byte] = []
  let map_line : Array[Int] = []
  let map_off : Array[Int] = []
  let start_idx = input.index
  let start_off = input.char_offset
  let mut i = start_idx
  while i < input.lines.length() {
    let line = input.lines[i]
    let from = if i == start_idx {
      let len = line.length()
      if start_off < len {
        start_off
      } else {
        len
      }
    } else {
      0
    }
    let mut off = from
    while off < line.length() {
      map_line.push(i)
      map_off.push(off)
      stream.push(line[off])
      off = off + 1
    }
    let line_len = line.length()
    if line_len == 0 || line[line_len - 1] != b'\n' {
      map_line.push(i + 1)
      map_off.push(-1)
      stream.push(b'\n')
    }
    i = i + 1
  }
  // 首转换符前流已无可用内容（Batch → EOF；Interactive → 等待）
  if !stream_has_content(stream) {
    if input.batch {
      input.set_eof()
      return InputOutcome::Value(0xFFFFFFFFFFFFFFFFUL)
    }
    return InputOutcome::Waiting
  }
  if input.eof {
    if input.batch {
      input.set_eof()
      return InputOutcome::Value(0xFFFFFFFFFFFFFFFFUL)
    }
    return InputOutcome::Waiting
  }
  let chars = stream
  let mut pos = 0
  let mut arg_idx = 0
  let mut matched = 0
  let mut exhausted = false
  for item in spec_types {
    let sl = match item {
      ScanfItem::Whitespace => {
        while pos < chars.length() && is_ascii_ws_byte(chars[pos]) {
          pos = pos + 1
        }
        continue
      }
      ScanfItem::Literal(expected) => {
        if pos >= chars.length() || chars[pos].to_int() != expected {
          break
        }
        pos = pos + 1
        continue
      }
      ScanfItem::Spec(s, lm) => (s, lm)
    }
    let spec = sl.0
    let len_mod = sl.1
    let ptr = ptrs[arg_idx]
    arg_idx = arg_idx + 1
    if spec == 100 {
      // d
      while pos < chars.length() && is_ascii_ws_byte(chars[pos]) {
        pos = pos + 1
      }
      if pos >= chars.length() {
        exhausted = true
        break
      }
      let start = pos
      if chars[pos] == 43 || chars[pos] == 45 {
        pos = pos + 1
      }
      while pos < chars.length() && chars[pos] >= 48 && chars[pos] <= 57 {
        pos = pos + 1
      }
      let token : Array[Byte] = []
      let mut j = start
      while j < pos {
        token.push(chars[j])
        j = j + 1
      }
      let f = if len_mod >= 2 {
        mem.store_u64(
          map,
          ptr,
          parse_int64_or_zero(token).reinterpret_as_uint64(),
        )
      } else {
        mem.store_u32(map, ptr, parse_int_or_zero(token).reinterpret_as_uint())
      }
      match f {
        Ok(_) => ()
        Err(e) => return InputOutcome::Trap(access_fault_text(e))
      }
    } else if spec == 117 {
      // u
      while pos < chars.length() && is_ascii_ws_byte(chars[pos]) {
        pos = pos + 1
      }
      if pos >= chars.length() {
        exhausted = true
        break
      }
      let start = pos
      if chars[pos] == 43 {
        pos = pos + 1
      }
      while pos < chars.length() && chars[pos] >= 48 && chars[pos] <= 57 {
        pos = pos + 1
      }
      let token : Array[Byte] = []
      let mut j = start
      while j < pos {
        token.push(chars[j])
        j = j + 1
      }
      let f = if len_mod >= 2 {
        mem.store_u64(map, ptr, parse_uint64_or_zero(token))
      } else {
        mem.store_u32(
          map,
          ptr,
          parse_uint_or_zero(token).reinterpret_as_int().reinterpret_as_uint(),
        )
      }
      match f {
        Ok(_) => ()
        Err(e) => return InputOutcome::Trap(access_fault_text(e))
      }
    } else if spec == 102 {
      // f
      while pos < chars.length() && is_ascii_ws_byte(chars[pos]) {
        pos = pos + 1
      }
      if pos >= chars.length() {
        exhausted = true
        break
      }
      let pair = read_float_token(chars, pos)
      let token = pair.0
      pos = pair.1
      if token.length() == 0 {
        break
      }
      let f = if len_mod >= 1 {
        mem.store_u64(
          map,
          ptr,
          parse_double_or_zero(token).reinterpret_as_uint64(),
        )
      } else {
        // %f → float（4 字节位模式）
        mem.store_u32(
          map,
          ptr,
          Float::reinterpret_as_uint(
            Float::from_double(parse_double_or_zero(token)),
          ),
        )
      }
      match f {
        Ok(_) => ()
        Err(e) => return InputOutcome::Trap(access_fault_text(e))
      }
    } else if spec == 99 {
      // c（不跳空白）
      if pos >= chars.length() {
        exhausted = true
        break
      }
      let ch = chars[pos]
      pos = pos + 1
      match mem.store_i8(map, ptr, ch.to_int()) {
        Ok(_) => ()
        Err(e) => return InputOutcome::Trap(access_fault_text(e))
      }
    } else if spec == 115 {
      // s
      while pos < chars.length() && is_ascii_ws_byte(chars[pos]) {
        pos = pos + 1
      }
      if pos >= chars.length() {
        exhausted = true
        break
      }
      let start = pos
      while pos < chars.length() && !is_ascii_ws_byte(chars[pos]) {
        pos = pos + 1
      }
      let token : Array[Byte] = []
      let mut j = start
      while j < pos {
        token.push(chars[j])
        j = j + 1
      }
      // V-P1-6：栈缓冲容量校验（token + NUL）
      match
        stack_buffer_check(
          stack_buffers,
          ptr,
          token.length() + 1,
          "scanf(\"%s\")",
        ) {
        Some(t) => return InputOutcome::Trap(t)
        None => ()
      }
      match mem.write_bytes(map, ptr, Bytes::from_array(token)) {
        Ok(_) => ()
        Err(e) => return InputOutcome::Trap(access_fault_text(e))
      }
      match mem.store_i8(map, ptr + token.length().reinterpret_as_uint(), 0) {
        Ok(_) => ()
        Err(e) => return InputOutcome::Trap(access_fault_text(e))
      }
    } else {
      // 不支持的转换符：未消费输入，不计入成功项
      continue
    }
    matched = matched + 1
  }
  // 游标推进（映射表；未消费部分留给后续输入函数）
  if pos > 0 && pos - 1 < map_line.length() {
    let idx = map_line[pos - 1]
    let off = map_off[pos - 1]
    if off < 0 {
      input.index = idx
      input.char_offset = 0
    } else {
      let line_len = if idx < input.lines.length() {
        input.lines[idx].length()
      } else {
        0
      }
      input.index = idx
      input.char_offset = if off + 1 < line_len { off + 1 } else { line_len }
    }
  }
  // 因流耗尽而中止 → Batch 置粘滞（字面量/转换不匹配不置——判据是 exhausted）
  if input.batch && exhausted {
    input.set_eof()
  }
  InputOutcome::Value(matched.to_uint64())
}

///|
/// `sscanf(str, fmt, ...)`（oracle `io.rs:431-564` 照搬）。
///
/// 与 scanf 的照搬差异：**无参数守卫**（坑 17）、`matched` 逐臂自增（未知
/// 转换符不计）、无 exhausted/EOF 概念（源串是内存非流）、`%s` 无栈缓冲
/// 校验（oracle 同）。源串按**字节**扫描（oracle 经 lossy char——非 ASCII
/// 的 `%c` 落点/空白判定分叉，A-10 族登记）。
pub fn host_sscanf(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  str_addr : UInt,
  fmt_addr : UInt,
  ptrs : Array[UInt],
) -> HostMemReply {
  let fmt_bytes = match read_cstring(mem, map, fmt_addr) {
    Ok(b) => b
    Err(f) => return fault_reply(f)
  }
  let src = match read_cstring(mem, map, str_addr) {
    Ok(b) => b
    Err(f) => return fault_reply(f)
  }
  let spec_types = parse_scanf_specs(lossy_codes(fmt_bytes))
  let chars : Array[Byte] = []
  let n = src.length()
  let mut ci = 0
  while ci < n {
    chars.push(src[ci])
    ci = ci + 1
  }
  let mut pos = 0
  let mut matched = 0
  let mut arg_idx = 0
  for item in spec_types {
    let sl = match item {
      ScanfItem::Whitespace => {
        while pos < chars.length() && is_ascii_ws_byte(chars[pos]) {
          pos = pos + 1
        }
        continue
      }
      ScanfItem::Literal(expected) => {
        if pos >= chars.length() || chars[pos].to_int() != expected {
          break
        }
        pos = pos + 1
        continue
      }
      ScanfItem::Spec(s, lm) => (s, lm)
    }
    let spec = sl.0
    let len_mod = sl.1
    if arg_idx >= ptrs.length() {
      break
    }
    let ptr = ptrs[arg_idx]
    arg_idx = arg_idx + 1
    if spec == 100 {
      // d
      while pos < chars.length() && is_ascii_ws_byte(chars[pos]) {
        pos = pos + 1
      }
      if pos >= chars.length() {
        break
      }
      let start = pos
      if chars[pos] == 43 || chars[pos] == 45 {
        pos = pos + 1
      }
      while pos < chars.length() && chars[pos] >= 48 && chars[pos] <= 57 {
        pos = pos + 1
      }
      let token : Array[Byte] = []
      let mut j = start
      while j < pos {
        token.push(chars[j])
        j = j + 1
      }
      let f = if len_mod >= 2 {
        mem.store_u64(
          map,
          ptr,
          parse_int64_or_zero(token).reinterpret_as_uint64(),
        )
      } else {
        mem.store_u32(map, ptr, parse_int_or_zero(token).reinterpret_as_uint())
      }
      match f {
        Ok(_) => ()
        Err(e) => return fault_reply(e)
      }
      matched = matched + 1
    } else if spec == 117 {
      // u
      while pos < chars.length() && is_ascii_ws_byte(chars[pos]) {
        pos = pos + 1
      }
      if pos >= chars.length() {
        break
      }
      let start = pos
      if chars[pos] == 43 {
        pos = pos + 1
      }
      while pos < chars.length() && chars[pos] >= 48 && chars[pos] <= 57 {
        pos = pos + 1
      }
      let token : Array[Byte] = []
      let mut j = start
      while j < pos {
        token.push(chars[j])
        j = j + 1
      }
      let f = if len_mod >= 2 {
        mem.store_u64(map, ptr, parse_uint64_or_zero(token))
      } else {
        mem.store_u32(
          map,
          ptr,
          parse_uint_or_zero(token).reinterpret_as_int().reinterpret_as_uint(),
        )
      }
      match f {
        Ok(_) => ()
        Err(e) => return fault_reply(e)
      }
      matched = matched + 1
    } else if spec == 102 {
      // f
      let pair = read_float_token(chars, pos)
      let token = pair.0
      pos = pair.1
      if token.length() == 0 {
        break
      }
      let f = if len_mod >= 1 {
        mem.store_u64(
          map,
          ptr,
          parse_double_or_zero(token).reinterpret_as_uint64(),
        )
      } else {
        mem.store_u32(
          map,
          ptr,
          Float::reinterpret_as_uint(
            Float::from_double(parse_double_or_zero(token)),
          ),
        )
      }
      match f {
        Ok(_) => ()
        Err(e) => return fault_reply(e)
      }
      matched = matched + 1
    } else if spec == 99 {
      // c
      if pos >= chars.length() {
        break
      }
      let ch = chars[pos]
      pos = pos + 1
      match mem.store_i8(map, ptr, ch.to_int()) {
        Ok(_) => ()
        Err(e) => return fault_reply(e)
      }
      matched = matched + 1
    } else if spec == 115 {
      // s
      while pos < chars.length() && is_ascii_ws_byte(chars[pos]) {
        pos = pos + 1
      }
      if pos >= chars.length() {
        break
      }
      let start = pos
      while pos < chars.length() && !is_ascii_ws_byte(chars[pos]) {
        pos = pos + 1
      }
      let token : Array[Byte] = []
      let mut j = start
      while j < pos {
        token.push(chars[j])
        j = j + 1
      }
      match mem.write_bytes(map, ptr, Bytes::from_array(token)) {
        Ok(_) => ()
        Err(e) => return fault_reply(e)
      }
      match mem.store_i8(map, ptr + token.length().reinterpret_as_uint(), 0) {
        Ok(_) => ()
        Err(e) => return fault_reply(e)
      }
      matched = matched + 1
    } else {
      // 未知转换符：不消费不计数
    }
  }
  value_only(matched.to_uint64())
}
