// E-08 快照闸 · 比对驱动（#122 闸门批）——node --test 直跑（node 25 type
// stripping，零构建）；渲染 bundle 由前置 vite build --ssr 步产出
// （dist-e08/entry.js，不入库）。类型面经 `typeof import(源)` 断言与源导出
// 对齐——bundle 导出面 ≡ src/e08/entry.ts 导出面由 tsc 机判，漂移即红。
//
// golden 纪律（E-04）：demo/e08/golden/*.html 是冻结快照，禁止测试内动态
// 生成；刷新走 demo/tests/e08-update.mts 显式通道（人工令），输出须人工
// 审定 diff 再入库。
import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import type { CaseResult, CorePayload } from "../src/e08/entry.ts";

const here = path.dirname(fileURLToPath(import.meta.url));
const demoRoot = path.resolve(here, "..");
const bundlePath = path.join(demoRoot, "dist-e08", "entry.js");

const bundle = (await import(pathToFileURL(bundlePath).href)) as typeof import("../src/e08/entry.ts");

// 用例输入：payloads/<case>.json 存在则优先（用例专属覆盖，如空态分支），
// 否则吃全量 core.json。
const payloadDir = path.join(demoRoot, "e08", "payloads");
function payloadFor(name: string): CorePayload {
  const over = path.join(payloadDir, `${name}.json`);
  return JSON.parse(readFileSync(existsSync(over) ? over : path.join(payloadDir, "core.json"), "utf8")) as CorePayload;
}
const goldenDir = path.join(demoRoot, "e08", "golden");

// 用例表 ↔ golden 目录全等——多快照（删用例忘删 golden）与少快照（加用例
// 忘生成）都红，防快照集僵死。
test("用例表与 golden 目录全等", () => {
  const golden = readdirSync(goldenDir)
    .filter((f) => f.endsWith(".html"))
    .map((f) => f.replace(/\.html$/, ""))
    .sort();
  assert.deepEqual(golden, [...bundle.CASE_NAMES].sort());
});

for (const name of bundle.CASE_NAMES) {
  test(`E-08 ${name}: 渲染输出 ≡ 冻结 golden`, () => {
    // golden 文件尾换行 = editorconfig 硬性项（update 端写入），比对前对称
    // 剥离——golden 正文与 renderCase 输出仍逐字节锚定。
    const golden = readFileSync(path.join(goldenDir, `${name}.html`), "utf8").replace(/\n$/, "");
    const result: CaseResult = bundle.renderCase(name, payloadFor(name));
    assert.equal(result.html, golden);
  });
}
