///| L7 执行层·VM 域：**trap 单点与文案渲染**（Rust `core/trap.rs` 照搬 +
/// `core/memory.rs` 访问器文案上收）。
///
/// **渲染单点纪律**（勘察 §5.3：执行器只发结构化事件，文案生成收敛到
/// 一处）：executor 各臂经 `vm_load_*`/`vm_store_*` 受检封装访存，
/// `@memory.MemFault`（结构化）在此渲染为教学文案；四个诊断文案
/// （UAF / 数组越界 / 除零 / 无限循环）逐字照搬 Rust——它们是 shadow
/// 对拍面（run_json 的 error 字段）。

///|
/// 值栈弹出一个 i32（低 32 位符号解释；空栈 trap「栈下溢」——Rust
/// `core/state.rs:795-803` 同款首错语义）。
fn VitroVM::pop(self : VitroVM) -> UInt64 {
  match self.stack.pop() {
    Some(v) => v
    None => {
      self.trap("运行时错误：栈下溢", 0, 0)
      0UL
    }
  }
}

///|
/// 值栈压入（超 `MAX_STACK_DEPTH` trap「值栈溢出」——Rust `:805-814`）。
fn VitroVM::push(self : VitroVM, val : UInt64) -> Unit {
  if self.stack.length() >= MAX_STACK_DEPTH {
    self.trap(
      "值栈溢出：栈深度超过限制。请检查是否有无限递归或过多嵌套表达式。",
      0, 0,
    )
    return
  }
  self.stack.push(val)
}

///|
/// trap 首错单点：`error` 已非空时不再覆盖（首错优先——后续连锁错误不
/// 冲掉根因）；行号非正时回退 `current_line`（Rust `trap.rs:145-156`）。
fn VitroVM::trap(
  self : VitroVM,
  msg : String,
  line : Int,
  column : Int,
) -> Unit {
  if self.error.is_empty() {
    self.error = msg
    let l = if line > 0 { line } else { self.current_line }
    if l > 0 {
      self.error = self.error + "\n📍 发生在第 " + l.to_string() + " 行"
      if column > 0 {
        self.error = self.error + " 第 " + column.to_string() + " 列"
      }
    }
  }
}

///|
/// UAF 教学文案（照搬 Rust `format_uaf_message`，`core/memory.rs:206-217`）。
fn VitroVM::format_uaf_message(
  self : VitroVM,
  log : @memory.FreedRegionInfo,
  is_write : Bool,
) -> String {
  let action = if is_write { "写入" } else { "读取" }
  "💥 Use-After-Free (E3060)：你正在向一块已经在第 " +
  log.freed_line.to_string() +
  " 行（第 " +
  log.freed_step.to_string() +
  " 步）被 free 的内存" +
  action +
  "（由第 " +
  log.alloc_line.to_string() +
  " 行的 malloc/realloc 分配）。\n\n⏱️ 时间轴：分配 → 释放（第 " +
  log.freed_step.to_string() +
  " 步）→ 继续访问（第 " +
  self.step_count.to_string() +
  " 步）。\n\n💡 原因：指针在 free 后没有置为 NULL，或者存在别名指针（另一个指针也指向同一块内存）。\n✅ 解决方法：free(p) 后立即写 p = NULL;，并确保不再通过其他指针访问这块内存。"
}

///|
/// 数组越界教学文案（照搬 Rust `format_bounds_error`，`trap.rs:6-61`）：
/// 扫符号表找**距 addr 最近的数组**（局部数组按当前帧基址展开），命中则
/// 给出「数组名[算出的索引] / 有效索引 0~n-1」的精确诊断，否则回退
/// 「内存访问越界 + 检查方法」通版。元素步长经 `@ast.Type::base_kind`
/// 单源（Char=1 / Double=8 / 其余 4）。
fn VitroVM::format_bounds_error(self : VitroVM, addr : UInt) -> String {
  let mut best : (@bytecode.Symbol, UInt)? = None // (sym, base)
  let mut best_dist = 2147483647
  for sym in self.symbols {
    guard sym.ty.is_array() && sym.ty.array_size() > 0 else { continue }
    let mut base = sym.addr
    if sym.is_local {
      guard self.call_stack.length() > 0 else { continue }
      base = self.call_stack[self.call_stack.length() - 1].locals_base +
        sym.addr
    }
    let elem_size = self.elem_size_of(sym.ty)
    let size = (sym.ty.array_size().to_uint64() * elem_size.to_uint64()).to_uint()
    let dist : Int = if addr >= base && addr < base + size {
      0
    } else if addr >= base + size && addr < base + size + 64U {
      (addr - (base + size)).reinterpret_as_int()
    } else if addr + 64U >= base && addr < base {
      (base - addr).reinterpret_as_int()
    } else {
      continue
    }
    if dist < best_dist {
      best_dist = dist
      best = Some((sym, base))
    }
  }
  match best {
    Some((sym, base)) => {
      let elem_size = self.elem_size_of(sym.ty)
      let index = ((addr.to_int64() - base.to_int64()) / elem_size.to_int64()).to_int()
      "🚫 数组越界：你访问了 " +
      sym.name +
      "[" +
      index.to_string() +
      "]，但数组 '" +
      sym.name +
      "' 只有 " +
      sym.ty.array_size().to_string() +
      " 个元素，有效索引是 0~" +
      (sym.ty.array_size() - 1).to_string() +
      "。\n\n📍 发生在第 " +
      self.current_line.to_string() +
      " 行\n💡 原因：数组索引超出了合法范围。\n✅ 检查方法：确认索引变量值在 0 到 " +
      (sym.ty.array_size() - 1).to_string() +
      " 之间。"
    }
    None =>
      "🚫 内存访问越界：你访问了地址 0x" +
      addr.reinterpret_as_int().to_string() +
      "，但合法内存范围是 0x" +
      @bytecode.NULL_TRAP_SIZE.reinterpret_as_int().to_string() +
      " ~ 0x" +
      @bytecode.MEM_SIZE.reinterpret_as_int().to_string() +
      "。\n\n✅ 检查方法：\n  • 确认数组索引小于数组大小\n  • 确认指针已经指向有效的内存地址\n  • 确认没有使用已经 free 的指针"
  }
}

