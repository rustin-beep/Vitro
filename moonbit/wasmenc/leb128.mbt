///|
/// LEB128 变长整数编解码（L0 机械件，wasm 二进制格式的数值底座）。
///
/// wasm 用两种 LEB128：uleb（段长/索引/计数——u32/u64 域非负）与
/// sleb（i32.const/i64.const 立即数——i32/i64 域）。编码容器一律
/// `UInt64`/`Int64`（全域安全），调用方负责域收窄；解码侧对截断
/// （字节流末尾续位悬空）fail loud——探针 2 实测形态（SLEB_TRUNCATED
/// 是「非自家发射产物拒载」的一类合法红）。
///
/// 探针蓝本：`rehost-probe/src/wasmcode.mjs` uleb/sleb/decodeSleb/decodeUleb
/// （BigInt 安全语义 → MoonBit Int64/UInt64 原生同构，无需位拼装）。

///|
/// uleb128 编码（非负值；容器 UInt64 全域安全）。
pub fn uleb_encode(value : UInt64) -> Array[Byte] {
  let mut n = value
  let out : Array[Byte] = []
  while true {
    let b = (n & 0x7FUL).to_uint().reinterpret_as_int().to_byte()
    n = n >> 7
    if n != 0UL {
      out.push(b | (0x80).to_byte())
    } else {
      out.push(b)
      break
    }
  }
  out
}

///|
/// sleb128 编码（Int64 容器；BigInt 算术右移语义 → MoonBit `>>` 对有符号
/// 整数即算术移位，同构）。8192 编码 3 字节（第二字节符号位 0x40 置位必须
/// 续写）——探针坑位 6 的编码侧正解。
pub fn sleb_encode(value : Int64) -> Array[Byte] {
  let mut n = value
  let out : Array[Byte] = []
  while true {
    let b = (n & 0x7FL).to_int().to_byte()
    n = n >> 7
    let sign = (b & 0x40) != 0b0
    if (n == 0L && !sign) || (n == -1L && sign) {
      out.push(b)
      break
    }
    out.push(b | (0x80).to_byte())
  }
  out
}

///|
/// LEB128 解码错误（fail loud 载体——折叠侧拒载的外部形态）。
pub(all) enum LebError {
  /// 字节流在续位悬空处耗尽（截断的操作数——非完整模板字节）
  Truncated
  /// u64 域超过 10 字节仍未见终止（非法编码）
  TooLong
}

///|
/// uleb128 解码：返回 (值, 消费字节数)。`bytes[pos..]` 视角，越界即
/// Truncated（调用方把错误翻译成折叠 fail loud，不静默截断）。
pub fn uleb_decode(
  bytes : Array[Byte],
  pos : Int32,
) -> Result[(UInt64, Int32), LebError] {
  let mut result = 0UL
  let mut shift = 0
  let mut i = pos
  while true {
    if i >= bytes.length() {
      return Err(Truncated)
    }
    if shift >= 64 {
      return Err(TooLong)
    }
    let b = bytes[i].to_uint64()
    result = result | ((b & 0x7FUL) << shift)
    i = i + 1
    shift = shift + 7
    if (b & 0x80UL) == 0UL {
      return Ok((result, i - pos))
    }
  }
  // 不可达（所有终止路径上方 return）——类型完备出口
  Err(TooLong)
}

///|
/// sleb128 解码：返回 (值, 消费字节数)。符号扩展按终止字节的 0x40 位
///（探针 decodeSleb 同构；容器 Int64，调用方按指令立即数域收窄）。
pub fn sleb_decode(
  bytes : Array[Byte],
  pos : Int32,
) -> Result[(Int64, Int32), LebError] {
  let mut result = 0L
  let mut shift = 0
  let mut i = pos
  let mut last = 0b0
  while true {
    if i >= bytes.length() {
      return Err(Truncated)
    }
    if shift >= 64 {
      return Err(TooLong)
    }
    let b = bytes[i].to_int()
    last = b & 0x7F
    result = result | (last.to_int64() << shift)
    i = i + 1
    shift = shift + 7
    if (b & 0x80) == 0 {
      break
    }
  }
  // 符号扩展：终止字节 bit6 置位且未满 64 位 → 负数补高位
  if shift < 64 && (last & 0x40) != 0 {
    result = result | (-1L << shift)
  }
  Ok((result, i - pos))
}
