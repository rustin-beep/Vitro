///| S6 宿主函数域**黑盒契约**（`vitro/engine/host` 的对外面）。
///
/// 黑盒 = 包外消费者视角（下一个消费者是 `vm` 的执行器与 session 的输出出口）。
/// 本文件同时承担对外面消费面（喂 `moonbit_surface -check`）——本包每个 pub
/// 符号都在这里以 `@host.` 形式被点名（闸门是文本 grep：**裸名不计消费**）。
///
/// 与白盒的分工：`host_memory_wbtest.mbt` / `output_wbtest.mbt` 锁**语义细节**
/// （含两条 oracle 缺陷固化锚）；本文件锁**接口够不够用**——即"只拿 pub 面
/// 能否完成一次完整的 malloc→写→free→诊断循环"，以及输出通道能否给出
/// stdout 比对所需的纯净字节流。

///|
/// 输出通道的公开常量与三通道分流（Shadow 比对合法性）。
test "output_surface_split" {
  assert_eq(@host.OUTPUT_LOG_BUDGET, 16 * 1024 * 1024)
  assert_eq(@host.MERGE_THRESHOLD, 64)
  assert_eq(@host.MERGE_LIMIT, 4096)
  let log : @host.OutputLog = @host.OutputLog::new()
  assert_eq(log.budget(), @host.OUTPUT_LOG_BUDGET)
  log.push_stdout(b"program output\n")
  log.push_stderr(b"err\n")
  log.push_note_str("[引擎] 附注")
  assert_eq(
    log.join(@host.OutputKind::Stdout),
    b"program output\n",
    msg="stdout 是 Clang 比对的唯一合法来源",
  )
  assert_eq(log.join(@host.OutputKind::Stderr), b"err\n")
  assert_eq(log.join(@host.OutputKind::Note), b"[引擎] 附注\n")
  assert_eq(log.len_of(@host.OutputKind::Stdout), 15)
  assert_eq(
    log.total_bytes(),
    15 + 4 + 16,
    msg="stdout 15 + stderr 4 + 附注 15 + 补的 \\n",
  )
  assert_eq(log.dropped_bytes(), 0)
  assert_true(log.is_empty() == false)
  // 带通道标记的交错视图（`OutputChunk` 是它的元素类型）
  let chunks : Array[@host.OutputChunk] = log.chunk_list()
  assert_eq(chunks.length(), 3)
  assert_eq(chunks[0].kind, @host.OutputKind::Stdout)
  assert_eq(chunks[0].bytes, b"program output\n")
  assert_eq(chunks[2].kind, @host.OutputKind::Note)
  // 通道标识往返
  assert_eq(@host.OutputKind::Stdout.as_str(), "stdout")
  guard @host.OutputKind::parse("note") is Some(@host.OutputKind::Note) else {
    fail("parse note")
  }
  log.clear()
  assert_true(log.is_empty())
}

///|
/// 内存族的公开接口：`HostMemReply` 三件（value / note / trap）足以表达
/// handler 的全部副作用，且**不需要 VM**。
test "host_memory_reply_surface" {
  let map = @memory.MemoryMap::new()
  let mem = @memory.Memory::new()
  // 分配 → 写 → 释放：全程只用 pub 面
  let r : @host.HostMemReply = @host.host_malloc(map, 32, 12)
  let p = match r.value {
    Some(a) => a.to_uint()
    None => fail("malloc 必须返回值")
  }
  assert_eq(r.note, None)
  assert_eq(r.trap, None)
  guard mem.store_i8(map, p, 42) is Ok(_) else { fail("受检写必须成功") }
  match mem.load_i8(map, p) {
    Ok(v) => assert_eq(v, 42)
    Err(_) => fail("受检读必须成功")
  }
  let f : @host.HostMemReply = @host.host_free(map, p, 13, 99)
  assert_eq(f.value, None, msg="free 无返回值")
  assert_eq(f.trap, None)
  // 二次释放：结构化 trap 文本
  let d : @host.HostMemReply = @host.host_free(map, p, 14, 100)
  guard d.trap is Some(t) else { fail("双释放必须给 trap 文本") }
  assert_true(t.contains("E3061"))
}

