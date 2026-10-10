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
/// 字节流，按实际消费量推进游标——"每行整行消费"的旧缺陷不复刻。
/// 行尾 `\n` 补位（映射表记 `(i+1, -1)`）是**守卫形态**：行已含尾换行
/// （2026-09-28 审阅批 P1 对齐后的正统形态）不补；仅无换行行（直接
/// 构造/末行无换行）兜底补一个流终止 `\n`。
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
pub extend InputOutcome with Debug::{to_repr}

///|
pub extend InputOutcome with Eq::{not_equal, equal}

///|
/// 会话输入态（oracle `RuntimeState` 输入域 + 模式）。
pub(all) struct InputState {
  /// 输入行（oracle `input_lines : Vec<String>`——此处按字节承载）。
  /// **行含尾换行**（oracle `split_stdin` 的 `split_inclusive('\n')` 产物
  /// 同形；2026-09-28 审阅批 P1 对齐——此前「行不含换行」形态是 V-P1-13
  /// 形态转换期的中间态，serve 切行剥掉换行使 getchar 每行少产一个
  /// `\n`〔实测 oracle `"ab\ncd\n"` 计 n=6 / 本侧 n=4〕；形态统一后
  /// getchar 逐字节读行数据自然对齐。无换行行〔直接构造/末行无换行〕
  /// 由 scanf 虚拟流的补位守卫兜底）。
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
/// 追加输入行并**清除 EOF 粘滞位**（Rust `RuntimeState::push_stdin_text`
/// 同形——交互续跑 `input.feed` 的通道：追加非覆盖，读取游标保留）。
/// 同步清除的语义：C 里管道关闭后不可复活，但教学场景下交互式续跑
/// 本质是"学生又键入了一行"，属预期的新内容到达。
pub fn InputState::push_lines(self : InputState, more : Array[Bytes]) -> Unit {
  for l in more {
    self.lines.push(l)
  }
  self.eof = false
}

///|
/// 置位 EOF 粘滞并把游标推到底（oracle `set_stdin_eof`：否则未消费的尾部
/// 空白会被后续 getchar 当普通字符读出）。
///
/// **批三号三段上提 pub**：vm 分发侧 Batch 模式 scanf/getchar 的
/// 「输入耗尽即 EOF」分支需要同一置位语义（Rust 侧是 session.runtime
/// 的方法，vm 可达；MoonBit 宿主域内聚在 InputState——vm 持有实例故
/// 该置位通道须跨包可见）。
pub fn InputState::set_eof(self : InputState) -> Unit {
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
  // #66：落盘层已整串 UTF-8 直通（cstring_bytes）——decode_lossy 对合法
  // 序列无损；非法字节（旧 Latin-1 口径残留形态）按 FFFD 退化兜底。
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
) -> Result[Bytes, HostMemReply] {
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
      log.push_stdout(out)
      // N3 销案（批四 2026-10-07）：返回输出字节数（C 标准 int）
      value_only(out.length().to_uint64())
    }
    Err(r) => r
  }
}

