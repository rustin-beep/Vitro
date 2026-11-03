// Json 访问/构造窄面（gateway 的 json_field 族系包内私有——本包自持等价
// 件；只做取值与构造，解析单源仍是 @util.json_parse，禁再写解析器）。

///|
/// 对象字段取值（非对象/缺字段 → Null）。
fn jget(v : Json, key : String) -> Json {
  match v {
    Object(m) =>
      match m.get(key) {
        Some(j) => j
        None => Json::null()
      }
    _ => Json::null()
  }
}

///|
fn jstr(v : Json) -> String? {
  match v {
    String(s) => Some(s)
    _ => None
  }
}

///|
fn jnum(v : Json) -> Double? {
  match v {
    Number(n, repr=_) => Some(n)
    _ => None
  }
}

///|
fn jint(v : Json) -> Int32? {
  match jnum(v) {
    Some(n) => Some(n.to_int())
    None => None
  }
}

///|
fn jbool(v : Json) -> Bool? {
  match v {
    True => Some(true)
    False => Some(false)
    _ => None
  }
}

///|
fn jarr(v : Json) -> Array[Json] {
  match v {
    Array(a) => a
    _ => []
  }
}

///|
fn jis_null(v : Json) -> Bool {
  match v {
    Null => true
    _ => false
  }
}

///|
fn jint_or(v : Json, d : Int32) -> Int32 {
  match jint(v) {
    Some(n) => n
    None => d
  }
}

///|
fn jstr_or(v : Json, d : String) -> String {
  match jstr(v) {
    Some(s) => s
    None => d
  }
}

///|
fn jbool_or(v : Json, d : Bool) -> Bool {
  match jbool(v) {
    Some(b) => b
    None => d
  }
}

///|
/// 字符串数组取值（非数组/元素非字符串 → 跳过）。
fn jstr_arr(v : Json) -> Array[String] {
  let out : Array[String] = []
  for x in jarr(v) {
    match jstr(x) {
      Some(s) => out.push(s)
      None => ()
    }
  }
  out
}

///|
/// 对象构造器（插入序 = 发射序；链式调用，struct 按引用传递故返回 self 即可）。
priv struct Ob {
  m : Map[String, Json]
}

///|
fn ob() -> Ob {
  { m: Map([]), }
}

///|
fn Ob::s(self : Ob, k : String, v : String) -> Ob {
  self.m.set(k, Json::string(v))
  self
}

///|
fn Ob::n(self : Ob, k : String, v : Int32) -> Ob {
  self.m.set(k, Json::number(v.to_double()))
  self
}

///|
fn Ob::d(self : Ob, k : String, v : Double) -> Ob {
  self.m.set(k, Json::number(v))
  self
}

///|
fn Ob::b(self : Ob, k : String, v : Bool) -> Ob {
  self.m.set(k, Json::boolean(v))
  self
}

///|
fn Ob::j(self : Ob, k : String, v : Json) -> Ob {
  self.m.set(k, v)
  self
}

///|
fn Ob::a(self : Ob, k : String, v : Array[Json]) -> Ob {
  self.m.set(k, Json::array(v))
  self
}

///|
fn Ob::sa(self : Ob, k : String, v : Array[String]) -> Ob {
  let arr : Array[Json] = []
  for s in v {
    arr.push(Json::string(s))
  }
  self.m.set(k, Json::array(arr))
  self
}

///|
fn Ob::done(self : Ob) -> Json {
  Json::object(self.m)
}

///|
fn jstrs(v : Array[String]) -> Json {
  let arr : Array[Json] = []
  for s in v {
    arr.push(Json::string(s))
  }
  Json::array(arr)
}

///|
fn jints(v : Array[Int32]) -> Json {
  let arr : Array[Json] = []
  for n in v {
    arr.push(Json::number(n.to_double()))
  }
  Json::array(arr)
}

///|
/// 空白剪裁（ASCII 空格/制表/回车/换行——NDJSON 行首尾宽容）。
fn trim_ws(s : String) -> String {
  let mut a = 0
  let mut b = s.length()
  while a < b && is_ws(s[a]) {
    a += 1
  }
  while b > a && is_ws(s[b - 1]) {
    b -= 1
  }
  s[a:b].to_owned()
}

///|
fn is_ws(c : UInt16) -> Bool {
  let n = c.to_int()
  n == 32 || n == 9 || n == 13 || n == 10 || n == 0xFEFF
}

///|
/// 源码首行摘要（sessions() 列表用：首个非空行前 40 个码元）。
fn source_head(src : String) -> String {
  for line in src.split("\n") {
    let t = trim_ws(line.to_owned())
    if t.length() > 0 {
      return if t.length() > 40 { t[0:40].to_owned() + "…" } else { t }
    }
  }
  ""
}

///|
fn line_count(src : String) -> Int32 {
  let mut n = 1
  for i = 0; i < src.length(); i = i + 1 {
    if src[i].to_int() == 10 {
      n += 1
    }
  }
  n
}

///|
fn min_int(a : Int32, b : Int32) -> Int32 {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn max_int(a : Int32, b : Int32) -> Int32 {
  if a > b {
    a
  } else {
    b
  }
}
