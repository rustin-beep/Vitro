// codegen 结构化错误载体（#223，2026-10-25）：report_error 单点构造——
// 文案形态「第 N 行：msg」保持不变（st.errors 串消费面与诊断 message
// 零扰动），新增 code / column 两维：code 0 = Unknown 过渡（codegen
// 错误体系整体立码挂 #38，E4 号段已随 #233 C++ 死臂摘除腾空），首个
// 具名码 E3089（函数已声明但未定义——issue #223，下游按码查卡/归因
// 不再落空）；column 旧口径恒 1（serve 层包装形态保持），带码错误走
// loc.column 真值。line 直存，取代 serve 层「第 N 行：」前缀手扫
//（extract_gen_error_line 退役）——无行号错误 line=0 与旧手扫缺省一致。

///|
pub(all) struct GenError {
  code : Int32
  line : Int32
  column : Int32
  message : String
}

///|
/// 无行号错误的过渡包装（code 0 / line 0 / column 1——旧 serve 层
/// 手扫缺省形态逐位保持；「缺少 main 函数入口」等无 loc 位点）。
pub fn GenError::plain(message : String) -> GenError {
  { code: 0, line: 0, column: 1, message, }
}