///|
/// `fprintf(stream, fmt, ...)`（C 语义三通道分流）——`stream == 1` 走
/// stdout、`stream == 2` 走 stderr（E-P1-5）、**自定义 `FILE*` 落盘 VFS**
///（DIFF-LIB-FPRINTF-01 销案，2026-10-05 批二-a：旧形态按 `stream != 2`
/// 全走 stdout 通道、自定义文件写静默丢弃系 oracle 照搬在案；fread 读回
/// 端到端锚见 host_io_wbtest）。**返回输出字节数（N3 销案，批四
/// 2026-10-07）**——三通道统一按提交给通道的字符数（落盘通道 vfs 尽写，
/// 无截断形态）。
pub fn host_fprintf_n(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  log : OutputLog,
  vfs : VirtualFileSystem,
  stream : UInt64,
  fmt_addr : UInt,
  args : Array[UInt64],
) -> HostMemReply {
  match printf_pipeline(map, mem, fmt_addr, args, Some("fprintf")) {
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
            "fprintf: stream 指向未打开的文件或文件不可写（FILE\\* 读取或写入失败）。",
          )
        }
      }
      // N3 销案（批四 2026-10-07）：返回输出字节数（三通道统一）
      value_only(out.length().to_uint64())
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
  let bytes = match printf_pipeline(map, mem, fmt_addr, args, None) {
    Ok(o) => o
    Err(r) => return r
  }
  write_bytes_raise(mem, map, buf_addr, bytes) catch {
    AccessFault::Fault(f~) => return fault_reply(f)
  }
  store_i8_raise(mem, map, buf_addr + bytes.length().reinterpret_as_uint(), 0) catch {
    AccessFault::Fault(f~) => return fault_reply(f)
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
  let bytes = match printf_pipeline(map, mem, fmt_addr, args, None) {
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

///|
/// `puts(s)`（oracle `io.rs:376-381`）——串 + 换行入 stdout，返回 1。
pub fn host_puts(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  log : OutputLog,
  s_addr : UInt,
) -> HostMemReply {
  let s = read_cstring_raise(mem, map, s_addr) catch {
    AccessFault::Fault(f~) => return fault_reply(f)
  }
  // #66：C 串字节直推（旧 lossy 对毁裸 Latin-1 字节）
  log.push_stdout(s.add(b"\n"))
  value_only(1UL)
}

///|
/// `putchar(c)`（oracle `io.rs:344-347` 对齐位）——**单字节直写通道**
///（DIFF-LIB-PUTCHAR-01 / DIFF-EXIT-STDOUT-ENCODE-01 销账，2026-10-05
/// 脱钩修复批批一）：此前照搬 oracle 的 char 通道（200 → U+00C8 →
/// UTF-8 两字节 `C3 88`——迁移期两侧一致优先登记不修），脱钩后回归
/// C 字节语义（Clang `putchar(200)` 落单字节 0xC8——putchar_range.c
/// 语料锚）；printf `%c` 高位字节的同族形态在 formatter 的 String 域，
/// 随批二 DIFF-LIB-PRINTF-01 处置

///|
/// 返回写入的字节（unsigned char 语义——N3 销案批四 2026-10-07，
/// `putchar('x') == 120`；原 Unit 形态系 oracle 照搬）。
pub fn host_putchar(log : OutputLog, val : UInt64) -> UInt64 {
  log.push_stdout(Bytes::make(1, (val & 0xFFUL).to_int().to_byte()))
  val & 0xFFUL
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
  /// `%` 转换符：(格式字母码, 长度修饰级别 0=无 1=l/h 2=ll, 赋值抑制
  /// ——width `*` 置位：读入丢弃、不消耗指针参数，%*d 批四 2026-10-07)
  Spec(Int, Int, Bool)
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
            // width：数字累计跳过；`*` = 赋值抑制（C §7.21.6.2——%*d 批四
            // 2026-10-07：读入丢弃、不消耗指针参数）
            let mut suppress = false
            while true {
              match scan.peek() {
                Some(c) =>
                  if c >= 48 && c <= 57 {
                    scan.advance()
                  } else if c == 42 {
                    suppress = true
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
                specs.push(ScanfItem::Spec(spec, len_mod, suppress))
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

// scanf/sscanf 转换符 ASCII 码（病 14 具名化，#61——原 15 处 spec 裸魔数）：
// d=100 u=117 f=102 c=99 s=115 i=105 x=120 o=111（fmt 字节域）

///|
const SCANF_D = 100

///|
const SCANF_U = 117

///|
const SCANF_F = 102

///|
const SCANF_C = 99

///|
const SCANF_S = 115

///|
const SCANF_I = 105

///|
const SCANF_X = 120

///|
const SCANF_O = 111

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
      // 赋值抑制（%*d）不消耗指针参数——批四 2026-10-07
      ScanfItem::Spec(_, _, false) => arg_count = arg_count + 1
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
      ScanfItem::Spec(s, lm, sup) => (s, lm, sup)
    }
    let spec = sl.0
    let len_mod = sl.1
    // 抑制赋值（%*d 批四 2026-10-07）：写目标改投已解析完的格式串
    // 地址（spec_types 在循环前已物化，覆盖无副作用）——读入消费
    // 照常、指针参数不消耗
    let ptr = if sl.2 { fmt_addr } else { ptrs[arg_idx] }
    if !sl.2 {
      arg_idx = arg_idx + 1
    }
    if spec == SCANF_D {
      // d（病 13 修复，#61：无数字=匹配失败——回退/不计/不写/终止，对齐 i/x/o 臂；
      // 旧臂 token 空也写 0 且 matched++ 对 UCRT/glibc 双分叉，C11 §7.21.6.2 匹配失败返 0）
      let entry_pos = pos
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
      if pos == start ||
        (pos == start + 1 && (chars[start] == 43 || chars[start] == 45)) {
        pos = entry_pos
        break
      }
      let token : Array[Byte] = []
      let mut j = start
      while j < pos {
        token.push(chars[j])
        j = j + 1
      }
      let f = if !sl.2 {
        if len_mod >= 2 {
          mem.store_u64(
            map,
            ptr,
            parse_int64_or_zero(token).reinterpret_as_uint64(),
          )
        } else {
          mem.store_u32(
            map,
            ptr,
            parse_int_or_zero(token).reinterpret_as_uint(),
          )
        }
      } else {
        Ok(())
      }
      match f {
        Ok(_) => ()
        Err(e) => return InputOutcome::Trap(access_fault_text(e))
      }
    } else if spec == SCANF_U {
      // u（病 13 失败语义 + #61 审阅 P1-3 符号面对齐 i/x/o 臂：+/- 记录、
      // 负值无符号回绕；旧臂不认 '-' 失败、'+' 被吃后 token 交
      // parse_uint 不吃 '+' → 写 0 还计数）
      let entry_pos = pos
      while pos < chars.length() && is_ascii_ws_byte(chars[pos]) {
        pos = pos + 1
      }
      if pos >= chars.length() {
        exhausted = true
        break
      }
      let mut negative = false
      if chars[pos] == 43 || chars[pos] == 45 {
        negative = chars[pos] == 45
        pos = pos + 1
      }
      let digits_start = pos
      while pos < chars.length() && chars[pos] >= 48 && chars[pos] <= 57 {
        pos = pos + 1
      }
      if pos == digits_start {
        pos = entry_pos
        break
      }
      let token : Array[Byte] = []
      let mut j = digits_start
      while j < pos {
        token.push(chars[j])
        j = j + 1
      }
      // 负值按无符号回绕（strtoul 形态，C11 §7.21.6.2——"-5" %u → 4294967291）
      let uval = if negative {
        0UL - parse_uint64_or_zero(token)
      } else {
        parse_uint64_or_zero(token)
      }
      let f = if !sl.2 {
        if len_mod >= 2 {
          mem.store_u64(map, ptr, uval)
        } else {
          mem.store_u32(
            map,
            ptr,
            @util.i64_to_i32_bits(uval.reinterpret_as_int64()).reinterpret_as_uint(),
          )
        }
      } else {
        Ok(())
      }
      match f {
        Ok(_) => ()
        Err(e) => return InputOutcome::Trap(access_fault_text(e))
      }
    } else if spec == SCANF_F {
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
      let f = if !sl.2 {
        if len_mod >= 1 {
          mem.store_u64(
            map,
            ptr,
            parse_double_or_zero(token).reinterpret_as_uint64(),
          )
          // %f → float（4 字节位模式）
        } else {
          mem.store_u32(
            map,
            ptr,
            Float::reinterpret_as_uint(
              Float::from_double(parse_double_or_zero(token)),
            ),
          )
        }
      } else {
        Ok(())
      }
      match f {
        Ok(_) => ()
        Err(e) => return InputOutcome::Trap(access_fault_text(e))
      }
    } else if spec == SCANF_C {
      // c（不跳空白）
      if pos >= chars.length() {
        exhausted = true
        break
      }
      let ch = chars[pos]
      pos = pos + 1
      if !sl.2 {
        match mem.store_i8(map, ptr, ch.to_int()) {
          Ok(_) => ()
          Err(e) => return InputOutcome::Trap(access_fault_text(e))
        }
      }
    } else if spec == SCANF_S {
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
      if !sl.2 {
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
      }
      if !sl.2 {
        match mem.write_bytes(map, ptr, Bytes::from_array(token)) {
          Ok(_) => ()
          Err(e) => return InputOutcome::Trap(access_fault_text(e))
        }
      }
      if !sl.2 {
        match mem.store_i8(map, ptr + token.length().reinterpret_as_uint(), 0) {
          Ok(_) => ()
          Err(e) => return InputOutcome::Trap(access_fault_text(e))
        }
      }
    } else if spec == SCANF_I || spec == SCANF_X || spec == SCANF_O {
      // i / x / o（病 9 修复，#47 2026-10-09——方向 A 扩面拍板；oracle
      // 从未实现、规范 :421 的 ✅ 系虚标，删区后以 C11 §7.21.6.2 为真值
      // 源补齐）：`%i` = strtol(s,NULL,0) 语义（0x/0X 前缀 16 进制、
      // 0 开头 8 进制、否则十进制）；`%x` = base 16（可选 0x 前缀——仅当
      // 后随 hex 数字才跳，防游标错位）；`%o` = base 8（'0' 天然是 oct
      // 数字无需前缀处理）。均可带符号；抑制（%*x）同外层只跳写不跳消费。
      let entry_pos = pos
      while pos < chars.length() && is_ascii_ws_byte(chars[pos]) {
        pos = pos + 1
      }
      if pos >= chars.length() {
        exhausted = true
        break
      }
      let mut negative = false
      if chars[pos] == 43 || chars[pos] == 45 {
        negative = chars[pos] == 45
        pos = pos + 1
      }
      if pos >= chars.length() {
        exhausted = true
        break
      }
      // #59 题 1（2026-10-10 裁定）："0x" 残缺前缀（x 后无 hex 数字、含
      // 串尾）= 匹配失败——**消费 "0x" 两字符不退回**（glibc 2.43/UCRT
      // 双派 stdin 实测一致：%c 随后读到 Z；与病 13 d/u 的回退语义刻意
      // 异构——那边失败时零消费故回退=未动，这边前缀已消费保留）、不计
      // matched、不写、终止（返已配数，C11 §7.21.6.2）
      if (spec == SCANF_I || spec == SCANF_X) &&
        pos < chars.length() &&
        chars[pos] == 48 &&
        pos + 1 < chars.length() &&
        (chars[pos + 1] == 120 || chars[pos + 1] == 88) &&
        !(pos + 2 < chars.length() && hex_digit_val(chars[pos + 2]) >= 0) {
        pos = pos + 2
        break
      }
      let mut base : Int = 10
      if spec == SCANF_X {
        base = 16
        // 可选 0x/0X 前缀（strtoul 语义：后随 hex 数字才构成前缀）
        if pos + 2 < chars.length() &&
          chars[pos] == 48 &&
          (chars[pos + 1] == 120 || chars[pos + 1] == 88) &&
          hex_digit_val(chars[pos + 2]) >= 0 {
          pos = pos + 2
        }
      } else if spec == SCANF_O {
        base = 8
      } else if chars[pos] == 48 {
        // %i 的前缀探测：0x/0X+hex → 16；0 开头 → 8（'0' 作为首个 oct
        // 数字由下方扫描自然消费）
        if pos + 2 < chars.length() &&
          (chars[pos + 1] == 120 || chars[pos + 1] == 88) &&
          hex_digit_val(chars[pos + 2]) >= 0 {
          base = 16
          pos = pos + 2
        } else {
          base = 8
        }
      }
      let mut val : UInt64 = 0UL
      let mut scanned = false
      while pos < chars.length() {
        let d = hex_digit_val(chars[pos])
        if d < 0 || d >= base {
          break
        }
        val = val * base.to_uint64() + d.to_uint64()
        pos = pos + 1
        scanned = true
      }
      if !scanned {
        // 无数字（如纯符号 / "0x" 无后随 hex）——匹配失败：游标回退到本项
        // 进入处、不计入 matched、终止后续匹配（C：首项失败即返回已配数）
        pos = entry_pos
        break
      }
      if negative {
        val = 0UL - val
      }
      let f = if !sl.2 {
        if len_mod >= 2 {
          mem.store_u64(map, ptr, val)
        } else {
          mem.store_u32(
            map,
            ptr,
            @util.i64_to_i32_bits(val.reinterpret_as_int64()).reinterpret_as_uint(),
          )
        }
      } else {
        Ok(())
      }
      match f {
        Ok(_) => ()
        Err(e) => return InputOutcome::Trap(access_fault_text(e))
      }
    } else {
      // 不支持的转换符：未消费输入，不计入成功项
      continue
    }
    // 抑制赋值（%*d）不计入返回值（C §7.21.6.2——批四 2026-10-07）
    if !sl.2 {
      matched = matched + 1
    }
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
  let fmt_bytes = read_cstring_raise(mem, map, fmt_addr) catch {
    AccessFault::Fault(f~) => return fault_reply(f)
  }
  let src = read_cstring_raise(mem, map, str_addr) catch {
    AccessFault::Fault(f~) => return fault_reply(f)
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
      ScanfItem::Spec(s, lm, sup) => (s, lm, sup)
    }
    let spec = sl.0
    let len_mod = sl.1
    if arg_idx >= ptrs.length() && !sl.2 {
      break
    }
    // 抑制赋值（%*d 批四 2026-10-07）：写目标改投已解析完的格式串
    // 地址——读入消费照常、指针参数不消耗（同 host_scanf_n）
    let ptr = if sl.2 { fmt_addr } else { ptrs[arg_idx] }
    if !sl.2 {
      arg_idx = arg_idx + 1
    }
    if spec == SCANF_D {
      // d（病 13 修复，#61：无数字=匹配失败——回退/不计/不写/终止，对齐 i/x/o 臂）
      let entry_pos = pos
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
      if pos == start ||
        (pos == start + 1 && (chars[start] == 43 || chars[start] == 45)) {
        pos = entry_pos
        break
      }
      let token : Array[Byte] = []
      let mut j = start
      while j < pos {
        token.push(chars[j])
        j = j + 1
      }
      let f = if !sl.2 {
        if len_mod >= 2 {
          mem.store_u64(
            map,
            ptr,
            parse_int64_or_zero(token).reinterpret_as_uint64(),
          )
        } else {
          mem.store_u32(
            map,
            ptr,
            parse_int_or_zero(token).reinterpret_as_uint(),
          )
        }
      } else {
        Ok(())
      }
      match f {
        Ok(_) => ()
        Err(e) => return fault_reply(e)
      }
      if !sl.2 {
        matched = matched + 1
      }
    } else if spec == SCANF_U {
      // u（病 13 失败语义 + #61 审阅 P1-3 符号面对齐 i/x/o 臂：+/- 记录、
      // 负值无符号回绕；旧臂不认 '-' 失败、'+' 被吃后 token 交
      // parse_uint 不吃 '+' → 写 0 还计数）
      let entry_pos = pos
      while pos < chars.length() && is_ascii_ws_byte(chars[pos]) {
        pos = pos + 1
      }
      if pos >= chars.length() {
        break
      }
      let mut negative = false
      if chars[pos] == 43 || chars[pos] == 45 {
        negative = chars[pos] == 45
        pos = pos + 1
      }
      let digits_start = pos
      while pos < chars.length() && chars[pos] >= 48 && chars[pos] <= 57 {
        pos = pos + 1
      }
      if pos == digits_start {
        pos = entry_pos
        break
      }
      let token : Array[Byte] = []
      let mut j = digits_start
      while j < pos {
        token.push(chars[j])
        j = j + 1
      }
      // 负值按无符号回绕（strtoul 形态，C11 §7.21.6.2——"-5" %u → 4294967291）
      let uval = if negative {
        0UL - parse_uint64_or_zero(token)
      } else {
        parse_uint64_or_zero(token)
      }
      let f = if !sl.2 {
        if len_mod >= 2 {
          mem.store_u64(map, ptr, uval)
        } else {
          mem.store_u32(
            map,
            ptr,
            @util.i64_to_i32_bits(uval.reinterpret_as_int64()).reinterpret_as_uint(),
          )
        }
      } else {
        Ok(())
      }
      match f {
        Ok(_) => ()
        Err(e) => return fault_reply(e)
      }
      if !sl.2 {
        matched = matched + 1
      }
    } else if spec == SCANF_I || spec == SCANF_X || spec == SCANF_O {
      // i / x / o（#47 同族对齐扩面，审阅 P2-1 2026-10-09——与 scanf 臂
      // 同源，C11 §7.21.6.2 真值源：%i 前缀探测 0x→16 / 0→8，%x 可选
      // 0x 前缀仅后随 hex 才跳，%o base 8；均可带符号。无数字 → 匹配
      // 失败：游标回退、不计数、终止后续匹配——与 scanf 臂刻意同形，
      // 与本函数 d/u 旧臂的「store 0 且计数」两套口径问题属 P3-2 待
      // 裁定面，此处不扩散）
      let entry_pos = pos
      while pos < chars.length() && is_ascii_ws_byte(chars[pos]) {
        pos = pos + 1
      }
      if pos >= chars.length() {
        pos = entry_pos
        break
      }
      let mut negative = false
      if chars[pos] == 43 || chars[pos] == 45 {
        negative = chars[pos] == 45
        pos = pos + 1
      }
      if pos >= chars.length() {
        pos = entry_pos
        break
      }
      // #59 题 1（2026-10-10 裁定）："0x" 残缺前缀（x 后无 hex 数字、含
      // 串尾）= 匹配失败——**消费 "0x" 两字符不退回**（glibc 2.43/UCRT
      // 双派 stdin 实测一致：%c 随后读到 Z；与病 13 d/u 的回退语义刻意
      // 异构——那边失败时零消费故回退=未动，这边前缀已消费保留）、不计
      // matched、不写、终止（返已配数，C11 §7.21.6.2）
      if (spec == SCANF_I || spec == SCANF_X) &&
        pos < chars.length() &&
        chars[pos] == 48 &&
        pos + 1 < chars.length() &&
        (chars[pos + 1] == 120 || chars[pos + 1] == 88) &&
        !(pos + 2 < chars.length() && hex_digit_val(chars[pos + 2]) >= 0) {
        pos = pos + 2
        break
      }
      let mut base : Int = 10
      if spec == SCANF_X {
        base = 16
        // 可选 0x/0X 前缀（strtoul 语义：后随 hex 数字才构成前缀）
        if pos + 2 < chars.length() &&
          chars[pos] == 48 &&
          (chars[pos + 1] == 120 || chars[pos + 1] == 88) &&
          hex_digit_val(chars[pos + 2]) >= 0 {
          pos = pos + 2
        }
      } else if spec == SCANF_O {
        base = 8
      } else if chars[pos] == 48 {
        // %i 的前缀探测：0x/0X+hex → 16；0 开头 → 8
        if pos + 2 < chars.length() &&
          (chars[pos + 1] == 120 || chars[pos + 1] == 88) &&
          hex_digit_val(chars[pos + 2]) >= 0 {
          base = 16
          pos = pos + 2
        } else {
          base = 8
        }
      }
      let mut val : UInt64 = 0UL
      let mut scanned = false
      while pos < chars.length() {
        let d = hex_digit_val(chars[pos])
        if d < 0 || d >= base {
          break
        }
        val = val * base.to_uint64() + d.to_uint64()
        pos = pos + 1
        scanned = true
      }
      if !scanned {
        pos = entry_pos
        break
      }
      if negative {
        val = 0UL - val
      }
      let f = if !sl.2 {
        if len_mod >= 2 {
          mem.store_u64(map, ptr, val)
        } else {
          mem.store_u32(
            map,
            ptr,
            @util.i64_to_i32_bits(val.reinterpret_as_int64()).reinterpret_as_uint(),
          )
        }
      } else {
        Ok(())
      }
      match f {
        Ok(_) => ()
        Err(e) => return fault_reply(e)
      }
      if !sl.2 {
        matched = matched + 1
      }
    } else if spec == SCANF_F {
      // f
      let pair = read_float_token(chars, pos)
      let token = pair.0
      pos = pair.1
      if token.length() == 0 {
        break
      }
      let f = if !sl.2 {
        if len_mod >= 1 {
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
      } else {
        Ok(())
      }
      match f {
        Ok(_) => ()
        Err(e) => return fault_reply(e)
      }
      if !sl.2 {
        matched = matched + 1
      }
    } else if spec == SCANF_C {
      // c
      if pos >= chars.length() {
        break
      }
      let ch = chars[pos]
      pos = pos + 1
      if !sl.2 {
        match mem.store_i8(map, ptr, ch.to_int()) {
          Ok(_) => ()
          Err(e) => return fault_reply(e)
        }
      }
      if !sl.2 {
        matched = matched + 1
      }
    } else if spec == SCANF_S {
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
      if !sl.2 {
        match mem.write_bytes(map, ptr, Bytes::from_array(token)) {
          Ok(_) => ()
          Err(e) => return fault_reply(e)
        }
      }
      if !sl.2 {
        match mem.store_i8(map, ptr + token.length().reinterpret_as_uint(), 0) {
          Ok(_) => ()
          Err(e) => return fault_reply(e)
        }
      }
      if !sl.2 {
        matched = matched + 1
      }
    } else {
      // 未知转换符：不消费不计数
    }
  }
  value_only(matched.to_uint64())
}

///|
/// 从 stdin 文本构造输入态（oracle `RuntimeState::split_stdin` +
/// `set_stdin` 的单源收口，2026-09-29 stdin 34 例批）：`\r\n` 规整 →
/// `split_inclusive('\n')` 切行（**行含尾换行**、末行无换行原样、空串
/// 零行）+ Batch/Interactive 模式一次到位。消费者：cmd/serve（run 的
/// input 参数 / input.feed）与 cmd/run（`-i` headless 通道）——此前
/// serve 层私有实现，runner 层缺口接线时上提为三消费者单源。
pub fn InputState::from_stdin_text(text : String, batch : Bool) -> InputState {
  // **循环规整**（2026-09-29 stdin 34 例批实锤）：MoonBit String::replace
  // 只替换**首个**匹配（探针：a\rb\rc.replace → a-bc）——单次调用只消
  // 一个 CRLF，kr_1_19 实测第二行起 \r 泄入程序（输出多 \r 分叉）；
  // 循环到不含即全量（stdin 规模小，O(n^2) 最坏可忽略）
  let mut normalized = text
  while normalized.contains("\r\n") {
    normalized = normalized.replace(old="\r\n", new="\n")
  }
  if normalized.is_empty() {
    return InputState::new([], batch)
  }
  let nl : String = "\n"
  let ends_with_nl = normalized.has_suffix(nl)
  let segs : Array[String] = []
  for seg in normalized.split("\n") {
    segs.push(seg.to_owned())
  }
  let lines : Array[Bytes] = []
  let last = segs.length() - 1
  for i = 0; i < segs.length(); i = i + 1 {
    if ends_with_nl || i < last {
      lines.push(@utf8.encode(segs[i] + nl))
    } else {
      lines.push(@utf8.encode(segs[i]))
    }
  }
  if ends_with_nl {
    ignore(lines.pop())
  }
  InputState::new(lines, batch)
}
