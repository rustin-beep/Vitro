///|
/// S6 host 余量批二号·printf 引擎与 IO 族白盒锚点。
///
/// 值锚全部来自 **oracle release 二进制实测**（2026-09-23，`vitro_cli run`
/// 亲跑）：定点 half-even（0.125→0.12）、`%+d` 旗标无效、`%.1s` 忽略精度、
/// `putchar(200)`→`C3 88`、`%g` 指数段 `e-05`/`e+06`。

// ── format_fixed：精确展开 + half-even ───────────────────────────────────

test "format_fixed_half_even_oracle_truth" {
  assert_eq(
    format_fixed(0.125, 2),
    "0.12",
    msg="半平局取偶（oracle 实测）",
  )
  assert_eq(format_fixed(3.5, 0), "4", msg="3.5 → 4（偶）")
  assert_eq(format_fixed(2.5, 0), "2", msg="2.5 → 2（偶）")
  assert_eq(format_fixed(999999.5, 0), "1000000", msg="%g 内部路径同锚")
  assert_eq(format_fixed(1.0 / 3, 6), "0.333333")
  assert_eq(format_fixed(2.5, 2), "2.50")
  assert_eq(format_fixed(0.25, 3), "0.250")
  assert_eq(format_fixed(2.675, 2), "2.67", msg="2.675 二进制是 2.67499…")
  assert_eq(format_fixed(0.05, 1), "0.1", msg="0.05 二进制是 0.05000…277")
  assert_eq(format_fixed(-0.0, 0), "-0", msg="符号保留（oracle 实测）")
  assert_eq(format_fixed(123456.789, 2), "123456.79")
  assert_eq(format_fixed(5.0, 2), "5.00", msg="整数补零")
  assert_eq(format_fixed(0.5, 2), "0.50", msg="左补零路径")
  assert_eq(format_fixed(@double.not_a_number, 2), "NaN")
  assert_eq(format_fixed(@double.infinity, 2), "inf")
  assert_eq(format_fixed(@double.neg_infinity, 2), "-inf")
  // 大整数路径（e ≥ 0：2^60 精确）
  assert_eq(format_fixed(1152921504606846976.0, 0), "1152921504606846976")
}

// ── format_g：边界与指数段 ───────────────────────────────────────────────

///|
test "format_g_oracle_truth" {
  assert_eq(format_g(0.0001, 6, false), "0.0001", msg="exp=-4 定点边界")
  assert_eq(format_g(100000.0, 6, false), "100000", msg="exp=5 < prec 定点")
  assert_eq(format_g(0.00001, 6, false), "1e-05")
  assert_eq(format_g(1234567.0, 6, false), "1.23457e+06")
  assert_eq(format_g(1.5e-5, 6, false), "1.5e-05")
  assert_eq(format_g(999999.5, 6, false), "1000000")
  assert_eq(format_g(0.000123456, 6, false), "0.000123456")
  assert_eq(format_g(-1.5e-5, 6, false), "-1.5e-05")
  assert_eq(format_g(0.00001, 6, true), "1E-05", msg="大写 E")
  assert_eq(format_g(0.0, 6, false), "0")
}

// ── apply_width / 旗标（oracle 既有偏差照搬）──────────────────────────────

///|
test "apply_width_flags_oracle_truth" {
  assert_eq(apply_width("42", Some(5), ""), "   42")
  assert_eq(apply_width("42", Some(5), "-"), "42   ")
  assert_eq(apply_width("42", Some(5), "0"), "00042")
  assert_eq(apply_width("42", None, ""), "42")
  // %+d / "% d"：旗标无效（oracle apply_width 只认 -/0）
  assert_eq(apply_width("42", None, "+"), "42")
  assert_eq(apply_width("42", None, " "), "42")
  // 0 旗标与 - 同时：- 优先
  assert_eq(apply_width("42", Some(5), "0-"), "42   ")
}

// ── printf 全管道（内存 + 输出通道）──────────────────────────────────────

///|
/// 便捷：格式串落内存 + 输出收集。
fn printf_run(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  fmt : String,
  args : Array[UInt64],
) -> (OutputLog, HostMemReply) raise {
  let fmt_addr = 0x6000U
  put_bytes(mem, map, fmt_addr, @utf8.encode(fmt), true)
  let log = OutputLog::new()
  let r = host_printf_n(map, mem, log, fmt_addr, args)
  (log, r)
}

