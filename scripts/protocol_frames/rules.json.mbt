// 手写真源（jsonmbt import 产初版，7c9c7e6d 翻转为唯一真相源；本文件即真相源，
// 直接编辑后 `jsonmbt build --pretty` 再生 .json 供闸门消费——AGENTS.md 第 13 条流程）。

///|
pub struct Rules {
  _comment : String
  skip_methods : Map[String, String]
  masks : Array[Name]
}

///|
pub struct Name {
  name : String
  pattern : String
  replace : String
  reason : String
}

///|
pub let rules : Rules = Rules::{
  _comment: "protocol_frames 帧对拍的分叉处置规则（2026-10-04 建表；D 桶收口 2026-10-09：oracle 缺陷族 5 mask 随基线翻转 mb 臂真值删除——delta/max_steps/heatmap_count/algorithm_matches/未知方法清单五面恢复值冻结，oracle 时代分叉定性见已知限制与差异.md 条目 10-13 终态）。skip_methods = 整帧豁免（键集结构性分叉——serve_smoke 豁免表同口径条目，长期）；masks = 帧内字段值/文本替换（作用于 canonicalize+compact 后的单行帧）。规则须非空（空集不得绿——已知分叉面显式登记）；mask 条目零命中不判红（依赖帧面演进，与 skip 不同域）。skip 为方法粒度（帧级拆分不预建）。",
  skip_methods: {
    "capabilities": "键集结构性分叉（2026-09-28 审阅批 P3-② + serve_smoke 永久豁免同口径三条）：MoonBit 无 capi 层（.mbti 取代 ABI 版本化）⇒ abi/engine_version 不出 + languages.cpp 节不出（F-2 砍 C++）；协议版本由 wasm-gc host.js 的 protocol_version 断言承担",
    "memory.dump": "1MB 映像 base64 帧（#49 批二 2026-10-06 加入 gateway）：帧文本 ~1.4MB 不适合基线全文冻结；覆盖面 = gateway wbtest 往返锚（serve_memory_dump_roundtrip：帧值==base64(dump_memory_raw) 单源对账）+ vitro_cli_smoke 映像对拍（双臂 --dump-memory 1MB 逐字节 cmp）——帧键集由 wbtest 锚锁",
  },
  masks: [
    Name::{
      name: "engine_version-del",
      pattern: "(,?\"engine_version\":\"[^\"]*\")",
      replace: "",
      reason: "engine_version 为构建期身份串（Rust=git 短哈希、MoonBit=moon.mod 版本）。**语义诚实化（审阅 P3-③）：本 mask 为无条件键抹除——单侧独现该键时同样被抹平（键集分叉探测不由此规则承担，首版注释「单臂独现应红」与实现不符已勘正）**；当前零命中（capabilities 已整帧 skip，其余帧无此键），属防御位——散出点出现时若帧与基线两侧同现可直接抹，单侧独现应改走 skip 并给理由",
    },
    // D 桶收口（2026-10-09，refs #47 批五）：以下 5 条 oracle 缺陷族/已收敛
    // mask 随基线翻转 mb 臂真值删除——delta/max_steps/heatmap_count/
    // algorithm_matches/未知方法清单五面恢复值冻结（原条目定性终态见
    // 已知限制与差异.md 条目 10-13）。
  ],
}
