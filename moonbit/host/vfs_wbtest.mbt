///| S6 host 余量批三号·VFS 白盒锚点。
///
/// 核心锚：坑 13 修复（append 建文件——oracle 死分支）、文本模式 CRLF 伸缩
/// 与逻辑/物理换算、容量扩容、FILE\* 协议、哨兵流分流。

///|
/// 便捷：VFS 三件套（map + mem + vfs）。
fn vfs_fresh() -> (@memory.MemoryMap, @memory.Memory, VirtualFileSystem) {
  (@memory.MemoryMap::new(), @memory.Memory::new(), VirtualFileSystem::new())
}

///|
/// 便捷：路径/模式串落内存。
fn put_str(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  addr : UInt32,
  s : String,
) -> Unit raise {
  put_cstr(mem, map, addr, s)
}

///|
test "vfs_preset_inject_fread_binary_roundtrip" {
  let (map, mem, vfs) = vfs_fresh()
  assert_true(vfs.inject_preset_file(map, mem, "t.bin", b"ABCDEF"))
  assert_false(
    vfs.inject_preset_file(map, mem, "t.bin", b"x"),
    msg="重名注入必须失败",
  )
  let fd = vfs.fopen(map, "t.bin", "rb")
  assert_true(fd != 0U)
  let buf = 0x8000U
  // fread 全量
  let n = vfs.fread(mem, map, fd, buf, 1, 100)
  assert_eq(n, 6, msg="6 元素（size=1）")
  assert_eq(peek(mem, map, buf, 6), b"ABCDEF")
  // 短读形态（请求 100 仅得 6）置 EOF——与 C 同形（A2 探针 clang 22.1.4
  // feof=1）。注：审阅 M23 曾把本行定性为「恰满即 EOF」病锚，A2 批复核
  // 此形态是短读非恰满，锚值正确，仅原 msg「读满即 EOF」描述机制有误导
  // 已改；真正的恰满偏差见下方 vfs_feof_exact_fill_known_divergence。
  assert_eq(
    vfs.feof(fd),
    1,
    msg="短读（请求 100 仅得 6）置 EOF——C 同形",
  )
  // 尺寸链防护：size*nmemb 超 MEM_SIZE → 0
  assert_eq(vfs.fread(mem, map, fd, buf, 0x100000, 16), 0)
}

///|
/// EOF 粘滞位「仅过读置位」族双形态锚（审阅 v2 批 A2 立 KNOWN_DIVERGENCE，
/// B10 批 #434 修复翻面；真值 = A2 探针 `D:/tmp/a2probe/feof.c` Win clang
/// 22.1.4-UCRT + B10 复测 `tmp/b10probe/p1b_feof_shapes.c` 同值，与 M23b
/// 四端表〔WSL gcc 15.2 / clang 21.1.8 glibc〕逐位一致）。
///
/// C11 7.21.10.2：EOF 指示器仅在**尝试读过文件尾**后置位，恰满不置。
/// 修前 `vfs.mbt` fread/fgets/fgetc 尾部 `cursor >= size ⇒ eof=true` 把
/// 三形态都提前一圈置位（教学经典 `while(!feof)` 反模式少跑一圈——M23b
/// a1_loop 实锤 loops 3 vs 真机 4；A2 锁修前三处值 1）。过读形态
/// （n=0 / fgetc=-1 后）双侧一致为 1。
test "vfs_feof_only_on_overread" {
  let (map, mem, vfs) = vfs_fresh()
  ignore(vfs.inject_preset_file(map, mem, "e6.bin", b"ABCDEF"))
  let fd = vfs.fopen(map, "e6.bin", "rb")
  let buf = 0x8000U
  // 恰满：请求 6 得 6——C11 §7.21.10.2 恰满不置（B10 修前 1）
  assert_eq(vfs.fread(mem, map, fd, buf, 1, 6), 6)
  assert_eq(vfs.feof(fd), 0, msg="恰满不置 EOF（仅过读置位）")
  // 过读：n=0 且 feof=1（双侧一致）
  assert_eq(vfs.fread(mem, map, fd, buf, 1, 6), 0)
  assert_eq(vfs.feof(fd), 1, msg="过读置 EOF（C 同形）")
  // fgetc 读完末字节
  ignore(vfs.inject_preset_file(map, mem, "e2.bin", b"xy"))
  let fd2 = vfs.fopen(map, "e2.bin", "rb")
  assert_eq(vfs.fgetc(mem, map, fd2), 120)
  assert_eq(vfs.fgetc(mem, map, fd2), 121)
  // B10 修前 1：读完末字节（恰满）不置
  assert_eq(vfs.feof(fd2), 0, msg="末字节后不置 EOF（恰满非过读）")
  assert_eq(vfs.fgetc(mem, map, fd2), -1)
  assert_eq(vfs.feof(fd2), 1, msg="fgetc 返 EOF 后置位（C 同形）")
  // fgets 停于 \n 且恰到文件尾
  ignore(vfs.inject_preset_file(map, mem, "e3.txt", b"ab\n"))
  let fd3 = vfs.fopen(map, "e3.txt", "r")
  assert_eq(vfs.fgets(mem, map, fd3, buf, 100), buf)
  // B10 修前 1：停于 \n 恰到尾（未尝试过读）不置
  assert_eq(vfs.feof(fd3), 0, msg="fgets 恰到尾不置 EOF（未过读）")
}

