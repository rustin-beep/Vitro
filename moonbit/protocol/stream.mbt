// 统一模式 StepPayload 差分编码（S7 批一号段二，2026-09-27）。
// 照搬 native/src/unified/stream.rs + stream/encode.rs + stream/diff.rs。
// 编码规则：base_payloads 含每 batch 第 1 个完整快照（step 0）；deltas 含
// 后续步差分（基于前一步局部变量状态）；symbol_table 全局去重字符串池
// （索引 0 预留空字符串）。MoonBit 侧 Map 即 LinkedHashMap（陷阱 #33，
// 符号表插入序 = symbols 数组序，index 仅做 O(1) 反查——与 Rust HashMap
// 的无序性不构成差分面：导出以 symbols 数组序为准，两侧一致）。
// 消费方向：gateway serve 出口（批三号 JSON 序列化）与前端 FrameCache
// 解码（TS @vitro/protocol 消费面）；encode/decode 往返等价锚在
// stream_wbtest（8 锚照搬 Rust tests 模块）。

///|
/// 符号表索引。
pub type SymIdx = Int

///|
/// 使用符号表的变量快照（不变数据 dedup）。
pub(all) struct ApiVarSnapshotRef {
  name_idx : SymIdx
  addr : UInt
  is_local : Bool
  ty_name_idx : SymIdx
  /// mut：encode 差分累积应用（current_full_ref）使用形态
  mut value : String
} derive(Debug)

///|
pub extend ApiVarSnapshotRef with Debug::{to_repr}

///|
/// 差分变量：仅包含值发生变化的变量。
pub(all) struct VarDelta {
  name_idx : SymIdx
  value : String
} derive(Debug)

///|
pub extend VarDelta with Debug::{to_repr}

///|
/// 使用符号表的指针快照。
pub(all) struct PointerSnapshotRef {
  name_idx : SymIdx
  addr : UInt
  ty_name_idx : SymIdx
  target_addr : UInt
  target_name_idx : SymIdx
  status : PointerStatus
} derive(Debug)

///|
pub extend PointerSnapshotRef with Debug::{to_repr}

///| 使用符号表的数组快照（旧流 truncated 缺省 false 向后兼容——serde

///|
/// default 语义由 gateway 序列化批承接，本结构显式字段）。
pub(all) struct ArraySnapshotRef {
  name_idx : SymIdx
  element_ty_idx : SymIdx
  elements : Array[String]
  truncated : Bool
} derive(Debug)

///|
pub extend ArraySnapshotRef with Debug::{to_repr}

///|
/// 使用符号表的访问变量。
pub(all) struct AccessedVarRef {
  name_idx : SymIdx
  access_type_idx : SymIdx
} derive(Debug)

///|
pub extend AccessedVarRef with Debug::{to_repr}

///|
/// 使用符号表的调用帧。
pub(all) struct ApiFrameInfoRef {
  func_name_idx : SymIdx
  return_line : Int
} derive(Debug)

///|
pub extend ApiFrameInfoRef with Debug::{to_repr}

///|
/// 使用符号表的算法步骤。
pub(all) struct AlgorithmStepSnapshotRef {
  algorithm_name_idx : SymIdx
  display_name_idx : SymIdx
  phase_idx : SymIdx
  description_idx : SymIdx
} derive(Debug)

///|
pub extend AlgorithmStepSnapshotRef with Debug::{to_repr}

///|
/// 使用符号表的 StepPayload（基准快照）。
pub(all) struct StepPayloadRef {
  step_index : Int
  code_line : Int
  func_name_idx : SymIdx
  semantic_label_idx : SymIdx
  algorithm_step : AlgorithmStepSnapshotRef?
  local_vars : Array[ApiVarSnapshotRef]
  call_stack : Array[ApiFrameInfoRef]
  vis_events : Array[VisEvent]
  heatmap_line : Int
  heatmap_count : UInt64
  accessed_vars : Array[AccessedVarRef]
  array_snapshots : Array[ArraySnapshotRef]
  pointer_snapshots : Array[PointerSnapshotRef]
  root_cause_hint : RootCauseHint?
} derive(Debug)

///|
pub extend StepPayloadRef with Debug::{to_repr}

