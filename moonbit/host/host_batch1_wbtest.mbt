///|
/// S6 host 余量批一号·ctype / math / convert / misc 白盒锚点。

// ── ctype：谓词表 + 变换边界 ───────────────────────────────────────────────

test "ctype_predicates_table" {
  // 数字 / 字母 / 大小写边界
  assert_eq(host_isdigit(48), 1)
  assert_eq(host_isdigit(57), 1)
  assert_eq(host_isdigit(47), 0)
  assert_eq(host_isdigit(58), 0)
  assert_eq(host_isalpha(97), 1)
  assert_eq(host_isalpha(122), 1)
  assert_eq(host_isalpha(65), 1)
  assert_eq(host_isalpha(90), 1)
  assert_eq(host_isalpha(91), 0)
  assert_eq(host_islower(97), 1)
  assert_eq(host_islower(96), 0)
  assert_eq(host_isupper(65), 1)
  assert_eq(host_isupper(97), 0)
  assert_eq(host_isalnum(53), 1)
  assert_eq(host_isalnum(64), 0)
  // 空白集六员 + 邻位
  assert_eq(host_isspace(32), 1)
  assert_eq(host_isspace(9), 1)
  assert_eq(host_isspace(10), 1)
  assert_eq(host_isspace(13), 1)
  assert_eq(host_isspace(12), 1)
  assert_eq(host_isspace(11), 1)
  assert_eq(host_isspace(8), 0)
  assert_eq(host_isspace(14), 0)
  // 可打印族三档：print 含空格、graph 不含、punct 排除字母数字空格
  assert_eq(host_isprint(32), 1)
  assert_eq(host_isprint(126), 1)
  assert_eq(host_isprint(31), 0)
  assert_eq(host_isprint(127), 0)
  assert_eq(host_isgraph(32), 0)
  assert_eq(host_isgraph(33), 1)
  assert_eq(host_ispunct(33), 1)
  assert_eq(host_ispunct(32), 0)
  assert_eq(host_ispunct(97), 0)
  // 控制字符两段
  assert_eq(host_iscntrl(0), 1)
  assert_eq(host_iscntrl(31), 1)
  assert_eq(host_iscntrl(32), 0)
  assert_eq(host_iscntrl(127), 1)
  assert_eq(host_iscntrl(126), 0)
  // 十六进制三段
  assert_eq(host_isxdigit(48), 1)
  assert_eq(host_isxdigit(102), 1)
  assert_eq(host_isxdigit(70), 1)
  assert_eq(host_isxdigit(71), 0)
  assert_eq(host_isxdigit(103), 0)
  // blank 两员
  assert_eq(host_isblank(32), 1)
  assert_eq(host_isblank(9), 1)
  assert_eq(host_isblank(10), 0)
}

///|
test "ctype_case_transform" {
  assert_eq(host_tolower(65), 97)
  assert_eq(host_tolower(90), 122)
  assert_eq(host_tolower(97), 97, msg="非大写原样")
  assert_eq(host_tolower(64), 64)
  assert_eq(host_toupper(97), 65)
  assert_eq(host_toupper(122), 90)
  assert_eq(host_toupper(65), 65, msg="非小写原样")
}

// ── math：位模式往返 + 知识值 + 边界位形 ─────────────────────────────────