///|
/// `fgets(buf, n, f)` n 边界族（B10 #434 / M23 A2；真值 = Win clang
/// 22.1.4-UCRT `tmp/b10probe/p1b_feof_shapes.c` S6 段，glibc 同形——
/// M23b 四端表）。
///
/// C11 §7.21.7.2：fgets 最多读 n-1 字符 + NUL；n=1 → 读 0 字符、写 NUL、
/// 返回 buf（**不置 eof、游标不动**）。修前 n=1 返 NULL 且误置 eof。
/// n<=0（UB 域）：按 glibc 口径零副作用返 NULL（不动 buf/游标/不置 eof）。
test "vfs_fgets_n1_returns_buf_writes_nul" {
  let (map, mem, vfs) = vfs_fresh()
  ignore(vfs.inject_preset_file(map, mem, "hi.txt", b"hi"))
  let fd = vfs.fopen(map, "hi.txt", "r")
  let buf = 0x8000U
  ignore(mem.write_bytes(map, buf, b"Z"))
  // n=1：返 buf、写 NUL、不置 eof
  assert_eq(vfs.fgets(mem, map, fd, buf, 1), buf, msg="n=1 返回 buf 非 NULL")
  assert_eq(peek(mem, map, buf, 1), b"\x00", msg="n=1 写入 NUL")
  assert_eq(vfs.feof(fd), 0, msg="n=1 不置 EOF（修前误置 1）")
  assert_eq(vfs.ftell(fd), 0, msg="n=1 游标不动（未消耗）")
  // 后续 fgets 未被吞
  assert_eq(vfs.fgets(mem, map, fd, buf, 8), buf)
  assert_eq(
    peek(mem, map, buf, 3),
    b"hi\x00",
    msg="后续读得 hi（未消耗）",
  )
  // n=0：返 NULL（双侧一致）
  assert_eq(vfs.fgets(mem, map, fd, buf, 0), 0U)
  // 负 n（UB 域）：glibc 口径零副作用返 NULL——修前置 eof=1
  ignore(mem.write_bytes(map, buf, b"Q"))
  assert_eq(vfs.fgets(mem, map, fd, buf, -1), 0U)
  assert_eq(peek(mem, map, buf, 1), b"Q", msg="负 n 不动 buf")
  assert_eq(vfs.feof(fd), 0, msg="负 n 不置 EOF（修前误置 1）")
}

///|
/// 文本臂 `fseek(SEEK_SET, 过尾)` 不钳位（B10 #434 / M23 A3；真值 = Win
/// clang 22.1.4-UCRT `tmp/b10probe/p1b_feof_shapes.c` F6 段：sk=0 tl=10
/// size=12 洞 00 XY@10——二进制臂修前即同形，此处锁文本臂对齐）。
///
/// 修前 `logical_to_physical` 对超长逻辑位截断到物理末尾（ftell=6、写
/// XY 落 @6、size=8）；C 语义过尾 fseek 合法、过尾写留 0 洞。
test "vfs_fseek_text_past_eof_unclamped" {
  let (map, mem, vfs) = vfs_fresh()
  ignore(vfs.inject_preset_file(map, mem, "s6.bin", b"ABCDEF"))
  let fd = vfs.fopen(map, "s6.bin", "r+")
  let buf = 0x8000U
  assert_eq(vfs.fseek(mem, map, fd, 10, 0), 0, msg="fseek 过尾成功")
  assert_eq(vfs.ftell(fd), 10, msg="修前钳到 6")
  put_str(mem, map, 0x6000U, "XY")
  assert_eq(vfs.fputs(mem, map, fd, 0x6000U), 0)
  ignore(vfs.fclose(fd))
  let fdr = vfs.fopen(map, "s6.bin", "rb")
  assert_eq(vfs.fread(mem, map, fdr, buf, 1, 12), 12, msg="修前 size=8")
  assert_eq(peek(mem, map, buf, 6), b"ABCDEF", msg="原 6 字节不动")
  assert_eq(
    peek(mem, map, buf + 6U, 6),
    b"\x00\x00\x00\x00XY",
    msg="过尾洞为 0 + XY 落 @10（修前 XY 落 @6 size=8）",
  )
  ignore(vfs.fclose(fdr))
}

///|
/// rename 覆盖已存在目标：旧目标堆块释放（B10 #434 / M23 B3 白盒面；
/// 可观测面 glibc 同形无罪——UCRT 才是失败口径，M23b 四端定责在案）。
///
/// 修前覆盖分支 `Map.set` 直接换键，旧目标 `heap_addr` 块不
/// `vfs_free_raw`——白盒堆泄漏（教学长会话可耗尽堆）。观测 =
/// regions 表中被释放条目计数（修复前 rename 覆盖后恒 0）。
test "vfs_rename_overwrite_frees_old_block" {
  let (map, mem, vfs) = vfs_fresh()
  ignore(vfs.inject_preset_file(map, mem, "old.txt", b"OLD"))
  ignore(vfs.inject_preset_file(map, mem, "new.txt", b"NEW"))
  let freed_before = count_freed_regions(map)
  assert_eq(freed_before, 0, msg="初始无释放块")
  // B10 修复连坐：rename 加 map 参数（覆盖分支释放旧目标块）
  assert_eq(vfs.rename(map, "old.txt", "new.txt"), 0)
  // B10 修前 0（旧目标块泄漏在表）；修后 1（覆盖分支先 vfs_free_raw）
  assert_eq(
    count_freed_regions(map),
    1,
    msg="覆盖分支释放旧目标块（修前泄漏恒 0）",
  )
  // 新路径内容 = OLD（glibc 口径替换，可观测面不变）
  let fd = vfs.fopen(map, "new.txt", "r")
  let buf = 0x8000U
  assert_eq(vfs.fread(mem, map, fd, buf, 1, 3), 3)
  assert_eq(peek(mem, map, buf, 3), b"OLD")
  ignore(vfs.fclose(fd))
  // 旧路径已不存在
  assert_eq(vfs.fopen(map, "old.txt", "r"), 0U)
}

