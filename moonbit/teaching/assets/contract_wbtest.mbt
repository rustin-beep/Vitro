///|
/// trap_messages 契约锚（#60 批二，2026-10-10）：每条 placeholders 声明集
/// == template 实际 {x} 占位符集**双向相等**——写坏声明（漏/多/拼错）或
/// 写坏模板（占位符不在声明）即红。文案正文审计无字面花括号（冲突面）。
/// 占位符名合法性与 util.is_placeholder_name 同款（字面花括号段过滤）。
fn is_id_name(view : String) -> Bool {
  let n = view.length()
  if n == 0 {
    return false
  }
  let first = view[0]
  if !((first >= 97 && first <= 122) ||
    (first >= 65 && first <= 90) ||
    first == 95) {
    return false
  }
  for k in 1..<n {
    let c = view[k]
    let idc = (c >= 97 && c <= 122) ||
      (c >= 65 && c <= 90) ||
      (c >= 48 && c <= 57) ||
      c == 95
    if !idc {
      return false
    }
  }
  true
}

///|
test "trap_messages_placeholder_contract" {
  let bad : Array[String] = []
  for pair in trap_messages {
    let (key, msg) = pair
    // template 实际占位符集
    let actual : Array[String] = []
    let t = msg.template
    let n = t.length()
    let mut i = 0
    while i < n {
      if t[i] == 123 {
        let mut j = i + 1
        let mut closed = false
        while j < n {
          if t[j] == 125 {
            closed = true
            break
          }
          j = j + 1
        }
        if closed && j > i + 1 && is_id_name(t[i + 1:j].to_owned()) {
          let nm = t[i + 1:j].to_owned()
          // 同名占位符多次出现（如 bounds_array 的 {name}×2）按集合语义计
          if !actual.contains(nm) {
            actual.push(nm)
          }
          i = j + 1
        } else {
          i = i + 1
        }
      } else {
        i = i + 1
      }
    }
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
/// builtin_notes 契约锚（#60 批三段二）：键集 = 12 个 FILE/mem 特判臂
/// 名单（与 typeck 消费面对账——新增消费臂须同步此锚与真源）；
/// param_notes 与该函数参数位对位（长度 ≤ 参数数）。
test "builtin_notes_contract" {
  assert_eq(builtin_notes.length(), 12, msg="12 臂名单基线")
  for pair in builtin_notes {
    let (name, note) = pair
    assert_true(
      note.count_note.length() > 0 || note.param_notes.length() > 0,
      msg="\{name} 至少一项非空",
    )
  }
}

///|
/// suggestions 键基数锚（审阅处置批二 2026-10-10 P3）：45/12 两族有
/// assert_eq 基数锚、43 族此前只有 map.mbt 穷举 match（编译期名单闸，
/// 性质不同——防漏臂不防多臂溢出），补数据面基数断言。
test "suggestions_key_cardinality" {
  assert_eq(suggestion_map.size(), 43, msg="43 算法键基线")
}

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
