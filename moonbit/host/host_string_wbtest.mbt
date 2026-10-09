///| S6 host 余量批一号·字符串族白盒锚点。
///
/// 锚定三档：① 合法输入下与 oracle 逐字节一致（值/返回指针/内存副作用）；
/// ② **登记分叉锚**——读侧受检化的教学 trap（oracle 静默形状：`strlen(NULL)`
/// 返 0、UAF 读内容、memset/memcpy 写已释放块无检——坑 16/18、U5#1）；
/// ③ oracle 特有形状照搬（`memset` 超长截断、`strncpy` 负 `n` 补零到尾、
/// `strchr` 无符号字节匹配、E3070 双重校验文案）。

///|
/// 在 `addr` 写入 C 字符串（`s` 不含 NUL，自动补终止符；受检写，测试地址
/// 须在 NULL 区之上）。
fn put_cstr(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  addr : UInt,
  s : String,
) -> Unit raise {
  put_bytes(mem, map, addr, @utf8.encode(s), true)
}

///|
/// 写原始字节（可选补 NUL）。
fn put_bytes(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  addr : UInt,
  data : Bytes,
  nul : Bool,
) -> Unit raise {
  let arr : Array[Byte] = []
  let n = data.length()
  let mut i = 0
  while i < n {
    arr.push(data[i])
    i = i + 1
  }
  if nul {
    arr.push(b'\x00')
  }
  match mem.write_bytes(map, addr, Bytes::from_array(arr)) {
    Ok(_) => ()
    Err(_) => fail("测试写入失败（地址 \{addr}）")
  }
}

///|
/// 读回 `n` 字节。
fn peek(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  addr : UInt,
  n : Int,
) -> Bytes raise {
  let arr : Array[Byte] = []
  let mut i = 0
  while i < n {
    match mem.load_i8(map, addr + i.reinterpret_as_uint()) {
      Ok(v) => arr.push(v.to_byte())
      Err(_) => fail("测试读取失败")
    }
    i = i + 1
  }
  Bytes::from_array(arr)
}

///|
/// `strlen`：合法输入逐字节一致。
test "strlen_counts_until_nul" {
  let (map, mem) = fresh()
  put_cstr(mem, map, 0x6000U, "hello")
  let r = host_strlen(mem, map, 0x6000U)
  assert_eq(r.value, Some(5UL))
  assert_eq(r.trap, None)
}

///|
/// 登记分叉锚：oracle `strlen(NULL)` 静默 0（坑 16），此处 NULL trap。
test "strlen_null_traps_divergence" {
  let (map, mem) = fresh()
  let r = host_strlen(mem, map, 9U)
  guard r.trap is Some(t) else { fail("NULL 读必须 trap") }
  assert_true(t.contains("NULL"))
  assert_eq(r.value, None)
}

///|
/// 登记分叉锚：oracle 读已释放块静默返回内容，此处 E3060。
test "uaf_read_traps_divergence" {
  let (map, mem) = fresh()
  let p = host_malloc(map, 8, 1).value.unwrap().to_uint()
  put_cstr(mem, map, p, "abc")
  ignore(host_free(map, p, 2, 2))
  let r = host_strlen(mem, map, p)
  guard r.trap is Some(t) else { fail("UAF 读必须 trap") }
  assert_true(t.contains("E3060"))
}

///|
/// `strdup`：内容往返 + 区域登记（alloc_by）。
test "strdup_roundtrip_and_region" {
  let (map, mem) = fresh()
  put_cstr(mem, map, 0x6000U, "vitro")
  let r = host_strdup(map, mem, 0x6000U, 7)
  let a = r.value.unwrap().to_uint()
  assert_eq(r.trap, None)
  assert_eq(peek(mem, map, a, 6), b"vitro\x00")
  guard map.region(a) is Some(rec) else { fail("必须登记区域") }
  assert_eq(rec.alloc_by, "strdup")
  assert_eq(rec.size, 6)
}

///|
/// `strcpy`：拷贝 + 终止符 + 返回 dest。
test "strcpy_copies_and_returns_dest" {
  let (map, mem) = fresh()
  put_cstr(mem, map, 0x6000U, "abc")
  let r = host_strcpy(map, mem, 0x7000U, 0x6000U, [])
  assert_eq(r.value, Some(0x7000UL))
  assert_eq(peek(mem, map, 0x7000U, 4), b"abc\x00")
}

