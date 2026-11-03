///|
/// 白盒锚（#426 B3' 批 0）——语义表逐格：①域判定表全格 ②M08 A1/A2 修复
/// 语义（clang 四端一致真值，速查表 §七 Z8-Z10）③VM 现状镜像（exec_arith/
/// exec_float 行为对照——批 3 接核零行为变化的前置锚，每格注 VM 出处）
/// ④f2i 饱和族（A5 修复语义，Z11）。
/// C 真值出处：M08 报告 §3.1/§3.3（Win/WSL × clang/gcc 四端一致）。

///|
/// 整型提升：char 系提升 signed int，unsigned 位消失（A7.1/A7.3 锚点）
test "integer_promote_char_drops_unsigned" {
  assert_eq(integer_promote(KChar, false), I32, msg="char→I32")
  assert_eq(
    integer_promote(KChar, true),
    I32,
    msg="uchar→I32（A7.1/A7.3：unsigned 位随提升消失）",
  )
  assert_eq(integer_promote(KInt, false), I32, msg="int→I32")
  assert_eq(integer_promote(KInt, true), U32, msg="uint→U32")
  assert_eq(integer_promote(KLongLong, false), I64, msg="LL→I64")
  assert_eq(integer_promote(KLongLong, true), U64, msg="ULL→U64")
}

///|
/// 公共域 16 格全表（promote_type 值域面孪生，C11 §6.3.1.8）
test "common_domain_full_table" {
  // 同 rank I32 档
  assert_eq(common_domain(I32, I32), I32, msg="i32×i32")
  assert_eq(common_domain(I32, U32), U32, msg="i32×u32→U32")
  assert_eq(common_domain(U32, I32), U32, msg="u32×i32→U32")
  assert_eq(common_domain(U32, U32), U32, msg="u32×u32→U32")
  // 同 rank I64 档
  assert_eq(common_domain(I64, I64), I64, msg="i64×i64")
  assert_eq(common_domain(I64, U64), U64, msg="i64×u64→U64")
  assert_eq(common_domain(U64, I64), U64, msg="u64×i64→U64")
  assert_eq(common_domain(U64, U64), U64, msg="u64×u64→U64")
  // 跨 rank：I64 ⊇ U32 → signed I64（A1 修复核心格：-1LL/2u 公共类型）
  assert_eq(
    common_domain(I64, U32),
    I64,
    msg="i64×u32→I64（A1：i64 容纳 u32 全值域）",
  )
  assert_eq(
    common_domain(U32, I64),
    I64,
    msg="u32×i64→I64（同上，交换律）",
  )
  assert_eq(common_domain(I64, I32), I64, msg="i64×i32→I64")
  assert_eq(common_domain(I32, I64), I64, msg="i32×i64→I64")
  // 跨 rank：U64 ⊄ I64 → U64
  assert_eq(common_domain(U64, I32), U64, msg="u64×i32→U64")
  assert_eq(common_domain(I32, U64), U64, msg="i32×u64→U64")
  assert_eq(common_domain(U64, U32), U64, msg="u64×u32→U64")
  assert_eq(common_domain(U32, U64), U64, msg="u32×u64→U64")
}

///|
/// 值按域归一四域
test "normalize_four_domains" {
  assert_eq(normalize(-1L, I32), -1L, msg="I32 符号扩展保持")
  assert_eq(
    normalize(4294967295L, I32),
    -1L,
    msg="I32 截低 32 位符号解释",
  )
  assert_eq(normalize(-1L, U32), 4294967295L, msg="U32 截低 32 位零扩展")
  assert_eq(normalize(4294967296L, U32), 0L, msg="U32 溢出位截断")
  assert_eq(normalize(-1L, I64), -1L, msg="I64 不动")
  assert_eq(
    normalize(-1L, U64),
    -1L,
    msg="U64 位模式不动（= 18446744073709551615）",
  )
}

