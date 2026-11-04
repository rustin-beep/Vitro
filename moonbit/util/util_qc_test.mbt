// util 层 quickcheck 属性批（QC 批，2026-11-04）——moon prove 盲区的互补
// 防线（tmp/moon_prove/report.md §8.2 方案 A）。prove 的 frontend 拒绝
// String/SB/移位/迭代器（报告 §2），util 恰是 String/Bytes 密集层——本文件
// 以采样级属性（count=300 + 双种子固定 + 内置 @shrink 反例收缩）补该面。
//
// 形态约定（与 kimicc qc_test 先例的差异）：每属性一个 test 块，块内双
// seed 各跑一次（seed=20261104 / 427）——失败时反例打印自带 seed 与收缩
// 后形态，直接重跑同 seed 即可复现。属性与 util_wbtest 的例锚互补勿重复
// （例锚管已知反例形态，属性管未枚举输入域）。
//
// prove 三态对照（每属性注明；三态 = 证过/超时/frontend 拒，出处报告 §3）：
// - str_cmp 反对称：prove 60s 仍 timeout（∃ witness 传递卡 Z3）——本批旗舰
// - String 域属性（utf8/base64 roundtrip 等）：prove frontend 全拒
// - i64_to_i32_bits：Int64 支持度 prove 未单测（报告 §4.1 未覆盖）
// - le_u32/le_u64 域性质：prove 码点数组模型可行（byte_get 亚秒证过）但
//   拼装组合语义未做——双保险

///|
/// str_cmp 反对称：sign(cmp(a,b)) == -sign(cmp(b,a))。
/// prove 三态：**60s 超时证不动**（报告 §3.2 试点 b——∃ witness 传递需
/// 手工引理重构规范）；采样秒过，本批存在的首要理由。
test "qc_str_cmp_antisymmetry" {
  let sign = (r : Int32) => if r < 0 { -1 } else if r > 0 { 1 } else { 0 }
  for seed in [20261104, 427] {
    @quickcheck.check(
      (t : (String, String)) => {
        sign(@util.str_cmp(t.0, t.1)) == -sign(@util.str_cmp(t.1, t.0))
      },
      count=300,
      max_size=32,
      seed=seed.to_uint64(),
    )
  }
}

///|
/// str_cmp 自反：cmp(a,a) == 0（含空串与代理对串）。
/// prove 三态：完整规范 38/45 goal 的子集（未单独出引理）——双保险。
test "qc_str_cmp_reflexivity" {
  for seed in [20261104, 427] {
    @quickcheck.check(
      (a : String) => @util.str_cmp(a, a) == 0,
      count=300,
      max_size=32,
      seed=seed.to_uint64(),
    )
  }
}

///|
/// str_cmp 传递：a<b 且 b<c 蕴含 a<c。前提不满足的样本为空真——**前提
/// 命中守卫**（PR #476 审阅 P3-1：实现缺陷可抽空前提使属性恒真——注入
/// 「cmp 恒返 1」后本属性仍绿即此形态；命中数为 0 即对该 seed 无判别力，
/// fail loud 而非静默空绿）。
/// prove 三态：未做（三条完整规范的组合引理，比反对称更重）——qc 补位。
test "qc_str_cmp_transitivity" {
  for seed in [20261104, 427] {
    let mut hits = 0
    @quickcheck.check(
      (t : (String, String, String)) => {
        let (a, b, c) = t
        if @util.str_cmp(a, b) < 0 && @util.str_cmp(b, c) < 0 {
          hits = hits + 1
          @util.str_cmp(a, c) < 0
        } else {
          true
        }
      },
      count=300,
      max_size=32,
      seed=seed.to_uint64(),
    )
    guard hits > 0 else {
      fail(
        "transitivity 前提零命中（seed=\{seed}）——属性对该 seed 空真",
      )
    }
  }
}

///|
/// i64_to_i32_bits 界内恒等：Int32 域内值经 i64 往返无损。
/// prove 三态：Int64 支持 prove 未单测（报告 §4.1 未覆盖）——qc 补位。
test "qc_i64_to_i32_bits_in_range_identity" {
  for seed in [20261104, 427] {
    @quickcheck.check(
      (v : Int32) => @util.i64_to_i32_bits(v.to_int64()) == v,
      count=300,
      seed=seed.to_uint64(),
    )
  }
}

