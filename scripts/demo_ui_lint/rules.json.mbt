// 手写真源（jsonmbt import 产初版后人工建模接管，4913eece；本文件即真相源，直接编辑后
// `jsonmbt build --pretty` 再生 .json 供闸门消费——AGENTS.md 第 13 条流程）。
// 手工建模注记（J4001 空数组逃生门，#14 前的临时形态）：class_whitelist /
// var_whitelist 为空数组占位（元素类型按语义定为 String 白名单），import
// 无法推断故本文件手写——数据变更仍走改本文件 + jsonmbt build。
// where 字段名保留字：MoonBit 侧 where_（#13 field-alias，JSON 键保持 where）。
// jsonmbt: field-alias DynamicClassAssign.where_ = "where"

///|
pub struct DynamicClassAssign {
  where_ : String
  classes : Array[String]
}

///|
pub struct DynamicIdPrefix {
  prefix : String
  ids : Array[String]
}

///|
pub struct Rules {
  _comment : String
  dynamic_class_assigns : Array[DynamicClassAssign]
  dynamic_id_prefixes : Array[DynamicIdPrefix]
  class_whitelist : Array[String]
  var_whitelist : Array[String]
}

///|
pub let rules : Rules = Rules::{
  _comment: "demo UI 契约：动态类名/ID 与静态白名单的对账基准（scripts/demo_ui_lint 判定闸消费）",
  dynamic_class_assigns: [
    DynamicClassAssign::{
      where_: "setStatus: el.className = \"pill \" + kind（kind 为状态字面量）",
      classes: ["idle", "busy", "ok", "err", "wait"],
    },
    DynamicClassAssign::{
      where_: "bandRender: b.className = \"blk \" + r.kind（引擎 region.kind 枚举）",
      classes: ["global", "heap", "stack", "freed"],
    },
  ],
  dynamic_id_prefixes: [
    DynamicIdPrefix::{
      prefix: "tab-",
      ids: ["tab-result", "tab-memory", "tab-catalog", "tab-proto"],
    },
  ],
  class_whitelist: [],
  var_whitelist: [],
}
