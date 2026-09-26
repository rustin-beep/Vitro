///| printf 引擎（Rust `host/utils.rs:33-344` 照搬）——`parse_format_spec` /
/// `apply_width` / `format_g` / `format_printf_string` + U2#9 预算闸。
///
/// **定点格式化 [`format_fixed`]（本文件的核心新件）**：Rust `{:.*}` 无
/// MoonBit 等价 API——用 `@bigint` 做**精确十进制展开**（每个 double 都是
/// 精确的有理数：`m × 2^e`；`e < 0` 时 `m × 5^k / 10^k`），再在 prec 位上
/// **half-even 舍入**（Rust flt2dec 的舍入语义）。oracle 真值锚（release
/// 二进制实测 2026-09-23）：`%.2f` 0.125→`0.12`、`%.0f` 3.5→`4`、
/// 999999.5（%g 内部）→`1000000`、`%.0f` -0.0→`-0`——half-even 与符号
/// 保留双双实证。
///
/// **照搬的 oracle 既有偏差（差异台账域，不修）**：`%+d`/`% d`/`%#` 旗标
/// 无效（`apply_width` 只实现 `-`/`0`——oracle 实测 `%+d`→`42`）；
/// `%.1s` 忽略精度（'s' 分支不取 precision——实测整串输出）；`%c` 高位
/// 字节经 char 通道变 UTF-8 两字节（`putchar(200)` 实测落 `C3 88`——
/// DIFF-LIB-PRINTF 族）。
///
/// **与 oracle 的登记分叉**：`%s` 实参串按受检读（oracle `read_cstring`
/// 裸读不 trap）——`format_printf_string` 因此返回 `Result`，读故障由
/// 调用方转 trap；格式串本身的读同（批一号读侧口径）。

///|
/// 宽度/精度预算（U2#9）：单转换上限 1MB——`printf("%999999999d",1)` 此前
/// 单次 ~1GB `repeat` 分配。
const PRINTF_FIELD_BUDGET : Int = 1 << 20

///|
/// 格式串游标（oracle 用 `chars.peekable()`；此处对码点数组）。
priv struct FmtScan {
  s : Array[Int]
  mut i : Int
}

///|
fn FmtScan::peek(self : FmtScan) -> Int? {
  if self.i < self.s.length() {
    Some(self.s[self.i])
  } else {
    None
  }
}

///|
fn FmtScan::advance(self : FmtScan) -> Unit {
  self.i = self.i + 1
}

///|
/// 解析一个格式说明符（`%` 之后）：flags / width（`*` 即止、值留空）/
/// precision / 长度修饰（只记 `ll`）/ 格式字母。
fn parse_format_spec(scan : FmtScan) -> (Int, Bool, Int?, Int?, String)? {
  // flags：- + 空格 # 0（去重追加）
  let mut flags = ""
  while true {
    match scan.peek() {
      Some(c) =>
        if c == 45 || c == 43 || c == 32 || c == 35 || c == 48 {
          let cs = Int::unsafe_to_char(c).to_string()
          if !flags.contains(cs) {
            flags = flags + cs
          }
          scan.advance()
        } else {
          break
        }
      None => break
    }
  }
  // width：数字累计；遇 `*` 消费即止（width 留 None——动态宽度整族由
  // typeck 编译期拒收，E3032；U6#3 登记在案）
  let mut width_str = ""
  while true {
    match scan.peek() {
      Some(c) =>
        if c >= 48 && c <= 57 {
          width_str = width_str + Int::unsafe_to_char(c).to_string()
          scan.advance()
        } else if c == 42 {
          scan.advance()
          break
        } else {
          break
        }
      None => break
    }
  }
  let width : Int? = if width_str == "" {
    None
  } else {
    Some(@string.parse_int(width_str)) catch {
      _ => None
    }
  }
  // precision：`.` 开头，数字累计或 `*`
  let mut precision : Int? = None
  match scan.peek() {
    Some(46) => {
      scan.advance()
      let mut prec_str = ""
      while true {
        match scan.peek() {
          Some(c) =>
            if c >= 48 && c <= 57 {
              prec_str = prec_str + Int::unsafe_to_char(c).to_string()
              scan.advance()
            } else if c == 42 {
              scan.advance()
              break
            } else {
              break
            }
          None => break
        }
      }
      if prec_str != "" {
        try {
          precision = Some(@string.parse_int(prec_str))
        } catch {
          _ => ()
        }
      }
    }
    _ => ()
  }
  // 长度修饰：l/h/L/z/j/t；只记 ll
  let mut is_ll = false
  match scan.peek() {
    Some(c) =>
      if c == 108 || c == 104 || c == 76 || c == 122 || c == 106 || c == 116 {
        scan.advance()
        match scan.peek() {
          Some(c2) =>
            if c == 108 && c2 == 108 {
              is_ll = true
              scan.advance()
            } else if c == 104 && c2 == 104 {
              scan.advance()
            }
          None => ()
        }
      }
    None => ()
  }
  // 格式字母
  match scan.peek() {
    Some(spec) => {
      scan.advance()
      Some((spec, is_ll, precision, width, flags))
    }
    None => None
  }
}

