///| L6 产物层·**C 字符串字节通道单源**（P4 口径照搬——Rust `vitro_shared::cstring`）。
///
/// **码点 ≤ 0xFF 的字符按 Latin-1 单字节写出，> 0xFF 的按 UTF-8 编码写出**。
/// 无歧义依据：源文件按 UTF-8 解码，多字节源字符码点必然 > 0xFF；码点
/// 落在 U+0080..=U+00FF 的只可能来自 `\xHH` 转义。已知差异（诚实记录）：
/// 源内直接书写的高位单字节字符写单字节，与 clang UTF-8 execution
/// charset 不同；中文等多字节源字符不受影响，按 UTF-8 写。
///
/// **单源义务（S6 vm 批一号上提）**：本口径原 priv 在 L6 `codegen/init.mbt`
/// （字符串延迟回填 P2 的私有实现）；vm 片 argv 区域装载需要同一字节口径
/// （`argv_region_footprint` + 参数串写入），跨 L6/L7 复用须上提为独立
/// 单源——定义点唯一在本包（L6 产物层，codegen 同层消费、vm 向下消费，
/// 依赖方向合法），两侧禁再私写。

///|
/// C 字符串字节序列（不含结尾 NUL）。
pub fn cstring_bytes(s : String) -> Array[Byte] {
  let out : Array[Byte] = []
  for c in s {
    let cp = c.to_int()
    if cp <= 0xFF {
      out.push(cp.to_byte())
    } else {
      // 码点 > 0xFF：按 UTF-8 编码写出（2~4 字节）
      for b in @utf8.encode(c.to_string()) {
        out.push(b)
      }
    }
  }
  out
}

///|
/// C 语义字节长度（不含结尾 NUL）——分配/对齐计算用。与 MoonBit
/// `String::length()`（UTF-16 码元数）在含 `\xHH ≥ 0x80` 转义时不同（F2）。
pub fn cstring_len(s : String) -> Int {
  let mut total = 0
  for c in s {
    let cp = c.to_int()
    if cp <= 0xFF {
      total += 1
    } else {
      total += @util.utf8_len(c.to_string())
    }
  }
  total
}
