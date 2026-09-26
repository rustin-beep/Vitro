///| L7 执行层·VM 域：**执行器状态机（`VitroVM`）**。
///
/// 与 Rust `VitroVM`（`core/state.rs:77-138`，36 字段）的关系是**新设计
/// 而非逐字段照搬**（types.mbt 头注的裁剪清单）；语义契约照搬的部分：
/// 值栈位模式（u64 低 32 位装 i32/f32）、局部变量在线性内存
/// （`mem_stack_top` 自 `STACK_START` 向下）、func_table 按索引稀疏注册
/// （注册顺序即覆盖语义）、`reset` 保留会话级配置（「先设上限再运行」
/// 不变量，Rust `session_config_test` 回归锚的语义）。

///|
/// 函数表容量上限（U2#13 照搬）：恶意/损坏索引（如 u32::MAX）曾直接
/// `resize(idx+1)` 致 4G 项 OOM；超上限索引拒绝（返回 false，表不扩）。
pub const MAX_FUNCTIONS : Int = 65_536

///|
/// 调用深度上限默认值（照搬 Rust `MAX_STACK_DEPTH = 10_000`——零局部变量
/// 递归使 `call_stack` 无限增长的结构性保险丝，坑 12）。
pub const MAX_STACK_DEPTH : Int = 10_000

///|
/// 默认步数预算（照搬 Rust `VitroVM::new` 的 1000 万——无限循环教学保险丝）。
pub const DEFAULT_MAX_STEPS : Int = 10_000_000

///|
/// 可视化事件队列环形上限（照搬 Rust `executor/debug.rs:6` 的 1024——
/// U2#8 环形丢弃最老保最新）。
pub const VIS_EVENT_LIMIT : Int = 1024