///|
test "math_bits_roundtrip" {
  // 探针锚：3.14 的 u64 位模式往返
  assert_eq(3.14.reinterpret_as_uint64(), 4614253070214989087UL)
  assert_eq(UInt64::reinterpret_as_double(4614253070214989087UL), 3.14)
  // handler 的位进出无损
  assert_eq(host_sin(0UL), 0UL)
  assert_eq(host_sqrt(4.0.reinterpret_as_uint64()), 2.0.reinterpret_as_uint64())
  assert_eq(
    host_pow(2.0.reinterpret_as_uint64(), 10.0.reinterpret_as_uint64()),
    1024.0.reinterpret_as_uint64(),
  )
  assert_eq(
    host_fabs((-2.5).reinterpret_as_uint64()),
    2.5.reinterpret_as_uint64(),
  )
  assert_eq(
    host_fmod(7.0.reinterpret_as_uint64(), 3.0.reinterpret_as_uint64()),
    1.0.reinterpret_as_uint64(),
  )
  assert_eq(
    host_fmod((-7.0).reinterpret_as_uint64(), 3.0.reinterpret_as_uint64()),
    (-1.0).reinterpret_as_uint64(),
  )
  // fmod(x, 0) = NaN（IEEE；与 libm 同——探针实测）
  let nan_bits = host_fmod(
    7.5.reinterpret_as_uint64(),
    0.0.reinterpret_as_uint64(),
  )
  assert_true(UInt64::reinterpret_as_double(nan_bits).is_nan())
  // log → ln
  assert_eq(host_log(1.0.reinterpret_as_uint64()), 0UL)
  assert_eq(
    host_log10(1000.0.reinterpret_as_uint64()),
    3.0.reinterpret_as_uint64(),
  )
  // 取整族
  assert_eq(host_ceil(1.2.reinterpret_as_uint64()), 2.0.reinterpret_as_uint64())
  assert_eq(
    host_floor(1.8.reinterpret_as_uint64()),
    1.0.reinterpret_as_uint64(),
  )
  assert_eq(
    host_round(2.5.reinterpret_as_uint64()),
    3.0.reinterpret_as_uint64(),
  )
}

///|
test "math_abs_wide_and_edge_bits" {
  assert_eq(host_abs(-5), 5UL)
  assert_eq(host_abs(5), 5UL)
  assert_eq(host_abs(0), 0UL)
  // INT_MIN：取反回绕 + i32→u64 符号扩展（Rust `wrapping_neg as u64` 同位）
  assert_eq(host_abs(-2147483648), 0xFFFFFFFF80000000UL)
  assert_eq(host_llabs(-9223372036854775808L), 0x8000000000000000UL)
  assert_eq(host_llabs(-5L), 5UL)
  // 三角/双曲在 0 点
  assert_eq(host_cos(0UL), 1.0.reinterpret_as_uint64())
  assert_eq(host_tan(0UL), 0UL)
  assert_eq(host_asin(0UL), 0UL)
  assert_eq(host_atan(0UL), 0UL)
  assert_eq(host_sinh(0UL), 0UL)
  assert_eq(host_cosh(0UL), 1.0.reinterpret_as_uint64())
  assert_eq(host_tanh(0UL), 0UL)
  assert_eq(host_exp(0UL), 1.0.reinterpret_as_uint64())
  // atan2 对位（y=0, x=1 → 0）
  assert_eq(host_atan2(0UL, 1.0.reinterpret_as_uint64()), 0UL)
}

// ── convert：字符串→数值 ─────────────────────────────────────────────────

///|
test "atoi_basic_sign_whitespace_garbage" {
  let (map, mem) = fresh()
  put_cstr(mem, map, 0x6000U, "42")
  assert_eq(host_atoi(mem, map, 0x6000U).value, Some(42UL))
  put_cstr(mem, map, 0x6100U, "  -7xyz")
  assert_eq(host_atoi(mem, map, 0x6100U).value, Some(0xFFFFFFFFFFFFFFF9UL))
  put_cstr(mem, map, 0x6200U, "+13")
  assert_eq(host_atoi(mem, map, 0x6200U).value, Some(13UL))
  put_cstr(mem, map, 0x6300U, "")
  assert_eq(host_atoi(mem, map, 0x6300U).value, Some(0UL))
  put_cstr(mem, map, 0x6400U, "abc")
  assert_eq(host_atoi(mem, map, 0x6400U).value, Some(0UL))
}

