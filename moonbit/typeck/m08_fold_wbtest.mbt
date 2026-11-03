///|
/// #426 B3' 批 1 红锚（M08 审阅报告六连 + 本批扫描 S2）——常量折叠器接
/// 共享算术核（vitro/engine/arith）前全红、接核后翻绿。J9：本文件先于
/// const_eval 改动入库跑红（7/7 红实录见批 1 commit 信息）。
///
/// 真值口径：Win clang 22.1.4 / Win gcc / WSL gcc 15.2 / WSL clang 21.1.8
/// 四端一致（M08 §3.1/§3.3；速查表 §七 Z7-Z11）；同时 = vitro 运行期值
/// （M08 探针：运行期 printf 与 clang 全同）——故本组锚兼作**折叠↔运行期
/// 一致性闸**：折叠值 ≠ 真值即红，无需另起 VM 对拍通道。
///
/// 形态说明：parser 对小 uint 字面量产 `Literal(v, uint)`、超 Int32 的产
/// `LongLiteral(v, uint)`（4294967295u）；`-1LL` = Unary(Neg, LongLiteral)。
/// 大浮点用定点字面量（陷阱 #13）——饱和语义与 1e300 同格。

///|
fn m08_loc() -> @source.SourceLoc {
  @source.SourceLoc::new(1, 1)
}

///|
fn m08_int(v : Int32) -> @ast.Expr {
  @ast.Expr::Literal(v, m08_loc(), @ast.Type::int())
}

///|
fn m08_uint(v : Int32) -> @ast.Expr {
  @ast.Expr::Literal(v, m08_loc(), @ast.Type::unsigned_int())
}

///|
fn m08_neg(e : @ast.Expr, ty : @ast.Type) -> @ast.Expr {
  @ast.Expr::Unary(@ast.UnaryOp::Neg, e, m08_loc(), ty)
}

///|
fn m08_bin(
  op : @ast.BinaryOp,
  l : @ast.Expr,
  r : @ast.Expr,
  ty : @ast.Type,
) -> @ast.Expr {
  @ast.Expr::Binary(op, l, r, m08_loc(), ty)
}

///|
/// 取全局 i 的折叠结果（Literal / LongLiteral 两形态统一成 Int64）。
fn m08_folded(typed : @ast.ProgramNode, i : Int32) -> Int64? {
  match typed.globals[i].init {
    Some(@ast.Expr::Literal(v, _, _)) => Some(v.to_int64())
    Some(@ast.Expr::LongLiteral(v, _, _)) => Some(v)
    _ => None
  }
}

///|
/// A1-①：`long long g1 = -1LL / 2u;` → 0（公共类型 signed LL；旧 u_domain
/// 任一侧 unsigned 即无符号域 → 9223372036854775807）。
test "m08_red_udomain_ll_vs_uint_div" {
  let ll = @ast.Type::long_long()
  let e = m08_bin(
    @ast.BinaryOp::Div,
    m08_neg(@ast.Expr::LongLiteral(1L, m08_loc(), ll), ll),
    m08_uint(2),
    ll,
  )
  let tc = TypeChecker::new()
  let (typed, errs, _, _) = tc.check(gprog([gdecl(ll, "g1", Some(e))]))
  assert_eq(errs.length(), 0, msg="合法常量表达式零诊断")
  assert_eq(
    m08_folded(typed, 0),
    Some(0L),
    msg="-1LL/2u 应折 0（LL 有符号域）",
  )
}

///|
/// A1-②：`int g2 = (unsigned char)200 / -1;` → -200（uchar 先提升 signed
/// int；旧按 unsigned 域除 → 0）。
test "m08_red_udomain_uchar_promote_div" {
  let uchar = @ast.Type::Char(true, false)
  let e = m08_bin(
    @ast.BinaryOp::Div,
    @ast.Expr::Cast(m08_int(200), uchar, m08_loc(), uchar),
    m08_neg(m08_int(1), @ast.Type::int()),
    @ast.Type::int(),
  )
  let tc = TypeChecker::new()
  let (typed, errs, _, _) = tc.check(
    gprog([gdecl(@ast.Type::int(), "g2", Some(e))]),
  )
  assert_eq(errs.length(), 0, msg="合法常量表达式零诊断")
  assert_eq(
    m08_folded(typed, 0),
    Some(-200L),
    msg="(uchar)200/-1 应折 -200（提升 int 有符号域）",
  )
}

