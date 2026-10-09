///| 字符串→数值族 6 个 handler（Rust `host/misc.rs` 照搬，勘察 §1.7 族 F）。
///
/// **扫描管道的等价性论证（照搬依据；atof 条目 2026-10-05 批二-a 修复后翻转）**：
/// - `atoi`/`atol`：oracle 走 `read_cstring`（lossy String）→ **Unicode**
///   `trim_start` → 逐 char 累加。此处字节级实现——**登记微差**：多字节
///   Unicode 空白前缀（NBSP `C2 A0` 等）oracle 会裁掉、此处不裁（字节
///   ≥ 0x80 一律非空白非数字即停）；ASCII 域逐位一致，语料形状不受影响。
/// - `atof`：**已修（批二-a）**——前缀扫描只跳 ASCII 空白（与 C `isspace`
///   域一致）；oracle 的 Unicode trim 对 NBSP 前缀的裁剪才是偏差（随
///   Rust 退役收敛，无需对齐）。
/// - `strtol`/`strtod`：oracle 虽也经 lossy String，但扫描用的是
///   `bytes[pos].is_ascii_whitespace()`（**只跳 ASCII 空白**）与 ASCII 数字
///   判定——多字节序列在 lossy 串里同样不被跳过、不构成数字 ⟹ **字节级
///   扫描与 oracle 逐位等价**（token 内只可能出现 ASCII，parse 输入相同）。
///
/// `errno` 解耦：oracle `set_errno` 查符号表写全局 `errno`（VM 耦合）——
/// 此处以 `errno_addr : UInt?` 参数化（vm 接线时解析符号地址传入；`None`
/// = 无 errno 符号，等价 oracle 查不到时的静默不写）。写入失败**照搬静默
/// 忽略**（oracle `let _ = vm.write_memory(...)`）。
///
/// **atof 整串 parse（与 C 的已知偏差，oracle 既有）**：`"12abc"` 整串
/// parse 失败 → 0.0（C 的 `atof` 会取前缀 `12.0`）——oracle 现状照搬，
/// 差异台账 S8 收编。

///|
/// `atoi(s)`（oracle `misc.rs:126-149`）——i32 回绕累加，结果符号扩展压栈。
pub fn host_atoi(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  addr : UInt,
) -> HostMemReply {
  let s = read_cstring_raise(mem, map, addr) catch {
    AccessFault::Fault(f~) => return fault_reply(f)
  }
  value_only(atoi_bytes(s).to_int64().reinterpret_as_uint64())
}

///|
/// 字节级 `atoi`：跳 ASCII 空白 → 可选符号 → 数字回绕累加（`atoi`/`atol`
/// 共用，宽度由参数化乘法承载——见 `atol_bytes`）。
fn atoi_bytes(s : Bytes) -> Int {
  let n = s.length()
  let mut pos = 0
  while pos < n && is_ascii_ws_byte(s[pos]) {
    pos = pos + 1
  }
  let mut sign = 1
  if pos < n {
    if s[pos] == b'-' {
      sign = -1
      pos = pos + 1
    } else if s[pos] == b'+' {
      pos = pos + 1
    }
  }
  let mut val = 0
  while pos < n {
    let c = s[pos]
    if c >= b'0' && c <= b'9' {
      val = val * 10 + (c.to_int() - 48)
      pos = pos + 1
    } else {
      break
    }
  }
  sign * val
}

///|
/// ASCII 空白字节集（Rust `char::is_whitespace` 的 ASCII 子集：
/// `\t \n \x0B \x0C \r space`）。
fn is_ascii_ws_byte(b : Byte) -> Bool {
  let v = b.to_int()
  (v >= 9 && v <= 13) || v == 32
}

