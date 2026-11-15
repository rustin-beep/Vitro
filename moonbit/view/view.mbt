///| 投影器查询与声明校验（手写面；数据面见 projectors_gen.mbt）。
///
/// 边界：引擎只提供「语义契约」——哪些 id 合法、一条声明需要几条序列、
/// 是否需要 dims 维度表。**不提供任何绘制**（DOM / SVG / CSS 归宿主），
/// 也不按变量名猜场景：傅里叶是 `series re im -> polar` 由课程声明，
/// 引擎只报名字与形状（array_snapshots[].dims）。

///|
/// 取投影器规格；未登记 id → None（消费点 fail loud，不静默回落默认投影器）。
pub fn projector(id : String) -> Projector? {
  for p in projectors() {
    if p.id == id {
      return Some(p)
    }
  }
  None
}

///|
/// 全族 id（按 id 字节序；宿主注册表面与词表的对账锚）。
pub fn projector_ids() -> Array[String] {
  let out : Array[String] = []
  for p in projectors() {
    out.push(p.id)
  }
  out
}

///|
/// 校验一条课程声明能否落到宿主。
///   count = 参与序列条数；dims = 首序列的维度个数（一维 = 1）。
/// 返回 None = 合法；Some(msg) = 错误文案（宿主原样展示，不猜、不兜底）。
pub fn check_decl(id : String, count : Int32, dims : Int32) -> String? {
  let p = match projector(id) {
    None => return Some("未知投影器: " + id)
    Some(x) => x
  }
  if count < p.series_min {
    return Some(
      id +
      " 需至少 " +
      p.series_min.to_string() +
      " 条序列，实得 " +
      count.to_string(),
    )
  }
  if p.series_max >= 0 && count > p.series_max {
    return Some(
      id +
      " 至多 " +
      p.series_max.to_string() +
      " 条序列，实得 " +
      count.to_string(),
    )
  }
  if dims < p.min_dims {
    return Some(
      id +
      " 需 " +
      p.min_dims.to_string() +
      " 维维度表，实得 " +
      dims.to_string() +
      " 维",
    )
  }
  None
}

///|
/// 选项键是否为该投影器的已知键。未知键**不判错**——课程与宿主版本可
/// 各自演进（消费点原样保留）；本函数只供宿主做提示与文档展示。
pub fn known_opt(id : String, key : String) -> Bool {
  match projector(id) {
    None => false
    Some(p) => {
      for k in p.opts {
        if k == key {
          return true
        }
      }
      false
    }
  }
}

///| ── ViewDoc v0.1.1 出口（批 E，2026-11-14；refs #470）──────────────
///
/// 一条声明 = 「哪几条序列用什么投影器画」。文法与课源
/// `<!-- vitri-viz v1 -->` 的 series 行同形，单源在引擎侧：
///   series <名…> -> <投影器> [k=v …]
/// 解析只校验**形态**，不校验投影器是否存在（课源与宿主可各自演进；
/// 存在性由消费点用 projector() 判，错误面板原样展示）。

///|
/// 一条视图声明（host 无关的语义面；绘制归宿主）。
pub(all) struct SeriesDecl {
  series : Array[String]
  projector : String
  opts : Array[(String, String)]
}