///|
/// 格式字母序列（参数计数用——只数转换符，`%%` 不计）。
fn parse_format_specs(fmt : Array[Int]) -> Array[Int] {
  let specs : Array[Int] = []
  let scan = FmtScan::{ s: fmt, i: 0, }
  while true {
    match scan.peek() {
      Some(ch) => {
        scan.advance()
        if ch == 37 {
          match scan.peek() {
            Some(n) =>
              if n == 37 {
                scan.advance() // %%
              } else {
                match parse_format_spec(scan) {
                  Some(t) => specs.push(t.0)
                  None => ()
                }
              }
            None => ()
          }
        }
      }
      None => break
    }
  }
  specs
}

///|
/// U2#9 预算闸：全部宽度/精度 ≤ [`PRINTF_FIELD_BUDGET`]，超限返回教学文案。
fn validate_format_field_budget(fmt : Array[Int]) -> String? {
  let scan = FmtScan::{ s: fmt, i: 0, }
  while true {
    match scan.peek() {
      Some(ch) => {
        scan.advance()
        if ch == 37 {
          match scan.peek() {
            Some(n) =>
              if n == 37 {
                scan.advance()
              } else {
                match parse_format_spec(scan) {
                  Some(t) => {
                    let precision = t.2
                    let width = t.3
                    match width {
                      Some(w) =>
                        if w > PRINTF_FIELD_BUDGET {
                          return Some(
                            "printf: 字段宽度 \{w} 超出上限 \{PRINTF_FIELD_BUDGET}（教学引擎输出预算；Clang 下此写法会尝试分配同量级内存）。",
                          )
                        }
                      None => ()
                    }
                    match precision {
                      Some(p) =>
                        if p > PRINTF_FIELD_BUDGET {
                          return Some(
                            "printf: 精度 \{p} 超出上限 \{PRINTF_FIELD_BUDGET}（教学引擎输出预算）。",
                          )
                        }
                      None => ()
                    }
                  }
                  None => ()
                }
              }
            None => ()
          }
        }
      }
      None => break
    }
  }
  None
}

///|
/// 宽度填充（只实现 `-` 与 `0` 旗标——oracle 现状：`+`/空格/`#` 无效）。
/// 长度按**字节**计（Rust `s.len()`；非 ASCII 的 `%s` 域用 encode 长度对齐）。
fn apply_width(s : String, width : Int?, flags : String) -> String {
  let w = match width {
    Some(w) => w
    None => return s
  }
  let slen = @util.utf8_len(s)
  if slen >= w {
    return s
  }
  let pad_len = w - slen
  let left_align = flags.contains("-")
  let zero_pad = flags.contains("0") && !left_align
  let pad_char = if zero_pad { "0" } else { " " }
  let mut pad = ""
  let mut i = 0
  while i < pad_len {
    pad = pad + pad_char
    i = i + 1
  }
  if left_align {
    s + pad
  } else {
    pad + s
  }
}