///|
/// regions 表已释放条目计数（rename 覆盖释放锚的观测辅助）。
fn count_freed_regions(map : @memory.MemoryMap) -> Int32 {
  let mut n = 0
  for pair in map.regions_to_array() {
    if pair.1.is_freed {
      n = n + 1
    }
  }
  n
}

///|
test "vfs_text_mode_crlf_compress_and_expand" {
  let (map, mem, vfs) = vfs_fresh()
  // 物理含 \r\n：文本读压成 \n
  ignore(vfs.inject_preset_file(map, mem, "t.txt", b"a\r\nb\r\n"))
  let fd = vfs.fopen(map, "t.txt", "r")
  let buf = 0x8000U
  let n = vfs.fread(mem, map, fd, buf, 1, 100)
  assert_eq(n, 4, msg="逻辑字节 4 个（a \\n b \\n）")
  assert_eq(peek(mem, map, buf, 4), b"a\nb\n")
  // 文本写 \n 展开 \r\n：w 建文件 → fputs → 重开读物理
  put_str(mem, map, 0x6000U, "x\ny")
  let fdw = vfs.fopen(map, "w.txt", "w")
  assert_true(fdw != 0U)
  assert_eq(vfs.fputs(mem, map, fdw, 0x6000U), 0)
  assert_eq(vfs.fclose(fdw), 0)
  // 物理校验（rb 读）
  let fdr = vfs.fopen(map, "w.txt", "rb")
  let buf2 = 0x8100U
  let n2 = vfs.fread(mem, map, fdr, buf2, 1, 100)
  assert_eq(n2, 4, msg="x\ny 三字节展开为四字节物理")
  assert_eq(peek(mem, map, buf2, 4), b"x\r\ny", msg="\n 展开为 \r\n")
}

///|
test "vfs_fopen_append_creates_file_pit13_fix" {
  let (map, mem, vfs) = vfs_fresh()
  // 坑 13 修复锚：append 建文件（oracle 死分支——追加写静默丢弃）
  put_str(mem, map, 0x6000U, "data")
  let fd = vfs.fopen(map, "a.txt", "a")
  assert_true(fd != 0U, msg="append 对新文件必须建文件并成功打开")
  assert_eq(vfs.fputs(mem, map, fd, 0x6000U), 0)
  // 重开读回
  let fdr = vfs.fopen(map, "a.txt", "rb")
  let buf = 0x8000U
  assert_eq(vfs.fread(mem, map, fdr, buf, 1, 100), 4)
  assert_eq(peek(mem, map, buf, 4), b"data")
  // 追加到既有文件：游标在末尾
  put_str(mem, map, 0x6100U, "!")
  let fda = vfs.fopen(map, "a.txt", "ab")
  assert_eq(vfs.fputs(mem, map, fda, 0x6100U), 0)
  let fdr2 = vfs.fopen(map, "a.txt", "rb")
  assert_eq(vfs.fread(mem, map, fdr2, buf, 1, 100), 5)
  assert_eq(peek(mem, map, buf, 5), b"data!")
}

///|
test "vfs_fopen_write_truncates_and_read_missing_fails" {
  let (map, mem, vfs) = vfs_fresh()
  ignore(vfs.inject_preset_file(map, mem, "t.txt", b"hello"))
  let fd = vfs.fopen(map, "t.txt", "w")
  assert_true(fd != 0U)
  // w 打开即清空
  let fdr = vfs.fopen(map, "t.txt", "rb")
  assert_eq(vfs.fread(mem, map, fdr, 0x8000U, 1, 10), 0)
  // 读模式不存在 → 0
  assert_eq(vfs.fopen(map, "no.txt", "r"), 0U)
  // 真未知模式串 → 0（r+ 系已合法化，见 vfs_fopen_plus_modes——#228）
  assert_eq(vfs.fopen(map, "t.txt", "rw"), 0U)
}