///|
fn is_ascii_alpha(c : Int32) -> Bool {
  (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
}

///|
fn is_ascii_digit(c : Int32) -> Bool {
  c >= 48 && c <= 57
}

///|
fn is_ident(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  let mut first = true
  for ch in s {
    let c = ch.to_int()
    let ok = if first {
      is_ascii_alpha(c) || c == 95
    } else {
      is_ascii_alpha(c) || is_ascii_digit(c) || c == 95
    }
    if !ok {
      return false
    }
    first = false
  }
  true
}

///|
fn split_ws(s : String) -> Array[String] {
  let out : Array[String] = []
  let cur = StringBuilder()
  for ch in s {
    if ch == ' ' || ch == '\t' {
      if !cur.is_empty() {
        out.push(cur.to_string())
        cur.reset()
      }
    } else {
      cur.write_char(ch)
    }
  }
  if !cur.is_empty() {
    out.push(cur.to_string())
  }
  out
}

///|
/// 解析单行声明；错误文案给原行与位置语义（宿主原样展示）。
pub fn parse_series_decl(line : String) -> Result[SeriesDecl, String] {
  let t = line.trim().to_owned()
  if t == "" {
    return Err("空声明行")
  }
  let arrow = match t.find("->") {
    Some(i) => i
    None =>
      return Err(
        "缺 `->`（形态：series <名…> -> <投影器> [k=v …]）",
      )
  }
  let left = split_ws(t[0:arrow].to_owned())
  let right = split_ws(t[arrow + 2:t.length()].to_owned())
  if left.length() < 2 || left[0] != "series" {
    return Err("行须以 `series <名…>` 起首：\{t}")
  }
  let series : Array[String] = []
  for i = 1; i < left.length(); i = i + 1 {
    if !is_ident(left[i]) {
      return Err("序列名不是标识符：\{left[i]}")
    }
    series.push(left[i])
  }
  if right.length() == 0 {
    return Err("缺投影器 id：\{t}")
  }
  if !is_ident(right[0]) {
    return Err("投影器 id 不是标识符：\{right[0]}")
  }
  let opts : Array[(String, String)] = []
  for i = 1; i < right.length(); i = i + 1 {
    let kv = right[i]
    let eq = match kv.find("=") {
      Some(x) => x
      None => return Err("选项须为 k=v：\{kv}")
    }
    if eq == 0 || eq + 1 >= kv.length() {
      return Err("选项键/值不得为空：\{kv}")
    }
    opts.push((kv[0:eq].to_owned(), kv[eq + 1:kv.length()].to_owned()))
  }
  Ok({ series, projector: right[0], opts, })
}

///|
/// 解析多行声明块（空行与 `//` 注释跳过）；错误带 1 起行号。
pub fn parse_series_decl_block(
  text : String,
) -> Result[Array[SeriesDecl], String] {
  let out : Array[SeriesDecl] = []
  for i, raw in text.split("\n") {
    let t = raw.trim().to_owned()
    if t == "" || t.has_prefix("//") {
      continue
    }
    match parse_series_decl(t) {
      Ok(d) => out.push(d)
      Err(m) => return Err("第 \{i + 1} 行：\{m}")
    }
  }
  Ok(out)
}

///|
fn json_str_array(xs : Array[String]) -> Json {
  let out : Array[Json] = []
  for x in xs {
    out.push(Json::string(x))
  }
  Json::array(out)
}

///|
/// ViewDoc v0.1.1 结构化出口：`{pv, default, projectors[], series_decl[]}`。
/// projectors 发全族规格（宿主据此校验/显示错误，不在宿主侧复刻词表）。
pub fn doc_value(decls : Array[SeriesDecl]) -> Json {
  let ps : Array[Json] = []
  for p in projectors() {
    ps.push(
      Json::object({
        "id": Json::string(p.id),
        "seriesMin": Json::number(p.series_min.to_double()),
        "seriesMax": Json::number(p.series_max.to_double()),
        "minDims": Json::number(p.min_dims.to_double()),
        "opts": json_str_array(p.opts),
        "note": Json::string(p.note),
      }),
    )
  }
  let ds : Array[Json] = []
  for d in decls {
    let opts = d.opts.copy()
    opts.sort_by((x, y) => @util.str_cmp(x.0, y.0))
    let om : Map[String, Json] = Map([])
    for kv in opts {
      om.set(kv.0, Json::string(kv.1))
    }
    ds.push(
      Json::object({
        "series": json_str_array(d.series),
        "projector": Json::string(d.projector),
        "opts": Json::object(om),
      }),
    )
  }
  Json::object({
    "pv": Json::string("0.1.1"),
    "default": Json::string(default_projector()),
    "projectors": Json::array(ps),
    "series_decl": Json::array(ds),
  })
}

///|
/// 序列化出口（键序由 doc_value 构造序固化，字节确定）。
pub fn doc_json(decls : Array[SeriesDecl]) -> String {
  doc_value(decls).stringify()
}
