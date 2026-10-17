///|
/// 教学卡片条目（L1 感知层：icon 语义 id + 标题 + 解释 + 常见原因清单）。
/// icon 值域 = moonbit/icons/index.tsv 的 id 集（76 个语义图标 id，
/// issue #27：emoji 码点退役，字形由消费方按 id 自备；资产随包发布）。
/// 数据由 scripts/gen_diag 从 diagnostics_data/catalog.json 生成
/// （catalog_gen.mbt），本类型为手写契约。
pub(all) struct CatalogEntry {
  code : Int32
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
  code : Int32,
  icon : String,
  title : String,
  explanation : String,
  common_causes : Array[String],
) -> CatalogEntry {
  { code, icon, title, explanation, common_causes, }
}

///|
/// 卡片查询（#130 批③b：139 臂穷尽 match 退查表——catalog_texts 载体
/// 经装载门填充；miss = None 与「无卡片码登记缺口
/// codes_without_catalog」同语义。编译期臂-卡对齐闸随拆包转
/// gen_diag -check 幂等 + content_data 对账锚）。
pub fn ErrorCode::catalog(self : ErrorCode) -> CatalogEntry? {
  catalog_texts.get(self.code())
}