///|
/// `strcpy` E3070：堆块容量不足（源 8 字节 + 终止符 > malloc(8) 起剩 8）。
test "strcpy_heap_overflow_e3070" {
  let (map, mem) = fresh()
  let buf = host_malloc(map, 8, 3).value.unwrap().to_uint()
  put_cstr(mem, map, 0x6000U, "12345678") // 8 字节 + NUL = 9 > 8
  let r = host_strcpy(map, mem, buf, 0x6000U, [])
  guard r.trap is Some(t) else { fail("堆溢出必须 E3070") }
  assert_true(t.contains("E3070"))
  assert_true(t.contains("strcpy 目标缓冲区溢出"))
  assert_true(t.contains("源字符串长度 8 字节"))
}

///|
/// `strcpy` V-P1-6：栈缓冲容量不足（dest 落栈缓冲内、余量不足）。
test "strcpy_stack_buffer_overflow_e3070" {
  let (map, mem) = fresh()
  let span = StackBufferSpan::{ base: 0x8000U, size: 4, name: "buf", }
  put_cstr(mem, map, 0x6000U, "abcdef") // 7 > 4
  let r = host_strcpy(map, mem, 0x8000U + 1U, 0x6000U, [span])
  guard r.trap is Some(t) else { fail("栈溢出必须 E3070") }
  assert_true(t.contains("栈上缓冲区 'buf' 溢出"))
  assert_true(t.contains("需要写入 7 字节"))
}

///|
/// `strcmp`：相等 0；不等**有符号字节差符号扩展**（-1 → 全 1 位模式）；
/// 高位字节（0x80 = -128）按有符号比较。
test "strcmp_diff_sign_extended" {
  let (map, mem) = fresh()
  put_cstr(mem, map, 0x6000U, "abc")
  put_cstr(mem, map, 0x6100U, "abd")
  assert_eq(
    host_strcmp(mem, map, 0x6000U, 0x6100U).value,
    Some(0xFFFFFFFFFFFFFFFFUL),
    msg="'c'-'d' = -1 符号扩展",
  )
  assert_eq(host_strcmp(mem, map, 0x6000U, 0x6000U).value, Some(0UL))
  put_bytes(mem, map, 0x6200U, b"\x80\x00", false)
  put_bytes(mem, map, 0x6300U, b"\x7F\x00", false)
  assert_eq(
    host_strcmp(mem, map, 0x6200U, 0x6300U).value,
    Some(0xFFFFFFFFFFFFFF01UL),
    msg="-128 - 127 = -255 符号扩展",
  )
}

///|
/// `memset`：填充 + 返回 ptr；value 取低 8 位。
test "memset_fills_and_returns_ptr" {
  let (map, mem) = fresh()
  let r = host_memset(map, mem, 0x6000U, 0x41UL, 4UL)
  assert_eq(r.value, Some(0x6000UL))
  assert_eq(peek(mem, map, 0x6000U, 4), b"AAAA")
  // 低 8 位截断（0x141 → 'A'）
  let r2 = host_memset(map, mem, 0x6100U, 0x141UL, 2UL)
  assert_eq(r2.value, Some(0x6100UL))
  assert_eq(peek(mem, map, 0x6100U, 2), b"AA")
}

///|
/// `memset` NULL trap：oracle 专属文案 + `0x{:04X}` 四位补零。
test "memset_null_trap_hex04_message" {
  let (map, mem) = fresh()
  let r = host_memset(map, mem, 9U, 0UL, 4UL)
  guard r.trap is Some(t) else { fail("NULL 写必须 trap") }
  assert_true(t.contains("向 NULL 指针区域写入（地址 0x0009）"))
}

///|
/// `memset` 超长照搬截断：填到内存尾、不 fault、返回 ptr。
test "memset_oversize_clamps_to_memory_end" {
  let (map, mem) = fresh()
  let near_end = @bytecode.MEM_SIZE - 4U
  let r = host_memset(map, mem, near_end, 0x5AUL, 0xFFFFFFFFFFFFFFFFUL)
  assert_eq(r.value, Some(near_end.to_uint64()))
  assert_eq(r.trap, None)
  assert_eq(peek(mem, map, near_end, 4), b"ZZZZ")
}

