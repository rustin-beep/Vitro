///|
/// 四表规范 JSON（#130 批③b 扩 error_catalog 段）——content_data.
/// baked_payload_json 单源（teaching 三段 + 诊断卡片段并装）。
#export_name("texts_json")
pub fn texts_json() -> String {
  @content_data.baked_payload_json()
}