///|
/// 引擎附注与诊断文案是**纯文本出口**（调用方决定写哪条通道、是否去重）。
test "text_exports_and_dedup" {
  let exhausted : String = @host.heap_exhausted_note()
  assert_true(exhausted.contains("内存耗尽"))
  assert_true(exhausted.has_suffix("\n"))
  let zero : String = @host.malloc_zero_note()
  assert_true(zero.contains("malloc(0)"))
  // 去重口径：同一段附注第二次不得重复写（Rust 的 O(n) contains 去重）
  let log = @host.OutputLog::new()
  log.push_note_str(exhausted)
  assert_true(log.has_note(@utf8.encode(exhausted)))
  assert_false(log.has_note(@utf8.encode("另一条附注")))
  // 诊断文案：Double-Free / 无效 free 由 host 出口，vm 只负责加行号后缀
  let map = @memory.MemoryMap::new()
  let p = @host.host_malloc(map, 8, 3).value.unwrap().to_uint()
  ignore(@host.host_free(map, p, 4, 4))
  guard map.freed_logs_get(p) is Some(info) else { fail("窗口必须登记") }
  let msg = @host.double_free_message(info)
  assert_true(msg.contains("E3061"))
  assert_true(msg.contains("第 4 行"))
  let bad = @host.invalid_free_message(map, 0xA000U)
  assert_true(bad.contains("E3027"))
  // calloc / realloc 也在同一接口内
  let c = @host.host_calloc(map, @memory.Memory::new(), 1, 8, 5)
  assert_true(c.trap is None)
  let rr = @host.host_realloc(
    map,
    @memory.Memory::new(),
    c.value.unwrap().to_uint(),
    16,
    6,
    6,
    6,
  )
  assert_true(rr.value is Some(_))
}

///|
/// 余量批一号·各族公开面点名（接口够不够用 + 对外面消费面喂闸——裸名不计
/// 消费，见文件头注）。合法值锚定在白盒；此处每符号至少一次 `@host.` 调用。
test "host_ctype_math_surface" {
  // ctype 14
  assert_eq(@host.host_isdigit(50), 1)
  assert_eq(@host.host_isalpha(97), 1)
  assert_eq(@host.host_islower(98), 1)
  assert_eq(@host.host_isupper(66), 1)
  assert_eq(@host.host_tolower(66), 98)
  assert_eq(@host.host_toupper(98), 66)
  assert_eq(@host.host_isspace(10), 1)
  assert_eq(@host.host_isalnum(51), 1)
  assert_eq(@host.host_isprint(65), 1)
  assert_eq(@host.host_iscntrl(7), 1)
  assert_eq(@host.host_isxdigit(97), 1)
  assert_eq(@host.host_isgraph(33), 1)
  assert_eq(@host.host_ispunct(44), 1)
  assert_eq(@host.host_isblank(9), 1)
  // math 22（位模式进出）
  assert_eq(@host.host_abs(-9), 9UL)
  assert_eq(@host.host_llabs(-9L), 9UL)
  assert_true(@host.host_sin(0UL) == 0UL)
  assert_true(@host.host_cos(0UL) == 1.0.reinterpret_as_uint64())
  assert_true(
    @host.host_sqrt(9.0.reinterpret_as_uint64()) == 3.0.reinterpret_as_uint64(),
  )
  assert_true(
    @host.host_pow(3.0.reinterpret_as_uint64(), 2.0.reinterpret_as_uint64()) ==
    9.0.reinterpret_as_uint64(),
  )
  assert_true(@host.host_atan(0UL) == 0UL)
  assert_true(@host.host_log(1.0.reinterpret_as_uint64()) == 0UL)
  assert_true(@host.host_exp(0UL) == 1.0.reinterpret_as_uint64())
  assert_true(@host.host_tan(0UL) == 0UL)
  assert_true(
    @host.host_log10(100.0.reinterpret_as_uint64()) ==
    2.0.reinterpret_as_uint64(),
  )
  assert_true(
    @host.host_fabs((-1.0).reinterpret_as_uint64()) ==
    1.0.reinterpret_as_uint64(),
  )
  assert_true(
    @host.host_ceil(0.1.reinterpret_as_uint64()) == 1.0.reinterpret_as_uint64(),
  )
  assert_true(@host.host_floor(0.9.reinterpret_as_uint64()) == 0UL)
  assert_true(
    @host.host_round(0.5.reinterpret_as_uint64()) == 1.0.reinterpret_as_uint64(),
  )
  assert_true(
    @host.host_fmod(5.0.reinterpret_as_uint64(), 2.0.reinterpret_as_uint64()) ==
    1.0.reinterpret_as_uint64(),
  )
  assert_true(@host.host_asin(0UL) == 0UL)
  assert_true(@host.host_acos(1.0.reinterpret_as_uint64()) == 0UL)
  assert_true(@host.host_atan2(0UL, 1.0.reinterpret_as_uint64()) == 0UL)
  assert_true(@host.host_sinh(0UL) == 0UL)
  assert_true(@host.host_cosh(0UL) == 1.0.reinterpret_as_uint64())
  assert_true(@host.host_tanh(0UL) == 0UL)
}

