///| S6 输出通道白盒锚点（`vitro/engine/host` 的 `OutputLog`）。
///
/// **锚点来源**：Rust `output.rs` 的文档化语义（三通道分流 / 16MB 预算 /
/// 64B 小段合并 / 环形丢弃保尾部 / note 不占预算不丢弃不入合并 / 截断注记
/// 只补一次 / O(1) 长度）逐条落成可断言用例；
/// 外加本批结构变更的两条**新锚**：
/// - **字节保真**：非 UTF-8 字节原样通过（`putchar(200)` → 1 字节 `0xC8`，
///   而非 String 化的 2 字节 `C3 88`——Rust 侧的预期 FAIL，正是 Bytes 化的收益）；
/// - **部分截除不做 UTF-8 边界对齐**（Bytes 没有"非法 UTF-8"这回事——这是与
///   Rust 的唯一语义差异，也是刻意差异）。

///|
/// `OutputKind` 的字符串往返（JSON 出口与文档口径）。
test "output_kind_roundtrip" {
  assert_eq(OutputKind::Stdout.as_str(), "stdout")
  assert_eq(OutputKind::Stderr.as_str(), "stderr")
  assert_eq(OutputKind::Note.as_str(), "note")
  guard OutputKind::parse("stdout") is Some(OutputKind::Stdout) else {
    fail("parse stdout")
  }
  guard OutputKind::parse("STDERR") is Some(OutputKind::Stderr) else {
    fail("大小写不敏感")
  }
  guard OutputKind::parse("notes") is Some(OutputKind::Note) else {
    fail("notes 别名")
  }
  assert_true(
    OutputKind::parse("display") is None,
    msg="display 不是单一片段的 kind",
  )
  assert_true(OutputKind::parse("bogus") is None)
}

///|
/// 三通道在源头分开：stdout 比对不受 stderr/note 污染（E-P1-5 的成立条件）。
test "three_channels_stay_separate" {
  let log = OutputLog::new()
  log.push_stdout(b"hello ")
  log.push_stdout(b"world\n")
  log.push_stderr(b"warn!\n")
  log.push_note_str("[引擎] 教学提示")
  assert_eq(
    log.join(OutputKind::Stdout),
    b"hello world\n",
    msg="stdout 通道必须纯净",
  )
  assert_eq(log.join(OutputKind::Stderr), b"warn!\n")
  assert_eq(
    log.join(OutputKind::Note),
    b"[引擎] 教学提示\n",
    msg="附注自动补 \\n",
  )
  // display：按写入顺序的交错视图（附注不在末尾时也不失真）
  assert_eq(log.join_all(), b"hello world\nwarn!\n[引擎] 教学提示\n")
  assert_eq(
    log.total_bytes(),
    log.join_all().length(),
    msg="O(1) 长度与拼接一致",
  )
  assert_eq(log.len_of(OutputKind::Stdout), 12)
  assert_eq(log.len(), 3)
  assert_true(log.is_empty() == false)
}

///|
/// 64B 小段合并：逐字符 putchar 形态合并进末尾同通道块（消除逐字符分配）；
/// 合并上限 4096 与"新段 >64B 独立成段"的边界。
test "small_writes_merge_into_last_chunk" {
  let log = OutputLog::new()
  // 逐字符 putchar 100 次：全部 ≤64B 且同通道 → 合并成一块
  for i = 0; i < 100; i = i + 1 {
    log.push_stdout(b"X")
  }
  assert_eq(log.len(), 1, msg="100 次 1 字节写必须合并成 1 块")
  assert_eq(log.total_bytes(), 100)
  assert_eq(log.join(OutputKind::Stdout).length(), 100)
  // 换 stderr：不同通道不合并 → 第二块
  log.push_stderr(b"E")
  assert_eq(log.len(), 2)
  // 附注不入合并：第三块，且不影响随后的 stdout 合并
  log.push_note_str("[n]")
  assert_eq(log.len(), 3)
  log.push_stdout(b"Y")
  assert_eq(log.len(), 4, msg="附注隔开末尾 stdout 块 ⇒ 新开一块")
  assert_eq(log.join(OutputKind::Stdout), b"X".repeat(100) + b"Y")
  // >64B 的新段独立成段
  log.push_stdout(b"Z".repeat(70))
  assert_eq(log.len(), 5)
  // 合并上限：把同通道累计逼近 4096 后，下一小触发新块
  let log2 = OutputLog::new()
  for i = 0; i < 63; i = i + 1 {
    log2.push_stdout(b".".repeat(64)) // 63×64 = 4032 ≤ 4096
  }
  assert_eq(log2.len(), 1, msg="累计未超上限必须合并成一块")
  log2.push_stdout(b".".repeat(64)) // 4032+64 = 4096 恰满
  assert_eq(log2.len(), 1, msg="恰满仍在一块内")
  log2.push_stdout(b"!") // 4096+1 > 4096 → 新块
  assert_eq(log2.len(), 2, msg="越过上限触发新块")
}

