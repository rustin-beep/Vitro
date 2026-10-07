// #27 方案 C：icons.get 方法帧——图标资产通道（业务帧只带语义 id，资产
// 经本方法按 digest 锁定下发）。数据面 = vitro/engine/icons 单源
// （icons_gen.mbt 由 scripts/gen_icons 生成，digest 与几何层
// moonbit/icons/icons.json 同源同值，icon_catalog 闸锁协议值域）。
//
// 参数 `{"ids":["uaf",...]}` 可选：缺省/空数组 = 全量（id 字典序）；
// 按请求序输出、重复 id 去重；含未知 id 整帧拒绝（fail loud 不静默缩水）。

///|
/// icons.get 方法帧（emitter → json_parse → serve_ok 通道，error_catalog 同款）。
/// params 惯例：`Json`（缺省 = `Json::Null`，分发层 json_field 归一）。
fn serve_icons_get_frame(id : Json, params : Json) -> (String, Bool) {
  let ids : Array[String] = []
  match params {
    Json::Object(m) =>
      match m.get("ids") {
        Some(Json::Array(arr)) =>
          for item in arr {
            match item {
              Json::String(s) => ids.push(s)
              _ =>
                return (
                  serve_err(
                    id, "protocol", "icons.get 的 ids 须为字符串数组",
                  ).stringify(),
                  false,
                )
            }
          }
        Some(_) =>
          return (
            serve_err(id, "protocol", "icons.get 的 ids 须为字符串数组").stringify(),
            false,
          )
        None => ()
      }
    _ => ()
  }
  match @icons.export_icons_json(ids) {
    None =>
      (
        serve_err(
          id, "protocol", "icons.get：含未知 icon id（值域 = moonbit/icons/index.tsv 单源，icon_catalog 闸锁）",
        ).stringify(),
        false,
      )
    Some(text) => {
      let parsed = json_parse(text) catch {
        _ =>
          return (
            serve_err(id, "internal", "icons.get 导出解析失败").stringify(),
            false,
          )
      }
      (serve_ok(id, parsed).stringify(), false)
    }
  }
}
