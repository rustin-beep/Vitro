// #427 批 B4（2026-11-03）：printf 缺臂族修复锚——全部值为 clang 22.1.4
// 实测真值（tmp/b4probes/truth_*.txt 留档；UCRT/glibc 平台方言域的 %a 形态
// 与 NaN 符号/payload 按《C 真值速查表》P3/G8 口径随 glibc/NAN 宏侧，锚
// 注逐处标明）。锚义务对应 issue #427「锚义务」节：四崩溃形态 + %n 写回 +
// 错位三联 + %q 门条件 + %hh 截断 + %# 前缀/尾零 + hexfloat/精确路径族。
// 辅助（fresh/put_bytes/printf_run/scanf_run/gf）沿用 host_io_wbtest 单源。

///|
/// %05.0d 族（M21 A1 / issue 探针 2）：旧三臂进程崩溃（`body[0]` 空串
/// 索引先于长度守卫）+ 精度在场 0 旗标被忽略（C11 7.21.6.1——空格填充
/// 非 00000）。clang 真值 `[     ]` ×3 / `[        ]`。
test "printf_b4_zero_precision_ignores_zero_flag" {
  let (map, mem) = fresh()
  let (log, r) = printf_run(map, mem, "[%05.0d][%05.0u][%08.0x][%05.0o]", [
    (0).to_uint64(),
    (0).to_uint64(),
    (0).to_uint64(),
    (0).to_uint64(),
  ])
  assert_eq(r.trap, None)
  assert_eq(
    log.join(OutputKind::Stdout),
    b"[     ][     ][        ][     ]",
    msg="精度在场 0 旗标忽略（clang [     ] 空格填充）",
  )
  // 精度补零与宽度空格并存：`%08.3d` 42 → clang "     042"
  let (map2, mem2) = fresh()
  let (log2, _) = printf_run(map2, mem2, "[%08.3d]", [(42).to_uint64()])
  assert_eq(log2.join(OutputKind::Stdout), b"[     042]")
}

///|
/// %a/%F/%A 执行臂 + 错位三联（M20 A-2 / M21 A3 / issue 探针 1）：旧无
/// 输出臂——字母原样 + 实参不消耗 + 后续 %d 错位吃参（`a|0`）；%a/%A 形态
/// 随 glibc 最短精确（UCRT 13 位全印属实现定义域平台分叉——速查表 P3）。
test "printf_b4_hexfloat_and_F_arms_alignment" {
  let (map, mem) = fresh()
  let (log, r) = printf_run(map, mem, "%a|%d|%F|%d|%A|%d", [
    1.5.reinterpret_as_uint64(),
    (42).to_uint64(),
    2.5.reinterpret_as_uint64(),
    (43).to_uint64(),
    1.5.reinterpret_as_uint64(),
    (44).to_uint64(),
  ])
  assert_eq(r.trap, None)
  assert_eq(
    log.join(OutputKind::Stdout),
    b"0x1.8p+0|42|2.500000|43|0X1.8P+0|44",
    msg="glibc 最短 hexfloat + %F 复用 f 臂 + 实参对位（clang 三联真值）",
  )
}

