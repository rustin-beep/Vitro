///| B10 批（#434）convert 族修复锚——审阅 v2 M22 A-3/A-4/A-5/A-6/A-8/
/// A-9/A-10/A-11/A-2 + M17b-A1。
///
/// 真值源：Win clang 22.1.4-UCRT 本机采证（`tmp/b10probe/p2_convert.c` /
/// `p2b_convert_full.c` / `p4_atoi_ws.c`，2026-11-05）+ M22 五方对拍表
/// （WSL gcc 15.2 glibc / clang 21.1.8 与 UCRT 三方一致面为判据）+
/// 《C 真值速查表》。非法 base 域（b1-b3）UCRT 杀进程采不到值，判据取
/// glibc（EINVAL/返 0/endptr=nptr——M22 p08c）。
///
/// 翻面连坐（本批旧锚）：`strtol_base_endptr_errno`（EINVAL 虚构翻面）/
/// `strerror_message_with_nul_and_region`（region 登记翻面）/
/// `atoi_wraps_like_cless_chain`（回绕翻饱和）/ `atol_i64_values`
/// （i64 值域翻 LLP64 饱和）。

///|
/// strtol 饱和失效族（M22 A-3）：修前 `val*eff+digit` i64 回绕绕过
/// LONG_MAX/LONG_MIN 判定——2^63/2^64/17F 全部静默错值（0 或 -1）且不写
/// ERANGE。真值（UCRT=LLP64 long=4；glibc LP64 值不同但同样饱和+ERANGE）：
/// 三形态全饱和 ±2^31 边界 + errno=34。
test "strtol_saturation_beyond_i64_wrap_b10" {
  let (map, mem) = fresh()
  let endp = 0x7000U
  let errn = 0x7100U
  // 2^64（20 位）→ LONG_MAX + ERANGE + endptr 全消费
  ignore(mem.store_u32(map, errn, 0U))
  put_cstr(mem, map, 0x6000U, "18446744073709551616")
  let r = host_strtol(mem, map, 0x6000U, endp, 10, Some(errn))
  assert_eq(
    r.value,
    Some(2147483647UL),
    msg="修前 0（i64 回绕绕过判定）",
  )
  assert_eq(mem.load_u32(map, errn), Ok(34U), msg="修前 0")
  assert_eq(mem.load_u32(map, endp), Ok(0x6014U))
  // 2^63 → LONG_MAX + ERANGE
  ignore(mem.store_u32(map, errn, 0U))
  put_cstr(mem, map, 0x6100U, "9223372036854775808")
  let r2 = host_strtol(mem, map, 0x6100U, 0U, 10, Some(errn))
  assert_eq(r2.value, Some(2147483647UL))
  assert_eq(mem.load_u32(map, errn), Ok(34U))
  // -2^63 → LONG_MIN + ERANGE
  ignore(mem.store_u32(map, errn, 0U))
  put_cstr(mem, map, 0x6200U, "-9223372036854775808")
  let r3 = host_strtol(mem, map, 0x6200U, 0U, 10, Some(errn))
  assert_eq(r3.value, Some((-2147483648L).reinterpret_as_uint64()))
  assert_eq(mem.load_u32(map, errn), Ok(34U))
  // 17 个 F（base 16）→ LONG_MAX + ERANGE（修前 -1）
  ignore(mem.store_u32(map, errn, 0U))
  put_cstr(mem, map, 0x6300U, "0xFFFFFFFFFFFFFFFFF")
  let r4 = host_strtol(mem, map, 0x6300U, 0U, 16, Some(errn))
  assert_eq(r4.value, Some(2147483647UL), msg="修前 -1（i64 回绕）")
  assert_eq(mem.load_u32(map, errn), Ok(34U))
}