///|
/// #228 锚（2026-10-22）：`r+`/`w+`/`a+` 读写模式（C11 §7.21.5.3——
/// 旧形态落 None 静默返 NULL 无任何诊断，学生 `fprintf(fp,…)` 后续行为
/// 不可预期）。语义：r+ 须存在/不清空/游标 0；w+ 建或清空；a+ 建文件/
/// 游标末尾；`b` 与 `+` 可任意序（rb+ = r+b）。
test "vfs_fopen_plus_modes" {
  let (map, mem, vfs) = vfs_fresh()
  // r+：存在文件打开成功，可写可读，游标 0（写覆盖不截断）
  ignore(vfs.inject_preset_file(map, mem, "t1.txt", b"hello"))
  let fd = vfs.fopen(map, "t1.txt", "r+")
  assert_true(fd != 0U, msg="r+ 打开存在文件不应返回 NULL")
  put_str(mem, map, 0x6000U, "HE")
  assert_eq(vfs.fputs(mem, map, fd, 0x6000U), 0, msg="r+ 允许写")
  ignore(vfs.fclose(fd))
  let fdr = vfs.fopen(map, "t1.txt", "rb")
  assert_eq(vfs.fread(mem, map, fdr, 0x8000U, 1, 100), 5)
  assert_eq(peek(mem, map, 0x8000U, 5), b"HEllo", msg="r+ 覆盖写不清空")
  // r+：不存在 → 0（与 r 同）
  assert_eq(vfs.fopen(map, "no.txt", "r+"), 0U)
  // w+：建新文件，写后可重读（fclose 重开校验）
  let fdw = vfs.fopen(map, "t3.txt", "w+")
  assert_true(fdw != 0U, msg="w+ 建文件")
  put_str(mem, map, 0x6100U, "abc")
  assert_eq(vfs.fputs(mem, map, fdw, 0x6100U), 0)
  ignore(vfs.fclose(fdw))
  let fdr3 = vfs.fopen(map, "t3.txt", "rb")
  assert_eq(vfs.fread(mem, map, fdr3, 0x8100U, 1, 100), 3)
  assert_eq(peek(mem, map, 0x8100U, 3), b"abc")
  // w+：清空既有（同 w）
  let fdw2 = vfs.fopen(map, "t1.txt", "w+")
  assert_true(fdw2 != 0U)
  ignore(vfs.fclose(fdw2))
  let fdr1 = vfs.fopen(map, "t1.txt", "rb")
  assert_eq(vfs.fread(mem, map, fdr1, 0x8200U, 1, 100), 0, msg="w+ 清空")
  // a+：建文件 + 读起点文件头（写恒末尾——追加后重开读全量）
  let fda = vfs.fopen(map, "t4.txt", "a+")
  assert_true(fda != 0U, msg="a+ 建文件")
  put_str(mem, map, 0x6200U, "XY")
  assert_eq(vfs.fputs(mem, map, fda, 0x6200U), 0)
  ignore(vfs.fclose(fda))
  let fdr4 = vfs.fopen(map, "t4.txt", "rb")
  assert_eq(vfs.fread(mem, map, fdr4, 0x8300U, 1, 100), 2)
  assert_eq(peek(mem, map, 0x8300U, 2), b"XY")
  // b/+ 序不敏感：rb+ = r+b（文件在——w+ 只清空不删除）
  assert_true(vfs.fopen(map, "t1.txt", "rb+") != 0U)
  assert_true(vfs.fopen(map, "t1.txt", "r+b") != 0U)
}

///|
test "vfs_fgets_line_and_fgetc_fputc" {
  let (map, mem, vfs) = vfs_fresh()
  ignore(vfs.inject_preset_file(map, mem, "t.txt", b"ab\ncd"))
  let fd = vfs.fopen(map, "t.txt", "r")
  let buf = 0x8000U
  // fgets 第一行
  assert_eq(vfs.fgets(mem, map, fd, buf, 100), buf)
  assert_eq(peek(mem, map, buf, 4), b"ab\n\x00")
  // fgetc：c、d
  assert_eq(vfs.fgetc(mem, map, fd), 99)
  assert_eq(vfs.fgetc(mem, map, fd), 100)
  assert_eq(vfs.fgetc(mem, map, fd), -1, msg="EOF")
  assert_eq(vfs.feof(fd), 1)
  // fputc（文本模式 \n → \r\n）
  let fdw = vfs.fopen(map, "o.txt", "w")
  assert_eq(vfs.fputc(mem, map, fdw, 65), 65)
  assert_eq(vfs.fputc(mem, map, fdw, 10), 10)
  let fdr = vfs.fopen(map, "o.txt", "rb")
  let b2 = 0x8100U
  assert_eq(vfs.fread(mem, map, fdr, b2, 1, 10), 3)
  assert_eq(peek(mem, map, b2, 3), b"A\r\n")
  // 只读 fd 拒写
  assert_eq(vfs.fputc(mem, map, fdr, 66), -1)
}

///|
test "vfs_fseek_ftell_negative_and_text_logical" {
  let (map, mem, vfs) = vfs_fresh()
  ignore(vfs.inject_preset_file(map, mem, "t.bin", b"abcdef"))
  let fd = vfs.fopen(map, "t.bin", "rb")
  // SEEK_SET / CUR / END
  assert_eq(vfs.fseek(mem, map, fd, 2, 0), 0)
  assert_eq(vfs.ftell(fd), 2)
  assert_eq(vfs.fseek(mem, map, fd, 1, 1), 0)
  assert_eq(vfs.ftell(fd), 3)
  assert_eq(vfs.fseek(mem, map, fd, -1, 2), 0)
  assert_eq(vfs.ftell(fd), 5)
  // 负目标：-1 且游标不动（U2#13）
  assert_eq(vfs.fseek(mem, map, fd, -100, 0), -1)
  assert_eq(vfs.ftell(fd), 5, msg="失败不动游标")
  // 未知 whence
  assert_eq(vfs.fseek(mem, map, fd, 0, 9), -1)
  // rewind 清 EOF
  vfs.rewind(fd)
  assert_eq(vfs.ftell(fd), 0)
  assert_eq(vfs.feof(fd), 0)
  // 文本模式：物理 "a\r\nb"，逻辑 SET(1) → 物理 1；SET(2) → 物理 3
  ignore(vfs.inject_preset_file(map, mem, "t2.txt", b"a\r\nb"))
  let fdt = vfs.fopen(map, "t2.txt", "r")
  assert_eq(vfs.fseek(mem, map, fdt, 1, 0), 0)
  assert_eq(vfs.ftell(fdt), 1, msg="ftell 返回物理游标")
  assert_eq(
    vfs.fgetc(mem, map, fdt),
    10,
    msg="物理 1 起读 \\r\\n → 逻辑 \\n",
  )
  assert_eq(vfs.fseek(mem, map, fdt, 2, 0), 0)
  assert_eq(vfs.ftell(fdt), 3)
  assert_eq(vfs.fgetc(mem, map, fdt), 98, msg="逻辑 2 = 物理 3 = 'b'")
}