///|
/// hex 数字字节值（'0'-'9'/'a'-'f'/'A'-'F' → 0-15；非 hex → -1）。
/// scanf %i/%x 扫描与 strtoul 前缀判定共用（病 9，#47 2026-10-09）。
fn hex_digit_val(b : Byte) -> Int {
  if b >= 48 && b <= 57 {
    b.to_int() - 48
  } else if b >= 97 && b <= 102 {
    b.to_int() - 97 + 10
  } else if b >= 65 && b <= 70 {
    b.to_int() - 65 + 10
  } else {
    -1
  }
}

///|
/// `atol(s)`（oracle `misc.rs:336-359`）——i64 回绕累加。
pub fn host_atol(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  addr : UInt,
) -> HostMemReply {
  let s = read_cstring_raise(mem, map, addr) catch {
    AccessFault::Fault(f~) => return fault_reply(f)
  }
  value_only(atol_bytes(s).reinterpret_as_uint64())
}

///|
/// 字节级 `atol`（i64 回绕；符号乘法回绕语义与 Rust `wrapping_mul` 同——
/// `sign * INT64_MIN` 回绕为自身，位模式一致）。
fn atol_bytes(s : Bytes) -> Int64 {
  let n = s.length()
  let mut pos = 0
  while pos < n && is_ascii_ws_byte(s[pos]) {
    pos = pos + 1
  }
  let mut sign = 1L
  if pos < n {
    if s[pos] == b'-' {
      sign = -1L
      pos = pos + 1
    } else if s[pos] == b'+' {
      pos = pos + 1
    }
  }
  let mut val = 0L
  while pos < n {
    let c = s[pos]
    if c >= b'0' && c <= b'9' {
      val = val * 10L + (c.to_int() - 48).to_int64()
      pos = pos + 1
    } else {
      break
    }
  }
  sign * val
}

///|
/// 字节 → 数字值（非字母数字 → -1；进位域判定由调用方负责）。
fn digit_value(c : Byte) -> Int {
  let v = c.to_int()
  if v >= 48 && v <= 57 {
    v - 48
  } else if v >= 97 && v <= 122 {
    v - 97 + 10
  } else if v >= 65 && v <= 90 {
    v - 65 + 10
  } else {
    -1
  }
}

