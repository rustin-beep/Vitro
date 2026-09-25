///| L7 执行层·VM 域·executor：**控制流族**（Rust `executor/control.rs`
/// 照搬；CallHost 的 host 分发随批三号，本文件到达即 fail loud）。
///
/// **新设计红利**：Rust 每次 Call/Ret 后 `rebuild_local_sym_map()`（全量
/// 重建 offset→名索引，坑 12 性能热点）——MoonBit 侧该字段已被装载期派生
/// 索引（`locals_by_func`，按帧 `func_name` 查）取代，此处**零重建调用**。
///
/// **宿主回调哨兵**：`return_ip : Int?` 的 `None`（Rust `usize::MAX`）——
/// qsort/bsearch 比较器经 `call_user_function` 进入用户函数，该帧 Ret 即
/// 整个宿主回调收尾（恢复 `original_stack_top` + 压返回值 + Finished）。

///|
fn VitroVM::do_call(
  self : VitroVM,
  func_idx : Int,
  line : Int,
  column : Int,
  op_name : String,
) -> Unit {
  // Option 数组：None = 未注册（Rust 侧是 Vec + ip==0 判定——Option 形态
  // 更精确，等价语义）
  match self.func_table.get(func_idx) {
    Some(Some(meta)) =>
      if meta.ip == 0 {
        self.trap("\{op_name}: 未知函数索引 \{func_idx}", line, column)
      } else {
        self.do_call_inner(func_idx, meta.arg_count, line, column, op_name)
      }
    _ => self.trap("\{op_name}: 未知函数索引 \{func_idx}", line, column)
  }
}

///|
fn VitroVM::do_call_with_arg_count(
  self : VitroVM,
  func_idx : Int,
  arg_count : Int,
  line : Int,
  column : Int,
  op_name : String,
) -> Unit {
  match self.func_table.get(func_idx) {
    Some(Some(meta)) =>
      if meta.ip == 0 {
        self.trap("\{op_name}: 未知函数索引 \{func_idx}", line, column)
      } else {
        self.do_call_inner(func_idx, arg_count, line, column, op_name)
      }
    _ => self.trap("\{op_name}: 未知函数索引 \{func_idx}", line, column)
  }
}

///|
fn VitroVM::do_call_inner(
  self : VitroVM,
  func_idx : Int,
  arg_count : Int,
  line : Int,
  column : Int,
  op_name : String,
) -> Unit {
  // Rust 此处 clone meta（借用检查器冲突的先 clone 再用 形态）——MoonBit
  // 引用语义直接持有，无克隆。
  let meta = match self.func_table.get(func_idx) {
    Some(Some(m)) => m
    _ => return
  }
  // V-P1-10 会话级保险丝：调用深度上限。教学内容 = 可控地撞上限并拿到
  // 教学 trap，而非无限等待。
  if self.call_stack.length() >= self.call_depth_limit {
    let limit = self.call_depth_limit
    self.trap(
      "\{op_name}: 调用深度超过上限（\{limit} 层）。请检查递归是否有终止条件，或把问题规模调小。",
      line,
      column,
    )
    return
  }
  let func_name : String = match self.func_names.get(func_idx) {
    Some(Some(n)) => n
    _ => "func_" + func_idx.to_string()
  }
  let frame_size = meta.local_count.reinterpret_as_uint()
  if frame_size > @bytecode.STACK_START - @bytecode.NULL_TRAP_SIZE ||
    frame_size > self.mem_stack_top {
    self.trap("\{op_name}: 栈溢出", line, column)
    return
  }
  if self.mem_stack_top < @bytecode.NULL_TRAP_SIZE + frame_size {
    self.trap("\{op_name}: 栈溢出", line, column)
    return
  }
  let heap_limit = self.mem_map.heap_offset()
  if self.mem_stack_top - frame_size < heap_limit {
    self.trap(
      "\{op_name}: 栈溢出（栈与堆发生碰撞）。请减少递归深度或动态内存分配。",
      line,
      column,
    )
    return
  }
  let original_stack_top = self.mem_stack_top
  self.mem_stack_top = self.mem_stack_top - frame_size
  let locals_base = self.mem_stack_top
  let mut word_offset : UInt = 0U
  // 先弹出命名参数（param_sizes 逐参 word 数；逆序逐 word 落局部区）
  for words in meta.param_sizes {
    let w = words.reinterpret_as_uint()
    let addr = locals_base + word_offset * 4U
    let mut k = w
    while k > 0U {
      k = k - 1U
      let val = self.pop().to_uint()
      self.vm_store_u32(addr + k * 4U, val, line, column)
    }
    word_offset = word_offset + w
  }
  // 变参函数：弹出额外变参（按 int word 处理）
  if meta.is_variadic {
    while word_offset < arg_count.reinterpret_as_uint() {
      let addr = locals_base + word_offset * 4U
      let val = self.pop().to_uint()
      self.vm_store_u32(addr, val, line, column)
      word_offset = word_offset + 1U
    }
  }
  let arg_bytes = word_offset * 4U
  // 变参函数预留 64 字节变参区域，清零仅从实际局部变量开始（避免覆盖变参）
  let zero_start : UInt = if meta.is_variadic {
    let mut named_words : UInt = 0U
    for w in meta.param_sizes {
      named_words = named_words + w.reinterpret_as_uint()
    }
    locals_base + named_words * 4U + 64U
  } else {
    locals_base + arg_bytes
  }
  let mut za = zero_start
  while za < locals_base + meta.local_count.reinterpret_as_uint() {
    self.vm_store_i8(za, 0, line, column)
    za = za + 1U
  }
  let buffers : Array[@bytecode.LocalBuffer] = []
  for b in meta.local_buffers {
    buffers.push(@bytecode.LocalBuffer::{
      offset: b.offset,
      size: b.size,
      name: b.name,
    })
  }
  self.call_stack.push(CallFrame::{
    return_ip: Some(self.ip),
    locals_base,
    local_count: meta.local_count,
    func_name,
    original_stack_top,
    caller_line: self.current_line,
    local_buffers: buffers,
  })
  // Rust 此处 rebuild_local_sym_map()（坑 12 热点）——派生索引免重建
  self.ip = meta.ip
}