///|
/// 字符串族 19 的公开面（一图流：setup 一次，逐 handler 走最小调用）。
test "host_string_surface" {
  let map = @memory.MemoryMap::new()
  let mem = @memory.Memory::new()
  ignore(mem.write_bytes(map, 0x6000U, b"hello\x00"))
  ignore(mem.write_bytes(map, 0x6100U, b"lo\x00"))
  let span : @host.StackBufferSpan = @host.StackBufferSpan::{
    base: 0x8000U,
    size: 64,
    name: "buf",
  }
  assert_true(@host.host_strlen(mem, map, 0x6000U).value is Some(5UL))
  assert_true(@host.host_strdup(map, mem, 0x6000U, 1).value is Some(_))
  assert_true(
    @host.host_strcpy(map, mem, 0x7000U, 0x6000U, [span]).value
    is Some(0x7000UL),
  )
  assert_true(@host.host_strcmp(mem, map, 0x6000U, 0x6000U).value is Some(0UL))
  assert_true(
    @host.host_memset(map, mem, 0x6200U, 0x5AUL, 3UL).value is Some(0x6200UL),
  )
  assert_true(
    @host.host_strcat(map, mem, 0x7000U, 0x6100U, [span]).value
    is Some(0x7000UL),
  )
  assert_true(
    @host.host_strncpy(map, mem, 0x7100U, 0x6000U, 3).value is Some(0x7100UL),
  )
  assert_true(
    @host.host_memcpy(map, mem, 0x7200U, 0x6000U, 3).value is Some(0x7200UL),
  )
  assert_true(
    @host.host_memmove(map, mem, 0x7300U, 0x6000U, 3).value is Some(0x7300UL),
  )
  assert_true(
    @host.host_strncat(map, mem, 0x7400U, 0x6100U, 1UL).value is Some(0x7400UL),
  )
  assert_true(
    @host.host_strncmp(mem, map, 0x6000U, 0x6000U, 2UL).value is Some(0UL),
  )
  assert_true(
    @host.host_memcmp(mem, map, 0x6000U, 0x6000U, 3UL).value is Some(0UL),
  )
  assert_true(@host.host_strchr(mem, map, 0x6000U, 101).value is Some(0x6001UL))
  assert_true(
    @host.host_strrchr(mem, map, 0x6000U, 108).value is Some(0x6003UL),
  )
  assert_true(
    @host.host_strstr(mem, map, 0x6000U, 0x6100U).value is Some(0x6003UL),
  )
  assert_true(
    @host.host_memchr(mem, map, 0x6000U, 108, 8UL).value is Some(0x6002UL),
  )
  assert_true(
    @host.host_strpbrk(mem, map, 0x6000U, 0x6100U).value is Some(0x6002UL),
  )
  assert_true(@host.host_strspn(mem, map, 0x6000U, 0x6100U).value is Some(0UL))
  assert_true(@host.host_strcspn(mem, map, 0x6000U, 0x6100U).value is Some(2UL))
}

