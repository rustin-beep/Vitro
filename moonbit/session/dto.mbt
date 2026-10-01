// 会话侧 DTO 族（S7 批二号）：诊断/追踪/快照/内存地图/堆统计/步进结果
// 的协议形态。照搬 native/src/session.rs 的 serde 形态（serve 批的
// JSON 出口消费）；与 vm 侧 Data 型的互转 impl 随 serve 批接线落地
//（Rust 侧 From 双向 impl 是 capi/serve 的消费面，此处先定形数据面）。
// VisEvent 已在 protocol（批一号收拢），本包消费不重定义。

///|
/// 编译诊断（协议形态——含修复建议字段族，E1 出口的消费侧形态）。
pub(all) struct Diagnostic {
  line : Int
  column : Int
  error_code : Int
  severity : Int
  message : String
  fix_suggestion : String
  fix_kind : Int
  replace_start_line : Int
  replace_start_column : Int
  replace_end_line : Int
  replace_end_column : Int
  replacement_text : String
  filename : String
} derive(Debug)

///|
/// 算法匹配（2026-10-01 批四号收拢至 protocol——session import
/// time_travel 成环，time_travel/teaching 消费走 @protocol.AlgorithmMatch；
/// 此处定义已删，session.algorithm_matches 字段类型随改）。

///|
/// 执行追踪条目。
pub(all) struct TraceEntry {
  line : Int
  operation : String
} derive(Debug)

///|
/// 变量快照（会话侧——ty 为渲染好的字符串形态时用 protocol 的
/// ApiVariableSnapshot；本形态保留 Rust 的 i64 位模式版本，vm 互转
/// 随 serve 批）。
pub(all) struct VariableSnapshot {
  name : String
  addr : UInt
  is_local : Bool
  ty : @ast.Type
  value : Int64
} derive(Debug)

///|
/// 内存地图区域（C2 三段式——global/stack/heap）。
pub(all) struct MemoryRegion {
  addr : UInt
  size : Int
  name : String
  ty : String
  is_heap : Bool
  is_freed : Bool
  /// 分配时的源码行号（教学用途）
  alloc_line : Int
  /// 分配方式，如 "malloc" / "realloc" / "fopen"
  alloc_by : String
  /// 段标识："global" / "stack" / "heap"
  kind : String
} derive(Debug)

///|
/// 空闲块（free_list 条目的协议形态）。
pub(all) struct MemoryFragment {
  addr : UInt
  size : Int
} derive(Debug)

///|
/// 堆统计。
pub(all) struct HeapStats {
  /// 本次运行的堆起点（R1：动态堆起点）
  heap_base : Int
  /// 总堆空间（heap_offset - heap_base），字节
  total_heap : Int
  /// 已分配且未释放的堆内存，字节
  allocated : Int
  /// 外部碎片（free_list 中所有块之和），字节
  fragmented : Int
  /// 碎片率（0~100）
  fragmentation_rate : Int
} derive(Debug)

///|
/// 单步执行结果。
pub(all) struct StepResult {
  status : StepStatus
  current_line : Int
  output : String
  waiting_input : Bool
} derive(Debug)

///|
/// 步进状态四态。
pub(all) enum StepStatus {
  Paused
  WaitingInput
  Finished
  Trap
} derive(Debug, Eq, Compare)

///|
/// StepStatus 的协议文本（serve JSON 出口用——Rust serde enum 裸字符串
/// 形态对齐）。
pub fn StepStatus::to_text(self : StepStatus) -> String {
  match self {
    Paused => "Paused"
    WaitingInput => "WaitingInput"
    Finished => "Finished"
    Trap => "Trap"
  }
}