///|
/// 执行器状态机。
///
/// 字段分区（快照纪律——`snapshot.mbt` 的 `VMSnapshot` 只收「执行状态」）：
/// - **编译期产物**（code / func_table / func_names / symbols / 常量池 /
///   派生索引 / arc_cleanup / vis_event_lines）：装载期由 `setup_*` 通道
///   灌入，**不入快照**（`Session` 重建，Rust `snapshot.rs:51-53` 同口径）；
/// - **会话级配置**（max_steps / call_depth_limit / deterministic）：
///   **不入快照、`reset` 保留**（capi `vitro_set_*` 语义）；
/// - **执行状态**（其余全部）：入快照，`reset` 清零。
pub struct VitroVM {
  // ── 指令流（编译期产物）──
  code : Array[@opcode.Instruction]
  mut ip : Int
  // ── 内存与堆 ──
  /// 1MB 载体 + 脏页位图（`bytes`/`dirty` priv——本包亦无裸字节出口，
  /// 受检读写一律经 memory 单入口）。
  memory : @memory.Memory
  /// 堆元数据（regions / free_list / quarantine / freed_logs）；reset 整体重建。
  mut mem_map : @memory.MemoryMap
  /// 栈区游标（自 `STACK_START` 向下增长，局部帧编址基准）。
  mut mem_stack_top : UInt
  // ── 值栈与调用 ──
  /// 值栈（**位模式**：i32/f32 用低 32 位，i64/f64 用满——与 golden 位级
  /// 一致相关，禁改 `enum Value` 装箱形态，勘察 §5.3）。
  stack : Array[UInt64]
  call_stack : Array[CallFrame]
  /// qsort/bsearch 回调深度（防递归比较器）。
  mut qsort_depth : Int
  // ── 编译期产物 ──
  /// 按索引稀疏的函数表（`None` = 未注册——Rust 是 Vec+resize+默认值占位，
  /// 此处 Option 数组免造默认 meta）。
  func_table : Array[@bytecode.FuncMeta?]
  func_names : Array[String?]
  symbols : Array[@bytecode.Symbol]
  f64_constants : Array[Double]
  i64_constants : Array[Int64]
  /// **装载期派生索引**（坑 12 结构性消除）：函数名 → (局部偏移 → 变量名)。
  /// 从 `symbols` 一次构建；Call/Ret 帧切换 = 换 Map 查找键，O(1)——
  /// 取代 Rust 每次 Call/Ret 全量重建 `local_sym_map` 的热点。
  locals_by_func : Map[String, Map[Int, String]]
  /// 全局符号索引（offset/addr → 名字），同上装载期派生。
  global_syms : Map[Int, String]
  /// **ARC 帧退出清理机制占位**（CS 批接线，C 恒空；CS 计划 §4.6——
  /// 「帧退出清理列表」：函数名 → 该帧引用类型局部变量的 offset 列表，
  /// Ret / UNWINDING 弹帧时逐个读 u32 → release。机制 v1 入形，
  /// retain/release 的 host id 与发射侧随 CS 批落）。
  arc_cleanup : Map[String, Array[Int]]
  // ── 运行控制（执行状态）──
  mut step_count : Int
  /// 会话级配置（reset 保留；装载通道**不得**设置——Rust 曾在 setup 硬编码
  /// 10_000_000 抹掉用户配置的事故见 compile_pipeline.rs:334 注释）。
  mut max_steps : Int
  /// 会话级配置（reset 保留）。
  mut call_depth_limit : Int
  mut finished : Bool
  mut exit_code : Int
  mut paused : Bool
  mut cancelled : Bool
  mut step_event_hit : Bool
  /// trap 文案（首错优先——执行器批二号扩展结构化事件，文案渲染单点）。
  mut error : String
  mut current_line : Int
  /// `main(int argc, char *argv[])` 的 argc。
  mut argc : Int
  /// argv 指针数组起始地址（R1 ③：自 `GLOBAL_REGION_LIMIT` 向下分配）。
  mut argv_addr : UInt
  // ── 教学观测 ──
  /// 可视化事件队列（环形 `VIS_EVENT_LIMIT`——超限丢最老）。
  vis_event_queue : Array[VisEventData]
  /// 可视化事件行登记（**会话注入配置**，快照不含——Rust `VMSnapshot`
  /// 同口径；set_vis_event_lines 灌入）。
  vis_event_lines : Array[(Int, Int, String)]
  /// 断点集合（行号；快照含——时间旅行不丢学生断点，Rust 同口径）。
  breakpoints : Set[Int]
  /// 最近一步的变量访问记录（瞬时观测，快照不含；每步清空重记）。
  last_accessed_vars : Array[VariableAccess]
  /// 执行热力图（行 → 计数；每步一次增量——MoonBit 可变 Map 直更，
  /// 无 Rust `Arc::make_mut` 的 COW 克隆点，快照时整表拷贝）。
  heatmap : Map[Int, UInt64]
  /// 无限循环诊断的变量快照（每 `SNAPSHOT_INTERVAL`(10 万) 步刷新；
  /// 与 CheckpointManager 的检查点间隔是两个频率，坑 14——口径独立保留）。
  snapshot_vars : Map[String, UInt64]
  mut last_snapshot_step : Int
  // ── 宿主域状态（L7 host 包；快照经各自快照通道）──
  mut output : @host.OutputLog
  mut input : @host.InputState
  mut rand : @host.RandState
  vfs : @host.VirtualFileSystem
  /// Interactive 模式 stdin 未就绪标志（可续跑）。
  mut waiting_input : Bool
  /// 确定性模式（time/clock 恒 0；wasm-gc 无熵源 F5/R12 ⇒ 默认开）。
  /// 会话级配置（reset 保留）。
  mut deterministic : Bool
  // ── C# 异常三执行状态（CS 批硬前置；C 前端恒默认值）──
  handler_stack : Array[HandlerFrame]
  mut exec_mode : ExecMode
  /// 当前异常寄存器（异常对象堆地址）。
  mut exception_ref : UInt?
  /// UNWINDING 剩余待展开帧数。
  mut unwind_remaining_frames : Int
  /// UNWINDING 已锁定的目标 handler。
  mut unwind_target : HandlerFrame?
}

