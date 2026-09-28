// 标准 JSON 解析器（S7 批三号一段，2026-09-28）——RFC 8259 子集。
// 落点裁定：用户唯一依赖清除批（B 路线 vendor fs）删 x 依赖后，
// x/json5 不可用；serve 的协议输入是**标准 JSON**（对端构造，非 JSON5
// 超集——注释/尾逗号/无引号键不在协议面），自写递归下降 ~250 行优于
// vendor json5 的 5 文件维护面。核心 builtin 只有构造+stringify 无
// parse（亲证），本件补解析向。
// 往返保真关键：数字捕获**原文 repr**（"42" 不 stringify 成 "42.0"——
// core Json::Number 的 repr~ 参数）；键序=插入序（与构造侧 Map 对称，
// 协议响应构造方可控）。
// 升序裁定：暂居 cmd/serve 内部 priv；第二个消费者出现时上提（G-1
// util 的「新件入包先登记 G 表」纪律同款——届时挂 §10.5）。

///|
priv suberror JsonParseError {
  Fail(message~ : String, offset~ : Int)
}

///|
const JSON_PARSE_DEPTH_LIMIT : Int = 128

///|
struct JsonCursor {
  src : String
  mut pos : Int
  mut depth : Int
}

///|
/// 入口：一行请求 → Json 值（失败 raise JsonParseError）。
fn json_parse(input : String) -> Json raise JsonParseError {
  let c = { src: input, pos: 0, depth: 0, }
  skip_ws(c)
  let v = parse_value(c)
  skip_ws(c)
  if c.pos < c.src.length() {
    raise JsonParseError::Fail(message="JSON 尾随内容", offset=c.pos)
  }
  v
}

///|
fn peek(c : JsonCursor) -> Int {
  if c.pos < c.src.length() {
    c.src[c.pos].to_int()
  } else {
    -1
  }
}

///|
fn advance(c : JsonCursor) -> Int {
  let ch = peek(c)
  c.pos += 1
  ch
}

///|
fn skip_ws(c : JsonCursor) -> Unit {
  while true {
    match peek(c) {
      32 | 9 | 10 | 13 => c.pos += 1
      _ => break
    }
  }
}

///|
fn expect(c : JsonCursor, ch : Int) -> Unit raise JsonParseError {
  if peek(c) != ch {
    raise JsonParseError::Fail(
      message="期望字符 '\{Char::from_int(ch)}'",
      offset=c.pos,
    )
  }
  ignore(advance(c))
}

///|
fn parse_value(c : JsonCursor) -> Json raise JsonParseError {
  c.depth += 1
  if c.depth > JSON_PARSE_DEPTH_LIMIT {
    raise JsonParseError::Fail(
      message="嵌套深度超限（>\{JSON_PARSE_DEPTH_LIMIT}，对齐 serde_json 默认）",
      offset=c.pos,
    )
  }
  let v = parse_value_inner(c)
  c.depth -= 1
  v
}

///|
fn parse_value_inner(c : JsonCursor) -> Json raise JsonParseError {
  skip_ws(c)
  match peek(c) {
    -1 =>
      raise JsonParseError::Fail(message="意外的输入结束", offset=c.pos)
    123 => parse_object(c) // {
    91 => parse_array(c) // [
    34 => Json::string(parse_string(c)) // "
    116 => parse_lit(c, "true", Json::boolean(true)) // t
    102 => parse_lit(c, "false", Json::boolean(false)) // f
    110 => parse_lit(c, "null", Json::null()) // n
    _ => parse_number(c)
  }
}

///|
fn parse_lit(
  c : JsonCursor,
  word : String,
  v : Json,
) -> Json raise JsonParseError {
  for i in 0..<word.length() {
    if peek(c) != word[i].to_int() {
      raise JsonParseError::Fail(
        message="字面量不匹配（期望 \{word}）",
        offset=c.pos,
      )
    }
    ignore(advance(c))
  }
  v
}

///|
fn parse_object(c : JsonCursor) -> Json raise JsonParseError {
  ignore(advance(c)) // {
  let m : Map[String, Json] = Map([])
  skip_ws(c)
  if peek(c) == 125 {
    ignore(advance(c))
    return Json::object(m)
  }
  while true {
    skip_ws(c)
    let key = parse_string(c)
    skip_ws(c)
    expect(c, 58) // :
    let v = parse_value(c)
    m.set(key, v)
    skip_ws(c)
    match advance(c) {
      44 => continue // ,
      125 => break // }
      _ =>
        raise JsonParseError::Fail(
          message="对象内期望 ',' 或 '}'",
          offset=c.pos - 1,
        )
    }
  }
  Json::object(m)
}