///|
test "printf_pipeline_mixed_specs" {
  let (map, mem) = fresh()
  put_cstr(mem, map, 0x6800U, "hi")
  let (log, r) = printf_run(map, mem, "%d|%s|%c|%x|%5.2f", [
    (42).to_uint64(),
    0x6800U.to_uint64(),
    (65).to_uint64(),
    (255).to_uint64(),
    3.14159.reinterpret_as_uint64(),
  ])
  assert_eq(r.trap, None)
  assert_eq(r.value, None, msg="printf 无返回值")
  assert_eq(log.join(OutputKind::Stdout), b"42|hi|A|ff| 3.14")
}

///|
test "printf_depth_guard_and_budget" {
  let (map, mem) = fresh()
  // 守卫：specs > args → 教学 trap（printf 族有守卫，坑 17 的另一半在后）
  let (_, r) = printf_run(map, mem, "%d %d", [(1).to_uint64()])
  guard r.trap is Some(t) else { fail("参数不足必须 trap") }
  assert_eq(
    t, "printf: 格式字符串要求的参数多于实际提供的参数。",
  )
  // U2#9 预算：宽度超 1MB → 教学 trap
  let (_, r2) = printf_run(map, mem, "%2000000d", [(1).to_uint64()])
  guard r2.trap is Some(t2) else { fail("超预算必须 trap") }
  assert_true(t2.contains("字段宽度 2000000 超出上限"))
}

///|
test "printf_percent_c_high_byte_single_byte" {
  let (map, mem) = fresh()
  let (log, r) = printf_run(map, mem, "%c", [(200).to_uint64()])
  assert_eq(r.trap, None)
  // DIFF-LIB-PRINTF-01 销案翻转（2026-10-05 批二-b）：%c 低字节单字节
  // 直出（与 putchar 一致；Clang printf("%c",200) 落单字节 0xC8）——
  // 旧两字节 C3 88 系 oracle char 通道照搬
  assert_eq(log.join(OutputKind::Stdout), Bytes::make(1, (200).to_byte()))
}

///|
test "printf_unknown_spec_consumes_arg_and_passthrough" {
  let (map, mem) = fresh()
  // 未知说明符 `%q`：原样输出且消耗实参（照搬）
  let (log, r) = printf_run(map, mem, "a%qb%dc", [
    (7).to_uint64(),
    (9).to_uint64(),
  ])
  assert_eq(r.trap, None)
  assert_eq(log.join(OutputKind::Stdout), b"a%qb9c")
  // 行尾孤立 %：原样
  let (log2, _) = printf_run(map, mem, "x%", [])
  assert_eq(log2.join(OutputKind::Stdout), b"x%")
}

// ── fprintf / sprintf / snprintf / puts / putchar ────────────────────────

///|
test "fprintf_stderr_split" {
  let (map, mem) = fresh()
  let vfs = VirtualFileSystem::new()
  put_bytes(mem, map, 0x6000U, b"boom\x00", false)
  let log = OutputLog::new()
  let r = host_fprintf_n(map, mem, log, vfs, 2UL, 0x6000U, [])
  assert_eq(r.trap, None)
  assert_eq(log.join(OutputKind::Stderr), b"boom")
  assert_eq(log.len_of(OutputKind::Stdout), 0)
  // stream=1 → stdout 通道（显式分流）
  let log2 = OutputLog::new()
  ignore(host_fprintf_n(map, mem, log2, vfs, 1UL, 0x6000U, []))
  assert_eq(log2.join(OutputKind::Stdout), b"boom")
}

///|
test "fprintf_custom_file_persists" {
  // DIFF-LIB-FPRINTF-01 销案锚（2026-10-05 批二-a）：fprintf 到 fopen 的
  // 自定义 FILE* 落盘 VFS（fopen 读回端到端）；旧形态静默转 stdout 通道
  //（照搬 oracle 在案）——修复后 stdout 通道零串扰
  let (map, mem) = fresh()
  let vfs = VirtualFileSystem::new()
  put_cstr(mem, map, 0x6000U, "v=%d\n")
  let fd = vfs.fopen(map, "out.txt", "w")
  assert_true(fd > 0U)
  // FILE* 协议 = 堆上 4 字节存 fd（host_fopen 同款——测试直接构造）
  ignore(mem.store_u32(map, 0x6500U, fd))
  let log = OutputLog::new()
  let r = host_fprintf_n(map, mem, log, vfs, 0x6500UL, 0x6000U, [
    (7).to_uint64(),
  ])
  assert_eq(r.trap, None)
  assert_eq(log.len_of(OutputKind::Stdout), 0)
  // 读回（文本模式写 \n 已展开 CRLF，文本模式读压回）——逐字节等于格式化输出
  let fdr = vfs.fopen(map, "out.txt", "r")
  assert_true(fdr > 0U)
  let buf = 0x7000U
  let n = vfs.fread(mem, map, fdr, buf, 1, 16)
  assert_eq(n, 4)
  assert_eq(peek(mem, map, buf, 5), b"v=7\n\x00")
}