///|
/// M08 A1 修复语义：有符号域除/右移（clang 真值 0 / -200 / -1，Z8-Z9）
test "m08_a1_signed_domain_div_shr" {
  // -1LL / 2u：公共域 I64（有符号）——normalize 后 -1 / 2 = 0
  let d = common_domain(
    integer_promote(KLongLong, false),
    integer_promote(KInt, true),
  )
  assert_eq(d, I64, msg="LL×uint 公共域=I64")
  assert_eq(
    eval_int_binary(OpDiv, normalize(-1L, d), normalize(2L, d), d),
    Ok(0L),
    msg="-1LL/2u → 0（旧 u_domain 误判产 9223372036854775807）",
  )
  // (uchar)200 / -1：两侧提升 I32（有符号）——200 / -1 = -200
  let d2 = common_domain(
    integer_promote(KChar, true),
    integer_promote(KInt, false),
  )
  assert_eq(
    d2,
    I32,
    msg="uchar×int 公共域=I32（unsigned 位随提升消失）",
  )
  assert_eq(
    eval_int_binary(OpDiv, normalize(200L, d2), normalize(-1L, d2), d2),
    Ok(-200L),
    msg="(uchar)200/-1 → -200（旧产 0）",
  )
  // -1LL >> 1u：Shr 域随左操作数（I64 算术右移）——-1 >> 1 = -1
  let shr_dom = integer_promote(KLongLong, false)
  assert_eq(
    eval_int_binary(OpShr, normalize(-1L, shr_dom), normalize(1L, d), shr_dom),
    Ok(-1L),
    msg="-1LL>>1u → -1（旧产 9223372036854775807）",
  )
}

///|
/// M08 A2 修复语义：同域规范后相等比较（clang 真值 1，Z10）
test "m08_a2_eq_uses_common_domain" {
  // -1 == 4294967295u：公共域 U32——normalize 后同为 0xFFFFFFFF
  let d = common_domain(
    integer_promote(KInt, false),
    integer_promote(KInt, true),
  )
  assert_eq(d, U32, msg="int×uint 公共域=U32")
  assert_eq(
    eval_int_binary(OpEq, normalize(-1L, d), normalize(4294967295L, d), d),
    Ok(1L),
    msg="-1==4294967295u → 1（旧按 Int64 位模式比较产 0）",
  )
}

///|
/// VM 镜像：I32 有符号四则溢出产故障（exec_arith.mbt:18-71 教学 trap 口径）
test "vm_mirror_i32_overflow_faults" {
  assert_eq(
    eval_int_binary(OpAdd, 2147483647L, 1L, I32),
    Err(AddOverflow),
    msg="INT_MAX+1 → AddOverflow（VM trap「整数加法溢出」）",
  )
  assert_eq(
    eval_int_binary(OpSub, -2147483648L, 1L, I32),
    Err(SubOverflow),
    msg="INT_MIN-1 → SubOverflow",
  )
  assert_eq(
    eval_int_binary(OpMul, 2147483647L, 2L, I32),
    Err(MulOverflow),
    msg="INT_MAX*2 → MulOverflow",
  )
  assert_eq(
    eval_int_unary(OpNeg, -2147483648L, I32),
    Err(NegOverflow),
    msg="-INT_MIN → NegOverflow",
  )
}

///|
/// VM 镜像：U32/I64/U64 四则回绕不产故障（exec_float.mbt:209-220 Q 族回绕契约）
test "vm_mirror_wrap_domains" {
  assert_eq(
    eval_int_binary(OpAdd, 4294967295L, 1L, U32),
    Ok(0L),
    msg="UINT_MAX+1 → 0 回绕（VM UAdd 镜像）",
  )
  assert_eq(
    eval_int_binary(OpAdd, 9223372036854775807L, 1L, I64),
    Ok(-9223372036854775808L),
    msg="LLONG_MAX+1 → LLONG_MIN 回绕（VM AddQ 镜像；M08 D1 双臂实测）",
  )
  assert_eq(
    eval_int_unary(OpNeg, 1L, U32),
    Ok(4294967295L),
    msg="-1u → 4294967295 模 2^32 补（VM UNeg 镜像）",
  )
  assert_eq(
    eval_int_unary(OpNeg, 1L, U64),
    Ok(-1L),
    msg="-1ull → 位模式 0xFFFF...（= 18446744073709551615，VM UNegQ 镜像）",
  )
}

///|
/// VM 镜像：Div/Mod 故障族（exec_arith.mbt:72-122 / exec_float.mbt:221-297）
test "vm_mirror_div_mod_faults" {
  assert_eq(
    eval_int_binary(OpDiv, 1L, 0L, I32),
    Err(DivByZero),
    msg="1/0 → DivByZero",
  )
  assert_eq(
    eval_int_binary(OpDiv, -2147483648L, -1L, I32),
    Err(DivOverflow),
    msg="INT_MIN/-1 → DivOverflow（VM trap 镜像）",
  )
  assert_eq(
    eval_int_binary(OpMod, -2147483648L, -1L, I32),
    Err(DivOverflow),
    msg="INT_MIN%-1 → DivOverflow（VM「整数取模溢出」镜像）",
  )
  assert_eq(
    eval_int_binary(OpDiv, -9223372036854775808L, -1L, I64),
    Err(DivOverflow),
    msg="LLONG_MIN/-1 → DivOverflow（VM DivQ 镜像）",
  )
  assert_eq(
    eval_int_binary(OpDiv, 1L, 0L, U64),
    Err(DivByZero),
    msg="u64 除零 → DivByZero（VM UDivQ 镜像）",
  )
  assert_eq(
    eval_int_binary(OpDiv, -1L, 3L, U64),
    Ok(6148914691236517205L),
    msg="0xFFFFFFFFFFFFFFFF/3 → 6148914691236517205（无符号除位模式镜像）",
  )
}