///|
fn parse_array(c : JsonCursor) -> Json raise JsonParseError {
  ignore(advance(c)) // [
  let arr : Array[Json] = []
  skip_ws(c)
  if peek(c) == 93 {
    ignore(advance(c))
    return Json::array(arr)
  }
  while true {
    arr.push(parse_value(c))
    skip_ws(c)
    match advance(c) {
      44 => continue // ,
      93 => break // ]
      _ =>
        raise JsonParseError::Fail(
          message="数组内期望 ',' 或 ']'",
          offset=c.pos - 1,
        )
    }
  }
  Json::array(arr)
}

///|
/// JSON 字符串（含全套转义；\uXXXX 产 BMP 码元，代理对原样透传拼接）。
fn parse_string(c : JsonCursor) -> String raise JsonParseError {
  expect(c, 34) // "
  let buf = StringBuilder()
  parse_string_body(c, buf)
  buf.to_string()
}

///|
fn parse_string_body(
  c : JsonCursor,
  buf : StringBuilder,
) -> Unit raise JsonParseError {
  while true {
    let ch = advance(c)
    if ch == -1 {
      raise JsonParseError::Fail(message="字符串未闭合", offset=c.pos)
    }
    if ch == 34 {
      return
    }
    if ch == 92 {
      // 反斜杠转义
      match advance(c) {
        34 => buf.write_char('"')
        92 => buf.write_char('\\')
        47 => buf.write_char('/')
        98 => buf.write_char('\b')
        102 => buf.write_char('\f')
        110 => buf.write_char('\n')
        114 => buf.write_char('\r')
        116 => buf.write_char('\t')
        117 => {
          // \uXXXX
          let mut code = 0
          for _ in 0..<4 {
            let h = advance(c)
            let d = if h >= 48 && h <= 57 {
              h - 48
            } else if h >= 97 && h <= 102 {
              h - 87
            } else if h >= 65 && h <= 70 {
              h - 55
            } else {
              -1
            }
            if d < 0 {
              raise JsonParseError::Fail(
                message="\\u 转义含非十六进制字符",
                offset=c.pos,
              )
            }
            code = code * 16 + d
          }
          buf.write_char(Char::from_int(code))
        }
        _ =>
          raise JsonParseError::Fail(
            message="非法转义字符",
            offset=c.pos - 1,
          )
      }
    } else if ch < 0x20 {
      raise JsonParseError::Fail(
        message="字符串含未转义控制字符",
        offset=c.pos - 1,
      )
    } else {
      buf.write_char(Char::from_int(ch))
    }
  }
}

///|
/// JSON 数字：捕获原文作 repr（往返保真——"42" 不变 "42.0"），值域
/// Double；整数字面量若超出 2^53 由 Double 语义承载（协议参数域内安全，
/// 与 serde_json 的 f64 口径一致）。
fn parse_number(c : JsonCursor) -> Json raise JsonParseError {
  let start = c.pos
  if peek(c) == 45 {
    ignore(advance(c)) // -
  }
  while true {
    match peek(c) {
      48..=57 => c.pos += 1
      _ => break
    }
  }
  if peek(c) == 46 {
    ignore(advance(c)) // .
    while true {
      match peek(c) {
        48..=57 => c.pos += 1
        _ => break
      }
    }
  }
  if peek(c) == 101 || peek(c) == 69 {
    ignore(advance(c)) // e/E
    if peek(c) == 43 || peek(c) == 45 {
      ignore(advance(c))
    }
    while true {
      match peek(c) {
        48..=57 => c.pos += 1
        _ => break
      }
    }
  }
  let text = c.src[start:c.pos].to_string()
  if text.length() == 0 || text == "-" {
    raise JsonParseError::Fail(message="非法数字字面量", offset=start)
  }
  // RFC 8259 number 文法校验（审阅八轮 P3③：此前 1e/01/1./.5/1e+ 全被
  // 静默放行——扫描只认字符集不认结构）：int 部分禁前导零（"0" 或
  // 非零开头）；'.' 后必须至少一位数字；'e' 后可带符号但必须有数字
  if !valid_json_number(text) {
    raise JsonParseError::Fail(
      message="非法数字字面量（RFC 8259）：\{text}",
      offset=start,
    )
  }
  // C strtod（最近 Double 精度；core 的 parse_double 在 internal 不可见）。
  // 数字串纯 ASCII；Bytes 不可按下标写——from_array 构造并自带 NUL 终止
  //（Bytes 内存布局不保证 NUL，x/fs OsString 同款自带约定）
  let arr : Array[Byte] = []
  for ch in text {
    arr.push(ch.to_int().to_byte())
  }
  arr.push(0)
  // 手写累积解析：整型域（< 2^53）逐位精确；小数/指数逐位累积
  // best-effort——**repr 保真兜底**（stringify 恒输出原文，值仅服务
  // as_int/比较，协议参数域〔id/step/max_steps〕全整数精确）。
  // FFI 数值返回通道（Double/UInt64/Int 双返回）在本机实测全垃圾值，
  // core 的 parse_double 在 internal 包不可见——手写是稳定通道。
  let n = accumulate_double(text)
  Json::number(n, repr=text)
}