///|
/// %n 写回（M20 A-1 / issue 探针 3；scanf %n #269 的对称补齐）：写回
/// 「到此处已输出字符数」（本调用累积字节）；长度修饰分档（默认 4 /
/// hh=1 / h=2 / ll=8——LLP64 l 与默认同 4）。clang 真值 abcd / n=2
///（Win UCRT 禁 %n，真值采 WSL gcc——速查表 P1）。
test "printf_b4_n_writeback_by_lenmod" {
  // 默认 %n：4 字节写回
  let (map, mem) = fresh()
  let n_addr = 0x7000U
  put_bytes(mem, map, n_addr, b"\xff\xff\xff\xff", false)
  let (log, r) = printf_run(map, mem, "ab%ncd", [n_addr.to_uint64()])
  assert_eq(r.trap, None)
  assert_eq(log.join(OutputKind::Stdout), b"abcd")
  assert_eq(
    mem.load_u32(map, n_addr),
    Ok(2U),
    msg="n=2（%n 前已输出字节）",
  )
  // %hhn：1 字节写回（高位不受污染）
  let (map2, mem2) = fresh()
  put_bytes(mem2, map2, n_addr, b"\xff\xff\xff\xff", false)
  let (_, r2) = printf_run(map2, mem2, "ab%hhncd", [n_addr.to_uint64()])
  assert_eq(r2.trap, None)
  assert_eq(mem2.load_u32(map2, n_addr), Ok(0xFFFFFF02U))
  // %hn：2 字节写回
  let (map3, mem3) = fresh()
  put_bytes(mem3, map3, n_addr, b"\xff\xff\xff\xff", false)
  let (_, r3) = printf_run(map3, mem3, "ab%hncd", [n_addr.to_uint64()])
  assert_eq(r3.trap, None)
  assert_eq(mem3.load_u32(map3, n_addr), Ok(0xFFFF0002U))
  // %lln：8 字节写回
  let (map4, mem4) = fresh()
  put_bytes(mem4, map4, n_addr, b"\xff\xff\xff\xff\xff\xff\xff\xff", false)
  let (_, r4) = printf_run(map4, mem4, "ab%llncd", [n_addr.to_uint64()])
  assert_eq(r4.trap, None)
  assert_eq(mem4.load_u64(map4, n_addr), Ok(2UL))
  // 计数含多字节段：%n 在 %5d 之后 = 5
  let (map5, mem5) = fresh()
  let (_, r5) = printf_run(map5, mem5, "%5d%n", [
    (7).to_uint64(),
    n_addr.to_uint64(),
  ])
  assert_eq(r5.trap, None)
  assert_eq(mem5.load_u32(map5, n_addr), Ok(5U))
}

///|
/// 未知转换符门条件（M21 A4 / 速查表 P9-P10）：输出与实参余量无关——
/// clang 恒「丢 % 输出字母、不消耗实参」。旧门条件参数耗尽位短路，
/// `[%q]`（1 参）保留 %q、`[%d%q]`（1 参）保留 %q、`[%5q]`（1 参，
/// 未知不计参 → vm 弹 0 参）整串透出。
test "printf_b4_unknown_spec_independent_of_args" {
  // clang 实测（t_q）：三配置 + 带修饰未知恒输出字母
  let (map, mem) = fresh()
  let (log, r) = printf_run(map, mem, "[%d%q|%d]", [
    (1).to_uint64(),
    (2).to_uint64(),
  ])
  assert_eq(r.trap, None)
  assert_eq(log.join(OutputKind::Stdout), b"[1q|2]")
  // 未知不计参 → args 弹 0 个（vm 按计数面弹参）——wbtest 直接给空组
  let (map2, mem2) = fresh()
  let (log2, r2) = printf_run(map2, mem2, "[%q]", [])
  assert_eq(r2.trap, None)
  assert_eq(log2.join(OutputKind::Stdout), b"[q]")
  // 已知 spec 吃尽参数后未知字母仍丢 %
  let (map3, mem3) = fresh()
  let (log3, r3) = printf_run(map3, mem3, "[%d%q]", [(1).to_uint64()])
  assert_eq(r3.trap, None)
  assert_eq(log3.join(OutputKind::Stdout), b"[1q]")
  // 带宽度/带修饰未知（clang t_q#6/#7 → [q]）
  let (map4, mem4) = fresh()
  let (log4, _) = printf_run(map4, mem4, "[%5q]", [])
  assert_eq(log4.join(OutputKind::Stdout), b"[q]")
  let (map5, mem5) = fresh()
  let (log5, _) = printf_run(map5, mem5, "[%hq]", [])
  assert_eq(log5.join(OutputKind::Stdout), b"[q]")
  // 长度修饰的合法 spec 不受门条件影响（防误伤：%hhd 正常截断臂）
  let (map6, mem6) = fresh()
  let (log6, _) = printf_run(map6, mem6, "[%hhd]", [(300).to_uint64()])
  assert_eq(log6.join(OutputKind::Stdout), b"[44]")
}

