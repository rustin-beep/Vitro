// 词汇表白盒锚（S7 批一号）：classify 3 锚照搬 vocabulary.rs tests 模块
// + 14 条词汇表三元组（id/domain/status）硬编码对账锚——与 Rust 源常量表
// 任一侧漂移即红。

///|
/// 照搬 Rust：example 取首个 '/' 或 '（' 前的片段并 trim，保证单一样本。
fn example_first_segment(example : String) -> String {
  let first = example.split("/").to_array()[0]
  let second = first.split("（").to_array()[0]
  second.trim().to_owned()
}

///|
test "classify_covers_every_active_kind" {
  for k in semantic_label_vocabulary() {
    let sample = example_first_segment(k.example)
    assert_eq(
      classify(sample),
      Some(k.id),
      msg="词汇表条目 \{k.id} 的 example `\{sample}` 无法归类——example 与 classify 口径不一致",
    )
  }
}

///|
test "classify_rejects_unknown_and_empty" {
  assert_eq(classify(""), None, msg="空串 = 无标签，不是词汇条目")
  assert_eq(
    classify("循环边界"),
    None,
    msg="未登记形态必须归类失败（防线信号）",
  )
  assert_eq(
    classify("调用 "),
    None,
    msg="空函数名的调用是退化形态，不予放行",
  )
}

///|
test "ids_are_unique" {
  let ids : Array[String] = []
  for k in semantic_label_vocabulary() {
    ids.push(k.id)
  }
  let n = ids.length()
  let seen : Set[String] = Set([])
  for id in ids {
    seen.add(id)
  }
  assert_eq(seen.length(), n, msg="词汇表 id 重复")
}

///|
test "vocabulary_table_matches_rust_source" {
  // 对账锚：14 条 (id, domain, status) 三元组硬编码对齐
  // native/src/unified/vocabulary.rs SEMANTIC_LABEL_VOCABULARY
  let expected : Array[(String, String, String)] = [
    ("swap", "c", "active"),
    ("recursive_call", "c", "active"),
    ("call", "c", "active"),
    ("generic_call", "c", "active"),
    ("loop", "c", "active"),
    ("return", "c", "active"),
    ("heap_alloc", "c", "active"),
    ("heap_free", "c", "active"),
    ("io", "c", "active"),
    ("line_fallback", "c", "active"),
    ("throw", "csharp", "reserved"),
    ("unwind", "csharp", "reserved"),
    ("catch_enter", "csharp", "reserved"),
    ("finally", "csharp", "reserved"),
  ]
  let vocab = semantic_label_vocabulary()
  assert_eq(vocab.length(), 14, msg="词汇表必须恰 14 条")
  for i, t in expected {
    assert_eq(vocab[i].id, t.0, msg="第 \{i} 条 id 与 Rust 源漂移")
    assert_eq(vocab[i].domain, t.1, msg="第 \{i} 条 domain 漂移")
    assert_eq(vocab[i].status, t.2, msg="第 \{i} 条 status 漂移")
    if t.2 == "active" {
      assert_eq(vocab[i].since, "-", msg="active 条目 since 恒 '-'")
    }
  }
  // reserved 条目 since = 激活批次（CS3b）
  for k in vocab {
    if k.status == "reserved" {
      assert_eq(k.since, "CS3b", msg="reserved 条目 since = CS3b")
    }
  }
}

///|
test "vocabulary_json_shape" {
  let json = vocabulary_json()
  assert_false(json.contains(": "), msg="紧凑形态不得含键值空格")
  assert_true(json.contains("\"schema\":\"v0.1\""))
  assert_true(json.contains("\"discipline\":\"词汇只增不改"))
  assert_true(json.contains("\"labels\":["))
  assert_true(
    json.contains(
      "{\"id\":\"swap\",\"domain\":\"c\",\"template\":\"交换 arr[{i}]↔arr[{j}]\"",
    ),
    msg="条目字段序 = id/domain/template 在前",
  )
}

///|
test "kind_by_id_roundtrip" {
  // classify 的逆查：active 域抽两条 + 未知 id
  assert_true(kind_by_id("swap") is Some(_))
  assert_true(kind_by_id("finally") is Some(_))
  assert_true(kind_by_id("not_a_kind") is None)
  match kind_by_id("loop") {
    Some(k) => assert_eq(k.domain, "c")
    None => fail("loop 必在词汇表内")
  }
}