///|
/// strtol/strtod 无转换 endptr=nptr 族（M22 A-4）：C11 §7.22.1.4p7
/// 「无转换则 endptr 指向 nptr 原始位置」——修前指向「跳过空白/符号后」
/// （off=1~3），`if (end == str)` 惯用法恒假分支错向。真值：off=0。
/// 连带 A-10：无转换**不写 errno**（修前虚构 EINVAL=22；glibc/UCRT 只在
/// base 非法时设）。
test "strtol_endptr_nptr_semantics_b10" {
  let (map, mem) = fresh()
  let endp = 0x7000U
  let errn = 0x7100U
  // "  -abc"：跳空白+符号后无数字 → endptr=nptr（off=0）+ 不写 errno
  ignore(mem.store_u32(map, errn, 0U))
  put_cstr(mem, map, 0x6000U, "  -abc")
  let r = host_strtol(mem, map, 0x6000U, endp, 10, Some(errn))
  assert_eq(r.value, Some(0UL))
  assert_eq(
    mem.load_u32(map, endp),
    Ok(0x6000U),
    msg="修前 0x6003（跳过后）",
  )
  assert_eq(mem.load_u32(map, errn), Ok(0U), msg="修前虚构 EINVAL=22")
  // 纯符号 / 纯空白同形
  ignore(mem.store_u32(map, errn, 0U))
  put_cstr(mem, map, 0x6100U, "-")
  let r2 = host_strtol(mem, map, 0x6100U, endp, 10, Some(errn))
  assert_eq(r2.value, Some(0UL))
  assert_eq(mem.load_u32(map, endp), Ok(0x6100U), msg="修前 0x6101")
  put_cstr(mem, map, 0x6200U, "   ")
  let r3 = host_strtol(mem, map, 0x6200U, endp, 10, None)
  assert_eq(r3.value, Some(0UL))
  assert_eq(mem.load_u32(map, endp), Ok(0x6200U), msg="修前 0x6203")
}

///|
/// strtol 非法 base 域（M22 A-9）：base 非 0 且 ∉[2,36] → EINVAL +
/// 返回 0 + endptr=nptr（glibc 判据；UCRT invalid parameter handler 杀
/// 进程采不到值——M22 p08c）。修前按该进制解析出静默错值（"z9" base40
/// → 1409）。base=1 怪形态（"0001"→0 off=3）一并消除。
test "strtol_invalid_base_einval_b10" {
  let (map, mem) = fresh()
  let endp = 0x7000U
  let errn = 0x7100U
  ignore(mem.store_u32(map, errn, 0U))
  put_cstr(mem, map, 0x6000U, "z9")
  let r = host_strtol(mem, map, 0x6000U, endp, 40, Some(errn))
  assert_eq(r.value, Some(0UL), msg="修前 1409（按 40 进制解析）")
  assert_eq(mem.load_u32(map, errn), Ok(22U))
  assert_eq(mem.load_u32(map, endp), Ok(0x6000U))
  // base=1 / 负 base 同形
  ignore(mem.store_u32(map, errn, 0U))
  put_cstr(mem, map, 0x6100U, "5")
  assert_eq(host_strtol(mem, map, 0x6100U, 0U, 1, Some(errn)).value, Some(0UL))
  assert_eq(mem.load_u32(map, errn), Ok(22U))
  put_cstr(mem, map, 0x6200U, "5")
  assert_eq(host_strtol(mem, map, 0x6200U, 0U, -1, None).value, Some(0UL))
}

///|
/// strtod 扫描器边界族（M22 A-4/A-5）：无 mantissa 数字回退（"e5"/
/// ".e5"/"-"→off=0）+ 指数后不并点（"1e5.3"→"1e5" off=3——修前整个
/// token "1e5.3" 解析失败返 0.0）。真值 = UCRT `p2b` d1-d4。
test "strtod_scanner_edges_b10" {
  let (map, mem) = fresh()
  let endp = 0x7000U
  let errn = 0x7100U
  // "-"：符号消费后无数字 → 无转换（off=0、0.0、不写 errno）
  ignore(mem.store_u32(map, errn, 0U))
  put_cstr(mem, map, 0x6000U, "-")
  let r = host_strtod(mem, map, 0x6000U, endp, Some(errn))
  assert_eq(r.value, Some(0UL))
  assert_eq(mem.load_u32(map, endp), Ok(0x6000U), msg="修前 0x6001")
  assert_eq(mem.load_u32(map, errn), Ok(0U), msg="修前虚构 EINVAL=22")
  // "e5"：mantissa 无数字 → 无转换（修前 token="e5" off=2）
  put_cstr(mem, map, 0x6100U, "e5")
  let r2 = host_strtod(mem, map, 0x6100U, endp, None)
  assert_eq(r2.value, Some(0UL))
  assert_eq(mem.load_u32(map, endp), Ok(0x6100U), msg="修前 0x6102")
  // ".e5" 同形
  put_cstr(mem, map, 0x6200U, ".e5")
  let r3 = host_strtod(mem, map, 0x6200U, endp, None)
  assert_eq(r3.value, Some(0UL))
  assert_eq(mem.load_u32(map, endp), Ok(0x6200U), msg="修前 0x6203")
  // "1e5.3"：指数段后 '.' 终止 subject → 100000 + off=3（修前 0.0/off=5）
  put_cstr(mem, map, 0x6300U, "1e5.3")
  let r4 = host_strtod(mem, map, 0x6300U, endp, None)
  assert_eq(r4.value, Some(100000.0.reinterpret_as_uint64()))
  assert_eq(mem.load_u32(map, endp), Ok(0x6303U), msg="修前 0x6305")
  // "2e1.0" 同形
  put_cstr(mem, map, 0x6400U, "2e1.0")
  let r5 = host_strtod(mem, map, 0x6400U, endp, None)
  assert_eq(r5.value, Some(20.0.reinterpret_as_uint64()))
  assert_eq(mem.load_u32(map, endp), Ok(0x6403U))
}

