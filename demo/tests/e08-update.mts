// E-08 快照闸 · golden 显式重建通道（人工令）——用法：
//
//   cd demo && npx vite build --ssr src/e08/entry.ts --outDir dist-e08
//   node demo/tests/e08-update.mts
//
// 以当前实现重建 demo/e08/golden/*.html 全量快照。E-04 纪律：这是唯一的
// 快照生成入口（测试比对驱动零生成能力），输出必须人工审定 diff 再入库——
// 对齐 scripts/protocol_frames --update-baseline 的「人工令刷新」语义。
// 用例表变化（新增/删除）会连带 golden 文件增删：删除的用例其 golden 一并
// 清掉，保持「用例表 ↔ golden 目录全等」锚绿。
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import type { CaseResult, CorePayload } from "../src/e08/entry.ts";

const here = path.dirname(fileURLToPath(import.meta.url));
const demoRoot = path.resolve(here, "..");
const bundlePath = path.join(demoRoot, "dist-e08", "entry.js");
const goldenDir = path.join(demoRoot, "e08", "golden");

let bundle: typeof import("../src/e08/entry.ts");
try {
  bundle = (await import(pathToFileURL(bundlePath).href)) as typeof import("../src/e08/entry.ts");
} catch {
  console.error("未找到渲染 bundle——先跑：cd demo && npx vite build --ssr src/e08/entry.ts --outDir dist-e08");
  process.exit(1);
}

const payloadDir = path.join(demoRoot, "e08", "payloads");
// 用例输入：payloads/<case>.json 存在则优先（用例专属覆盖，如空态分支），
// 否则吃全量 core.json——与 e08.test.mts 同规则，两处须同批改。
function payloadFor(name: string): CorePayload {
  const over = path.join(payloadDir, `${name}.json`);
  return JSON.parse(readFileSync(existsSync(over) ? over : path.join(payloadDir, "core.json"), "utf8")) as CorePayload;
}

mkdirSync(goldenDir, { recursive: true });
const valid = new Set<string>(bundle.CASE_NAMES);

for (const name of bundle.CASE_NAMES) {
  const result: CaseResult = bundle.renderCase(name, payloadFor(name));
  // 尾换行 = editorconfig 硬性项（CI editorconfig_check 全仓文本面）；比对端
  // e08.test.mts 对称剥离，golden 正文 = renderCase 输出逐字节不变。
  writeFileSync(path.join(goldenDir, `${name}.html`), `${result.html}\n`, "utf8");
  console.log(`golden 重写: ${name}.html (${result.html.length} B)`);
}

// 删除失效 golden（用例已从用例表移除的快照）
for (const f of readdirSync(goldenDir)) {
  if (!f.endsWith(".html")) continue;
  const name = f.replace(/\.html$/, "");
  if (!valid.has(name)) {
    rmSync(path.join(goldenDir, f));
    console.log(`golden 清除（用例已不存在）: ${f}`);
  }
}

console.log(`完成——${bundle.CASE_NAMES.length} 份 golden 已重建，请人工审定 diff 后再入库。`);
