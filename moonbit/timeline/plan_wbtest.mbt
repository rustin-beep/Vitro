// TimelinePlan v0.1 白盒锚（#470 批一）：结构对齐 / 归属判据 / 存在性纪律 /
// 越界过滤（旧规则等价面）/ J9 错位证红。

///|
fn tlev(ty : Int32, e0 : Int32, e1 : Int32, context : String) -> FrameEvent {
  { ty, e0, e1, e2: -1, context, }
}

///|
fn tlfv(
  label : String,
  arrays : Array[(String, Int32)],
  events : Array[FrameEvent],
) -> FrameView {
  {
    code_line: 1,
    func_name: "main",
    semantic_label: label,
    vis_events: events,
    arrays,
  }
}

///|
test "timeline_plan_steps_align_with_frames" {
  let frames = [
    tlfv("", [("a", 5)], []),
    tlfv("交换 a[0]↔a[1]", [("a", 5)], [tlev(2, 0, 1, "a[j]:a[j + 1]")]),
    tlfv("循环 i=0", [("a", 5)], []),
  ]
  let p = plan(frames)
  assert_eq(p.pv, PLAN_PV, msg="pv 恒 1")
  assert_eq(p.steps.length(), 3, msg="steps 与选中帧零基同构")
  assert_eq(validate(p, 3), Ok(()), msg="对齐校验绿")
  assert_true(p.steps[0].sw is None, msg="无事件帧无 sw")
  assert_true(p.steps[0].cap is None, msg="空标签无 cap")
}

///|
test "timeline_swap_context_attribution_and_order" {
  // e0/e1 反序输入 → 输出升序（旧规则 lo/hi 同款）
  let fr = tlfv("交换 a[0]↔a[1]", [("a", 5)], [
    tlev(2, 3, 1, "a[j]:a[j + 1]"),
  ])
  let p = plan([fr])
  match p.steps[0].sw {
    Some(sw) => {
      assert_eq(sw.name, "a", msg="context 点名的真实数组名")
      assert_eq(sw.i, 1, msg="升序下界")
      assert_eq(sw.j, 3, msg="升序上界")
    }
    None => fail("合法交换事件须产 sw")
  }
}

///|
test "timeline_swap_no_context_is_not_guessed" {
  // context 空 = 归属缺失——不产 sw（旧规则 ctxMentions 恒假，同语义）
  let fr = tlfv("函数调用", [("a", 5)], [tlev(2, 0, 1, "")])
  assert_true(plan([fr]).steps[0].sw is None, msg="无 context 不猜")
}

///|
test "timeline_swap_ambiguous_context_is_not_guessed" {
  // 一次交换点名两个数组 = v0.1 单 sw 装不下的歧义形态——不猜（丢 sw）
  let fr = tlfv("交换", [("a", 5), ("b", 5)], [tlev(2, 0, 1, "a[j]:b[j + 1]")])
  assert_true(plan([fr]).steps[0].sw is None, msg="归属歧义不产 sw")
}

///|
test "timeline_swap_multi_array_attribution_by_context" {
  // 多数组在场：按 context 归属到 b（不得按名字顺序猜 a）
  let fr = tlfv("交换", [("a", 5), ("b", 5)], [tlev(2, 2, 3, "b[j]:b[j + 1]")])
  match plan([fr]).steps[0].sw {
    Some(sw) => {
      assert_eq(sw.name, "b", msg="多数组按 context 归属")
      assert_eq(sw.i, 2, msg="下标来自 extras")
      assert_eq(sw.j, 3, msg="下标来自 extras")
    }
    None => fail("唯一归属须产 sw")
  }
}

///|
test "timeline_swap_out_of_bounds_dropped" {
  // 旧规则 `hi >= len` 丢弃（bubble_sort 实测 2 帧 a[4]↔a[5] 数组长 5）——
  // 生成器同款过滤，否则交换帧集合 56 vs 54 分叉
  let fr = tlfv("函数调用", [("a", 5)], [tlev(2, 4, 5, "a[j]:a[j + 1]")])
  assert_true(plan([fr]).steps[0].sw is None, msg="越界交换不产 sw")
}

///|
test "timeline_swap_degenerate_indices_dropped" {
  let same = tlfv("交换", [("a", 5)], [tlev(2, 2, 2, "a[j]:a[j + 1]")])
  assert_true(plan([same]).steps[0].sw is None, msg="i==j 丢")
  let neg = tlfv("交换", [("a", 5)], [tlev(2, -1, 0, "a[j]:a[j + 1]")])
  assert_true(
    plan([neg]).steps[0].sw is None,
    msg="负下标（-1 哨兵）丢",
  )
}