///|
/// %hh/%h 截断（M20 A-4）：变参实参 int 提升 4 字节，打印侧按修饰截断
///（d/i 符号扩展、u/x/o 零扩展）。clang 真值 t_hh。
test "printf_b4_hh_h_truncation" {
  let (map, mem) = fresh()
  let (log, r) = printf_run(
    map,
    mem,
    "%hhd|%hd|%hhu|%hu|%hhd|%hd|%hhx|%hx|%hho",
    [
      (300).to_uint64(),
      (70000).to_uint64(),
      (70000).to_uint64(),
      (70000).to_uint64(),
      (-1).to_uint64(),
      (-1).to_uint64(),
      (0x1234).to_uint64(),
      (0x12345).to_uint64(),
      (0x1FF).to_uint64(),
    ],
  )
  assert_eq(r.trap, None)
  assert_eq(log.join(OutputKind::Stdout), b"44|4464|112|4464|-1|-1|34|2345|377")
}

///|
/// `#` 前缀位置（M20 A-5）：前缀属数值部分——零填充时 `0x` 在 pad 前、
/// 数字在 pad 后（clang `%#08x` 255 → `0x0000ff`；旧 `00000xff` 前缀
/// 排到填充外）；空格填充与左对齐形态不受影响。
test "printf_b4_hash_prefix_before_zero_pad" {
  let (map, mem) = fresh()
  let (log, r) = printf_run(map, mem, "%#08x|%#05X|%#05o|%#8x|%-#8x", [
    (255).to_uint64(),
    (255).to_uint64(),
    (8).to_uint64(),
    (255).to_uint64(),
    (255).to_uint64(),
  ])
  assert_eq(r.trap, None)
  assert_eq(
    log.join(OutputKind::Stdout),
    b"0x0000ff|0X0FF|00010|    0xff|0xff    ",
  )
}

///|
/// `#` 对 g = 不删尾零（M20 A-6）：`%#.3g` 0.0001 → `0.000100`（精度
/// 3 位有效保留尾零）；`%#g`（缺省 6）→ `0.000100000`；`%#.17g` 0.1
/// → 17 位有效保尾零。旧 format_g 无视 # 恒 trim（`0.0001`）。
test "printf_b4_hash_g_keeps_trailing_zeros" {
  let (map, mem) = fresh()
  let (log, r) = printf_run(map, mem, "%#.3g|%#g|%#.17g", [
    0.0001.reinterpret_as_uint64(),
    0.0001.reinterpret_as_uint64(),
    0.1.reinterpret_as_uint64(),
  ])
  assert_eq(r.trap, None)
  assert_eq(
    log.join(OutputKind::Stdout),
    b"0.000100|0.000100000|0.10000000000000001",
  )
}

///|
/// NaN/inf 大小写族（M20 A-12 / M21 A5 / 速查表 G8-G10）：`%f|%e|%g`
/// 小写 nan、`%F|%E|%G` 大写（NaN 宏口径——运行时 0.0/0.0 的 x86 符号
/// 位与 UCRT `-nan(ind)` payload 属 M20 D-4 平台域，非本锚目标）。
test "printf_b4_nan_inf_case_family" {
  let (map, mem) = fresh()
  let nan_v = @double.not_a_number
  let (log, r) = printf_run(map, mem, "%f|%e|%g|%F|%E|%G", [
    nan_v.reinterpret_as_uint64(),
    nan_v.reinterpret_as_uint64(),
    nan_v.reinterpret_as_uint64(),
    nan_v.reinterpret_as_uint64(),
    nan_v.reinterpret_as_uint64(),
    nan_v.reinterpret_as_uint64(),
  ])
  assert_eq(r.trap, None)
  assert_eq(log.join(OutputKind::Stdout), b"nan|nan|nan|NAN|NAN|NAN")
  // %F inf 大写（format_fixed_case）
  let (map2, mem2) = fresh()
  let (log2, _) = printf_run(map2, mem2, "%F|%f", [
    @double.infinity.reinterpret_as_uint64(),
    @double.infinity.reinterpret_as_uint64(),
  ])
  assert_eq(log2.join(OutputKind::Stdout), b"INF|inf")
}

