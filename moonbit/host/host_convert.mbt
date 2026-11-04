// 蓝本注记：文内 Rust 源引用（`*.rs` 路径/行号/符号）均为档案态蓝本——tag rust-oracle-freeze（2026-10-05 删区），现为本仓自主基线。

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
/// `atoi(s)`（oracle `misc.rs:126-149`）——B10（#434 / M22 A-2 + M17b-A1）
/// 改 `strtol_core` 饱和单源：atoi ≡ (int)strtol(s,NULL,10)（C
/// §7.22.1.2），LLP64 strtol 饱和 ±2^31 经 (int) 传导（UCRT 实测
/// `atoi("4294967296")=2147483647`、`atoi("-2147483649")=-2147483648`；
/// glibc 截断回绕系 LP64 平台差，主判 Win）。修前 i32 回绕累加——
/// CLI 侧另走 Bytecode 预编译段（空白前缀只认空格 + 超域**整程序
/// trap**），双源不同义，route 改判后本 handler 是唯一真源。
pub fn host_atoi(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  addr : UInt32,
) -> HostMemReply {
  let s = read_cstring_raise(mem, map, addr) catch {
    AccessFault::Fault(f~) => return fault_reply(f)
  }
  value_only(atoi_bytes(s).to_int64().reinterpret_as_uint64())
}

