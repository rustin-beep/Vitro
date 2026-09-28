// Option→Json 出口组合子（S7 批四号，openseek 对照纪律批 ①——总计划
// 批四号段排期）：**Some(v) 绝不编成单元素数组 [v]**。
//
// 陷阱记录（openseek `protocol/to_json.mbt` or_null 先例，注释精确转译）：
// MoonBit 派生 ToJson 对 `Option[T]` 的编码是 `Some(v) → [v]` / `None → []`
// ——JSON 消费方按 object/array/值域做类型分派时，`[v]` 会被当成数组
// 拒绝 string lookup ⇒ **present 字段静默变 absent**，且这种错不炸、
// 只让下游拿空值——排查成本极高。本仓「显式 emitter 禁 ToJson 派生」
// 纪律（schema.mbt）挡住了派生路径，但手写 emitter 的 Option 分支仍是
// 散拼风险点——本组合子收口为唯一写法。
//
// 协议契约（README「协议演化纪律」第 0 条的前置件）：**Option 字段的
// JSON 形态 = 值或 null，绝不省略字段、绝不数组**。省略字段会把
// 「字段晚于冻结引入」的版本协商信号吃掉（读者无法区分 v0.1 旧帧与
// 显式 None）。
//
// 消费点：S8 step 族 emitter（StepPayload.payload : StepPayload? /
// root_cause_hint 等字段族）与 dump 族；serve 侧既有出口无 Option→Json
// 散拼（2026-09-28 批四号盘点——serve_compile/serve_run 的 output : None
// 分支是控制流非 Json 化），首个消费者出现时 surface 白名单条目移除。

///|
/// Option→Json 出口组合子：`Some(j)` 原值 / `None` 恒 `Json::null()`。
pub fn json_or_null(v : Json?) -> Json {
  match v {
    Some(j) => j
    None => Json::null()
  }
}
