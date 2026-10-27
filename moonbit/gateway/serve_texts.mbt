///|
/// texts.install 方法帧（#130 批② 注入通道，2026-10-17；批③b 扩第四段；
/// #323 段级合并语义 + 清空可观测，2026-10-27）：
/// 语言包装载门的协议半边——浏览器宿主懒加载语言包 js 模块
/// （teaching/langpack）后经本方法注入引擎。payload 顶层键 ⊆
/// {suggestions, builtin_notes, trap_messages, error_catalog}（全部可选段
/// ——缺省段不动现表；携带段**逐键合并覆盖**，段恰 {"__clear__":true}
/// = 显式清空）。前三段整发 @assets.install_texts（域内原子），
/// error_catalog 段（{<code>:{icon,title,explanation,common_causes}}）
/// 剥出整发 @diag.install_catalog_texts。段序 = assets 先 diag 后，任一
/// 段失败即 error 帧（已装段保留——幂等重试语义，跨域不回滚，登记边界）。
/// 成功 ok 帧带四表装后计数 + `cleared` 数组（被清空段名——清空类
/// 操作显式回告，#323 治④）。
fn serve_texts_install_frame(id : Json, params : Json) -> (String, Bool) {
  let payload = match json_field(params, "payload").as_string() {
    Some(p) => p
    None =>
      return (
        serve_err(
          id, "protocol", "texts.install 需要 params.payload:string（语言包 texts_json 同 schema）",
        ).stringify(),
        false,
      )
  }
  // 剥段：error_catalog 段独立走 diag 装载门，其余三段重组走 assets
  let top = @util.json_parse(payload) catch {
    _ =>
      return (
        serve_err(id, "texts", "装载失败：payload 不是合法 JSON").stringify(),
        false,
      )
  }
  let top_map = match top {
    Object(m) => m
    _ =>
      return (
        serve_err(id, "texts", "装载失败：payload 顶层须为对象").stringify(),
        false,
      )
  }
  let catalog_seg : Map[String, Json]? = match top_map.get("error_catalog") {
    Some(Object(m)) => Some(m)
    Some(_) =>
      return (
        serve_err(id, "texts", "装载失败：error_catalog 段须为对象").stringify(),
        false,
      )
    None => None
  }
  // 剥后重组（剩段给 assets——空对象合法：单装/单清 catalog 段形态）
  let rest : Map[String, Json] = Map([])
  for k, v in top_map {
    if k != "error_catalog" {
      rest.set(k, v)
    }
  }
  let assets_cleared : Array[String] = if rest.length() > 0 {
    @assets.install_texts(Json::object(rest).stringify()) catch {
      SchemaFail(message~, ..) =>
        return (
          serve_err(id, "texts", "装载失败：\{message}").stringify(),
          false,
        )
    }
  } else {
    []
  }
  let catalog_cleared = match catalog_seg {
    Some(seg) =>
      @diag.install_catalog_texts(Json::object(seg).stringify()) catch {
        SchemaFail(message~, ..) =>
          return (
            serve_err(id, "texts", "装载失败：\{message}").stringify(),
            false,
          )
      }
    None => false
  }
  let counts : Map[String, Json] = Map([])
  counts.set(
    "suggestions",
    Json::number(@assets.suggestion_map.length().to_double()),
  )
  counts.set(
    "builtin_notes",
    Json::number(@assets.builtin_notes.length().to_double()),
  )
  counts.set(
    "trap_messages",
    Json::number(@assets.trap_messages.length().to_double()),
  )
  counts.set(
    "error_catalog",
    Json::number(@diag.catalog_texts.length().to_double()),
  )
  // 清空可观测（#323 治④）：被清空段名数组恒在场（无清空 = []）——
  // 字节面稳定，下游可判读
  let cleared : Array[Json] = []
  for c in assets_cleared {
    cleared.push(Json::string(c))
  }
  if catalog_cleared {
    cleared.push(Json::string("error_catalog"))
  }
  counts.set("cleared", Json::array(cleared))
  (serve_ok(id, Json::object(counts)).stringify(), false)
}

///|
/// texts.get 方法帧（#323 治①，2026-10-27）：四表现值回读——
/// texts.install 的读-改-写闭环读口（此前 30 方法零教学文案表读接口，
/// 非 MoonBit 宿主无法自查键集 ⇒ 合法载荷不可构造）。result = 四段
/// 对象（suggestions/builtin_notes/trap_messages 取 @assets.texts_json
/// 原样 + error_catalog 段并位），stringify 后可直接作 install 的
/// payload（get→install 幂等闭环，serve_texts_wbtest 锚）。
fn serve_texts_get_frame(id : Json) -> (String, Bool) {
  let three = @util.json_parse(@assets.texts_json()) catch {
    _ =>
      return (
        serve_err(id, "internal", "texts_json 发射不可解析").stringify(),
        false,
      )
  }
  let m = match three {
    Object(m) => m
    _ =>
      return (
        serve_err(id, "internal", "texts_json 顶层形态异常").stringify(),
        false,
      )
  }
  let cat = @util.json_parse(@diag.catalog_texts_json()) catch {
    _ =>
      return (
        serve_err(id, "internal", "catalog_texts_json 发射不可解析").stringify(),
        false,
      )
  }
  m.set("error_catalog", cat)
  (serve_ok(id, Json::object(m)).stringify(), false)
}
