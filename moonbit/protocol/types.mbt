// 协议 DTO 族（照搬 native/src/unified/types.rs + root_cause.rs +
// session.rs::VisEvent，2026-09-27）。StepPayload 在内存中的完整表示用于
// 前端解码后的状态；跨 FFI 传输时经 stream 差分编码（S7 批一号段二）。
// 字段名/类型/语义与 Rust 侧逐字段对齐（serde 字段名 = 原名 snake_case）；
// emitter（显式 JSON 序列化）随 gateway serve 批落地，本批先定形数据面。

///| 可视化事件（Rust 侧定义在 session.rs；本包因 StepPayload.vis_events

///|
/// 字段自持收拢至此——落点裁定见 moon.pkg 头注）。
pub(all) struct VisEvent {
  ty : Int
  line : Int
  extra0 : Int
  extra1 : Int
  extra2 : Int
  context : String
} derive(Debug)

///| 根因提示（认知推理层 P0；Rust 侧 unified/root_cause.rs）。

///|
/// 由 TraceAnalyzer 生成、前端展示的运行期 trap 根因结构化提示。
pub(all) struct RootCauseHint {
  /// 根因类别标识，如 "OffByOne"/"UseAfterFree"/"UninitializedIndex"/
  ///| "WrongStartIndex"/"SizeMismatch"/"NullDeref"/"DivZero"/"DoubleFree"
  category : String
  /// 给学生看的一句话自然语言解释
  one_liner : String
  /// 与根因相关的源码行（IDE 内可点击）
  related_lines : Array[Int]
  /// 建议修复类型（对齐既有 auto-fix 标识）："ChangeLeToLt"/"AddNullCheck"/
  ///| "InitVariable"/"FixLoopStart"/"FixArraySize"/"SetNullAfterFree"/
  ///| "AvoidDivZero"/"None"
  suggested_fix_kind : String
  /// 建议修复应用的具体行号（若已知）
  suggested_fix_line : Int?
  /// 修复的可读描述（如「将 <= 改为 <」）
  suggested_fix_desc : String?
} derive(Debug)

///|
/// 算法匹配（语义标注检测产物——2026-10-01 批四号自 session/dto.mbt 收拢
/// 进本包：session import time_travel 成环约束下，time_travel/teaching 两侧
/// 消费须走 protocol〔VisEvent/RootCauseHint 同款收编先例〕；Rust 侧该类型
/// 在 algorithm_detector/session 两域各一份靠 map 转换，本侧单源不造孪生）。
pub(all) struct AlgorithmMatch {
  name : String
  display_name : String
  func_name : String
  confidence : Int
  suggestion : String
  line : Int
  vis_events : Array[VisEvent]
} derive(Debug)

///|
/// 算法步骤语义快照（用于前端步骤标注）。
pub(all) struct AlgorithmStepSnapshot {
  algorithm_name : String
  display_name : String
  phase : String
  description : String
} derive(Debug)

///| 指针状态。emitter 文本对齐 Rust serde enum 序列化（"Valid"/"Freed"/

///|
/// "Null"/"Dangling"）。
pub(all) enum PointerStatus {
  Valid // 指向有效内存（栈、全局、已分配堆）
  Freed // 指向已释放的堆内存
  Null // NULL 指针
  Dangling // 悬空指针（越界或未初始化）
} derive(Debug, Eq, Compare)

///|
/// 指针状态的 JSON 文本（serde enum 形态：裸字符串）。
pub fn PointerStatus::to_json_text(self : PointerStatus) -> String {
  match self {
    Valid => "Valid"
    Freed => "Freed"
    Null => "Null"
    Dangling => "Dangling"
  }
}

///|
/// 指针变量快照（用于指针追踪动画）。
pub(all) struct PointerSnapshot {
  name : String
  addr : UInt
  ty_name : String
  /// mut：消费方 clone+mutate 使用形态
  mut target_addr : UInt
  target_name : String
  status : PointerStatus
} derive(Debug)

///|
/// 当前步访问的变量（用于变量级高亮）。
pub(all) struct AccessedVar {
  name : String
  /// "Read" | "Write"（保持 Rust 侧 String 形态，不造枚举）；
  /// mut：消费方 clone+mutate 使用形态
  mut access_type : String
} derive(Debug)

///|
/// FRB 友好的变量快照（ty 已格式化为字符串）。
pub(all) struct ApiVariableSnapshot {
  name : String
  addr : UInt
  is_local : Bool
  ty_name : String
  /// mut：decode 差分应用与消费方 clone+mutate 使用形态（Rust 同构）
  mut value : String
} derive(Debug)

///|
/// 数组变量快照（用于算法可视化条形图）。
pub(all) struct ArraySnapshot {
  name : String
  element_ty : String
  /// mut：消费方 clone+mutate 使用形态
  mut elements : Array[String]
  /// U2#10：元素被截断的可见标记
  truncated : Bool
} derive(Debug)

///|
/// FRB 友好的调用帧信息。
pub(all) struct ApiFrameInfo {
  func_name : String
  return_line : Int
} derive(Debug)

///| 每步的轻量数据包，传输到 Flutter 前端作为 FrameCache。

///|
/// 14 字段 = step_payload_fields_v0_1() 白名单（v0.1 冻结，只增不改）。
pub(all) struct StepPayload {
  step_index : Int
  code_line : Int
  func_name : String
  semantic_label : String
  algorithm_step : AlgorithmStepSnapshot?
  local_vars : Array[ApiVariableSnapshot]
  mut call_stack : Array[ApiFrameInfo]
  mut vis_events : Array[VisEvent]
  heatmap_line : Int
  heatmap_count : UInt64
  mut accessed_vars : Array[AccessedVar]
  mut array_snapshots : Array[ArraySnapshot]
  mut pointer_snapshots : Array[PointerSnapshot]
  root_cause_hint : RootCauseHint?
} derive(Debug)

///|
/// 语义元数据（用于进度条标签和智能检查点）。
pub(all) struct StepMeta {
  code_line : Int
  func_name : String
  loop_depth : Int
  semantic_label : String
} derive(Debug)

///|
/// 调试摘要（悬浮球零延迟）。
pub(all) struct DebugSummary {
  local_vars : Array[ApiVariableSnapshot]
  call_stack : Array[ApiFrameInfo]
  output_len : Int
} derive(Debug)

///|
/// 执行热力图增量。
pub(all) struct HeatmapDelta {
  line : Int
  count : UInt64
} derive(Debug)

///|
/// 编译并启动统一模式的返回结果。
pub(all) struct UnifiedRunResult {
  success : Bool
  error : String?
  total_steps : Int
  finished : Bool
} derive(Debug)

///|
/// 批量自动执行的返回结果。
pub(all) struct AutoStepResult {
  payloads : Array[StepPayload]
  finished : Bool
  trapped : Bool
  waiting_input : Bool
  paused : Bool
  current_line : Int
  trap_message : String?
  /// 当前 frame_cache 窗口起始步号，供前端同步窗口起点
  cache_start_step : Int
} derive(Debug)

///|
/// seek 到指定步的返回结果。
pub(all) struct SeekResult {
  success : Bool
  payload : StepPayload?
  error : String?
} derive(Debug)

///| 执行热力图数据。line_counts 保持 Rust 元组语义（serde 落二元数组

///|
/// [line, count]，emitter 随 gateway serve 批对齐——moon.pkg 头注登记）。
pub(all) struct HeatmapData {
  line_counts : Array[(Int, UInt64)]
  max_count : UInt64
} derive(Debug)
