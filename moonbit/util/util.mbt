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