///|
/// strtod 上溢/下溢 ERANGE（M22 A-6 + B10 复测 d5/d6）：上溢 ±inf +
/// errno=34（修前 0.0——比 inf 误导）；下溢值 0 + errno=34（UCRT/glibc
/// 均设，修前不设）。
test "strtod_overflow_inf_range_b10" {
  let (map, mem) = fresh()
  let errn = 0x7100U
  ignore(mem.store_u32(map, errn, 0U))
  put_cstr(mem, map, 0x6000U, "1e400")
  let r = host_strtod(mem, map, 0x6000U, 0U, Some(errn))
  assert_eq(
    r.value,
    Some(9218868437227405312UL),
    msg="+inf 位模式（修前 0.0）",
  )
  assert_eq(mem.load_u32(map, errn), Ok(34U))
  // -1e400 → -inf
  ignore(mem.store_u32(map, errn, 0U))
  put_cstr(mem, map, 0x6100U, "-1e400")
  let r2 = host_strtod(mem, map, 0x6100U, 0U, Some(errn))
  assert_eq(r2.value, Some(18442240474082181120UL), msg="-inf 位模式")
  assert_eq(mem.load_u32(map, errn), Ok(34U))
  // 1e-400 → 0.0 + ERANGE（UCRT d6 实测；修前 errno=0）
  ignore(mem.store_u32(map, errn, 0U))
  put_cstr(mem, map, 0x6200U, "1e-400")
  let r3 = host_strtod(mem, map, 0x6200U, 0U, Some(errn))
  assert_eq(r3.value, Some(0UL))
  assert_eq(mem.load_u32(map, errn), Ok(34U), msg="修前 0（下溢不设）")
}

///|
/// strtod INF/INFINITY/NAN 族（M22 A-8；C99 §6.4.4.2 strtod 须接受）：
/// 大小写混排 + 可选符号 + NAN(n-char-seq)（括号须闭合才消费）+ 最长
/// 合法前缀（"infin"→"inf"）。真值 = UCRT `p2b` i1-i3/n1-n3。
test "strtod_inf_nan_family_b10" {
  let (map, mem) = fresh()
  let endp = 0x7000U
  let errn = 0x7100U
  // inf / infinity
  ignore(mem.store_u32(map, errn, 0U))
  put_cstr(mem, map, 0x6000U, "infinity")
  let r = host_strtod(mem, map, 0x6000U, endp, Some(errn))
  assert_eq(r.value, Some(9218868437227405312UL), msg="修前 0.0")
  assert_eq(mem.load_u32(map, endp), Ok(0x6008U), msg="全消费 8 字符")
  assert_eq(mem.load_u32(map, errn), Ok(0U))
  put_cstr(mem, map, 0x6100U, "-INF")
  let r2 = host_strtod(mem, map, 0x6100U, endp, None)
  assert_eq(r2.value, Some(18442240474082181120UL))
  assert_eq(mem.load_u32(map, endp), Ok(0x6104U))
  // "infin" → 最长合法前缀 "inf"（off=3）
  put_cstr(mem, map, 0x6200U, "infin")
  let r3 = host_strtod(mem, map, 0x6200U, endp, None)
  assert_eq(r3.value, Some(9218868437227405312UL))
  assert_eq(mem.load_u32(map, endp), Ok(0x6203U))
  // nan（正 NaN）
  put_cstr(mem, map, 0x6300U, "nan")
  let r4 = host_strtod(mem, map, 0x6300U, endp, None)
  assert_true(
    r4.value.unwrap().reinterpret_as_double().is_nan(),
    msg="修前 0.0",
  )
  assert_eq(mem.load_u32(map, endp), Ok(0x6303U))
  // NAN(123)：括号段闭合全消费（off=8）
  put_cstr(mem, map, 0x6400U, "NAN(123)")
  let r5 = host_strtod(mem, map, 0x6400U, endp, None)
  assert_true(r5.value.unwrap().reinterpret_as_double().is_nan())
  assert_eq(mem.load_u32(map, endp), Ok(0x6408U))
  // "nan("：括号未闭合不消费（off=3）
  put_cstr(mem, map, 0x6500U, "nan(")
  let r6 = host_strtod(mem, map, 0x6500U, endp, None)
  assert_true(r6.value.unwrap().reinterpret_as_double().is_nan())
  assert_eq(mem.load_u32(map, endp), Ok(0x6503U))
}

