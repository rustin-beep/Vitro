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
  addr : UInt,
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
  assert_eq(vfs.feof(fd), 1, msg="读满即 EOF")
  // 尺寸链防护：size*nmemb 超 MEM_SIZE → 0
  assert_eq(vfs.fread(mem, map, fd, buf, 0x100000, 16), 0)
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
  // 未知模式串 → 0
  assert_eq(vfs.fopen(map, "t.txt", "r+"), 0U)
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
  assert_eq(vfs.rename("a.txt", "b.txt"), 0)
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
  assert_eq(vfs.rename("no.txt", "z.txt"), -1)
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
    b"to-erropen failed: Error\n",
    msg="stderr 追加",
  )
  // perror(NULL) 形态：空前缀（空串）→ "Error\n"
  put_bytes(mem, map, 0x6300U, b"\x00", false)
  ignore(host_perror(map, mem, log, 0x6300U))
  assert_true(
    @utf8.encode(log.join(OutputKind::Stderr).to_unchecked_string()).length() >
    0,
  )
}

///|
test "file_misc_handlers_shape" {
  let (map, mem, vfs) = vfs_fresh()
  ignore(vfs.inject_preset_file(map, mem, "m.txt", b"ab"))
  put_str(mem, map, 0x6100U, "m.txt")
  // fopen 拿 FILE*
  put_str(mem, map, 0x6000U, "r")
  let fp = host_fopen(map, mem, vfs, 0x6100U, 0x6000U, 1).value
    .unwrap()
    .to_uint()
  // fwrite 写回读模式 → 0（Read 拒写）
  assert_eq(host_fwrite(map, mem, vfs, 0x8000U, 1, 1, fp).value, Some(0UL))
  // fgets / fgetc / feof / ftell / fseek / fflush / rewind / clearerr
  assert_eq(host_fgets(map, mem, vfs, 0x8000U, 10, fp).value, Some(0x8000UL))
  assert_eq(
    host_fgetc(map, mem, vfs, fp).value,
    Some(0xFFFFFFFFFFFFFFFFUL),
    msg="EOF -1",
  )
  assert_eq(host_feof(map, mem, vfs, fp).value, Some(1UL))
  assert_eq(
    host_fseek(map, mem, vfs, fp, 0, 0).value,
    Some(0UL),
    msg="rewind 后可 seek",
  )
  assert_eq(host_ftell(map, mem, vfs, fp).value, Some(0UL))
  assert_eq(host_fflush(map, mem, vfs, fp).value, Some(0UL))
  ignore(host_rewind(map, mem, vfs, fp))
  assert_eq(host_feof(map, mem, vfs, fp).value, Some(0UL))
  ignore(host_clearerr(map, mem, vfs, fp))
  // fputc 读模式 → -1
  assert_eq(host_fputc(map, mem, vfs, 66, fp).value, Some(0xFFFFFFFFFFFFFFFFUL))
  // remove / rename
  assert_eq(host_remove(map, mem, vfs, 0x6100U).value, Some(0UL))
  put_str(mem, map, 0x6200U, "n.txt")
  ignore(vfs.inject_preset_file(map, mem, "n.txt", b"z"))
  assert_eq(host_rename(map, mem, vfs, 0x6200U, 0x6300U).value, Some(0UL))
}