///|
/// 去尾零与小数点（`%g` 用）：无 `.` 原样；否则剥尾 `0`，再剥残留 `.`。
fn trim_trailing_zeros_and_dot(s : String) -> String {
  let n = s.length()
  let mut has_dot = false
  let mut j = 0
  while j < n {
    if s[j].to_int() == 46 {
      has_dot = true
    }
    j = j + 1
  }
  if !has_dot {
    return s
  }
  let mut end = n
  while end > 0 && s[end - 1].to_int() == 48 {
    end = end - 1
  }
  if end > 0 && s[end - 1].to_int() == 46 {
    end = end - 1
  }
  s[0:end].to_owned()
}

///|
/// 10 的整数幂（**Rust std `f64::powi` 语义**——P1 修复，2026-09-23）。
///
/// **为什么不用朴素逐乘**：oracle `utils.rs:227` 用 `10f64.powi(e)`，其
/// 结果 = 精确 10^e 的最近舍入（平局向上），恰好 633 个指数中仅 **e=126**
/// 偏 1 ulp（Rust std 自身实现偏差，本函数显式锁定）；而逐乘链会从 e≥23
/// 起累积偏差（实测 `%g` 9/60 分叉、次正规区 `powi10(-320)=0` 导致
/// `infe-320` 泄漏）。
///
/// 实现 = `@bigint` 精确有理数 + 最近舍入（`2r ≥ d` 进位，即平局向上），
/// 次正规区按 2^-1074 网格直接舍入（`e=-324` 得 0 与 Rust 一致 → DBL_TRUE_MIN
/// 上两侧同形输出 `infe-324`，照搬 oracle 泄漏形状）。
///
/// **验证口径**：与本机 Rust 1.95.0（oracle 同工具链）的 `10f64.powi(e)`
/// 位模式全量对拍 —— e ∈ [-324, 308] 633 点仅 e=126 差异（已锁定）；
/// `host_io_wbtest.mbt` 的 `powi10_bit_alignment` / `format_g_powi_oracle_alignment`
/// 抽查 10 点锚 + oracle release 真机端到端 12 值锚。
fn powi10(e : Int) -> Double {
  if e == 0 {
    return 1.0
  }
  if e > 308 {
    return @double.infinity
  }
  if e < -324 {
    return 0.0
  }
  // Rust std powi(126) 的已知偏离（1 ulp 高于正确舍入）——显式锁定，勿"顺手修正"
  if e == 126 {
    return UInt64::reinterpret_as_double(0x5A17A2ECC414A040UL)
  }
  let k = if e < 0 { -e } else { e }
  let one = @bigint.BigInt::from_int(1)
  let p10 = big_pow10(k)
  let num = if e > 0 { p10 } else { one }
  let den = if e > 0 { one } else { p10 }
  // e_val = floor(log2(num/den))：位长差起步，一次校正
  let mut e_val = num.bit_length() - den.bit_length()
  if e_val >= 0 {
    if num.compare(big_mul_pow2(den, e_val)) < 0 {
      e_val = e_val - 1
    }
  } else if big_mul_pow2(num, -e_val).compare(den) < 0 {
    e_val = e_val - 1
  }
  if e_val >= -1022 {
    // 正规：m = round((num/den) × 2^(52-e_val)) ∈ [2^52, 2^53)
    let mut m = round_ratio(num, den, 52 - e_val)
    let mut exp2 = e_val
    if m == 0x20000000000000UL {
      // 舍入进位到 2^53：退一位
      m = 0x10000000000000UL
      exp2 = exp2 + 1
    }
    if exp2 > 1023 {
      return @double.infinity
    }
    UInt64::reinterpret_as_double(
      ((exp2 + 1023).to_uint64() << 52) | (m - 0x10000000000000UL),
    )
  } else {
    // 次正规：m = round((num/den) × 2^1074)，直接即低 52 位（含进位为最小正规）
    let m = round_ratio(num, den, 1074)
    UInt64::reinterpret_as_double(m)
  }
}