///|
/// **字节保真**（本批结构变更的收益）：非 UTF-8 字节原样通过。
///
/// Rust 现版 `push_stdout(impl Into<String>)` 会把 `putchar(200)` 编码成 2 字节
/// `C3 88`（`host/io.rs:346`）——这是**现版的预期 FAIL**，golden 侧
/// `engine_note_lookalike.c` 固化该口径。Bytes 化后按字节通过。
test "byte_fidelity_non_utf8_passthrough" {
  let log = OutputLog::new()
  log.push_stdout(b"\xC8") // putchar(200) 的真实字节
  assert_eq(log.join(OutputKind::Stdout), b"\xC8")
  assert_eq(log.total_bytes(), 1, msg="1 字节保真，不做 UTF-8 重编码")
  // 与合法 UTF-8 混合：各按字节拼
  log.push_stdout(b"ab")
  assert_eq(log.join(OutputKind::Stdout), b"\xC8ab")
}

///|
/// 环形丢弃：超预算丢最旧、保最新，附一条截断注记（截断可见）；丢弃只数
/// **程序输出**（note 不占预算、不动位置）。
test "budget_ring_drops_oldest_keeps_tail" {
  let log = OutputLog::new()
  log.set_budget(10)
  log.push_note_str("[头]") // 5 字节，不占预算
  log.push_stdout(b"0123456789") // 恰 10
  log.push_stdout(b"ABCD") // 合并后 14 字节 > 预算 10
  // 最旧的程序块（"0123456789" + "ABCD" 合并成的 14 字节块）被截头 4 字节保尾部
  assert_eq(log.dropped_bytes(), 4)
  assert_eq(
    log.join(OutputKind::Stdout),
    b"456789ABCD",
    msg="丢最旧保最新（14 − 4 = 10）",
  )
  // 截断注记只补一次且**位置不被程序输出吃掉**（note 原地不动）
  let notes = log.chunks_of(OutputKind::Note)
  assert_eq(notes.length(), 2, msg="原注 + 截断注记")
  assert_true(notes[1].length() > 0)
  assert_true(log.has_note(notes[1]), msg="has_note 命中")
  // 再压：旧的程序块整块被丢、新块截头保尾；截断注记不再重复
  log.push_stdout(b"01234567890123456") // 17 ≤ 64 → 合并进待封口块后一起被裁
  assert_eq(
    log.chunks_of(OutputKind::Note).length(),
    2,
    msg="截断注记只补一次",
  )
  assert_eq(
    log.join(OutputKind::Stdout),
    b"7890123456",
    msg="丢整旧块 + 截新块头 7 字节",
  )
  assert_eq(
    log.total_bytes() - log.len_of(OutputKind::Note),
    10,
    msg="程序输出不超过预算",
  )
}

///|
/// **部分截除不做 UTF-8 边界对齐**（与 Rust 的唯一语义差异，刻意差异）：
/// 切点落在多字节字符内部也按字节截（`Bytes` 没有非法 UTF-8）。
test "partial_trim_is_byte_exact_no_utf8_alignment" {
  let log = OutputLog::new()
  log.set_budget(5)
  // "中文" = 6 字节 UTF-8；整块 > 预算 ⇒ 截头 1 字节，落在"中"的第二字节
  log.push_stdout(b"\xE4\xB8\xAD\xE6\x96\x87")
  assert_eq(
    log.join(OutputKind::Stdout),
    b"\xB8\xAD\xE6\x96\x87",
    msg="字节级截头（Rust 会因 char boundary 把切点后推，这是刻意的差异）",
  )
  assert_eq(log.len_of(OutputKind::Stdout), 5)
}