///|
/// 字节级 `atoi`（strtol 饱和单源——B10 起与 atol/strtol 同核）。
fn atoi_bytes(s : Bytes) -> Int32 {
  let (out, _, _, _) = strtol_core(s, 10)
  // 饱和后值域 ⊂ i32（±2^31 边界），to_int 无损
  out.to_int()
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
fn hex_digit_val(b : Byte) -> Int32 {
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
/// `atol(s)`（oracle `misc.rs:336-359`）——B10（#434 / M22 A-11）改
/// `strtol_core` 饱和单源：atol ≡ strtol(s,NULL,10)（C §7.22.1.2），
/// LLP64 long=32 位 → 饱和 ±2^31（UCRT 实测 `atol("3000000000")=
/// 2147483647`；WSL LP64 值不同系平台差）。修前纯 i64 回绕，与同文件
/// strtol 的饱和语义内部不一致。
pub fn host_atol(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  addr : UInt32,
) -> HostMemReply {
  let s = read_cstring_raise(mem, map, addr) catch {
    AccessFault::Fault(f~) => return fault_reply(f)
  }
  value_only(atol_bytes(s).reinterpret_as_uint64())
}

///|
/// 字节级 `atol`（strtol 饱和单源——B10 起与 atoi/strtol 同核）。
fn atol_bytes(s : Bytes) -> Int64 {
  let (out, _, _, _) = strtol_core(s, 10)
  out
}

///|
/// strtol 字节级核心（B10 #434 抽出——strtol/atol/atoi 三路单源）：
/// 跳 ASCII 空白 → 可选符号 → base 前缀探测（0x/0 前缀同 host_strtol
/// 原逻辑）→ 数字累加 + **饱和预判**。
///
/// 饱和域 = LLP64 long 32 位（±2^31；病 20 残余面同口径）。修前
/// `val*eff+digit` i64 回绕绕过 LONG_MAX/LONG_MIN 判定（M22 A-3：
/// 2^63/2^64/17F 静默错值且不写 ERANGE）；预判式 `val > (limit-digit)/eff`
/// 为 strtoul 式标准写法（比较两侧均 ≤2^31·36 < 2^63，无 i64 溢出面）。
/// 溢出后**继续消费后续数字**（endptr 指数字串尾——UCRT s1 off=20 实测）。
///
/// 返回 `(值, 溢出标志, 消费终点 pos, 有转换标志)`；**无转换时 pos=0**
/// （endptr=nptr——C11 §7.22.1.4p7「无转换则 endptr 存 nptr 原始值」；
/// 修前 pos 停在跳过空白/符号后，`if (end==str)` 惯用法恒假分支错向，
/// M22 A-4）。
fn strtol_core(s : Bytes, base : Int32) -> (Int64, Bool, Int32, Bool) {
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
  let effective_base : Int32 = if base == 0 {
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
  let limit : Int64 = if sign > 0L { 2147483647L } else { 2147483648L }
  let mut val = 0L
  let mut overflow = false
  while pos < n {
    let digit = digit_value(s[pos])
    if digit < 0 || digit.to_int64() >= eff {
      break
    }
    if !overflow {
      if val > (limit - digit.to_int64()) / eff {
        overflow = true
      } else {
        val = val * eff + digit.to_int64()
      }
    }
    pos = pos + 1
  }
  if pos == start_pos {
    // 无转换：endptr=nptr（pos=0）；errno 不写（B10 / M22 A-10——glibc/
    // UCRT 均不在无转换时设 EINVAL，修前虚构 errno=22）
    return (0L, false, 0, false)
  }
  let out : Int64 = if overflow {
    if sign > 0L {
      2147483647L
    } else {
      -2147483648L
    }
  } else if sign > 0L {
    val
  } else {
    -val
  }
  (out, overflow, pos, true)
}

///|
/// 字节 → 数字值（非字母数字 → -1；进位域判定由调用方负责）。
fn digit_value(c : Byte) -> Int32 {
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
/// 空白 → 可选符号 → **INF/INFINITY/NAN 族**（B10 #434 / M22 A-8 补：
/// 大小写不敏感 + 符号已消费 + nan 括号段闭合才消费 + "infin" 取最长
/// 合法前缀 "inf"）或 **十进制**（数字/小数点一次/eE 指数一次）或
/// **hex float**（`0x`+hex 数字 ≥1 → hex 数字/[.]/[pP 带符号十进制
/// 指数]）——**悬空指数回退**（`e`/`e+`/`e-`/`p`… 后无数字则不消费，
/// 最长**合法**前缀语义——审阅 P2-1 补强）。
/// B10（#434）三面修复：①mantissa 须含 ≥1 数字（"e5"/".e5"/"-"/"+"/
/// "." 无数字 → **无转换**：token 空 + pos 回退 nptr=0——M22 A-4，
/// 修前 "e5" 整 token 消费、符号/点消费后不回退）；②指数段后不并点
/// （"1e5.3" → "1e5"——M22 A-5，修前 '.' 只挡 has_dot 误吞成整 token
/// 解析失败返 0.0）；③hex 尾点无条件消费（"0x1." → off=4——M22
/// A-12，与十进制 "1." 口径对齐）。
/// atof ≡ strtod(str, NULL)（C §7.22.1.1）的公共扫描器；返回
/// (token 字节, 消费位数)。
fn scan_float_token(s : Bytes) -> (Array[Byte], Int32) {
  let n = s.length()
  let mut pos = 0
  while pos < n && is_ascii_ws_byte(s[pos]) {
    pos = pos + 1
  }
  let start = pos
  if pos < n && (s[pos] == b'+' || s[pos] == b'-') {
    pos = pos + 1
  }
  // INF/INFINITY：最长合法前缀（"infin" → "inf"）
  if matches_ci(s, pos, "infinity") {
    return (slice_bytes(s, start, pos + 8), pos + 8)
  }
  if matches_ci(s, pos, "inf") {
    return (slice_bytes(s, start, pos + 3), pos + 3)
  }
  // NAN + 可选 (n-char-seq)：括号段 [A-Za-z0-9_]* 须闭合才消费
  //（"nan(" → off=3；"NAN(123)" → off=8——UCRT 实测）
  if matches_ci(s, pos, "nan") {
    let mut end = pos + 3
    if end < n && s[end] == b'(' {
      let mut j = end + 1
      while j < n && (digit_value(s[j]) >= 0 || s[j] == b'_') {
        j = j + 1
      }
      if j < n && s[j] == b')' {
        end = j + 1
      }
    }
    return (slice_bytes(s, start, end), end)
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
      // B10（M22 A-12）：hex 尾点无条件消费（点后 hex 数字可选——
      // "0x1."→off=4、"0x1.p3" 合法全消费；修前点后无数字不消费）
      pos = pos + 1
      while pos < n && is_hex_digit(s[pos]) {
        pos = pos + 1
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
    // 十进制形态：数字/小数点（一次，且未进指数段）/eE 指数（一次，
    // 后可带符号；e 前须已有数字——mantissa 空则 e 不属 subject）
    let mut has_dot = false
    let mut exp_start = -1
    let mut has_digit = false
    while pos < n {
      let c = s[pos]
      if c >= b'0' && c <= b'9' {
        has_digit = true
        pos = pos + 1
      } else if c == b'.' && !has_dot && exp_start < 0 {
        has_dot = true
        pos = pos + 1
      } else if (c == b'e' || c == b'E') && exp_start < 0 && has_digit {
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
    // 无数字（"-"/"+"/"."/"e5"/".e5"…）→ 无转换：token 空 + pos=nptr
    //（B10 / M22 A-4——endptr 惯用法 `if (end==str)` 依赖此位点）
    if !has_digit {
      let empty : Array[Byte] = []
      return (empty, 0)
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
/// 大小写不敏感前缀匹配（INF/NAN 族探测辅助，B10）：s[from..] 是否以
/// lit 开头（逐字节 CI 比较；越界即 false）。
fn matches_ci(s : Bytes, from : Int32, lit : String) -> Bool {
  let n = s.length()
  let bytes = lit.to_array()
  if from < 0 || from + bytes.length() > n {
    return false
  }
  for i = 0; i < bytes.length(); i = i + 1 {
    let a = s[from + i].to_int()
    let b = bytes[i].to_int()
    let al = if a >= 65 && a <= 90 { a + 32 } else { a }
    let bl = if b >= 65 && b <= 90 { b + 32 } else { b }
    if al != bl {
      return false
    }
  }
  true
}

///|
/// 字节切片（scan_float_token 辅助，B10）。
fn slice_bytes(s : Bytes, from : Int32, upto : Int32) -> Array[Byte] {
  let out : Array[Byte] = []
  let mut i = from
  while i < upto {
    out.push(s[i])
    i = i + 1
  }
  out
}

///|
/// 浮点 token 值计算：INF/INFINITY/NAN 族直构造（**符号自理**——实测
/// `parse_double("-inf")` 符号位不可靠）；十进制形态走 parse_double
///（**B10 起失败返 None**——调用方区分「语法拒」（token 空已在上游拦）
/// 与「超域」（扫描器保证语法合法 ⇒ parse 拒即上溢，实测 1e400/12e309
/// ERR、1.e5/.5e3/超长指数全收）→ ±inf + ERANGE，M22 A-6 修前上溢
/// 归 0.0）；hex float 形态（`0x` mantissa + 可选 `p` 二进制指数）自算
/// ——mantissa hex 逐位累加（≤2^53 域内 Double 精确）、小数段 16^-k
/// 缩放累加、指数 2^p（`@math.pow` 整数幂精确）。正确舍入（C 的
/// correctly-rounded）不做——教学域精度取舍，登记。
fn parse_float_token(token : Array[Byte]) -> Double? {
  let len = token.length()
  if len == 0 {
    // 无转换（token 空）：值恒 0.0——None 保留给「非空且超域」形态
    return Some(0.0)
  }
  let mut off = 0
  let neg = len > 0 && token[0] == b'-'
  if len > 0 && (token[0] == b'+' || token[0] == b'-') {
    off = 1
  }
  // INF/INFINITY/NAN（token 形态由 scan_float_token 产出保证）。body 按
  // 匹配字面量取——parse_double 拒 "nan(123)" 带 payload 形态（实测），
  // 括号段只影响 endptr 不影响值（值恒静态 NaN/inf）。
  let tb = Bytes::from_array(token)
  let body : Double = if matches_ci(tb, off, "infinity") {
    @string.parse_double("infinity") catch {
      _ => 0.0
    }
  } else if matches_ci(tb, off, "inf") {
    @string.parse_double("inf") catch {
      _ => 0.0
    }
  } else if matches_ci(tb, off, "nan") {
    @string.parse_double("nan") catch {
      _ => 0.0
    }
  } else {
    0.0
  }
  if body != 0.0 {
    return Some(if neg { -body } else { body })
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
    Some(sign * val)
  } else {
    let v : Double = @string.parse_double(
      @utf8.decode_lossy(Bytes::from_array(token)),
    ) catch {
      _ => return None
    }
    Some(v)
  }
}

///|
/// Array[Byte] 切片（parse_float_token INF/NAN 分支辅助，B10）。
fn slice_bytes_from(
  token : Array[Byte],
  from : Int32,
  upto : Int32,
) -> Array[Byte] {
  let out : Array[Byte] = []
  let mut i = from
  while i < upto {
    out.push(token[i])
    i = i + 1
  }
  out
}

///|
/// token 是否含非零数字（strtod ERANGE 判定辅助，B10）：上溢（inf）与
/// 下溢（0）仅在「token 数值形态非零」时设 ERANGE——"inf"/"nan"（无
/// 数字）与 "0e-400"（全零形态）不设。

///|
/// token 是否 INF/NAN 字面形态（strtod ERANGE 判定排除项，B10）——
/// infinity 的 'f' 是 hex 数字（token_has_nz_digit true），但 INF/NAN
/// 族非数值形态不设 ERANGE（真值 errno=0）。
fn is_inf_nan_token(token : Array[Byte]) -> Bool {
  let len = token.length()
  let mut off = 0
  if len > 0 && (token[0] == b'+' || token[0] == b'-') {
    off = 1
  }
  let b = Bytes::from_array(token)
  matches_ci(b, off, "inf") || matches_ci(b, off, "nan")
}

///|
fn token_has_nz_digit(token : Array[Byte]) -> Bool {
  for i = 0; i < token.length(); i = i + 1 {
    // 字节域判定：十进制 1-9 + hex a-f/A-F（'0' 排除；勿用 digit_value>0
    // ——它对任意字母返正值，infinity 的 i/n/f 会被误判非零形态）
    let c = token[i]
    if (c >= b'1' && c <= b'9') ||
      (c >= b'a' && c <= b'f') ||
      (c >= b'A' && c <= b'F') {
      return true
    }
  }
  false
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
  addr : UInt32,
) -> HostMemReply {
  let s = read_cstring_raise(mem, map, addr) catch {
    AccessFault::Fault(f~) => return fault_reply(f)
  }
  let (token, _) = scan_float_token(s)
  // B10（M22 A-6 连坐）：atof ≡ strtod(str,NULL)——超域 → ±inf
  //（parse_double 对 1e400 返 Err；修前 catch → 0.0）
  let val : Double = match parse_float_token(token) {
    Some(v) => v
    None =>
      if token.length() > 0 && token[0] == b'-' {
        -@double.infinity
      } else {
        @double.infinity
      }
  }
  value_only(val.reinterpret_as_uint64())
}

///|
/// `strtol(str, endptr, base)`（C §7.22.1.4）。
/// **endptr 位点差异记录**（2026-10-06 审阅 P3-2，纪律 4）："0x"/"0x!"
/// 无有效十六进制数字形态下 base=0 的 endptr 偏移——Clang(UCRT) `off=0`
/// vs 本实现 `off=1`（只消费 '0'；返回值两侧全对，C 标准 §7.22.1.4 的
/// subject sequence 口径**本实现更对**——"0x" 无后继数字时序列即 "0"，
/// endptr 应指向 x 之后=1；UCRT 形态属实现差异）——不对齐 UCRT，差异
/// 在案。
/// B10（#434）三面修复：①base 域校验前置（非 0 且 ∉[2,36] → EINVAL +
/// 返 0 + endptr=nptr——glibc 判据，UCRT invalid parameter handler 杀
/// 进程采不到值；修前按该进制解析出静默错值，M22 A-9）；②无转换不写
/// errno（修前虚构 EINVAL=22——glibc/UCRT 仅 base 非法时设，M22 A-10）
/// + endptr=nptr（M22 A-4）；③累加饱和预判（strtol_core 单源——修前
/// i64 回绕绕过 ±2^31 判定，M22 A-3）。
pub fn host_strtol(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  str_addr : UInt32,
  endptr_addr : UInt32,
  base : Int32,
  errno_addr : UInt32?,
) -> HostMemReply {
  // base 域校验前置（EINVAL=22 与 errno.h stub 宏同值）
  if base != 0 && (base < 2 || base > 36) {
    match errno_addr {
      Some(a) =>
        match mem.store_u32(map, a, 22U) {
          Ok(_) => ()
          Err(_) => ()
        }
      None => ()
    }
    if endptr_addr != 0U {
      let _ = mem.store_u64(map, endptr_addr, str_addr.to_uint64())
    }
    return value_only(0UL)
  }
  let s = read_cstring_raise(mem, map, str_addr) catch {
    AccessFault::Fault(f~) => return fault_reply(f)
  }
  let (out, range_overflow, pos, _converted) = strtol_core(s, base)
  if endptr_addr != 0U {
    // 病 20（#61，2026-10-10）：endptr 是 char**——写回须 64 位全宽
    //（旧 store_u32 只写低 4 字节，char* 高位留内存残值 → 指针全乱）。
    // 无转换时 pos=0 → endptr=nptr（C11 §7.22.1.4p7）。
    let _ = mem.store_u64(
      map,
      endptr_addr,
      (str_addr + pos.reinterpret_as_uint()).to_uint64(),
    )
  }
  if range_overflow {
    match errno_addr {
      Some(a) => {
        let _ = mem.store_u32(map, a, 34U) // ERANGE（UCRT 值）
        ()
      }
      None => ()
    }
  }
  value_only(out.reinterpret_as_uint64())
}

///|
/// `strtod(str, endptr)`（oracle `misc.rs:417-459`）——token 扫描：可选
/// 符号 → INF/NAN/数字族（scan_float_token 单源）；token 内只可能是
/// ASCII（扫描集决定）。
/// B10（#434）三面修复：①无转换 endptr=nptr + **不写 errno**（修前虚构
/// EINVAL=22 且 endptr 指跳空白后——M22 A-4/A-10）；②上溢 → ±inf +
/// ERANGE（修前 parse 失败归 0.0——M22 A-6）；③下溢（值 0 且 token 数值
/// 形态非零）→ ERANGE（UCRT/glibc 同设，B10 复测 d6 实测 errno=34）。
pub fn host_strtod(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  str_addr : UInt32,
  endptr_addr : UInt32,
  errno_addr : UInt32?,
) -> HostMemReply {
  let s = read_cstring_raise(mem, map, str_addr) catch {
    AccessFault::Fault(f~) => return fault_reply(f)
  }
  // 扫描器与 atof 单源（2026-10-05 批二-a 抽出；值计算同用 parse_float_token
  //——含 hex float/悬空回退/INF·NAN，B10 补强）
  let (token, pos) = scan_float_token(s)
  // 上溢标志（parse 拒 + 扫描器保证语法合法 ⇒ 超域，M22 A-6）
  let mut overflow = false
  let val : Double = match parse_float_token(token) {
    Some(v) => v
    None => {
      overflow = true
      if token.length() > 0 && token[0] == b'-' {
        -@double.infinity
      } else {
        @double.infinity
      }
    }
  }
  if endptr_addr != 0U {
    // 病 20 同款（strtol 锚见上）：endptr 写回 64 位全宽；无转换 pos=0
    //→ endptr=nptr（C11 §7.22.1.4p7 同款口径）
    let _ = mem.store_u64(
      map,
      endptr_addr,
      (str_addr + pos.reinterpret_as_uint()).to_uint64(),
    )
  }
  // ERANGE：上溢（parse 拒）或下溢（值 0 且 token 数值形态非零）；
  // INF/NAN 字面形态排除（'f' 是 hex 数字但 infinity 非数值形态——
  // 真值 errno=0）；hex 超域（0x1p1025 → inf）含数字照设
  let numeric_form = !is_inf_nan_token(token)
  if numeric_form && (overflow || (val == 0.0 && token_has_nz_digit(token))) {
    match errno_addr {
      Some(a) =>
        match mem.store_u32(map, a, 34U) {
          Ok(_) => ()
          Err(_) => ()
        }
      None => ()
    }
  }
  value_only(val.reinterpret_as_uint64())
}

///|
/// `strerror(errnum)`（oracle `misc.rs:461-519`）——C 语义返回**静态
/// 串**（free 它才是 UB）。B10（#434 / M22 A-7）改「无主静态块」：
/// 保留 allocate+写入（地址可读可 printf），**不 register_alloc**——
/// regions 无条目 ⇒ 泄漏报告天然不见（修前每次调用一条 region，学生
/// 遵守 C 语义不 free 反被报「N 处未释放」）；free 该地址走无效 free
/// 诊断（release 找不到条目——教学上 free 静态串被拦，比真机 UB 安全）。
/// 已知取舍（登记）：块不进 free_list/quarantine，堆单调推进——消息
/// 最长 ~28B 对齐块，教学场景调用次数有限；`alloc_line` 参数保留签名
/// 兼容（不再有登记用途）。
/// **消息字节数含内嵌 NUL**（oracle 字面量 `\0` 计入 size/写入——勘察
/// §3.2-9 的"易错点"在此显式保留）。
pub fn host_strerror(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  errnum : Int32,
  alloc_line : Int32,
) -> HostMemReply {
  let _ = alloc_line // 静态块形态下无登记用途（签名兼容保留）
  // 病 47（2026-10-13）：映射对齐 UCRT errnum 值域（与 errno.h stub 宏
  // 同源——旧表 1/2/3/4/5 连续自定义编号系 d1253f91 宏族对齐批的漏
  // 连坐面，errnum 与文案错位：strerror(1) 出 EINVAL 文案）。
  // B10 连坐（M22 D-2）：34 文案补 UCRT 口径（病 47 批漏面——34 曾留
  // glibc 式文案）。
  let msg : Bytes = match errnum {
    0 => b"No error\x00"
    1 => b"Operation not permitted\x00"
    2 => b"No such file or directory\x00"
    13 => b"Permission denied\x00"
    22 => b"Invalid argument\x00"
    33 => b"Domain error\x00"
    34 => b"Result too large\x00"
    _ => b"Unknown error\x00"
  }
  let size = msg.length()
  let aligned = @bytecode.align4(size.reinterpret_as_uint())
  let addr = match map.allocate_raw(aligned, @bytecode.MEM_SIZE) {
    Some(a) => a
    None => return null_silent()
  }
  // free_list 复用块可能带 freed_logs 记录——不清理会把首次读误报 UAF
  //（allocate 配套步骤，与 register_alloc 无关，保留）
  map.freed_logs_remove_overlapping(addr, addr + aligned)
  match mem.write_bytes(map, addr, msg) {
    Ok(_) => value_only(addr.to_uint64())
    // oracle 对该"理论不可达"失败显式 trap（非静默——审阅 P1-b 定的口径）
    Err(_) => trap_only("strerror: 输出缓冲写入失败", "")
  }
}