///|
test "vfs_capacity_growth_preserves_content" {
  let (map, mem, vfs) = vfs_fresh()
  // 初始 256 容量 → 写 300 字节触发扩容（2× 容 ≥ 512）
  let fd = vfs.fopen(map, "big.txt", "wb")
  let chunk = 0x8000U
  let three_hundred : Array[Byte] = []
  let mut i = 0
  while i < 300 {
    three_hundred.push((i % 251).to_byte())
    i = i + 1
  }
  ignore(mem.write_bytes(map, chunk, Bytes::from_array(three_hundred)))
  assert_eq(vfs.fwrite(mem, map, fd, chunk, 1, 300), 300)
  let fdr = vfs.fopen(map, "big.txt", "rb")
  let out = 0x9000U
  assert_eq(vfs.fread(mem, map, fdr, out, 1, 400), 300)
  assert_eq(peek(mem, map, out, 300), Bytes::from_array(three_hundred))
}

///|
test "vfs_remove_and_rename" {
  let (map, mem, vfs) = vfs_fresh()
  ignore(vfs.inject_preset_file(map, mem, "a.txt", b"x"))
  let fd = vfs.fopen(map, "a.txt", "r")
  assert_true(fd != 0U)
  // rename：描述符跟随
  assert_eq(vfs.rename(map, "a.txt", "b.txt"), 0)
  assert_eq(vfs.get_file_name(fd), Some("b.txt"))
  let fdr = vfs.fopen(map, "b.txt", "r")
  assert_true(fdr != 0U, msg="新名可开")
  // remove：关描述符 + 释放区域
  assert_eq(vfs.remove(map, "b.txt"), 0)
  assert_eq(
    vfs.get_file_name(fd),
    None,
    msg="指向被删文件的描述符关闭",
  )
  assert_eq(vfs.fopen(map, "b.txt", "r"), 0U)
  assert_eq(vfs.remove(map, "b.txt"), -1)
  assert_eq(vfs.rename(map, "no.txt", "z.txt"), -1)
}

// ── FILE* 协议与 handler 面 ─────────────────────────────────────────────

///|
test "file_ptr_protocol_fopen_fclose_uaf_window" {
  let (map, mem, vfs) = vfs_fresh()
  put_str(mem, map, 0x6000U, "d.txt")
  put_str(mem, map, 0x6100U, "r")
  // 读模式打开不存在的 d.txt → NULL（fopen 失败语义）
  let r0 = host_fopen(map, mem, vfs, 0x6000U, 0x6100U, 3)
  assert_eq(r0.value, Some(0UL), msg="读模式缺文件必须 NULL")
  // 注入后打开成功
  ignore(vfs.inject_preset_file(map, mem, "d.txt", b"hi"))
  let r = host_fopen(map, mem, vfs, 0x6000U, 0x6100U, 4)
  let file_ptr = r.value.unwrap().to_uint()
  assert_true(file_ptr != 0U)
  // FILE* 处的 fd 可读回（read_fd 等价面：fread 成功即证）
  guard map.region(file_ptr) is Some(rec) else {
    fail("FILE* 区域必须登记")
  }
  assert_eq(rec.alloc_by, "fopen")
  assert_true(rec.name.has_prefix("FILE:"))
  let r2 = host_fopen(map, mem, vfs, 0x6000U, 0x6100U, 4)
  let fp2 = r2.value.unwrap().to_uint()
  let f = host_fread(map, mem, vfs, 0x8000U, 1, 10, fp2)
  assert_eq(f.value, Some(2UL))
  assert_eq(peek(mem, map, 0x8000U, 2), b"hi")
  // fclose：0 + FILE* 区域释放（进 UAF 窗口——登记分叉锚）
  let c = host_fclose(map, mem, vfs, fp2, 5, 5)
  assert_eq(c.value, Some(0UL))
  assert_true(
    map.freed_logs_contains(fp2),
    msg="release 单出口——oracle 侧缺口②登记",
  )
  // 二次 fclose：FILE* 已进 UAF 窗口——**登记分叉锚**：oracle 裸读得陈旧 fd
  // 返回 -1（free_region 不写 freed_logs——缺口②）；此处受检读 → trap
  let c2 = host_fclose(map, mem, vfs, fp2, 6, 6)
  guard c2.trap is Some(t2) else {
    fail("二次 fclose 必须 UAF trap（受检化分叉）")
  }
  assert_true(t2.contains("E3060"))
}

///|
test "file_fputs_stdout_stderr_split_and_perror" {
  let (map, mem, vfs) = vfs_fresh()
  put_str(mem, map, 0x6000U, "to-out")
  put_str(mem, map, 0x6100U, "to-err")
  let log = OutputLog::new()
  // 哨兵 1/2 → 通道直出（E-P1-5）
  let r1 = host_fputs(map, mem, vfs, log, 0x6000U, 1U)
  assert_eq(r1.value, Some(0UL))
  let r2 = host_fputs(map, mem, vfs, log, 0x6100U, 2U)
  assert_eq(r2.value, Some(0UL))
  assert_eq(log.join(OutputKind::Stdout), b"to-out")
  assert_eq(log.join(OutputKind::Stderr), b"to-err")
  // perror：带前缀 / 空
  put_str(mem, map, 0x6200U, "open failed")
  assert_eq(host_perror(map, mem, log, 0x6200U).value, None)
  assert_eq(
    log.join(OutputKind::Stderr),
    b"to-erropen failed: No error\n",
    msg="stderr 追加",
  )
  // perror(NULL) 形态：空前缀（空串）→ "No error\n"（病 49 UCRT 口径，
  // M23b 四端复证：vitro 与 Win-UCRT 逐字节同形，glibc 为 "Success"——
  // 既定锁定非缺陷。审阅 v2 批 A2 / M23 B2：原注释写 "Error\n" 系实现改
  // 后漏改的残留，原断言仅 length>0 未锁内容——此处双修：注释对齐实现，
  // 断言锚完整 stderr 累积（含前段 perror 残留，逐字节））
  put_bytes(mem, map, 0x6300U, b"\x00", false)
  ignore(host_perror(map, mem, log, 0x6300U))
  assert_eq(
    log.join(OutputKind::Stderr),
    b"to-erropen failed: No error\nNo error\n",
    msg="空前缀 perror 全量 stderr 累积（UCRT 口径）",
  )
}