///|
test "sprintf_writes_and_returns_len" {
  let (map, mem) = fresh()
  put_cstr(mem, map, 0x6000U, "n=%d")
  let buf = 0x7000U
  let r = host_sprintf(map, mem, buf, 0x6000U, [(42).to_uint64()])
  assert_eq(r.value, Some(4UL))
  assert_eq(peek(mem, map, buf, 5), b"n=42\x00")
}

///|
test "snprintf_truncates_returns_full_len" {
  let (map, mem) = fresh()
  put_cstr(mem, map, 0x6000U, "abcdef")
  let buf = 0x7000U
  // size=4 → 写 3 字节 + NUL；返回完整长度 6
  let r = host_snprintf(map, mem, buf, 4, 0x6000U, [])
  assert_eq(r.value, Some(6UL))
  assert_eq(peek(mem, map, buf, 4), b"abc\x00")
  // size=0：不写，仍返回 6
  let r2 = host_snprintf(map, mem, 0x7100U, 0, 0x6000U, [])
  assert_eq(r2.value, Some(6UL))
  assert_eq(mem.load_i8(map, 0x7100U), Ok(0))
}

///|
test "puts_appends_newline_and_putchar_byte_channel" {
  let (map, mem) = fresh()
  put_cstr(mem, map, 0x6000U, "hello")
  let log = OutputLog::new()
  let r = host_puts(map, mem, log, 0x6000U)
  assert_eq(r.value, Some(1UL))
  assert_eq(log.join(OutputKind::Stdout), b"hello\n")
  // putchar(200)：单字节 0xC8（DIFF-LIB-PUTCHAR-01 销账锚 2026-10-05——
  // 旧形态 C3 88 两字节系 oracle char 通道照搬，脱钩后回归 C 字节语义）
  let log2 = OutputLog::new()
  host_putchar(log2, 200UL)
  assert_eq(log2.join(OutputKind::Stdout), b"\xC8")
}

// ── getchar / ungetc：行内游标 + EOF 粘滞 + 等待 ─────────────────────────

///|
test "getchar_reads_across_lines_and_eof_sticky" {
  // 形态勘误（2026-09-28 审阅批 P1）：锚输入改为 oracle 可达形态
  // [b"ab\n", b"cd"]（split_inclusive 产物——"ab\ncd" 的切行）；旧形态
  // [b"ab", b"cd"]（行不含换行）是 V-P1-13 形态转换期的中间态构造，
  // 在 oracle 的 split_inclusive 切行下不可产生，且把「getchar 跳过
  // 行间换行」的错误行为固定成了预期（审阅实锤：serve 通道 n=4 vs
  // oracle n=6）。行含 \n 后 getchar 逐字节自然读到（a b \n c d）
  let input = InputState::new([b"ab\n", b"cd"], true)
  assert_eq(host_getchar(input), InputOutcome::Value(97UL))
  assert_eq(host_getchar(input), InputOutcome::Value(98UL))
  assert_eq(
    host_getchar(input),
    InputOutcome::Value(10UL),
    msg="行尾换行是数据字节（oracle split_inclusive）",
  )
  assert_eq(host_getchar(input), InputOutcome::Value(99UL))
  assert_eq(host_getchar(input), InputOutcome::Value(100UL))
  // 耗尽 → -1 + 粘滞
  assert_eq(host_getchar(input), InputOutcome::Value(0xFFFFFFFFFFFFFFFFUL))
  assert_eq(input.eof, true)
  assert_eq(host_getchar(input), InputOutcome::Value(0xFFFFFFFFFFFFFFFFUL))
}

