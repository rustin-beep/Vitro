///| 数学族 22 个 handler（Rust `host/math.rs` 全文照搬，勘察 §1.7 族 G）。
///
/// 纯函数：**位模式进出**（值栈承载 u64 位模式，f64 经
/// `reinterpret_as_uint64` / `reinterpret_as_double` 零损耗往返——探针实测
/// `3.14 ↔ 4614253070214989087`）。`libm` 对位：`@math`（`log` → `ln`）+
/// builtin 的 `Double::sqrt` / `Double::abs` / `Double::mod`（IEEE fmod 语义，
/// 探针实测 `mod(7.5, 0.0) = NaN`）。
///
/// **vm 接线义务（登记）**：oracle 的弹参顺序**两族不一致**——`pow` 先弹 x
/// （`math.rs:23-25`：`let x = pop(); let y = pop();`），`atan2` 先弹 y
/// （`:93-95`：`let y = pop(); let x = pop();`）——本包一律按 C 语义命名参数
/// （`host_pow(x, y)` / `host_atan2(y, x)`），压栈序由 vm 接线时逐 handler
/// 对 codegen 的压参方向核实，**不得统一假设**。
///
/// **位级对拍风险（登记，D 级对拍时收口）**：`@math` 与 Rust `libm` 是两套
/// 实现，超出现值语料（整点/半点/常见输入）的 ULP 级差异可能存在——golden
/// 语料以 Clang（平台 libm）为真值，三套数学库的差异入差异台账（S8）。

///|
/// `abs(n)`——`INT_MIN` 取反回绕（Rust `wrapping_neg`，位模式符号扩展后压栈）。
pub fn host_abs(n : Int) -> UInt64 {
  let v = if n < 0 { 0 - n } else { n }
  v.to_int64().reinterpret_as_uint64()
}

///|
/// `llabs(n)`
pub fn host_llabs(n : Int64) -> UInt64 {
  let v = if n < 0L { 0L - n } else { n }
  v.reinterpret_as_uint64()
}

///|
/// `sin(x)`
pub fn host_sin(x_bits : UInt64) -> UInt64 {
  @math.sin(x_bits.reinterpret_as_double()).reinterpret_as_uint64()
}

///|
/// `cos(x)`
pub fn host_cos(x_bits : UInt64) -> UInt64 {
  @math.cos(x_bits.reinterpret_as_double()).reinterpret_as_uint64()
}

///|
/// `sqrt(x)`
pub fn host_sqrt(x_bits : UInt64) -> UInt64 {
  Double::sqrt(x_bits.reinterpret_as_double()).reinterpret_as_uint64()
}

///|
/// `pow(x, y)`
pub fn host_pow(x_bits : UInt64, y_bits : UInt64) -> UInt64 {
  @math.pow(x_bits.reinterpret_as_double(), y_bits.reinterpret_as_double()).reinterpret_as_uint64()
}

///|
/// `atan(x)`
pub fn host_atan(x_bits : UInt64) -> UInt64 {
  @math.atan(x_bits.reinterpret_as_double()).reinterpret_as_uint64()
}

///|
/// `log(x)`（自然对数——Rust `libm::log`，MoonBit 位对 `@math.ln`）
pub fn host_log(x_bits : UInt64) -> UInt64 {
  @math.ln(x_bits.reinterpret_as_double()).reinterpret_as_uint64()
}

///|
/// `exp(x)`
pub fn host_exp(x_bits : UInt64) -> UInt64 {
  @math.exp(x_bits.reinterpret_as_double()).reinterpret_as_uint64()
}

///|
/// `tan(x)`
pub fn host_tan(x_bits : UInt64) -> UInt64 {
  @math.tan(x_bits.reinterpret_as_double()).reinterpret_as_uint64()
}

///|
/// `log10(x)`
pub fn host_log10(x_bits : UInt64) -> UInt64 {
  @math.log10(x_bits.reinterpret_as_double()).reinterpret_as_uint64()
}

///|
/// `fabs(x)`
pub fn host_fabs(x_bits : UInt64) -> UInt64 {
  Double::abs(x_bits.reinterpret_as_double()).reinterpret_as_uint64()
}

///|
/// `ceil(x)`
pub fn host_ceil(x_bits : UInt64) -> UInt64 {
  @math.ceil(x_bits.reinterpret_as_double()).reinterpret_as_uint64()
}

///|
/// `floor(x)`
pub fn host_floor(x_bits : UInt64) -> UInt64 {
  @math.floor(x_bits.reinterpret_as_double()).reinterpret_as_uint64()
}

///|
/// `round(x)`
pub fn host_round(x_bits : UInt64) -> UInt64 {
  @math.round(x_bits.reinterpret_as_double()).reinterpret_as_uint64()
}

///|
/// `fmod(x, y)`——IEEE 语义（`fmod(x, 0) = NaN`，探针实测对齐 libm）。
pub fn host_fmod(x_bits : UInt64, y_bits : UInt64) -> UInt64 {
  Double::mod(x_bits.reinterpret_as_double(), y_bits.reinterpret_as_double()).reinterpret_as_uint64()
}

///|
/// `asin(x)`
pub fn host_asin(x_bits : UInt64) -> UInt64 {
  @math.asin(x_bits.reinterpret_as_double()).reinterpret_as_uint64()
}

///|
/// `acos(x)`
pub fn host_acos(x_bits : UInt64) -> UInt64 {
  @math.acos(x_bits.reinterpret_as_double()).reinterpret_as_uint64()
}

///|
/// `atan2(y, x)`
pub fn host_atan2(y_bits : UInt64, x_bits : UInt64) -> UInt64 {
  @math.atan2(y_bits.reinterpret_as_double(), x_bits.reinterpret_as_double()).reinterpret_as_uint64()
}

///|
/// `sinh(x)`
pub fn host_sinh(x_bits : UInt64) -> UInt64 {
  @math.sinh(x_bits.reinterpret_as_double()).reinterpret_as_uint64()
}

///|
/// `cosh(x)`
pub fn host_cosh(x_bits : UInt64) -> UInt64 {
  @math.cosh(x_bits.reinterpret_as_double()).reinterpret_as_uint64()
}

///|
/// `tanh(x)`
pub fn host_tanh(x_bits : UInt64) -> UInt64 {
  @math.tanh(x_bits.reinterpret_as_double()).reinterpret_as_uint64()
}