///|
/// 浮点 token 前缀扫描（C strtod 语义，C99 §6.4.4.2 两形态）：跳 ASCII
/// 空白 → 可选符号 → **十进制**（数字/小数点一次/eE 指数一次）或 **hex
/// float**（`0x`+hex 数字 ≥1 → hex 数字/[.]/[pP 带符号十进制指数]）——
/// **悬空指数回退**（`e`/`e+`/`e-`/`p`… 后无数字则不消费，最长**合法**
/// 前缀语义——审阅 P2-1 补强）；atof ≡ strtod(str, NULL)（C §7.22.1.1）
/// 的公共扫描器；返回 (token 字节, 消费位数)。
/// 2026-10-05 批二-a 自 strtod 内联体抽出；同日审阅处置补悬空回退+hex。
fn scan_float_token(s : Bytes) -> (Array[Byte], Int) {
  let n = s.length()
  let mut pos = 0
  while pos < n && is_ascii_ws_byte(s[pos]) {
    pos = pos + 1
  }
  let start = pos
  if pos < n && (s[pos] == b'+' || s[pos] == b'-') {
    pos = pos + 1
  }
  // hex float 探测：0x/0X 后（hex 数字 | '.'+hex 数字——C99 hex-fraction
  // 可无整数位，"0x.8p1"）至少一位才成立（否则回退十进制，如 "0x" → "0"）
  let hex_probe = pos + 2 < n &&
    s[pos] == b'0' &&
    (s[pos + 1] == b'x' || s[pos + 1] == b'X') &&
    (
      is_hex_digit(s[pos + 2]) ||
      (s[pos + 2] == b'.' && pos + 3 < n && is_hex_digit(s[pos + 3]))
    )
  if hex_probe {
    pos = pos + 2
    while pos < n && is_hex_digit(s[pos]) {
      pos = pos + 1
    }
    if pos < n && s[pos] == b'.' {
      // hex 小数：点后须有 hex 数字，否则点不消费（"0x1." → "0x1"）
      if pos + 1 < n && is_hex_digit(s[pos + 1]) {
        pos = pos + 1
        while pos < n && is_hex_digit(s[pos]) {
          pos = pos + 1
        }
      }
    }
    // p 指数（可选，悬空回退）
    if pos < n && (s[pos] == b'p' || s[pos] == b'P') {
      let exp_start = pos
      pos = pos + 1
      if pos < n && (s[pos] == b'+' || s[pos] == b'-') {
        pos = pos + 1
      }
      if pos < n && s[pos] >= b'0' && s[pos] <= b'9' {
        while pos < n && s[pos] >= b'0' && s[pos] <= b'9' {
          pos = pos + 1
        }
      } else {
        pos = exp_start
      }
    }
  } else {
    // 十进制形态：数字/小数点（一次）/eE 指数（一次，后可带符号）
    let mut has_dot = false
    let mut exp_start = -1
    while pos < n {
      let c = s[pos]
      if c >= b'0' && c <= b'9' {
        pos = pos + 1
      } else if c == b'.' && !has_dot {
        has_dot = true
        pos = pos + 1
      } else if (c == b'e' || c == b'E') && exp_start < 0 {
        exp_start = pos
        pos = pos + 1
        if pos < n && (s[pos] == b'+' || s[pos] == b'-') {
          pos = pos + 1
        }
      } else {
        break
      }
    }
    // 悬空指数回退：e（及可选符号）后无数字 → token 截到 e 前
    //（"1e"→"1"、"1e+"→"1"；合法指数 "1e2" 不受影响）
    if exp_start >= 0 {
      let mut j = exp_start + 1
      if j < n && (s[j] == b'+' || s[j] == b'-') {
        j = j + 1
      }
      if j >= pos {
        pos = exp_start
      }
    }
  }
  let token : Array[Byte] = []
  let mut i = start
  while i < pos {
    token.push(s[i])
    i = i + 1
  }
  (token, pos)
}

///|
/// 浮点 token 值计算：十进制形态走 parse_double；hex float 形态
///（`0x` mantissa + 可选 `p` 二进制指数）自算——mantissa hex 逐位累加
///（≤2^53 域内 Double 精确）、小数段 16^-k 缩放累加、指数 2^p
///（`@math.pow` 整数幂精确）。正确舍入（C 的 correctly-rounded）不做——
/// 教学域精度取舍，登记。
fn parse_float_token(token : Array[Byte]) -> Double {
  let len = token.length()
  let mut off = 0
  let neg = len > 0 && token[0] == b'-'
  if len > 0 && (token[0] == b'+' || token[0] == b'-') {
    off = 1
  }
  let is_hex = len - off >= 3 &&
    token[off] == b'0' &&
    (token[off + 1] == b'x' || token[off + 1] == b'X')
  let sign : Double = if neg { -1.0 } else { 1.0 }
  if is_hex {
    let mut i = off + 2
    let mut mant = 0.0
    while i < len && is_hex_digit(token[i]) {
      mant = mant * 16.0 + digit_value(token[i]).to_double()
      i = i + 1
    }
    if i < len && token[i] == b'.' {
      i = i + 1
      let mut scale = 1.0 / 16.0
      while i < len && is_hex_digit(token[i]) {
        mant = mant + digit_value(token[i]).to_double() * scale
        scale = scale / 16.0
        i = i + 1
      }
    }
    let mut val = mant
    if i < len && (token[i] == b'p' || token[i] == b'P') {
      i = i + 1
      let mut esign = 1
      if i < len && token[i] == b'+' {
        i = i + 1
      } else if i < len && token[i] == b'-' {
        esign = -1
        i = i + 1
      }
      let mut ev = 0
      while i < len && token[i] >= b'0' && token[i] <= b'9' {
        ev = ev * 10 + (token[i].to_int() - 48)
        i = i + 1
      }
      val = mant * @math.pow(2.0, (esign * ev).to_double())
    }
    sign * val
  } else {
    @string.parse_double(@utf8.decode_lossy(Bytes::from_array(token))) catch {
      _ => 0.0
    }
  }
}

