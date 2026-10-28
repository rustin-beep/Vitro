// 三面 runner 主体：断言面 = gateway 四导出面（F-5：invoke/reset/
// protocol_version/engine_version）的源级等价物——ping 帧 / 非法 JSON
// 错误帧 / 协议版本 / 引擎版本，全部确定性输出（常量 + 纯结构帧），
// 三后端跨臂逐字节可比。顺序即输出序（驱动按行对拍，勿改序）。

///|
fn main {
  println(@gateway.invoke("{\"id\":1,\"method\":\"ping\",\"params\":{}}"))
  println(@gateway.invoke("not-json"))
  println(@gateway.protocol_version())
  println(@gateway.engine_version())
}