///|
test "atoi_wraps_like_cless_chain" {
  let (map, mem) = fresh()
  // 2^32 ≡ 0（i32 回绕链）
  put_cstr(mem, map, 0x6000U, "4294967296")
  assert_eq(host_atoi(mem, map, 0x6000U).value, Some(0UL))
  // 2^31 → INT_MIN（符号扩展位模式）
  put_cstr(mem, map, 0x6100U, "2147483648")
  assert_eq(host_atoi(mem, map, 0x6100U).value, Some(0xFFFFFFFF80000000UL))
}

///|
test "atol_i64_values" {
  let (map, mem) = fresh()
  put_cstr(mem, map, 0x6000U, "9223372036854775807")
  assert_eq(host_atol(mem, map, 0x6000U).value, Some(9223372036854775807UL))
  put_cstr(mem, map, 0x6100U, "-1")
  assert_eq(host_atol(mem, map, 0x6100U).value, Some(0xFFFFFFFFFFFFFFFFUL))
}

///|
test "atof_parse_trim_and_garbage_zero" {
  let (map, mem) = fresh()
  put_cstr(mem, map, 0x6000U, "3.14")
  assert_eq(
    host_atof(mem, map, 0x6000U).value,
    Some(3.14.reinterpret_as_uint64()),
  )
  put_cstr(mem, map, 0x6100U, " 1.5 ")
  assert_eq(
    host_atof(mem, map, 0x6100U).value,
    Some(1.5.reinterpret_as_uint64()),
  )
  // oracle 既有偏差锚：整串 parse 失败 → 0.0（C 的 atof 取前缀 12.0）
  put_cstr(mem, map, 0x6200U, "12abc")
  assert_eq(host_atof(mem, map, 0x6200U).value, Some(0UL))
}

///|
test "strtol_base_endptr_errno" {
  let (map, mem) = fresh()
  let endp = 0x7000U
  let errn = 0x7100U
  // base 10 + 停止位
  put_cstr(mem, map, 0x6000U, "123abc")
  let r = host_strtol(mem, map, 0x6000U, endp, 10, Some(errn))
  assert_eq(r.value, Some(123UL))
  assert_eq(mem.load_u32(map, endp), Ok(0x6003U))
  // base 16
  put_cstr(mem, map, 0x6100U, "ff")
  assert_eq(host_strtol(mem, map, 0x6100U, 0U, 16, None).value, Some(255UL))
  // base 16 不剥 0x 前缀（oracle 现状）："0x10" → 0，停止位在 'x' 前
  put_cstr(mem, map, 0x6200U, "0x10")
  let r2 = host_strtol(mem, map, 0x6200U, endp, 16, None)
  assert_eq(r2.value, Some(0UL))
  assert_eq(mem.load_u32(map, endp), Ok(0x6201U))
  // base 0 → 10
  put_cstr(mem, map, 0x6300U, "9")
  assert_eq(host_strtol(mem, map, 0x6300U, 0U, 0, None).value, Some(9UL))
  // 无数字 → errno=1 + 停止位 = 起点
  ignore(mem.store_u32(map, errn, 0U))
  put_cstr(mem, map, 0x6400U, "zz")
  let r3 = host_strtol(mem, map, 0x6400U, endp, 10, Some(errn))
  assert_eq(r3.value, Some(0UL))
  assert_eq(mem.load_u32(map, errn), Ok(1U))
  assert_eq(mem.load_u32(map, endp), Ok(0x6400U))
  // errno_addr = None（无 errno 符号）→ 不写不炸
  assert_eq(host_strtol(mem, map, 0x6400U, 0U, 10, None).value, Some(0UL))
}