///|
/// 差分 StepPayload（基于前一个 StepPayloadRef 或 StepPayloadDelta）。
pub(all) struct StepPayloadDelta {
  step_index : Int
  code_line : Int
  func_name_idx : SymIdx
  semantic_label_idx : SymIdx
  algorithm_step : AlgorithmStepSnapshotRef?
  /// 值发生变化的变量。
  var_deltas : Array[VarDelta]
  /// 新出现的变量。
  new_vars : Array[ApiVarSnapshotRef]
  /// 消失的变量名索引。
  removed_var_name_indices : Array[SymIdx]
  /// None 表示调用栈无变化；Some(vec) 为完整新调用栈。
  call_stack : Array[ApiFrameInfoRef]?
  /// None 表示当前步无可视化事件；Some(vec) 为当前步完整事件列表。
  vis_events : Array[VisEvent]?
  heatmap_line : Int
  heatmap_count : UInt64
  /// None 表示访问变量集合无变化；Some(vec) 为完整新集合。
  accessed_vars : Array[AccessedVarRef]?
  /// None 表示数组快照集合无变化；Some(vec) 为新增/替换的数组快照。
  array_snapshots : Array[ArraySnapshotRef]?
  /// 已删除的数组变量名索引（相对于上一步）。
  removed_array_name_indices : Array[SymIdx]
  /// None 表示指针快照集合无变化；Some(vec) 为新增/替换的指针快照。
  pointer_snapshots : Array[PointerSnapshotRef]?
  /// 已删除的指针变量名索引（相对于上一步）。
  removed_pointer_name_indices : Array[SymIdx]
  root_cause_hint : RootCauseHint?
} derive(Debug)

///|
pub extend StepPayloadDelta with Debug::{to_repr}

///| Stream 批量传输单元（编码规则见模块头注；状态八字段由 gateway

///|
/// serve 批填充语义，encode_payloads 全部置默认值——与 Rust 同形）。
pub(all) struct StepStreamBatch {
  symbol_table : Array[String]
  base_payloads : Array[StepPayloadRef]
  deltas : Array[StepPayloadDelta]
  finished : Bool
  trapped : Bool
  waiting_input : Bool
  paused : Bool
  current_line : Int
  trap_message : String?
  /// 当前 frame_cache 窗口起始步号，供前端同步窗口起点。
  cache_start_step : Int
} derive(Debug)

///|
pub extend StepStreamBatch with Debug::{to_repr}

///|
/// 去重字符串池（索引 0 预留空字符串；导出序 = 插入序）。
struct SymbolTable {
  symbols : Array[String]
  index : Map[String, SymIdx]
}

///|
fn SymbolTable::new() -> SymbolTable {
  let t : SymbolTable = { symbols: [], index: Map([]), }
  // 索引 0 预留为空字符串
  ignore(t.insert(""))
  t
}

///|
fn SymbolTable::insert(self : SymbolTable, s : String) -> SymIdx {
  match self.index.get(s) {
    Some(idx) => idx
    None => {
      let idx = self.symbols.length()
      self.symbols.push(s)
      self.index.set(s, idx)
      idx
    }
  }
}

///|
fn SymbolTable::into_vec(self : SymbolTable) -> Array[String] {
  self.symbols
}

///|
/// 将一个 StepPayload 全量编码为符号表形态（基准快照）。
pub fn encode_step_payload(
  payload : StepPayload,
  sym : SymbolTable,
) -> StepPayloadRef {
  {
    step_index: payload.step_index,
    code_line: payload.code_line,
    func_name_idx: sym.insert(payload.func_name),
    semantic_label_idx: sym.insert(payload.semantic_label),
    algorithm_step: encode_algo_step(payload.algorithm_step, sym),
    local_vars: payload.local_vars.map(v => {
      name_idx: sym.insert(v.name),
      addr: v.addr,
      is_local: v.is_local,
      ty_name_idx: sym.insert(v.ty_name),
      value: v.value,
    }),
    call_stack: payload.call_stack.map(f => {
      func_name_idx: sym.insert(f.func_name),
      return_line: f.return_line,
    }),
    vis_events: payload.vis_events,
    heatmap_line: payload.heatmap_line,
    heatmap_count: payload.heatmap_count,
    accessed_vars: payload.accessed_vars.map(a => {
      name_idx: sym.insert(a.name),
      access_type_idx: sym.insert(a.access_type),
    }),
    array_snapshots: payload.array_snapshots.map(a => {
      name_idx: sym.insert(a.name),
      element_ty_idx: sym.insert(a.element_ty),
      elements: a.elements,
      truncated: a.truncated,
    }),
    pointer_snapshots: payload.pointer_snapshots.map(p => {
      name_idx: sym.insert(p.name),
      addr: p.addr,
      ty_name_idx: sym.insert(p.ty_name),
      target_addr: p.target_addr,
      target_name_idx: sym.insert(p.target_name),
      status: p.status,
    }),
    root_cause_hint: payload.root_cause_hint,
  }
}