///|
test "file_misc_handlers_shape" {
  let (map, mem, vfs) = vfs_fresh()
  // 病 15 批 B：fwrite/fputc +log、feof +InputState（stdin EOF 粘滞查询——占位）
  let log = OutputLog::new()
  let input = InputState::new([], true)
  ignore(vfs.inject_preset_file(map, mem, "m.txt", b"ab"))
  put_str(mem, map, 0x6100U, "m.txt")
  // fopen 拿 FILE*
  put_str(mem, map, 0x6000U, "r")
  let fp = host_fopen(map, mem, vfs, 0x6100U, 0x6000U, 1).value
    .unwrap()
    .to_uint()
  // fwrite 写回读模式 → 0（Read 拒写）
  assert_eq(host_fwrite(map, mem, vfs, log, 0x8000U, 1, 1, fp).value, Some(0UL))
  // fgets / fgetc / feof / ftell / fseek / fflush / rewind / clearerr
  assert_eq(host_fgets(map, mem, vfs, 0x8000U, 10, fp).value, Some(0x8000UL))
  assert_eq(
    host_fgetc(map, mem, vfs, fp).value,
    Some(0xFFFFFFFFFFFFFFFFUL),
    msg="EOF -1",
  )
  assert_eq(host_feof(map, mem, vfs, input, fp).value, Some(1UL))
  assert_eq(
    host_fseek(map, mem, vfs, fp, 0, 0).value,
    Some(0UL),
    msg="rewind 后可 seek",
  )
  assert_eq(host_ftell(map, mem, vfs, fp).value, Some(0UL))
  assert_eq(host_fflush(map, mem, vfs, fp).value, Some(0UL))
  ignore(host_rewind(map, mem, vfs, fp))
  assert_eq(host_feof(map, mem, vfs, input, fp).value, Some(0UL))
  ignore(host_clearerr(map, mem, vfs, fp))
  // fputc 读模式 → -1
  assert_eq(
    host_fputc(map, mem, vfs, log, 66, fp).value,
    Some(0xFFFFFFFFFFFFFFFFUL),
  )
  // remove / rename
  assert_eq(host_remove(map, mem, vfs, 0x6100U).value, Some(0UL))
  put_str(mem, map, 0x6200U, "n.txt")
  ignore(vfs.inject_preset_file(map, mem, "n.txt", b"z"))
  assert_eq(host_rename(map, mem, vfs, 0x6200U, 0x6300U).value, Some(0UL))
}

///|
test "vfs_fgets_binary_mode_no_crlf_compress" {
  // DIFF-VFS-CRLF-01 销案锚（2026-10-05 批二-b）：二进制模式 fgets 字节
  // 原样（\r\n 不压缩）——旧形态无条件走 read_text_byte 系 oracle 照搬；
  // Clang rb 模式探针 fgets_bin.c 双侧实证（61 0d 0a vs 修前 61 0a）
  let (map, mem, vfs) = vfs_fresh()
  // wb 写入 61 0D 0A 62（二进制原样——写侧本就不展开 \n）
  let fdw = vfs.fopen(map, "bin_raw.bin", "wb")
  assert_true(fdw > 0U)
  ignore(mem.store_u32(map, 0x6000U, 0U))
  put_bytes(mem, map, 0x6000U, b"a\r\nb", false)
  assert_eq(vfs.fwrite(mem, map, fdw, 0x6000U, 1, 4), 4)
  ignore(vfs.fclose(fdw))
  // rb fgets：\r\n 原样两字节（修前被压成 \n）
  let fdr = vfs.fopen(map, "bin_raw.bin", "rb")
  assert_true(fdr > 0U)
  let buf = 0x6500U
  let ret = vfs.fgets(mem, map, fdr, buf, 16)
  assert_eq(ret, buf)
  let got : Array[Byte] = []
  for i = 0; i < 4; i = i + 1 {
    got.push(
      mem.load_i8(map, buf + i.reinterpret_as_uint()).unwrap_or(0).to_byte(),
    )
  }
  // 逐字节断言（避开字符串字面量转义链：a=97 CR=13 LF=10）
  assert_eq(got[0].to_int(), 97)
  assert_eq(got[1].to_int(), 13)
  assert_eq(got[2].to_int(), 10)
  ignore(vfs.fclose(fdr))
}