///|
/// `round((num/den) × 2^s)`（平局向上——Rust std powi 的口径）。
fn round_ratio(num : @bigint.BigInt, den : @bigint.BigInt, s : Int) -> UInt64 {
  let n2 = if s >= 0 { big_mul_pow2(num, s) } else { num }
  let d2 = if s >= 0 { den } else { big_mul_pow2(den, -s) }
  let q = n2.div(d2)
  let r = n2.mod(d2)
  if r.is_zero() {
    return q.to_uint64()
  }
  let cmp = r.mul(@bigint.BigInt::from_int(2)).compare(d2)
  if cmp >= 0 {
    q.add(@bigint.BigInt::from_int(1)).to_uint64()
  } else {
    q.to_uint64()
  }
}

///|
/// `x × 2^n`（BigInt 无移位原语——pow 构造 2^n 后相乘）。
fn big_mul_pow2(x : @bigint.BigInt, n : Int) -> @bigint.BigInt {
  if n == 0 {
    return x
  }
  x.mul(@bigint.BigInt::from_int(2).pow(@bigint.BigInt::from_int(n)))
}

///|
/// `%g`/`%G`（Rust `format_g` 照搬）。指数段 `{:+#03}`：恒符号 + 两位
/// 补零（oracle 实测 `1e-05` / `1.23457e+06`）。
fn format_g(val : Double, prec : Int, upper : Bool) -> String {
  if val.is_nan() {
    return if upper { "NAN" } else { "nan" }
  }
  if val.is_inf() {
    if val > 0.0 {
      return if upper { "INF" } else { "inf" }
    }
    return if upper { "-INF" } else { "-inf" }
  }
  if val == 0.0 {
    return "0"
  }
  let prec = if prec < 1 { 1 } else { prec }
  let abs_val = if val < 0.0 { -val } else { val }
  let exp = @math.floor(@math.log10(abs_val)).to_int()
  let e_char = if upper { "E" } else { "e" }
  let result = if exp < -4 || exp >= prec {
    let mantissa = abs_val / powi10(exp)
    let s = trim_trailing_zeros_and_dot(format_fixed(mantissa, prec - 1))
    "\{s}\{e_char}\{fmt_exp_signed(exp)}"
  } else {
    let frac_digits = if prec - 1 - exp > 0 { prec - 1 - exp } else { 0 }
    trim_trailing_zeros_and_dot(format_fixed(abs_val, frac_digits))
  }
  if val < 0.0 && !result.has_prefix("-") {
    "-\{result}"
  } else {
    result
  }
}

///|
/// `{:+#03}`：恒符号 + 补零到 3 字符总宽（含符号）。
fn fmt_exp_signed(e : Int) -> String {
  let sign = if e < 0 { "-" } else { "+" }
  let mut d = if e < 0 { (-e).to_string() } else { e.to_string() }
  while sign.length() + d.length() < 3 {
    d = "0" + d
  }
  sign + d
}

///|
/// u64 小写十六进制（无前缀无填充）。
fn u64_hex_lower(v : UInt64) -> String {
  u64_radix(v, "0123456789abcdef")
}

///|
/// u64 大写十六进制。
fn u64_hex_upper(v : UInt64) -> String {
  u64_radix(v, "0123456789ABCDEF")
}

///|
/// u64 八进制。
fn u64_octal(v : UInt64) -> String {
  u64_radix(v, "01234567")
}

///|
fn u64_radix(v : UInt64, digits : String) -> String {
  if v == 0UL {
    return "0"
  }
  let base = digits.length()
  let mut out = ""
  let mut x = v
  while x > 0UL {
    let d = (x % base.to_uint64()).to_int()
    out = digits[d:d + 1].to_owned() + out
    x = x / base.to_uint64()
  }
  out
}