///|
/// 新建 VM（全默认态：空程序、1MB 零页、`STACK_START` 栈顶、1000 万步预算、
/// 42 号种子 LCG、deterministic 开）。
pub fn VitroVM::new() -> VitroVM {
  VitroVM::{
    code: [],
    ip: 0,
    memory: @memory.Memory::new(),
    mem_map: @memory.MemoryMap::new(),
    mem_stack_top: @bytecode.STACK_START,
    stack: [],
    call_stack: [],
    qsort_depth: 0,
    func_table: [],
    func_names: [],
    symbols: [],
    f64_constants: [],
    i64_constants: [],
    locals_by_func: Map([]),
    global_syms: Map([]),
    arc_cleanup: Map([]),
    step_count: 0,
    max_steps: DEFAULT_MAX_STEPS,
    call_depth_limit: MAX_STACK_DEPTH,
    finished: false,
    exit_code: 0,
    paused: false,
    cancelled: false,
    step_event_hit: false,
    error: "",
    current_line: 0,
    argc: 0,
    argv_addr: 0U,
    vis_event_queue: [],
    vis_event_lines: [],
    breakpoints: Set([]),
    last_accessed_vars: [],
    heatmap: Map([]),
    snapshot_vars: Map([]),
    last_snapshot_step: 0,
    output: @host.OutputLog::new(),
    input: @host.InputState::new([], true),
    rand: @host.RandState::new(42U),
    vfs: @host.VirtualFileSystem::new(),
    waiting_input: false,
    deterministic: true,
    handler_stack: [],
    exec_mode: Running,
    exception_ref: None,
    unwind_remaining_frames: 0,
    unwind_target: None,
  }
}

///|
/// 重置执行状态（照搬 Rust `reset` 语义 + 新设计完整清）。
///
/// **保留**（会话级配置 / 宿主域状态——宿主域重置属会话层职责）：
/// `max_steps` / `call_depth_limit` / `deterministic` / 隔离预算
/// `quarantine_budget` / `output` / `input` / `vfs` / `rand`。
/// **清零**：指令流与全部编译期产物（含派生索引）、执行状态、教学观测、
/// C# 三状态、内存（字节清零 + 堆元数据重建）。
pub fn VitroVM::reset(self : VitroVM) -> Unit {
  self.code.clear()
  self.ip = 0
  self.stack.clear()
  self.call_stack.clear()
  self.qsort_depth = 0
  self.func_table.clear()
  self.func_names.clear()
  self.symbols.clear()
  self.f64_constants.clear()
  self.i64_constants.clear()
  self.locals_by_func.clear()
  self.global_syms.clear()
  self.arc_cleanup.clear()
  self.step_count = 0
  self.finished = false
  self.exit_code = 0
  self.paused = false
  self.cancelled = false
  self.step_event_hit = false
  self.error = ""
  self.current_line = 0
  self.argc = 0
  self.argv_addr = 0U
  self.vis_event_queue.clear()
  // vis_event_lines 同清（oracle state.rs:201 有 clear——审阅 P2-3：注入
  // 配置随 reset 卸载，session 复用 VM 时不按旧行号表产事件）
  self.vis_event_lines.clear()
  self.breakpoints.clear()
  self.last_accessed_vars.clear()
  self.heatmap.clear()
  self.snapshot_vars.clear()
  self.last_snapshot_step = 0
  self.waiting_input = false
  self.handler_stack.clear()
  self.exec_mode = Running
  self.exception_ref = None
  self.unwind_remaining_frames = 0
  self.unwind_target = None
  // 内存：字节清零 + 堆元数据整体重建（隔离预算是会话配置，跨重建保留）。
  let budget = self.mem_map.quarantine_budget()
  self.mem_map = @memory.MemoryMap::new()
  self.mem_map.set_quarantine_budget(budget)
  self.memory.reset()
  self.mem_stack_top = @bytecode.STACK_START
}

// ---------------------------------------------------------------------------
// 装载通道（setup 协议的 vm 侧原语——libc 自举的 12 步组装随批四号；
// 此处只提供与 Rust `VitroVM` 对齐的装载入口）
// ---------------------------------------------------------------------------

