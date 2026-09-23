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
    Some(a) => a
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
  let p = @host.host_malloc(map, 8, 3).value.unwrap()
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
    c.value.unwrap(),
    16,
    6,
    6,
    6,
  )
  assert_true(rr.value is Some(_))
}
