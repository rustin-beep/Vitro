// E-08 夹具同形性闸（#324 治本批，2026-10-31）——「金样本 payload 与引擎
// 实产同形」的机判防线：现场跑引擎（demo/e08/bubble.c，前端 worker 同款
// 方法序列）与 payloads/core.json 做形态比对，任一不符即红。这把「夹具
// 漂移」（#324：手写夹具与实产值形态完全相反——label 英文 id vs 中文、
// phase 中文 vs 英文 id、缺 code_file/semantic_label_id、labels 段字符串数组
// vs 对象数组、capabilities 段数组 vs 对象）变成可机判的失败，E-08 渲染
// 金标准从此锚在真实协议流形态上。
//
// 断言面（形态，非值全等——帧窗口/裁剪合法，形态漂移不合法）：
//   S1 frames 非空            S2 帧字段集全等（并集双向）
//   S3 label/label_id 值域⊆   S4 phase 值域⊆
//   S5 labels 段=对象数组且 id∈受控词表
//   S6 capabilities=对象且顶层键≡实产
//   S7 catalog 卡字段集⊆且 code_str∈实产码集
//   S8 diagband-trap 帧同 S2  S9 outputs 三流为字符串
//
// 引擎臂：缺省 js（CI artifact 同形）；VITRO_E08_BACKEND=native 双臂对拍
// （AGENTS 三臂纪律——防线验收结论须双臂一致）。
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { engineLive, liveShape } from "./e08_live.mts";

const here = path.dirname(fileURLToPath(import.meta.url));
const payloadDir = path.resolve(here, "..", "e08", "payloads");

function loadPayload(name: string): Record<string, unknown> {
  return JSON.parse(readFileSync(path.join(payloadDir, `${name}.json`), "utf8")) as Record<string, unknown>;
}