///|
/// 装载指令流（ip 归零）。
pub fn VitroVM::load_program(
  self : VitroVM,
  code : Array[@opcode.Instruction],
) -> Unit {
  self.code.clear()
  for instr in code {
    self.code.push(instr)
  }
  self.ip = 0
}

///|
/// 注册函数元数据到指定索引（超 `MAX_FUNCTIONS` 拒绝，返回 false 表不扩——
/// U2#13 照搬；调用方静默跳过是编译器侧防御口径）。
pub fn VitroVM::register_function(
  self : VitroVM,
  idx : Int,
  meta : @bytecode.FuncMeta,
) -> Bool {
  if idx < 0 || idx >= MAX_FUNCTIONS {
    return false
  }
  while self.func_table.length() <= idx {
    self.func_table.push(None)
  }
  self.func_table[idx] = Some(meta)
  true
}

///|
/// 注册函数名到指定索引（与 `register_function` 同上限语义）。
pub fn VitroVM::register_function_name(
  self : VitroVM,
  idx : Int,
  name : String,
) -> Bool {
  if idx < 0 || idx >= MAX_FUNCTIONS {
    return false
  }
  while self.func_names.length() <= idx {
    self.func_names.push(None)
  }
  self.func_names[idx] = Some(name)
  true
}

///|
/// 装载符号表 + **重建派生索引**（`locals_by_func` / `global_syms`——
/// 装载期单次构建，此后帧切换 O(1)）。
pub fn VitroVM::set_symbols(
  self : VitroVM,
  symbols : Array[@bytecode.Symbol],
) -> Unit {
  self.symbols.clear()
  for s in symbols {
    self.symbols.push(s)
  }
  self.locals_by_func.clear()
  self.global_syms.clear()
  for s in self.symbols {
    if s.is_local {
      let bucket = match self.locals_by_func.get(s.func_name) {
        Some(m) => m
        None => {
          let m : Map[Int, String] = Map([])
          self.locals_by_func.set(s.func_name, m)
          m
        }
      }
      bucket.set(s.addr.reinterpret_as_int(), s.name)
    } else {
      self.global_syms.set(s.addr.reinterpret_as_int(), s.name)
    }
  }
}

///|
/// 装载可视化事件行登记（会话注入配置，快照不含）。
pub fn VitroVM::set_vis_event_lines(
  self : VitroVM,
  lines : Array[(Int, Int, String)],
) -> Unit {
  self.vis_event_lines.clear()
  for l in lines {
    self.vis_event_lines.push((l.0, l.1, l.2))
  }
}

///|
/// 装载 32 位全局初始化表（offset 相对 `GLOBAL_START`；受检写入）。
pub fn VitroVM::set_globals_32(
  self : VitroVM,
  globals : Array[(UInt, Int)],
) -> Unit {
  for pair in globals {
    let addr = @bytecode.GLOBAL_START + pair.0
    let v = pair.1.reinterpret_as_uint()
    ignore(self.memory.store_u32(self.mem_map, addr, v))
  }
}

///|
/// 装载 64 位全局初始化表（offset 相对 `GLOBAL_START`；受检写入）。
pub fn VitroVM::set_globals_64(
  self : VitroVM,
  globals : Array[(UInt, UInt64)],
) -> Unit {
  for pair in globals {
    let addr = @bytecode.GLOBAL_START + pair.0
    ignore(self.memory.store_u64(self.mem_map, addr, pair.1))
  }
}

///|
/// 装载 f64 常量池。
pub fn VitroVM::set_f64_constants(
  self : VitroVM,
  constants : Array[Double],
) -> Unit {
  self.f64_constants.clear()
  for c in constants {
    self.f64_constants.push(c)
  }
}

///|
/// 装载 i64 常量池。
pub fn VitroVM::set_i64_constants(
  self : VitroVM,
  constants : Array[Int64],
) -> Unit {
  self.i64_constants.clear()
  for c in constants {
    self.i64_constants.push(c)
  }
}