///|
/// 转数值 + 杂项族的公开面。
test "host_convert_misc_surface" {
  let map = @memory.MemoryMap::new()
  let mem = @memory.Memory::new()
  ignore(mem.write_bytes(map, 0x6000U, b"123\x00"))
  assert_true(@host.host_atoi(mem, map, 0x6000U).value is Some(123UL))
  assert_true(@host.host_atol(mem, map, 0x6000U).value is Some(123UL))
  assert_eq(
    @host.host_atof(mem, map, 0x6000U).value,
    Some(123.0.reinterpret_as_uint64()),
  )
  assert_true(
    @host.host_strtol(mem, map, 0x6000U, 0U, 10, None).value is Some(123UL),
  )
  assert_eq(
    @host.host_strtod(mem, map, 0x6000U, 0U, None).value,
    Some(123.0.reinterpret_as_uint64()),
  )
  assert_true(@host.host_strerror(map, mem, 1, 1).value is Some(_))
  // 杂项：LCG / 确定性时钟 / unreachable / va_*
  let st : @host.RandState = @host.RandState::new(42U)
  ignore(@host.host_rand(st))
  @host.host_srand(st, 7U)
  assert_eq(@host.host_time(true, 0UL), 0UL)
  assert_eq(@host.host_clock(false, 2UL), 2000UL)
  assert_true(@host.host_unreachable().contains("unreachable"))
  ignore(mem.write_bytes(map, 0x7000U, b"\x00\x00\x00\x00"))
  assert_true(@host.host_va_start(mem, map, 0x7000U, 0x7000, 4).value is None)
  assert_true(@host.host_va_arg(mem, map, 0x7000U, 4).value is Some(_))
  assert_true(@host.host_va_copy(mem, map, 0x7100U, 0x7000U).value is None)
  assert_true(@host.host_va_end(0x7000U).value is None)
}

///|
/// 余量批二号·printf/scanf/IO 族公开面点名。
test "host_io_surface" {
  let map = @memory.MemoryMap::new()
  let mem = @memory.Memory::new()
  ignore(mem.write_bytes(map, 0x6000U, b"n=%d\x00"))
  let log : @host.OutputLog = @host.OutputLog::new()
  // printf 族 6 个 + 输出通道
  let r : @host.HostMemReply = @host.host_printf_n(map, mem, log, 0x6000U, [
    (42).to_uint64(),
  ])
  assert_eq(log.join(@host.OutputKind::Stdout), b"n=42")
  assert_true(r.value is None)
  let r2 = @host.host_fprintf_n(map, mem, log, 2UL, 0x6000U, [])
  assert_true(r2.value is None)
  let buf = 0x7000U
  assert_true(
    @host.host_sprintf(map, mem, buf, 0x6000U, [(7).to_uint64()]).value
    is Some(3UL),
  )
  assert_true(
    @host.host_snprintf(map, mem, buf, 3, 0x6000U, [(7).to_uint64()]).value
    is Some(3UL),
  )
  assert_true(@host.host_puts(map, mem, log, 0x6000U).value is Some(1UL))
  @host.host_putchar(log, 65UL)
  // 输入族 3 个 + 状态类型
  let input : @host.InputState = @host.InputState::new([b"1 2"], true)
  let oc : @host.InputOutcome = @host.host_getchar(input)
  guard oc is @host.InputOutcome::Value(49UL) else { fail("getchar 读 '1'") }
  ignore(@host.host_ungetc(input, 97))
  ignore(mem.write_bytes(map, 0x6100U, b"%d\x00"))
  let pa = 0x8000U
  let sc = @host.host_scanf_n(map, mem, input, [], 0x6100U, [pa])
  guard sc is @host.InputOutcome::Value(1UL) else { fail("scanf 匹配 1 项") }
  ignore(mem.write_bytes(map, 0x6800U, b"5\x00"))
  ignore(mem.write_bytes(map, 0x6200U, b"%d\x00"))
  let ss = @host.host_sscanf(map, mem, 0x6800U, 0x6200U, [pa])
  assert_true(ss.value is Some(1UL))
}