///|
/// 登记分叉锚：oracle memset 裸写无 UAF（U5#1），此处 E3060。
test "memset_freed_region_traps_uaf_divergence" {
  let (map, mem) = fresh()
  let p = host_malloc(map, 8, 1).value.unwrap().to_uint()
  ignore(host_free(map, p, 2, 2))
  let r = host_memset(map, mem, p, 0UL, 4UL)
  guard r.trap is Some(t) else { fail("UAF 写必须 trap") }
  assert_true(t.contains("E3060"))
}

///|
/// `strcat`：追加 + E3070（已有 + 源 + 终止符）。
test "strcat_appends_and_e3070" {
  let (map, mem) = fresh()
  put_cstr(mem, map, 0x6000U, "ab")
  put_cstr(mem, map, 0x6100U, "cd")
  let r = host_strcat(map, mem, 0x6000U, 0x6100U, [])
  assert_eq(r.value, Some(0x6000UL))
  assert_eq(peek(mem, map, 0x6000U, 5), b"abcd\x00")
  // 堆块 4 字节：已有 2 + 源 2 + 1 = 5 > 4 → E3070
  let buf = host_malloc(map, 4, 3).value.unwrap().to_uint()
  put_cstr(mem, map, buf, "ab")
  let r2 = host_strcat(map, mem, buf, 0x6100U, [])
  guard r2.trap is Some(t) else { fail("strcat 堆溢出必须 E3070") }
  assert_true(
    t.contains(
      "已有 2 字节 + 源字符串 2 字节 + 终止符 1 字节 = 5 字节",
    ),
  )
}

///|
/// `strncpy`：截断拷贝不补零？不——**源更长时截到 n，源更短时补零到 n**；
/// 负 `n` 补零到内存尾（U5#3 缺陷形状照搬）。
test "strncpy_pads_and_negative_n_fills_tail" {
  let (map, mem) = fresh()
  put_cstr(mem, map, 0x6000U, "ab")
  // 源短补零：n=4 → "ab\0\0"
  let r = host_strncpy(map, mem, 0x7000U, 0x6000U, 4)
  assert_eq(r.value, Some(0x7000UL))
  assert_eq(peek(mem, map, 0x7000U, 4), b"ab\x00\x00")
  // 负 n → 越界写 trap（DIFF-LIB-STRNCPY-01 销案翻转 2026-10-05 批二-b：
  // 旧「补零到内存尾」软夹紧系 oracle 照搬；Clang 同形态 segfault 实证）
  let r2 = host_strncpy(map, mem, 0x7000U, 0x6000U, -1)
  assert_true(r2.trap is Some(_), msg="负 n 必须 trap 非软夹紧")
}

///|
/// `memcpy`/`memmove`：重叠安全（memmove 语义）+ 越界截断。
test "memcpy_memmove_overlap_safe" {
  let (map, mem) = fresh()
  put_bytes(mem, map, 0x6000U, b"abcdef", false)
  // 前向重叠：dest = src + 2, n = 4 → "ab"+"abcd"
  let r = host_memmove(map, mem, 0x6002U, 0x6000U, 4)
  assert_eq(r.value, Some(0x6002UL))
  assert_eq(peek(mem, map, 0x6000U, 6), b"ababcd")
  // memcpy 同实现（oracle 两函数同型）
  put_bytes(mem, map, 0x6100U, b"abcdef", false)
  let r2 = host_memcpy(map, mem, 0x6102U, 0x6100U, 4)
  assert_eq(r2.value, Some(0x6102UL))
  assert_eq(peek(mem, map, 0x6100U, 6), b"ababcd")
  // 越界截断：n 超剩余 → 拷到尾、不 fault
  let near_end = @bytecode.MEM_SIZE - 3U
  let r3 = host_memcpy(map, mem, near_end, 0x6100U, 100)
  assert_eq(r3.value, Some(near_end.to_uint64()))
  assert_eq(r3.trap, None)
}

