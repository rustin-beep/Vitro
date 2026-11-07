// 蓝本注记：文内 Rust 源引用（`*.rs` 路径/行号/符号）均为档案态蓝本——tag rust-oracle-freeze（2026-10-05 删区），现为本仓自主基线。

///| L7 执行层·VM 域：**快照体系（`VMSnapshot` / `MemoryImage` 定形 +
/// `snapshot`/`restore` 单点）**。
///
/// 设计基准（总计划 §10 S6 验收线 = 门 3 集成版；勘察 §5.2）：
/// - **快照 = 执行状态的全量真相**：编译期产物（code/func_table/symbols/
///   常量池/派生索引/arc_cleanup/vis_event_lines）与**会话级配置**
///   （max_steps/call_depth_limit/deterministic）不入快照——`Session` 重建 /
///   配置随会话存续（Rust `snapshot.rs:51-53` 同口径）；
/// - **两端单点**：`snapshot()` 与 `restore()` 是仅有的两处字段枚举点，
///   字段增删由 struct 字面量构造的编译错强制同步（「字段增删不得要求
///   改动快照代码」的判定标准——除这两点外无散装同步义务）；
/// - **拷贝即快照**：MoonBit struct 引用语义 + 无 `Arc` ⇒ 快照侧全量深拷
///   （可变结构复制、`Bytes` 等不可变数据共享），`restore` 侧**再拷一次**——
///   快照持有者与运行态互不渗透（Rust `Arc::make_mut` 的"窗口首写克隆"
///   语义在此显式化为两次拷贝点，无引用意外共享的坑）；
/// - **隔离区三件套随快照**（`quarantine`/`quarantine_bytes`/
///   `quarantine_budget`——门 3 验收锚；"budget 是否应随快照"的口径争议
///   〔勘察 A-5〕未裁前照搬 Rust 现状）；
/// - **fd 元数据进快照**（`VfsSnapshot`——修复 Rust「VFS 不入快照 ⇒ 回退
///   后文件状态来自未来」的 P1 缺陷；文件数据在 VM 堆随 `MemoryImage` 行）；
/// - **C# 异常三状态一等含入**（handler 栈/异常寄存器/UNWINDING 三件——
///   时间旅行免费安全，总计划 §4 L7 行）。
///
/// `MemoryImage::Delta`（脏页增量）是**检查点存储形态**——生成/应用通道
/// 随门 3 集成批（CheckpointManager 的 checkpoint 重放方案，总计划 §5
/// 「Trap 回退改检查点+正向重放」）；本批只定形枚举。

///|
/// 1MB 载体的快照形态（照搬 Rust `MemoryImage` 二分，`snapshot.rs:9-15`）。
#derive(Eq, Debug)
pub(all) enum MemoryImage {
  /// 全量 1MB 逐字节。
  Full(FixedArray[Byte])
  /// 脏页增量：(base_step, pages)——`base_step` 为所基于的最近 Full 快照
  /// 步号；`pages` 为 (页号, 页字节) 对（页号 0..255，`PAGE_SIZE` 4096）。
  Delta(Int32, Array[(Int32, FixedArray[Byte])])
}

///|
pub extend MemoryImage with Debug::{to_repr}

///|
pub extend MemoryImage with Eq::{not_equal, equal}

///|
/// VM 执行状态快照（全量真相；结构含 C# 异常三状态与宿主域三态）。
pub(all) struct VMSnapshot {
  // ── 内存 ──
  /// 1MB 载体（`snapshot()` 恒产 Full；Delta 是检查点层的存储优化形态）。
  memory : MemoryImage
  /// 堆元数据全量（含隔离区三件套与 region refcount——随条目自动随行）。
  mem : @memory.MemorySnapshot
  // ── 值栈与调用 ──
  stack : Array[UInt64]
  call_stack : Array[CallFrame]
  ip : Int32
  mem_stack_top : UInt32
  // ── 运行控制 ──
  step_count : Int32
  current_line : Int32
  finished : Bool
  exit_code : Int32
  error : String
  /// trap 的结构化 E 码（#261——与 `error` 同生命周期，随快照往返）。
  trap_code : String
  paused : Bool
  cancelled : Bool
  step_event_hit : Bool
  waiting_input : Bool
  qsort_depth : Int32
  argc : Int32
  argv_addr : UInt32
  // ── 教学观测 ──
  vis_event_queue : Array[VisEventData]
  /// 断点（Set 无序 ⇒ 排序后存数组；restore 重建 Set）。
  breakpoints : Array[Int32]
  /// 执行热力图（行号 → 计数；P0b-1 定长数组——snapshot/restore 双向深拷贝）。
  heatmap : FixedArray[UInt64]
  /// 无限循环诊断的变量快照。
  snapshot_vars : Map[String, UInt64]
  last_snapshot_step : Int32
  // ── 宿主域三态（host 快照通道）──
  output : @host.OutputLog
  input : @host.InputState
  rand_seed : UInt32
  vfs : @host.VfsSnapshot
  // ── C# 异常三执行状态（一等含入——展开中间态可快照，CS 计划 §4.5）──
  exec_mode : ExecMode
  exception_ref : UInt32?
  unwind_remaining_frames : Int32
  unwind_target : HandlerFrame?
  handler_stack : Array[HandlerFrame]
}