///|
fn is_hex_digit(c : Byte) -> Bool {
  let d = digit_value(c)
  d >= 0 && d < 16
}

///|
/// `atof(s)`（C §7.22.1.1：atof(str) ≡ strtod(str, NULL)）——取最长浮点
/// 前缀 parse（`"12abc"` → 12.0）。DIFF-LIB-ATOF-01 销案（2026-10-05
/// 批二-a）：旧「两端裁剪后整串 parse，失败 → 0.0」系 oracle 照搬（与 C
/// 取前缀语义的偏差在案）；脱钩后回归 C 语义，扫描器与 strtod 单源。
pub fn host_atof(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  addr : UInt,
) -> HostMemReply {
  let s = read_cstring_raise(mem, map, addr) catch {
    AccessFault::Fault(f~) => return fault_reply(f)
  }
  let (token, _) = scan_float_token(s)
  let val : Double = parse_float_token(token)
  value_only(val.reinterpret_as_uint64())
}

///|
/// `strtol(str, endptr, base)`（C §7.22.1.4）。
/// **endptr 位点差异记录**（2026-10-06 审阅 P3-2，纪律 4）："0x"/"0x!"
/// 无有效十六进制数字形态下 base=0 的 endptr 偏移——Clang(UCRT) `off=0`
/// vs 本实现 `off=1`（只消费 '0'；返回值两侧全对，C 标准 §7.22.1.4 的
/// subject sequence 口径**本实现更对**——"0x" 无后继数字时序列即 "0"，
/// endptr 应指向 x 之后=1；UCRT 形态属实现差异）——不对齐 UCRT，差异
/// 在案。**base=0 前缀探测**：
/// `0x`/`0X`+十六进制数字 → 16、`0` 前缀 → 8、否则 10；**base=16 允许
/// 可选 `0x`/`0X` 前缀**（`0x` 后无数字则回退为只消费 `'0'`）。
/// 2026-10-05 批二-a 修复（#47 新病销案）：旧「base=0 恒 10、base=16
/// 不剥 0x」系 oracle 照搬在案。无数字时写 `errno=1`（EINVAL）。
/// `endptr` 非 NULL 时写入停止位（str 起始 + 扫描位数）。
pub fn host_strtol(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  str_addr : UInt,
  endptr_addr : UInt,
  base : Int,
  errno_addr : UInt?,
) -> HostMemReply {
  let s = read_cstring_raise(mem, map, str_addr) catch {
    AccessFault::Fault(f~) => return fault_reply(f)
  }
  let n = s.length()
  let mut pos = 0
  while pos < n && is_ascii_ws_byte(s[pos]) {
    pos = pos + 1
  }
  let mut sign = 1L
  if pos < n {
    if s[pos] == b'-' {
      sign = -1L
      pos = pos + 1
    } else if s[pos] == b'+' {
      pos = pos + 1
    }
  }
  let start_pos = pos
  let mut val = 0L
  // 前缀探测（C §7.22.1.4 subject sequence；0x 后无有效数字不消费 x）。
  // digit_value 越界值 -1 不可当合法十六进制（审阅 P3-4：旧 `< 16` 把
  // "0x!" 的 '!' 探测成有效——is_hex_digit 单源判定）
  let effective_base : Int = if base == 0 {
    if pos + 1 < n &&
      s[pos] == b'0' &&
      (s[pos + 1] == b'x' || s[pos + 1] == b'X') &&
      pos + 2 < n &&
      is_hex_digit(s[pos + 2]) {
      pos = pos + 2
      16
    } else if pos < n && s[pos] == b'0' {
      8
    } else {
      10
    }
  } else if base == 16 {
    if pos + 1 < n &&
      s[pos] == b'0' &&
      (s[pos + 1] == b'x' || s[pos + 1] == b'X') &&
      pos + 2 < n &&
      is_hex_digit(s[pos + 2]) {
      pos = pos + 2
    }
    16
  } else {
    base
  }
  let eff = effective_base.to_int64()
  while pos < n {
    let digit = digit_value(s[pos])
    if digit < 0 || digit.to_int64() >= eff {
      break
    }
    val = val * eff + digit.to_int64()
    pos = pos + 1
  }
  if pos == start_pos {
    // EINVAL（写入失败照搬 oracle 静默忽略）
    match errno_addr {
      Some(a) =>
        match mem.store_u32(map, a, 1U) {
          Ok(_) => ()
          Err(_) => ()
        }
      None => ()
    }
  }
  if endptr_addr != 0U {
    let _ = mem.store_u32(
      map,
      endptr_addr,
      str_addr + pos.reinterpret_as_uint(),
    )
  }
  value_only((sign * val).reinterpret_as_uint64())
}