///|
test "timeline_cap_absent_on_empty_label_no_empty_string" {
  // 存在性纪律：空标签 = 无 cap，禁 {"t":""} 占位
  let fr = tlfv("", [("a", 5)], [tlev(2, 0, 1, "a[j]:a[j + 1]")])
  let p = plan([fr])
  assert_true(p.steps[0].cap is None, msg="空标签无 cap")
  let text = plan_json(p).stringify()
  assert_false(text.contains("\"t\""), msg="不产空 t 键")
  assert_false(text.contains("\"cap\""), msg="不产空 cap")
}

///|
test "timeline_cap_weight_and_duration_tiers" {
  // 交换帧 w=2 / dur=1；常规字幕帧 w=1 / dur=0（v0.2 预留 3/2 档）
  let swap_fr = tlfv("交换 a[0]↔a[1]", [("a", 5)], [
    tlev(2, 0, 1, "a[j]:a[j + 1]"),
  ])
  let plain_fr = tlfv("循环 i=0", [("a", 5)], [])
  let p = plan([swap_fr, plain_fr])
  match p.steps[0].cap {
    Some(c) => {
      assert_eq(c.w, 2, msg="交换帧量感档 2")
      assert_eq(c.dur, 1, msg="交换帧持续档 1")
      assert_eq(c.t, "交换 a[0]↔a[1]", msg="字幕原文透传")
    }
    None => fail("非空标签须产 cap")
  }
  match p.steps[1].cap {
    Some(c) => {
      assert_eq(c.w, 1, msg="常规帧量感档 1")
      assert_eq(c.dur, 0, msg="常规帧持续档 0")
    }
    None => fail("非空标签须产 cap")
  }
}

///|
test "timeline_validate_detects_step_misalignment" {
  // J9：步骤错位必红——① 帧数不匹配；② 少一步的 plan 同样红
  let p = plan([tlfv("", [("a", 5)], []), tlfv("", [("a", 5)], [])])
  let e1 = validate(p, 3)
  assert_true(
    match e1 {
      Err(m) => m.contains("步骤错位")
      Ok(_) => false
    },
    msg="steps=2/frames=3 须红",
  )
  ignore(p.steps.pop())
  let e2 = validate(p, 2)
  assert_true(
    match e2 {
      Err(m) => m.contains("步骤错位")
      Ok(_) => false
    },
    msg="plan 丢步须红（J9 埋雷形态）",
  )
}

///|
test "timeline_plan_json_shape_and_byte_order" {
  // 字节确定性：pv→steps、sw→cap、name→i→j、t→w→dur 键序固化
  let frames = [
    tlfv("交换 a[0]↔a[1]", [("a", 5)], [tlev(2, 0, 1, "a[j]:a[j + 1]")]),
    tlfv("", [("a", 5)], []),
  ]
  let text = plan_json(plan(frames)).stringify()
  assert_eq(
    text,
    "{\"pv\":1,\"steps\":[{\"sw\":{\"name\":\"a\",\"i\":0,\"j\":1},\"cap\":{\"t\":\"交换 a[0]↔a[1]\",\"w\":2,\"dur\":1}},{}]}",
    msg="v0.1 信封逐字节形态",
  )
}

///|
test "timeline_context_mentions_identifier_boundary" {
  // 旧规则 regex `(^|[^\w.])name\s*\[` 的引擎侧等价：
  assert_true(context_mentions("a[j]:a[j + 1]", "a"), msg="基本形态")
  assert_true(context_mentions("a [j]", "a"), msg="名字与 [ 间空白")
  assert_true(context_mentions("x:a[j]", "a"), msg="非标识符前缀 :")
  assert_false(context_mentions("obj.arr[j]", "arr"), msg="成员访问不算")
  assert_false(context_mentions("barr[j]", "arr"), msg="标识符内含不算")
  assert_false(context_mentions("arrj]", "arr"), msg="缺 [ 不算")
  assert_false(context_mentions("", "arr"), msg="空串不算")
}

///|
test "timeline_swap_duplicate_snapshot_names_not_ambiguous" {
  // 全局数组 + 数组形参解引用视图可能同名双发（vm/observe 不去重）：
  // 重名按 Map 语义折叠为一个名字（后写覆盖长度），不得当歧义丢弃。
  let dup = tlfv("交换", [("arr", 4), ("arr", 6)], [
    tlev(2, 0, 5, "arr[j]:arr[j + 1]"),
  ])
  match plan([dup]).steps[0].sw {
    Some(sw) => {
      assert_eq(sw.name, "arr", msg="重名折叠后归属唯一")
      assert_eq(sw.i, 0, msg="下界")
      assert_eq(sw.j, 5, msg="j=5 合法（后写长度 6 生效）")
    }
    None => fail("同名双发不得当歧义——须产 sw")
  }
  // 后写覆盖（非取最大）：后一条长度 4 时 j=5 越界丢弃
  let dup2 = tlfv("交换", [("arr", 6), ("arr", 4)], [
    tlev(2, 0, 5, "arr[j]:arr[j + 1]"),
  ])
  assert_true(
    plan([dup2]).steps[0].sw is None,
    msg="长度后写覆盖：末条 4 生效，j=5 越界",
  )
}