///|
/// `strncat`：至多 n 字节 + 终止符；`n` 是原始 u64 栈字。
test "strncat_limits_n" {
  let (map, mem) = fresh()
  put_cstr(mem, map, 0x6000U, "ab")
  put_cstr(mem, map, 0x6100U, "cdef")
  let r = host_strncat(map, mem, 0x6000U, 0x6100U, 2UL)
  assert_eq(r.value, Some(0x6000UL))
  assert_eq(peek(mem, map, 0x6000U, 5), b"abcd\x00")
}

///|
/// `strncmp`：前缀相等按 n 截断；`memcmp` 不因 NUL 停。
test "strncmp_and_memcmp" {
  let (map, mem) = fresh()
  put_cstr(mem, map, 0x6000U, "abc")
  put_cstr(mem, map, 0x6100U, "abd")
  // n=2 前缀相等 → 0
  assert_eq(host_strncmp(mem, map, 0x6000U, 0x6100U, 2UL).value, Some(0UL))
  // n=3 → 'c'-'d' = -1
  assert_eq(
    host_strncmp(mem, map, 0x6000U, 0x6100U, 3UL).value,
    Some(0xFFFFFFFFFFFFFFFFUL),
  )
  // memcmp 跨 NUL：第 3 字节 differ（'x'-'y' = -1）
  put_bytes(mem, map, 0x6200U, b"a\x00x", false)
  put_bytes(mem, map, 0x6300U, b"a\x00y", false)
  assert_eq(
    host_memcmp(mem, map, 0x6200U, 0x6300U, 3UL).value,
    Some(0xFFFFFFFFFFFFFFFFUL),
  )
  assert_eq(host_memcmp(mem, map, 0x6200U, 0x6200U, 3UL).value, Some(0UL))
}

///|
/// `strchr`：命中/未命中/`c == 0` 命中终止符/无符号字节匹配（c=200 命中
/// 0xC8；负 c 按 C11 §7.24.5.2 char 截断语义命中——病 1 修复随锚翻转，
/// #47 2026-10-09，旧「恒不中」系 oracle 病行为的固化锚）。
test "strchr_unsigned_byte_match" {
  let (map, mem) = fresh()
  put_cstr(mem, map, 0x6000U, "abc")
  assert_eq(
    host_strchr(mem, map, 0x6000U, 98).value,
    Some(0x6001UL),
    msg="'b' 在偏移 1",
  )
  assert_eq(host_strchr(mem, map, 0x6000U, 122).value, Some(0UL))
  // c = 0 命中终止符（偏移 3）
  assert_eq(host_strchr(mem, map, 0x6000U, 0).value, Some(0x6003UL))
  // 无符号匹配：字节 0xC8 ↔ c = 200
  put_bytes(mem, map, 0x6100U, b"\xC8\x00", false)
  assert_eq(host_strchr(mem, map, 0x6100U, 200).value, Some(0x6100UL))
  // 负 c（-56 ≡ 0xC8）：char 截断语义命中（病 1 翻转锚——Clang 对拍同值）
  assert_eq(host_strchr(mem, map, 0x6100U, -56).value, Some(0x6100UL))
}

///|
/// `strrchr`：最后一次命中。
test "strrchr_last_match" {
  let (map, mem) = fresh()
  put_cstr(mem, map, 0x6000U, "abcb")
  assert_eq(host_strrchr(mem, map, 0x6000U, 98).value, Some(0x6003UL))
  assert_eq(host_strrchr(mem, map, 0x6000U, 122).value, Some(0UL))
}

///|
/// `strstr`：首次命中 / 空 needle 返回自身 / 未命中 NULL。
test "strstr_first_occurrence" {
  let (map, mem) = fresh()
  put_cstr(mem, map, 0x6000U, "abcabcd")
  put_cstr(mem, map, 0x6100U, "bc")
  assert_eq(host_strstr(mem, map, 0x6000U, 0x6100U).value, Some(0x6001UL))
  put_cstr(mem, map, 0x6200U, "")
  assert_eq(host_strstr(mem, map, 0x6000U, 0x6200U).value, Some(0x6000UL))
  put_cstr(mem, map, 0x6300U, "zz")
  assert_eq(host_strstr(mem, map, 0x6000U, 0x6300U).value, Some(0UL))
}