///|
/// VM 镜像：移位量按运算域宽判界（exec_arith.mbt:262-299 / 321-358）
test "vm_mirror_shift_bounds" {
  // I32 域 0~31
  assert_eq(
    eval_int_binary(OpShl, 1L, 32L, I32),
    Err(ShiftOutOfRange(32L)),
    msg="1<<32（int 左）→ 越界（VM trap「必须是 0~31」镜像；旧折叠静默产 0）",
  )
  assert_eq(
    eval_int_binary(OpShl, 1L, -1L, I32),
    Err(ShiftOutOfRange(-1L)),
    msg="1<<-1 → 负移位越界",
  )
  // I64 域 0~63
  assert_eq(
    eval_int_binary(OpShl, 1L, 64L, I64),
    Err(ShiftOutOfRange(64L)),
    msg="1LL<<64 → 越界（VM ShlQ「必须是 0~63」镜像）",
  )
  // 域内正常值
  assert_eq(
    eval_int_binary(OpShl, 1L, 31L, I32),
    Ok(-2147483648L),
    msg="1<<31 → INT_MIN（VM Shl 32 位截断语义镜像）",
  )
  assert_eq(
    eval_int_binary(OpShl, 2147483648L, 1L, U32),
    Ok(0L),
    msg="0x80000000u<<1 → 0（U32 截 32 位）",
  )
  assert_eq(
    eval_int_binary(OpShr, -1L, 1L, I32),
    Ok(-1L),
    msg="-1>>1（int）→ 算术右移 -1",
  )
  assert_eq(
    eval_int_binary(OpShr, normalize(-1L, U32), 1L, U32),
    Ok(2147483647L),
    msg="(0xFFFFFFFFu)>>1 → 2147483647 逻辑右移（操作数先归一到 U32 规范值）",
  )
  assert_eq(
    eval_int_binary(OpShr, -1L, 1L, U64),
    Ok(9223372036854775807L),
    msg="ULL>>1 → 0x7FFF...（位模式逻辑右移镜像）",
  )
}

///|
/// VM 镜像：比较族按域（exec_arith.mbt:156-230 / exec_float.mbt:317-343）
test "vm_mirror_comparisons" {
  assert_eq(
    eval_int_binary(OpLt, -1L, 1L, I32),
    Ok(1L),
    msg="-1<1 有符号真",
  )
  assert_eq(
    eval_int_binary(OpLt, normalize(-1L, U32), 1L, U32),
    Ok(0L),
    msg="0xFFFFFFFFu<1 → 假（无符号比较；既有锚 const_fold_unsigned_semantics）",
  )
  assert_eq(
    eval_int_binary(OpGt, -1L, 1L, U64),
    Ok(1L),
    msg="ULL_MAX>1 → 真（位模式无符号比较，病 34 镜像）",
  )
  assert_eq(
    eval_int_binary(OpGe, 4294967295L, 4294967295L, U32),
    Ok(1L),
    msg="u32 等值",
  )
}

///|
/// BitNot 各域（二补码代数式 ~v = -v-1）
test "bitnot_domains" {
  assert_eq(eval_int_unary(OpBitNot, 0L, I32), Ok(-1L), msg="~0 → -1")
  assert_eq(
    eval_int_unary(OpBitNot, 0L, U32),
    Ok(4294967295L),
    msg="~0u → 4294967295（A7.2 修复后定型 U32 的值域面）",
  )
  assert_eq(
    eval_int_unary(OpBitNot, 0L, U64),
    Ok(-1L),
    msg="~0ull → 位模式 0xFFFF...",
  )
  assert_eq(eval_int_unary(OpBitNot, 200L, I32), Ok(-201L), msg="~200 → -201")
}

