// 蓝本注记：文内 Rust 源引用（`*.rs` 路径/行号/符号）均为档案态蓝本——tag rust-oracle-freeze（2026-10-05 删区），现为本仓自主基线。

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
/// **栈深守卫的族内不一致（坑 17，已知限制——历史蓝本同病，tag rust-oracle-freeze；
/// 修复工单 R1b W3-5 三函数守卫统一）**：printf/fprintf/scanf 有
/// 参数计数守卫（教学文案 trap）；**sprintf/snprintf/sscanf 没有**——参数
/// 不足时落到 format 引擎的"实参耗尽即原样输出"路径（`%d` 字面透传）。
///
/// **登记分叉**：fmt/`%s` 实参/`%c` 的读侧受检化（蓝本裸读）；sscanf
/// 的源串按字节扫描（蓝本经 lossy char——非 ASCII 的 `%c` 落点与空白
/// 判定不同，A-10 族）；scanf `%s` 的栈缓冲校验保留（V-P1-6）。

///|
/// 输入函数的三种结果：压栈值 / 等待输入（Interactive 模式输入耗尽）/ trap。
pub(all) enum InputOutcome {
  Value(UInt64)
  Waiting
  /// (trap 文案, 结构化 E 码)——#261：与 HostMemReply.trap 同形态双件。
  Trap(String, String)
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
  mut index : Int32
  mut char_offset : Int32
  /// stdin EOF 粘滞位（A1：置位后 getchar 恒 -1、scanf 恒 EOF）。
  mut eof : Bool
  /// ungetc 缓存（Some = 已回退一字节）。
  mut ungetc : Int32?
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
/// EOF 粘滞不推底（#210，2026-10-21）：feed 单帧 text+eof 同帧时已喂
/// 内容仍可读（stdio close 语义——close 后缓冲内容可读、耗尽返回 EOF），
/// 耗尽判定由读取路径承担（eof 把耗尽后的 Waiting 变 EOF 值）。
pub fn InputState::set_eof_sticky(self : InputState) -> Unit {
  self.eof = true
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
fn lossy_codes(bytes : Bytes) -> Array[Int32] {
  // #66：落盘层已整串 UTF-8 直通（cstring_bytes）——decode_lossy 对合法
  // 序列无损；非法字节（旧 Latin-1 口径残留形态）按 FFFD 退化兜底。
  let s = @utf8.decode_lossy(bytes)
  let codes : Array[Int32] = []
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
  fmt_addr : UInt32,
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
            "",
          ),
        )
      }
    }
    None => ()
  }
  match validate_format_field_budget(fmt) {
    Some(msg) => return Err(trap_only(msg, ""))
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
  fmt_addr : UInt32,
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
  fmt_addr : UInt32,
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
            "",
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
  buf_addr : UInt32,
  fmt_addr : UInt32,
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
  buf_addr : UInt32,
  size : Int32,
  fmt_addr : UInt32,
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
  s_addr : UInt32,
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
/// 实参不解析），返回 `c`（符号扩展压栈）。#428 A-11（2026-11-04）：
/// `ungetc(EOF, ...)` 是**无操作**（C11 §7.21.7.10——失败含 EOF 实参时
/// 流不变，返回 EOF）——旧形态 -1 被当回退字节缓存回吐，教学惯用法
/// `ungetc(getchar(), stdin)` 在 EOF 处吞流（clang 真值：回退后 getchar
/// 读流原内容 'x'=120）。
pub fn host_ungetc(input : InputState, ch : Int32) -> UInt64 {
  if ch == -1 {
    return 0xFFFFFFFFFFFFFFFFUL
  }
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
  // #210（2026-10-21）：eof 前置「先于一切」会吞掉剩余可读内容——改为
  // eof 只把「耗尽后的 Waiting」变 EOF 值（stdio close 语义：置位后已
  // 喂内容仍可读）。#88 收尾语义不变（耗尽即 EOF）。
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
    if input.batch || input.eof {
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
  /// ——width `*` 置位：读入丢弃、不消耗指针参数，%*d 批四 2026-10-07；
  /// 字段宽度 #71 病 23 2026-10-11——Some(n) 限本转换符最多读 n 个
  /// 输入字符（C11 §7.21.6.2，此前解析后丢弃=静默忽略）)
  Spec(Int32, Int32, Bool, Int32?)
  /// scanset 转换 `%[...]`（#149，2026-10-18，C11 §7.21.6.2p12）：
  /// (否定 `^` 置位, 集合字节表——首位 `]` 字面规则已并入, 赋值抑制,
  /// 字段宽度)。width/`*` 与 Spec 同语义。
  Scanset(Bool, Array[Byte], Bool, Int32?)
  /// 空白指令：匹配任意数量（含零）空白
  Whitespace
  /// 普通字符指令（含 `%%` 展开的 `%`）：精确匹配
  Literal(Int32)
}

///|
/// 解析 scanf 格式串（oracle `parse_scanf_specs` 照搬；非 ASCII 字面字符
/// 忽略——oracle 同：`ch.is_ascii()` 才入 Literal）。
fn parse_scanf_specs(fmt : Array[Int32]) -> Array[ScanfItem] {
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
            // width：数字累计（#71 病 23 修复，2026-10-11——此前累计后
            // 丢弃=静默忽略，%3d 读穿到下一个空白）；`*` = 赋值抑制
            //（C §7.21.6.2——%*d 批四 2026-10-07：读入丢弃、不消耗指针参数）
            let mut suppress = false
            let mut width_val = 0
            let mut width_seen = false
            while true {
              match scan.peek() {
                Some(c) =>
                  if c >= 48 && c <= 57 {
                    width_val = width_val * 10 + (c - 48)
                    width_seen = true
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
            let width_opt : Int32? = if width_seen && width_val > 0 {
              Some(width_val)
            } else {
              None
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
            // 长度修饰（审阅 P2-1，2026-10-23 分档化）：l=1 / ll=2 /
            // h=3 / hh=4（旧形态 h 与 hh 都记 1〔与 l 同档〕——%hn 写
            // 4 字节、%hhn 写 4 字节，相邻 canary 写穿）
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
                  len_mod = 3
                  scan.advance()
                  match scan.peek() {
                    Some(104) => {
                      len_mod = 4
                      scan.advance()
                    }
                    _ => ()
                  }
                } else if c == 76 {
                  scan.advance()
                }
              None => ()
            }
            // 格式字母
            // #149（2026-10-18）：`[`（91）不是格式字母——scanset 转换
            //（C11 §7.21.6.2p12）：`^` 否定位 + 字符集到 `]`（`]` 紧跟
            // `[` 或 `[^` 时是集合成员）；width/`*` 前缀同 Spec 语义。
            // 旧形态 `[` 落格式字母臂 + 集合内容被当字面字符 → 首字符
            // 即失配，四模型 7/8 采样全中的 SSCANF 族根因。
            match scan.peek() {
              Some(91) => {
                scan.advance()
                let negated = if scan.peek() == Some(94) {
                  scan.advance()
                  true
                } else {
                  false
                }
                let set : Array[Byte] = []
                // 首位 `]` 是集合成员（C11 规则）
                if scan.peek() == Some(93) {
                  set.push(Int32::to_byte(93))
                  scan.advance()
                }
                // 到终止 `]`。**未闭合（EOF）= 该转换失败**（对抗探针
                // adv_c n4 实测：clang 对 `%[abc`（无 ]）返回 0——收
                // raw 后按 closed 位决定产正常集合还是必失败形态）。
                // 先收原始 token（`-` 位置保留——范围判定要看邻位）
                let mut closed = false
                let raw : Array[Int32] = []
                while true {
                  match scan.peek() {
                    Some(93) => {
                      scan.advance()
                      closed = true
                      break
                    }
                    Some(c) => {
                      raw.push(c)
                      scan.advance()
                    }
                    None => break
                  }
                }
                // `-` 范围展开（实现定义域：glibc/clang 一致——**中缀**位
                // `-` 表范围（a-z）；首/末位 = 字面；降序（z-a）= 字面
                // 三字符。展开只补中间字符，两端由自身位置 push（无重复）。
                let mut k = 0
                while k < raw.length() {
                  let c = raw[k]
                  if c == 45 &&
                    k > 0 &&
                    k + 1 < raw.length() &&
                    raw[k - 1] < raw[k + 1] {
                    // 升序中缀 `-` = 范围：raw[k-1] 已 push（k-1 迭代），
                    // 补 (lo, hi) 开区间段；raw[k+1] 由其自身迭代 push
                    let lo = raw[k - 1]
                    let hi = raw[k + 1]
                    let mut m = lo + 1
                    while m < hi {
                      set.push(Int32::to_byte(m))
                      m = m + 1
                    }
                  } else {
                    // 普通字符 / 首末位 `-` / 降序范围（z-a）与怪形：字面
                    set.push(Int32::to_byte(c))
                  }
                  k = k + 1
                }
                // 未闭合：产「空正集合」——任意首字符都不在集 → 零长度
                // 匹配失败（adv_c n4 对齐 clang 的 n=0）；合法空集 `%[]`
                //（closed 且零字符）同语义
                if closed {
                  specs.push(
                    ScanfItem::Scanset(negated, set, suppress, width_opt),
                  )
                } else {
                  specs.push(ScanfItem::Scanset(false, [], suppress, width_opt))
                }
              }
              Some(spec) => {
                specs.push(ScanfItem::Spec(spec, len_mod, suppress, width_opt))
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
fn is_ws_code(c : Int32) -> Bool {
  (c >= 9 && c <= 13) || c == 32
}

///|
/// 读浮点 token（#71 病 23+24 重写，2026-10-11）：
/// - 形态统一 host_convert `scan_float_token` 同款判定（十进制/eE 指数/
///   hexfloat 0x…p…/悬空指数回退——此前只吃数字/点，"1e5" 读成 1 游标
///   停 'e'；host_convert atof 侧 2026-10-05 已修，scanf 侧未同步）；
/// - 字段宽度 max（病 23）：Some(w) 时 token 最多吃 w 个字符（前导空白
///   不计宽——先跳空白再计界）。
fn read_float_token(
  chars : Array[Byte],
  pos0 : Int32,
  max_chars : Int32?,
) -> (Array[Byte], Int32) {
  let n = chars.length()
  let mut pos = pos0
  while pos < n && is_ascii_ws_byte(chars[pos]) {
    pos = pos + 1
  }
  if pos >= n {
    return ([], pos)
  }
  let limit = match max_chars {
    Some(w) => if pos + w < n { pos + w } else { n }
    None => n
  }
  let start = pos
  if chars[pos] == 43 || chars[pos] == 45 {
    pos = pos + 1
  }
  // #428 A-10 连坐（2026-11-04）：INF/INFINITY/NAN 字母 token（strtod
  // subject sequence——C11 6.4.2.3 经 §7.21.6.2，大小写不敏感、可带
  // 符号；NAN 可带 `(n-char-sequence)` payload 体消费至 `)`，未闭合 →
  // 括号段整体不消费）。真值：inf/INFINITY/nan/NAN(1) 四形态双派 r=4
  // 全配。值层转换见 scanf_float_value。
  if pos < limit &&
    (chars[pos] == 105 || chars[pos] == 73) &&
    pos + 2 < limit &&
    (chars[pos + 1] == 110 || chars[pos + 1] == 78) &&
    (chars[pos + 2] == 102 || chars[pos + 2] == 70) {
    // INF 前缀；INITY? → INFINITY 尾段（完整 5 字母才消费——部分匹配
    // 如 "INFIN" 回退到 INF 结束位，INF 本身已是完整 token；尾段比较
    // **大小写不敏感**——C11 全族不敏感，"INFINITY" 大写尾段也须消费，
    // 否则游标停在半途（debug 实锤：off 停 'N' 第三字符）
    pos = pos + 3
    let inity : Array[Int32] = [105, 110, 105, 116, 121]
    let save = pos
    let mut k = 0
    while k < 5 && pos < limit {
      let c = chars[pos].to_int()
      let lower = if c >= 65 && c <= 90 { c + 32 } else { c }
      if lower == inity[k] {
        pos = pos + 1
        k = k + 1
      } else {
        break
      }
    }
    if k < 5 {
      pos = save
    }
    let token : Array[Byte] = []
    let mut i2 = start
    while i2 < pos {
      token.push(chars[i2])
      i2 = i2 + 1
    }
    return (token, pos)
  }
  if pos < limit &&
    (chars[pos] == 110 || chars[pos] == 78) &&
    pos + 2 < limit &&
    (chars[pos + 1] == 97 || chars[pos + 1] == 65) &&
    (chars[pos + 2] == 110 || chars[pos + 2] == 78) {
    // NAN 前缀；可选 (...) payload（n-char-sequence 域 [a-zA-Z0-9_]——
    // C11 6.4.2.3；闭合才属 subject sequence）。**未闭合 / 域外字符 =
    // 匹配失败**（PR #474 审阅 P3：旧形态回退成合法 "nan" 误判成功 r=1
    // ——clang 真值 sscanf("nan(") glibc r=0 / UCRT r=-1〔实现分叉，择
    // glibc 匹配失败边，UCRT 输入失败边登记〕、scanf 流内 r=0 双派一致）
    // → 空 token + pos 回 start（调用方不计数终止）
    pos = pos + 3
    if pos < limit && chars[pos] == 40 {
      pos = pos + 1
      let mut closed = false
      let mut bad_char = false
      while pos < limit {
        if chars[pos] == 41 {
          pos = pos + 1
          closed = true
          break
        }
        let ch = chars[pos]
        let nchar = (ch >= 97 && ch <= 122) ||
          (ch >= 65 && ch <= 90) ||
          (ch >= 48 && ch <= 57) ||
          ch == 95
        if !nchar {
          bad_char = true
          break
        }
        pos = pos + 1
      }
      if !closed || bad_char {
        return ([], start)
      }
    }
    let token : Array[Byte] = []
    let mut i3 = start
    while i3 < pos {
      token.push(chars[i3])
      i3 = i3 + 1
    }
    return (token, pos)
  }
  // hex float 探测（scan_float_token 同款：0x 后 hex 数字或 .+hex）
  let hex_probe = pos + 2 < limit &&
    chars[pos] == 48 &&
    (chars[pos + 1] == 120 || chars[pos + 1] == 88) &&
    (
      hex_digit_val(chars[pos + 2]) >= 0 ||
      (
        chars[pos + 2] == 46 &&
        pos + 3 < limit &&
        hex_digit_val(chars[pos + 3]) >= 0
      )
    )
  if hex_probe {
    pos = pos + 2
    while pos < limit && hex_digit_val(chars[pos]) >= 0 {
      pos = pos + 1
    }
    if pos < limit &&
      chars[pos] == 46 &&
      pos + 1 < limit &&
      hex_digit_val(chars[pos + 1]) >= 0 {
      pos = pos + 1
      while pos < limit && hex_digit_val(chars[pos]) >= 0 {
        pos = pos + 1
      }
    }
    if pos < limit && (chars[pos] == 112 || chars[pos] == 80) {
      let exp_start = pos
      pos = pos + 1
      if pos < limit && (chars[pos] == 43 || chars[pos] == 45) {
        pos = pos + 1
      }
      if pos < limit && chars[pos] >= 48 && chars[pos] <= 57 {
        while pos < limit && chars[pos] >= 48 && chars[pos] <= 57 {
          pos = pos + 1
        }
      } else {
        pos = exp_start
      }
    }
  } else {
    // 十进制：数字/点（一次）/eE 指数（一次，悬空回退）
    let mut has_dot = false
    let mut exp_start = -1
    while pos < limit {
      let c = chars[pos]
      if c >= 48 && c <= 57 {
        pos = pos + 1
      } else if c == 46 && !has_dot {
        has_dot = true
        pos = pos + 1
      } else if (c == 101 || c == 69) && exp_start < 0 {
        exp_start = pos
        pos = pos + 1
        if pos < limit && (chars[pos] == 43 || chars[pos] == 45) {
          pos = pos + 1
        }
      } else {
        break
      }
    }
    if exp_start >= 0 {
      // e(±) 后无数字 → 截回 e 前（"1e"/"1e+"→"1"；scan_float_token 同款）
      let b = exp_start
      let has_digit_after = (
          b + 1 < limit && chars[b + 1] >= 48 && chars[b + 1] <= 57
        ) ||
        (
          b + 2 < limit &&
          (chars[b + 1] == 43 || chars[b + 1] == 45) &&
          chars[b + 2] >= 48 &&
          chars[b + 2] <= 57
        )
      if !has_digit_after {
        pos = exp_start
      }
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
const SCANF_N = 110

// #428 缺臂族（2026-11-04，rules.json B 轮清账 / R1a-F3）：C11
// §7.21.6.2 p12 浮点族 a/A/e/E/f/F/g/G 输入语义全同（strtod subject
// sequence，不区分输出记法）；大写 X ≡ x（hex 同实现）。
// X=88 e=101 E=69 g=103 G=71 a=97 A=65 F=70

///|
const SCANF_X_UPPER = 88

///|
const SCANF_E = 101

///|
const SCANF_E_UPPER = 69

///|
const SCANF_G = 103

///|
const SCANF_G_UPPER = 71

///|
const SCANF_A = 97

///|
const SCANF_A_UPPER = 65

///|
const SCANF_F_UPPER = 70

///|
/// scanf 写目标按长度修饰分宽（审阅 P2-1，2026-10-23）：ll→8 字节 /
/// 无与 l→4（LLP64 long=4）/ h→2 / hh→1。val 一律 u64 位模式（各臂
/// parse 后 reinterpret；窄档取低位字节与 C 实现一致）。u16 = 两次 i8
/// 小端组合（memory 无 store_u16——组合写避免出口面扩张）。
fn scanf_store_by_lenmod(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  ptr : UInt32,
  len_mod : Int32,
  v64 : UInt64,
) -> Result[Unit, @memory.MemFault] {
  if len_mod == 2 {
    mem.store_u64(map, ptr, v64)
  } else if len_mod == 3 {
    match mem.store_i8(map, ptr, (v64 & 0xFFUL).to_int()) {
      Ok(_) => mem.store_i8(map, ptr + 1U, ((v64 >> 8) & 0xFFUL).to_int())
      Err(e) => Err(e)
    }
  } else if len_mod == 4 {
    mem.store_i8(map, ptr, (v64 & 0xFFUL).to_int())
  } else {
    mem.store_u32(
      map,
      ptr,
      @util.i64_to_i32_bits(v64.reinterpret_as_int64()).reinterpret_as_uint(),
    )
  }
}

///|
/// strtoll/strtoul 语义数字累加器（#428 A-9，2026-11-04）——替代
/// d/u 臂 parse_*_or_zero 的「溢出 catch→0」与 i/x/o 臂的裸回绕：
/// u64 域内逐位累加；超域 **clamp 边界位模式**（真值 = glibc+UCRT 双派
/// 一致，t2/t2b/t2c/t3/t5/t8 探针，2026-11-04 亲采）：
/// - 有符号转换符（d/i）负溢出 → LLONG_MIN（0x8000..0）**全档**——
///   %lld → LLONG_MIN / %d 低 32 位 = 0 / %hd 低 16 位 = 0
/// - 有符号正溢出 **ll 档**（len_mod==2）→ LLONG_MAX；4 字节及窄档 →
///   ULLONG_MAX 截位（%d → 0xFFFFFFFF = -1 / %hd → 0xFFFF——glibc
///   vfscanf 实现怪形按真值建模，不逆向）
/// - 无符号转换符（u/x/X/o）正负溢出 → ULLONG_MAX（**负号吞**——clamp
///   压过回绕：`%llx` 读 "-10000000000000000" → 0xFFFF..F；`%hu` 负
///   超域 → 65535）
/// - 域内负号 → 位模式回绕取负（`-5 %u` → 4294967291，现状已对）
/// digits 为纯数字 token（符号/进制前缀由调用方剥），base ∈ {10,16,8}。
fn scan_int_clamp(
  digits : Array[Byte],
  base : Int32,
  negative : Bool,
  signed_conv : Bool,
  is_ll : Bool,
) -> UInt64 {
  let b = base.to_uint64()
  let mut val : UInt64 = 0UL
  let mut overflow = false
  let n = digits.length()
  let mut i = 0
  while i < n {
    let d = hex_digit_val(digits[i]).to_uint64()
    // 溢出前探：val*b + d > ULLONG_MAX ⟺ val > (MAX-d)/b（UInt64 算术
    // 回绕——前探在乘加前完成，检测式自身不回绕）
    if val > (0xFFFFFFFFFFFFFFFFUL - d) / b {
      overflow = true
      break
    }
    val = val * b + d
    i = i + 1
  }
  if overflow {
    if signed_conv {
      if negative {
        0x8000000000000000UL
      } else if is_ll {
        9223372036854775807UL
      } else {
        0xFFFFFFFFFFFFFFFFUL
      }
    } else {
      0xFFFFFFFFFFFFFFFFUL
    }
  } else if negative {
    0UL - val
  } else {
    val
  }
}

///|
/// 浮点 token 值转换单点（#428 A-10，2026-11-04）：hexfloat 接
/// host_convert `parse_float_token` 单源（mantissa hex 逐位累加 + 2^p
/// 指数，精度取舍登记在彼处）；INF/INFINITY/NAN 形态本地识别
/// （strtod subject sequence——C11 6.4.2.3 经 §7.21.6.2，带符号；
/// NAN payload 位与 -nan 符号位是平台实现定义域〔M20 D-4〕——产静态
/// NaN）。atof/strtod 侧的 inf/nan token 缺口登记（host_convert
/// scan_float_token 域，非本批）。
fn scanf_float_value(token : Array[Byte]) -> Double {
  let neg = token.length() > 0 && token[0] == 45
  let off : Int32 = if token.length() > 0 && (token[0] == 43 || token[0] == 45) {
    1
  } else {
    0
  }
  fn ci(i : Int32) -> Int32 {
    let v = token[i].to_int()
    if v >= 65 && v <= 90 {
      v + 32
    } else {
      v
    }
  }
  let rest = token.length() - off
  // INF（INFINITY 尾段由 token 层收——此处只判三字母前缀）
  if rest >= 3 && ci(off) == 105 && ci(off + 1) == 110 && ci(off + 2) == 102 {
    return if neg { @double.neg_infinity } else { @double.infinity }
  }
  // NAN（payload 括号体 token 层已消费；**符号位保留**——PR #474 审阅 P3：
  // 旧静态 not_a_number 丢 "-nan" 符号；真值 glibc/UCRT 双派 signbit=1，
  // 置符号位 0xFFF8..0 静默 NaN）
  if rest >= 3 && ci(off) == 110 && ci(off + 1) == 97 && ci(off + 2) == 110 {
    if neg {
      return 0xFFF8000000000000UL.reinterpret_as_double()
    }
    return @double.not_a_number
  }
  parse_float_token(token)
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
  fmt_addr : UInt32,
  ptrs : Array[UInt32],
) -> InputOutcome {
  let fmt_bytes = match read_cstring(mem, map, fmt_addr) {
    Ok(b) => b
    Err(f) =>
      return InputOutcome::Trap(access_fault_text(f), access_fault_code(f))
  }
  let spec_types = parse_scanf_specs(lossy_codes(fmt_bytes))
  let mut arg_count = 0
  for it in spec_types {
    match it {
      // 赋值抑制（%*d）不消耗指针参数——批四 2026-10-07
      ScanfItem::Spec(_, _, false, _) => arg_count = arg_count + 1
      _ => ()
    }
  }
  if ptrs.length() < arg_count {
    return InputOutcome::Trap(
      "scanf: 格式字符串要求的参数多于实际提供的参数。", "",
    )
  }
  // 虚拟字节流 + 映射表（V-P1-13）
  let stream : Array[Byte] = []
  let map_line : Array[Int32] = []
  let map_off : Array[Int32] = []
  let start_idx = input.index
  let start_off = input.char_offset
  // 病 46（#71 P2 表，2026-10-16）：ungetc 缓存优先吐——scanf 流式游标
  // 与 getchar 的 ungetc 优先语义对齐（旧形态流拼装无视槽，'9' 回退后
  // scanf 直接读管道下字节）。映射锚 = (start_idx, start_off-1)：游标
  // 推进算法对 off+1=start_off 恰落 start_off（消费后位置不动=ungetc
  // 字节逻辑前置于游标）；start_off=0 时 off=-1 走补位锚分支归
  // (start_idx, 0) 同样正确
  if input.ungetc is Some(c) {
    stream.push(c.to_byte())
    map_line.push(start_idx)
    map_off.push(start_off - 1)
  }
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
  // #210（2026-10-21）：eof 前置联合「无可用内容」判定——置位后已喂
  // 内容仍可读（#88 的「显式 EOF 口生效」由本分支与 1366 区 exhausted
  // 共同承担：耗尽 + eof → EOF 值而非 Waiting）
  if input.eof && !stream_has_content(stream) {
    return InputOutcome::Value(0xFFFFFFFFFFFFFFFFUL)
  }
  // 首转换符前流已无可用内容（Batch → EOF；Interactive → 等待）
  if !stream_has_content(stream) {
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
      ScanfItem::Spec(s, lm, sup, wopt) => (s, lm, sup, wopt)
      // #149：scanset 执行（%s 同款 token 收集 + write_bytes + NUL；
      // 带 V-P1-6 栈缓冲校验——与 %s 同族写目标风险）。匹配规则：不跳
      // 前导空白（集合含空白才消费）；零长度 = 匹配失败（回退/不写/
      // 不计/终止——与 d/i/x/o 臂同语义）。
      ScanfItem::Scanset(neg, set, sup, wopt) => {
        if arg_idx >= ptrs.length() && !sup {
          break
        }
        let ptr = if sup { fmt_addr } else { ptrs[arg_idx] }
        if !sup {
          arg_idx = arg_idx + 1
        }
        let entry_pos = pos
        let lim = match wopt {
          Some(w) =>
            if pos + w < chars.length() {
              pos + w
            } else {
              chars.length()
            }
          None => chars.length()
        }
        let start = pos
        while pos < lim {
          let c = chars[pos]
          let in_set = set.contains(c)
          let take = if neg { !in_set } else { in_set }
          if take {
            pos = pos + 1
          } else {
            break
          }
        }
        if pos == start {
          pos = entry_pos
          break
        }
        let token : Array[Byte] = []
        let mut j = start
        while j < pos {
          token.push(chars[j])
          j = j + 1
        }
        if !sup {
          match
            stack_buffer_check(
              stack_buffers,
              ptr,
              token.length() + 1,
              "scanf(\"%[\")",
            ) {
            Some((t, c)) => return InputOutcome::Trap(t, c)
            None => ()
          }
        }
        if !sup {
          match mem.write_bytes(map, ptr, Bytes::from_array(token)) {
            Ok(_) => ()
            Err(e) =>
              return InputOutcome::Trap(
                access_fault_text(e),
                access_fault_code(e),
              )
          }
        }
        if !sup {
          match
            mem.store_i8(map, ptr + token.length().reinterpret_as_uint(), 0) {
            Ok(_) => ()
            Err(e) =>
              return InputOutcome::Trap(
                access_fault_text(e),
                access_fault_code(e),
              )
          }
        }
        if !sup {
          matched = matched + 1
        }
        continue
      }
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
      // #71 病 23：字段宽度限本转换符最多读 w 个输入字符（sl.3 流转）
      let lim = match sl.3 {
        Some(w) =>
          if pos + w < chars.length() {
            pos + w
          } else {
            chars.length()
          }
        None => chars.length()
      }
      let mut negative = false
      if chars[pos] == 43 || chars[pos] == 45 {
        negative = chars[pos] == 45
        pos = pos + 1
      }
      let digits_start = pos
      while pos < lim && chars[pos] >= 48 && chars[pos] <= 57 {
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
      // #428 A-9：超域 clamp 边界位模式（d = 有符号转换符——负溢出
      // LLONG_MIN 低 32 位 = 0；正溢出 ULLONG_MAX 低 32 位 = -1）；
      // 宽度分档照旧（审阅 P2-1——scanf_store_by_lenmod 取 clamp 值低位）
      let f = if !sl.2 {
        scanf_store_by_lenmod(
          mem,
          map,
          ptr,
          len_mod,
          scan_int_clamp(token, 10, negative, true, len_mod == 2),
        )
      } else {
        Ok(())
      }
      match f {
        Ok(_) => ()
        Err(e) =>
          return InputOutcome::Trap(access_fault_text(e), access_fault_code(e))
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
      // #71 病 23（2026-10-11）：字段宽度限本转换符最多读 w 个输入字符
      //（C11 §7.21.6.2——宽度不含前导空白；pos 此刻=跳空白后首字符位）
      let lim = match sl.3 {
        Some(w) =>
          if pos + w < chars.length() {
            pos + w
          } else {
            chars.length()
          }
        None => chars.length()
      }
      let mut negative = false
      if chars[pos] == 43 || chars[pos] == 45 {
        negative = chars[pos] == 45
        pos = pos + 1
      }
      let digits_start = pos
      while pos < lim && chars[pos] >= 48 && chars[pos] <= 57 {
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
      // #428 A-9 + 域内负号回绕（strtoul 形态，C11 §7.21.6.2——
      // "-5" %u → 4294967291 现状对保留）：负溢出 clamp ULLONG_MAX
      //（负号吞）；u = 无符号转换符
      let uval = scan_int_clamp(token, 10, negative, false, len_mod == 2)
      let f = if !sl.2 {
        scanf_store_by_lenmod(mem, map, ptr, len_mod, uval)
      } else {
        Ok(())
      }
      match f {
        Ok(_) => ()
        Err(e) =>
          return InputOutcome::Trap(access_fault_text(e), access_fault_code(e))
      }
    } else if spec == SCANF_F ||
      spec == SCANF_E ||
      spec == SCANF_E_UPPER ||
      spec == SCANF_G ||
      spec == SCANF_G_UPPER ||
      spec == SCANF_A ||
      spec == SCANF_A_UPPER ||
      spec == SCANF_F_UPPER {
      // f 族（#428 缺臂扩面，2026-11-04：e/E/g/G/a/A/F 输入语义与 f 全同
      //——C11 §7.21.6.2 p12 浮点族同一行，strtod subject sequence 不区分
      // 输出记法；此前缺臂落「未知转换符」else 兜底不消费不计数）。
      // #428 A-10：值转换走 scanf_float_value 单点（hexfloat 接
      // host_convert parse_float_token + inf/nan 形态——旧
      // parse_double_or_zero 的 @string.parse_double 不认 hexfloat → 0.0）。
      // 旧臂死代码 lim 顺手删（M20 B-2——read_float_token 自带 max 重算）
      while pos < chars.length() && is_ascii_ws_byte(chars[pos]) {
        pos = pos + 1
      }
      if pos >= chars.length() {
        exhausted = true
        break
      }
      let pair = read_float_token(chars, pos, sl.3)
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
            scanf_float_value(token).reinterpret_as_uint64(),
          )
          // %f → float（4 字节位模式）
        } else {
          mem.store_u32(
            map,
            ptr,
            Float::reinterpret_as_uint(
              Float::from_double(scanf_float_value(token)),
            ),
          )
        }
      } else {
        Ok(())
      }
      match f {
        Ok(_) => ()
        Err(e) =>
          return InputOutcome::Trap(access_fault_text(e), access_fault_code(e))
      }
    } else if spec == SCANF_C {
      // c（不跳空白）；#428 A-3（2026-11-04）：宽度 k = wopt 或 1
      //（C11 §7.21.6.2——宽度适用**所有**转换；#71 病 23 修漏 %c 臂——
      // scanf+sscanf 双臂同漏）：逐字节读 k 个连续 store_i8，**不写
      // NUL**（%c 无终止符语义，clang `scanf("%3c")` 输入 abcdef →
      // buf="abc" next='d'）。中途流尽：部分写入保留（照 C——真值
      // `scanf("%5c")` 输入 "ab" → buf="ab"），转换未完成不计 matched。
      if pos >= chars.length() {
        exhausted = true
        break
      }
      let k = match sl.3 {
        Some(w) => w
        None => 1
      }
      let mut j = 0
      while j < k && pos < chars.length() {
        let ch = chars[pos]
        pos = pos + 1
        if !sl.2 {
          match mem.store_i8(map, ptr + j.reinterpret_as_uint(), ch.to_int()) {
            Ok(_) => ()
            Err(e) =>
              return InputOutcome::Trap(
                access_fault_text(e),
                access_fault_code(e),
              )
          }
        }
        j = j + 1
      }
      if j < k {
        // 宽度未读满即流尽——输入失败终止（matched 不计；部分写入已发生）
        exhausted = true
        break
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
      // #71 病 23（2026-10-11）：字段宽度限本转换符最多读 w 个输入字符
      //（C11 §7.21.6.2——宽度不含前导空白；pos 此刻=跳空白后首字符位）
      let lim = match sl.3 {
        Some(w) =>
          if pos + w < chars.length() {
            pos + w
          } else {
            chars.length()
          }
        None => chars.length()
      }
      let start = pos
      while pos < lim && !is_ascii_ws_byte(chars[pos]) {
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
          Some((t, c)) => return InputOutcome::Trap(t, c)
          None => ()
        }
      }
      if !sl.2 {
        match mem.write_bytes(map, ptr, Bytes::from_array(token)) {
          Ok(_) => ()
          Err(e) =>
            return InputOutcome::Trap(
              access_fault_text(e),
              access_fault_code(e),
            )
        }
      }
      if !sl.2 {
        match mem.store_i8(map, ptr + token.length().reinterpret_as_uint(), 0) {
          Ok(_) => ()
          Err(e) =>
            return InputOutcome::Trap(
              access_fault_text(e),
              access_fault_code(e),
            )
        }
      }
    } else if spec == SCANF_I ||
      spec == SCANF_X ||
      spec == SCANF_X_UPPER ||
      spec == SCANF_O {
      // i / x / o（病 9 修复，#47 2026-10-09——方向 A 扩面拍板；oracle
      // 从未实现、规范 :421 的 ✅ 系虚标，删区后以 C11 §7.21.6.2 为真值
      // 源补齐）：`%i` = strtol(s,NULL,0) 语义（0x/0X 前缀 16 进制、
      // 0 开头 8 进制、否则十进制）；`%x` = base 16（可选 0x 前缀——仅当
      // 后随 hex 数字才跳，防游标错位）；`%o` = base 8（'0' 天然是 oct
      // 数字无需前缀处理）。均可带符号；抑制（%*x）同外层只跳写不跳消费。
      // #428（2026-11-04）：大写 X 并臂（C11 %X ≡ %x）；累加器换
      // scan_int_clamp（旧裸回绕超域错值——clamp：i 有符号负溢出
      // LLONG_MIN / x/X/o 无符号溢出 ULLONG_MAX 负号吞）。
      let entry_pos = pos
      while pos < chars.length() && is_ascii_ws_byte(chars[pos]) {
        pos = pos + 1
      }
      if pos >= chars.length() {
        exhausted = true
        break
      }
      // #71 病 23（2026-10-11）：字段宽度限本转换符最多读 w 个输入字符
      //（C11 §7.21.6.2——宽度不含前导空白；pos 此刻=跳空白后首字符位）
      let lim = match sl.3 {
        Some(w) =>
          if pos + w < chars.length() {
            pos + w
          } else {
            chars.length()
          }
        None => chars.length()
      }
      let mut negative = false
      if chars[pos] == 43 || chars[pos] == 45 {
        negative = chars[pos] == 45
        pos = pos + 1
      }
      if pos >= lim {
        exhausted = true
        break
      }
      // #59 题 1（2026-10-10 裁定）："0x" 残缺前缀（x 后无 hex 数字、含
      // 串尾）= 匹配失败——**消费 "0x" 两字符不退回**（glibc 2.43/UCRT
      // 双派 stdin 实测一致：%c 随后读到 Z；与病 13 d/u 的回退语义刻意
      // 异构——那边失败时零消费故回退=未动，这边前缀已消费保留）、不计
      // matched、不写、终止（返已配数，C11 §7.21.6.2）
      if (spec == SCANF_I || spec == SCANF_X || spec == SCANF_X_UPPER) &&
        pos < lim &&
        chars[pos] == 48 &&
        pos + 1 < lim &&
        (chars[pos + 1] == 120 || chars[pos + 1] == 88) &&
        !(pos + 2 < lim && hex_digit_val(chars[pos + 2]) >= 0) {
        pos = pos + 2
        break
      }
      let mut base : Int32 = 10
      if spec == SCANF_X || spec == SCANF_X_UPPER {
        base = 16
        // 可选 0x/0X 前缀（strtoul 语义：后随 hex 数字才构成前缀）
        if pos + 2 < lim &&
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
        if pos + 2 < lim &&
          (chars[pos + 1] == 120 || chars[pos + 1] == 88) &&
          hex_digit_val(chars[pos + 2]) >= 0 {
          base = 16
          pos = pos + 2
        } else {
          base = 8
        }
      }
      let digits_start2 = pos
      let mut scanned = false
      while pos < lim {
        let d = hex_digit_val(chars[pos])
        if d < 0 || d >= base {
          break
        }
        pos = pos + 1
        scanned = true
      }
      if !scanned {
        // 无数字（如纯符号 / "0x" 无后随 hex）——匹配失败：游标回退到本项
        // 进入处、不计入 matched、终止后续匹配（C：首项失败即返回已配数）
        pos = entry_pos
        break
      }
      let token2 : Array[Byte] = []
      let mut j2 = digits_start2
      while j2 < pos {
        token2.push(chars[j2])
        j2 = j2 + 1
      }
      // #428 A-9：clamp 累加器（i 有符号 / x·X·o 无符号）
      let val = scan_int_clamp(
        token2,
        base,
        negative,
        spec == SCANF_I,
        len_mod == 2,
      )
      let f = if !sl.2 {
        scanf_store_by_lenmod(mem, map, ptr, len_mod, val)
      } else {
        Ok(())
      }
      match f {
        Ok(_) => ()
        Err(e) =>
          return InputOutcome::Trap(access_fault_text(e), access_fault_code(e))
      }
    } else if spec == SCANF_N {
      // #269（2026-10-22）：`%n` 写回到该点**已读字符数**（C23 §7.23.6.2p12
      // ——不消耗输入、不计返回值；被转换符消费的前导空白也计入 pos）。
      // `pos += consumed` 循环推进形态的教学语料（gen4/q36_27b）依赖此
      // 写回，漏写即死循环。长度修饰同 d/u/i 臂口径：ll → 8 字节、其余
      // 4 字节；h=2 字节、hh=1 字节（审阅 P2-1 分档——len_mod 3=h/4=hh）。
      let f = if !sl.2 {
        scanf_store_by_lenmod(
          mem,
          map,
          ptr,
          len_mod,
          pos.to_int64().reinterpret_as_uint64(),
        )
      } else {
        Ok(())
      }
      match f {
        Ok(_) => ()
        Err(e) =>
          return InputOutcome::Trap(access_fault_text(e), access_fault_code(e))
      }
      continue
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
    // 病 46 连坐：pos>0 = 流头 ungetc 字节（若有）已消费——清槽防
    // getchar 二次吐（C 语义 ungetc 字节只吐一次）
    if input.ungetc is Some(_) {
      input.ungetc = None
    }
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
  // 病 109 修正（#71 P1 批，2026-10-12）：Interactive 中途流耗尽 →
  // Waiting——旧判据仅查首转换符前（770 区），`scanf("%d %d")` 喂 "10"
  // 后 %d1 配成、%d2 流尽走终判返 matched=1（静默丢参；客户端再 feed
  // 因非等待态重跑清输出——serve 在册语义连带）。回退到本次 scanf
  // 起点等输入，vm 侧 Waiting 协议（ip 回退+参数回推）接管重执行。
  // #210（2026-10-21）：eof 粘滞已置时不再回退等待——流已被调用方
  // 显式收尾，返回 EOF 哨兵（scanf 读输入即 -1 的 #88 承诺）
  if !input.batch && exhausted {
    if input.eof {
      return InputOutcome::Value(0xFFFFFFFFFFFFFFFFUL)
    }
    input.index = start_idx
    input.char_offset = start_off
    return InputOutcome::Waiting
  }
  // #474 审阅 P2（2026-11-04）：**首个转换完成前的输入失败 → EOF**（C11
  // §7.21.6.2 p16）——matched==0 且因流耗尽中止（exhausted 而非不匹配）
  // 时返 -1 而非 0：`scanf("%5c")` 输入 "ab" → clang r=-1（buf 已写 "ab"
  // 部分写入保留）；`scanf("%d")` 仅空白输入同形（顺治存量边角——旧返
  // matched=0）。不匹配（字面失配/格式错）仍返 0 ✓ 不变。
  if exhausted && matched == 0 {
    return InputOutcome::Value(0xFFFFFFFFFFFFFFFFUL)
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
  str_addr : UInt32,
  fmt_addr : UInt32,
  ptrs : Array[UInt32],
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
  // #474 审阅 P2（2026-11-04）：源串尽中止位（区别于不匹配 break）——
  // 尾部「首个转换完成前的输入失败 → EOF」判定用（C11 §7.21.6.2 p16）
  let mut exhausted = false
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
      ScanfItem::Spec(s, lm, sup, wopt) => (s, lm, sup, wopt)
      // #149：scanset 执行（host_sscanf 版——fault_reply 形态；写调用
      // 者缓冲无栈缓冲校验，与本函数 %s 臂注释口径一致）。匹配规则与
      // host_scanf_n 版逐字同款：不跳空白 / 零长度=匹配失败回退终止。
      ScanfItem::Scanset(neg, set, sup, wopt) => {
        if arg_idx >= ptrs.length() && !sup {
          break
        }
        let ptr = if sup { fmt_addr } else { ptrs[arg_idx] }
        if !sup {
          arg_idx = arg_idx + 1
        }
        let entry_pos = pos
        let lim = match wopt {
          Some(w) =>
            if pos + w < chars.length() {
              pos + w
            } else {
              chars.length()
            }
          None => chars.length()
        }
        let start = pos
        while pos < lim {
          let c = chars[pos]
          let in_set = set.contains(c)
          let take = if neg { !in_set } else { in_set }
          if take {
            pos = pos + 1
          } else {
            break
          }
        }
        if pos == start {
          pos = entry_pos
          break
        }
        let token : Array[Byte] = []
        let mut j = start
        while j < pos {
          token.push(chars[j])
          j = j + 1
        }
        if !sup {
          match mem.write_bytes(map, ptr, Bytes::from_array(token)) {
            Ok(_) => ()
            Err(e) => return fault_reply(e)
          }
        }
        if !sup {
          match
            mem.store_i8(map, ptr + token.length().reinterpret_as_uint(), 0) {
            Ok(_) => ()
            Err(e) => return fault_reply(e)
          }
        }
        if !sup {
          matched = matched + 1
        }
        continue
      }
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
        exhausted = true
        break
      }
      // #71 病 23（2026-10-11）：字段宽度限本转换符最多读 w 个输入字符
      //（C11 §7.21.6.2——宽度不含前导空白；pos 此刻=跳空白后首字符位）
      let lim = match sl.3 {
        Some(w) =>
          if pos + w < chars.length() {
            pos + w
          } else {
            chars.length()
          }
        None => chars.length()
      }
      let mut negative = false
      if chars[pos] == 43 || chars[pos] == 45 {
        negative = chars[pos] == 45
        pos = pos + 1
      }
      let digits_start = pos
      while pos < lim && chars[pos] >= 48 && chars[pos] <= 57 {
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
      // #428 A-9：clamp 累加器（与 scanf 臂同修——d 有符号）
      let f = if !sl.2 {
        scanf_store_by_lenmod(
          mem,
          map,
          ptr,
          len_mod,
          scan_int_clamp(token, 10, negative, true, len_mod == 2),
        )
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
        exhausted = true
        break
      }
      // #71 病 23（2026-10-11）：字段宽度限本转换符最多读 w 个输入字符
      //（C11 §7.21.6.2——宽度不含前导空白；pos 此刻=跳空白后首字符位）
      let lim = match sl.3 {
        Some(w) =>
          if pos + w < chars.length() {
            pos + w
          } else {
            chars.length()
          }
        None => chars.length()
      }
      let mut negative = false
      if chars[pos] == 43 || chars[pos] == 45 {
        negative = chars[pos] == 45
        pos = pos + 1
      }
      let digits_start = pos
      while pos < lim && chars[pos] >= 48 && chars[pos] <= 57 {
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
      // #428 A-9 + 域内负号回绕（"-5" %u → 4294967291 现状对保留）：
      // 负溢出 clamp ULLONG_MAX（负号吞）；u = 无符号转换符
      let uval = scan_int_clamp(token, 10, negative, false, len_mod == 2)
      let f = if !sl.2 {
        scanf_store_by_lenmod(mem, map, ptr, len_mod, uval)
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
    } else if spec == SCANF_I ||
      spec == SCANF_X ||
      spec == SCANF_X_UPPER ||
      spec == SCANF_O {
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
        exhausted = true
        pos = entry_pos
        break
      }
      // #71 病 23：字段宽度（同第一循环臂——sl.3 经 Spec 第四参流转）
      let lim = match sl.3 {
        Some(w) =>
          if pos + w < chars.length() {
            pos + w
          } else {
            chars.length()
          }
        None => chars.length()
      }
      let mut negative = false
      if chars[pos] == 43 || chars[pos] == 45 {
        negative = chars[pos] == 45
        pos = pos + 1
      }
      if pos >= lim {
        pos = entry_pos
        break
      }
      // #59 题 1（2026-10-10 裁定）："0x" 残缺前缀（x 后无 hex 数字、含
      // 串尾）= 匹配失败——**消费 "0x" 两字符不退回**（glibc 2.43/UCRT
      // 双派 stdin 实测一致：%c 随后读到 Z；与病 13 d/u 的回退语义刻意
      // 异构——那边失败时零消费故回退=未动，这边前缀已消费保留）、不计
      // matched、不写、终止（返已配数，C11 §7.21.6.2）
      if (spec == SCANF_I || spec == SCANF_X || spec == SCANF_X_UPPER) &&
        pos < lim &&
        chars[pos] == 48 &&
        pos + 1 < lim &&
        (chars[pos + 1] == 120 || chars[pos + 1] == 88) &&
        !(pos + 2 < lim && hex_digit_val(chars[pos + 2]) >= 0) {
        pos = pos + 2
        break
      }
      let mut base : Int32 = 10
      if spec == SCANF_X || spec == SCANF_X_UPPER {
        base = 16
        // 可选 0x/0X 前缀（strtoul 语义：后随 hex 数字才构成前缀）
        if pos + 2 < lim &&
          chars[pos] == 48 &&
          (chars[pos + 1] == 120 || chars[pos + 1] == 88) &&
          hex_digit_val(chars[pos + 2]) >= 0 {
          pos = pos + 2
        }
      } else if spec == SCANF_O {
        base = 8
      } else if chars[pos] == 48 {
        // %i 的前缀探测：0x/0X+hex → 16；0 开头 → 8
        if pos + 2 < lim &&
          (chars[pos + 1] == 120 || chars[pos + 1] == 88) &&
          hex_digit_val(chars[pos + 2]) >= 0 {
          base = 16
          pos = pos + 2
        } else {
          base = 8
        }
      }
      let digits_start2 = pos
      let mut scanned = false
      while pos < lim {
        let d = hex_digit_val(chars[pos])
        if d < 0 || d >= base {
          break
        }
        pos = pos + 1
        scanned = true
      }
      if !scanned {
        pos = entry_pos
        break
      }
      let token2 : Array[Byte] = []
      let mut j2 = digits_start2
      while j2 < pos {
        token2.push(chars[j2])
        j2 = j2 + 1
      }
      // #428 A-9：clamp 累加器（与 scanf 臂同修——i 有符号 / x·X·o 无符号）
      let val = scan_int_clamp(
        token2,
        base,
        negative,
        spec == SCANF_I,
        len_mod == 2,
      )
      let f = if !sl.2 {
        scanf_store_by_lenmod(mem, map, ptr, len_mod, val)
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
    } else if spec == SCANF_F ||
      spec == SCANF_E ||
      spec == SCANF_E_UPPER ||
      spec == SCANF_G ||
      spec == SCANF_G_UPPER ||
      spec == SCANF_A ||
      spec == SCANF_A_UPPER ||
      spec == SCANF_F_UPPER {
      // f 族（#428 缺臂扩面：e/E/g/G/a/A/F 与 f 全同 + hexfloat/inf/nan
      // 值转换走 scanf_float_value——与 scanf 臂同修）
      // f（#71 病 23+24：宽度经 token 读取 max 承接；token 形态统一
      // host_convert.scan_float_token——十进制/eE 指数/hexfloat/悬空回退）
      let pair = read_float_token(chars, pos, sl.3)
      let token = pair.0
      pos = pair.1
      if token.length() == 0 {
        // 流尽形态（pos 推到串尾）置 exhausted——首字符非法的不匹配不置
        if pos >= chars.length() {
          exhausted = true
        }
        break
      }
      let f = if !sl.2 {
        if len_mod >= 1 {
          mem.store_u64(
            map,
            ptr,
            scanf_float_value(token).reinterpret_as_uint64(),
          )
        } else {
          mem.store_u32(
            map,
            ptr,
            Float::reinterpret_as_uint(
              Float::from_double(scanf_float_value(token)),
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
      // c；#428 A-3：宽度 k = wopt 或 1（与 scanf 臂同修——双臂同漏实证）；
      // 逐字节读 k 个、不写 NUL；中途源串尽 → 部分写入保留、不计 matched
      if pos >= chars.length() {
        exhausted = true
        break
      }
      let k = match sl.3 {
        Some(w) => w
        None => 1
      }
      let mut j = 0
      while j < k && pos < chars.length() {
        let ch = chars[pos]
        pos = pos + 1
        if !sl.2 {
          match mem.store_i8(map, ptr + j.reinterpret_as_uint(), ch.to_int()) {
            Ok(_) => ()
            Err(e) => return fault_reply(e)
          }
        }
        j = j + 1
      }
      if j < k {
        exhausted = true
        break
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
        exhausted = true
        break
      }
      // #71 病 23（2026-10-11）：字段宽度限本转换符最多读 w 个输入字符
      //（C11 §7.21.6.2——宽度不含前导空白；pos 此刻=跳空白后首字符位）
      let lim = match sl.3 {
        Some(w) =>
          if pos + w < chars.length() {
            pos + w
          } else {
            chars.length()
          }
        None => chars.length()
      }
      let start = pos
      while pos < lim && !is_ascii_ws_byte(chars[pos]) {
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
    } else if spec == SCANF_N {
      // #269（2026-10-22）：`%n` 写回已读字符数（与 scanf 臂同语义——
      // 不消耗输入、不计返回值；pos = 源串到该点已消费字节数）
      let f = if !sl.2 {
        scanf_store_by_lenmod(
          mem,
          map,
          ptr,
          len_mod,
          pos.to_int64().reinterpret_as_uint64(),
        )
      } else {
        Ok(())
      }
      match f {
        Ok(_) => ()
        Err(e) => return fault_reply(e)
      }
    } else {
      // 未知转换符：不消费不计数
    }
  }
  // #474 审阅 P2（2026-11-04）：**首个转换完成前的输入失败 → EOF**
  //（C11 §7.21.6.2 p16——sscanf 的「eof」= 读过源串尾）：matched==0 且
  // 因源串尽中止时返 -1：`sscanf("ab","%5c")` → clang r=-1（glibc/UCRT
  // 双派一致）。不匹配（字面失配/格式错/nan( 未闭合）仍返 0 ✓。
  if exhausted && matched == 0 {
    return value_only(0xFFFFFFFFFFFFFFFFUL)
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
  let mut normalized = text
  // #317（2026-10-26）：流首 UTF-8 BOM（U+FEFF）剥离——Windows 下游
  // （PowerShell Out-File 等）默认写 BOM，此前 BOM 泄入首行 ⇒ 首读
  // scanf 匹配失败 ⇒ 程序静默无输出 rc=0（判分主路径全盘错判零线索）。
  // 与源码通道（lexer pp strip_bom）对齐：BOM 是编码标记非内容。语义
  // 边界（P3-3 审阅处置）：本函数无状态——剥的是**每次调用的首** U+FEFF
  //（行中不动）；input.feed / serve stdin 流分块追加时每 chunk 各剥各自
  // 首（chunk 间拼接处的 BOM 属内容保留——实际影响极小，语义取舍在
  // 此明示）。三消费者（run -i / serve input 参数 / serve stdin 流）经
  // 本单源一次治本。
  let bom = Int32::unsafe_to_char(0xFEFF).to_string()
  if normalized.has_prefix(bom) {
    normalized = normalized[1:].to_owned()
  }
  // **循环规整**（2026-09-29 stdin 34 例批实锤）：MoonBit String::replace
  // 只替换**首个**匹配（探针：a\rb\rc.replace → a-bc）——单次调用只消
  // 一个 CRLF，kr_1_19 实测第二行起 \r 泄入程序（输出多 \r 分叉）；
  // 循环到不含即全量（stdin 规模小，O(n^2) 最坏可忽略）
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
