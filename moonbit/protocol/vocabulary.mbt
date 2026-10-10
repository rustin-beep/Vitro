// semantic_label 受控词汇表 —— 词汇即契约（schema 附录 B，词汇只增不改）。
// 照搬 native/src/unified/vocabulary.rs（2026-09-27）。
// 背景：semantic_label 长期是"自由文本启发"，消费方只能对 label 做模式
// 匹配，词汇一旦漂移（「循环边界」→「循环」）下游知识卡片静默失效。
// 本模块把词汇升级为受控词汇表：
// - 词汇表在此单源定义，schema 附录 B 与出口 semantic_labels 均从它
//   派生，禁止三处各写一份；
// - classify 是"产出的 label -> 词汇表条目"的映射，冻结测试断言引擎
//   实际产出的每个 label 都能归类——新增标签而不登记词汇表 = 测试失败；
// - 只增不改：既有 id 与 template 不得改语义；扩充只能追加条目。
//   这与 CSharp前端引入计划 §6-B 的"消费端 UI 直读不做推断"是同一份契约。
// 状态位 status：active = 当前引擎会产出（C 域）；reserved = 随 v0.1 冻结
// 预先登记的词汇（异常域，CS3b 激活时开始产出）——登记在案 = 下游可提前
// 把 UI 分支写好，激活不是"新增契约"而是"契约兑现"。

///|
/// 词汇表条目：一个 semantic_label 的受控形态。
pub(all) struct SemanticLabelKind {
  /// 稳定标识（消费方按此分支，不解析 template 文本）
  id : String
  /// 语言域："c" / "csharp"（同一词汇表按域登记，字段下发按语言域）
  domain : String
  /// 人类可读模板（{...} 为值槽）
  template : String
  /// 实际产出样例（给文档与联调对照）
  example : String
  /// "active"（已产出）/"reserved"（已登记，激活前不产出）
  status : String
  /// 激活批次（"-" = 已激活）
  since : String
} derive(Debug)

///|
pub extend SemanticLabelKind with Debug::{to_repr}

///| semantic_label 受控词汇表（schema 附录 B 的机器可读单源）。

///|
/// 顺序即 classify 的判定顺序（前缀更专的条目在前）。
pub fn semantic_label_vocabulary() -> Array[SemanticLabelKind] {
  [
    {
      id: "swap",
      domain: "c",
      template: "交换 arr[{i}]↔arr[{j}]",
      example: "交换 arr[3]↔arr[4]",
      status: "active",
      since: "-",
    },
    {
      id: "recursive_call",
      domain: "c",
      template: "递归调用 {func}",
      example: "递归调用 fib",
      status: "active",
      since: "-",
    },
    {
      id: "call",
      domain: "c",
      template: "调用 {func}",
      example: "调用 printf / 调用 qsort / 调用 swap",
      status: "active",
      since: "-",
    },
    {
      id: "generic_call",
      domain: "c",
      template: "函数调用",
      example: "函数调用",
      status: "active",
      since: "-",
    },
    {
      id: "loop",
      domain: "c",
      template: "循环 {iter=v, …}",
      example: "循环 i=0, j=1（无值形态为裸 `循环`）",
      status: "active",
      since: "-",
    },
    {
      id: "return",
      domain: "c",
      template: "返回",
      example: "返回",
      status: "active",
      since: "-",
    },
    {
      id: "heap_alloc",
      domain: "c",
      template: "内存分配",
      example: "内存分配",
      status: "active",
      since: "-",
    },
    {
      id: "heap_free",
      domain: "c",
      template: "释放内存",
      example: "释放内存",
      status: "active",
      since: "-",
    },
    {
      id: "io",
      domain: "c",
      template: "IO 操作",
      example: "IO 操作",
      status: "active",
      since: "-",
    },
    {
      id: "line_fallback",
      domain: "c",
      template: "第 {line} 行",
      example: "第 12 行",
      status: "active",
      since: "-",
    },
    // ── 异常域（SharpTutor S4 §6 首批；CS3b 激活）──
    {
      id: "throw",
      domain: "csharp",
      template: "抛出异常",
      example: "抛出异常",
      status: "reserved",
      since: "CS3b",
    },
    {
      id: "unwind",
      domain: "csharp",
      template: "栈展开",
      example: "栈展开",
      status: "reserved",
      since: "CS3b",
    },
    {
      id: "catch_enter",
      domain: "csharp",
      template: "进入 catch",
      example: "进入 catch",
      status: "reserved",
      since: "CS3b",
    },
    {
      id: "finally",
      domain: "csharp",
      template: "finally 执行",
      example: "finally 执行",
      status: "reserved",
      since: "CS3b",
    },
  ]
}

