///|
/// 教学卡片条目（L1 感知层：icon 语义 id + 标题 + 解释 + 常见原因清单）。
/// icon 值域 = moonbit/icons/index.tsv 的 id 集（52 个语义图标 id，
/// issue #27：emoji 码点退役，字形由消费方按 id 自备；资产随包发布）。
/// 数据由 scripts/gen_diag 从 diagnostics_data/catalog.json 生成
/// （catalog_gen.mbt），本类型为手写契约。
pub(all) struct CatalogEntry {
  code : Int
  icon : String
  title : String
  explanation : String
  common_causes : Array[String]
} derive(Debug, Eq)

///|
pub extend CatalogEntry with Debug::{to_repr}

///|
pub extend CatalogEntry with Eq::{not_equal, equal}

///|
/// 构造（生成代码专用入口；外部构造走同一契约）。
pub fn CatalogEntry::of(
  code : Int,
  icon : String,
  title : String,
  explanation : String,
  common_causes : Array[String],
) -> CatalogEntry {
  { code, icon, title, explanation, common_causes, }
}
