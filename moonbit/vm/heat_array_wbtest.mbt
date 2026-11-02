///| P0b 观测降本锚（#176 §6-P0b，2026-11-02）——heatmap 定长数组化 +
/// vis 事件行索引化的行为不变量（重构等价锚 + 深拷贝防别名锚）。
///
/// P0b 是零行为变更的重构：锚锁的是新结构下的语义等价（与原 Map/线性扫
/// 形态逐字节一致）；`p0b_heat_snapshot_deep_copy_no_alias` 是防别名锚
/// （restore 若共享 FixedArray 引用即红——突变证红见批次报告）。

///|
/// 锚一：热力图惰性扩容 + 读口边界（未命中/远超容量/负行号 → 0，与原 Map
/// None→0 等价）；再扩容保留旧值。
test "p0b_heat_lazy_growth_and_read_bounds" {
  let vm = VitroVM::new()
  assert_eq(vm.heatmap.length(), 0)
  // 零装载直接记行 5（load_program 直装通道——无 setup 期行号上界）
  vm.ensure_heat(5)
  vm.heatmap[5] = vm.heatmap[5] + 1UL
  assert_eq(vm.heatmap_count_at(5), 1UL)
  assert_eq(vm.heatmap_count_at(2), 0UL, msg="未命中行 = 0")
  assert_eq(vm.heatmap_count_at(1000000), 0UL, msg="远超容量读不崩 = 0")
  assert_eq(vm.heatmap_count_at(-3), 0UL, msg="负行号 = 0")
  // 再扩容（倍增支）保留旧值
  vm.ensure_heat(100)
  assert_eq(vm.heatmap_count_at(5), 1UL, msg="扩容保留旧计数")
  vm.heatmap[100] = vm.heatmap[100] + 1UL
  assert_eq(vm.heatmap_count_at(100), 1UL)
  // reset 清空（长度归零形态）
  vm.reset()
  assert_eq(vm.heatmap.length(), 0)
  assert_eq(vm.heatmap_count_at(5), 0UL)
}

///|
/// 锚二：快照/restore 深拷贝防别名——restore 后自增不得回写 snap
/// （FixedArray 引用语义下共享引用即污染检查点；time_travel 复用面）。
test "p0b_heat_snapshot_deep_copy_no_alias" {
  let vm = VitroVM::new()
  vm.ensure_heat(3)
  vm.heatmap[3] = 7UL
  let snap = vm.snapshot()
  // churn + 恢复
  vm.heatmap[3] = 99UL
  vm.restore(snap)
  assert_eq(vm.heatmap_count_at(3), 7UL)
  // 防别名：恢复后自增，snap 必须仍是快照时刻值
  vm.heatmap[3] = vm.heatmap[3] + 1UL
  assert_eq(vm.heatmap_count_at(3), 8UL)
  assert_eq(
    snap.heatmap[3],
    7UL,
    msg="restore 深拷贝——自增不得回写快照",
  )
}

///|
/// 锚三：vis 行索引与线性扫逐字节等价——同命中多条按登记序入队；
/// 未登记行不入队；ty=2 命中 swap extras（无帧 → -1 哨兵）。
test "p0b_vis_lines_index_multi_entry_order" {
  let vm = VitroVM::new()
  vm.set_vis_event_lines([(4, 1, "a"), (4, 2, "b"), (9, 1, "c")])
  // 派生索引在位（行 4 两条 / 行 9 一条 / 行 5 无）
  assert_eq(vm.vis_events_by_line.get(4).unwrap().length(), 2)
  assert_eq(vm.vis_events_by_line.get(9).unwrap().length(), 1)
  assert_true(vm.vis_events_by_line.get(5) is None)
  vm.load_program(
    code_of([instr(StepEvent, 4), instr(StepEvent, 9), instr(StepEvent, 5)]),
  )
  assert_true(vm.step() is Ok) // StepEvent 4 → 命中两条按登记序
  assert_eq(vm.vis_event_queue.length(), 2)
  assert_eq(vm.vis_event_queue[0].context, "a")
  assert_eq(vm.vis_event_queue[0].ty, 1)
  assert_eq(vm.vis_event_queue[1].context, "b")
  assert_eq(vm.vis_event_queue[1].ty, 2)
  assert_eq(
    vm.vis_event_queue[1].extra0,
    -1,
    msg="ty=2 extras 哨兵（无帧）",
  )
  assert_true(vm.step() is Ok) // StepEvent 9 → 命中一条
  assert_eq(vm.vis_event_queue.length(), 3)
  assert_eq(vm.vis_event_queue[2].context, "c")
  assert_true(vm.step() is Ok) // StepEvent 5 → 未登记不入队
  assert_eq(vm.vis_event_queue.length(), 3)
}

///|
/// PR #439 审阅 P1-1 锚（2026-11-02）：reset 必须逐字段归零教学观测面——
/// P0b 改写 reset 时相邻一行 `snapshot_vars.clear()` 被一并吞掉（无限循环诊断
/// 的变量基线跨程序残留：serve 编译新程序 → run 撞步数墙，`[inspect]` 文案
/// 把上一程序的基线当本程序的——同名变量 + max_steps < 100_000 即命中，
/// 双臂探针实锤）。预置非零 → reset → 逐字段断言，任一字段漏清即红。
test "p1_reset_clears_every_observation_field" {
  let vm = VitroVM::new()
  // 预置：观测面全部非零
  vm.ensure_heat(3)
  vm.heatmap[3] = 17UL
  vm.snapshot_vars.set("i", 999UL)
  vm.last_snapshot_step = 40
  vm.last_accessed_vars.push(VariableAccess::{ name: "i", access_type: Read, })
  vm.vis_event_queue.push(VisEventData::{
    ty: 1,
    line: 3,
    extra0: 0,
    extra1: 0,
    extra2: 0,
    context: "c",
  })
  vm.set_vis_event_lines([(3, 1, "c")])
  vm.breakpoints.add(5)
  vm.current_line = 12
  vm.step_event_hit = true
  vm.paused = true
  vm.reset()
  assert_eq(vm.heatmap.length(), 0, msg="heatmap")
  assert_eq(
    vm.snapshot_vars.length(),
    0,
    msg="snapshot_vars（P1-1：曾漏清）",
  )
  assert_eq(vm.last_snapshot_step, 0, msg="last_snapshot_step")
  assert_eq(vm.last_accessed_vars.length(), 0, msg="last_accessed_vars")
  assert_eq(vm.vis_event_queue.length(), 0, msg="vis_event_queue")
  assert_eq(vm.vis_event_lines.length(), 0, msg="vis_event_lines")
  assert_eq(vm.vis_events_by_line.length(), 0, msg="vis_events_by_line")
  assert_eq(vm.breakpoints.length(), 0, msg="breakpoints")
  assert_eq(vm.current_line, 0, msg="current_line")
  assert_false(vm.step_event_hit, msg="step_event_hit")
  assert_false(vm.paused, msg="paused")
  assert_true(
    vm.observe,
    msg="observe 非执行态——reset 不碰且恒 true",
  )
}