test("E-08 同形性：core.json ≡ 引擎实产形态", () => {
  const shape = liveShape(engineLive());
  const core = loadPayload("core");
  const diffs: string[] = [];

  // S1 frames 非空
  const frames = core["frames"] as Array<Record<string, unknown>> | undefined;
  if (!Array.isArray(frames) || frames.length === 0) {
    assert.fail("S1 core.json frames 缺失或为空——E-08 输入不是 step 帧流");
  }

  // S2 帧字段集全等（夹具字段并集 vs 实产字段并集，双向）
  const fixtureFields = new Set<string>();
  for (const f of frames) for (const k of Object.keys(f)) fixtureFields.add(k);
  const missing = shape.frameFields.filter((k) => !fixtureFields.has(k));
  const extra = [...fixtureFields].filter((k) => !shape.frameFields.includes(k));
  if (missing.length > 0) diffs.push(`S2 夹具帧缺字段（实产有）：${missing.join(",")}`);
  if (extra.length > 0) diffs.push(`S2 夹具帧多字段（实产无）：${extra.join(",")}`);

  // S3 semantic_label / semantic_label_id 值域 ⊆ 实产
  for (const [field, domain] of [
    ["semantic_label", shape.labelValues],
    ["semantic_label_id", shape.labelIds],
  ] as const) {
    for (const f of frames) {
      const v = f[field];
      if (v === undefined) continue; // 字段缺省已由 S2 抓
      if (typeof v !== "string" || !domain.includes(v)) {
        diffs.push(`S3 ${field} 值不在实产值域：${JSON.stringify(v)}`);
        break;
      }
    }
  }

  // S4 algorithm_step.phase 值域 ⊆ 实产
  for (const f of frames) {
    const as = f["algorithm_step"] as { phase?: unknown } | null | undefined;
    if (as === null || as === undefined) continue;
    const p = as.phase;
    if (p === undefined) continue;
    if (typeof p !== "string" || !shape.phases.includes(p)) {
      diffs.push(`S4 algorithm_step.phase 值不在实产值域：${JSON.stringify(p)}（实产：${shape.phases.join(",")}）`);
      break;
    }
  }

  // S5 labels 段 = 对象数组，每条 id ∈ 实产受控词表
  const labels = core["labels"];
  const labelIds = shape.semanticLabels
    .map((l) => l["id"])
    .filter((v): v is string => typeof v === "string");
  if (!Array.isArray(labels) || labels.length === 0) {
    diffs.push("S5 labels 段缺失或为空（实产 = semantic_labels 对象数组）");
  } else {
    for (const l of labels) {
      if (typeof l !== "object" || l === null) {
        diffs.push(`S5 labels 段元素非对象（实产为 {id,domain,status,template,...}）：${JSON.stringify(l)}`);
        break;
      }
      const id = (l as Record<string, unknown>)["id"];
      if (typeof id !== "string" || !labelIds.includes(id)) {
        diffs.push(`S5 labels 段 id 不在引擎受控词表：${JSON.stringify(id)}`);
        break;
      }
    }
  }

  // S6 capabilities = 对象且顶层键 ≡ 实产
  const cap = core["capabilities"];
  if (typeof cap !== "object" || cap === null || Array.isArray(cap)) {
    diffs.push(`S6 capabilities 段形态非对象（实产 = {engine,schema,behavior_contracts,...}）：${typeof cap}`);
  } else {
    const liveKeys = Object.keys(shape.capabilities).sort();
    const fixtureKeys = Object.keys(cap).sort();
    if (JSON.stringify(liveKeys) !== JSON.stringify(fixtureKeys)) {
      diffs.push(`S6 capabilities 顶层键不符：实产 [${liveKeys.join(",")}] vs 夹具 [${fixtureKeys.join(",")}]`);
    }
  }

  // S7 catalog 卡字段集 ⊆ 实产且 code_str ∈ 实产码集
  const catalog = core["catalog"] as Array<Record<string, unknown>> | undefined;
  if (!Array.isArray(catalog) || catalog.length === 0) {
    diffs.push("S7 catalog 段缺失或为空（实产 = error_catalog 卡集）");
  } else if (shape.catalog.length > 0) {
    const liveFields = new Set<string>();
    for (const c of shape.catalog) for (const k of Object.keys(c)) liveFields.add(k);
    const liveCodes = new Set<string>(
      shape.catalog.map((c) => c["code_str"]).filter((v): v is string => typeof v === "string"),
    );
    for (const c of catalog) {
      const bad = Object.keys(c).filter((k) => !liveFields.has(k));
      if (bad.length > 0) {
        diffs.push(`S7 catalog 卡多字段（实产无）：${bad.join(",")}`);
        break;
      }
      const code = c["code_str"];
      if (typeof code !== "string" || !liveCodes.has(code)) {
        diffs.push(`S7 catalog 卡 code_str 不在引擎码集：${JSON.stringify(code)}`);
        break;
      }
    }
  }

  // S9 outputs 三流为字符串
  const outputs = core["outputs"] as Record<string, unknown> | undefined;
  for (const stream of ["stdout", "stderr", "note"]) {
    if (!outputs || typeof outputs[stream] !== "string") {
      diffs.push(`S9 outputs.${stream} 缺失或非字符串`);
    }
  }

  assert.deepEqual(diffs, [], `E-08 夹具与引擎实产形态漂移（处置：node demo/tests/e08-export.mts 重导后人工审定）：\n${diffs.map((d) => `  - ${d}`).join("\n")}`);
});

test("E-08 同形性：diagband-trap 帧（若在场）≡ 实产字段集", () => {
  const shape = liveShape(engineLive());
  const trap = loadPayload("diagband-trap");
  const frames = trap["frames"] as Array<Record<string, unknown>> | undefined;
  if (!Array.isArray(frames) || frames.length === 0) return; // 空帧形态合法（trap 场景可零帧）
  const fixtureFields = new Set<string>();
  for (const f of frames) for (const k of Object.keys(f)) fixtureFields.add(k);
  const missing = shape.frameFields.filter((k) => !fixtureFields.has(k));
  const extra = [...fixtureFields].filter((k) => !shape.frameFields.includes(k));
  assert.deepEqual(
    { missing, extra },
    { missing: [], extra: [] },
    `diagband-trap.json 帧字段集与实产不符（缺 [${missing.join(",")}] / 多 [${extra.join(",")}]）`,
  );
});