///|
/// strtod hex 尾点（M22 A-12）：hex significand 允许「hexdigits '.'」
/// （点后无数字）——"0x1." 点应消费（off=4，修前 off=3）；十进制 "1."
/// 修前即消费（off=2），hex 与十进制口径对齐。真值 = UCRT h1/h2。
test "strtod_hex_trailing_dot_b10" {
  let (map, mem) = fresh()
  let endp = 0x7000U
  put_cstr(mem, map, 0x6000U, "0x1.")
  let r = host_strtod(mem, map, 0x6000U, endp, None)
  assert_eq(r.value, Some(1.0.reinterpret_as_uint64()))
  assert_eq(
    mem.load_u32(map, endp),
    Ok(0x6004U),
    msg="修前 0x6003（点不消费）",
  )
  // "0x1.p3" → 8.0 全消费（点后直挂 p 指数）
  put_cstr(mem, map, 0x6100U, "0x1.p3")
  let r2 = host_strtod(mem, map, 0x6100U, endp, None)
  assert_eq(r2.value, Some(8.0.reinterpret_as_uint64()))
  assert_eq(mem.load_u32(map, endp), Ok(0x6106U))
}

///|
/// atol LLP64 饱和连坐（M22 A-11）：atol ≡ strtol(str,NULL,10)（C
/// §7.22.1.2），LLP64 long=4 → 饱和 ±2^31（UCRT L1 实测）。修前纯 i64
/// 回绕（"3000000000"→-1294967296）且与同文件 strtol 饱和语义内部不一
/// 致；旧锚 `atol_i64_values`（LP64 值域）随翻。
test "atol_llp64_saturation_b10" {
  let (map, mem) = fresh()
  put_cstr(mem, map, 0x6000U, "3000000000")
  assert_eq(
    host_atol(mem, map, 0x6000U).value,
    Some(2147483647UL),
    msg="修前 -1294967296（i64 回绕截 32 位）",
  )
  put_cstr(mem, map, 0x6100U, "9223372036854775807")
  assert_eq(
    host_atol(mem, map, 0x6100U).value,
    Some(2147483647UL),
    msg="修前 9223372036854775807（LP64 值域）",
  )
  put_cstr(mem, map, 0x6200U, "-2147483649")
  assert_eq(
    host_atol(mem, map, 0x6200U).value,
    Some((-2147483648L).reinterpret_as_uint64()),
    msg="负向饱和 LONG_MIN",
  )
  // 域内原值不动
  put_cstr(mem, map, 0x6300U, "-1")
  assert_eq(
    host_atol(mem, map, 0x6300U).value,
    Some((-1L).reinterpret_as_uint64()),
  )
}

