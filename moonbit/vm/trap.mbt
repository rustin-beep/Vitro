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
fn VitroVM::push_i32(self : VitroVM, v : Int32) -> Unit {
  self.push(v.to_int64().reinterpret_as_uint64())
}

///|
/// trap 首错单点：`error` 已非空时不再覆盖（首错优先——后续连锁错误不
/// 冲掉根因）；行号非正时回退 `current_line`（Rust `trap.rs:145-156`）。
/// #261（2026-10-24）：`code~` 具名参数 = 结构化 trap 码（缺省空串 =
/// 无码形态）；与 `error` 同首错生命周期——首错带码即记录，连锁 trap
/// 不改写。
fn VitroVM::trap(
  self : VitroVM,
  msg : String,
  line : Int32,
  column : Int32,
  code~ : String = "",
) -> Unit {
  if self.error.is_empty() {
    self.error = msg
    self.trap_code = code
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
/// 单源（Char=1 / Double=8 / 其余 4）。#261（2026-10-24）：返回
/// (文案, trap 码)——数组命中 E3086 / 泛地址回退 E3087（调用方传给
/// trap() 的结构化码与文案首段码同源，不二次判型）。
fn VitroVM::format_bounds_error(
  self : VitroVM,
  addr : UInt32,
) -> (String, String) {
  let mut best : (@bytecode.Symbol, UInt32)? = None // (sym, base)
  let mut best_dist = 2147483647
  for sym in self.symbols {
    guard sym.ty.is_array() && sym.ty.array_size() > 0 else { continue }
    let mut base = sym.addr
    if sym.is_local {
      guard self.call_stack.length() > 0 else { continue }
      base = self.call_stack[self.call_stack.length() - 1].locals_base +
        sym.addr
    }
    let elem_size = self.elem_size_of_vm(sym.ty)
    let size = (sym.ty.array_size().to_uint64() * elem_size.to_uint64()).to_uint()
    // 首尾各 64 字素的「近似归属窗口」（遗留 7 补注，#47 2026-10-09）：
    // 越界地址落在数组尾/首邻近 64 字节内仍归因到该数组（`a[3]` 写偏 1
    // 格这类典型教学形态须给出「哪个数组越界」而非泛地址文案）；64 系
    // Rust `trap.rs` 同形魔数照搬（≈16 个 4 字节元素的教学尺度）。
    let dist : Int32 = if addr >= base && addr < base + size {
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
      let elem_size = self.elem_size_of_vm(sym.ty)
      let index = ((addr.to_int64() - base.to_int64()) / elem_size.to_int64()).to_int()
      // 病 10 修复（#47，2026-10-09）：location 统一由 trap() 追加（带列），
      // 与 exec_debug TrapBounds 臂同形。#60 批二：文案模板外置（键
      // E3086_bounds_array——{name} 双占位符同值渲染；#261 立码带前缀）。
      (
        @util.render_template(
          @assets.trap_messages.get("E3086_bounds_array").unwrap().template,
          [
            ("name", sym.name),
            ("index", index.to_string()),
            ("count", sym.ty.array_size().to_string()),
            ("max_index", (sym.ty.array_size() - 1).to_string()),
          ],
        ),
        "E3086",
      )
    }
    None =>
      // #60 批二：文案模板外置（键 E3087_bounds_generic）
      (
        @util.render_template(
          @assets.trap_messages.get("E3087_bounds_generic").unwrap().template,
          [
            ("addr", addr.reinterpret_as_int().to_string()),
            ("min", @bytecode.NULL_TRAP_SIZE.reinterpret_as_int().to_string()),
            ("max", @bytecode.MEM_SIZE.reinterpret_as_int().to_string()),
          ],
        ),
        "E3087",
      )
  }
}

///|
/// 数组元素步长（base_kind 单源：Char=1 / Double·LongLong=8 / 其余 4——
/// 与 observe.mbt slot_covers:234 同族表对齐）。病 52（2026-10-13）：
/// 旧漏 TK_LongLong（LL 数组元素宽 8 反算除 4 → index 错倍 ×2，登记
/// p[6]→"a[12]" 形态）；端到端触发形态三层探测未复现（疑被 TrapBounds
/// 前置臂遮蔽——修复为同族对齐+防御，wbtest 单点锚在案）。
fn VitroVM::elem_size_of_vm(self : VitroVM, ty : @ast.Type) -> Int32 {
  // 病 81（2026-10-16）：struct/union 按真实布局（method 化拿
  // struct_defs；原独立函数落兜底 4——越界文案 index 错倍同族）
  self.elem_size_of_kind(ty).reinterpret_as_int()
}

///|
/// 除零教学文案（照搬 Rust `format_div_zero_error`，`trap.rs:63-102`）：
/// 扫当前作用域值为 0 的变量附进诊断。
fn VitroVM::format_div_zero_error(self : VitroVM, a : Int32) -> String {
  // #60 批二（2026-10-10）：文案骨架/段落外置资产（E3088_div_zero 主骨架 +
  // E3088_div_zero_inspect 变量段——zero_section 占位；#261 立码带前缀），扫描/、连接逻辑留代码。
  @util.render_template(
    @assets.trap_messages.get("E3088_div_zero").unwrap().template,
    [("a", a.to_string()), ("zero_section", self.div_zero_zero_section())],
  )
}

///|
/// 除零文案的零值变量扫描段（i32/u64 两版共用——#61 第一梯队病 34 批
/// 自 format_div_zero_error 抽出；扫当前作用域值为 0 的变量附进诊断）。
fn VitroVM::div_zero_zero_section(self : VitroVM) -> String {
  let zero_vars : Array[String] = []
  // 病 53（2026-10-13）：局部符号按**当前帧函数名**过滤——旧扫全符号
  // 表且一律用栈顶帧 locals_base，跨函数局部变量（other 的 far_var 在
  // main 帧错位读值）被错位列进「值为 0 的变量」（错作用域+错值双错；
  // oracle 同病，S9 脱钩修正）。全局符号（func_name=""）不过滤。
  // 空栈形态（wbtest 直调/宿主回调边界）退化为不过滤——局部符号由下方
  // 既有 guard 栈空跳过，行为不崩。
  let cur_frame : CallFrame? = if self.call_stack.length() > 0 {
    Some(self.call_stack[self.call_stack.length() - 1])
  } else {
    None
  }
  for sym in self.symbols {
    guard !sym.ty.is_array() else { continue }
    let mut vaddr = sym.addr
    if sym.is_local {
      guard self.call_stack.length() > 0 else { continue }
      guard cur_frame is Some(f) && sym.func_name == f.func_name else {
        continue
      }
      vaddr = cur_frame.unwrap().locals_base + sym.addr
    }
    if vaddr + 4U <= @bytecode.MEM_SIZE && vaddr >= @bytecode.NULL_TRAP_SIZE {
      match self.memory.load_u32(self.mem_map, vaddr) {
        Ok(val) => if val.reinterpret_as_int() == 0 { zero_vars.push(sym.name) }
        Err(_) => ()
      }
    }
  }
  if !zero_vars.is_empty() {
    // 连接符「、」照搬 Rust join
    let names = StringBuilder()
    for i, name in zero_vars {
      if i > 0 {
        names.write_string("、")
      }
      names.write_string(name)
    }
    @util.render_template(
      @assets.trap_messages.get("div_zero_inspect").unwrap().template,
      [("vars", names.to_string())],
    )
  } else {
    ""
  }
}

///|
/// 除零教学文案·u64 版（#61 第一梯队病 34，2026-10-11）：UDivQ/UModQ 消费
/// ——被除数按**无符号**渲染（病 93 同族教训：U 系臂不得借 i32 版把
/// 4000000000u 渲染成负数）。
fn VitroVM::format_div_zero_error_u64(self : VitroVM, a : UInt64) -> String {
  @util.render_template(
    @assets.trap_messages.get("E3088_div_zero").unwrap().template,
    [("a", a.to_string()), ("zero_section", self.div_zero_zero_section())],
  )
}

///|
/// 除零教学文案·i64 版（审阅 P2-1，2026-10-24）：DivQ/ModQ 消费——被除数
/// 按**有符号**渲染（符号域不同不得互借：负值借 u64 版会渲染成巨大无符号
/// 数误导归因）。
fn VitroVM::format_div_zero_error_i64(self : VitroVM, a : Int64) -> String {
  @util.render_template(
    @assets.trap_messages.get("E3088_div_zero").unwrap().template,
    [("a", a.to_string()), ("zero_section", self.div_zero_zero_section())],
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
  // 病 53 同款（2026-10-13）：局部符号按当前帧过滤（跨函数变量在别的
  // 帧，read_variable 用当前帧 base 读出的是错位值，stale/changed 分组
  // 双双失真）。snapshot_vars 的键含跨函数同名变量时同样只比当前帧。
  let inf_frame : CallFrame? = if self.call_stack.length() > 0 {
    Some(self.call_stack[self.call_stack.length() - 1])
  } else {
    None
  }
  for sym in self.symbols {
    guard !sym.ty.is_array() else { continue }
    if sym.is_local && !(inf_frame is Some(f) && sym.func_name == f.func_name) {
      continue
    }
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
    cap : Int32,
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
fn take_first(arr : Array[String], n : Int32) -> Array[String] {
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
  // 病 54 修正（#71 病 91 A 档，2026-10-11）：8 字节族按实宽读——
  // 此前恒 4 字节，double/long long 变量在无限循环诊断里错分组错值
  //（「没变化的变量 x=0」——迁移分叉：oracle 有 Double/LongLong 分支）。
  match sym.ty.kind() {
    TK_Double =>
      match self.memory.load_u64(self.mem_map, vaddr) {
        Ok(v) => v.reinterpret_as_double().to_int64()
        Err(_) => 0L
      }
    TK_LongLong =>
      match self.memory.load_u64(self.mem_map, vaddr) {
        Ok(v) => v.reinterpret_as_int64()
        Err(_) => 0L
      }
    _ =>
      // 布尔指针标志位（Rust：is_bool_ptr() 时取低 8 位判真假）——C 子集
      // 布尔经 int 通道承载，其余 4 字节读（与 Rust 非 bool 路径同口径）。
      match self.memory.load_u32(self.mem_map, vaddr) {
        Ok(v) => v.reinterpret_as_int().to_int64()
        Err(_) => 0L
      }
  }
}

// ---------------------------------------------------------------------------
// 受检访存封装（executor 各臂唯一访存通道；MemFault → 文案渲染单点）
// ---------------------------------------------------------------------------

///|
fn VitroVM::render_mem_fault(
  self : VitroVM,
  fault : @memory.MemFault,
  line : Int32,
  column : Int32,
) -> Unit {
  match fault {
    NullDeref(addr, kind) => {
      // #178（2026-10-19）：NULL 解引用 trap 补 E3083 码位（对齐 E3060
      // uaf 直写形态——vm 层不 import teaching/assets〔分层〕，文案
      // 直写；error_catalog 有卡片条目，demo 码表卡可渲染）
      let addr_dec = addr.reinterpret_as_int().to_string()
      let msg = if kind is Write {
        "[null-deref] NULL 指针解引用 (E3083)：你正在向 NULL 指针区域写入（地址 0x" +
        addr_dec +
        "）。\n\n[cause] 原因：指针的值是 NULL（不指向任何对象），常见于声明后未初始化、malloc 返回 NULL 未检查、或 free 后未置 NULL。\n[fix] 解决方法：解引用前检查指针非空，如 `if (p != NULL) { *p = 1; }`；malloc 后检查返回值。"
      } else {
        "[null-deref] NULL 指针解引用 (E3083)：你正在通过 NULL 指针读取（地址 0x" +
        addr_dec +
        "）。NULL 指针不能解引用。\n\n[cause] 原因：指针的值是 NULL（不指向任何对象），常见于声明后未初始化、malloc 返回 NULL 未检查、或 free 后未置 NULL。\n[fix] 解决方法：解引用前检查指针非空，如 `if (p != NULL) { x = *p; }`；malloc 后检查返回值。"
      }
      self.trap(msg, line, column, code="E3083")
    }
    OutOfBounds(addr, _) => {
      // #261：数组命中 E3086 / 泛地址回退 E3087——码由 format_bounds_error
      // 与文案同源返回（不二次判型）。
      let (msg, code) = self.format_bounds_error(addr)
      self.trap(msg, line, column, code~)
    }
    UseAfterFree(info, kind) =>
      self.trap(
        self.format_uaf_message(info, kind is Write),
        line,
        column,
        code="E3060",
      )
  }
}

///|
/// 受检 4 字节读（Rust `load_i32`：失败回 0 + trap）。
fn VitroVM::vm_load_u32(
  self : VitroVM,
  addr : UInt32,
  line : Int32,
  column : Int32,
) -> UInt32 {
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
  addr : UInt32,
  val : UInt32,
  line : Int32,
  column : Int32,
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
  addr : UInt32,
  line : Int32,
  column : Int32,
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
  addr : UInt32,
  val : UInt64,
  line : Int32,
  column : Int32,
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
  addr : UInt32,
  line : Int32,
  column : Int32,
) -> Int32 {
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
  addr : UInt32,
  val : Int32,
  line : Int32,
  column : Int32,
) -> Unit {
  match self.memory.store_i8(self.mem_map, addr, val) {
    Ok(_) => ()
    Err(f) => self.render_mem_fault(f, line, column)
  }
}
