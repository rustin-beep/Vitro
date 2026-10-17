///|
/// trap_messages 契约锚（#60 批二，2026-10-10）：每条 placeholders 声明集
/// == template 实际 {x} 占位符集**双向相等**——写坏声明（漏/多/拼错）或
/// 写坏模板（占位符不在声明）即红。文案正文审计无字面花括号（冲突面）。
/// 提取器 = texts_io.mbt 的 extract_template_placeholders 单源
///（#130 批① 收编：契约锚与装载校验同一判据，分叉即互红）。

///|
test "trap_messages_placeholder_contract" {
  let bad : Array[String] = []
  for pair in trap_messages {
    let (key, msg) = pair
    // template 实际占位符集（texts_io.mbt 单源提取器——#130 批① 收编）
    let actual = extract_template_placeholders(msg.template)
    for p in msg.placeholders {
      if !actual.contains(p) {
        bad.push("\{key} 声明 \{p} 不在模板")
      }
    }
    for a in actual {
      if !msg.placeholders.contains(a) {
        bad.push("\{key} 模板 \{a} 未声明")
      }
    }
    if actual.length() != msg.placeholders.length() {
      bad.push(
        "\{key} 集大小不等（声明 \{msg.placeholders.length()} vs 模板 \{actual.length()}）",
      )
    }
  }
  assert_eq(bad.length(), 0, msg=bad.join("; "))
  assert_eq(
    trap_messages.length(),
    45,
    msg="45 键基线（trap 20 + hint 13 + bounds 12；增删键须同步此锚）",
  )
}

///|
/// builtin_notes 契约 + suggestions 键基数锚已随 #130 批③a 拆包迁
/// content_data/contract_wbtest.mbt（烘焙数据面基线随数据包走；本包
/// lean 载体默认空表，锚在此恒假）。

///|
/// is_id_name 行为锚（审阅处置批二 2026-10-10 P3）：本函数与
/// util/render.mbt 的 priv is_placeholder_name **手工同构**（两处须同步
/// 改——开 pub 复用需 surface 连坐，登记待拍板）；此处至少落行为真值锚，
/// 任一侧演化分叉时本锚守住占位符名合法集的既有语义。
test "is_id_name_behavior_anchor" {
  assert_true(is_id_name("addr"))
  assert_true(is_id_name("_x1"))
  assert_true(!is_id_name(""))
  assert_true(!is_id_name("1abc"))
  assert_true(!is_id_name("a-b"))
  assert_true(!is_id_name("a b"))
}