///|
/// `strpbrk`/`strspn`/`strcspn`：字节集语义。
test "strpbrk_strspn_strcspn" {
  let (map, mem) = fresh()
  put_cstr(mem, map, 0x6000U, "hello")
  put_cstr(mem, map, 0x6100U, "ol")
  put_cstr(mem, map, 0x6200U, "leh")
  assert_eq(
    host_strpbrk(mem, map, 0x6000U, 0x6100U).value,
    Some(0x6002UL),
    msg="'l' 是首个在 accept 集的字节",
  )
  assert_eq(host_strspn(mem, map, 0x6000U, 0x6200U).value, Some(4UL))
  assert_eq(host_strcspn(mem, map, 0x6000U, 0x6100U).value, Some(2UL))
  // 未命中 → NULL / 全命中 / 全不命中
  put_cstr(mem, map, 0x6300U, "xyz")
  assert_eq(host_strpbrk(mem, map, 0x6000U, 0x6300U).value, Some(0UL))
  assert_eq(host_strspn(mem, map, 0x6000U, 0x6200U).value, Some(4UL))
  assert_eq(host_strcspn(mem, map, 0x6000U, 0x6300U).value, Some(5UL))
}

///|
/// P2 修复锚：`memchr`（110 路由中唯一未登记缺口——oracle `string.rs:426-442`）。
/// 语义照搬：无符号字节与 c 匹配（负 c 恒不中）、未命中返 0、n 取原始 u64。
/// 登记分叉：oracle 越界静默 break，此处受检 trap（读侧口径同族）。
test "memchr_scan_unsigned_and_bounds" {
  let (map, mem) = fresh()
  put_bytes(mem, map, 0x6000U, b"abc\xC8\x00", false)
  assert_eq(host_memchr(mem, map, 0x6000U, 98, 5UL).value, Some(0x6001UL))
  assert_eq(
    host_memchr(mem, map, 0x6000U, 200, 5UL).value,
    Some(0x6003UL),
    msg="无符号字节 0xC8 ↔ c=200",
  )
  assert_eq(host_memchr(mem, map, 0x6000U, 122, 5UL).value, Some(0UL))
  assert_eq(
    host_memchr(mem, map, 0x6000U, -56, 5UL).value,
    Some(0UL),
    msg="负 c 恒不中（oracle 同）",
  )
  assert_eq(host_memchr(mem, map, 0x6000U, 97, 0UL).value, Some(0UL))
  // 受检化分叉锚：n 超内存尾 → trap（oracle 静默 break）
  let r = host_memchr(mem, map, @bytecode.MEM_SIZE - 2U, 1, 100UL)
  guard r.trap is Some(t) else {
    fail("越界必须 trap（受检化分叉）")
  }
  assert_true(t.contains("越界"))
}

// ── Host Contract 补锚段续（2026-10-04）：strcpy 高边界/NULL trap——
// oracle host_contract_tests.rs:263/528 断言照搬（dst=MEM_SIZE-4 界内成功 /
// NULL dest 受检 trap——mb 受检化分叉族形态）。

///|
test "strcpy_dest_at_high_boundary" {
  let (map, mem) = fresh()
  put_cstr(mem, map, 0x6000U, "ab")
  // dst 靠近内存末尾（MEM_SIZE-4）：两字符 + NUL 界内——必须成功拷贝
  let dst = @bytecode.MEM_SIZE - 4U
  let r = host_strcpy(map, mem, dst, 0x6000U, [])
  assert_eq(r.value, Some(dst.to_uint64()))
  assert_eq(peek(mem, map, dst, 3), b"ab\x00")
}

///|
test "strcpy_null_dest_traps" {
  let (map, mem) = fresh()
  put_cstr(mem, map, 0x6000U, "ab")
  // NULL dest：mb 受检访问单入口（NULL 区首查）——E30xx trap 分叉形态
  //（oracle 侧 has_error 同义；oracle 裸写 segfault 防护面）
  let r = host_strcpy(map, mem, 0U, 0x6000U, [])
  guard r.trap is Some(t) else { fail("NULL dest 必须受检 trap") }
  assert_true(
    t.contains("访问了 NULL 指针区域"),
    msg="NULL 区受检 fault 文案",
  )
}