///|
/// i64_to_i32_bits 高 32 位丢弃：任意 hi，(hi<<32)|lo 截断 == 仅 lo 的
/// 截断（位截断语义只看低半）。
/// **判别面登记**（PR #476 审阅 P3-1）：本属性判「输出只依低 32 位」——
/// 符号位泄漏形态红（注入 +(v>>62)，falsified after 3）；Int64::to_int
/// 截断族形态恒绿（减 2^32 不改低 32 位，issue #475 等价性）——界内偏移
/// 类缺陷由 in_range_identity 判别，两属性互补不重叠。
/// prove 三态：同上未覆盖——qc 补位（与上属性合力覆盖「无损 + 丢弃」两向）。
test "qc_i64_to_i32_bits_high_half_dropped" {
  for seed in [20261104, 427] {
    @quickcheck.check(
      (t : (Int32, Int32)) => {
        let (hi, lo) = t
        let full = (hi.to_int64() << 32) | (lo.to_int64() & 0xFFFFFFFFL)
        @util.i64_to_i32_bits(full) ==
        @util.i64_to_i32_bits(lo.to_int64() & 0xFFFFFFFFL)
      },
      count=300,
      seed=seed.to_uint64(),
    )
  }
}

///|
/// le_u32_at 写读对偶：UInt32 按小端拆 4 字节写回，拼装读必得原值。
/// prove 三态：byte_get 域性质亚秒证过（报告 §3.2 卡点对照），拼装组合
/// 未做——双保险。
test "qc_le_u32_roundtrip_write_read" {
  for seed in [20261104, 427] {
    @quickcheck.check(
      (v : UInt32) => {
        let b : FixedArray[Byte] = FixedArray::make(4, b'\x00')
        b[0] = (v & 0xFFU).to_byte()
        b[1] = ((v >> 8) & 0xFFU).to_byte()
        b[2] = ((v >> 16) & 0xFFU).to_byte()
        b[3] = ((v >> 24) & 0xFFU).to_byte()
        @util.le_u32_at(b, 0) == v
      },
      count=300,
      seed=seed.to_uint64(),
    )
  }
}

///|
/// le_u64_at 写读对偶（同上，u64 位宽）。
/// prove 三态：同上——双保险。
test "qc_le_u64_roundtrip_write_read" {
  for seed in [20261104, 427] {
    @quickcheck.check(
      (v : UInt64) => {
        let b : FixedArray[Byte] = FixedArray::make(8, b'\x00')
        let mut k = 0
        while k < 8 {
          b[k] = ((v >> (k * 8)) & 0xFFUL).to_byte()
          k += 1
        }
        @util.le_u64_at(b, 0) == v
      },
      count=300,
      seed=seed.to_uint64(),
    )
  }
}

///|
/// 越界不设防的补偿采样：随机字节串 + 域内随机偏移（wrapper 保证
/// off ∈ [0, len-8]——全随机 Int32 偏移几乎必被 filter 丢弃，自造域），
/// le_u64_at 必等于两个 le_u32_at 的高低半拼装——抓两实现间漂移。
test "qc_le_u64_composes_from_two_u32" {
  for seed in [20261104, 427] {
    @quickcheck.check(
      (s : QcByteSlice) => {
        let fa : FixedArray[Byte] = FixedArray::make(s.bytes.length(), b'\x00')
        for i in 0..<s.bytes.length() {
          fa[i] = s.bytes[i]
        }
        let lo = @util.le_u32_at(fa, s.off)
        let hi = @util.le_u32_at(fa, s.off + 4)
        @util.le_u64_at(fa, s.off) == (lo.to_uint64() | (hi.to_uint64() << 32))
      },
      count=300,
      max_size=40,
      seed=seed.to_uint64(),
    )
  }
}

///|
/// base64 编解码 roundtrip：decode(encode(b)) == Some(b)。
/// **oracle 分工**（PR #476 审阅 P2-3）：roundtrip 对「编码解码双错互逆」
/// 无判别力（encode/decode 同时注入 ^0xFF 后本属性与 shape 属性均绿）——
/// 编码正确性的**唯一语义 oracle 是 util_wbtest 的 RFC 4648 向量例锚**
/// （删例锚即该面归零）；本属性管任意长度输入域的往返闭包与形态。
/// prove 三态：位打包域模型亚秒证过（报告 §3.2 试点 b2），roundtrip 组合
/// 语义 frontend 拒——qc 补组合面。
test "qc_base64_roundtrip" {
  for seed in [20261104, 427] {
    @quickcheck.check(
      (b : Bytes) => @util.base64_decode(@util.base64_encode(b)) == Some(b),
      count=300,
      max_size=48,
      seed=seed.to_uint64(),
    )
  }
}

