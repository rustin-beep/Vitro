// 三面 runner 主体。断言面两层：
//
// ① gateway 四导出面（F-5：invoke/reset/protocol_version/engine_version）
//   的源级等价物——ping 帧 / 非法 JSON 错误帧 / 协议版本 / 引擎版本，
//   全部确定性输出（常量 + 纯结构帧）。
// ② PR #367 审阅 P2-2（2026-10-28）扩容——常量之外的可观测运算面：
//   Int64 除/乘/模链、double 格式化（1/3 与 -0.0——后端浮点文本化
//   实现的直击面）、UTF-16 拼接长度（CJK + astral）、真实 compile+run
//   会话（return_value 帧端到端）。任两臂分叉直接归因编译后端。
//
// 顺序即输出序（驱动按行对拍，勿改序）；新增行只增不改既有行。

///|
fn main {
  println(@gateway.invoke("{\"id\":1,\"method\":\"ping\",\"params\":{}}"))
  println(@gateway.invoke("not-json"))
  println(@gateway.protocol_version())
  println(@gateway.engine_version())
  // Int64 链（9223372036854775807 / 3 * 7 % 1000000007——除法舍入与
  // 乘模溢出缠绕在后端语义内可见）
  println((9223372036854775807L / 3L * 7L % 1000000007L).to_string())
  // double 文本化两形态：非整值（1/3）与负零（-0.0——「0」还是「-0」
  // 是各后端浮点格式化实现的经典分叉面）
  println((1.0 / 3.0).to_string())
  println((-0.0).to_string())
  // UTF-16 code unit 长度：「中文」2 + 「😀」astral 2 = 4（字符串内码
  // 语义的后端投影）
  println(("中文" + "😀").length().to_string())
  // 真实会话：compile（return 7）+ run——帧端到端（诊断/状态机/JSON
  // emitter 全链）
  println(
    @gateway.invoke(
      "{\"id\":9,\"method\":\"compile\",\"params\":{\"source\":\"int main(){return 7;}\"}}",
    ),
  )
  println(
    @gateway.invoke(
      "{\"id\":10,\"method\":\"run\",\"params\":{\"argv\":[\"m.c\"],\"batch_input\":true}}",
    ),
  )
}
