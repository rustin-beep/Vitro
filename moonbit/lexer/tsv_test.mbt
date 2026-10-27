///|
/// #338 批四（2026-10-27）：tsv.mbt 白盒转黑盒锚——此前 0/17 零单测域
/// 执行（TSV 形态只经差分驱动间接锁）。锚面：转义表四映射（`\\`/`\n`/
/// `\t`/`\r`）、L1/L2 行列差异（L1 带 byte_off 尾列）、尾行 count/errors
/// 形态。转义契约 = 两侧逐字节一致的差分锚点出口（文件头注）。

///|
/// 首行（首个 \n 前；无 \n 则整串）。
fn first_line(s : String) -> String {
  let buf = StringBuilder()
  for ch in s {
    if ch == '\n' {
      break
    }
    buf.write_char(ch)
  }
  buf.to_string()
}

///|
fn count_char(s : String, target : Char) -> Int32 {
  let mut n = 0
  for ch in s {
    if ch == target {
      n = n + 1
    }
  }
  n
}

///|
test "dump_raw_tsv_escape_and_tail" {
  // 字符串字面量解码值含真 tab/反斜杠——TSV text 列须转义回两字符形态
  //（逐字节可比契约）
  let r = @lexer.tokenize_raw("const char *s = \"a\\tb\\\\c\";\n")
  let tsv = @lexer.dump_raw_tsv(r)
  // 转义表：真 tab → `\t` 文本、`\` → `\\`
  assert_true(
    tsv.contains("a\\tb\\\\c"),
    msg="text 列转义表未生效: \{tsv}",
  )
  // 尾行三段形态（count/errors/warnings）——raw 口径 warnings 恒 0
  assert_true(tsv.contains("\ncount="), msg="尾行须独立成行: \{tsv}")
  assert_true(tsv.contains("errors=0") && tsv.contains("warnings=0"))
  // 每数据行 6 列（L1 含 byte_off 尾列）
  let first = first_line(tsv)
  assert_eq(count_char(first, '\t') + 1, 6, msg="L1 行须 6 列: \{first}")
}

///|
test "dump_lex_tsv_l2_no_byte_off" {
  let r = @lexer.tokenize("int x;\n")
  let tsv = @lexer.dump_lex_tsv(r)
  let first = first_line(tsv)
  // L2 五列：index/Ty/text/line/col（无 byte_off）
  assert_eq(count_char(first, '\t') + 1, 5, msg="L2 行须 5 列: \{first}")
  assert_true(
    tsv.contains("warnings=0"),
    msg="lex 口径 warnings 来自 result",
  )
}

///|
test "dump_raw_tsv_error_count" {
  // 非法字符进 errors → 尾行 errors 计数如实（禁粉饰）
  let r = @lexer.tokenize_raw("int $x;\n")
  let tsv = @lexer.dump_raw_tsv(r)
  assert_true(tsv.contains("errors=1"), msg="errors 计数须如实: \{tsv}")
}