///|
test "getchar_interactive_waits_and_ungetc_pushback" {
  let input = InputState::new([], false)
  assert_eq(host_getchar(input), InputOutcome::Waiting)
  // ungetc 回推一字节（返回 c 本身，符号扩展）
  let input2 = InputState::new([b"x"], true)
  ignore(host_ungetc(input2, 90))
  assert_eq(host_getchar(input2), InputOutcome::Value(90UL))
  // 回退只一次：随后按流继续
  assert_eq(host_getchar(input2), InputOutcome::Value(120UL))
  assert_eq(host_getchar(input2), InputOutcome::Value(0xFFFFFFFFFFFFFFFFUL))
}

// ── scanf：V-P1-13 流式游标五连锚 ────────────────────────────────────────

///|
/// 便捷：fmt 落内存后跑一次 scanf。
fn scanf_run(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  input : InputState,
  fmt : String,
  ptrs : Array[UInt],
) -> InputOutcome raise {
  put_bytes(mem, map, 0x6000U, @utf8.encode(fmt), true)
  host_scanf_n(map, mem, input, [], 0x6000U, ptrs)
}

///|
test "scanf_stream_cursor_five_calls" {
  let (map, mem) = fresh()
  let input = InputState::new([b"1 2", b"3 4"], true)
  let pa = 0x8000U
  let pb = 0x8100U
  // 第 1 次：读 1（游标停在行内偏移 1）
  assert_eq(scanf_run(map, mem, input, "%d", [pa]), InputOutcome::Value(1UL))
  assert_eq(mem.load_u32(map, pa), Ok(1U))
  assert_eq(input.index, 0)
  assert_eq(input.char_offset, 1)
  // 第 2 次：读同行剩余的 2（V-P1-13 锚——旧行消费语义会读到 3）
  assert_eq(scanf_run(map, mem, input, "%d", [pb]), InputOutcome::Value(1UL))
  assert_eq(mem.load_u32(map, pb), Ok(2U))
  // 第 3 次：跨行读 3（经补位 \n 跳白）
  assert_eq(scanf_run(map, mem, input, "%d", [pa]), InputOutcome::Value(1UL))
  assert_eq(mem.load_u32(map, pa), Ok(3U))
  // 第 4 次：读 4
  assert_eq(scanf_run(map, mem, input, "%d", [pb]), InputOutcome::Value(1UL))
  assert_eq(mem.load_u32(map, pb), Ok(4U))
  // 第 5 次：Batch 耗尽 → EOF(-1) + 粘滞
  assert_eq(
    scanf_run(map, mem, input, "%d", [pa]),
    InputOutcome::Value(0xFFFFFFFFFFFFFFFFUL),
  )
  assert_eq(input.eof, true)
}

///|
test "scanf_percent_c_reads_padded_newline" {
  let (map, mem) = fresh()
  let input = InputState::new([b"7"], true)
  let pd = 0x8000U
  let pc = 0x8100U
  // %d 消费 7；%c 经补位 '\n' 读到行分隔（C 流式语义）
  assert_eq(
    scanf_run(map, mem, input, "%d%c", [pd, pc]),
    InputOutcome::Value(2UL),
  )
  assert_eq(mem.load_i8(map, pc), Ok(10))
}

///|
test "scanf_batch_eof_exhaust_mid_format" {
  let (map, mem) = fresh()
  let input = InputState::new([b"7"], true)
  let pa = 0x8000U
  let pb = 0x8100U
  // "%d %d"：第二个 %d 因流耗尽中止 → matched=1 + 置粘滞
  assert_eq(
    scanf_run(map, mem, input, "%d %d", [pa, pb]),
    InputOutcome::Value(1UL),
  )
  assert_eq(mem.load_u32(map, pa), Ok(7U))
  assert_eq(input.eof, true, msg="因流耗尽中止 → 粘滞（A1）")
  // 已粘滞：后续 scanf 恒 EOF
  assert_eq(
    scanf_run(map, mem, input, "%d", [pa]),
    InputOutcome::Value(0xFFFFFFFFFFFFFFFFUL),
  )
}