///|
fn encode_algo_step(
  a : AlgorithmStepSnapshot?,
  sym : SymbolTable,
) -> AlgorithmStepSnapshotRef? {
  match a {
    Some(step) =>
      Some({
        algorithm_name_idx: sym.insert(step.algorithm_name),
        display_name_idx: sym.insert(step.display_name),
        phase_idx: sym.insert(step.phase),
        description_idx: sym.insert(step.description),
      })
    None => None
  }
}

///|
/// 相邻两步差分编码（照搬 encode.rs encode_step_delta）。
pub fn encode_step_delta(
  prev : StepPayload,
  curr : StepPayload,
  sym : SymbolTable,
  prev_vars : Map[SymIdx, String],
) -> StepPayloadDelta {
  // 当前步变量名 -> 快照（供 removed 判定）
  let curr_vars : Map[String, Bool] = Map([])
  for v in curr.local_vars {
    curr_vars.set(v.name, true)
  }
  let var_deltas : Array[VarDelta] = []
  let new_vars : Array[ApiVarSnapshotRef] = []
  let removed_var_name_indices : Array[SymIdx] = []
  for v in curr.local_vars {
    let name_idx = sym.insert(v.name)
    match prev_vars.get(name_idx) {
      Some(prev_val) =>
        if prev_val != v.value {
          var_deltas.push({ name_idx, value: v.value, })
        }
      None =>
        new_vars.push({
          name_idx,
          addr: v.addr,
          is_local: v.is_local,
          ty_name_idx: sym.insert(v.ty_name),
          value: v.value,
        })
    }
  }
  for v in prev.local_vars {
    let name_idx = sym.insert(v.name)
    if !curr_vars.get(v.name).unwrap_or(false) {
      removed_var_name_indices.push(name_idx)
    }
  }
  // call_stack 差分
  let call_stack : Array[ApiFrameInfoRef]? = if frame_lists_equal(
      prev.call_stack,
      curr.call_stack,
    ) {
    None
  } else {
    Some(
      curr.call_stack.map(f => {
        func_name_idx: sym.insert(f.func_name),
        return_line: f.return_line,
      }),
    )
  }
  // vis_events 差分
  let vis_events : Array[VisEvent]? = if vis_events_equal(
      prev.vis_events,
      curr.vis_events,
    ) {
    None
  } else {
    Some(curr.vis_events)
  }
  // accessed_vars 差分
  let accessed_vars : Array[AccessedVarRef]? = if accessed_vars_equal(
      prev.accessed_vars,
      curr.accessed_vars,
    ) {
    None
  } else {
    Some(
      curr.accessed_vars.map(a => {
        name_idx: sym.insert(a.name),
        access_type_idx: sym.insert(a.access_type),
      }),
    )
  }
  // 数组/指针差分：按名索引追踪新增/替换/删除
  let (array_snapshots, removed_array_name_indices) = diff_array_snapshots(
    prev.array_snapshots,
    curr.array_snapshots,
    sym,
  )
  let (pointer_snapshots, removed_pointer_name_indices) = diff_pointer_snapshots(
    prev.pointer_snapshots,
    curr.pointer_snapshots,
    sym,
  )
  {
    step_index: curr.step_index,
    code_line: curr.code_line,
    func_name_idx: sym.insert(curr.func_name),
    semantic_label_idx: sym.insert(curr.semantic_label),
    algorithm_step: encode_algo_step(curr.algorithm_step, sym),
    var_deltas,
    new_vars,
    removed_var_name_indices,
    call_stack,
    vis_events,
    heatmap_line: curr.heatmap_line,
    heatmap_count: curr.heatmap_count,
    accessed_vars,
    array_snapshots,
    removed_array_name_indices,
    pointer_snapshots,
    removed_pointer_name_indices,
    root_cause_hint: curr.root_cause_hint,
  }
}

