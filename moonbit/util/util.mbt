// L0 纯机械助手（G-1，2026-09-26 落地）。准入判据（总计划 §6 G-1）：只收
// **零语义机械件**——纯函数、无业务判定、无状态、无副作用；新件入包须先在
// G 表登记。四族件的来历：
//
// - `utf8_len`：`@utf8.encode(s).length()` 散拼 ≥8 处收口（encode 对非法
//   UTF-8 静默产空串——S2/S5 事故同族根源，单点化后口径只剩一处可审计）；
// - `str_cmp`：bytecode/emitter 与 cmd/dump_compile 两份孪生收口；
// - `i64_to_i32_bits`：parser/decl 上提（`Int64::to_int` 语义未文档化，
//   位截断自己写——陷阱 #25）；
// - `le_u32_at` / `le_u64_at`：memory/carrier 的手工小端拼装上提
//   （`FixedArray[Byte]` 读侧无 LE 原语——陷阱 #35）。
// - `base64_encode`：gateway memory.dump 的 1MB 映像经 JSON 帧传输
//   （RFC 4648 标准字母表 + `=` 补位；解码侧宿主标准库——MoonBit 侧
//   只需编码方向，2026-10-06 #49 批二登记）。

///|
/// String 的 UTF-8 字节长度（与 Rust `String::len()` 同口径；与
/// `String::length()` 的码元数区分——多字节字符两者不等）。
///
/// 非法 UTF-8 的现状照 `@utf8.encode` 语义（静默产空串 ⇒ 长度 0），
/// 本包不新增判定——「非法 UTF-8 怎么算」的审计点只有这里。
pub fn utf8_len(s : String) -> Int32 {
  @utf8.encode(s).length()
}

///|
/// 字典序比较（负/零/正）。**禁用 `String::compare` / `<` `>`**——MoonBit
/// 内置 String 比较实测非字典序（`"delta" > "charlie"` 为 false，疑似长度
/// 优先；陷阱 #29），与 Go canonicalize 的键排序（sort.Strings，字节字典序）
/// 不一致。本函数按 UTF-16 码元逐位比较 + 短者小——键域为 C 标识符
/// （ASCII），与 UTF-8 字节字典序在此域等价。
pub fn str_cmp(a : String, b : String) -> Int32 {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<n {
    let x = a[i].to_int()
    let y = b[i].to_int()
    if x != y {
      return if x < y { -1 } else { 1 }
    }
  }
  if a.length() == b.length() {
    0
  } else if a.length() < b.length() {
    -1
  } else {
    1
  }
}

///|
/// Rust `as i32` 的 i64→i32 位截断（低 32 位符号解释）。照搬原
/// parser/decl.mbt 实现——`Int64::to_int` 语义未文档化，不依赖（陷阱 #25）。
pub fn i64_to_i32_bits(v : Int64) -> Int32 {
  let low = v & 0xFFFFFFFF
  if low >= 2147483648 {
    (low - 4294967296).to_int()
  } else {
    low.to_int()
  }
}

///|
/// 小端四字节拼装读（`FixedArray[Byte]` 读侧无 LE 原语——陷阱 #35；与
/// Rust `u32::from_le_bytes` 同形）。**越界不设防**：调用方负责区间
/// （memory 包的受检读在 `check_access` 之后调用本件）。
pub fn le_u32_at(bytes : FixedArray[Byte], off : Int32) -> UInt32 {
  bytes[off].to_uint() |
  (bytes[off + 1].to_uint() << 8) |
  (bytes[off + 2].to_uint() << 16) |
  (bytes[off + 3].to_uint() << 24)
}

///|
/// 小端八字节拼装读（同 `le_u32_at`，u64 位宽）。
pub fn le_u64_at(bytes : FixedArray[Byte], off : Int32) -> UInt64 {
  bytes[off].to_uint64() |
  (bytes[off + 1].to_uint64() << 8) |
  (bytes[off + 2].to_uint64() << 16) |
  (bytes[off + 3].to_uint64() << 24) |
  (bytes[off + 4].to_uint64() << 32) |
  (bytes[off + 5].to_uint64() << 40) |
  (bytes[off + 6].to_uint64() << 48) |
  (bytes[off + 7].to_uint64() << 56)
}

///|
/// String 的 UTF-8 字节序列（`@utf8.encode` 收口——S8 diagnostics 批
/// fix_gen/auto_fix 的字节域坐标操作共用；与 `String::to_bytes` 的
/// **UTF-16LE** 通道区分〔后者首跑实测 "a中b" → 8 字节〕）。非法 UTF-8
/// 现状同 `utf8_len` 的审计点声明（静默产空串）。
pub fn utf8_bytes(s : String) -> Bytes {
  @utf8.encode(s)
}

