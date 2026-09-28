// Copyright 2025 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
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
//   sha256 75f67d4f6155facc1033be6ae97d887ab2acabc636f5a6eab49237b6eae6b69d）。
//   这是 fs_native.mbt 对 x/unicode 的全部消费面——内联进本包后 vendor
//   边界闭合（模块零外部依赖）。
// 改动：① 四函数 pub → priv（本包内部件，对外面零暴露）；② 两个辅助
//   纯函数 shift_char / char_to_utf16_pair 中仅保留被消费的两个
//   （shift_char 零消费不搬）；③ 文件头追加本标注。函数体逐字未动。
// ⚠️ 行为分界锚（0.5.5 vs 上游 main）：to_utf8_string 对**非法 UTF-8 输入**
//   静默截断尾部（见函数注释 NOTE），上游 main 已改为 U+FFFD 替换——本包
//   保持 0.5.5 语义，分界锚见 fs_wbtest.mbt。

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
/// NOTE: an incomplete or malformed sequence at the end of the input is
/// silently truncated.
fn to_utf8_string(bytes : Bytes) -> String {
  let res : Array[Char] = []
  let len = bytes.length()
  let mut i = 0
  while i < len {
    let mut c = bytes[i].to_int()
    if c < 0x80 {
      res.push(Int::unsafe_to_char(c))
      i += 1
    } else if c < 0xE0 {
      if i + 1 >= len {
        break
      }
      c = ((c & 0x1F) << 6) | (bytes[i + 1].to_int() & 0x3F)
      res.push(Int::unsafe_to_char(c))
      i += 2
    } else if c < 0xF0 {
      if i + 2 >= len {
        break
      }
      c = ((c & 0x0F) << 12) |
        ((bytes[i + 1].to_int() & 0x3F) << 6) |
        (bytes[i + 2].to_int() & 0x3F)
      res.push(Int::unsafe_to_char(c))
      i += 3
    } else {
      if i + 3 >= len {
        break
      }
      c = ((c & 0x07) << 18) |
        ((bytes[i + 1].to_int() & 0x3F) << 12) |
        ((bytes[i + 2].to_int() & 0x3F) << 6) |
        (bytes[i + 3].to_int() & 0x3F)
      match char_to_utf16_pair(Int::unsafe_to_char(c)) {
        Some((hi, lo)) => {
          res.push(Int::unsafe_to_char(hi))
          res.push(Int::unsafe_to_char(lo))
          i += 4
        }
        None => break
      }
    }
  }
  String::from_array(res)
}

///|
/// Combine a UTF-16 leading surrogate `hi` and trailing surrogate `lo` into
/// a char, or `None` if the code units are not a valid surrogate pair.
fn utf16_pair_to_char(hi : Int, lo : Int) -> Char? {
  guard hi.is_leading_surrogate() && lo.is_trailing_surrogate() else { None }
  Some(Int::unsafe_to_char((hi << 10) + lo - 0x35fdc00))
}

///|
/// Split a supplementary (astral) char into its UTF-16 leading and trailing
/// surrogate code units, or `None` if the char fits in a single code unit.
fn char_to_utf16_pair(ch : Char) -> (Int, Int)? {
  let c = ch.to_int()
  if c > 0xFFFF {
    let v = c - 0x10000
    Some((0xD800 + (v >> 10), 0xDC00 + (v & 0x3FF)))
  } else {
    None
  }
}