///|
fn diff_array_snapshots(
  prev : Array[ArraySnapshot],
  curr : Array[ArraySnapshot],
  sym : SymbolTable,
) -> (Array[ArraySnapshotRef]?, Array[SymIdx]) {
  let mut all_equal = prev.length() == curr.length()
  if all_equal {
    let len_prev = prev.length()
    for i in 0..<len_prev {
      if !arrays_equal(prev[i], curr[i]) {
        all_equal = false
        break
      }
    }
  }
  if all_equal {
    return (None, [])
  }
  let curr_names : Map[String, Bool] = Map([])
  for a in curr {
    curr_names.set(a.name, true)
  }
  let removed : Array[SymIdx] = []
  for a in prev {
    if !curr_names.get(a.name).unwrap_or(false) {
      removed.push(sym.insert(a.name))
    }
  }
  let snapshots = curr.map(a => {
    name_idx: sym.insert(a.name),
    element_ty_idx: sym.insert(a.element_ty),
    elements: a.elements,
    truncated: a.truncated,
  })
  (Some(snapshots), removed)
}

///|
fn diff_pointer_snapshots(
  prev : Array[PointerSnapshot],
  curr : Array[PointerSnapshot],
  sym : SymbolTable,
) -> (Array[PointerSnapshotRef]?, Array[SymIdx]) {
  let mut all_equal = prev.length() == curr.length()
  if all_equal {
    let len_prev = prev.length()
    for i in 0..<len_prev {
      if !pointers_equal(prev[i], curr[i]) {
        all_equal = false
        break
      }
    }
  }
  if all_equal {
    return (None, [])
  }
  let curr_names : Map[String, Bool] = Map([])
  for p in curr {
    curr_names.set(p.name, true)
  }
  let removed : Array[SymIdx] = []
  for p in prev {
    if !curr_names.get(p.name).unwrap_or(false) {
      removed.push(sym.insert(p.name))
    }
  }
  let snapshots = curr.map(p => {
    name_idx: sym.insert(p.name),
    addr: p.addr,
    ty_name_idx: sym.insert(p.ty_name),
    target_addr: p.target_addr,
    target_name_idx: sym.insert(p.target_name),
    status: p.status,
  })
  (Some(snapshots), removed)
}

///| 将一组 StepPayload 编码为优化的 StepStreamBatch（照搬 encode_payloads；

///| prev_vars 增量维护逻辑逐句对齐——current_full_ref 应用 delta 后重建

///|
/// prev_vars，保证后续步差分基于累积状态而非相邻裸比较）。
pub fn encode_payloads(
  payloads : Array[StepPayload],
  cache_start_step : Int,
) -> StepStreamBatch {
  if payloads.is_empty() {
    return {
      symbol_table: [""],
      base_payloads: [],
      deltas: [],
      finished: false,
      trapped: false,
      waiting_input: false,
      paused: false,
      current_line: 0,
      trap_message: None,
      cache_start_step,
    }
  }
  let sym = SymbolTable::new()
  // 编码第 0 个 payload 为 base
  let base = encode_step_payload(payloads[0], sym)
  let deltas : Array[StepPayloadDelta] = []
  let prev_vars : Map[SymIdx, String] = Map([])
  for v in base.local_vars {
    prev_vars.set(v.name_idx, v.value)
  }
  // 对后续 payload 做差分编码
  let current_full_ref = clone_ref(base)
  let len_payloads = payloads.length()
  for i in 1..<len_payloads {
    let delta = encode_step_delta(payloads[i - 1], payloads[i], sym, prev_vars)
    // 增量更新 prev_vars：应用当前 delta 到 current_full_ref
    for d in delta.var_deltas {
      for v in current_full_ref.local_vars {
        if v.name_idx == d.name_idx {
          v.value = d.value
        }
      }
    }
    for v in delta.new_vars {
      current_full_ref.local_vars.push(v)
    }
    retain_ref_vars(current_full_ref, delta.removed_var_name_indices)
    prev_vars.clear()
    for v in current_full_ref.local_vars {
      prev_vars.set(v.name_idx, v.value)
    }
    deltas.push(delta)
  }
  let current_line = payloads[payloads.length() - 1].code_line
  {
    symbol_table: sym.into_vec(),
    base_payloads: [base],
    deltas,
    finished: false,
    trapped: false,
    waiting_input: false,
    paused: false,
    current_line,
    trap_message: None,
    cache_start_step,
  }
}