///|
/// 抓快照（Full 形态；全字段深拷）。
pub fn VitroVM::snapshot(self : VitroVM) -> VMSnapshot {
  let stack_copy : Array[UInt64] = Array(capacity=self.stack.length())
  for v in self.stack {
    stack_copy.push(v)
  }
  let call_copy : Array[CallFrame] = Array(capacity=self.call_stack.length())
  for f in self.call_stack {
    let buffers : Array[@bytecode.LocalBuffer] = Array(
      capacity=f.local_buffers.length(),
    )
    for b in f.local_buffers {
      buffers.push(@bytecode.LocalBuffer::{
        offset: b.offset,
        size: b.size,
        name: b.name,
      })
    }
    call_copy.push(CallFrame::{
      return_ip: f.return_ip,
      locals_base: f.locals_base,
      local_count: f.local_count,
      func_name: f.func_name,
      original_stack_top: f.original_stack_top,
      caller_line: f.caller_line,
      local_buffers: buffers,
    })
  }
  let vis_copy : Array[VisEventData] = Array(
    capacity=self.vis_event_queue.length(),
  )
  for e in self.vis_event_queue {
    vis_copy.push(VisEventData::{
      ty: e.ty,
      line: e.line,
      extra0: e.extra0,
      extra1: e.extra1,
      extra2: e.extra2,
      context: e.context,
    })
  }
  let bps : Array[Int32] = Array(capacity=self.breakpoints.length())
  for bp in self.breakpoints {
    bps.push(bp)
  }
  bps.sort_by(fn(a, b) { a.compare(b) })
  // P0b-1：整组深拷贝（FixedArray 引用语义——快照与活体必须独立）
  let heatmap_copy : FixedArray[UInt64] = FixedArray::make(
    self.heatmap.length(),
    0UL,
  )
  for i = 0; i < self.heatmap.length(); i = i + 1 {
    heatmap_copy[i] = self.heatmap[i]
  }
  let vars_copy : Map[String, UInt64] = Map([])
  for k, v in self.snapshot_vars {
    vars_copy.set(k, v)
  }
  let handlers_copy : Array[HandlerFrame] = Array(
    capacity=self.handler_stack.length(),
  )
  for h in self.handler_stack {
    handlers_copy.push(HandlerFrame::{
      catch_ip: h.catch_ip,
      frame_idx: h.frame_idx,
      stack_depth: h.stack_depth,
      mem_stack_top: h.mem_stack_top,
    })
  }
  VMSnapshot::{
    memory: Full(self.memory.clone_raw()),
    mem: self.mem_map.dump(),
    stack: stack_copy,
    call_stack: call_copy,
    ip: self.ip,
    mem_stack_top: self.mem_stack_top,
    step_count: self.step_count,
    current_line: self.current_line,
    finished: self.finished,
    exit_code: self.exit_code,
    error: self.error,
    trap_code: self.trap_code,
    paused: self.paused,
    cancelled: self.cancelled,
    step_event_hit: self.step_event_hit,
    waiting_input: self.waiting_input,
    qsort_depth: self.qsort_depth,
    argc: self.argc,
    argv_addr: self.argv_addr,
    vis_event_queue: vis_copy,
    breakpoints: bps,
    heatmap: heatmap_copy,
    snapshot_vars: vars_copy,
    last_snapshot_step: self.last_snapshot_step,
    output: self.output.snapshot(),
    input: self.input.snapshot(),
    rand_seed: self.rand.seed,
    vfs: self.vfs.snapshot(),
    exec_mode: self.exec_mode,
    exception_ref: self.exception_ref,
    unwind_remaining_frames: self.unwind_remaining_frames,
    unwind_target: self.unwind_target,
    handler_stack: handlers_copy,
  }
}