///|
/// base64 输出形态：长度恒为 4*⌈n/3⌉；'=' 只出现在尾部且 ≤2 个；非填充
/// 字符全在 RFC 4648 字母表。同 qc_base64_roundtrip 的 oracle 分工注记
/// （PR #476 审阅 P2-3）——形态断言对错值注入亦无判别力，语义面归例锚。
/// prove 三态：6-bit 索引域证过（模型重写后），填充/长度形态未做——双保险。
test "qc_base64_output_shape" {
  let alphabet : Array[Char] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".to_array()
  for seed in [20261104, 427] {
    @quickcheck.check(
      (b : Bytes) => {
        let enc = @util.base64_encode(b)
        let n = b.length()
        if enc.length() != 4 * ((n + 2) / 3) {
          return false
        }
        // 尾部 '=' 恰为 pads 个（rem==1 → 2；rem==2 → 1；rem==0 → 0）
        let rem = n % 3
        let pads = if rem == 0 { 0 } else { 3 - rem }
        let cs = enc.to_array()
        let mut tail = 0
        while tail < pads {
          if cs[enc.length() - 1 - tail] != '=' {
            return false
          }
          tail += 1
        }
        // 其余字符全在字母表
        for i in 0..<(enc.length() - pads) {
          if !alphabet.contains(cs[i]) {
            return false
          }
        }
        true
      },
      count=300,
      max_size=48,
      seed=seed.to_uint64(),
    )
  }
}

///|
/// utf8 编解码 roundtrip：utf8_text(utf8_bytes(s)) == s。
/// prove 三态：String 域 frontend 全拒——qc 盲区互补。内置 String 生成器
/// 逐合法 Char 拼接（core quickcheck arbitrary.mbt 亲读：75% ASCII 含控制
/// 字符 + 25% 任意 Unicode scalar 排除代理段），天然合法码点域。
test "qc_utf8_roundtrip" {
  for seed in [20261104, 427] {
    @quickcheck.check(
      (s : String) => @util.utf8_text(@util.utf8_bytes(s)) == s,
      count=300,
      max_size=32,
      seed=seed.to_uint64(),
    )
  }
}

///|
/// utf8_len 码点累加：字节长度 == 逐码点 UTF-8 宽度求和（参照表与
/// @utf8.encode 实现路径独立，非重言）。
/// prove 三态：String 域 frontend 全拒——qc 盲区互补。
test "qc_utf8_len_matches_codepoint_sum" {
  for seed in [20261104, 427] {
    @quickcheck.check(
      (s : String) => {
        let mut total = 0
        for c in s {
          total += qc_utf8_width(c)
        }
        @util.utf8_len(s) == total
      },
      count=300,
      max_size=32,
      seed=seed.to_uint64(),
    )
  }
}

///|
/// utf8_text_partial 前缀止：任意字节切点 k，部分解码 == 按整字符消费的
/// 最大前缀（流式前缀契约的属性化——#363 语义的机器检查面）。
/// prove 三态：String 域 frontend 全拒——qc 盲区互补。
test "qc_utf8_text_partial_prefix_cut" {
  for seed in [20261104, 427] {
    @quickcheck.check(
      (c : QcTextCut) => {
        let bytes = @util.utf8_bytes(c.text)
        let arr : Array[Byte] = []
        for i in 0..<c.cut {
          arr.push(bytes[i])
        }
        @util.utf8_text_partial(Bytes::from_array(arr)) ==
        qc_prefix_at(c.text, c.cut)
      },
      count=300,
      max_size=32,
      seed=seed.to_uint64(),
    )
  }
}

// —— 测试侧辅助（不进包面；黑盒 _test.mbt 独立编译） ——

///|
/// 码点 → UTF-8 宽度参照表（与 @utf8.encode 实现独立）。
fn qc_utf8_width(c : Char) -> Int32 {
  let v = c.to_int()
  if v < 0x80 {
    1
  } else if v < 0x800 {
    2
  } else if v < 0x10000 {
    3
  } else {
    4
  }
}