///|
test "negative_n_family_traps_not_clamps" {
  // DIFF-LIB-STRNCPY-01 销案锚（2026-10-05 批二-b）：负 n（size_t 符号
  // 扩展巨量）= 清晰程序错误信号 → 越界写 trap（Clang 同形态 segfault
  // 实证 rc=139）；旧形态软夹紧补零到内存尾系 oracle 照搬。正巨量（如
  // 0x7FFFFFFF）保留教学软夹紧（与 memset ②-3 语义一致）
  let (map, mem) = fresh()
  put_cstr(mem, map, 0x6000U, "x")
  // strncpy 负 n → trap
  let r1 = host_strncpy(map, mem, 0x5000U, 0x6000U, -1)
  assert_true(r1.trap is Some(_), msg="strncpy 负 n 必须 trap")
  // memmove（memcpy 同实现）负 n → trap
  let r2 = host_memmove(map, mem, 0x5000U, 0x6000U, -1)
  assert_true(r2.trap is Some(_), msg="memmove 负 n 必须 trap")
  // strncat 贅量 n（u64 栈字形态）→ trap
  let r4 = host_strncat(map, mem, 0x5000U, 0x6000U, 0xFFFFFFFFFFFFFFFFUL)
  assert_true(r4.trap is Some(_), msg="strncat 巨量 n 必须 trap")
  // 正常形态不受影响
  put_cstr(mem, map, 0x6200U, "ab")
  let r3 = host_strncpy(map, mem, 0x6600U, 0x6200U, 4)
  assert_eq(r3.value, Some(0x6600UL))
  assert_eq(peek_str(mem, map, 0x6600U), "ab")
}

///|
fn peek_str(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  addr : UInt,
) -> String {
  let buf : Array[Byte] = []
  let mut p = addr
  let mut lim = 0
  while lim < 64 {
    match mem.load_i8(map, p) {
      Ok(b) => {
        if b == 0 {
          break
        }
        buf.push(b.to_byte())
        p = p + 1U
      }
      Err(_) => break
    }
    lim = lim + 1
  }
  @utf8.decode_lossy(Bytes::from_array(buf))
}

///|
/// 病 2 锚（#47，2026-10-09）：strdup 堆耗尽口径对齐 malloc——**返回 NULL +
/// 教学附注、不 trap**（旧照搬 oracle「静默压 NULL 无附注」与同包 malloc
/// 不一致；oracle 已随删区消失可单侧修）。
test "strdup_heap_exhausted_note" {
  let (map, mem) = fresh()
  put_cstr(mem, map, 0x6000U, "vitro")
  let mut n = 0
  let mut note : String? = None
  while true {
    let r = host_strdup(map, mem, 0x6000U, 7)
    match r.note {
      Some(t) => {
        note = Some(t)
        assert_eq(r.value, Some(0UL))
        assert_eq(r.trap, None, msg="堆耗尽不 trap")
        break
      }
      None => {
        guard r.value is Some(a) else { fail("未耗尽前必须分配成功") }
        assert_true(a != 0UL)
        n = n + 1
      }
    }
  }
  guard note is Some(t) else { fail("循环到耗尽必须命中 note") }
  assert_true(t.length() > 0)
  assert_true(n > 0)
}

///|
/// 病 1 锚（#47，2026-10-09）：strchr/strrchr 的 `c` 按 C11 §7.24.5.2
/// 「转换为 char 后比较」——负 `c` 取低 8 位（-1 → 0xFF）命中高位字节；
/// 旧实现负 `c` 恒不中（静默错值；Clang 对拍 `"abc\xFF""def"` 的
/// strchr(s,-1) = offset 3 vs 旧 Vitro -1）。
test "strchr_negative_c_char_conversion" {
  let (map, mem) = fresh()
  put_bytes(mem, map, 0x6000U, b"abc\xFFdef", true)
  let r = host_strchr(mem, map, 0x6000U, -1)
  assert_eq(
    r.value,
    Some(0x6003UL),
    msg="strchr 负 c 须按 char 截断语义命中 0xFF 字节",
  )
  let r2 = host_strrchr(mem, map, 0x6000U, -1)
  assert_eq(r2.value, Some(0x6003UL), msg="strrchr 同款 char 截断语义")
}
