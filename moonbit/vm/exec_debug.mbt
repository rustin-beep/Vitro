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
  operand : Int32,
  line : Int32,
  column : Int32,
  file_id : Int32,
) -> StepResult? {
  match op {
    StepEvent => {
      // #167/#168（2026-10-21）：libc 段（装载 file_id=1）的 StepEvent
      // 行号是 libc C 源自家坐标（464 条、域 3~536），与用户行号共用
      // 一个无文件域编号空间，三面全部跳过——①断点行号域重叠假暂停
      //（用户在 89~95 行设断点 + strlen 内部同号）；②current_line 错
      // 染（UI 把 libc 行号高亮到用户源文件——错行高亮根源）；③vis
      // 事件同号误触发。跳过后 libc 步行进时 current_line 保持上一
      // 用户行（高亮停在调用点——教学语义合理）。热力图的 file_id==0
      // 口径（step()）同族先例。
      if file_id == 1 {
        return None
      }
      self.current_line = operand
      if self.breakpoints.contains(operand) {
        self.paused = true
      }
      self.step_event_hit = true
      for entry in self.vis_event_lines {
        if entry.0 == operand {
          // #51 批②首片（2026-10-17）：ty=2（相邻交换）带运行期 extras
          // （j/j+1/-1——swap_event_extras）；其余 ty 维持 0,0,0 冻结面
          let (e0, e1, e2) = if entry.1 == 2 {
            self.swap_event_extras()
          } else {
            (0, 0, 0)
          }
          self.vis_event_queue.push(VisEventData::{
            ty: entry.1,
            line: operand,
            extra0: e0,
            extra1: e1,
            extra2: e2,
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
        // #261（2026-10-24）：数组越界文案首段带码 E3086（与
        // E3086_bounds_array 资产模板同码——两条渲染路径同码位）。
        let diag = if operand >= 0 {
          "[deny] 数组越界 (E3086)：你访问了 " +
          name +
          "[" +
          index.to_string() +
          "]，但数组 '" +
          name +
          "' 只有 " +
          size.to_string() +
          " 个元素，有效索引是 0~" +
          max_idx.to_string() +
          "。\n\n[cause] 原因：数组索引超出了合法范围。\n[fix] 检查方法：确认索引变量值在 0 到 " +
          max_idx.to_string() +
          " 之间。"
        } else {
          "[deny] 数组越界 (E3086)：索引 " +
          index.to_string() +
          " 超出了合法范围 0~" +
          max_idx.to_string() +
          "。\n\n[cause] 原因：数组索引超出了合法范围。"
        }
        self.trap(diag, line, column, code="E3086")
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

///|
/// #51 批②首片（2026-10-17）：ty=2（相邻交换）事件的运行期 extras——按
/// 教学模板约定读**当前帧**局部 int 变量 `j`（infer_sorting 的 swap 判据
/// 同款约定），extra0=j、extra1=j+1、extra2 恒 -1；无帧/无该局部/读失败
/// 落全 -1 哨兵（「无值 -1 不许 0」——诚实空态非 0）。
fn VitroVM::swap_event_extras(self : VitroVM) -> (Int32, Int32, Int32) {
  let top = self.call_stack.length()
  guard top > 0 else { return (-1, -1, -1) }
  let frame = self.call_stack[top - 1]
  for sym in self.symbols {
    if sym.name == "j" && sym.is_local && sym.func_name == frame.func_name {
      let addr = frame.locals_base + sym.addr
      match self.memory.load_u32(self.mem_map, addr) {
        Ok(bits) => {
          let j = bits.reinterpret_as_int()
          return (j, j + 1, -1)
        }
        Err(_) => return (-1, -1, -1)
      }
    }
  }
  (-1, -1, -1)
}