///|
test "scanf_literal_match_and_interactive_waiting" {
  let (map, mem) = fresh()
  let input = InputState::new([b"a=5"], true)
  let pa = 0x8000U
  assert_eq(scanf_run(map, mem, input, "a=%d", [pa]), InputOutcome::Value(1UL))
  assert_eq(mem.load_u32(map, pa), Ok(5U))
  // 字面量不匹配：matched 0、游标不动、不置 EOF
  let input2 = InputState::new([b"b=1"], true)
  assert_eq(scanf_run(map, mem, input2, "a=%d", [pa]), InputOutcome::Value(0UL))
  assert_eq(input2.eof, false)
  assert_eq(input2.index, 0)
  assert_eq(
    input2.char_offset,
    0,
    msg="字面量不匹配输入流保持不动",
  )
  // Interactive 空 → Waiting
  let input3 = InputState::new([], false)
  assert_eq(scanf_run(map, mem, input3, "%d", [pa]), InputOutcome::Waiting)
}

///|
test "scanf_percent_s_stack_guard_and_ll_ull" {
  let (map, mem) = fresh()
  let input = InputState::new([b"hello 42 9223372036854775807"], true)
  let ps = 0x8000U
  let pd = 0x8100U
  let pll = 0x8200U
  put_bytes(mem, map, 0x6000U, b"%s %d %lld", true)
  assert_eq(
    host_scanf_n(map, mem, input, [], 0x6000U, [ps, pd, pll]),
    InputOutcome::Value(3UL),
  )
  assert_eq(peek(mem, map, ps, 6), b"hello\x00")
  assert_eq(mem.load_u32(map, pd), Ok(42U))
  assert_eq(mem.load_u64(map, pll), Ok(9223372036854775807UL))
  // %s 栈缓冲溢出：V-P1-6 trap
  let input2 = InputState::new([b"abcdef"], true)
  let span = StackBufferSpan::{ base: 0x9000U, size: 4, name: "buf", }
  put_bytes(mem, map, 0x6000U, b"%s", true)
  match host_scanf_n(map, mem, input2, [span], 0x6000U, [0x9000U]) {
    InputOutcome::Trap(t) =>
      assert_true(t.contains("栈上缓冲区 'buf' 溢出"))
    _ => fail("%s 栈溢出必须 trap")
  }
  // %f/%lf：4/8 字节位模式
  let input3 = InputState::new([b"1.5 2.5"], true)
  let pf = 0x8000U
  let plf = 0x8100U
  put_bytes(mem, map, 0x6000U, b"%f %lf", true)
  assert_eq(
    host_scanf_n(map, mem, input3, [], 0x6000U, [pf, plf]),
    InputOutcome::Value(2UL),
  )
  assert_eq(
    mem.load_u32(map, pf),
    Ok(Float::reinterpret_as_uint(Float::from_double(1.5))),
  )
  assert_eq(mem.load_u64(map, plf), Ok(2.5.reinterpret_as_uint64()))
}

// ── sscanf ───────────────────────────────────────────────────────────────

///|
test "sscanf_mixed_and_no_guard_shape" {
  let (map, mem) = fresh()
  put_cstr(mem, map, 0x6800U, "123 45.67 word")
  put_cstr(mem, map, 0x6000U, "%d %lf %s")
  let pa = 0x8000U
  let pf = 0x8100U
  let ps = 0x8200U
  let r = host_sscanf(map, mem, 0x6800U, 0x6000U, [pa, pf, ps])
  assert_eq(r.value, Some(3UL))
  assert_eq(mem.load_u32(map, pa), Ok(123U))
  assert_eq(mem.load_u64(map, pf), Ok(45.67.reinterpret_as_uint64()))
  assert_eq(peek(mem, map, ps, 5), b"word\x00")
  // %c 与字面量
  put_cstr(mem, map, 0x6900U, "x7")
  put_cstr(mem, map, 0x6100U, "%c%d")
  let pc = 0x8300U
  let pd = 0x8400U
  let r2 = host_sscanf(map, mem, 0x6900U, 0x6100U, [pc, pd])
  assert_eq(r2.value, Some(2UL))
  assert_eq(mem.load_i8(map, pc), Ok(120))
  assert_eq(mem.load_u32(map, pd), Ok(7U))
}

///|
/// P1 修复锚（oracle release 真机 2026-09-23 取值）：`format_g` 的 10^e
/// 路径与 oracle `10f64.powi` 逐位对齐——含 exp 平局（e=23）、已知偏离
/// （e=126）、次正规（powi(-320..-323)）与 oracle 自身的泄漏形状
/// （DBL_TRUE_MIN：powi(-324)=0 → `infe-324`，两侧照搬同形）。
fn gf(lit : String, prec : Int) -> String {
  let v : Double = @string.parse_double(lit) catch { _ => 0.0 }
  format_g(v, prec, false)
}

