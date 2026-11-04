///| printf 引擎（历史蓝本 Rust `host/utils.rs:33-344`，tag rust-oracle-freeze）——
/// `parse_format_spec` / `apply_width` / `format_g` / `format_printf_string`
/// + U2#9 预算闸。
///
/// **定点格式化 [`format_fixed`]（本文件的核心新件）**：Rust `{:.*}` 无
/// MoonBit 等价 API——用 `@bigint` 做**精确十进制展开**（每个 double 都是
/// 精确的有理数：`m × 2^e`；`e < 0` 时 `m × 5^k / 10^k`），再在 prec 位上
/// **half-even 舍入**（Rust flt2dec 的舍入语义）。历史蓝本真值锚（release
/// 二进制实测 2026-09-23）：`%.2f` 0.125→`0.12`、`%.0f` 3.5→`4`、
/// 999999.5（%g 内部）→`1000000`、`%.0f` -0.0→`-0`——half-even 与符号
/// 保留双双实证。
///
/// **历史蓝本既有偏差三病已修（#47 批一/批二-b 销案，旧照搬形态见 tag
/// rust-oracle-freeze；现行为以 Clang 直拍为准）**：`%+d`/`% d`/`%#` 旗标
/// （批二-b 2026-10-05 `apply_width` 补全五旗标——蓝本实测 `%+d`→`42`，
/// 现 `+42`）；`%.1s` 精度（现生效——蓝本整串输出）；`%c`/`putchar` 高位
/// 字节（批一 Bytes 载体化——蓝本 `putchar(200)` 落 `C3 88`，现单字节
/// `C8` == Clang；DIFF-LIB-PRINTF 族销案）。
///
/// **与历史蓝本的登记分叉**：`%s` 实参串按受检读（蓝本 `read_cstring`
/// 裸读不 trap）——`format_printf_string` 因此返回 `Result`，读故障由
/// 调用方转 trap；格式串本身的读同（批一号读侧口径）。

///|
/// 宽度/精度预算（U2#9）：单转换上限 1MB——`printf("%999999999d",1)` 此前
/// 单次 ~1GB `repeat` 分配。
const PRINTF_FIELD_BUDGET : Int32 = 1 << 20

///|
/// 格式串游标（oracle 用 `chars.peekable()`；此处对码点数组）。
priv struct FmtScan {
  s : Array[Int32]
  mut i : Int32
}