///|
/// format_a hexfloat 全形态（本批新臂的直锚）：缺省最短（glibc）/ 精度
/// 截断 half-even / lead 进位（%.0a 1.5 → 0x2p+0——clang t_conv#11）/
/// %#.0a 保点 / 次正规 / 零与负零 / 超精确域补零。UCRT 对比值（13 位
/// 全印）登记为实现定义域分叉，锚随 glibc。
test "printf_b4_format_a_hexfloat_family" {
  // 缺省 = 最短精确
  assert_eq(format_a(1.5, None, false), "0x1.8p+0")
  assert_eq(format_a(0.1, None, false), "0x1.999999999999ap-4")
  assert_eq(format_a(0.0, None, false), "0x0p+0")
  assert_eq(format_a(-1.5, None, false), "-0x1.8p+0")
  // 大写
  assert_eq(format_a(1.5, None, true), "0X1.8P+0")
  // 精度族（clang：%.3a → 0x1.800p+0；%.1a 0.1 → 0x1.ap-4）
  assert_eq(format_a(1.5, Some(3), false), "0x1.800p+0")
  assert_eq(format_a(0.1, Some(1), false), "0x1.ap-4")
  // lead 进位（half-even 平局取偶判舍入前完整整数）：%.0a 1.5 → 0x2p+0
  assert_eq(format_a(1.5, Some(0), false), "0x2p+0")
  assert_eq(format_a(1.5, Some(0), false, alt=true), "0x2.p+0")
  // 次正规（0x0.…p-1022）
  assert_eq(
    format_a(4.9406564584124654e-324, None, false),
    "0x0.0000000000001p-1022",
  )
  // 超精确域（>13 位补零）
  assert_eq(format_a(1.5, Some(15), false), "0x1.800000000000000p+0")
}

///|
/// %.17e 精确路径（#427 批 B4 连带：format_e 与 format_g 同根换十进制
/// 精确路径——探针 t_prec#9-14 六值 clang 逐位一致；旧浮点商路径
/// `0.99999999999999978e+23` 尾数不规格化与 %.17g 旧病同形）。
test "printf_b4_format_e_decimal_exact" {
  let fe = fn(v : String, prec : Int32) -> String {
    let dv : Double = @string.parse_double(v) catch { _ => 0.0 }
    format_e(dv, prec, false)
  }
  assert_eq(fe("1e23", 17), "9.99999999999999916e+22")
  assert_eq(fe("1e126", 17), "9.99999999999999925e+125")
  assert_eq(fe("1.5e126", 17), "1.50000000000000011e+126")
  assert_eq(fe("0.1", 17), "1.00000000000000006e-01")
  assert_eq(fe("8.8817841970012523e-320", 17), "8.88181811528808912e-320")
  assert_eq(fe("4.9406564584124654e-324", 17), "4.94065645841246544e-324")
  // 默认精度段既有真值不回归（P1① 进位归一的精确版）
  assert_eq(fe("999999.99", 6), "1.000000e+06")
  assert_eq(fe("1.5", 6), "1.500000e+00")
  assert_eq(fe("0.1", 6), "1.000000e-01")
}