///|
/// 余量批三号·VFS 公开面点名（含 17 handler 与 VirtualFileSystem 方法族）。
test "host_vfs_surface" {
  let map = @memory.MemoryMap::new()
  let mem = @memory.Memory::new()
  let vfs : @host.VirtualFileSystem = @host.VirtualFileSystem::new()
  assert_true(
    @host.VirtualFileSystem::inject_preset_file(vfs, map, mem, "s.txt", b"ab"),
  )
  assert_eq(@host.VirtualFileSystem::get_file_name(vfs, 99U), None)
  let log : @host.OutputLog = @host.OutputLog::new()
  // 名称串落内存
  ignore(mem.write_bytes(map, 0x6000U, b"s.txt\x00"))
  ignore(mem.write_bytes(map, 0x6100U, b"r\x00"))
  ignore(mem.write_bytes(map, 0x6200U, b"w\x00"))
  ignore(mem.write_bytes(map, 0x6300U, b"a\x00"))
  // fopen（读）→ FILE*
  let fp = @host.host_fopen(map, mem, vfs, 0x6000U, 0x6100U, 1).value
    .unwrap()
    .to_uint()
  assert_true(fp != 0U)
  // fread / fgets / fgetc / feof / fseek / ftell / rewind
  assert_true(
    @host.host_fread(map, mem, vfs, 0x8000U, 1, 10, fp).value is Some(2UL),
  )
  ignore(@host.host_fseek(map, mem, vfs, fp, 0, 0))
  assert_true(@host.host_ftell(map, mem, vfs, fp).value is Some(0UL))
  assert_true(
    @host.host_fgets(map, mem, vfs, 0x8100U, 10, fp).value is Some(0x8100UL),
  )
  assert_true(
    @host.host_fgetc(map, mem, vfs, fp).value is Some(0xFFFFFFFFFFFFFFFFUL),
  )
  assert_true(@host.host_feof(map, mem, vfs, fp).value is Some(_))
  ignore(@host.host_rewind(map, mem, vfs, fp))
  ignore(@host.host_clearerr(map, mem, vfs, fp))
  assert_true(@host.host_fflush(map, mem, vfs, fp).value is Some(0UL))
  // 写族：非法模式串 → NULL
  ignore(mem.write_bytes(map, 0x6A00U, b"zz\x00"))
  assert_eq(
    @host.host_fopen(map, mem, vfs, 0x6200U, 0x6A00U, 2).value,
    Some(0UL),
  )
  ignore(mem.write_bytes(map, 0x6400U, b"wb\x00"))
  let fw2 = @host.host_fopen(map, mem, vfs, 0x6200U, 0x6400U, 3).value
    .unwrap()
    .to_uint()
  assert_true(fw2 != 0U)
  ignore(mem.write_bytes(map, 0x6500U, b"XY"))
  assert_true(
    @host.host_fwrite(map, mem, vfs, 0x6500U, 1, 2, fw2).value is Some(2UL),
  )
  assert_true(@host.host_fputc(map, mem, vfs, 90, fw2).value is Some(90UL))
  ignore(mem.write_bytes(map, 0x6600U, b"Q\x00"))
  assert_true(
    @host.host_fputs(map, mem, vfs, log, 0x6600U, fw2).value is Some(0UL),
  )
  // append（坑 13）
  ignore(mem.write_bytes(map, 0x6700U, b"wb\x00"))
  assert_true(
    @host.host_fopen(map, mem, vfs, 0x6300U, 0x6400U, 4).value is Some(_),
  )
  // fclose 两个
  assert_true(@host.host_fclose(map, mem, vfs, fp, 5, 5).value is Some(0UL))
  assert_true(@host.host_fclose(map, mem, vfs, fw2, 6, 6).value is Some(0UL))
  // perror / remove / rename
  ignore(mem.write_bytes(map, 0x6800U, b"pfx\x00"))
  assert_true(@host.host_perror(map, mem, log, 0x6800U).value is None)
  assert_true(@host.host_remove(map, mem, vfs, 0x6000U).value is Some(0UL))
  assert_true(
    @host.host_rename(map, mem, vfs, 0x6000U, 0x6900U).value
    is Some(0xFFFFFFFFFFFFFFFFUL),
  )
}