///|
test "format_g_powi_oracle_alignment" {
  // e=23 精确平局：Rust powi 取上（非 half-even）→ oracle 输出 0.9999...e+23
  assert_eq(gf("1e23", 17), "0.9999999999999998e+23")
  // e=126 已知偏离（Rust std powi 1 ulp 高——显式锁定）
  assert_eq(gf("1e126", 17), "0.9999999999999999e+126")
  assert_eq(gf("1.5e126", 17), "1.5e+126")
  // 大指数与 DBL_MAX
  assert_eq(gf("1.2345678901234567e30", 17), "1.2345678901234567e+30")
  assert_eq(gf("1.7976931348623157e308", 17), "1.7976931348623157e+308")
  assert_eq(gf("9.999999999999999e29", 17), "0.9999999999999999e+30")
  assert_eq(gf("1e30", 17), "1e+30")
  // 次正规（powi(-320..-323) 非零）
  assert_eq(gf("8.8817841970012523e-320", 17), "8.8819169960474316e-320")
  assert_eq(gf("2.5e-323", 17), "2.5e-323")
  // DBL_TRUE_MIN：oracle 自身 powi(-324)=0 → inf 泄漏（照搬同形）
  assert_eq(gf("4.9406564584124654e-324", 17), "infe-324")
  // 默认精度出口
  assert_eq(gf("1e23", 6), "1e+23")
  assert_eq(gf("1.5e126", 6), "1.5e+126")
  // %.2f 大整数路径（format_fixed，bigint 精确——不受 powi 影响）
  assert_eq(gf("1e23", 0), "1e+23")
}

///|
/// powi10 直接锚：与 Rust std `powi` 的 633 个指数位模式逐位对齐
/// （-324..308；e=126 为已知偏离显式锁定）。
test "powi10_bit_alignment" {
  assert_eq(powi10(0), 1.0)
  assert_eq(powi10(22).reinterpret_as_uint64(), 0x4480f0cf064dd592UL)
  assert_eq(powi10(23).reinterpret_as_uint64(), 0x44b52d02c7e14af7UL)
  assert_eq(powi10(30).reinterpret_as_uint64(), 0x46293e5939a08ceaUL)
  assert_eq(powi10(126).reinterpret_as_uint64(), 0x5a17a2ecc414a040UL)
  assert_eq(powi10(308).reinterpret_as_uint64(), 0x7fe1ccf385ebc8a0UL)
  assert_eq(powi10(-320).reinterpret_as_uint64(), 0x7e8UL)
  assert_eq(powi10(-323).reinterpret_as_uint64(), 0x2UL)
  assert_eq(powi10(-324).reinterpret_as_uint64(), 0UL, msg="oracle 同值")
  assert_true(powi10(309).is_inf())
  assert_eq(powi10(-325).reinterpret_as_uint64(), 0UL)
}

///|
/// P3 修复锚：`%%` 双语义（P3 突变实证的盲区——此前全批零用例，
/// `parse_format_specs` 不跳 `%%` / 输出分支失效都不红）。
test "printf_percent_percent_semantics" {
  let (map, mem) = fresh()
  // **oracle 既有偏差（实测 2026-09-23，照搬）**：`%%` 展开带
  // `used < args.len()` 守卫——**实参耗尽后 %% 原样输出**（C 语义会展开）。
  // oracle 真机：printf("100%%") → "100%%"、printf("%d%%",42) → "42%%"
  let (log, r) = printf_run(map, mem, "100%%", [])
  assert_eq(r.trap, None)
  assert_eq(log.join(OutputKind::Stdout), b"100%%")
  let (log0, _) = printf_run(map, mem, "%d%%", [(42).to_uint64()])
  assert_eq(log0.join(OutputKind::Stdout), b"42%%")
  // 有实参剩余时 %% 正常展开（oracle 真机：a%%b%dc + 7 → "a%b7c"）
  let (loga, _) = printf_run(map, mem, "a%%b%dc", [(7).to_uint64()])
  assert_eq(loga.join(OutputKind::Stdout), b"a%b7c")
  // 零实参纯双百分号（oracle 真机已验：输出原样两字符）
  let (log2, _) = printf_run(map, mem, "%%", [])
  assert_eq(log2.join(OutputKind::Stdout), b"%%")
  // 注：`"x%"` 尾孤立 % 形状在 oracle typeck 层被拒（E3032：尾 %+字符计入
  // 说明符计数）——host 层行为见下（parity 由同构代码保证，无端到端真值）
  // 混合：%% 不干扰其余转换符的实参计数
  let (log3, r3) = printf_run(map, mem, "%d%%|%d", [
    (7).to_uint64(),
    (9).to_uint64(),
  ])
  assert_eq(r3.trap, None)
  assert_eq(log3.join(OutputKind::Stdout), b"7%|9")
  // 解析侧：规格序列只含真转换符（%% 不计）
  let specs = parse_format_specs([97, 37, 37, 98, 37, 100, 99])
  assert_eq(specs.length(), 1, msg="a%%b%dc 只有一个真转换符")
  assert_eq(specs[0], 100, msg="'d'")
  // 行尾孤立 %：原样输出（host 层；typeck 层另见 E3032 登记）
  let (log4, _) = printf_run(map, mem, "x%", [])
  assert_eq(log4.join(OutputKind::Stdout), b"x%")
}