///|
/// 定点格式化——Rust `{:.*}` 等价：**精确**十进制展开 + half-even 舍入。
///
/// 每个 double 都是精确的 `m × 2^e`（m 为 53 位整数）：
/// - `e ≥ 0`：整数，无舍入；
/// - `e = -k < 0`：`m × 5^k / 10^k`——`m × 5^k` 的十进制即精确展开（k 位
///   小数），`k ≤ prec` 补零，`k > prec` 在第 prec 位 half-even（比较
///   `2r` 与除数，相等取偶）。
fn format_fixed(val : Double, prec : Int) -> String {
  if val.is_nan() {
    return "NaN"
  }
  if val.is_inf() {
    return if val < 0.0 { "-inf" } else { "inf" }
  }
  let bits = val.reinterpret_as_uint64()
  let neg = bits >> 63 == 1UL
  let biased = ((bits >> 52) & 0x7FFUL).to_int()
  let frac = bits & 0xFFFFFFFFFFFFFUL
  let m = if biased == 0 {
    @bigint.BigInt::from_uint64(frac)
  } else {
    @bigint.BigInt::from_uint64(frac + 0x10000000000000UL)
  }
  let e2 = if biased == 0 { -1074 } else { biased - 1075 }
  // q = |val| × 10^prec 的（可能经舍入的）整数
  let q : @bigint.BigInt = if e2 >= 0 {
    // 精确整数路径：m << e2 再 × 10^prec
    let mut p2 = @bigint.BigInt::from_int(1)
    let mut i = 0
    while i < e2 {
      p2 = p2.mul(@bigint.BigInt::from_int(2))
      i = i + 1
    }
    m.mul(p2).mul(big_pow10(prec))
  } else {
    let k = -e2
    // num = m × 5^k（= |val| × 10^k 的精确整数）
    let mut p5 = @bigint.BigInt::from_int(1)
    let mut i = 0
    while i < k {
      p5 = p5.mul(@bigint.BigInt::from_int(5))
      i = i + 1
    }
    let num = m.mul(p5)
    if k <= prec {
      num.mul(big_pow10(prec - k))
    } else {
      // half-even：num = q0 × d + r
      let d = big_pow10(k - prec)
      let q0 = num.div(d)
      let r = num.mod(d)
      let two = @bigint.BigInt::from_int(2)
      let r2 = r.mul(two)
      let cmp = r2.compare(d)
      if cmp > 0 {
        q0.add(@bigint.BigInt::from_int(1))
      } else if cmp == 0 {
        // 平局取偶：q0 奇数进位
        if q0.mod(two).is_zero() {
          q0
        } else {
          q0.add(@bigint.BigInt::from_int(1))
        }
      } else {
        q0
      }
    }
  }
  let body = big_fixed_to_string(q, prec)
  if neg {
    "-\{body}"
  } else {
    body
  }
}

///|
fn big_pow10(n : Int) -> @bigint.BigInt {
  let mut r = @bigint.BigInt::from_int(1)
  let ten = @bigint.BigInt::from_int(10)
  let mut i = 0
  while i < n {
    r = r.mul(ten)
    i = i + 1
  }
  r
}

///|
/// q（= |val| × 10^prec）→ 定点字符串：整数段.小数段（prec 位；0 位无点）。
fn big_fixed_to_string(q : @bigint.BigInt, prec : Int) -> String {
  let s = q.to_string()
  if prec == 0 {
    return s
  }
  if s.length() <= prec {
    // 补左零到 prec+1（如 q=5, prec=2 → "0.05"）
    let mut padded = ""
    let mut i = 0
    while i < prec + 1 - s.length() {
      padded = padded + "0"
      i = i + 1
    }
    let full = padded + s
    return "\{full[0:1].to_owned()}.\{full[1:prec + 1].to_owned()}"
  }
  let cut = s.length() - prec
  "\{s[0:cut].to_owned()}.\{s[cut:s.length()].to_owned()}"
}