///|
fn VitroVM::execute_control_flow(
  self : VitroVM,
  op : @opcode.OpCode,
  operand : Int,
  line : Int,
  column : Int,
) -> StepResult? {
  match op {
    Jump => {
      if operand < 0 || operand >= self.code.length() {
        self.trap(
          "Jump 目标越界：\{operand}（代码长度：\{self.code.length()}）",
          line,
          column,
        )
      } else {
        self.ip = operand
      }
      None
    }
    JumpIfZero | JumpIfNotZero => {
      let val = self.pop()
      let taken = if op is JumpIfZero { val == 0UL } else { val != 0UL }
      if taken {
        if operand < 0 || operand >= self.code.length() {
          let nm = if op is JumpIfZero { "JumpIfZero" } else { "JumpIfNotZero" }
          self.trap(
            "\{nm} 目标越界：\{operand}（代码长度：\{self.code.length()}）",
            line,
            column,
          )
        } else {
          self.ip = operand
        }
      }
      None
    }
    Call => {
      self.do_call(operand, line, column, "Call")
      None
    }
    CallVar => {
      if self.stack.length() == 0 {
        self.trap("CallVar: 栈下溢（缺少参数数量）", line, column)
      } else {
        let arg_count = self.pop_i32()
        self.do_call_with_arg_count(operand, arg_count, line, column, "CallVar")
      }
      None
    }
    CallPtr => {
      if self.stack.length() == 0 {
        self.trap("CallPtr: 栈下溢（缺少函数索引）", line, column)
      } else {
        let func_idx = self.pop().to_uint()
        match self.func_table.get(func_idx.reinterpret_as_int()) {
          Some(Some(_)) =>
            self.do_call(func_idx.reinterpret_as_int(), line, column, "CallPtr")
          _ =>
            self.trap(
              "CallPtr: 函数指针索引 \{func_idx} 越界，可能指针未正确初始化",
              line,
              column,
            )
        }
      }
      None
    }
    CallHost => {
      self.execute_host_func(operand, line, column)
      // Interactive 输入未就绪：ip 回退一步（可续跑——重执行本指令重新弹参）
      if self.waiting_input {
        self.ip = self.ip - 1
        return Some(WaitingInput)
      }
      None
    }
    Ret => {
      if self.call_stack.length() == 0 {
        return Some(Finished)
      }
      let ret_val = self.pop()
      guard self.call_stack.pop() is Some(frame) else { return Some(Finished) }
      // 宿主回调哨兵（return_ip = None）：整个宿主回调收尾
      if frame.return_ip is None {
        self.mem_stack_top = frame.original_stack_top
        self.push(ret_val)
        return Some(Finished)
      }
      guard frame.return_ip is Some(rip) else { return Some(Finished) }
      self.ip = rip
      self.mem_stack_top = frame.original_stack_top
      self.current_line = frame.caller_line
      self.push(ret_val)
      None
    }
    RetVoid => {
      if self.call_stack.length() == 0 {
        return Some(Finished)
      }
      guard self.call_stack.pop() is Some(frame) else { return Some(Finished) }
      if frame.return_ip is None {
        self.mem_stack_top = frame.original_stack_top
        return Some(Finished)
      }
      guard frame.return_ip is Some(rip) else { return Some(Finished) }
      self.ip = rip
      self.mem_stack_top = frame.original_stack_top
      self.current_line = frame.caller_line
      None
    }
    _ => None
  }
}
