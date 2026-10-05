///| ctype 族 14 个 handler（Rust `host/misc.rs:21-124` 逐字照搬）。
///
/// 纯函数：入参是弹栈后的字符码（i32 位模式），返回 1/0（谓词）或变换后的
/// 码位。**不含任何内存访问**——与内存/输出无关的 handler 一律不取
/// `HostMemReply`，vm 接线时直接压返回值（勘察 §1.7 族 H）。
///
/// 照搬口径注意：谓词基于**有符号 i32 比较**（Rust `c >= '0' as i32`），
/// 负码位（如 `-56`，即字节 0xC8 经 i32 弹栈）全部落 0。曾登记「glibc
/// 按 256 取模查表非零 vs 此处恒 0」的差异——**2026-10-05 工序① retest
/// 销案**：差异面在 C locale 域实测不存在（十点 ×12 函数全套含负码位/
/// 域外全域，与 Clang 逐位一致；C locale 下 128-255 段表项全零/原值，
/// 镜像取模与原值比较数学恒同——非零形态只存在于非 C locale）。
/// 台账 DIFF-LIB-CTYPE-01 已转 resolved-verified。

///|
/// `isdigit(c)`
pub fn host_isdigit(c : Int) -> Int {
  if c >= 48 && c <= 57 {
    1
  } else {
    0
  }
}

///|
/// `isalpha(c)`
pub fn host_isalpha(c : Int) -> Int {
  if (c >= 97 && c <= 122) || (c >= 65 && c <= 90) {
    1
  } else {
    0
  }
}

///|
/// `islower(c)`
pub fn host_islower(c : Int) -> Int {
  if c >= 97 && c <= 122 {
    1
  } else {
    0
  }
}

///|
/// `isupper(c)`
pub fn host_isupper(c : Int) -> Int {
  if c >= 65 && c <= 90 {
    1
  } else {
    0
  }
}

///|
/// `tolower(c)`——非大写原样返回。
pub fn host_tolower(c : Int) -> Int {
  if c >= 65 && c <= 90 {
    c + 32
  } else {
    c
  }
}

///|
/// `toupper(c)`——非小写原样返回。
pub fn host_toupper(c : Int) -> Int {
  if c >= 97 && c <= 122 {
    c - 32
  } else {
    c
  }
}

///|
/// `isspace(c)`——C 空白集：`' ' '\t' '\n' '\r' '\x0C' '\x0B'`。
pub fn host_isspace(c : Int) -> Int {
  if c == 32 || c == 9 || c == 10 || c == 13 || c == 12 || c == 11 {
    1
  } else {
    0
  }
}

///|
/// `isalnum(c)`
pub fn host_isalnum(c : Int) -> Int {
  if host_isalpha(c) == 1 || host_isdigit(c) == 1 {
    1
  } else {
    0
  }
}

///|
/// `isprint(c)`——可打印区 `[0x20, 0x7E]`。
pub fn host_isprint(c : Int) -> Int {
  if c >= 32 && c <= 126 {
    1
  } else {
    0
  }
}

///|
/// `iscntrl(c)`——`[0,31] ∪ {127}`。
pub fn host_iscntrl(c : Int) -> Int {
  if (c >= 0 && c <= 31) || c == 127 {
    1
  } else {
    0
  }
}

///|
/// `isxdigit(c)`
pub fn host_isxdigit(c : Int) -> Int {
  if host_isdigit(c) == 1 || (c >= 97 && c <= 102) || (c >= 65 && c <= 70) {
    1
  } else {
    0
  }
}

///|
/// `isgraph(c)`——`isprint` 排除空格（`> 0x20`）。
pub fn host_isgraph(c : Int) -> Int {
  if c > 32 && c <= 126 {
    1
  } else {
    0
  }
}

///|
/// `ispunct(c)`——可打印且非字母数字非空格。
pub fn host_ispunct(c : Int) -> Int {
  let is_print = c >= 32 && c <= 126
  let is_alnum = (c >= 97 && c <= 122) ||
    (c >= 65 && c <= 90) ||
    (c >= 48 && c <= 57)
  if is_print && !is_alnum && c != 32 {
    1
  } else {
    0
  }
}

///|
/// `isblank(c)`——`' ' '\t'`。
pub fn host_isblank(c : Int) -> Int {
  if c == 32 || c == 9 {
    1
  } else {
    0
  }
}