///|
/// C 风格字符串安全写入（含 NUL 终止；字节口径 = `@bytecode.cstring_bytes`
/// 单源——Latin-1 ≤0xFF / UTF-8 >0xFF，P4 口径照搬）。
///
/// 越界/NULL 区静默跳过（照搬 Rust `write_cstring`：装载期数据由 codegen
/// 保证合法，越界属编译器 bug 不炸运行）；UAF 置 `error`（结构化 trap 与
/// 文案渲染单点随批二号 executor 统一，此处登记占位）。
pub fn VitroVM::write_cstring(self : VitroVM, addr : UInt, s : String) -> Unit {
  let bytes = @bytecode.cstring_bytes(s)
  let raw : Array[Byte] = Array(capacity=bytes.length() + 1)
  for b in bytes {
    raw.push(b)
  }
  raw.push(b'\x00')
  match self.memory.write_bytes(self.mem_map, addr, Bytes::from_array(raw)) {
    Ok(_) => ()
    Err(@memory.MemFault::UseAfterFree(_, _)) =>
      self.error = "运行时错误：E3060 Use-After-Free（字符串装载命中已释放区域）"
    Err(_) => ()
  }
}

///|
/// 设置命令行参数（R1 ③ 照搬 `state.rs:269-298`：argv 区自
/// `GLOBAL_REGION_LIMIT` 向下分配——指针数组 [array_addr, +argc*4) +
/// 字符串数据向上排；与全局数据区冲突 / 超区则置 error 返回）。
pub fn VitroVM::setup_argv(
  self : VitroVM,
  argc : Int,
  argv : Array[String],
  global_data_end : UInt,
) -> Unit {
  if argc <= 0 || argv.is_empty() {
    self.argc = 0
    self.argv_addr = 0U
    return
  }
  let footprint = @bytecode.argv_region_footprint(argc, argv)
  let array_addr = @bytecode.GLOBAL_REGION_LIMIT - footprint
  if array_addr < @bytecode.align4(global_data_end) {
    self.error = "setup_argv: 命令行参数与全局数据区冲突（全局数据过大），无法安放 argv"
    return
  }
  let mut string_addr = array_addr + argc.reinterpret_as_uint() * 4U
  let count = if argc < argv.length() { argc } else { argv.length() }
  for i = 0; i < count; i = i + 1 {
    let s = argv[i]
    // 推进口径 = UTF-8 字节数（与 `argv_region_footprint` 同口径——Rust
    // `s.len()` 同义）；**写入**字节走 cstring 单源（Latin-1 ≤0xFF）——
    // 非 ASCII 参数串内容短于推进量，尾部留零间隙，与 oracle 逐字节同形。
    let byte_len = @util.utf8_len(s).reinterpret_as_uint()
    let next = string_addr + byte_len + 1U
    if next > @bytecode.GLOBAL_REGION_LIMIT {
      self.error = "setup_argv: 命令行参数过长，超出全局数据区"
      return
    }
    self.write_cstring(string_addr, s)
    let slot = array_addr + i.reinterpret_as_uint() * 4U
    ignore(self.memory.store_u32(self.mem_map, slot, string_addr))
    string_addr = next
  }
  self.argc = argc
  self.argv_addr = array_addr
}

///|
/// 设置步数预算（会话级配置——reset 保留；装载通道禁设，见字段注释）。
pub fn VitroVM::set_max_steps(self : VitroVM, max_steps : Int) -> Unit {
  self.max_steps = max_steps
}

///|
/// 设置调用深度上限（会话级配置）。
pub fn VitroVM::set_call_depth_limit(self : VitroVM, limit : Int) -> Unit {
  self.call_depth_limit = limit
}

///|
/// 设置确定性模式（会话级配置：true = time/clock 恒 0、rand 走固定 LCG；
/// capi vitro_set_deterministic 对应物）。
pub fn VitroVM::set_deterministic(self : VitroVM, deterministic : Bool) -> Unit {
  self.deterministic = deterministic
}