///|
/// A1-③（同族右移面）：`long long g3 = -1LL >> 1u;` → -1（Shr 域随左操作
/// 数 LL 算术右移；旧无符号域逻辑右移 → 9223372036854775807）。
test "m08_red_udomain_ll_shr_uint" {
  let ll = @ast.Type::long_long()
  let e = m08_bin(
    @ast.BinaryOp::Shr,
    m08_neg(@ast.Expr::LongLiteral(1L, m08_loc(), ll), ll),
    m08_uint(1),
    ll,
  )
  let tc = TypeChecker::new()
  let (typed, errs, _, _) = tc.check(gprog([gdecl(ll, "g3", Some(e))]))
  assert_eq(errs.length(), 0, msg="合法常量表达式零诊断")
  assert_eq(
    m08_folded(typed, 0),
    Some(-1L),
    msg="-1LL>>1u 应折 -1（算术右移）",
  )
}

///|
/// A2：`int g4 = (-1 == 4294967295u);` → 1（-1 转 unsigned 比较；旧 Eq
/// 不做域转换按 Int64 位模式比 → 0）。4294967295u 按 parser 真实形态
/// 构造为 LongLiteral(uint)——用 Literal(-1, uint) 构造会凑巧通过测不到病。
test "m08_red_eq_ignores_unsigned_domain" {
  let e = m08_bin(
    @ast.BinaryOp::Eq,
    m08_neg(m08_int(1), @ast.Type::int()),
    @ast.Expr::LongLiteral(4294967295L, m08_loc(), @ast.Type::unsigned_int()),
    @ast.Type::int(),
  )
  let tc = TypeChecker::new()
  let (typed, errs, _, _) = tc.check(
    gprog([gdecl(@ast.Type::int(), "g4", Some(e))]),
  )
  assert_eq(errs.length(), 0, msg="合法常量表达式零诊断")
  assert_eq(m08_folded(typed, 0), Some(1L), msg="-1==4294967295u 应折 1")
}

///|
/// A3：`int d1 = 1 || 1/0;` → 1 零诊断（短路：右侧不求值；旧非短路先算
/// 右侧 1/0 → 整体折叠失败 → 静默置 0）。
test "m08_red_logical_or_short_circuit" {
  let e = m08_bin(
    @ast.BinaryOp::Or,
    m08_int(1),
    m08_bin(@ast.BinaryOp::Div, m08_int(1), m08_int(0), @ast.Type::int()),
    @ast.Type::int(),
  )
  let tc = TypeChecker::new()
  let (typed, errs, _, _) = tc.check(
    gprog([gdecl(@ast.Type::int(), "d1", Some(e))]),
  )
  assert_eq(
    errs.length(),
    0,
    msg="短路后右侧除零不触发诊断（clang 同）",
  )
  assert_eq(
    m08_folded(typed, 0),
    Some(1L),
    msg="1||1/0 应折为 Literal(1)（实得折叠失败原样返回）",
  )
}

///|
/// A4：`int d3 = 1/0;` 静态初始化器除零 → 必须有 E3075 诊断（clang
/// "initializer element is not a compile-time constant"；旧零诊断置 0）。
test "m08_red_div_by_zero_static_init_diag" {
  let e = m08_bin(@ast.BinaryOp::Div, m08_int(1), m08_int(0), @ast.Type::int())
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(
    gprog([gdecl(@ast.Type::int(), "d3", Some(e))]),
  )
  assert_true(
    errs.exists(e => e.code == 3075),
    msg="1/0 应有 E3075 诊断，实得零诊断",
  )
}