///|
test "from_stdin_text_crlf_fully_normalized" {
  // **replace 首个匹配陷阱锚**（2026-09-29 stdin 34 例批实锤）：MoonBit
  // String::replace 只替换首个匹配——单次规整只消一个 CRLF，kr_1_19
  // 实测第二行起 \r 泄入程序（输出多 \r 分叉）。from_stdin_text 循环
  // 规整后全量：每行字节序列必须无 13（\r）
  let cr = Char::from_int(13).to_string()
  let nl = Char::from_int(10).to_string()
  let text = "hello" + cr + nl + "world" + cr + nl + "tail" + cr + nl
  let st = InputState::from_stdin_text(text, true)
  assert_eq(st.lines.length(), 3)
  for l in st.lines {
    for i = 0; i < l.length(); i = i + 1 {
      assert_not_eq(
        l[i].to_int(),
        13,
        msg="行内不得残留 \r（全量规整）",
      )
    }
  }
  // 末行无换行原样 + 空串零行（既有语义回归位）
  let st2 = InputState::from_stdin_text("ab" + cr + nl + "cd", true)
  assert_eq(st2.lines.length(), 2)
  assert_eq(st2.lines[0].length(), 3, msg="ab\n（3 字节）")
  assert_eq(st2.lines[1].length(), 2, msg="cd 原样（末行无换行）")
  assert_true(InputState::from_stdin_text("", true).lines.is_empty())
}

// ── Host Contract 补锚段续（2026-10-04）：scanf 实参不足（B43）——
// oracle host_contract_tests.rs:1394 断言照搬（mb 侧守卫在 ptrs 长度判定，
// host_io.mbt:565——行为在、锚缺）。

///|
test "scanf_n_rejects_insufficient_args" {
  let (map, mem) = fresh()
  put_cstr(mem, map, 0x2000U, "%d %d")
  // fmt 要求 2 个目标指针，ptrs 只给 1 个——必须 Trap 且文案点名
  let r = host_scanf_n(map, mem, InputState::new([], true), [], 0x2000U, [
    0x3000U,
  ])
  guard r is InputOutcome::Trap(t) else { fail("实参不足必须 Trap") }
  assert_true(
    t.contains("参数多于实际提供的参数"),
    msg="文案与 oracle 同形（B43）",
  )
}

///|
test "printf_zero_pad_sign_prefix_and_float_flags" {
  // 审阅 P2-a 锚（2026-10-06）：零填充符号前置（C +0003/-0003——旧
  // 000+3）+ 浮点臂 +/空格旗标（旧只传 d/i 臂）
  let (map, mem) = fresh()
  let (log, _) = printf_run(map, mem, "[ %+05d ][ %05d ][ %05.1f ]", [
    (3).to_uint64(),
    (-3).to_uint64(),
    (-3.5).reinterpret_as_uint64(),
  ])
  assert_eq(log.join(OutputKind::Stdout), b"[ +0003 ][ -0003 ][ -03.5 ]")
  let (map2, mem2) = fresh()
  let (log2, _) = printf_run(map2, mem2, "[%+f][% g][%+g]", [
    3.5.reinterpret_as_uint64(),
    3.5.reinterpret_as_uint64(),
    3.5.reinterpret_as_uint64(),
  ])
  inspect(log2.join(OutputKind::Stdout), content="b\"[+3.500000][ 3.5][+3.5]\"")
}
