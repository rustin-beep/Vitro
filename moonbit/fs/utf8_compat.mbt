// Copyright 2025 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// ── vendored into vitro/engine/fs（唯一依赖清除 B 路线批，2026-09-28）──
// 来源：moonbitlang/x@0.5.5 的 unicode/utf8.mbt（to_utf8_bytes /
//   to_utf8_string，sha256 770e253ecd23dc38cf15ee40f4960397feefcf369edfbfb050f2a3727c260cdf）
//   与 unicode/basic.mbt（utf16_pair_to_char / char_to_utf16_pair，
//   sha256 75f67d4f6155facc1033d6bae97d887ab2acabc636f5a6eab49637b6eae4b69）。
//   这是 fs_native.mbt 对 x/unicode 的全部消费面——内联进本包后 vendor
//   边界闭合（模块零外部依赖）。
// 改动：① 四函数 pub → priv（本包内部件，对外面零暴露）；② 两个辅助
//   纯函数 shift_char / char_to_utf16_pair 中仅保留被消费的两个
//   （shift_char 零消费不搬）；③ 文件头追加本标注。
//   ④ #363（2026-10-28）：to_utf8_string 重写——非法/不完整序列从
//   0.5.5 的「静默截断尾」改为 **U+FFFD 替换**（每个非法极大子部分一个
//   替换符，上游 main 同向）。翻案动因：本函数是三后端
//   read_file_to_string 的唯一解码口，0.5.5 语义对越界 4 字节序列
//   （如 FF FE 64 65）与代理段编码（ED A0 80）经 unsafe_to_char 产出
//   非法码点——native 运行时 panic、wasm-gc 裸 unreachable、js 静默
//   容忍，同一输入三臂三结局（issue #363 实测）。重写后解码永不产出
//   非法码点（unsafe_to_char 恒安全）。行为锚见 fs_wbtest.mbt
//   「utf8_decode_replaces_malformed_with_ufffd」。与 util 包
//   utf8_text_partial（流式前缀解码——尾部截断止保留、中段非法同样
//   U+FFFD）语义分立，两侧头注互指。

///|
/// Encode a string into UTF-8 bytes.
///
/// The trailing portion of a truncated surrogate pair at the end of the
/// string is ignored.
fn to_utf8_bytes(s : String) -> Bytes {
  let res : Array[Byte] = []
  let len = s.length()
  let mut i = 0
  while i < len {
    let mut c = s.code_unit_at(i).to_int()
    if c.is_leading_surrogate() {
      i = i + 1
      let l = s.code_unit_at(i).to_int()
      c = utf16_pair_to_char(c, l).unwrap().to_int()
    }

    if c < 0x80 {
      res.push(c.to_byte())
    } else if c < 0x800 {
      res.push((0xc0 + (c >> 6)).to_byte())
      res.push((0x80 + (c & 0x3f)).to_byte())
    } else if c < 0x10000 {
      res.push((0xe0 + (c >> 12)).to_byte())
      res.push((0x80 + ((c >> 6) & 0x3f)).to_byte())
      res.push((0x80 + (c & 0x3f)).to_byte())
    } else {
      res.push((0xf0 + (c >> 18)).to_byte())
      res.push((0x80 + ((c >> 12) & 0x3f)).to_byte())
      res.push((0x80 + ((c >> 6) & 0x3f)).to_byte())
      res.push((0x80 + (c & 0x3f)).to_byte())
    }
    i = i + 1
  }
  Bytes::from_array(res)
}

///|
/// Decode UTF-8 bytes into a string.
///
/// #363（2026-10-28）：非法/不完整序列以 U+FFFD 替换（每个非法极大
/// 子部分一个替换符）——孤立延续字节与越界 lead（≥0xF8）各占一个
/// 替换符；序列内首个坏延续字节处重同步（坏字节自身下一轮按 lead
/// 重判）；延续字节合法但码点非法（过长/代理段/超上限）时整个序列
/// 折一个替换符；尾部不完整折一个替换符止。解码永不产出非法码点。
fn to_utf8_string(bytes : Bytes) -> String {
  let res : Array[Char] = []
  let len = bytes.length()
  let mut i = 0
  while i < len {
    let b0 = bytes[i].to_int()
    if b0 < 0x80 {
      res.push(Int32::unsafe_to_char(b0))
      i += 1
      continue
    }
    if b0 < 0xC0 || b0 >= 0xF8 {
      // 孤立延续字节（0x80..0xBF）/ 非 lead 域（0xF8..0xFF）→ 单字节替换
      res.push('\u{FFFD}')
      i += 1
      continue
    }
    let need : Int32 = if b0 < 0xE0 { 2 } else if b0 < 0xF0 { 3 } else { 4 }
    let mask : Int32 = if b0 < 0xE0 {
      0x1F
    } else if b0 < 0xF0 {
      0x0F
    } else {
      0x07
    }
    let cp_min : Int32 = if b0 < 0xE0 {
      0x80
    } else if b0 < 0xF0 {
      0x800
    } else {
      0x10000
    }
    let cp_max : Int32 = if b0 < 0xE0 {
      0x7FF
    } else if b0 < 0xF0 {
      0xFFFF
    } else {
      0x10FFFF
    }
    if i + need > len {
      // 尾部不完整（整缓冲语境 = 非法截断）→ 一个替换符止
      res.push('\u{FFFD}')
      break
    }
    let mut cp = b0 & mask
    let mut bad_at = -1
    let mut k = 1
    while k < need {
      let bk = bytes[i + k].to_int()
      if bk < 0x80 || bk >= 0xC0 {
        bad_at = k
        break
      }
      cp = (cp << 6) | (bk & 0x3F)
      k += 1
    }
    if bad_at >= 0 {
      // 坏延续字节处重同步：已消费前缀折一个替换符，坏字节下一轮按
      // lead 重判（多数形态即孤立延续 → 自占一个替换符）
      res.push('\u{FFFD}')
      i += bad_at
      continue
    }
    i += need
    if cp < cp_min || cp > cp_max || (cp >= 0xD800 && cp <= 0xDFFF) {
      // 过长编码 / 独立代理段 / 超出 Unicode 上限（F4..F7 lead 可组出
      // >0x10FFFF）——形态完整但码点非法，整个序列折一个替换符
      res.push('\u{FFFD}')
      continue
    }
    if cp > 0xFFFF {
      match char_to_utf16_pair(Int32::unsafe_to_char(cp)) {
        Some((hi, lo)) => {
          res.push(Int32::unsafe_to_char(hi))
          res.push(Int32::unsafe_to_char(lo))
        }
        None => res.push('\u{FFFD}')
      }
    } else {
      res.push(Int32::unsafe_to_char(cp))
    }
  }
  String::from_array(res)
}

///|
/// Combine a UTF-16 leading surrogate `hi` and trailing surrogate `lo` into
/// a char, or `None` if the code units are not a valid surrogate pair.
fn utf16_pair_to_char(hi : Int32, lo : Int32) -> Char? {
  guard hi.is_leading_surrogate() && lo.is_trailing_surrogate() else { None }
  Some(Int32::unsafe_to_char((hi << 10) + lo - 0x35fdc00))
}

///|
/// Split a supplementary (astral) char into its UTF-16 leading and trailing
/// surrogate code units, or `None` if the char fits in a single code unit.
fn char_to_utf16_pair(ch : Char) -> (Int32, Int32)? {
  let c = ch.to_int()
  if c > 0xFFFF {
    let v = c - 0x10000
    Some((0xD800 + (v >> 10), 0xDC00 + (v & 0x3FF)))
  } else {
    None
  }
}