///|
/// 病 15 批 B 红→绿锚（#61，2026-10-10）：标准流句柄（stdin=0/stdout=1/
/// stderr=2 宏展开形态）分流——旧形态（≤2 折叠 fd=0 静默失败）下
/// `fputc('x', stdout)` 输出凭空丢失、`fgets(b,n,stdin)` 恒空读。
test "stdio_handle_dispatch_batch_b" {
  let (map, mem, vfs) = vfs_fresh()
  let log = OutputLog::new()
  // 写族：stdout/stderr 直推通道、返回 (unsigned char)c
  assert_eq(
    host_fputc(map, mem, vfs, log, 120, 1U).value,
    Some(120UL),
    msg="fputc('x', stdout) 返 x",
  )
  assert_eq(log.join(OutputKind::Stdout), b"x", msg="fputc stdout 落流")
  assert_eq(
    host_fputc(map, mem, vfs, log, 121, 2U).value,
    Some(121UL),
    msg="fputc('y', stderr) 返 y",
  )
  assert_eq(log.join(OutputKind::Stderr), b"y", msg="fputc stderr 落流")
  assert_eq(
    host_fputc(map, mem, vfs, log, 120, 0U).value,
    Some(0xFFFFFFFFFFFFFFFFUL),
    msg="fputc 对 stdin 写 → EOF",
  )
  // fwrite 到 stdout：内容直推、返 nmemb
  put_bytes(mem, map, 0x7000U, b"AB", false)
  assert_eq(
    host_fwrite(map, mem, vfs, log, 0x7000U, 1, 2, 1U).value,
    Some(2UL),
    msg="fwrite(buf,1,2,stdout) 返 2",
  )
  assert_eq(log.join(OutputKind::Stdout), b"xAB", msg="fwrite 追加落 stdout")
  // 状态族：std 流非 seekable / fclose 成功 / fflush 成功
  assert_eq(
    host_fseek(map, mem, vfs, 1U, 0, 0).value,
    Some(0xFFFFFFFFFFFFFFFFUL),
    msg="fseek(stdout) → -1",
  )
  assert_eq(
    host_ftell(map, mem, vfs, 1U).value,
    Some(0xFFFFFFFFFFFFFFFFUL),
    msg="ftell(stdout) → -1",
  )
  assert_eq(
    host_fclose(map, mem, vfs, 1U, 9, 99).value,
    Some(0UL),
    msg="fclose(stdout) → 0（C 语义）",
  )
  assert_eq(
    host_fflush(map, mem, vfs, 1U).value,
    Some(0UL),
    msg="fflush(stdout) → 0",
  )
  ignore(host_rewind(map, mem, vfs, 2U))
  ignore(host_clearerr(map, mem, vfs, 0U))
  // 读族：stdin 走 InputState（Batch 消费后 EOF）
  let input = InputState::new([b"hi\n"], true)
  let buf = 0x7100U
  match host_fgets_dispatch(map, mem, vfs, input, buf, 8, 0U) {
    StdioRead::Done(r) =>
      assert_eq(r.value, Some(0x7100UL), msg="fgets(b,8,stdin) 返 buf")
    StdioRead::StdioWaiting => fail("Batch 模式不应等待")
  }
  assert_eq(
    read_span(mem, map, buf, 3),
    Ok([b'h', b'i', b'\n']),
    msg="fgets stdin 行落 buf（含 \n + NUL）",
  )
  assert_eq(
    host_fgetc_dispatch(map, mem, vfs, input, 0U) is StdioRead::Done(_),
    true,
    msg="fgetc(stdin) Batch 耗尽 → EOF（Done 态）",
  )
  // Interactive 空输入 → StdioWaiting（零消费等待）
  let inter = InputState::new([], false)
  assert_true(
    host_fgetc_dispatch(map, mem, vfs, inter, 0U) is StdioRead::StdioWaiting,
    msg="fgetc(stdin) Interactive 空 → 等待",
  )
  // fread stdin 批读
  let input2 = InputState::new([b"abc", b"de"], true)
  match host_fread_dispatch(map, mem, vfs, input2, buf, 1, 4, 0U) {
    StdioRead::Done(r) =>
      assert_eq(r.value, Some(4UL), msg="fread(buf,1,4,stdin) 跨行返 4")
    StdioRead::StdioWaiting => fail("Batch 不等待")
  }
  assert_eq(
    read_span(mem, map, buf, 4),
    Ok([b'a', b'b', b'c', b'd']),
    msg="fread stdin 跨行拼接（'abc'+'de' 前 4 字节）",
  )
}

///|
/// 审阅 P2-2 锚（2026-10-23，修复前证红）：a/a+ 的追加写语义与 a+ 读起点
///——C11 §7.21.5.3：a/a+ **写恒在末尾**（fseek 不改变写位）；a+ 的**读
/// 起点在文件头**。旧形态：a/a+ 共用「游标初始=末尾」+ 写按游标——
/// a+ 同 fd 读返回空、fseek(0) 后 fputs 覆盖头部（Xbc）。
test "vfs_append_mode_write_always_end_and_aplus_reads_from_start" {
  let (map, mem, vfs) = vfs_fresh()
  ignore(vfs.inject_preset_file(map, mem, "t.txt", b"abc"))
  // a+ 同 fd 读：起点在文件头（旧：游标在末尾 → 读空）
  let fap = vfs.fopen(map, "t.txt", "a+")
  assert_true(fap != 0U)
  let buf = 0x8000U
  assert_eq(
    vfs.fread(mem, map, fap, buf, 1, 10),
    3,
    msg="a+ 读起点在文件头",
  )
  assert_eq(peek(mem, map, buf, 3), b"abc")
  // a+ fseek(0) 后写：写位恒末尾（旧：Xbc 覆盖头部）
  assert_eq(vfs.fseek(mem, map, fap, 0, 0), 0)
  put_str(mem, map, 0x6000U, "X")
  assert_eq(vfs.fputs(mem, map, fap, 0x6000U), 0)
  ignore(vfs.fclose(fap))
  let fr = vfs.fopen(map, "t.txt", "rb")
  assert_eq(vfs.fread(mem, map, fr, 0x8100U, 1, 10), 4)
  assert_eq(peek(mem, map, 0x8100U, 4), b"abcX", msg="a+ 写恒追加到末尾")
  // a（纯追加）fseek(0) 后写：同语义（既有缺口，一处根因两个症状）
  let fa = vfs.fopen(map, "t.txt", "a")
  assert_eq(vfs.fseek(mem, map, fa, 0, 0), 0)
  put_str(mem, map, 0x6100U, "Y")
  assert_eq(vfs.fputs(mem, map, fa, 0x6100U), 0)
  ignore(vfs.fclose(fa))
  let fr2 = vfs.fopen(map, "t.txt", "rb")
  assert_eq(vfs.fread(mem, map, fr2, 0x8200U, 1, 10), 5)
  assert_eq(peek(mem, map, 0x8200U, 5), b"abcXY", msg="a 写恒追加")
}