///|
fn FmtScan::peek(self : FmtScan) -> Int32? {
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
/// precision / 长度修饰（`""`/`"l"`/`"ll"`/`"h"`/`"hh"`——#427 批 B4
/// 2026-11-03 起全量记录：旧「只记 ll」使 %hhd/%hd/%hhu/%hu 不截断
/// （M20 A-4）与 %n 写回宽度无从分档；`L`/`z`/`j`/`t` 消费不记——无
/// long double，z/j/t 视同默认的旧口径维持（无真值锚，乱动无据））/
/// 格式字母。
fn parse_format_spec(
  scan : FmtScan,
) -> (Int32, String, Int32?, Int32?, String, Bool, Bool)? {
  // flags：- + 空格 # 0（去重追加）
  let mut flags = ""
  while true {
    match scan.peek() {
      Some(c) =>
        if c == 45 || c == 43 || c == 32 || c == 35 || c == 48 {
          let cs = Int32::unsafe_to_char(c).to_string()
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
  // width：数字累计；`*` = 运行期宽度（%*d 批四 2026-10-07——星号参数
  // 由 formatter 从参数组取，width 留 None、star_w 置位；原「typeck 编译
  // 期拒收」防线已随 W3032 降级退役）
  let mut width_str = ""
  let mut star_w = false
  while true {
    match scan.peek() {
      Some(c) =>
        if c >= 48 && c <= 57 {
          width_str = width_str + Int32::unsafe_to_char(c).to_string()
          scan.advance()
        } else if c == 42 {
          star_w = true
          scan.advance()
          break
        } else {
          break
        }
      None => break
    }
  }
  let width : Int32? = if width_str == "" {
    None
  } else {
    Some(@string.parse_int(width_str)) catch {
      _ => None
    }
  }
  // precision：`.` 开头，数字累计或 `*`（星号精度——参数组取值，批四）
  let mut precision : Int32? = None
  let mut star_p = false
  match scan.peek() {
    Some(46) => {
      scan.advance()
      let mut prec_str = ""
      while true {
        match scan.peek() {
          Some(c) =>
            if c >= 48 && c <= 57 {
              prec_str = prec_str + Int32::unsafe_to_char(c).to_string()
              scan.advance()
            } else if c == 42 {
              star_p = true
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
  // 长度修饰：l/h/L/z/j/t（ll/hh 双字符先行；L/z/j/t 消费不记——见函数头注）
  let mut len_mod = ""
  match scan.peek() {
    Some(c) =>
      if c == 108 || c == 104 || c == 76 || c == 122 || c == 106 || c == 116 {
        scan.advance()
        match scan.peek() {
          Some(c2) =>
            if c == 108 && c2 == 108 {
              len_mod = "ll"
              scan.advance()
            } else if c == 104 && c2 == 104 {
              len_mod = "hh"
              scan.advance()
            } else if c == 108 {
              len_mod = "l"
            } else if c == 104 {
              len_mod = "h"
            }
          None =>
            // 格式串终止于长度修饰后：仍记 l/h（后续格式字母缺失，
            // 调用方按 None 处理——此处只为语义完备）
            if c == 108 {
              len_mod = "l"
            } else if c == 104 {
              len_mod = "h"
            }
        }
      }
    None => ()
  }
  // 格式字母
  match scan.peek() {
    Some(spec) => {
      scan.advance()
      Some((spec, len_mod, precision, width, flags, star_w, star_p))
    }
    None => None
  }
}

///|
/// 已知转换符码点集（病 26，2026-10-13）：d i o u x X f F e E g G a A
/// c s p n——计数器只认此集（clang 一致：未知字母原样输出不取参）。
fn is_known_conv_code(c : Int32) -> Bool {
  c == 100 ||
  c == 105 ||
  c == 111 ||
  c == 117 ||
  c == 120 ||
  c == 88 ||
  c == 102 ||
  c == 70 ||
  c == 101 ||
  c == 69 ||
  c == 103 ||
  c == 71 ||
  c == 97 ||
  c == 65 ||
  c == 99 ||
  c == 115 ||
  c == 112 ||
  c == 110
}

///|
/// 剔除 flags 串中的 `0` 旗标（#427 批 B4：d/i/o/u/x/X 精度在场时
/// 0 旗标被忽略——flags 由 parse 侧去重，至多一个 `0`；ASCII 域码元
/// 即码点）。
fn strip_flag_zero(flags : String) -> String {
  let mut out = ""
  for i = 0; i < flags.length(); i = i + 1 {
    let c = flags[i].to_int()
    if c != 48 {
      out = out + Int32::unsafe_to_char(c).to_string()
    }
  }
  out
}

///|
/// %hhd/%hd 截断（M20 A-4 / #427 批 B4）：变参实参 int 提升（4 字节，
/// 位模式在低 32 位）取低 bits 位**符号扩展**（%hhd 300 → 44、
/// %hhd -1 → -1）。
fn printf_trunc_signed(v : UInt64, bits : Int32) -> Int32 {
  let lo = v.to_uint().reinterpret_as_int()
  let mask = if bits == 8 { 0xFF } else { 0xFFFF }
  let x = lo & mask
  let sign = if bits == 8 { 0x80 } else { 0x8000 }
  if (x & sign) != 0 {
    x - (mask + 1)
  } else {
    x
  }
}

///|
/// %hhu/%hu/%hhx 族截断：低 bits 位**零扩展**（%hhu 70000 → 112、
/// %hu 70000 → 4464）。
fn printf_trunc_unsigned(v : UInt64, bits : Int32) -> UInt64 {
  let mask = if bits == 8 { 0xFF } else { 0xFFFF }
  v & mask.to_uint64()
}

///|
/// 格式字母序列（参数计数用——只数**已知**转换符，`%%` 不计；未知
/// 字母（%q 等）不算说明符——病 26：旧计数把任意尾字符当转换符，
/// 说明符数 > 参数数 → 假 TRAP，而 clang 对 q 原样输出不取参）。
fn parse_format_specs(fmt : Array[Int32]) -> Array[Int32] {
  let specs : Array[Int32] = []
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
                  Some(t) =>
                    if is_known_conv_code(t.0) {
                      specs.push(t.0)
                    } else {
                      ()
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
  specs
}

///|
/// U2#9 预算闸：全部宽度/精度 ≤ [`PRINTF_FIELD_BUDGET`]，超限返回教学文案。
fn validate_format_field_budget(fmt : Array[Int32]) -> String? {
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
/// 宽度填充（`-`/`0`/`+`/空格/`#` 五旗标——DIFF-LIB-PRINTF-01 销案
/// 2026-10-05 批二-b：旧「只实现 - 与 0」系 oracle 照搬在案）。
/// 长度按**字节**计（Rust `s.len()`；非 ASCII 的 `%s` 域用 encode 长度对齐）。
/// `+`/空格只对带符号数值说明符有意义（调用方数字族）；`#` 前缀由调用方
/// （x/X/o 臂）经 `prefix~` 传入——**前缀属于数值部分**：零填充时前缀在
/// pad 之前、数字在 pad 之后（C11 7.21.6.1：`%#08x` → `0x0000ff`——
/// #427 批 B4 / M20 A-5：旧「前缀并入 body 再零填充」把前缀推到填充外
/// 成 `00000xff`）。
fn apply_width(
  s : String,
  width : Int32?,
  flags : String,
  signed_pos~ : Bool = false,
  prefix~ : String = "",
) -> String {
  // + / 空格旗标：正数带符号前缀（C：+ 优先于空格）
  let body = if signed_pos && !s.has_prefix("-") {
    if flags.contains("+") {
      "+" + s
    } else if flags.contains(" ") {
      " " + s
    } else {
      s
    }
  } else {
    s
  }
  let w = match width {
    Some(w) => w
    None => return prefix + body
  }
  let slen = @util.utf8_len(prefix + body)
  if slen >= w {
    return prefix + body
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
    prefix + body + pad
  } else if zero_pad {
    if prefix != "" {
      // # 前缀（x/X/o）：前缀在 pad 前（0x0000ff / 0X0FF / 0 + 000 + 10）
      prefix + pad + body
    } else if (body.length() > 0 && body[0].to_int() == 43) ||
      (body.length() > 0 && body[0].to_int() == 45) ||
      (body.length() > 0 && body[0].to_int() == 32) {
      // 零填充时符号（+/空格/-）前置 pad 前（C：+0003 / -0003——审阅 P2-a：
      // 旧 pad+body 把符号推到填充后成 000+3）。长度守卫先于索引（#427
      // 批 B4 / M21 A1：`%05.0d` 的精度 0×值 0 特例产空串，旧 `body[0]`
      // 先于守卫求值直接进程崩溃——三臂同崩）
      let sym = body[0:1].to_owned()
      sym + pad + body[1:].to_owned()
    } else {
      pad + body
    }
  } else {
    pad + prefix + body
  }
}

///|
/// `%s`/`%c` 的字节域宽度填充（左/右对齐空格——C 对字节串不用零填）。
fn apply_width_bytes(b : Bytes, width : Int32?, flags~ : String = "") -> Bytes {
  let w = match width {
    Some(w) => w
    None => return b
  }
  let blen = b.length()
  if blen >= w {
    return b
  }
  let pad_len = w - blen
  let out : Array[Byte] = []
  if flags.contains("-") {
    for j = 0; j < blen; j = j + 1 {
      out.push(b[j])
    }
    let mut i = 0
    while i < pad_len {
      out.push(b' ')
      i = i + 1
    }
  } else {
    let mut i = 0
    while i < pad_len {
      out.push(b' ')
      i = i + 1
    }
    for j = 0; j < blen; j = j + 1 {
      out.push(b[j])
    }
  }
  Bytes::from_array(out)
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
/// 次正规区按 2^-1074 网格直接舍入（`e=-324` 得 0——历史蓝本同值，tag
/// rust-oracle-freeze → DBL_TRUE_MIN 上输出 `infe-324`，沿用蓝本泄漏形状，已知边界）。
///
/// **验证口径**：与本机 Rust 1.95.0（oracle 同工具链）的 `10f64.powi(e)`
/// 位模式全量对拍 —— e ∈ [-324, 308] 633 点仅 e=126 差异（已锁定）；
/// `host_io_wbtest.mbt` 的 `powi10_bit_alignment` / `format_g_powi_oracle_alignment`
/// 抽查 10 点锚 + oracle release 真机端到端 12 值锚。
fn powi10(e : Int32) -> Double {
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
fn round_ratio(num : @bigint.BigInt, den : @bigint.BigInt, s : Int32) -> UInt64 {
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
fn big_mul_pow2(x : @bigint.BigInt, n : Int32) -> @bigint.BigInt {
  if n == 0 {
    return x
  }
  x.mul(@bigint.BigInt::from_int(2).pow(@bigint.BigInt::from_int(n)))
}

///|
/// double → 精确有理数 `m × 2^e2`（m 为正整数 bigint；次正规含隐位 0）。
/// format_g 精确路径的拆数单源（#427 批 B4）。
fn double_mant_exp(val : Double) -> (@bigint.BigInt, Int32) {
  let bits = val.reinterpret_as_uint64()
  let biased = ((bits >> 52) & 0x7FFUL).to_int()
  let frac = bits & 0xFFFFFFFFFFFFFUL
  let m = if biased == 0 {
    @bigint.BigInt::from_uint64(frac)
  } else {
    @bigint.BigInt::from_uint64(frac + 0x10000000000000UL)
  }
  let e2 = if biased == 0 { -1074 } else { biased - 1075 }
  (m, e2)
}

///|
/// 比较 `m × 2^e2` 与 `10^e`（decimal_exp_exact 的精确校正原语）。
fn cmp_pow10(m : @bigint.BigInt, e2 : Int32, e : Int32) -> Int32 {
  // 统一成整数比较：e2 ≥ 0 → m×2^e2 vs 10^e；e2 < 0 → m×5^(-e2) vs 10^(e-e2)
  let ten = @bigint.BigInt::from_int(10)
  let lhs = if e2 >= 0 {
    m.mul(@bigint.BigInt::from_int(2).pow(@bigint.BigInt::from_int(e2)))
  } else {
    m.mul(@bigint.BigInt::from_int(5).pow(@bigint.BigInt::from_int(-e2)))
  }
  let rhs_e = if e2 >= 0 { e } else { e - e2 }
  let rhs = if rhs_e >= 0 {
    ten.pow(@bigint.BigInt::from_int(rhs_e))
  } else {
    @bigint.BigInt::from_int(1)
  }
  lhs.compare(rhs)
}

///|
/// 有理数 half-even 舍入到整数（`round(num/den)`，平局取偶——与
/// format_fixed 同口径；#427 批 B4 的 %g 精确路径用）。
fn round_dec_half_even(
  num : @bigint.BigInt,
  den : @bigint.BigInt,
) -> @bigint.BigInt {
  let q = num.div(den)
  let r = num.mod(den)
  if r.is_zero() {
    return q
  }
  let two = @bigint.BigInt::from_int(2)
  let cmp = r.mul(two).compare(den)
  if cmp > 0 {
    q.add(@bigint.BigInt::from_int(1))
  } else if cmp == 0 {
    if q.mod(two).is_zero() {
      q
    } else {
      q.add(@bigint.BigInt::from_int(1))
    }
  } else {
    q
  }
}

///|
/// `round(val / 10^k)`（val = m×2^e2 精确有理数；k 可正可负——负即乘）。
fn round_ratio_dec(m : @bigint.BigInt, e2 : Int32, k : Int32) -> @bigint.BigInt {
  let ten = @bigint.BigInt::from_int(10)
  let mut num = m
  let mut den = @bigint.BigInt::from_int(1)
  if e2 >= 0 {
    num = num.mul(@bigint.BigInt::from_int(2).pow(@bigint.BigInt::from_int(e2)))
  } else {
    // m×2^-t = m×5^t / 10^t
    num = num.mul(
      @bigint.BigInt::from_int(5).pow(@bigint.BigInt::from_int(-e2)),
    )
    den = den.mul(ten.pow(@bigint.BigInt::from_int(-e2)))
  }
  if k >= 0 {
    den = den.mul(ten.pow(@bigint.BigInt::from_int(k)))
  } else {
    num = num.mul(ten.pow(@bigint.BigInt::from_int(-k)))
  }
  round_dec_half_even(num, den)
}

///|
/// 精确十进制指数 d（`10^d ≤ |val| < 10^(d+1)`）：log10 粗估 + 精确
/// 比较校正（浮点 log10 边界值可差 1——如 1e23 的精确值是
/// 9.9999999999999992e22，log10 粗估与边界判定必须由 bigint 定夺）。
fn decimal_exp_exact(m : @bigint.BigInt, e2 : Int32, abs_val : Double) -> Int32 {
  let d0 = @math.floor(@math.log10(abs_val)).to_int()
  let mut d = d0
  // 校正至多两三次（粗估误差 ≤1；防御性 while 上限 4）
  let mut rounds = 0
  while rounds < 4 {
    if cmp_pow10(m, e2, d) < 0 {
      d = d - 1
    } else if cmp_pow10(m, e2, d + 1) >= 0 {
      d = d + 1
    } else {
      break
    }
    rounds = rounds + 1
  }
  d
}

///|
/// `%g`/`%G`——#427 批 B4（2026-11-03）换**十进制精确路径**：旧实现的
/// `abs_val / powi10(exp)` 浮点商带 ulp 误差，%.17g 高精度段系统性偏差
///（1e23 → `0.9999999999999998e+23`，尾数 <1 违反 [1,10) 规格化、指数
/// 差 1——M20 A-7 / A2 锚 A2-A5）、次正规区精度损失（锚 A6/A7）与
/// DBL_TRUE_MIN 的 `infe-324` 泄漏（powi10(-324)=0 除零，锚 A8）。现
/// 尾数与指数均由 bigint 精确有理数 half-even 舍入（同 format_fixed
/// 口径）。`alt`（`#` 旗标）= 不删尾零（C11 7.21.6.1：`%#.3g` 0.0001
/// → `0.000100`——M20 A-6：旧 format_g 无视 # 恒 trim）。
fn format_g(
  val : Double,
  prec : Int32,
  upper : Bool,
  alt~ : Bool = false,
) -> String {
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
    // 病 22 修正（#71 第三梯队，2026-10-11）：负零保符号（%g -0.0 →
    // "-0"，clang 同形；符号位按位模式判——`-0.0 == 0.0` 为 true 拦
    // 不住）；format_fixed 的 -0.0 → "-0" 头注已证同族形态
    let neg = val.reinterpret_as_uint64() >> 63 == 1UL
    return if neg { "-0" } else { "0" }
  }
  let prec = if prec < 1 { 1 } else { prec }
  let neg = val < 0.0
  let abs_val = if neg { -val } else { val }
  let (m, e2) = double_mant_exp(abs_val)
  let d = decimal_exp_exact(m, e2, abs_val)
  // I = round(|val| / 10^(d-prec+1))——prec 位有效数字整数
  let i_big = round_ratio_dec(m, e2, d - prec + 1)
  // 进位归一（P1① 精确化）：I == 10^prec ⇒ 1.0×10^(d+1)（如 9.9995
  // 两位有效 round 推上 10²）——数学保证 I ∈ [10^(prec-1), 10^prec]
  let (i2, d2) = if i_big.compare(big_pow10(prec)) == 0 {
    (big_pow10(prec - 1), d + 1)
  } else {
    (i_big, d)
  }
  let digits = i2.to_string()
  let e_char = if upper { "E" } else { "e" }
  let result = if d2 < -4 || d2 >= prec {
    // e 形态：d.ddd × 10^d2（prec-1 位小数）
    let mant = if prec == 1 {
      digits
    } else {
      "\{digits[0:1].to_owned()}.\{digits[1:prec].to_owned()}"
    }
    let mant2 = if alt { mant } else { trim_trailing_zeros_and_dot(mant) }
    "\{mant2}\{e_char}\{fmt_exp_signed(d2)}"
  } else {
    // 定点形态：值 = I × 10^(d2-prec+1)，小数位 = prec-1-d2（≥0——分支
    // 条件 d2 < prec 保证；与旧 format_fixed(abs, frac) 数学等价，同
    // half-even 位次，但从同一 I 构造保证与 e 形态分支的有效位一致）
    let frac = prec - 1 - d2
    let dl = digits.length()
    let s = if dl > frac {
      "\{digits[0:dl - frac].to_owned()}.\{digits[dl - frac:dl].to_owned()}"
    } else {
      "0.\{"0".repeat(frac - dl)}\{digits}"
    }
    if alt {
      s
    } else {
      trim_trailing_zeros_and_dot(s)
    }
  }
  if neg {
    "-\{result}"
  } else {
    result
  }
}

///|
/// `{:+#03}`：恒符号 + 补零到 3 字符总宽（含符号）。
fn fmt_exp_signed(e : Int32) -> String {
  let sign = if e < 0 { "-" } else { "+" }
  let mut d = if e < 0 { (-e).to_string() } else { e.to_string() }
  while sign.length() + d.length() < 3 {
    d = "0" + d
  }
  sign + d
}

///|
/// `%e`/`%E`（#71 第三梯队病 21，2026-10-11 新增——此前无臂输出字面
/// "%e" 还消耗实参）。形态对齐 clang：尾数一位整数 + '.' + prec 位小数
/// （**不去尾零**——与 %g 的 trim 语义相反）+ e/E + 恒符号两位补零指数
/// （fmt_exp_signed 复用）。零特例 exp=0；符号含负零（位模式判）。
/// #427 批 B4（2026-11-03）换**十进制精确路径**（同 format_g）：旧
/// `abs_val / powi10(exp0)` 浮点商 ulp 误差在 %.17e 高精度段与 %.17g
/// 同形分叉（1e23 → `0.99999999999999978e+23` 尾数不规格化、指数差 1
/// ——探针 t_prec#9-14 六值实锤；默认精度段由 P1① 进位归一兜住无实
/// 错）。进位归一（P1①）保留为精确版：I == 10^(pr+1) ⇒ 1.0×10^(d+1)。
fn format_e(
  val : Double,
  prec : Int32,
  upper : Bool,
  alt~ : Bool = false,
) -> String {
  if val.is_nan() {
    return if upper { "NAN" } else { "nan" }
  }
  if val.is_inf() {
    if val > 0.0 {
      return if upper { "INF" } else { "inf" }
    }
    return if upper { "-INF" } else { "-inf" }
  }
  let neg = val.reinterpret_as_uint64() >> 63 == 1UL
  let sign = if neg { "-" } else { "" }
  let e_char = if upper { "E" } else { "e" }
  if val == 0.0 {
    let pr = precision_default6(prec)
    let frac = if pr > 0 { "." + "0".repeat(pr) } else { "" }
    return "\{sign}0\{frac}\{e_char}+00"
  }
  let abs_val = if val < 0.0 { -val } else { val }
  let pr = precision_default6(prec)
  let (m, e2) = double_mant_exp(abs_val)
  let d = decimal_exp_exact(m, e2, abs_val)
  // I = round(|val| / 10^(d-pr))——pr+1 位有效数字整数（一位整数 + pr
  // 位小数）；进位归一：I == 10^(pr+1) ⇒ 1.000…×10^(d+1)（如 %.0e 9.5
  // → half-even 取偶 10 → 1e+01；%e 999999.99 → 1.000000e+06——P1①）
  let i_big = round_ratio_dec(m, e2, d - pr)
  let (i2, d2) = if i_big.compare(big_pow10(pr + 1)) == 0 {
    (big_pow10(pr), d + 1)
  } else {
    (i_big, d)
  }
  let digits = i2.to_string()
  // PR #462 审阅 P2-3：# 的「恒含小数点」（%#.0e 1.5 → 2.e+00）
  let mant = if pr == 0 {
    if alt {
      "\{digits}."
    } else {
      digits
    }
  } else {
    "\{digits[0:1].to_owned()}.\{digits[1:pr + 1].to_owned()}"
  }
  "\{sign}\{mant}\{e_char}\{fmt_exp_signed(d2)}"
}

///|
/// %e 默认精度 6（与 f/g 同款内联口径的具名单源）。
fn precision_default6(prec : Int32) -> Int32 {
  if prec < 0 {
    6
  } else {
    prec
  }
}

///|
/// `format_fixed` 的大小写包装（#427 批 B4 的 %F 臂用）：定点输出只
/// 有 `nan`/`inf` 含字母，upper 位只作用这两段（数字段无字母）。
/// PR #462 审阅 P2-3（2026-11-03）：补 `#` 的「恒含小数点」语义
///（C11 7.21.6.1p6——a/A/e/E/f/F/g/G 族；`%#.0f` 1.5 → `2.` 而非 `2`；
/// g 族由 format_g 的 alt 保尾零路径已含此语义）。
fn format_fixed_case(
  val : Double,
  prec : Int32,
  upper : Bool,
  alt~ : Bool = false,
) -> String {
  let s0 = format_fixed(val, prec)
  // # + 有限值 + 结果无点（prec=0 整数形态）→ 补尾点；nan/inf/-inf 不涉
  let s = if alt && !s0.contains(".") && !s0.contains("n") && !s0.contains("i") {
    s0 + "."
  } else {
    s0
  }
  if !upper {
    return s
  }
  if s == "nan" {
    return "NAN"
  }
  if s == "inf" {
    return "INF"
  }
  if s == "-inf" {
    return "-INF"
  }
  s
}

///|
/// `%a`/`%A` hexfloat（#427 批 B4 新增臂——M20 A-2 / M21 A3：旧实现
/// `is_known_conv_code` 认 a/A 且计数弹参，但 `format_printf_string`
/// 无输出臂——字母原样 + 实参不消耗 + 下一个转换符错位吃参）。形态随
/// **glibc「最短精确」**口径（`0x1.8p+0`；UCRT 恒 13 位全印
/// `0x1.8000000000000p+0` 属实现定义域平台分叉——速查表 P3 / M21 §四
/// 建议随 glibc/C 标准，本臂不进 clang 直拍语料域）；指数为二进制指数
/// 的十进制、恒符号**不补零**（`p+0` / `p-4` / `p+1023`）。
///
/// 精度语义（C11 7.21.6.1p8）：缺省 = 最短精确表示（去尾零）；精度
/// 在场 = 小数点后十六进制位数，52 bit 尾数按 half-even 舍入（与
/// format_fixed/format_g 同口径），进位（0xff…f → 0x100）归一为
/// `1.000…×2^(e+1)`；精度 > 13 超出 52 bit 精确域的部分补零；
/// `#`（alt）+ 精度 0 保留小数点（`0x1.p+0`）。
fn format_a(
  val : Double,
  precision : Int32?,
  upper : Bool,
  alt~ : Bool = false,
) -> String {
  let x = if upper { "0X" } else { "0x" }
  let pc = if upper { "P" } else { "p" }
  if val.is_nan() {
    return if upper { "NAN" } else { "nan" }
  }
  if val.is_inf() {
    let s = if upper { "INF" } else { "inf" }
    return if val < 0.0 { "-\{s}" } else { s }
  }
  let neg = val.reinterpret_as_uint64() >> 63 == 1UL
  let sign = if neg { "-" } else { "" }
  if val == 0.0 {
    // ±0x0p+0（glibc 同形；负零保符号）
    return "\{sign}\{x}0p+0"
  }
  let bits = val.reinterpret_as_uint64()
  let biased = ((bits >> 52) & 0x7FFUL).to_int()
  let frac = bits & 0xFFFFFFFFFFFFFUL
  let mut lead = if biased == 0 { "0" } else { "1" }
  // 次正规：0.xxx × 2^-1022（隐含位 0）；正规：1.xxx × 2^(biased-1023)
  let exp2 = if biased == 0 { -1022 } else { biased - 1023 }
  // 13 位 hex 尾数（52 bit 补零）→ 按精度截断 + half-even 舍入
  let mut hexs = u64_hex_lower(frac)
  while hexs.length() < 13 {
    hexs = "0" + hexs
  }
  match precision {
    None =>
      // 缺省 = 最短精确（glibc）：去尾零（全零 → 无小数段）
      while hexs.length() > 0 && hexs[hexs.length() - 1].to_int() == 48 {
        hexs = hexs[0:hexs.length() - 1].to_owned()
      }
    Some(q) =>
      if q >= 0 && q < 13 {
        let shift = 52 - q * 4
        let v = frac >> shift
        let rem = frac & ((1UL << shift) - 1UL)
        let half = 1UL << (shift - 1)
        // 进位统一视角：R = lead 数字 + q 位尾数构成的定点 hex 数，舍入
        // 只加在尾数 LSB 上。half-even 平局取偶判**舍入前完整整数**
        // r_pre 的奇偶（format_fixed 的 q0 同款；%.0a 1.5 → r_pre=1 奇
        // → 进位 2 = clang `0x2p+0`）。正规 lead 恒为隐含位 1（R ∈ [1,2)，
        // 舍入最多推到 2——lead 数字 +1、指数**不变**）；次正规 lead=0
        //（R ∈ [0,1)，舍入到 1.0 = 跨入正规最小值 0x1.000…p-1022，指数
        // 本就 -1022 不变）。两形态均由 r_int 的统一拆分自然覆盖。
        let lead_val : UInt64 = if biased == 0 { 0UL } else { 1UL }
        let r_pre = (lead_val << (q * 4)) + v
        let vr = if rem > half || (rem == half && (r_pre & 1UL) == 1UL) {
          v + 1UL
        } else {
          v
        }
        let r_int = (lead_val << (q * 4)) + vr
        lead = u64_hex_lower(r_int >> (q * 4))
        // q=0 时尾数段为空（u64_hex_lower(0) 给 "0" 会污染——clang
        // %.0a 1.5 → 0x2p+0 无小数段）
        if q == 0 {
          hexs = ""
        } else {
          hexs = u64_hex_lower(r_int & ((1UL << (q * 4)) - 1UL))
          while hexs.length() < q {
            hexs = "0" + hexs
          }
        }
      } else if q > 13 {
        // 超精确域：13 位精确位后补零（glibc %.20a 同形）
        hexs = hexs + "0".repeat(q - 13)
      }
  }
  let body = if hexs.length() > 0 {
    "\{lead}.\{hexs}"
  } else if alt {
    "\{lead}."
  } else {
    lead
  }
  let es = if exp2 < 0 { "-" } else { "+" }
  let ea = if exp2 < 0 { -exp2 } else { exp2 }
  "\{sign}\{x}\{body}\{pc}\{es}\{ea}"
}

///|
/// 整数转换的精度语义（C11 7.21.6.1——PR #313 审阅 P2-2 语料战果，
/// 2026-10-26）：precision = **最少数字位数**（不足前导零补足；符号不
/// 占位数，-42 精度 4 ⇒ "-0042"）；精度 0 且值 0 ⇒ 空串（C 特例——
/// 符号一并省）。旧 d/i/u/x/X/o 六分支只 apply_width，精度整个被忽略
/// （`printf("%.*d", 3, 9)` 给 "9" 而 clang 给 "009"）。# 前缀（0x/0）
/// 与 0 旗标的精度交互是更深边缘（C11：精度在场 0 旗标被忽略；# 的
/// 八进制前导 0 被精度覆盖）——本单源只管 digits 补零，# 前缀由调用点
/// 在补零后拼接（x/X/o 分支），0 旗标×精度组合暂不区分（语料不锚，
/// 随差异台账登记）。
fn pad_int_digits(raw : String, precision : Int32?) -> String {
  let p = match precision {
    Some(v) => if v >= 0 { v } else { return raw }
    None => return raw
  }
  if raw.has_prefix("-") {
    let digits = raw[1:].to_owned()
    if p == 0 && digits == "0" {
      return ""
    }
    let n = digits.length()
    if n < p {
      "-\{"0".repeat(p - n)}\{digits}"
    } else {
      raw
    }
  } else {
    if p == 0 && raw == "0" {
      return ""
    }
    let n = raw.length()
    if n < p {
      "0".repeat(p - n) + raw
    } else {
      raw
    }
  }
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
pub fn format_fixed(val : Double, prec : Int32) -> String {
  if val.is_nan() {
    // #427 批 B4（M20 A-12 / A2 锚 A1 翻面）：C11 7.21.6.1 小写
    // `nan`（glibc 对 0.0/0.0 运行时折叠给 `-nan`——符号位差为 M20
    // D-4 平台域，非本臂翻面目标）；旧 "NaN" 系 Rust `{:?}` 拼法照搬
    return "nan"
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
fn big_pow10(n : Int32) -> @bigint.BigInt {
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
fn big_fixed_to_string(q : @bigint.BigInt, prec : Int32) -> String {
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
/// 格式串 + 参数 → 输出（Rust `format_printf_string` 照搬；2026-10-05
/// 批二-b 重构为**字节域累积**——DIFF-LIB-PRINTF-01 销案：%c 低字节单
/// 字节直出（旧 char 通道两字节化照搬）、%s 字节原样（旧 decode_lossy
/// 对非 UTF-8 字节串有损）、%.Ns 精度截断（旧整串输出）、+ / 空格 /
/// # 旗标（旧无效）。数字族仍在 String 域格式化后 encode 拼接（ASCII
/// 无损），# 前缀在此加（x→0x / X→0X / o→0，非零值时）。
fn format_printf_string(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  fmt : Array[Int32],
  args : Array[UInt64],
) -> Result[Bytes, @memory.MemFault] {
  let scan = FmtScan::{ s: fmt, i: 0, }
  let acc : Array[Byte] = []
  fn push_str(t : String) -> Unit {
    let b = @utf8.encode(t)
    for i = 0; i < b.length(); i = i + 1 {
      acc.push(b[i])
    }
  }
  fn push_bytes(b : Bytes) -> Unit {
    for i = 0; i < b.length(); i = i + 1 {
      acc.push(b[i])
    }
  }
  let mut used = 0
  while true {
    let ch = match scan.peek() {
      Some(c) => {
        scan.advance()
        c
      }
      None => break
    }
    // #82（2026-10-13 报 / 2026-10-14 修）：%% 折叠不消耗实参、判定与
    // 参数组无关（零参 printf("%%") 与参数耗尽位 "%d %%" 旧输出 "%%"
    // vs clang/gcc 折叠 "%"）。
    //
    // #427 批 B4（2026-11-03，M21 A4）：**旧门条件整体退役**——旧
    // `(used < args.length() || peek==%) && ch==%` 在参数耗尽位短路、
    // `%` 原样透出：`[%q]`（1 参）保留 `%q`、`[%d%q]`（1 参）保留
    // `%q`、`[%5q]`（1 参；未知不计参 → vm 弹 0 参 → args 空 → 门恒
    // 闭）整串透出——同一未知字母随实参配置产出多种输出，clang 恒为
    // 「丢 `%` 输出字母、不消耗实参」。现统一走 parse 路径：未知 spec
    //（裸/带修饰）落未知臂输出字母；已知 spec 参数不足时值参数按 0
    // 兜底（该形态实际不可达——printf pipeline 守卫 trap / sprintf
    // vm 弹参栈下溢 / vprintf 游标读越界 MemFault 三守卫先拦，B-5
    // 登记）；行尾孤立 % 原样透出（glibc 同形；UCRT 吞——真值间自
    // 分歧的平台方言域，随 glibc 侧登记）。
    if ch == 37 {
      let nx = scan.peek()
      if nx == Some(37) {
        push_str("%")
        scan.advance()
        continue
      }
      if nx is None {
        push_str("%") // 行尾孤立 %（原样透出——glibc 同形）
        continue
      }
      match parse_format_spec(scan) {
        Some(t) => {
          let spec = t.0
          let len_mod = t.1
          let mut precision = t.2
          let mut width = t.3
          let mut flags = t.4
          // %*d 批四（2026-10-07）：星号宽度/精度从参数组**前位**取
          //（语义序 ("%*d", w, 42)——星号参数在值参数前，dispatch 弹
          // 参后 args 为语义序）。**负宽度 = 左对齐 |w|（as if "%-*d"，
          // C 语义——审阅 P2-1 修正，旧 clamp 0 与 Clang 不符）；负精度
          // = 视同省略（precision None）**；超 PRINTF_FIELD_BUDGET 教学
          // 截断（Clang 会尝试同量级输出——U2#9 静态闸的运行期对位）。
          if t.5 && used < args.length() {
            let w = args[used].to_uint().reinterpret_as_int()
            if w < 0 {
              let abs_w = -w
              width = Some(
                if abs_w > PRINTF_FIELD_BUDGET {
                  PRINTF_FIELD_BUDGET
                } else {
                  abs_w
                },
              )
              if !flags.contains("-") {
                flags = flags + "-"
              }
            } else {
              width = Some(
                if w > PRINTF_FIELD_BUDGET {
                  PRINTF_FIELD_BUDGET
                } else {
                  w
                },
              )
            }
            used += 1
          }
          if t.6 && used < args.length() {
            let p = args[used].to_uint().reinterpret_as_int()
            // 负精度视同省略（C 语义——审阅 P2-1）
            precision = if p < 0 {
              None
            } else if p > PRINTF_FIELD_BUDGET {
              Some(PRINTF_FIELD_BUDGET)
            } else {
              Some(p)
            }
            used += 1
          }
          // 值参数（星号消耗后可能越界——参数不足形态按 0 字面输出）
          let arg = if used < args.length() { args[used] } else { 0UL }
          // C11 7.21.6.1：d/i/o/u/x/X **精度在场 → 0 旗标被忽略**（#427
          // 批 B4 / M21 A1：`%05.0d` 0 → 空格×5 而非 00000——旧口径输出
          // 错值，且精度 0 × 值 0 特例的空串叠加 0 旗标进 zero_pad 分支
          // 即 `body[0]` 空串索引、三臂进程崩溃；apply_width 守卫已前置，
          // 此处根除「精度在场仍零填充」的语义错用。0 旗标对 a/e/f/g
          // 不受精度禁用（flags 原样传下游浮点臂）
          let flags_num = if precision is Some(_) &&
            (
              spec == 100 ||
              spec == 105 ||
              spec == 117 ||
              spec == 120 ||
              spec == 88 ||
              spec == 111
            ) {
            strip_flag_zero(flags)
          } else {
            flags
          }
          if spec == 100 || spec == 105 {
            // d / i（+ / 空格旗标：正数带符号前缀）。#427 批 B4（M20
            // A-4）：h/hh 长度修饰截断（%hhd 300 → 44、%hhd -1 → -1
            // ——低 8/16 位符号扩展；变参实参 int 提升 4 字节，截断在
            // 打印侧；l 维持 LLP64 long=4 旧口径（D-1），ll 8 字节）
            let val0 = match len_mod {
              "ll" => arg.reinterpret_as_int64().to_string()
              "hh" => printf_trunc_signed(arg, 8).to_string()
              "h" => printf_trunc_signed(arg, 16).to_string()
              _ => arg.to_uint().reinterpret_as_int().to_string()
            }
            // 精度 = 最少数字位数（#313 审阅 P2-2——pad 单源）
            let val = pad_int_digits(val0, precision)
            push_str(apply_width(val, width, flags_num, signed_pos=true))
          } else if spec == 117 {
            // u（hh/h 截断零扩展：%hhu 70000 → 112、%hu 70000 → 4464）
            let val0 = match len_mod {
              "ll" => arg.to_string()
              "hh" => printf_trunc_unsigned(arg, 8).to_string()
              "h" => printf_trunc_unsigned(arg, 16).to_string()
              _ => arg.to_uint().to_string()
            }
            let val = pad_int_digits(val0, precision)
            push_str(apply_width(val, width, flags_num))
          } else if spec == 120 {
            // x（# → 0x 前缀，非零值；#427 批 B4 / M20 A-5：前缀属数值
            // 部分经 apply_width prefix~ 传参——零填充时 0x0000ff（旧
            // 00000xff 前缀排到填充外）；精度补零属数字段（pad_int_digits
            // 先行）；hh/h 截断同 u 臂）
            let raw0 = match len_mod {
              "ll" => u64_hex_lower(arg)
              "hh" => u64_hex_lower(printf_trunc_unsigned(arg, 8))
              "h" => u64_hex_lower(printf_trunc_unsigned(arg, 16))
              _ => u64_hex_lower(arg.to_uint().to_uint64())
            }
            let raw = pad_int_digits(raw0, precision)
            let prefix = if flags.contains("#") && arg != 0UL {
              "0x"
            } else {
              ""
            }
            push_str(apply_width(raw, width, flags_num, prefix~))
          } else if spec == 88 {
            // X（# → 0X；prefix~ 语义同 x 臂）
            let raw0 = match len_mod {
              "ll" => u64_hex_upper(arg)
              "hh" => u64_hex_upper(printf_trunc_unsigned(arg, 8))
              "h" => u64_hex_upper(printf_trunc_unsigned(arg, 16))
              _ => u64_hex_upper(arg.to_uint().to_uint64())
            }
            let raw = pad_int_digits(raw0, precision)
            let prefix = if flags.contains("#") && arg != 0UL {
              "0X"
            } else {
              ""
            }
            push_str(apply_width(raw, width, flags_num, prefix~))
          } else if spec == 111 {
            // o（PR #462 审阅 P2-1/P2-2 处置：`#` 对 o 的 C11 7.21.6.1p6
            // 语义 =「**提高精度**以强制首位数字为 0」——与精度补零是同一
            // 件事而非叠加（旧实现 pad_int_digits 补零后再拼 prefix "0"
            // → `%#.3o` 8 给 `0010` 而 clang 为 `010`）。现非零值 + # 时
            // 精度提至 max(prec, 位数+1)、不再另加 prefix（零填充/空格
            // 填充形态由此自然正确）；括号句特例「值 0 且精度 0 → 单个
            // 0」——`%#.0o` 0 旧给空串（pad 空串特例 + # 的 arg!=0 条件
            // 双重排掉），现补 "0"；`%#o` 0 不提精度（clang "0" 非 "00"）
            let raw0 = match len_mod {
              "ll" => u64_octal(arg)
              "hh" => u64_octal(printf_trunc_unsigned(arg, 8))
              "h" => u64_octal(printf_trunc_unsigned(arg, 16))
              _ => u64_octal(arg.to_uint().to_uint64())
            }
            let prec_eff = if flags.contains("#") && arg != 0UL {
              let need = raw0.length() + 1
              match precision {
                Some(p) => if p >= need { precision } else { Some(need) }
                None => Some(need)
              }
            } else {
              precision
            }
            let mut raw = pad_int_digits(raw0, prec_eff)
            if raw == "" && flags.contains("#") {
              // 值 0 + 精度 0 + #：C11 p6 括号句 → 单个 "0"
              raw = "0"
            }
            push_str(apply_width(raw, width, flags_num))
          } else if spec == 112 {
            // p（oracle 实测 "0x1234"——小写不填充）
            push_str(
              apply_width(
                "0x\{u64_hex_lower(arg.to_uint().to_uint64())}",
                width,
                flags,
              ),
            )
          } else if spec == 102 {
            // f（0 旗标不受精度禁用——flags 原样；NaN/inf 小写）
            let f = arg.reinterpret_as_double()
            let pr = match precision {
              Some(pr) => pr
              None => 6
            }
            push_str(
              apply_width(
                format_fixed_case(f, pr, false, alt=flags.contains("#")),
                width,
                flags,
                signed_pos=true,
              ),
            )
          } else if spec == 70 {
            // F（#427 批 B4 / M20 A-2 / M21 A3：旧无输出臂——字母原样 +
            // 实参不消耗 + 后续转换符错位吃参三连错；计数面（病 26 白
            // 名单）旧已认故参数不缺、假值不弹。%F = %f + 大写 inf/nan
            //（C11 同义转换，速查表 G10 真值 NAN））
            let f = arg.reinterpret_as_double()
            let pr = match precision {
              Some(pr) => pr
              None => 6
            }
            push_str(
              apply_width(
                format_fixed_case(f, pr, true, alt=flags.contains("#")),
                width,
                flags,
                signed_pos=true,
              ),
            )
          } else if spec == 101 {
            // e（#71 病 21：此前无臂落「未知说明符」输出字面 %e）
            let f = arg.reinterpret_as_double()
            let pr = match precision {
              Some(pr) => pr
              None => 6
            }
            push_str(
              apply_width(
                format_e(f, pr, false, alt=flags.contains("#")),
                width,
                flags,
                signed_pos=true,
              ),
            )
          } else if spec == 69 {
            // E
            let f = arg.reinterpret_as_double()
            let pr = match precision {
              Some(pr) => pr
              None => 6
            }
            push_str(
              apply_width(
                format_e(f, pr, true, alt=flags.contains("#")),
                width,
                flags,
                signed_pos=true,
              ),
            )
          } else if spec == 103 {
            // g（#427 批 B4：# 旗标 = 不删尾零（M20 A-6）——alt~ 透传
            // format_a/format_g 的精确路径见其函数头注）
            let f = arg.reinterpret_as_double()
            let pr = match precision {
              Some(pr) => pr
              None => 6
            }
            push_str(
              apply_width(
                format_g(f, pr, false, alt=flags.contains("#")),
                width,
                flags,
                signed_pos=true,
              ),
            )
          } else if spec == 71 {
            // G
            let f = arg.reinterpret_as_double()
            let pr = match precision {
              Some(pr) => pr
              None => 6
            }
            push_str(
              apply_width(
                format_g(f, pr, true, alt=flags.contains("#")),
                width,
                flags,
                signed_pos=true,
              ),
            )
          } else if spec == 97 || spec == 65 {
            // a / A（#427 批 B4 / M20 A-2 / M21 A3：hexfloat 新臂——
            // glibc 最短精确口径（见 format_a 头注）；**精度缺省 = 最短**
            // 非 6——%a 的精度语义与 f/e/g 族独立，precision 直传 Int32?；
            // 实参消耗 1（double 8 字节，va_spec_width 同步））
            let f = arg.reinterpret_as_double()
            push_str(
              apply_width(
                format_a(f, precision, spec == 65, alt=flags.contains("#")),
                width,
                flags,
                signed_pos=true,
              ),
            )
          } else if spec == 110 {
            // n（#427 批 B4 / M20 A-1：printf %n 写回「到此处已输出的
            // 字符数」（C11 7.21.6.1p8——本调用累积字节，acc 为字节域，
            // %c/%s 字节直出同序）；scanf 侧 %n 已修（#269）的对称补齐。
            // 写回宽度按长度修饰分档（hh=1 / h=2 / 默认·l=4（LLP64
            // long=4，与 scanf %ln 同口径）/ ll=8——复用
            // scanf_store_by_lenmod 的分档编码 2=ll/3=h/4=hh）；无输出
            // （不 push）；写失败 → MemFault（调用方转教学 trap，C 侧
            // 为 UB））
            let cnt = acc.length().to_uint64()
            let store_code : Int32 = match len_mod {
              "ll" => 2
              "h" => 3
              "hh" => 4
              _ => 0
            }
            match
              scanf_store_by_lenmod(mem, map, arg.to_uint(), store_code, cnt) {
              Ok(_) => ()
              Err(f) => return Err(f)
            }
          } else if spec == 115 {
            // s：字节原样（DIFF-LIB-PRINTF-01——旧 decode_lossy 对
            // 非 UTF-8 字节串有损）+ %.Ns 精度截断（旧忽略精度）+
            // 字节域宽度
            match read_cstring(mem, map, arg.to_uint()) {
              Ok(bytes) => {
                let limited : Bytes = match precision {
                  Some(pr) =>
                    if pr < bytes.length() {
                      let cut : Array[Byte] = []
                      for q = 0; q < pr; q = q + 1 {
                        cut.push(bytes[q])
                      }
                      Bytes::from_array(cut)
                    } else {
                      bytes
                    }
                  None => bytes
                }
                push_bytes(apply_width_bytes(limited, width, flags~))
              }
              Err(f) => return Err(f)
            }
          } else if spec == 99 {
            // c：低字节单字节直出（DIFF-LIB-PRINTF-01——旧 char 通道
            // 200 → U+00C8 → UTF-8 两字节 C3 88 照搬；现与 putchar
            // 单字节语义一致）+ 字节域宽度
            let one = Bytes::make(1, (arg & 0xFFUL).to_int().to_byte())
            push_bytes(apply_width_bytes(one, width, flags~))
          } else {
            // 未知说明符（病 26）：**% 丢弃、字母原样、不消耗实参**
            //（clang 实测 "A%qB" → "AqB"；旧「透出 %q + 消耗一个」
            // 双错——照搬形态，探针证伪翻面）。#427 批 B4 后此处只剩
            // **带 flags/宽度/精度前缀**的未知形态（`%5q`——裸未知字母
            // 已在门条件前移处理）
            push_str(Int32::unsafe_to_char(spec).to_string())
            continue
          }
          used = used + 1
        }
        None => ()
      }
    } else {
      push_str(Int32::unsafe_to_char(ch).to_string())
    }
  }
  Ok(Bytes::from_array(acc))
}

///|
/// printf 族参数消耗总数（vm 分发侧弹参数数用——%*d 批四 2026-10-07：
/// 每 spec = 1 + 星号宽度 + 星号精度；dispatch 原按说明符个数弹参，
/// 星号 spec 曾少弹导致栈失衡）。
pub fn format_arg_count(fmt : Array[Int32]) -> Int32 {
  let scan = FmtScan::{ s: fmt, i: 0, }
  let mut n = 0
  while true {
    match scan.peek() {
      Some(ch) => {
        scan.advance()
        if ch == 37 {
          match scan.peek() {
            Some(nx) =>
              if nx == 37 {
                scan.advance() // %%
              } else {
                match parse_format_spec(scan) {
                  Some(t) =>
                    if is_known_conv_code(t.0) {
                      n += 1
                      if t.5 {
                        n += 1
                      }
                      if t.6 {
                        n += 1
                      }
                    } else {
                      () // 病 26：未知字母不取参（与计数器/输出侧同口径）
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
  n
}

///|
/// scanf 族指针参数计数（vm 分发侧用——只数 `%` 转换符，空白指令与
/// 字面量不计；与 `parse_scanf_specs` 的 Spec 分支计数同口径）。
pub fn scanf_spec_count(fmt : Array[Int32]) -> Int32 {
  let mut count = 0
  for it in parse_scanf_specs(fmt) {
    match it {
      // 赋值抑制（%*d 批四 2026-10-07）不消耗指针参数
      Spec(_, _, false, _) => count = count + 1
      // #149（2026-10-18）：scanset 同消耗一个指针参数（VM 弹栈按本
      // 计数——漏数致 ptrs 短缺，scanset 臂 arg_idx 越界提前断链）
      Scanset(_, _, false, _) => count = count + 1
      _ => ()
    }
  }
  count
}
