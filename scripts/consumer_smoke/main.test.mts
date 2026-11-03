// consumer_smoke.test.mts —— 纯判定面（judgeWasmSurface / judgeLangpack 各红路）+ 基线/bridges 真实面对账。
// 端到端（真产物装载 + 真调用）在 CI gates-wasm serve_channel slice 活行，不在此 spawn（scripts-ts job 无 wasm 产物）。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {
  BASELINE_PATH,
  BRIDGES_RULES_PATH,
  LANGPACK_BRIDGE_FILE,
  WASM_BRIDGE_FILE,
  judgeLangpack,
  judgeWasmSurface,
  loadBaseline,
  loadBridges,
  sameSet,
} from "./main.mts";
import type { Baseline, Bridges } from "./main.mts";
import { projectRoot } from "../internal/capi.mts";

const B: Baseline = {
  schema: 1,
  wasm: { allowed_import_modules: ["_", "wasm:js-string"], js_string_functions: ["length", "concat"] },
  langpack: { payload_top_keys: ["a", "b"] },
};
const BR: Bridges = { files: { [WASM_BRIDGE_FILE]: ["invoke", "reset"], [LANGPACK_BRIDGE_FILE]: ["texts_json"] } };

function surf(imports: Record<string, string[]>, exports: string[]) {
  return { imports: new Map(Object.entries(imports)), exports };
}

test("sameSet：序无关 / 长度与元素双判", () => {
  assert.equal(sameSet(["b", "a"], ["a", "b"]), true);
  assert.equal(sameSet(["a"], ["a", "a"]), false);
  assert.equal(sameSet([], []), true);
});

test("judgeWasmSurface：绿 + 五红路（规范外模块 / js-string 多一 / 少一 / export 漂移 / 「_」缺席）", () => {
  const good = surf({ _: ["x", "y"], "wasm:js-string": ["concat", "length"] }, ["invoke", "reset"]);
  assert.ok(judgeWasmSurface(good, B, BR).every((f) => f.ok), "基线形态全绿");
  const byId = (fs_: ReturnType<typeof judgeWasmSurface>) => Object.fromEntries(fs_.map((f) => [f.id.slice(0, 2), f.ok]));
  // W1：产物多要一个 env 模块 = 宿主被迫供给
  assert.equal(byId(judgeWasmSurface(surf({ _: ["x"], "wasm:js-string": ["concat", "length"], env: ["abort"] }, ["invoke", "reset"]), B, BR))["W1"], false);
  // W1：「_」常量模块缺席（产物形态变）
  assert.equal(byId(judgeWasmSurface(surf({ "wasm:js-string": ["concat", "length"] }, ["invoke", "reset"]), B, BR))["W1"], false);
  // W2：多一个 js-string 内建（codePointAt）= 供给面扩大
  assert.equal(byId(judgeWasmSurface(surf({ _: ["x"], "wasm:js-string": ["concat", "length", "codePointAt"] }, ["invoke", "reset"]), B, BR))["W2"], false);
  // W2：少一个
  assert.equal(byId(judgeWasmSurface(surf({ _: ["x"], "wasm:js-string": ["length"] }, ["invoke", "reset"]), B, BR))["W2"], false);
  // W3：产物 export 多一个（内部面泄漏）/ 少一个（桥断）
  assert.equal(byId(judgeWasmSurface(surf({ _: ["x"], "wasm:js-string": ["concat", "length"] }, ["invoke", "reset", "leak"]), B, BR))["W3"], false);
  assert.equal(byId(judgeWasmSurface(surf({ _: ["x"], "wasm:js-string": ["concat", "length"] }, ["invoke"]), B, BR))["W3"], false);
  // W3：bridges 登记空 → 红（空集不得绿）
  assert.equal(byId(judgeWasmSurface(good, B, { files: {} }))["W3"], false);
});

test("judgeLangpack：绿 + 导出漂移 / 顶层键漂移红", () => {
  assert.ok(judgeLangpack(["texts_json"], ["b", "a"], B, BR).every((f) => f.ok));
  assert.equal(judgeLangpack(["texts_json", "extra"], ["a", "b"], B, BR)[0]!.ok, false);
  assert.equal(judgeLangpack(["texts_json"], ["a"], B, BR)[1]!.ok, false);
  assert.equal(judgeLangpack(["texts_json"], ["a", "b", "c"], B, BR)[1]!.ok, false);
});

test("loadBaseline：真实基线可加载 + schema/空集 fail loud", () => {
  const b = loadBaseline(path.join(projectRoot(), BASELINE_PATH));
  assert.equal(b.wasm.js_string_functions.length, 6, "引擎实际只要 6 个 js-string 内建（W4 报告实测）");
  // 基线内名字须 ∈ js-string-builtins 提案 13 内建名（防拼错成永红/永绿）
  const SPEC13 = ["cast", "test", "fromCharCodeArray", "intoCharCodeArray", "fromCharCode", "fromCodePoint", "charCodeAt", "codePointAt", "length", "concat", "substring", "equals", "compare"];
  for (const n of b.wasm.js_string_functions) assert.ok(SPEC13.includes(n), `${n} 非 js-string 提案内建名`);
  assert.deepEqual([...b.wasm.allowed_import_modules].sort(), ["_", "wasm:js-string"]);
  assert.equal(b.langpack.payload_top_keys.length, 4, "baked_payload_json 四段（#130 批③b）");
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-cs-"));
  const p = path.join(dir, "b.json");
  fs.writeFileSync(p, JSON.stringify({ schema: 2 }));
  assert.throws(() => loadBaseline(p), /schema/);
  fs.writeFileSync(p, JSON.stringify({ schema: 1, wasm: { allowed_import_modules: [], js_string_functions: [] }, langpack: { payload_top_keys: ["a"] } }));
  assert.throws(() => loadBaseline(p), /空集/);
});

test("loadBridges：真实 pkg_deps rules.json 两桥在场（与 pkg_deps 判据⑤同源）", () => {
  const br = loadBridges(path.join(projectRoot(), BRIDGES_RULES_PATH));
  // **改导出面连坐义务（PR #452 审阅 P3-7）**：本 test 的名集是硬编码真值锚（与
  // rules.json bridges 互为对账，非「从 bridges 读」的空转）——改 bridges 时本锚必须
  // 连坐改（同侧连坐链：rules.json bridges ↔ 本锚 ↔ consumer_smoke/baseline.json 注释互指）
  assert.deepEqual([...(br.files[WASM_BRIDGE_FILE] ?? [])].sort(), ["engine_version", "invoke", "protocol_version", "reset"]);
  assert.deepEqual(br.files[LANGPACK_BRIDGE_FILE], ["texts_json"]);
});
