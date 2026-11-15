#!/usr/bin/env node
// demo_smoke 单测（四件套之一）：ArraySnapshot 必填键三向对账（PR #521 审阅 P2-2）。
// 判据：demo_smoke 必填键清单 ≡ 生成字段表（moonbit/bindings/ts/fields.mjs，
// 源 = protocol types）≡ demo 手写 DTO（demo/js/types.ts）——wire 新增字段
// 而 demo_smoke 漏收时本锚必红，不再依赖人肉记得补。
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { ARRAY_SNAPSHOT_KEYS } from "./contract.mts";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "../..");

/** 从生成物文本提取 `ArraySnapshot: [...]` 列表（避免 .mjs↔.d.ts 解析口径差）。 */
function generatedFields(): string[] {
  const src = readFileSync(path.join(ROOT, "moonbit/bindings/ts/fields.mjs"), "utf8");
  const m = /ArraySnapshot: \[([^\]]*)\]/.exec(src);
  assert.ok(m, "生成字段表缺 ArraySnapshot 条目（先跑 gen_protocol_ts）");
  return (m?.[1] ?? "")
    .split(",")
    .map((s) => s.trim().replace(/^"|"$/g, ""))
    .filter((s) => s !== "")
    .sort();
}

test("ArraySnapshot 必填键 ≡ 生成字段表 ≡ demo DTO（wire 新字段漏收即红）", () => {
  const generated = generatedFields();
  assert.deepEqual([...ARRAY_SNAPSHOT_KEYS].sort(), generated, "demo_smoke 必填键与生成字段表不一致");

  const dto = readFileSync(path.join(ROOT, "demo/js/types.ts"), "utf8");
  const block = /export interface ArraySnapshot \{([\s\S]*?)\n\}/.exec(dto);
  assert.ok(block, "demo DTO 缺 ArraySnapshot 接口");
  const dtoKeys = [...(block?.[1] ?? "").matchAll(/^\s{2}([A-Za-z_]\w*)\??:/gm)]
    .map((x) => x[1] ?? "")
    .filter((s) => s !== "")
    .sort();
  assert.deepEqual(dtoKeys, generated, "demo DTO 字段集与生成字段表不一致");
});