///|
/// 数组元素步长（base_kind 单源：Char=1 / Double=8 / 其余 4——Rust
/// `format_bounds_error` 内两处 match 的合并；Float 族走 f32 但 base_kind
/// 落 TK_Float → 4，与 Rust `_ => 4` 同口径）。
fn VitroVM::elem_size_of(self : VitroVM, ty : @ast.Type) -> Int {
  match ty.base_kind() {
    TK_Char => 1
    TK_Double => 8
    _ => 4
  }
}

///|
/// 除零教学文案（照搬 Rust `format_div_zero_error`，`trap.rs:63-102`）：
/// 扫当前作用域值为 0 的变量附进诊断。
fn VitroVM::format_div_zero_error(self : VitroVM, a : Int) -> String {
  let mut diag = "😵 除零错误：你试图用 " +
    a.to_string() +
    " 除以 0。\n\n"
  let zero_vars : Array[String] = []
  for sym in self.symbols {
    guard !sym.ty.is_array() else { continue }
    let mut vaddr = sym.addr
    if sym.is_local {
      guard self.call_stack.length() > 0 else { continue }
      vaddr = self.call_stack[self.call_stack.length() - 1].locals_base +
        sym.addr
    }
    if vaddr + 4U <= @bytecode.MEM_SIZE && vaddr >= @bytecode.NULL_TRAP_SIZE {
      match self.memory.load_u32(self.mem_map, vaddr) {
        Ok(val) => if val.reinterpret_as_int() == 0 { zero_vars.push(sym.name) }
        Err(_) => ()
      }
    }
  }
  if !zero_vars.is_empty() {
    diag = diag + "🔍 当前作用域内值为 0 的变量："
    // 连接符照搬 Rust `join("、")`
    for i, name in zero_vars {
      if i > 0 {
        diag = diag + "、"
      }
      diag = diag + name
    }
    diag = diag +
      "。请检查除法表达式中是否使用了这些变量。\n\n"
  }
  diag +
  "💡 原因：除数不能为 0。\n✅ 检查你的除法表达式，确保除数在被除之前不是 0。\n📝 示例：如果变量 b 可能为 0，先用 if 判断：\n    if (b != 0) {\n        result = a / b;\n    }"
}

///|
/// 无限循环教学文案（照搬 Rust `format_infinite_loop_error`，`trap.rs:104-144`）：
/// 对比 `snapshot_vars`（每 10 万步刷新）分「没变化 / 发生变化」两组变量，
/// 各取前 6 / 前 4。
fn VitroVM::format_infinite_loop_error(self : VitroVM) -> String {
  let mut diag = "🔄 程序执行步数超过限制（" +
    self.max_steps.to_string() +
    " 步），可能包含无限循环。\n\n"
  let stale_vars : Array[String] = []
  let changed_vars : Array[String] = []
  for sym in self.symbols {
    guard !sym.ty.is_array() else { continue }
    let cur_val = self.read_variable(sym)
    match self.snapshot_vars.get(sym.name) {
      Some(old_val) =>
        if old_val == cur_val.reinterpret_as_uint64() {
          stale_vars.push(sym.name + " = " + cur_val.to_string())
        } else {
          changed_vars.push(sym.name + " = " + cur_val.to_string())
        }
      None => ()
    }
  }
  if !stale_vars.is_empty() {
    diag = diag +
      "🔍 在最近 " +
      SNAPSHOT_INTERVAL.to_string() +
      " 步内没有变化的变量："
    let shown = take_first(stale_vars, 6)
    for i, name in shown {
      if i > 0 {
        diag = diag + "，"
      }
      diag = diag + name
    }
    if stale_vars.length() > 6 {
      diag = diag + " 等"
    }
    diag = diag + "。\n\n"
  }
  if !changed_vars.is_empty() {
    diag = diag + "🔍 发生变化的变量："
    let shown = take_first(changed_vars, 4)
    for i, name in shown {
      if i > 0 {
        diag = diag + "，"
      }
      diag = diag + name
    }
    if changed_vars.length() > 4 {
      diag = diag + " 等"
    }
    diag = diag + "。\n\n"
  }
  diag +
  "💡 原因：程序执行了太多步数但没有结束。常见原因：\n  • 循环条件永远为真（如 while(1)）\n  • 循环变量没有更新（如忘了写 i++）\n  • 递归函数没有正确的终止条件\n✅ 检查方法：确认循环体中有改变循环条件的语句。"
}