///|
/// A5：`int f1 = (int)1e10;` → 2147483647 饱和（旧 to_int64 饱和到 INT64_MAX
/// 再截低 32 位 → -1）。1e10 与 1e300 同饱和格（定点可写）。
test "m08_red_float_to_int_cast_saturate" {
  let big : Double = 10000000000.0
  let e = @ast.Expr::Cast(
    @ast.Expr::FloatLiteral(big, m08_loc(), @ast.Type::double()),
    @ast.Type::int(),
    m08_loc(),
    @ast.Type::int(),
  )
  let tc = TypeChecker::new()
  let (typed, errs, _, _) = tc.check(
    gprog([gdecl(@ast.Type::int(), "f1", Some(e))]),
  )
  assert_eq(errs.length(), 0, msg="合法常量表达式零诊断")
  assert_eq(
    m08_folded(typed, 0),
    Some(2147483647L),
    msg="(int)1e10 应饱和 2147483647（实得 -1）",
  )
}

///|
/// S2（本批扫描新面）：`int g = 2147483647 + 1;` → 折回绕值 -2147483648
/// **带 W3090 警告**（#426 拍板①：W 级照折对齐 clang -Winteger-overflow；
/// 旧零诊断；运行期教学 trap 口径不变——两上下文从「静默分裂」变「有提示」）。
test "m08_s2_int_add_overflow_warns" {
  let e = m08_bin(
    @ast.BinaryOp::Add,
    m08_int(2147483647),
    m08_int(1),
    @ast.Type::int(),
  )
  let tc = TypeChecker::new()
  let (typed, errs, warns, _) = tc.check(
    gprog([gdecl(@ast.Type::int(), "g", Some(e))]),
  )
  assert_eq(errs.length(), 0, msg="溢出是 UB 非错误（clang 仅警告）")
  assert_eq(
    m08_folded(typed, 0),
    Some(-2147483648L),
    msg="INT_MAX+1 折回绕值（与 clang 静态折值一致）",
  )
  assert_true(
    warns.exists(w => w.code == 3090),
    msg="应报 W3090 常量表达式整数溢出警告",
  )
}

///|
/// PR #456 审阅 P2-1：字符串字面量下标是 C11 §6.6 合法常量表达式
/// （clang `char c = "abc"[0];` 零诊断折 97）——批 1 的 A4 Index 诊断臂
/// 无条件报错属误报。成对锚：合法界内折值 / 越界拒折报 E3075 /
/// 数组裸用仍报（锁 A4 修复不回退）。
test "p2_1_string_literal_index_folds" {
  let loc = m08_loc()
  fn stridx(s : String, i : Int32) -> @ast.Expr {
    @ast.Expr::Index(
      @ast.Expr::StringLiteral(s, loc, @ast.Type::char()),
      m08_int(i),
      loc,
      @ast.Type::char(),
    )
  }
  // 合法：折字节值零诊断（J9：现状红——E3075 误报 + 不折）
  let tc = TypeChecker::new()
  let (typed, errs, _, _) = tc.check(
    gprog([
      gdecl(@ast.Type::char(), "c0", Some(stridx("abc", 0))),
      gdecl(@ast.Type::char(), "c2", Some(stridx("abc", 2))),
    ]),
  )
  assert_eq(
    errs.length(),
    0,
    msg="字符串下标界内零诊断（clang 同）",
  )
  assert_eq(
    m08_folded(typed, 0),
    Some(97L),
    msg="\"abc\"[0] 应折 97（现状 E3075 误报）",
  )
  assert_eq(
    m08_folded(typed, 1),
    Some(99L),
    msg="\"abc\"[2] 应折 99（右端界内）",
  )
  // 越界：拒折 + E3075（负/超长同）
  let tc2 = TypeChecker::new()
  let (_, errs2, _, _) = tc2.check(
    gprog([
      gdecl(@ast.Type::char(), "oob", Some(stridx("abc", 5))),
      gdecl(@ast.Type::char(), "neg", Some(stridx("abc", -1))),
    ]),
  )
  assert_eq(
    errs2.filter(e => e.code == 3075).length(),
    2,
    msg="越界/负下标各报一条 E3075",
  )
  // 数组裸用仍报（A4 修复面锁回归）
  let tc3 = TypeChecker::new()
  let (_, errs3, _, _) = tc3.check(
    gprog([
      gdecl(@ast.Type::int(), "a", Some(m08_int(0))),
      gdecl(
        @ast.Type::int(),
        "bad",
        Some(
          @ast.Expr::Index(
            @ast.Expr::Literal(0, loc, @ast.Type::int()),
            m08_int(0),
            loc,
            @ast.Type::int(),
          ),
        ),
      ),
    ]),
  )
  assert_true(
    errs3.exists(e => e.code == 3075),
    msg="数组元素裸用（折不掉）仍报 E3075",
  )
}