///|
/// 串的 UTF-8 字节长度参照（Σ 码点宽度——与 @util.utf8_len 独立的
/// 测试侧口径，QcTextCut 的域界定用它而非被测函数，PR #476 审阅 P3-2）。
fn qc_byte_len(s : String) -> Int32 {
  let mut n = 0
  for c in s {
    n += qc_utf8_width(c)
  }
  n
}

///|
/// 按整字符消费的最大前缀（utf8_text_partial 的期望值参照：逐码点累计
/// 字节宽，超 k 即止）。
fn qc_prefix_at(s : String, k : Int32) -> String {
  let buf = StringBuilder()
  let mut used = 0
  for c in s {
    let w = qc_utf8_width(c)
    if used + w > k {
      break
    }
    buf.write_char(c)
    used += w
  }
  buf.to_string()
}

///|
/// 字节串 + 域内偏移（le_u32/le_u64 越界不设防的补偿采样域）：
/// off ∈ [0, len-8] 由生成器保证（全随机 Int32 偏移 filter 丢弃率近乎
/// 全量，不可用）。
struct QcByteSlice {
  bytes : Bytes
  off : Int32
}

///|
impl @quickcheck.Arbitrary for QcByteSlice with fn arbitrary(
  size : Int32,
  state : @splitmix.RandomState,
) -> QcByteSlice {
  let len = if size < 8 { 8 } else { size }
  let arr : Array[Byte] = []
  for _ in 0..<len {
    arr.push((state.next_uint() & 0xFFU).to_byte())
  }
  let bytes = Bytes::from_array(arr)
  let span = bytes.length() - 7
  let off = (state.next_uint() % span.reinterpret_as_uint()).reinterpret_as_int()
  { bytes, off, }
}

///|
impl @shrink.Shrink for QcByteSlice with fn shrink(self : QcByteSlice) -> Iter[
  QcByteSlice,
] {
  // 字节串缩短后偏移重算入域（保持 off ∈ [0, len-8] 不变量）。
  // 域下界 filter（PR #476 审阅 P2-1）：Bytes 内置 shrink 会产长度 <8 的
  // 候选——off 域随之变负（span=len-7<1），反例收缩路径崩溃（js 臂
  // unreachable / native 臂 0xc0000409 整包中断）而非给出最小反例；
  // 此处滤掉域外候选，shrink 收敛于域内最小形态
  @shrink.Shrink::shrink(self.bytes)
  .filter(b => b.length() >= 8)
  .map(b => {
    let span = b.length() - 7
    let off = if self.off > span { span } else { self.off }
    { bytes: b, off, }
  })
}

///|
impl @debug.Debug for QcByteSlice with fn to_repr(self : QcByteSlice) -> Repr {
  Repr("QcByteSlice(len=\{self.bytes.length()}, off=\{self.off})")
}

///|
/// 合法码点串 + 字节切点（utf8_text_partial 前缀属性域）：cut ∈
/// [0, qc_byte_len(text)]。**域由测试侧参照表定**（PR #476 审阅 P3-2：
/// 不用被测 @util.utf8_len 界域——生成器依赖被测函数会把实现缺陷折进
/// 采样域，注入 utf8_len 为码元数时域静默变窄而非暴露）。
struct QcTextCut {
  text : String
  cut : Int32
}

///|
impl @quickcheck.Arbitrary for QcTextCut with fn arbitrary(
  size : Int32,
  state : @splitmix.RandomState,
) -> QcTextCut {
  let text = @quickcheck.Arbitrary::arbitrary(size, state)
  let n = qc_byte_len(text)
  let cut = if n == 0 {
    0
  } else {
    (state.next_uint() % (n + 1).reinterpret_as_uint()).reinterpret_as_int()
  }
  { text, cut, }
}

///|
impl @shrink.Shrink for QcTextCut with fn shrink(self : QcTextCut) -> Iter[
  QcTextCut,
] {
  // 串缩短后切点重算入域（同 qc_byte_len 参照口径）；String 内置 shrink
  // 的候选仍是合法码点串（Char shrink 候选皆合法字符），域不变量保持
  @shrink.Shrink::shrink(self.text).map(t => {
    let n = qc_byte_len(t)
    let cut = if self.cut > n { n } else { self.cut }
    { text: t, cut, }
  })
}

///|
impl @debug.Debug for QcTextCut with fn to_repr(self : QcTextCut) -> Repr {
  Repr(
    "QcTextCut(len=\{self.text.length()}, cut=\{self.cut}, text=\{self.text})",
  )
}
