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
/// **i32 结果符号扩展压栈**（oracle `x as u64` 语义——Rust 从 i32 到 u64
/// 的 `as` 是符号扩展；MoonBit `Int` 是 32 位，`reinterpret_as_uint().
/// to_uint64()` 是零扩展，负值时位模式分叉〔审阅 P1-1 实锤：PushConst(-1)
/// 落栈 0xFFFFFFFFFFFFFFFF vs 0x00000000FFFFFFFF〕）。所有「i32 语义值压栈」
/// 的臂一律走本入口；u32 语义值（地址/无符号结果）仍 `push` 直压。
fn VitroVM::push_i32(self : VitroVM, v : Int) -> Unit {
  self.push(v.to_int64().reinterpret_as_uint64())
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
      self.error = self.error +
        "\n[location] 发生在第 " +
        l.to_string() +
        " 行"
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
  "[uaf] Use-After-Free (E3060)：你正在向一块已经在第 " +
  log.freed_line.to_string() +
  " 行（第 " +
  log.freed_step.to_string() +
  " 步）被 free 的内存" +
  action +
  "（由第 " +
  log.alloc_line.to_string() +
  " 行的 malloc/realloc 分配）。\n\n[timeline] 时间轴：分配 → 释放（第 " +
  log.freed_step.to_string() +
  " 步）→ 继续访问（第 " +
  self.step_count.to_string() +
  " 步）。\n\n[cause] 原因：指针在 free 后没有置为 NULL，或者存在别名指针（另一个指针也指向同一块内存）。\n[fix] 解决方法：free(p) 后立即写 p = NULL;，并确保不再通过其他指针访问这块内存。"
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
    let elem_size = elem_size_of(sym.ty)
    let size = (sym.ty.array_size().to_uint64() * elem_size.to_uint64()).to_uint()
    // 首尾各 64 字素的「近似归属窗口」（遗留 7 补注，#47 2026-10-09）：
    // 越界地址落在数组尾/首邻近 64 字节内仍归因到该数组（`a[3]` 写偏 1
    // 格这类典型教学形态须给出「哪个数组越界」而非泛地址文案）；64 系
    // Rust `trap.rs` 同形魔数照搬（≈16 个 4 字节元素的教学尺度）。
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
      let elem_size = elem_size_of(sym.ty)
      let index = ((addr.to_int64() - base.to_int64()) / elem_size.to_int64()).to_int()
      // 病 10 修复（#47，2026-10-09）：location 统一由 trap() 追加（带列），
      // 与 exec_debug TrapBounds 臂同形。#60 批二：文案模板外置（键
      // bounds_array——{name} 双占位符同值渲染）。
      @util.render_template(
        @assets.trap_messages.get("bounds_array").unwrap().template,
        [
          ("name", sym.name),
          ("index", index.to_string()),
          ("count", sym.ty.array_size().to_string()),
          ("max_index", (sym.ty.array_size() - 1).to_string()),
        ],
      )
    }
    None =>
      // #60 批二：文案模板外置（键 bounds_generic）
      @util.render_template(
        @assets.trap_messages.get("bounds_generic").unwrap().template,
        [
          ("addr", addr.reinterpret_as_int().to_string()),
          ("min", @bytecode.NULL_TRAP_SIZE.reinterpret_as_int().to_string()),
          ("max", @bytecode.MEM_SIZE.reinterpret_as_int().to_string()),
        ],
      )
  }
}

///|
/// 数组元素步长（base_kind 单源：Char=1 / Double=8 / 其余 4——Rust
/// `format_bounds_error` 内两处 match 的合并；Float 族走 f32 但 base_kind
/// 落 TK_Float → 4，与 Rust `_ => 4` 同口径）。
fn elem_size_of(ty : @ast.Type) -> Int {
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
  // #60 批二（2026-10-10）：文案骨架/段落外置资产（E_div_zero 主骨架 +
  // E_div_zero_inspect 变量段——zero_section 占位），扫描/、连接逻辑留代码。
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
  let zero_section = if !zero_vars.is_empty() {
    // 连接符「、」照搬 Rust join
    let names = StringBuilder()
    for i, name in zero_vars {
      if i > 0 {
        names.write_string("、")
      }
      names.write_string(name)
    }
    @util.render_template(
      @assets.trap_messages.get("E_div_zero_inspect").unwrap().template,
      [("vars", names.to_string())],
    )
  } else {
    ""
  }
  @util.render_template(
    @assets.trap_messages.get("E_div_zero").unwrap().template,
    [("a", a.to_string()), ("zero_section", zero_section)],
  )
}

///|
/// 无限循环教学文案（照搬 Rust `format_infinite_loop_error`，`trap.rs:104-144`）：
/// 对比 `snapshot_vars`（每 10 万步刷新）分「没变化 / 发生变化」两组变量，
/// 各取前 6 / 前 4。
fn VitroVM::format_infinite_loop_error(self : VitroVM) -> String {
  // #60 批二（2026-10-10）：文案骨架/段落外置资产（E_inf_loop 主骨架 +
  // E_inf_loop_stale/changed 变量段——section 占位），分组/截断（前 6/前 4
  // +「等」尾巴）逻辑留代码。
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
  fn render_var_section(
    tpl_key : String,
    vars : Array[String],
    cap : Int,
    extra : Array[(String, String)],
  ) -> String {
    if vars.is_empty() {
      return ""
    }
    let names = StringBuilder()
    let shown = take_first(vars, cap)
    for i, name in shown {
      if i > 0 {
        names.write_string("，")
      }
      names.write_string(name)
    }
    if vars.length() > cap {
      names.write_string(" 等")
    }
    let ps : Array[(String, String)] = [("vars", names.to_string())]
    for e in extra {
      ps.push(e)
    }
    @util.render_template(
      @assets.trap_messages.get(tpl_key).unwrap().template,
      ps,
    )
  }
  let stale_section = render_var_section("E_inf_loop_stale", stale_vars, 6, [
    ("interval", SNAPSHOT_INTERVAL.to_string()),
  ])
  let changed_section = render_var_section(
    "E_inf_loop_changed",
    changed_vars,
    4,
    [],
  )
  @util.render_template(
    @assets.trap_messages.get("E_inf_loop").unwrap().template,
    [
      ("max_steps", self.max_steps.to_string()),
      ("stale_section", stale_section),
      ("changed_section", changed_section),
    ],
  )
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
