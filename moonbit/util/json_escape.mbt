///|
/// JSON 字符串转义单源（issue #55 六份收一；serde_json 口径）：
/// `"` `\` + `\n` `\r` `\t` + 其余 U+0000–001F 控制字符转 `\u00XX`（小写
/// hex，RFC 8259 要求全部控制字符转义）；其余字符原样。只转义**字符串
/// 内容**——首尾引号包裹由调用方自拼（各 emitter 本就在拼 JSON 帧壳）。
/// 消费面：ast（json_escape_string 转发）/diag E4 出口/gateway dump 帧/
/// cmd 族 dump 与 CLI 请求拼装——禁下游再写本地转义实现。
pub fn json_escape(s : String) -> String {
  let buf = StringBuilder()
  json_escape_into(s, buf)
  buf.to_string()
}

///|
/// 流式版（emitter 直写 buf——ast/canonical dump 大产物面零中间串）。
pub fn json_escape_into(s : String, buf : StringBuilder) -> Unit {
  for c in s {
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      _ => {
        // 控制字符（< 0x20）必须 \u00XX 转义——C 转义序列（\x4 类）解析出的
        // 真字节原样写出即非法 JSON（baseline 的 string_escape_octal_hex.c
        // 差分曾抓出；diag E4 出口同缺口由 issue #55 收口）
        let code = c.to_int()
        if code < 0x20 {
          buf.write_string("\\u00")
          let hex = "0123456789abcdef"
          buf.write_string(hex[code / 16:code / 16 + 1].to_owned())
          buf.write_string(hex[code % 16:code % 16 + 1].to_owned())
        } else {
          buf.write_char(c)
        }
      }
    }
  }
}
