///| L7 执行层·VM 域·executor：**教学观测族**（Rust `executor/debug.rs`
/// 照搬）。

///|
/// 教学观测族（StepEvent / TrapBounds / TrapBoundsVla）。
///
/// - `StepEvent`：current_line 更新 + 断点暂停 + vis 事件命中行登记
///   （环形 `VIS_EVENT_LIMIT` 丢最旧保最新）；
/// - `TrapBounds`：operand ≥ 0 = 符号表下标（数组名/长度），< 0 =
///   `-operand` 为长度（字面量形状）；
/// - `TrapBoundsVla`：零发射死码（总计划 §5）——fail loud 登记。
fn VitroVM::execute_debug(
  self : VitroVM,
  op : @opcode.OpCode,
  operand : Int,
  line : Int,
  column : Int,
) -> StepResult? {
  match op {
    StepEvent => {
      self.current_line = operand
      if self.breakpoints.contains(operand) {
        self.paused = true
      }
      self.step_event_hit = true
      for entry in self.vis_event_lines {
        if entry.0 == operand {
          self.vis_event_queue.push(VisEventData::{
            ty: entry.1,
            line: operand,
            extra0: 0,
            extra1: 0,
            extra2: 0,
            context: entry.2,
          })
        }
      }
      // 环形丢最旧（U2#8：超上限 drain 头部 overflow 条）
      let overflow = self.vis_event_queue.length() - VIS_EVENT_LIMIT
      if overflow > 0 {
        for k = 0; k < overflow; k = k + 1 {
          ignore(self.vis_event_queue.remove(0))
        }
      }
      if self.paused {
        return Some(Paused)
      }
      None
    }
    TrapBounds => {
      let index = if self.stack.length() > 0 {
        self.stack[self.stack.length() - 1].reinterpret_as_int64()
      } else {
        self.trap("TrapBounds: 值栈为空，无法获取索引", line, column)
        return Some(Trap)
      }
      let mut name = "数组"
      let mut size = 0
      if operand >= 0 {
        if operand < self.symbols.length() {
          let sym = self.symbols[operand]
          name = sym.name
          size = sym.ty.array_size()
        }
      } else {
        size = -operand
      }
      if index < 0L || index >= size.to_int64() {
        let max_idx = if size > 0 { size - 1 } else { 0 }
        let diag = if operand >= 0 {
          "🚫 数组越界：你访问了 " +
          name +
          "[" +
          index.to_string() +
          "]，但数组 '" +
          name +
          "' 只有 " +
          size.to_string() +
          " 个元素，有效索引是 0~" +
          max_idx.to_string() +
          "。\n\n💡 原因：数组索引超出了合法范围。\n✅ 检查方法：确认索引变量值在 0 到 " +
          max_idx.to_string() +
          " 之间。"
        } else {
          "🚫 数组越界：索引 " +
          index.to_string() +
          " 超出了合法范围 0~" +
          max_idx.to_string() +
          "。\n\n💡 原因：数组索引超出了合法范围。"
        }
        self.trap(diag, line, column)
      }
      None
    }
    TrapBoundsVla => {
      // 零发射死码（总计划 §5 亲证）——到达即产物契约破坏。
      self.trap(
        "TrapBoundsVla: 零发射死码被执行——字节码产物契约破坏（VLA 边界检查已随死 opcode 裁撤）",
        line, column,
      )
      None
    }
    _ => None
  }
}
