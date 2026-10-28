///|
/// #130 批③b（2026-10-17）：诊断卡片教学文本装载门——catalog 卡片
/// 数据（title/explanation/common_causes + icon id，~23KB 中文）拆出
/// 引擎（lean 形态不进 wasm 产物；数据真源产物落
/// teaching/content_data/catalog_data_gen.mbt，经 install_baked 装载；
/// 浏览器宿主经 gateway texts.install 的 error_catalog 段注入）。
///
/// 载体 = `catalog_texts : Map[Int32, CatalogEntry]`（空启动，原地
/// clear+fill——pub let 对象同一性保持）；`ErrorCode::catalog()` 查表
/// （miss = None——与「无卡片码登记缺口 codes_without_catalog」同语义，
/// 消费面 push_one/error_catalog 天然 None-safe = lean 空文案诚实暴露）。
/// 值域闸 = catalog_codes()（结构面，error_code_gen 生成、留引擎）。

///|
pub let catalog_texts : Map[Int32, CatalogEntry] = Map([])

///|
pub suberror InstallCatalogTextsError {
  SchemaFail(message~ : String)
}

///|
/// 段发射：当前表 → JSON 段对象文本（`{ "<code>": {icon,title,
/// explanation,common_causes}, ... }`——键数字字典序 = 码值序〔四位数
/// 码位域〕；compact）。langpack 并段与装载往返锚共用本形态。
pub fn catalog_texts_json() -> String {
  let buf = StringBuilder()
  buf.write_string("{")
  let keys : Array[Int32] = []
  for k, _v in catalog_texts {
    keys.push(k)
  }
  keys.sort()
  for i, k in keys {
    if i > 0 {
      buf.write_string(",")
    }
    let e = catalog_texts
      .get(k)
      .unwrap_or({
        code: k,
        icon: "",
        title: "",
        explanation: "",
        common_causes: [],
      })
    buf.write_string("\"\{k}\":{\"icon\":\"")
    @util.json_escape_into(e.icon, buf)
    buf.write_string("\",\"title\":\"")
    @util.json_escape_into(e.title, buf)
    buf.write_string("\",\"explanation\":\"")
    @util.json_escape_into(e.explanation, buf)
    buf.write_string("\",\"common_causes\":[")
    for j, c in e.common_causes {
      if j > 0 {
        buf.write_string(",")
      }
      buf.write_string("\"")
      @util.json_escape_into(c, buf)
      buf.write_string("\"")
    }
    buf.write_string("]}")
  }
  buf.write_string("}")
  buf.to_string()
}

///|
/// 段装载（#323 起段级合并语义，2026-10-27）：payload = 段对象（不含
/// 段名）。校验：键为整数且 ∈ catalog_codes() 值域（防拼写/幽灵码静默
/// 入表）、四字段恰、形态对；全过后**逐键合并覆盖**（未提供码保持——
/// 治整表替换下「改一张卡须带全 108 张」的不可用形态）。段恰为
/// {"__clear__":true} = 显式清空（返回 true；空对象 = 不覆盖 ≠ 清空）。
/// 校验全过后原子应用，返回是否发生清空。
pub fn install_catalog_texts(
  payload : String,
) -> Bool raise InstallCatalogTextsError {
  let top = @util.json_parse(payload) catch {
    _ =>
      raise InstallCatalogTextsError::SchemaFail(message="段不是合法 JSON")
  }
  let m = match top {
    Object(o) => o
    _ =>
      raise InstallCatalogTextsError::SchemaFail(
        message="段须为 JSON 对象",
      )
  }
  // __clear__ 哨兵（#323）：恰单键 true = 清空；混数据键/值非 true = 拒
  match m.get("__clear__") {
    Some(Json::True) => {
      if m.length() != 1 {
        raise InstallCatalogTextsError::SchemaFail(
          message="__clear__ 不得与数据键混用（清空 = 恰 {\"__clear__\":true} 单键）",
        )
      }
      catalog_texts.clear()
      return true
    }
    Some(_) =>
      raise InstallCatalogTextsError::SchemaFail(
        message="__clear__ 须为布尔 true",
      )
    None => ()
  }
  let codes = catalog_codes()
  let new_entries : Map[Int32, CatalogEntry] = Map([])
  for k, v in m {
    let code = parse_code_key(k) catch {
      _ =>
        raise InstallCatalogTextsError::SchemaFail(
          message="键 '\{k}' 不是整数码",
        )
    }
    if !codes.contains(code) {
      raise InstallCatalogTextsError::SchemaFail(
        message="码 \{code} 不在 catalog_codes 值域（无卡片码或幽灵码）",
      )
    }
    let e = parse_entry(code, v)
    new_entries.set(code, e)
  }
  for k, v in new_entries {
    catalog_texts.set(k, v)
  }
  false
}

///|
fn parse_code_key(k : String) -> Int32 raise InstallCatalogTextsError {
  if k.length() == 0 {
    raise InstallCatalogTextsError::SchemaFail(message="空码键")
  }
  let mut n = 0
  for i = 0; i < k.length(); i = i + 1 {
    let c = k[i]
    if c < 48 || c > 57 {
      raise InstallCatalogTextsError::SchemaFail(message="键 '\{k}' 非数字")
    }
    n = n * 10 + (c.to_int() - 48)
    if n > 1_000_000 {
      raise InstallCatalogTextsError::SchemaFail(message="码 '\{k}' 越界")
    }
  }
  n
}

///|
fn get_str_field(
  m : Map[String, Json],
  name : String,
  code : Int32,
) -> String raise InstallCatalogTextsError {
  match m.get(name) {
    Some(String(s)) => s
    Some(_) =>
      raise InstallCatalogTextsError::SchemaFail(
        message="码 \{code} 字段 '\{name}' 须为字符串",
      )
    None =>
      raise InstallCatalogTextsError::SchemaFail(
        message="码 \{code} 缺字段 '\{name}'",
      )
  }
}

///|
fn parse_entry(
  code : Int32,
  v : Json,
) -> CatalogEntry raise InstallCatalogTextsError {
  let m = match v {
    Object(o) => o
    _ =>
      raise InstallCatalogTextsError::SchemaFail(
        message="码 \{code} 条目须为对象",
      )
  }
  if m.length() != 4 {
    raise InstallCatalogTextsError::SchemaFail(
      message="码 \{code} 须恰含 icon/title/explanation/common_causes 四字段",
    )
  }
  let icon = get_str_field(m, "icon", code)
  let title = get_str_field(m, "title", code)
  let explanation = get_str_field(m, "explanation", code)
  let causes : Array[String] = []
  match m.get("common_causes") {
    Some(Array(items)) =>
      for item in items {
        match item {
          String(s) => causes.push(s)
          _ =>
            raise InstallCatalogTextsError::SchemaFail(
              message="码 \{code} common_causes 元素须为字符串",
            )
        }
      }
    Some(_) =>
      raise InstallCatalogTextsError::SchemaFail(
        message="码 \{code} common_causes 须为数组",
      )
    None =>
      raise InstallCatalogTextsError::SchemaFail(
        message="码 \{code} 缺字段 'common_causes'",
      )
  }
  { code, icon, title, explanation, common_causes: causes, }
}
