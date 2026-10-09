///|
/// E4 锚出口（error_catalog JSON）——与 Rust `error_catalog::export_json`
/// 同形：`{"catalog":[{...},...]}`，码升序，字段序
/// code / code_str / lang / category / icon / title / explanation / common_causes。
///
/// 显式 emitter 纪律（B 级锚）：两侧手写序列化，禁一侧 serde 一侧 ToJson
/// 派生直拼——字段序与转义在此单点可控。
///
/// lang 值域对齐 Rust 目录导出（"c" / "c++"）：SourceLang::Cpp 的
/// 协议标识 "cpp"（is_cpp_mode 单源）与此处的展示值 "c++" 是两个
/// 语义层，emitter 内显式映射，不共用 to_str。
///
/// category 值域：1xxx=词法 / 2xxx=语法 / 3xxx=语义 / 4xxx=C++。
pub fn export_catalog_json() -> String {
  let buf = StringBuilder()
  buf.write_string("{\"catalog\":[")
  let codes = catalog_codes()
  for i, code in codes {
    if i > 0 {
      buf.write_string(",")
    }
    let op = ErrorCode::from_code(code).unwrap()
    let e = op.catalog().unwrap()
    buf.write_string("{\"code\":\{e.code}")
    buf.write_string(",\"code_str\":\"\{op.display_code()}\"")
    buf.write_string(",\"lang\":\"\{export_lang_of(e.code)}\"")
    buf.write_string(",\"category\":\"\{category_of(e.code)}\"")
    buf.write_string(",\"icon\":\"\{@util.json_escape(e.icon)}\"")
    buf.write_string(",\"title\":\"\{@util.json_escape(e.title)}\"")
    buf.write_string(",\"explanation\":\"\{@util.json_escape(e.explanation)}\"")
    buf.write_string(",\"common_causes\":[")
    for j, cause in e.common_causes {
      if j > 0 {
        buf.write_string(",")
      }
      buf.write_string("\"\{@util.json_escape(cause)}\"")
    }
    buf.write_string("]}")
  }
  buf.write_string("]}")
  buf.to_string()
}

///|
/// lang 导出值（Rust lang_of_code 四值对齐：1000..=3999 "c" /
/// 4000..=4999 "c++" / 5000..=5999 "csharp" / 其它 "unknown"——审阅
/// P2-3：此前二值化，5xxx 落地即静默错）。
fn export_lang_of(code : Int) -> String {
  if code >= 1000 && code <= 3999 {
    "c"
  } else if code >= 4000 && code <= 4999 {
    "c++"
  } else if code >= 5000 && code <= 5999 {
    "csharp"
  } else {
    "unknown"
  }
}

///|
/// category 导出值（Rust category_of_code 对齐）。
fn category_of(code : Int) -> String {
  match code / 1000 {
    1 => "词法"
    2 => "语法"
    3 => "语义"
    4 => "C++"
    5 => "C#"
    _ => "其它"
  }
}

// 字符串转义已收口 @util.json_escape（issue #55 六份收一；原本地副本只转
// 五字符、控制字符原样写出=非法 JSON——单源补齐 U+0000–001F 全转义）。
