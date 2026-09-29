// cmd/serve：NDJSON 会话模式的 native stdio 壳（S7 批五号起协议层在
// vitro/engine/gateway——本包只剩 stdio 循环；帧语义/方法表见 gateway）。

///|
#borrow(buf)
extern "C" fn serve_read_line_stub(buf : Bytes, cap : Int) -> Int = "moonbit_vitro_serve_read_line"

///|
const SERVE_LINE_CAP : Int = 65536

///|
/// serve 主循环：stdin 逐行 → gateway.invoke → stdout 响应；shutdown 停。
fn main {
  // quote-include 的文件系统读取注册（2026-09-29 审阅 P2 修复——
  // native 形态恢复；gateway 侧经 include_reader 分叉，wasm-gc 不
  // 注册走 E1021 教学诊断）
  @gateway.set_include_reader(fn(path : String) -> String? {
    let s = @fs.read_file_to_string(path) catch { _ => return None }
    Some(s)
  })
  let buf : Bytes = Bytes::make(SERVE_LINE_CAP, b'\x00')
  while true {
    let n = serve_read_line_stub(buf, SERVE_LINE_CAP)
    if n < 0 {
      if n == -2 {
        // 超长行（行内容 ≥65535 字符且不含换行）：oracle 侧 BufRead::lines
        // 按需增长无上限，本壳 fgets 定长缓冲。静默丢弃违反协议演化纪律②
        // （沉默是调用方唯一无法处置的回应——模块审阅 06 P1-1 实锤：
        // ≥65536 字节行零输出 rc=0，与 shutdown 正常退出不可区分）。
        // 回显式错误帧后干净退出；帧形态对齐 gateway serve_err。
        println(
          "{\"id\":0,\"ok\":false,\"error\":{\"kind\":\"protocol\",\"message\":\"请求行超过 65535 字符上限（serve 定长行缓冲）——请缩减单帧 source 或分段喂入\"}}",
        )
      }
      break // EOF（-1）
    }
    // BytesView.to_string 是 Show 展示形态（引号被 debug 转义成 "——
    // 端到端实测实锤），UTF-8 解码走 @utf8.decode_lossy
    let line = @utf8.decode_lossy(buf[:n])
    let resp = @gateway.invoke(line)
    println(resp)
    // shutdown 帧判停（gateway.invoke 的 String→String 单口语义——
    // 宿主见 "shutdown":true 帧自行停止，与 wasm 宿主同判据）
    if resp.contains("\"shutdown\":true") {
      break
    }
  }
}
