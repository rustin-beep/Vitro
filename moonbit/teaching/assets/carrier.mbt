///|
/// 教学表载体（#130 批③a，2026-10-17）：suggestions / builtin_notes 两表
/// 拆包后本包只持**空载体 + 装载门**（install_texts/texts_json）——
/// 烘焙数据真源产物在 teaching/content_data（native/CLI 与语言包链接并
/// 经 install_baked 装载；浏览器 wasm 引擎不链接 = lean，宿主懒加载
/// 语言包后经 texts.install 注入）。trap_messages 留本包烘焙（#120 切分
/// 线裁定：trap 帧即时渲染、{name} 占位符引擎填）。
///
/// Map 为 core 可变哈希结构：`pub let` 绑定的**对象本体**可原地
/// clear+fill（install_texts / content_data.install_baked 两装载入口同款
/// 手法）——消费面（steps/typeck）持有的引用自动见覆盖，零改动。

///|
pub let suggestion_map : Map[String, String] = Map([])

///|
/// builtin_notes 条目类型（pub(all)：content_data 生成物跨包构造——
/// 数据产物发射 `@assets.BuiltinNote::` 前缀）。
pub(all) struct BuiltinNote {
  count_note : String
  param_notes : Array[String]
}

///|
pub let builtin_notes : Map[String, BuiltinNote] = Map([])
