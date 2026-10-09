// 诊断教学域类型层（历史出处 native/src/diagnostics/{error_catalog,
// knowledge_graph,misconception_patterns,learning_path,auto_fix}.rs
// ——已随 2026-10-05 删区消失，tag rust-oracle-freeze 可回溯，类型定义
// 现为本仓自主维护基线；FixTarget 为自持形态——Rust 侧复用 session::
// Diagnostic，本包零 import 故转装，见 moon.pkg 头注）。

///|
/// 静态修复载荷的坐标锚定模式（勘察 A3 拆分：载荷文案是数据、
/// 坐标计算是机制——本枚举是表与机制的接口）。
pub enum FixAnchor {
  /// 手工提示（fix_kind=4 形态）：坐标全 0、无替换文本
  Manual
  /// 行末锚定（fix_kind=2 插入形态）：坐标 = (line, 行尾 trim_end 长) ×2
  LineEnd
} derive(Debug)

///|
/// 静态修复载荷（error_catalog.rs generate_fix 的纯静态码子集）。
pub(all) struct FixPayload {
  suggestion : String
  fix_kind : Int
  anchor : FixAnchor
  text : String
} derive(Debug)

///|
/// 知识图谱概念节点（knowledge_graph.rs ConceptNode 照搬）。
pub(all) struct ConceptNode {
  id : String
  /// "Compile" | "Memory" | "ControlFlow"
  domain : String
  title : String
  description : String
  /// 1-5
  difficulty : Int
  related_card_ids : Array[String]
} derive(Debug)

///|
/// 概念间有向边（knowledge_graph.rs ConceptEdge 照搬）。
pub(all) struct ConceptEdge {
  from_id : String
  to_id : String
  /// "Prerequisite" | "LeadsTo" | "CommonMistake" | "UsedTogether" | "Contradicts"
  relation : String
  /// 0.0 ~ 1.0。oracle 系 f32、本侧 Double——现状取值全为十进制常量
  ///（0.6/0.7/0.8/0.9）两侧文本一致，**系常量域遮蔽非宽度无害**（审阅
  /// F6 登记）：表内新增非十进制 strength 时须过 round_to_f32 语义化
  strength : Double
} derive(Debug)

///|
/// 学生编译历史单条记录（misconception_patterns.rs CompileRecord 照搬）。
pub(all) struct CompileRecord {
  /// Unix 毫秒时间戳（机制不消费，仅为记录保真）
  timestamp_ms : Int64
  success : Bool
  error_codes : Array[Int]
  trap_message : String?
} derive(Debug)

///|
/// 预置误区模式（misconception_patterns.rs MisconceptionPattern 照搬）。
pub(all) struct MisconceptionPattern {
  id : String
  name : String
  description : String
  /// 触发本模式的错误码集合（空 = 仅 trap 关键词匹配，如 M05）
  error_codes : Array[Int]
  min_occurrences : Int
  time_window : Int
} derive(Debug)

///|
/// 检出的误区（misconception_patterns.rs DetectedMisconception 照搬）。
pub(all) struct DetectedMisconception {
  pattern_id : String
  pattern_name : String
  description : String
  occurrence_count : Int
  /// 0.0 ~ 1.0（occurrences / min(window, records)）
  confidence : Double
} derive(Debug)

///|
/// 学习路径单步（learning_path.rs PathStep 照搬）。
pub(all) struct PathStep {
  /// "ReadKnowledgeCard" | "StudyTemplate" | "CompleteExercise" | "ReviewOwnCode"
  step_type : String
  title : String
  detail : String
  /// 卡片/模板/练习 id（oracle 现状存在悬空引用——照搬不修，登记在案）
  target_id : String
  /// 1-based 高亮行（StudyTemplate 用）
  highlight_lines : Array[Int]
} derive(Debug)

///|
/// 完整学习路径（learning_path.rs LearningPath 照搬）。
pub(all) struct LearningPath {
  target_misconception_id : String
  target_misconception_name : String
  estimated_time_minutes : Int
  steps : Array[PathStep]
} derive(Debug)

///|
/// 修复应用目标（auto_fix.rs 消费 session::Diagnostic 的坐标五件套 +
/// fix_kind 的自持形态——本包不依赖 session，gateway 调用处转装）。
pub(all) struct FixTarget {
  /// 0=None 1=ReplaceText 2=InsertText 3=DeleteText 4=ManualHint
  fix_kind : Int
  replace_start_line : Int
  replace_start_column : Int
  replace_end_line : Int
  replace_end_column : Int
  replacement_text : String
} derive(Debug)

///|
/// 修复生成结果（Rust generate_fix 七元组的 record 形态——勘察 R5
/// 抛弃位置参数元组；字段序 = 七元组序）。
pub(all) struct FixOutcome {
  suggestion : String
  fix_kind : Int
  start_line : Int
  start_col : Int
  end_line : Int
  end_col : Int
  text : String
} derive(Debug)

///|
/// 激活子图的邻居概念（knowledge_graph.rs NeighborConcept 照搬）。
pub(all) struct NeighborConcept {
  node : ConceptNode
  relation : String
  strength : Double
  is_prerequisite : Bool
} derive(Debug)

///|
/// 激活的概念及其 1-hop 邻居（knowledge_graph.rs ActivatedConcept 照搬）。
pub(all) struct ActivatedConcept {
  node : ConceptNode
  /// "Error" | "AST" | "Runtime"（现状两产者）
  activated_by : String
  neighbors : Array[NeighborConcept]
} derive(Debug)