///|
/// 标准 base64 编码（RFC 4648 字母表 + `=` 补位）。纯函数机械件——
/// gateway memory.dump 的 1MB 映像经 JSON 帧传输用（解码侧宿主标准库，
/// MoonBit 侧只需编码方向）。锚 = RFC 测试向量全集（util_wbtest）。
pub fn base64_encode(b : Bytes) -> String {
  let table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  let n = b.length()
  let buf = StringBuilder()
  let mut i = 0
  while i + 3 <= n {
    let v = ((b[i].to_int() & 0xff) << 16) |
      ((b[i + 1].to_int() & 0xff) << 8) |
      (b[i + 2].to_int() & 0xff)
    buf.write_char(table[(v >> 18) & 63].unsafe_to_char())
    buf.write_char(table[(v >> 12) & 63].unsafe_to_char())
    buf.write_char(table[(v >> 6) & 63].unsafe_to_char())
    buf.write_char(table[v & 63].unsafe_to_char())
    i += 3
  }
  let rem = n - i
  if rem == 1 {
    let v = (b[i].to_int() & 0xff) << 16
    buf.write_char(table[(v >> 18) & 63].unsafe_to_char())
    buf.write_char(table[(v >> 12) & 63].unsafe_to_char())
    buf.write_string("==")
  } else if rem == 2 {
    let v = ((b[i].to_int() & 0xff) << 16) | ((b[i + 1].to_int() & 0xff) << 8)
    buf.write_char(table[(v >> 18) & 63].unsafe_to_char())
    buf.write_char(table[(v >> 12) & 63].unsafe_to_char())
    buf.write_char(table[(v >> 6) & 63].unsafe_to_char())
    buf.write_string("=")
  }
  buf.to_string()
}

///|
/// UTF-8 字节序列解码回 String（`utf8_bytes` 的逆操作）。Malformed 即
/// 调用方拼装 bug——fail loud abort，不吞解码错误（本包不做 lossy）。
pub fn utf8_text(b : Bytes) -> String {
  @utf8.decode(b) catch {
    _ =>
      abort(
        "util.utf8_text: 非法 UTF-8 字节序列（调用方拼装 bug）",
      )
  }
}

///|
/// UTF-8 字节序列解码——**流式前缀语义**（`utf8_text` 的宽容变体：
/// malformed 不 abort）。消费场景 = 游标可落在多字节序列中间的字节域
/// 切片（gateway output.delta 的 note 通道
/// cursor 增量；CLI note 聚合同款先例）。实现自 cmd/lib/cli `utf8_decode`
/// 上提（三态锚随迁 util_wbtest）。
/// #363（2026-10-28）语义改向：**中段非法序列 U+FFFD 替换 + 重同步**
/// （孤立延续 / 非法 lead / 坏延续 / WHATWG 第二字节域——旧实现不校验
/// 续位，经 unsafe_to_char 可产出代理段与越界码点：native panic、
/// wasm-gc 裸 unreachable、js 静默容忍，三臂分叉 issue #363 实测）；
/// **尾部不完整保留「截断止」**（serve_io 增量切片靠它保证块界不切
/// 半个字符——下一块续上）。替换计数与 WHATWG 最大子部分规则逐例
/// 对齐（PR #367 审阅 P2-5，基准同 fs 包头注）。与 fs 包 to_utf8_string
/// （整缓冲：非法与截尾全替换 U+FFFD）语义分立，两侧头注互指。
pub fn utf8_text_partial(b : Bytes) -> String {
  let buf = StringBuilder()
  let n = b.length()
  let mut i = 0
  while i < n {
    let c0 = b[i].to_int() & 0xff
    if c0 < 0x80 {
      buf.write_char(c0.unsafe_to_char())
      i += 1
      continue
    }
    if c0 < 0xC2 || c0 > 0xF4 {
      // 孤立延续字节（0x80..0xBF）/ 非法 lead（C0..C1 过长专用 /
      // F5..FF 越界）→ 单字节替换（WHATWG lead 域 C2..F4）
      buf.write_char('\u{FFFD}')
      i += 1
      continue
    }
    let need : Int32 = if c0 < 0xE0 { 2 } else if c0 < 0xF0 { 3 } else { 4 }
    let mask : Int32 = if c0 < 0xE0 {
      0x1F
    } else if c0 < 0xF0 {
      0x0F
    } else {
      0x07
    }
    let cp_min : Int32 = if c0 < 0xE0 {
      0x80
    } else if c0 < 0xF0 {
      0x800
    } else {
      0x10000
    }
    let cp_max : Int32 = if c0 < 0xE0 {
      0x7FF
    } else if c0 < 0xF0 {
      0xFFFF
    } else {
      0x10FFFF
    }
    if i + need > n {
      // 尾部不完整 → 截断止（流式前缀契约：下一块续上，不折替换符）
      break
    }
    // WHATWG 第二字节域（E0/ED/F0/F4 收紧界——PR #367 审阅 P2-5）
    let s_lo : Int32 = if c0 == 0xE0 {
      0xA0
    } else if c0 == 0xF0 {
      0x90
    } else {
      0x80
    }
    let s_hi : Int32 = if c0 == 0xED {
      0x9F
    } else if c0 == 0xF4 {
      0x8F
    } else {
      0xBF
    }
    let mut cp = c0 & mask
    let mut bad_at = -1
    let mut k = 1
    while k < need {
      let bk = b[i + k].to_int()
      let cont_ok = bk >= 0x80 && bk <= 0xBF
      let dom_ok = k != 1 || (bk >= s_lo && bk <= s_hi)
      if !cont_ok || !dom_ok {
        bad_at = k
        break
      }
      cp = (cp << 6) | (bk & 0x3F)
      k += 1
    }
    if bad_at >= 0 {
      // 坏延续字节处重同步：已消费前缀折一个替换符，坏字节下一轮按
      // lead 重判
      buf.write_char('\u{FFFD}')
      i += bad_at
      continue
    }
    i += need
    if cp < cp_min || cp > cp_max || (cp >= 0xD800 && cp <= 0xDFFF) {
      // 兜底（第二字节域拦截后理论不可达——防御性保留，unsafe_to_char
      // 恒安全）
      buf.write_char('\u{FFFD}')
      continue
    }
    // MoonBit Char 是 Unicode 码点（非 UTF-16 码元）——直接写码点，
    // String 内部自管 UTF-16 编码（wbtest 代理对锚抓过手拆形态的错）
    buf.write_char(cp.unsafe_to_char())
  }
  buf.to_string()
}