///|
/// current_full_ref 局部变量按 removed 索引表过滤（Rust retain 对应物）。
fn retain_ref_vars(
  current_full_ref : StepPayloadRef,
  removed : Array[SymIdx],
) -> Unit {
  let kept : Array[ApiVarSnapshotRef] = []
  for v in current_full_ref.local_vars {
    let mut drop = false
    for idx in removed {
      if v.name_idx == idx {
        drop = true
        break
      }
    }
    if !drop {
      kept.push(v)
    }
  }
  current_full_ref.local_vars.clear()
  for v in kept {
    current_full_ref.local_vars.push(v)
  }
}

///| Ref 基准快照浅重建（String 不可变共享；嵌套 Array 按引用共享——

///|
/// encode 侧仅读改 local_vars 一个字段，其余字段共享即安全）。
fn clone_ref(base : StepPayloadRef) -> StepPayloadRef {
  {
    step_index: base.step_index,
    code_line: base.code_line,
    func_name_idx: base.func_name_idx,
    semantic_label_idx: base.semantic_label_idx,
    algorithm_step: base.algorithm_step,
    local_vars: base.local_vars.map(v => {
      name_idx: v.name_idx,
      addr: v.addr,
      is_local: v.is_local,
      ty_name_idx: v.ty_name_idx,
      value: v.value,
    }),
    call_stack: base.call_stack,
    vis_events: base.vis_events,
    heatmap_line: base.heatmap_line,
    heatmap_count: base.heatmap_count,
    accessed_vars: base.accessed_vars,
    array_snapshots: base.array_snapshots,
    pointer_snapshots: base.pointer_snapshots,
    root_cause_hint: base.root_cause_hint,
  }
}

// ── 差分比较辅助（照搬 stream/diff.rs，5 函数逐字段对齐）──

///|
fn frame_lists_equal(a : Array[ApiFrameInfo], b : Array[ApiFrameInfo]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let len_a = a.length()
  for i in 0..<len_a {
    if a[i].func_name != b[i].func_name || a[i].return_line != b[i].return_line {
      return false
    }
  }
  true
}

///|
fn vis_events_equal(a : Array[VisEvent], b : Array[VisEvent]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let len_a = a.length()
  for i in 0..<len_a {
    let x = a[i]
    let y = b[i]
    if x.ty != y.ty ||
      x.line != y.line ||
      x.extra0 != y.extra0 ||
      x.extra1 != y.extra1 ||
      x.extra2 != y.extra2 ||
      x.context != y.context {
      return false
    }
  }
  true
}

///|
fn accessed_vars_equal(a : Array[AccessedVar], b : Array[AccessedVar]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let len_a = a.length()
  for i in 0..<len_a {
    if a[i].name != b[i].name || a[i].access_type != b[i].access_type {
      return false
    }
  }
  true
}

///|
fn arrays_equal(a : ArraySnapshot, b : ArraySnapshot) -> Bool {
  // 照搬 diff.rs:38 逐字（不含 truncated 比较）——Rust 侧现状：仅
  // truncated 翻转（elements 不变）不触发数组差分。潜在缺陷登记不修
  // 正（编码纪律 #4；U2#10 截断标记同族，S8 差异台账收口）。
  a.name == b.name && a.element_ty == b.element_ty && a.elements == b.elements
}

///|
fn pointers_equal(a : PointerSnapshot, b : PointerSnapshot) -> Bool {
  a.name == b.name &&
  a.addr == b.addr &&
  a.ty_name == b.ty_name &&
  a.target_addr == b.target_addr &&
  a.target_name == b.target_name &&
  a.status == b.status
}