///|
/// atoi ≡ (int)strtol 饱和单源（M22 A-2 + M17b-A1；UCRT L3/L4 实测：
/// 4294967296→2147483647、-2147483649→-2147483648——饱和经 (int) 传导）。
/// 修前：CLI 侧 atoi 走 Bytecode 预编译段（空白前缀只认空格 + 超域
/// **整程序 trap**「整数加法溢出」归因「第 69 行」）；Host 侧
/// `atoi_bytes` 回绕（`atoi_wraps_like_cless_chain` 锚）——双源不同义。
/// 本批：改判 Host + 饱和单源（B10 route.mbt `is_host_rerouted`+atoi）。
test "atoi_strtol_saturation_single_source_b10" {
  let (map, mem) = fresh()
  put_cstr(mem, map, 0x6000U, "2147483648")
  assert_eq(
    host_atoi(mem, map, 0x6000U).value,
    Some(2147483647UL),
    msg="修前回绕 0xFFFFFFFF80000000",
  )
  put_cstr(mem, map, 0x6100U, "4294967296")
  assert_eq(
    host_atoi(mem, map, 0x6100U).value,
    Some(2147483647UL),
    msg="修前回绕 0",
  )
  put_cstr(mem, map, 0x6200U, "-2147483649")
  assert_eq(
    host_atoi(mem, map, 0x6200U).value,
    Some((-2147483648L).reinterpret_as_uint64()),
  )
  // 域内边界原值（UCRT L5/L6）
  put_cstr(mem, map, 0x6300U, "2147483647")
  assert_eq(host_atoi(mem, map, 0x6300U).value, Some(2147483647UL))
  put_cstr(mem, map, 0x6400U, "-2147483648")
  assert_eq(
    host_atoi(mem, map, 0x6400U).value,
    Some((-2147483648L).reinterpret_as_uint64()),
  )
}

///|
/// atoi 空白前缀全集（M17b-A1：Bytecode 段 ip 297-300 循环条件只比较
/// 常量 32——`\t\n\v\f\r` 前缀全返 0；Host 侧 `is_ascii_ws_byte` 本就对
/// 但被遮蔽不可达）。真值 = UCRT `p4` 实测 `42 42 42 7 -9 13`，与
/// WSL glibc 三方一致（M17b 探针五 p1）。改判 Host 后经本锚锁定。
test "atoi_whitespace_prefix_full_set_b10" {
  let (map, mem) = fresh()
  put_cstr(mem, map, 0x6000U, " 42")
  assert_eq(host_atoi(mem, map, 0x6000U).value, Some(42UL))
  put_cstr(mem, map, 0x6100U, "\t42")
  assert_eq(host_atoi(mem, map, 0x6100U).value, Some(42UL))
  put_cstr(mem, map, 0x6200U, "\n42")
  assert_eq(host_atoi(mem, map, 0x6200U).value, Some(42UL))
  put_cstr(mem, map, 0x6300U, "\r\n+7")
  assert_eq(host_atoi(mem, map, 0x6300U).value, Some(7UL))
  put_cstr(mem, map, 0x6400U, "\u{0B}-9")
  assert_eq(
    host_atoi(mem, map, 0x6400U).value,
    Some((-9L).reinterpret_as_uint64()),
  )
  put_cstr(mem, map, 0x6500U, "\f13")
  assert_eq(host_atoi(mem, map, 0x6500U).value, Some(13UL))
}

///|
/// strerror 静态串语义（M22 A-7）：C 语义返回静态串（free 它才是 UB），
/// 学生遵守 C 语义不应被泄漏报告惩罚。修前每次调用 allocate_raw +
/// register_alloc（alloc_by="strerror"）——9 次调用 = 「发现 9 处未释放
/// 的堆内存」。B10 改「无主静态块」：保留 allocate+写入（地址可读），
/// 不 register_alloc（regions 无条目 → 泄漏报告天然不见；free 它走无
/// 效 free 诊断——教学上 free 静态串被拦，比真机 UB 更安全）。
/// 连坐翻面旧锚 `strerror_message_with_nul_and_region`（region 登记）。
test "strerror_static_block_no_leak_entry_b10" {
  let (map, mem) = fresh()
  for i = 0; i < 3; i = i + 1 {
    let r = host_strerror(map, mem, 2, 9)
    let a = r.value.unwrap().to_uint()
    assert_eq(peek(mem, map, a, 26), b"No such file or directory\x00")
  }
  let mut strerror_regions = 0
  for pair in map.regions_to_array() {
    if pair.1.alloc_by == "strerror" {
      strerror_regions = strerror_regions + 1
    }
  }
  assert_eq(
    strerror_regions,
    0,
    msg="修前 3（每次调用一条 region 进泄漏报告）",
  )
}