///|
/// f2i 饱和族（M08 A5 修复语义；VM CastD2I/CastD2Q 镜像；大浮点用定点
/// 字面量——陷阱 #13：e 记法浮点字面量不可用）
test "f2i_saturate_family" {
  let huge_i32 : Double = 10000000000.0 // 1e10 > INT_MAX
  let huge_i64 : Double = 10000000000000000000.0 // 1e19 > LLONG_MAX
  let nan = 0.0 / 0.0
  let pos_inf = 1.0 / 0.0
  assert_eq(
    f2i_saturate_i32(huge_i32),
    2147483647L,
    msg="(int)1e10 → 2147483647 饱和（旧路径产 -1）",
  )
  assert_eq(
    f2i_saturate_i32(2147483648.5),
    2147483647L,
    msg="(int)2147483648.5 → 2147483647（旧产 -2147483648）",
  )
  assert_eq(
    f2i_saturate_i32(-2147483648.5),
    -2147483648L,
    msg="(int)-2147483648.5 → -2147483648 饱和",
  )
  assert_eq(f2i_saturate_i32(2.7), 2L, msg="(int)2.7 → 2 截断")
  assert_eq(
    f2i_saturate_i32(-1.5),
    -1L,
    msg="(int)-1.5 → -1 截断（C 向零取整）",
  )
  assert_eq(f2i_saturate_i32(nan), 0L, msg="(int)NaN → 0")
  assert_eq(f2i_saturate_i32(pos_inf), 2147483647L, msg="(int)inf → INT_MAX")
  assert_eq(
    f2i_saturate_i64(huge_i64),
    9223372036854775807L,
    msg="(long long)1e19 → LLONG_MAX 饱和",
  )
}

///|
/// PR #456 审阅 P2-2：核锚「16 算子逐格」实测有空洞——OpLe/OpBitAnd/
/// OpBitOr/OpBitXor 在锚中出现 0 次（审阅者把 OpLe 等值格改坏后
/// moon test 全绿实证）。本锚补四算子的判别力锚：OpLe 等值格（5<=5=1，
/// 与 OpLt 判别）+ 位运算三算子两域（同位形/异位形/全 0/全 1）。
test "p2_2_core_op_coverage_gap_le_bitops" {
  // OpLe 等值格：5<=5 → 1（审阅改坏形态：判成 < 则此处得 0）
  assert_eq(
    eval_int_binary(OpLe, 5L, 5L, I32),
    Ok(1L),
    msg="5<=5 等值格 → 1（OpLe/OpLt 判别锚）",
  )
  assert_eq(eval_int_binary(OpLe, 4L, 5L, I32), Ok(1L), msg="4<=5 → 1")
  assert_eq(eval_int_binary(OpLe, 6L, 5L, I32), Ok(0L), msg="6<=5 → 0")
  assert_eq(
    eval_int_binary(OpLe, normalize(-1L, U32), 0L, U32),
    Ok(0L),
    msg="U32 域 0xFFFFFFFF<=0 → 0（与 I32 域的 -1<=0 → 1 不同值——域判别）",
  )
  assert_eq(
    eval_int_binary(OpLe, -9223372036854775808L, -1L, I64),
    Ok(1L),
    msg="I64 域 LLONG_MIN<=-1 → 1",
  )
  // BitAnd / BitOr / BitXor：I32 与 I64 两域、同位/异位/全 1 形
  assert_eq(
    eval_int_binary(OpBitAnd, 12L, 10L, I32),
    Ok(8L),
    msg="12&10=8（1100&1010）",
  )
  assert_eq(
    eval_int_binary(OpBitAnd, 12L, 10L, I64),
    Ok(8L),
    msg="I64 域同值（位模式域无关）",
  )
  assert_eq(
    eval_int_binary(OpBitAnd, 0L, -1L, I32),
    Ok(0L),
    msg="0&-1=0（全 1 掩码）",
  )
  assert_eq(
    eval_int_binary(OpBitOr, 12L, 10L, I32),
    Ok(14L),
    msg="12|10=14（1100|1010）",
  )
  assert_eq(
    eval_int_binary(OpBitOr, 0L, -1L, I64),
    Ok(-1L),
    msg="0|-1=-1（I64 位模式）",
  )
  assert_eq(
    eval_int_binary(OpBitXor, 12L, 10L, I32),
    Ok(6L),
    msg="12^10=6（1100^1010）",
  )
  assert_eq(
    eval_int_binary(OpBitXor, -1L, -1L, I32),
    Ok(0L),
    msg="-1^-1=0（自反）",
  )
  assert_eq(
    eval_int_binary(OpBitXor, 5L, 0L, I64),
    Ok(5L),
    msg="5^0=5（幺元）",
  )
}