///|
/// 十进制数字面量 → Double（手写累积；text 形态已由 parse_number 语法
/// 校验——[+-]?digits[.digits][eE[+-]digits]）。
fn accumulate_double(text : String) -> Double {
  let mut i = 0
  let mut neg = false
  if i < text.length() && text[i] == '-' {
    neg = true
    i += 1
  }
  let mut int_part : Double = 0
  while i < text.length() && text[i] >= '0' && text[i] <= '9' {
    int_part = int_part * 10 + (text[i] - '0').to_int().to_double()
    i += 1
  }
  let mut frac : Double = 0
  let mut frac_scale : Double = 1
  if i < text.length() && text[i] == '.' {
    i += 1
    while i < text.length() && text[i] >= '0' && text[i] <= '9' {
      frac_scale = frac_scale / 10
      frac = frac + (text[i] - '0').to_int().to_double() * frac_scale
      i += 1
    }
  }
  let mut exp : Int = 0
  if i < text.length() && (text[i] == 'e' || text[i] == 'E') {
    i += 1
    let mut exp_neg = false
    if i < text.length() && (text[i] == '+' || text[i] == '-') {
      exp_neg = text[i] == '-'
      i += 1
    }
    while i < text.length() && text[i] >= '0' && text[i] <= '9' {
      exp = exp * 10 + (text[i] - '0').to_int()
      i += 1
    }
    if exp_neg {
      exp = -exp
    }
  }
  let mut v = int_part + frac
  // 指数应用（10^|exp| 逐乘——|exp| 协议域内个位到百位）
  let mut k = 0
  while k < exp {
    v = v * 10
    k += 1
  }
  while k > exp {
    v = v / 10
    k -= 1
  }
  if neg {
    -v
  } else {
    v
  }
}

///|
/// RFC 8259 number 文法校验：[-]?int[.frac][e[+-]?exp]——int 禁前导零、
/// frac/exp 至少一位数字。text 已过字符集扫描（只含 [0-9.eE+-]）。
fn valid_json_number(text : String) -> Bool {
  let n = text.length()
  let mut i = 0
  if i < n && text[i] == '-' {
    i += 1
  }
  // int 部分
  let int_start = i
  while i < n && text[i] >= '0' && text[i] <= '9' {
    i += 1
  }
  let int_len = i - int_start
  if int_len == 0 {
    return false
  }
  if int_len > 1 && text[int_start] == '0' {
    return false // 前导零（"01"）
  }
  // frac 部分
  if i < n && text[i] == '.' {
    i += 1
    let frac_start = i
    while i < n && text[i] >= '0' && text[i] <= '9' {
      i += 1
    }
    if i == frac_start {
      return false // "1." 裸尾点（".5" 在更早被 int_len==0 拦）
    }
  }
  // exp 部分
  if i < n && (text[i] == 'e' || text[i] == 'E') {
    i += 1
    if i < n && (text[i] == '+' || text[i] == '-') {
      i += 1
    }
    let exp_start = i
    while i < n && text[i] >= '0' && text[i] <= '9' {
      i += 1
    }
    if i == exp_start {
      return false // "1e" / "1e+"
    }
  }
  i == n
}