///|
/// 格式串 + 参数 → 输出（Rust `format_printf_string` 照搬）。
///
/// 返回 `Err` 的唯一来源是 `%s` 实参串的受检读（登记分叉：oracle 裸读
/// 不 trap）。
fn format_printf_string(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  fmt : Array[Int],
  args : Array[UInt64],
) -> Result[String, @memory.MemFault] {
  let scan = FmtScan::{ s: fmt, i: 0, }
  let mut out = ""
  let mut used = 0
  while true {
    let ch = match scan.peek() {
      Some(c) => {
        scan.advance()
        c
      }
      None => break
    }
    if used < args.length() && ch == 37 {
      match scan.peek() {
        Some(n) =>
          if n == 37 {
            out = out + "%"
            scan.advance()
          } else {
            match parse_format_spec(scan) {
              Some(t) => {
                let spec = t.0
                let is_ll = t.1
                let precision = t.2
                let width = t.3
                let flags = t.4
                let arg = args[used]
                let piece : String = if spec == 100 || spec == 105 {
                  // d / i
                  let val = if is_ll {
                    arg.reinterpret_as_int64().to_string()
                  } else {
                    arg.to_uint().reinterpret_as_int().to_string()
                  }
                  apply_width(val, width, flags)
                } else if spec == 117 {
                  // u
                  let val = if is_ll {
                    arg.to_string()
                  } else {
                    arg.to_uint().to_string()
                  }
                  apply_width(val, width, flags)
                } else if spec == 120 {
                  // x
                  let val = if is_ll {
                    u64_hex_lower(arg)
                  } else {
                    u64_hex_lower(arg.to_uint().to_uint64())
                  }
                  apply_width(val, width, flags)
                } else if spec == 88 {
                  // X
                  let val = if is_ll {
                    u64_hex_upper(arg)
                  } else {
                    u64_hex_upper(arg.to_uint().to_uint64())
                  }
                  apply_width(val, width, flags)
                } else if spec == 111 {
                  // o
                  let val = if is_ll {
                    u64_octal(arg)
                  } else {
                    u64_octal(arg.to_uint().to_uint64())
                  }
                  apply_width(val, width, flags)
                } else if spec == 112 {
                  // p（oracle 实测 "0x1234"——小写不填充）
                  apply_width(
                    "0x\{u64_hex_lower(arg.to_uint().to_uint64())}",
                    width,
                    flags,
                  )
                } else if spec == 102 {
                  // f
                  let f = arg.reinterpret_as_double()
                  let p = match precision {
                    Some(p) => p
                    None => 6
                  }
                  apply_width(format_fixed(f, p), width, flags)
                } else if spec == 103 {
                  // g
                  let f = arg.reinterpret_as_double()
                  let p = match precision {
                    Some(p) => p
                    None => 6
                  }
                  apply_width(format_g(f, p, false), width, flags)
                } else if spec == 71 {
                  // G
                  let f = arg.reinterpret_as_double()
                  let p = match precision {
                    Some(p) => p
                    None => 6
                  }
                  apply_width(format_g(f, p, true), width, flags)
                } else if spec == 115 {
                  // s（受检读；**忽略精度**——oracle 现状，%.1s 整串输出）
                  match read_cstring(mem, map, arg.to_uint()) {
                    Ok(bytes) =>
                      apply_width(@utf8.decode_lossy(bytes), width, flags)
                    Err(f) => return Err(f)
                  }
                } else if spec == 99 {
                  // c：低字节经 char 通道（200 → U+00C8 → UTF-8 两字节，
                  // oracle 缺陷形状照搬）
                  let cs = Int::unsafe_to_char((arg & 0xFFUL).to_int()).to_string()
                  apply_width(cs, width, flags)
                } else {
                  // 未知说明符：原样 `%` + 字母，但**消耗一个实参**
                  "%" + Int::unsafe_to_char(spec).to_string()
                }
                out = out + piece
                used = used + 1
              }
              None => ()
            }
          }
        None => out = out + "%" // 行尾孤立 %
      }
    } else {
      out = out + Int::unsafe_to_char(ch).to_string()
    }
  }
  Ok(out)
}

///|
/// printf 族参数计数（vm 分发侧用——批三号三段上提 pub：转换符个数，
/// `%%` 不计）。与 `parse_format_specs` 同解析器，只吐数量。
pub fn format_spec_kinds(fmt : Array[Int]) -> Array[Int] {
  parse_format_specs(fmt)
}

///|
/// scanf 族指针参数计数（vm 分发侧用——只数 `%` 转换符，空白指令与
/// 字面量不计；与 `parse_scanf_specs` 的 Spec 分支计数同口径）。
pub fn scanf_spec_count(fmt : Array[Int]) -> Int {
  let mut count = 0
  for it in parse_scanf_specs(fmt) {
    match it {
      ScanfItem::Spec(_, _) => count = count + 1
      _ => ()
    }
  }
  count
}