///| 产出的 semantic_label -> 词汇表条目 id。

///|

///| None 有两种语义，消费方与冻结测试都需区分：

///| - 空串（code_line <= 0，无源码行）不是词汇缺失，是"本步无标签"——

///|   调用方应先判空；

///|
/// - 非空却归类失败 = 词汇漂移（引擎产出了未登记形态），属防线失败。
pub fn classify(label : String) -> String? {
  if label.is_empty() {
    return None
  }
  if label.has_prefix("交换 arr[") && label.contains("↔") {
    return Some("swap")
  }
  if label.has_prefix("递归调用 ") {
    return Some("recursive_call")
  }
  if label == "函数调用" {
    return Some("generic_call")
  }
  if label.has_prefix("调用 ") && label.length() > "调用 ".length() {
    return Some("call")
  }
  if label == "循环" || label.has_prefix("循环 ") {
    return Some("loop")
  }
  if label == "返回" {
    return Some("return")
  }
  if label == "内存分配" {
    return Some("heap_alloc")
  }
  if label == "释放内存" {
    return Some("heap_free")
  }
  if label == "IO 操作" {
    return Some("io")
  }
  if label.has_prefix("第 ") && label.has_suffix(" 行") {
    return Some("line_fallback")
  }
  // ── 异常域（预留）──
  if label == "抛出异常" {
    return Some("throw")
  }
  if label == "栈展开" {
    return Some("unwind")
  }
  if label == "进入 catch" {
    return Some("catch_enter")
  }
  if label == "finally 执行" {
    return Some("finally")
  }
  None
}

///|
/// 按 id 取条目（classify 的逆查，供出口与文档校验）。
pub fn kind_by_id(id : String) -> SemanticLabelKind? {
  for k in semantic_label_vocabulary() {
    if k.id == id {
      return Some(k)
    }
  }
  None
}

///| 词汇表 JSON（serve 的 semantic_labels 出口 / 文档自检共用）。

///| 显式 emitter：**键序 = serde_json 字典序**（Rust 侧 json! 宏落

///| Value::Object = BTreeMap，to_string 按键字典序——顶层

///| discipline/labels/schema，SemanticLabelKind 条目

///| domain/example/id/since/status/template；数组元素序保持插入序）。

///| 紧凑无空格；与 Rust 真值的逐字节对拍锚在 vocabulary_wbtest（探针

///| tmp/review_20260927/json_order，2026-09-27 用户审阅 P2-1 实测锁定）。

///|
/// 值域全部来自本包常量表，直拼安全（同 contracts_json）。
pub fn vocabulary_json() -> String {
  let buf = StringBuilder()
  buf.write_string(
    "{\"discipline\":\"词汇只增不改：id 与 template 一经发布不得改语义，扩充只能追加条目\",\"labels\":[",
  )
  for i, k in semantic_label_vocabulary() {
    if i > 0 {
      buf.write_char(',')
    }
    buf.write_string(
      "{\"domain\":\"\{k.domain}\",\"example\":\"\{k.example}\",\"id\":\"\{k.id}\",\"since\":\"\{k.since}\",\"status\":\"\{k.status}\",\"template\":\"\{k.template}\"}",
    )
  }
  buf.write_string("],\"schema\":\"\{SCHEMA_VERSION}\"}")
  buf.to_string()
}
