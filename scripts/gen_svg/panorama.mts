// panorama.mts —— 图 M：冻结协议层全景（#273 存量 Go 重写批；原 panorama.go）。
//
// 源：moonbit/docs/spec/STEP_PAYLOAD_SCHEMA_V0_1.md + docs/current/06-出口与协议/。
// 本图零 facts 依赖（数字一律口径化，不制造第二份会漂移的数字拷贝）：图上
// 出现的 14 字段 / v0.1 / 2026-09-12 均为设计常量（协议包 SCHEMA_V0_1_FROZEN_AT /
// SCHEMA_VERSION 同源），非跑批快照。
//
// 落盘：docs/current/06-出口与协议/protocol-panorama.svg
import {
  MARKER_DEF,
  arrow,
  box,
  svgOpen,
  textF,
  textL,
  writeSVG,
} from "./svg.mts";

export function genPanorama(root: string): void {
  const P: string[] = svgOpen(
    1200,
    990,
    "vitro 冻结协议层全景",
    "vitro — 冻结协议层全景 · 单源 × 对拍 × 出口",
    "对账 moonbit/docs/spec/STEP_PAYLOAD_SCHEMA_V0_1.md §0–§9 与 moonbit/protocol/README.mbt.md 演化纪律三条；结构图无数字锚（设计常量：十四字段 / v0.1 / 2026-09-12 冻结）",
  );
  P.push(
    MARKER_DEF,
    textF(600, 56, "tt", "vitro — 冻结协议层全景 · 单源 × 对拍 × 出口", ""),
  );
  // 顶卡：协议本体
  P.push(
    box(40, 96, 1120, 96, "core", 12),
    textF(600, 132, "t", "StepPayload schema v0.1（2026-09-12 冻结）· 字段只增不改语义", ""),
    textF(600, 160, "tc", "十四字段白名单 + v0.2 预留位台账 · 语言中立：任何语言按 schema 解析，无需了解引擎内部", ""),
    textF(600, 184, "tc", "帧结构逐字段图见 step-payload-frame.svg · 冻结常量由 vitro/engine/protocol 出口", ""),
  );
  // 左列：单源派生链（5 卡垂直箭头链，右列同网格）
  P.push(
    box(40, 212, 580, 392, "zone", 14),
    textF(330, 246, "t", "单源派生链（生成绑定）", ""),
    textF(330, 272, "tc", "一个 wire format 只有一个解码器（演化纪律三）", ""),
  );
  const chain: { name: string; sub: string; subCls: string }[] = [
    { name: "STEP_PAYLOAD_SCHEMA_V0_1.md", sub: "权威 schema 文档 · 字段冻结测试主锚", subCls: "tc" },
    { name: "v01_payload_fields.json", sub: "字段真单源（JSON · 生成器输入）", subCls: "tc" },
    { name: "schema_fields_gen.mbt", sub: "闸 gen_protocol_fields -check", subCls: "tn" },
    { name: "moonbit/bindings/ts/index.d.ts + fields.mjs", sub: "闸 gen_protocol_ts -check（双向对账）", subCls: "tn" },
    { name: "consumer.mjs", sub: "TS 首个消费者 · 字段级校验真输出", subCls: "tc" },
  ];
  chain.forEach((n, i) => {
    const y = 288 + i * 62;
    P.push(
      box(64, y, 532, 52, "card", 10),
      textL(84, y + 21, "tn", n.name),
      textL(84, y + 43, n.subCls, n.sub),
    );
    if (i < chain.length - 1) P.push(arrow(330, y + 52, 330, y + 62, "edge"));
  });
  // 右列：对拍与冒烟防线（4 卡同网格 + 底注）
  P.push(
    box(660, 212, 500, 392, "zone", 14),
    textF(910, 246, "t", "对拍与冒烟防线", ""),
    textF(910, 272, "tc", "帧序 · 出口契约 · 会话交互", ""),
  );
  const smokes: { name: string; sub: string }[] = [
    { name: "replay", sub: "S1–S5 帧序列断言（冻结签字回放主锚）" },
    { name: "serve_smoke", sub: "NDJSON 出口冒烟 · 豁免表外置" },
    { name: "interaction_probe", sub: "会话交互 fuzz（帧形状 / payload 不变量）" },
    { name: "protocol 错误帧", sub: "serve 未知 method 必回错（读侧严格纪律二）" },
  ];
  smokes.forEach((s, i) => {
    const y = 288 + i * 62;
    P.push(
      box(684, y, 452, 52, "card", 10),
      textL(704, y + 21, "tn", s.name),
      textL(704, y + 43, "tc", s.sub),
    );
  });
  P.push(textL(684, 580, "tc", "Rust 对拍臂已随删区退役 · MoonBit 臂为现役"));
  // 底带一：实现锚
  P.push(
    box(40, 624, 1120, 72, "card", 12),
    textF(600, 654, "t", "实现锚", ""),
    textF(600, 682, "tn", "vitro/engine/protocol（schema · stream · types · vocabulary）+ session + gateway", ""),
  );
  // 底带二：消费者拓扑
  P.push(
    box(40, 716, 1120, 76, "card", 12),
    textF(600, 746, "t", "消费者拓扑（数据源单源论：引擎画数据，下游画像素）", ""),
    textF(600, 774, "tc", "serve JSON-lines（cmd/serve · cmd/vitro api）· gateway wasm 绑定 · TS @vitro/protocol · 任意第三方语言", ""),
  );
  // 演化纪律带
  P.push(
    box(40, 836, 1120, 88, "warn", 12),
    textF(600, 866, "t", "协议演化纪律三条（对 v0.2 激活与一切 v0.x 追加生效）", ""),
    textF(600, 892, "tc", "缺省字段双条件规则 · 未知容忍非对称（写侧宽容、读侧严格）· 单解码器佐证", ""),
    textF(600, 914, "tc", "纪律成文与依据见 moonbit/protocol/README.mbt.md（openseek 教训转译，2026-09-28）", ""),
  );
  P.push(
    textF(600, 956, "tc", "对账 moonbit/docs/spec/STEP_PAYLOAD_SCHEMA_V0_1.md §0–§9 · 生成：node scripts/gen_svg/main.mts panorama", ""),
  );
  writeSVG(root, "docs/current/06-出口与协议/protocol-panorama.svg", P);
}