///|
/// PR #280 审阅 P2-2 锚（2026-10-23）：a/a+「写恒末尾」的 **fwrite 通道**
///——同根因两点此前只锚了 vfs_append_bytes（fputs/fputc），fwrite 写前
/// 强制游标末尾零锚（注入 no-op 化 170/170 绿）。a 模式 fseek(0) 后 fwrite
/// 读回应为追加形态（覆盖头部=旧病）。
test "vfs_fwrite_append_writes_at_end" {
  let (map, mem, vfs) = vfs_fresh()
  ignore(vfs.inject_preset_file(map, mem, "t.bin", b"12345"))
  let buf = 0x8400U
  // fwrite 通道：a 模式 + fseek(0) + fwrite("AB") → 读回 12345AB（非 AB345）
  let fa = vfs.fopen(map, "t.bin", "a")
  assert_true(fa != 0U)
  assert_eq(vfs.fseek(mem, map, fa, 0, 0), 0)
  put_str(mem, map, 0x6300U, "AB")
  ignore(mem.write_bytes(map, buf, b"AB"))
  assert_eq(vfs.fwrite(mem, map, fa, buf, 1, 2), 2, msg="fwrite 追加写")
  ignore(vfs.fclose(fa))
  let fr = vfs.fopen(map, "t.bin", "rb")
  assert_eq(vfs.fread(mem, map, fr, 0x8500U, 1, 10), 7)
  assert_eq(
    peek(mem, map, 0x8500U, 7),
    b"12345AB",
    msg="a 模式 fseek 后 fwrite 仍恒末尾（审阅预演形态）",
  )
}

///|
/// PR #280 审阅 P3-4b 锚（2026-10-23）：`+` 族 b 位——rb+/r+b 的
/// is_text_mode=false（二进制：\n 不做 CRLF 伸缩）。M4 注入证明该面
/// 零锚（写穿 is_text 判定 170/170 绿）。
test "vfs_plus_modes_binary_flag" {
  let (map, mem, vfs) = vfs_fresh()
  ignore(vfs.inject_preset_file(map, mem, "t.bin", b"a"))
  // rb+ / r+b：二进制位——fputs 含 \n 的串不展开 \r\n
  for m in ["rb+", "r+b"] {
    let fd = vfs.fopen(map, "t.bin", m)
    assert_true(fd != 0U, msg="\{m} 打开")
    assert_eq(vfs.fseek(mem, map, fd, 1, 0), 0)
    put_str(mem, map, 0x6400U, "X")
    ignore(vfs.fputs(mem, map, fd, 0x6400U))
    ignore(vfs.fclose(fd))
  }
  let fr = vfs.fopen(map, "t.bin", "rb")
  let n = vfs.fread(mem, map, fr, 0x8600U, 1, 10)
  // 两次写各覆盖 [1]=X（同位）→ 终态 a X（二进制：无 \r 插入，长度 2）
  assert_eq(n, 2, msg="二进制模式无 CRLF 展开")
  assert_eq(peek(mem, map, 0x8600U, 2), b"aX")
}

///|
/// #95 VFS 列举口锚：`list_files` 返回 (文件名, 逻辑 size) 清单，
/// **插入序**（core `Map` 迭代序即插入序——预置在前、动态文件在后，
/// 与 serve 注入序一致）；remove 后退出列举。
test "vfs_list_files_insertion_order_and_sizes" {
  let (map, mem, vfs) = vfs_fresh()
  // 空表：列举口返回空清单（零文件会话态）
  assert_eq(vfs.list_files().length(), 0, msg="空 VFS 列举为空")
  // 预置注入两件（serve 同款清单/同款序）
  assert_true(vfs.inject_preset_file(map, mem, "test.txt", b"hello\nworld\n"))
  assert_true(vfs.inject_preset_file(map, mem, "numbers.txt", b"1 2 3 4 5\n"))
  // fopen("w") 建空文件（动态文件进列举——size 0）
  let fd = vfs.fopen(map, "out.txt", "w")
  assert_true(fd != 0U, msg="w 模式建文件")
  let listed = vfs.list_files()
  assert_eq(listed.length(), 3)
  // 插入序：预置在前（注入序），动态文件在后
  assert_eq(listed[0].0, "test.txt")
  assert_eq(listed[0].1, 12, msg="hello\\nworld\\n = 12 字节")
  assert_eq(listed[1].0, "numbers.txt")
  assert_eq(listed[1].1, 10, msg="1 2 3 4 5\\n = 10 字节")
  assert_eq(listed[2].0, "out.txt")
  assert_eq(listed[2].1, 0, msg="新建文件逻辑长度 0")
  // remove 后退出列举（其余保持原序）
  assert_eq(vfs.remove(map, "test.txt"), 0)
  let listed2 = vfs.list_files()
  assert_eq(listed2.length(), 2)
  assert_eq(listed2[0].0, "numbers.txt", msg="remove 不扰余下文件序")
  assert_eq(listed2[1].0, "out.txt")
}
