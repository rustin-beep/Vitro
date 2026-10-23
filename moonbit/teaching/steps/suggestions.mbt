// teaching/steps·suggestions（S8 teaching 批一号）：build_match——判据
// 43 算法教学文案已外置为数据资产（issue #60 双出口架构终局，2026-10-10）：
// 真源 = teaching/assets 包（suggestions.json.mbt——moon check 类型系统即
// 写作闸；43 臂穷尽 match = 编译期名单闸；教师面 jsonmbt build 出同目录
// suggestions.json、改后 import --fill 回真源）。本处查表消费（miss 走
// 空串兜底）。vis_events = compare_lines 投影

///|
/// 构造算法匹配（confidence 固定 85——Rust 同款；evidence 具名参数缺省
/// "name"——命名分支调用点零改动，结构分支显式传 "structure"，#224）。
pub fn build_match(
  name : String,
  display_name : String,
  func_name : String,
  line : Int32,
  compare_lines : Array[(Int32, Int32, String)],
  evidence~ : String = "name",
) -> @protocol.AlgorithmMatch {
  let suggestion = @assets.suggestion_map.get(name).unwrap_or("")
  let vis : Array[@protocol.VisEvent] = []
  for pair in compare_lines {
    let (ln, ty, ctx) = pair
    vis.push({ ty, line: ln, extra0: 0, extra1: 0, extra2: 0, context: ctx, })
  }
  {
    name,
    display_name,
    func_name,
    confidence: 85,
    suggestion,
    line,
    vis_events: vis,
    evidence,
  }
}