///|
/// `strtod(str, endptr)`（oracle `misc.rs:417-459`）——token 扫描：可选
/// 符号 → 数字/小数点（一次）/指数（一次，后可带符号）；token 内只可能是
/// ASCII（扫描集决定）。无数字时写 `errno=1`。
pub fn host_strtod(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  str_addr : UInt,
  endptr_addr : UInt,
  errno_addr : UInt?,
) -> HostMemReply {
  let s = read_cstring_raise(mem, map, str_addr) catch {
    AccessFault::Fault(f~) => return fault_reply(f)
  }
  // 扫描器与 atof 单源（2026-10-05 批二-a 抽出；值计算同用 parse_float_token
  //——含 hex float/悬空回退，审阅 P2-1 补强）
  let (token, pos) = scan_float_token(s)
  let val : Double = parse_float_token(token)
  if token.is_empty() {
    match errno_addr {
      Some(a) =>
        match mem.store_u32(map, a, 1U) {
          Ok(_) => ()
          Err(_) => ()
        }
      None => ()
    }
  }
  if endptr_addr != 0U {
    let _ = mem.store_u32(
      map,
      endptr_addr,
      str_addr + pos.reinterpret_as_uint(),
    )
  }
  value_only(val.reinterpret_as_uint64())
}

///|
/// `strerror(errnum)`（oracle `misc.rs:461-519`）——分配三步契约同
/// `strdup`；**消息字节数含内嵌 NUL**（oracle 字面量 `\0` 计入 `size`/
/// 对齐/写入——勘察 §3.2-9 的"易错点"在此显式保留）。
///
/// 与 oracle 的元数据微差（登记）：区域 `ty` 经 memory 包 `register_alloc`
/// 的 `auto_name` 形态落 `"int"`（oracle 手写 `"char"`）——符号表诊断面
/// 差异，不影响 stdout/返回值对拍。
pub fn host_strerror(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  errnum : Int,
  alloc_line : Int,
) -> HostMemReply {
  let msg : Bytes = match errnum {
    1 => b"Invalid argument\x00"
    2 => b"Numerical result out of range\x00"
    3 => b"Domain error\x00"
    4 => b"No such file or directory\x00"
    5 => b"Permission denied\x00"
    _ => b"Unknown error\x00"
  }
  let size = msg.length()
  let aligned = @bytecode.align4(size.reinterpret_as_uint())
  let addr = match map.allocate_raw(aligned, @bytecode.MEM_SIZE) {
    Some(a) => a
    None => return null_silent()
  }
  map.freed_logs_remove_overlapping(addr, addr + aligned)
  map.register_alloc(addr, size, alloc_line, "strerror", true)
  match mem.write_bytes(map, addr, msg) {
    Ok(_) => value_only(addr.to_uint64())
    // oracle 对该"理论不可达"失败显式 trap（非静默——审阅 P1-b 定的口径）
    Err(_) => trap_only("strerror: 输出缓冲写入失败")
  }
}
