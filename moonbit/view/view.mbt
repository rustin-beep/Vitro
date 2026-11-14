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