///|
/// scanf/sscanf `%Nc` 字段宽度（M20 A-3，#427 任务书点名「范围外顺手」：
/// C11 §7.21.6.2 p12 宽度适用 %c——逐字节写、不写 NUL、缺省 1；#71 病
/// 23 宽度修复漏了 %c 臂）。clang 真值 r=1 [abc] next=100（t_scanfc）。
test "scanf_b4_width_c" {
  // scanf 流式臂
  let (map, mem) = fresh()
  let buf = 0x7000U
  let input = InputState::new([b"abcdef"], true)
  let r = scanf_run(map, mem, input, "%3c", [buf])
  guard r is InputOutcome::Value(v) else { fail("r=1 期望") }
  assert_eq(v, 1)
  assert_eq(mem.load_u32(map, buf), Ok(0x00636261U), msg="abc\\0")
  // sscanf 臂（双臂同修）
  let (map2, mem2) = fresh()
  put_bytes(mem2, map2, 0x6800U, b"abcdef", true)
  put_bytes(mem2, map2, 0x6000U, b"%3c", true)
  let r2 = host_sscanf(map2, mem2, 0x6800U, 0x6000U, [buf])
  assert_eq(r2.value, Some(1UL))
  assert_eq(mem2.load_u32(map2, buf), Ok(0x00636261U))
}

///|
/// `#` 对 o 的「提精度」语义（PR #462 审阅 P2-1/P2-2 处置，2026-11-03）：
/// C11 7.21.6.1p6——# 对 o = 提高精度以强制首位 0，与精度补零**同一件事**
/// 非叠加（旧 pad 补零再拼 prefix 双重给零：`%#.3o` 8 → `0010` vs clang
/// `010`）；括号句特例「值 0 + 精度 0 → 单 0」（旧空串）；`%#o` 0 不提
/// 精度（clang `0` 非 `00`）。
test "printf_b4_hash_o_precision_semantics" {
  let (map, mem) = fresh()
  let (log, r) = printf_run(
    map,
    mem,
    "[%#.3o][%#.5o][%#5.3o][%-#8.3o][%#.0o][%#o][%#.3o][%#o][%#08o]",
    [
      (8).to_uint64(),
      (8).to_uint64(),
      (8).to_uint64(),
      (8).to_uint64(),
      (0).to_uint64(),
      (0).to_uint64(),
      (0).to_uint64(),
      (8).to_uint64(),
      (8).to_uint64(),
    ],
  )
  assert_eq(r.trap, None)
  assert_eq(
    log.join(OutputKind::Stdout),
    b"[010][00010][  010][010     ][0][0][000][010][00000010]",
  )
}

///|
/// `#` 的「恒含小数点」族（PR #462 审阅 P2-3 处置）：C11 7.21.6.1p6 对
/// a/A/e/E/f/F/g/G——`%#.0f` 1.5 → `2.`（旧 `2`）；`%#.0e` → `2.e+00`
///（旧 `2e+00`）；g 族 alt 保尾零路径本含此语义（`%#.0g` → `2.` 旧已对）。
test "printf_b4_hash_decimal_point_family" {
  let (map, mem) = fresh()
  let (log, r) = printf_run(
    map,
    mem,
    "[%#.0f][%#.0F][%#.0e][%#.0E][%#.0g][%#.0a][%#f][%#.1f]",
    [
      1.5.reinterpret_as_uint64(),
      1.5.reinterpret_as_uint64(),
      1.5.reinterpret_as_uint64(),
      1.5.reinterpret_as_uint64(),
      1.5.reinterpret_as_uint64(),
      1.5.reinterpret_as_uint64(),
      1.0.reinterpret_as_uint64(),
      1.5.reinterpret_as_uint64(),
    ],
  )
  assert_eq(r.trap, None)
  // %#.0a 1.5：精度 0 + # → 0x2.p+0（format_a alt 分支）
  assert_eq(
    log.join(OutputKind::Stdout),
    b"[2.][2.][2.e+00][2.E+00][2.][0x2.p+0][1.000000][1.5]",
  )
}