///|
test "strtod_token_endptr" {
  let (map, mem) = fresh()
  let endp = 0x7000U
  put_cstr(mem, map, 0x6000U, "3.14abc")
  let r = host_strtod(mem, map, 0x6000U, endp, None)
  assert_eq(r.value, Some(3.14.reinterpret_as_uint64()))
  assert_eq(mem.load_u32(map, endp), Ok(0x6004U))
  put_cstr(mem, map, 0x6100U, "1e3x")
  let r2 = host_strtod(mem, map, 0x6100U, endp, None)
  assert_eq(r2.value, Some(1000.0.reinterpret_as_uint64()))
  assert_eq(mem.load_u32(map, endp), Ok(0x6103U))
  // 指数后符号
  put_cstr(mem, map, 0x6200U, "1e-2")
  let r3 = host_strtod(mem, map, 0x6200U, 0U, None)
  assert_eq(r3.value, Some(0.01.reinterpret_as_uint64()))
}

///|
test "strerror_message_with_nul_and_region" {
  let (map, mem) = fresh()
  let r = host_strerror(map, mem, 4, 9)
  let a = r.value.unwrap().to_uint()
  assert_eq(r.trap, None)
  assert_eq(peek(mem, map, a, 26), b"No such file or directory\x00")
  guard map.region(a) is Some(rec) else { fail("必须登记区域") }
  assert_eq(rec.alloc_by, "strerror")
  assert_eq(rec.size, 26, msg="size 含内嵌 NUL（oracle 口径）")
  // 未知错误号
  let r2 = host_strerror(map, mem, 99, 9)
  let a2 = r2.value.unwrap().to_uint()
  assert_eq(peek(mem, map, a2, 14), b"Unknown error\x00")
}

// ── misc：LCG / 确定性时钟 / unreachable / va_* ───────────────────────────

///|
test "rand_lcg_sequence_from_seed_42" {
  let st = RandState::new(42U)
  // LCG（u32 回绕）：42 * 1103515245 + 12345 = 3397979675 (mod 2^32)，
  // 3397979675 & 0x7fff = 3611
  let v1 = host_rand(st)
  assert_eq(v1, 3611)
  assert_eq(st.seed, 3397979675U)
  // 序列推进（第二个值由新种子决定——关系锚，不硬编码）
  let v2 = host_rand(st)
  assert_true(v2 >= 0 && v2 <= 32767)
  assert_true(st.seed != 3397979675U)
}

///|
test "srand_sets_seed" {
  let st = RandState::new(0U)
  host_srand(st, 1U)
  assert_eq(st.seed, 1U)
  // glibc 风格首值锚：seed=1 → (1103515245+12345) & 0x7fff
  let v = host_rand(st)
  let expect = ((1103515245U + 12345U) & 0x7FFFU).reinterpret_as_int()
  assert_eq(v, expect)
}

///|
test "time_clock_deterministic_and_derived" {
  assert_eq(host_time(true, 123456789UL), 0UL)
  assert_eq(host_clock(true, 123456789UL), 0UL)
  assert_eq(host_time(false, 1234567UL), 1234UL)
  assert_eq(host_clock(false, 1234567UL), 1234567000UL)
}

///|
test "unreachable_trap_text" {
  let t = host_unreachable()
  assert_true(t.contains("unreachable"))
  assert_true(t.contains("逻辑错误"))
}

///|
test "va_start_arg_copy_roundtrip" {
  let (map, mem) = fresh()
  let ap = 0x6000U
  // va_start：ap = last_addr + last_size
  let r = host_va_start(mem, map, ap, 0x7000, 8)
  assert_eq(r.value, None)
  assert_eq(mem.load_u32(map, ap), Ok(0x7008U))
  // va_arg：返回旧游标、前进 size
  let r2 = host_va_arg(mem, map, ap, 4)
  assert_eq(r2.value, Some(0x7008UL))
  assert_eq(mem.load_u32(map, ap), Ok(0x700CU))
  // va_copy：复制游标
  let dst = 0x6100U
  assert_eq(host_va_copy(mem, map, dst, ap).value, None)
  assert_eq(mem.load_u32(map, dst), Ok(0x700CU))
  // va_end：无操作
  assert_eq(host_va_end(ap).value, None)
}