///|
/// **note 独立预算**（批五 note 无界治理）：超限丢最旧 note、保最新，附一条
/// 截断注记；note 丢弃不触碰程序块（反向亦然——程序输出的裁剪从不动 note）。
test "note_budget_ring_drops_oldest_keeps_tail" {
  let log = OutputLog::new()
  log.set_note_budget(10)
  log.push_stdout(b"prog-stdout")
  log.push_note_str("AAAA") // 5 字节（补 \n）
  log.push_note_str("BBBB") // 5 字节，累计 10 恰满
  assert_eq(log.note_dropped_bytes(), 0)
  log.push_note_str("C") // +2 → 12 > 10 ⇒ 最旧 note（"AAAA\n"）截头 2 字节 → 10 ≤ 10
  assert_eq(
    log.note_dropped_bytes(),
    2,
    msg="丢最旧 note 的超出部分（2 字节）",
  )
  assert_true(
    log.has_note(@utf8.encode("AA\n")),
    msg="最旧附注被截头（剩 \"AA\\n\"——与程序块同款的部分截除）",
  )
  assert_true(
    log.has_note(@utf8.encode("BBBB\n")),
    msg="较新附注原样保留",
  )
  assert_true(log.has_note(@utf8.encode("C\n")), msg="最新附注原样保留")
  assert_true(
    log.has_note(
      @utf8.encode(
        "[引擎] 引擎附注超出 10 字节预算，更早的附注已截断丢弃，仅保留最新部分。\n",
      ),
    ),
    msg="截断注记可见（与程序输出截断注记同款语义）",
  )
  // 截断注记只补一次：连环再丢（小预算下注记自身也会被环形语义吃掉，
  // 但不得出现第二条注记——核心不变量是「至多一条」）
  log.push_note_str("DDDD") // +5 触发连环丢
  log.push_note_str("E")
  assert_true(
    note_truncation_marker_count(log) <= 1,
    msg="截断注记至多一条（置位后不再重复追加）",
  )
  // 程序块不受 note 丢弃影响
  assert_eq(log.join(OutputKind::Stdout), b"prog-stdout")
  // clear 复位丢弃记账（预算配置保留）
  log.clear()
  assert_eq(log.note_dropped_bytes(), 0)
  assert_eq(
    log.note_budget(),
    10,
    msg="clear 保留预算配置（与程序预算同款）",
  )
}

///|
/// note 截断注记段的前缀匹配计数（`Bytes` 无 startsWith——逐字节比对）。
fn note_truncation_marker_count(log : OutputLog) -> Int {
  let marker = @utf8.encode("[引擎] 引擎附注超出")
  let m = marker.length()
  let mut count = 0
  for c in log.chunks_of(OutputKind::Note) {
    let mut hit = c.length() >= m
    if hit {
      for i = 0; i < m; i = i + 1 {
        if c[i] != marker[i] {
          hit = false
          break
        }
      }
    }
    if hit {
      count = count + 1
    }
  }
  count
}

///|
/// 单条 note 超预算：截头留尾（防御形态——真实 8MB 预算下单条引擎附注
/// 不可达，此锚钉住与程序块同款的部分截除语义）。
test "note_budget_single_chunk_trims_head" {
  let log = OutputLog::new()
  log.set_note_budget(5)
  log.push_note_str("0123456789") // 11 字节 > 5 ⇒ 截头 6 字节保尾部
  assert_eq(log.note_dropped_bytes(), 6)
  assert_eq(
    log.len_of(OutputKind::Note) > 5,
    true,
    msg="截后 note 计数只含保留字节",
  )
  assert_true(
    log.has_note(@utf8.encode("6789\n")),
    msg="截头 6 字节后保留尾部（\"6789\\n\"——含补齐的段落换行）",
  )
}

///|
/// O(1) 长度口径与 clear 复位。
test "counters_and_clear" {
  let log = OutputLog::new()
  assert_true(log.is_empty())
  log.push_stdout(b"abc")
  log.push_stderr(b"de")
  log.push_note_str("n")
  assert_eq(log.total_bytes(), 7) // 3 + 2 + 2(附注补 \n)
  assert_eq(log.len_of(OutputKind::Stdout), 3)
  assert_eq(log.len_of(OutputKind::Stderr), 2)
  assert_eq(log.len_of(OutputKind::Note), 2)
  assert_eq(log.budget(), OUTPUT_LOG_BUDGET)
  log.clear()
  assert_true(log.is_empty())
  assert_eq(log.total_bytes(), 0)
  assert_eq(log.dropped_bytes(), 0)
  assert_eq(log.join_all().length(), 0)
}