///|
/// base64 标准字母表解码（#70 第二步，2026-10-11）：memory.dump 帧的
/// bytes_base64 消费侧（CLI 文本模式 --dump-memory 走帧通路后需要）。
/// 与 base64_encode 对偶；非法字符返 None（fail loud——帧数据自产，
/// 出现非法即协议破损）。
pub fn base64_decode(s : String) -> Bytes? {
  fn val(c : Int32) -> Int32? {
    if c >= 'A'.to_int() && c <= 'Z'.to_int() {
      Some(c - 'A'.to_int())
    } else if c >= 'a'.to_int() && c <= 'z'.to_int() {
      Some(c - 'a'.to_int() + 26)
    } else if c >= '0'.to_int() && c <= '9'.to_int() {
      Some(c - '0'.to_int() + 52)
    } else if c == '+'.to_int() {
      Some(62)
    } else if c == '/'.to_int() {
      Some(63)
    } else {
      None
    }
  }
  let n = s.length()
  if n == 0 {
    return Some(b"") // encode(b"") = "" 对偶（空映像）
  }
  if n % 4 != 0 {
    return None
  }
  let cap = n / 4 * 3
  let out : Array[Byte] = Array(capacity=cap)
  let cs = s.to_array()
  let mut i = 0
  while i < n {
    // 4 字符组（尾部 '=' 填充）
    if i + 4 > n {
      return None
    }
    let pad = if cs[i + 2] == '=' && cs[i + 3] == '=' {
      2
    } else if cs[i + 3] == '=' {
      1
    } else {
      0
    }
    let v0 = val(cs[i].to_int())
    let v1 = val(cs[i + 1].to_int())
    let v2 = if pad == 2 { Some(0) } else { val(cs[i + 2].to_int()) }
    let v3 = if pad >= 1 { Some(0) } else { val(cs[i + 3].to_int()) }
    match (v0, v1, v2, v3) {
      (Some(a), Some(b), Some(c), Some(d)) => {
        let x = (a << 18) | (b << 12) | (c << 6) | d
        out.push(((x >> 16) & 0xFF).to_byte())
        if pad < 2 {
          out.push(((x >> 8) & 0xFF).to_byte())
        }
        if pad < 1 {
          out.push((x & 0xFF).to_byte())
        }
      }
      _ => return None
    }
    i += 4
  }
  Some(Bytes::from_array(out))
}