///|
fn take_first(arr : Array[String], n : Int) -> Array[String] {
  let out : Array[String] = []
  for i = 0; i < n; i = i + 1 {
    if i < arr.length() {
      out.push(arr[i])
    }
  }
  out
}

///|
/// 读符号变量的当前值（照搬 Rust `read_variable`，`core/memory.rs:229-` ——
/// 局部按当前帧基址展开；访存失败回 0）。
fn VitroVM::read_variable(self : VitroVM, sym : @bytecode.Symbol) -> Int64 {
  let vaddr = if sym.is_local {
    guard self.call_stack.length() > 0 else { return 0L }
    let frame = self.call_stack[self.call_stack.length() - 1]
    frame.locals_base + sym.addr
  } else {
    sym.addr
  }
  // 布尔指针标志位（Rust：is_bool_ptr() 时取低 8 位判真假）——C 子集
  // 布尔经 int 通道承载，此处直接 4 字节读（与 Rust 非 bool 路径同口径）。
  match self.memory.load_u32(self.mem_map, vaddr) {
    Ok(v) => v.reinterpret_as_int().to_int64()
    Err(_) => 0L
  }
}

// ---------------------------------------------------------------------------
// 受检访存封装（executor 各臂唯一访存通道；MemFault → 文案渲染单点）
// ---------------------------------------------------------------------------

///|
fn VitroVM::render_mem_fault(
  self : VitroVM,
  fault : @memory.MemFault,
  line : Int,
  column : Int,
) -> Unit {
  match fault {
    NullDeref(addr, kind) => {
      let msg = if kind is Write {
        "向 NULL 指针区域写入（地址 0x" +
        addr.reinterpret_as_int().to_string() +
        "）。请确认指针已被正确初始化。"
      } else {
        "访问了 NULL 指针区域（地址 0x" +
        addr.reinterpret_as_int().to_string() +
        "）。NULL 指针不能解引用。请确认指针已被正确初始化。"
      }
      self.trap(msg, line, column)
    }
    OutOfBounds(addr, _) =>
      self.trap(self.format_bounds_error(addr), line, column)
    UseAfterFree(info, kind) =>
      self.trap(self.format_uaf_message(info, kind is Write), line, column)
  }
}

///|
/// 受检 4 字节读（Rust `load_i32`：失败回 0 + trap）。
fn VitroVM::vm_load_u32(
  self : VitroVM,
  addr : UInt,
  line : Int,
  column : Int,
) -> UInt {
  match self.memory.load_u32(self.mem_map, addr) {
    Ok(v) => v
    Err(f) => {
      self.render_mem_fault(f, line, column)
      0U
    }
  }
}

///|
/// 受检 4 字节写。
fn VitroVM::vm_store_u32(
  self : VitroVM,
  addr : UInt,
  val : UInt,
  line : Int,
  column : Int,
) -> Unit {
  match self.memory.store_u32(self.mem_map, addr, val) {
    Ok(_) => ()
    Err(f) => self.render_mem_fault(f, line, column)
  }
}

///|
/// 受检 8 字节读。
fn VitroVM::vm_load_u64(
  self : VitroVM,
  addr : UInt,
  line : Int,
  column : Int,
) -> UInt64 {
  match self.memory.load_u64(self.mem_map, addr) {
    Ok(v) => v
    Err(f) => {
      self.render_mem_fault(f, line, column)
      0UL
    }
  }
}

///|
/// 受检 8 字节写。
fn VitroVM::vm_store_u64(
  self : VitroVM,
  addr : UInt,
  val : UInt64,
  line : Int,
  column : Int,
) -> Unit {
  match self.memory.store_u64(self.mem_map, addr, val) {
    Ok(_) => ()
    Err(f) => self.render_mem_fault(f, line, column)
  }
}

///|
/// 受检单字节读（符号扩展到 Int——Rust `load_i8`）。
fn VitroVM::vm_load_i8(
  self : VitroVM,
  addr : UInt,
  line : Int,
  column : Int,
) -> Int {
  match self.memory.load_i8(self.mem_map, addr) {
    Ok(v) => v
    Err(f) => {
      self.render_mem_fault(f, line, column)
      0
    }
  }
}

///|
/// 受检单字节写。
fn VitroVM::vm_store_i8(
  self : VitroVM,
  addr : UInt,
  val : Int,
  line : Int,
  column : Int,
) -> Unit {
  match self.memory.store_i8(self.mem_map, addr, val) {
    Ok(_) => ()
    Err(f) => self.render_mem_fault(f, line, column)
  }
}