///|
/// 恢复快照（整体替换执行状态；**restore 侧再拷一次**——快照对象与恢复后
/// 的运行态互不渗透，持有者手里的快照不被后续执行污染）。
///
/// 瞬时观测 `last_accessed_vars` 不随快照（每步重置，无历史语义）——
/// restore 后清空。编译期产物（code/func_table/…）与会话配置不动。
///
/// **会话配置不随快照回退（#430，2026-11-04）**：`breakpoints`/`paused`
/// 是会话层配置（用户意图）而非程序执行状态——restore **保留现役值**，
/// 不再被快照覆写。旧形态按快照覆写：时间旅行越窗 seek 回退到检查点后
/// 用户断点被静默清空、续跑永不命中（M26 A1 P1）；若快照采于
/// paused=true 还会反向引入假暂停（同一缺陷另一面）。快照侧两字段仍
/// 记录（诊断价值），仅 restore 不消费——有意偏离 Rust oracle 照搬渊源
/// （#430 拍板会话配置归会话层单源；oracle 侧缺陷形态已随删区不可追修）。
pub fn VitroVM::restore(self : VitroVM, snap : VMSnapshot) -> Unit {
  // #430：现役会话配置快照暂存（restore 尾回填）
  let keep_paused = self.paused
  let keep_bps : Array[Int32] = Array(capacity=self.breakpoints.length())
  for bp in self.breakpoints {
    keep_bps.push(bp)
  }
  match snap.memory {
    Full(bytes) => self.memory.restore_raw(clone_byte_array(bytes))
    Delta(_, _) =>
      // restore 只接受 Full（Delta 的重建是检查点层职责——先回 base Full
      // 再逐页应用；直接喂 Delta = 调用方错误，fail loud）。
      abort(
        "VitroVM::restore: 不接受 Delta 形态（先由检查点层重建为 Full）",
      )
  }
  self.mem_map.load(snap.mem)
  self.stack.clear()
  for v in snap.stack {
    self.stack.push(v)
  }
  self.call_stack.clear()
  for f in snap.call_stack {
    let buffers : Array[@bytecode.LocalBuffer] = Array(
      capacity=f.local_buffers.length(),
    )
    for b in f.local_buffers {
      buffers.push(@bytecode.LocalBuffer::{
        offset: b.offset,
        size: b.size,
        name: b.name,
      })
    }
    self.call_stack.push(CallFrame::{
      return_ip: f.return_ip,
      locals_base: f.locals_base,
      local_count: f.local_count,
      func_name: f.func_name,
      original_stack_top: f.original_stack_top,
      caller_line: f.caller_line,
      local_buffers: buffers,
    })
  }
  self.ip = snap.ip
  self.mem_stack_top = snap.mem_stack_top
  self.step_count = snap.step_count
  self.current_line = snap.current_line
  self.finished = snap.finished
  self.exit_code = snap.exit_code
  self.error = snap.error
  self.trap_code = snap.trap_code
  // paused 不覆写（#430：会话配置——尾部回填现役值）
  self.cancelled = snap.cancelled
  self.step_event_hit = snap.step_event_hit
  self.waiting_input = snap.waiting_input
  self.qsort_depth = snap.qsort_depth
  self.argc = snap.argc
  self.argv_addr = snap.argv_addr
  self.vis_event_queue.clear()
  for e in snap.vis_event_queue {
    self.vis_event_queue.push(VisEventData::{
      ty: e.ty,
      line: e.line,
      extra0: e.extra0,
      extra1: e.extra1,
      extra2: e.extra2,
      context: e.context,
    })
  }
  // breakpoints 不覆写（#430：会话配置——尾部回填现役集）
  ignore(snap.breakpoints)
  // P0b-1：深拷贝回放——restore 后的自增不得回写 snap（检查点复用面，
  // 锚 p0b_heat_snapshot_deep_copy_no_alias）
  let heat_restore : FixedArray[UInt64] = FixedArray::make(
    snap.heatmap.length(),
    0UL,
  )
  for i = 0; i < snap.heatmap.length(); i = i + 1 {
    heat_restore[i] = snap.heatmap[i]
  }
  self.heatmap = heat_restore
  self.snapshot_vars.clear()
  for k, v in snap.snapshot_vars {
    self.snapshot_vars.set(k, v)
  }
  self.last_snapshot_step = snap.last_snapshot_step
  // 宿主域三态：restore 侧独立拷贝（快照对象不被运行态共享）
  self.output = snap.output.snapshot()
  self.input = snap.input.snapshot()
  self.rand = @host.RandState::new(snap.rand_seed)
  self.vfs.restore(snap.vfs)
  // C# 异常三状态
  self.exec_mode = snap.exec_mode
  self.exception_ref = snap.exception_ref
  self.unwind_remaining_frames = snap.unwind_remaining_frames
  self.unwind_target = snap.unwind_target
  self.handler_stack.clear()
  for h in snap.handler_stack {
    self.handler_stack.push(HandlerFrame::{
      catch_ip: h.catch_ip,
      frame_idx: h.frame_idx,
      stack_depth: h.stack_depth,
      mem_stack_top: h.mem_stack_top,
    })
  }
  self.last_accessed_vars.clear()
  // #430 尾部回填：现役会话配置（断点/暂停）在执行状态恢复后原样保留
  self.paused = keep_paused
  self.breakpoints.clear()
  for bp in keep_bps {
    self.breakpoints.add(bp)
  }
}

///|
fn clone_byte_array(src : FixedArray[Byte]) -> FixedArray[Byte] {
  let out = FixedArray::make(src.length(), b'\x00')
  for i = 0; i < src.length(); i = i + 1 {
    out[i] = src[i]
  }
  out
}