///|
/// PR #456 审阅 P3-1/P3-2：signed long long 四则溢出也应发 W3090（clang
/// -Winteger-overflow 对 LL 同报；批 1 只覆盖 I32 域），且文案按域
///（「int / long long」——审阅实测 -(-LLONG_MAX-1) 文案错说 int）。
/// J9：溢出三态（Add/Sub/Mul）现状零警告红；INT64_MIN 特格与未溢对照锁防误报。
test "p3_i64_overflow_warns_with_domain_message" {
  let ll = @ast.Type::long_long()
  fn llit(v : Int64) -> @ast.Expr {
    @ast.Expr::LongLiteral(v, m08_loc(), ll)
  }
  fn lldecl(name : String, e : @ast.Expr) -> @ast.GlobalDecl {
    gdecl(ll, name, Some(e))
  }
  let tc = TypeChecker::new()
  let (typed, errs, warns, _) = tc.check(
    gprog([
      lldecl("a", m08_bin(Add, llit(9223372036854775807L), llit(1L), ll)),
      lldecl("s", m08_bin(Sub, llit(-9223372036854775807L), llit(2L), ll)),
      lldecl("m", m08_bin(Mul, llit(9223372036854775807L), llit(3L), ll)),
      // 未溢对照：2^62-1 与 2 的积 = 9223372036854775804 < LLONG_MAX
      lldecl("ok1", m08_bin(Mul, llit(4611686018427387903L), llit(2L), ll)),
      // INT64_MIN * 1 = INT64_MIN 合法（|积|恰为 2^63）
      lldecl("ok2", m08_bin(Mul, llit(-9223372036854775808L), llit(1L), ll)),
      // INT64_MIN * -1 = 2^63 数学超界（回绕 INT64_MIN）——clang 警告
      lldecl(
        "w4",
        m08_bin(Mul, llit(-9223372036854775808L), m08_neg(llit(1L), ll), ll),
      ),
    ]),
  )
  assert_eq(errs.length(), 0)
  let w3090 = warns.filter(w => w.code == 3090)
  assert_eq(
    w3090.length(),
    4,
    msg="Add/Sub/Mul/INT64_MIN*-1 四条 W3090（现状零警告）",
  )
  let mut ll_msg = 0
  for w in w3090 {
    if w.message.contains("long long") {
      ll_msg = ll_msg + 1
    }
  }
  assert_eq(
    ll_msg,
    4,
    msg="LL 域文案须说 long long（P3-2：现状错说 int）",
  )
  assert_eq(
    m08_folded(typed, 0),
    Some(-9223372036854775808L),
    msg="LLONG_MAX+1 折回绕 LLONG_MIN（值与 clang 一致）",
  )
  // INT64_MIN*1（ok2 折 INT64_MIN）与未溢积零警告
  assert_eq(
    m08_folded(typed, 4),
    Some(-9223372036854775808L),
    msg="INT64_MIN*1 = INT64_MIN（零警告对照）",
  )
}
