///| L7 执行层·VM 域的数据类型（Rust `vitro_vm::core::state` 的结构面照搬
/// + C# 异常三执行状态〔全新设计，Rust 无对应物〕）。
///
/// **新设计裁剪登记（相对 Rust 36 字段与伴随类型）**：
/// - JIT 全族不搬（总计划 F-3：宿主 V8 自带 JIT，模板 JIT 倾向不搬；
///   `ip_hits`/`trace_recorder`/`jit_traces`/`jit_stats`/`jit_enabled` 全无）；
/// - `global_count`（恒 0 死字段，Rust `snapshot.rs:264` 注释自证历史遗留）不搬；
/// - `pending_array_construction`（C++ `new[]` 构造守卫）随砍 C++ 不搬；
/// - `dirty_pages` 并入 `@memory.Memory`（脏页位图随载体）；
/// - `freed_logs` 并入 `@memory.MemoryMap`；
/// - `local_sym_map`/`global_sym_map`（offset→名字常驻索引）**结构性取消**：
///   Rust 每次 Call/Ret 全量重建（`state.rs:770-779`，坑 12 点名的性能热点），
///   唯一消费者（每步 `last_accessed_vars` 记录 / trap 文案 / 快照变量刷新）
///   改用**装载期派生索引**（`locals_by_func`/`global_syms`，从 symbols 一次
///   构建，帧切换 O(1)——见 state.mbt）；
/// - `trace`（`Arc<Vec<TraceEntryData>>`）死路径不搬（codegen 不发射
///   `__vitro_step`，勘察 §8.2 实测）；
/// - `usize::MAX` 宿主回调哨兵换 `Option`（`CallFrame.return_ip : Int?`，
///   None = 从 host 进入用户函数——qsort/bsearch 回调机制，穷尽可判）。

///|
/// 单步执行结果（照搬 Rust `core/state.rs:46-53` 五态）。
pub(all) enum StepResult {
  /// 正常执行一步。
  Ok
  /// 断点暂停。
  Paused
  /// 程序执行完毕（`Ret`/exit）。
  Finished
  /// 教学陷阱（error 字段承载文案）。
  Trap
  /// 等待输入（Interactive 模式 stdin 未就绪——可续跑，`ip` 已回退）。
  WaitingInput
} derive(Eq, Debug)

///|
/// 调用帧（照搬 Rust `CallFrame`，`core/state.rs:34-44`）。
///
/// `return_ip` 的 `None` 即**宿主回调哨兵**：qsort/bsearch 的比较器经
/// `call_user_function` 从 host 进入用户函数，该帧"无处可返"——Rust 用
/// `usize::MAX` 标识（`control.rs:214/236`），MoonBit 换 `Option` 显式表达
/// （勘察 §2.1 调用约定条目的等价变换）。
pub(all) struct CallFrame {
  /// 返回地址；`None` = 宿主回调帧（返回即回 host 分发点）。
  return_ip : Int?
  /// 本帧局部变量区基址（线性内存编址）。
  locals_base : UInt
  /// 本帧局部变量数。
  local_count : Int
  /// 函数名（trap 文案 / 教学调用栈展示）。
  func_name : String
  /// 调用前值栈深度（返回时截回）。
  original_stack_top : Int
  /// 调用者行号（教学调用栈展示）。
  caller_line : Int
  /// 栈上局部数组缓冲区表（V-P1-6 栈缓冲容量校验；随函数 meta 克隆进帧）。
  local_buffers : Array[@bytecode.LocalBuffer]
} derive(Eq, Debug)

///|
/// 可视化事件（照搬 Rust `VisEventData`，`runtime_state.rs:17-24`；
/// S8 teaching/steps 消费——`StepPayload` 的词汇来源之一）。
pub(all) struct VisEventData {
  ty : Int
  line : Int
  extra0 : Int
  extra1 : Int
  extra2 : Int
  context : String
} derive(Eq, Debug)

///|
/// 变量访问记录（每步的 `last_accessed_vars` 元素；访问类型复用
/// `@memory.AccessKind`——同一 Read/Write 语义，不另立枚举）。
pub(all) struct VariableAccess {
  name : String
  access_type : @memory.AccessKind
} derive(Eq, Debug)

// ---------------------------------------------------------------------------
// C# 异常三执行状态（CS 批硬前置——CSharp 前端引入计划 §4；C 前端零使用，
// v1 入形非事后补丁；VMSnapshot 一等含入 ⇒ 时间旅行免费安全）
// ---------------------------------------------------------------------------

///|
/// 执行模式（三执行状态之一：UNWINDING 状态机的模式位）。
///
/// - `Running`：正常执行（C 前端恒此态）；
/// - `Unwinding`：`Throw` 时当前帧无 handler ⇒ 逐帧弹出 `call_stack`
///   （每帧批量 release 局部引用 + 执行未完成的 finally，**每帧一 step**
///   ——行为契约「UNWINDING 不得合并单步」），直到命中 `unwind_target`
///   锁定的 handler 或传播出 main 转 trap。
pub(all) enum ExecMode {
  Running
  Unwinding
} derive(Eq, Debug)

///|
/// 异常 handler 栈帧（三执行状态之一：handler 栈）。
///
/// `TryBegin <catch_ip>` 压入、`TryEnd` 弹出；`Throw` 恢复
/// `stack_depth`/`mem_stack_top` 两项并跳 `catch_ip`（try 块内中间计算值
/// 自然作废——显式 handler 栈而非异常表，白箱可见，CS 计划 §4.1 裁决）。
/// `frame_idx` 记录压栈时的 `call_stack` 深度（跨帧展开时判断 handler
/// 是否仍属于当前帧）。
pub(all) struct HandlerFrame {
  catch_ip : Int
  frame_idx : Int
  stack_depth : Int
  mem_stack_top : UInt
} derive(Eq, Debug)

///|
/// 当前异常寄存器（三执行状态之一）：异常对象引用（堆地址）。
///
/// 在 `VitroVM` 上是 `exception_ref : UInt?`（None = 无活动异常）；
/// UNWINDING 中间态 = 异常寄存器 + `unwind_remaining_frames` +
/// `unwind_target` 三件（缺一则 seek 落在展开区间中间恢复出撕裂状态，
/// CS 计划 §4.5——故三件全部一等进 `VMSnapshot`）。
