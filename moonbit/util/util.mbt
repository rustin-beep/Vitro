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

///|
/// String 的 UTF-8 字节长度（与 Rust `String::len()` 同口径；与
/// `String::length()` 的码元数区分——多字节字符两者不等）。
///
/// 非法 UTF-8 的现状照 `@utf8.encode` 语义（静默产空串 ⇒ 长度 0），
/// 本包不新增判定——「非法 UTF-8 怎么算」的审计点只有这里。
pub fn utf8_len(s : String) -> Int {
  @utf8.encode(s).length()
}

///|
/// 字典序比较（负/零/正）。**禁用 `String::compare` / `<` `>`**——MoonBit
/// 内置 String 比较实测非字典序（`"delta" > "charlie"` 为 false，疑似长度
/// 优先；陷阱 #29），与 Go canonicalize 的键排序（sort.Strings，字节字典序）
/// 不一致。本函数按 UTF-16 码元逐位比较 + 短者小——键域为 C 标识符
/// （ASCII），与 UTF-8 字节字典序在此域等价。
pub fn str_cmp(a : String, b : String) -> Int {
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
pub fn i64_to_i32_bits(v : Int64) -> Int {
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
pub fn le_u32_at(bytes : FixedArray[Byte], off : Int) -> UInt {
  bytes[off].to_uint() |
  (bytes[off + 1].to_uint() << 8) |
  (bytes[off + 2].to_uint() << 16) |
  (bytes[off + 3].to_uint() << 24)
}

///|
/// 小端八字节拼装读（同 `le_u32_at`，u64 位宽）。
pub fn le_u64_at(bytes : FixedArray[Byte], off : Int) -> UInt64 {
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
/// UTF-8 字节序列解码——**最长合法前缀，截断尾静默止**（`utf8_text` 的
/// 宽容变体：malformed/截断不 abort，返回已解码前缀）。消费场景 = 游标
/// 可落在多字节序列中间的字节域切片（gateway output.delta 的 note 通道
/// cursor 增量；CLI note 聚合同款先例）。实现自 cmd/lib/cli `utf8_decode`
/// 上提（三态锚随迁 util_wbtest）：ASCII 单字节 / 2–4 字节序列按续位
/// 拼码点（Char = Unicode 码点，代理对由 String 内管）；**不校验续位
/// 前缀字节合法性**（0xC0 0x41 会被拼出 U+041——宽容域语义，引擎文本
/// 域实际恒合法，前缀截断是唯一现实形态）。
pub fn utf8_text_partial(b : Bytes) -> String {
  let buf = StringBuilder()
  let n = b.length()
  let mut i = 0
  while i < n {
    let c0 = b[i].to_int() & 0xff
    if c0 < 0x80 {
      buf.write_char(c0.unsafe_to_char())
      i += 1
    } else if c0 < 0xe0 && i + 1 < n {
      let c1 = b[i + 1].to_int() & 0x3f
      buf.write_char((((c0 & 0x1f) << 6) | c1).unsafe_to_char())
      i += 2
    } else if c0 < 0xf0 && i + 2 < n {
      let c1 = b[i + 1].to_int() & 0x3f
      let c2 = b[i + 2].to_int() & 0x3f
      buf.write_char((((c0 & 0x0f) << 12) | (c1 << 6) | c2).unsafe_to_char())
      i += 3
    } else if i + 3 < n {
      let c1 = b[i + 1].to_int() & 0x3f
      let c2 = b[i + 2].to_int() & 0x3f
      let c3 = b[i + 3].to_int() & 0x3f
      let cp = ((c0 & 0x07) << 18) | (c1 << 12) | (c2 << 6) | c3
      // MoonBit Char 是 Unicode 码点（非 UTF-16 码元）——直接写码点，
      // String 内部自管 UTF-16 编码（wbtest 代理对锚抓过手拆形态的错）
      buf.write_char(cp.unsafe_to_char())
      i += 4
    } else {
      break
    }
  }
  buf.to_string()
}
