// E-08 core.json / diagband-trap.json 重导通道（#324 治本批，2026-10-31；
// 人工令——E-04 纪律：产物必须人工审定 diff 再入库）。以 demo/e08/bubble.c
// 与 demo/e08/uaf.c 为输入现场跑引擎（前端 worker 同款方法序列），把两份
// payload 的引擎数据段整体换为实产：
//   core.json：frames / outputs / memory / capabilities / labels / catalog
//   diagband-trap.json：frames（取 step 流末帧 = trap 帧，实产
//     root_cause_hint + pointer_snapshots Freed 态）/ stopped（trap_message
//     实产文案）/ runStats（run 帧真值）/ catalog
// 手写保留段（教学锚，非引擎数据）：core 的 currentCase（id/label/source
// 真源引用/referenceOutput=实产 stdout）与 idx（展示帧定位，--idx 覆盖，
// 缺省 = 首个 phase==="swap" 帧——「交换瞬间」教学语义）。
//
// 用法：
//   node demo/tests/e08-export.mts [--idx N]
//   VITRO_E08_BACKEND=native node demo/tests/e08-export.mts   （native 臂对拍）
//
// 导出后连坐：
//   1. 人工审定 demo/e08/payloads/*.json diff
//   2. cd demo && npx vite build --ssr src/e08/entry.ts --outDir dist-e08
//      && node demo/tests/e08-update.mts   重冻 golden（人工审定）
//   3. node --test demo/tests/e08-shape.test.mts   同形性闸必须绿
import { writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { engineLive, liveShape, BUBBLE_C, UAF_C } from "./e08_live.mts";
import { readFileSync } from "node:fs";

const here = path.dirname(fileURLToPath(import.meta.url));
const payloadDir = path.resolve(here, "..", "e08", "payloads");
const corePath = path.join(payloadDir, "core.json");
const trapPath = path.join(payloadDir, "diagband-trap.json");

const live = engineLive();
const shape = liveShape(live);

// idx：--idx 显式给；缺省 = 首个 phase==="swap" 帧（无则 0）
let idx = 0;
const argIdx = process.argv.indexOf("--idx");
if (argIdx !== -1 && process.argv[argIdx + 1] !== undefined) {
  idx = Number.parseInt(process.argv[argIdx + 1] as string, 10);
  if (!Number.isInteger(idx) || idx < 0 || idx >= live.frames.length) {
    throw new Error(`--idx 越界：${idx}（帧域 [0,${live.frames.length})）`);
  }
} else {
  const firstSwap = live.frames.findIndex(
    (f) => (f["algorithm_step"] as { phase?: unknown } | undefined)?.phase === "swap",
  );
  idx = firstSwap === -1 ? 0 : firstSwap;
}

const source = readFileSync(BUBBLE_C, "utf8");
const prev = JSON.parse(readFileSync(corePath, "utf8")) as Record<string, unknown>;
const prevCase = (prev["currentCase"] ?? {}) as Record<string, unknown>;

const out = {
  frames: live.frames,
  idx,
  outputs: live.outputs,
  memory: live.memory,
  catalog: live.catalog,
  capabilities: live.capabilities,
  labels: live.semanticLabels,
  currentCase: {
    ...prevCase,
    id: typeof prevCase["id"] === "string" ? (prevCase["id"] as string) : "bubble",
    label: typeof prevCase["label"] === "string" ? (prevCase["label"] as string) : "冒泡排序",
    source,
    referenceOutput: live.outputs.stdout,
  },
};

writeFileSync(corePath, `${JSON.stringify(out, null, 2)}\n`, "utf8");

// diagband-trap：真 UAF 实产（argv0="main.c" —— code_file 实产值与旧夹具
// 同形态；trap 帧 = step 流末帧）
const trapLive = engineLive(UAF_C, { argv0: "main.c" });
if (trapLive.trapMessage === null) throw new Error("[e08-export] uaf.c 未按预期 trap——diagband-trap 用例语义失配");
const trapFrame = trapLive.frames[trapLive.frames.length - 1];
if (trapFrame === undefined) throw new Error("[e08-export] uaf.c step 流为空");
const trapPrev = JSON.parse(readFileSync(trapPath, "utf8")) as Record<string, unknown>;
const trapOut = {
  ...trapPrev,
  catalog: trapLive.catalog,
  // 审阅 P3：frames 全量 + idx=trap 帧下标——旧稿裁 1 帧+idx=0 与真机
  // 24 帧不同形（DiagBand 当前只判 frames.length 非空属碰巧等价）
  frames: trapLive.frames,
  idx: trapLive.frames.length - 1,
  compileOk: true,
  // stopped 组装对齐 demo worker 前端口径（engine.worker.ts drainSteps：
  // trap 分支 stopped = "受检终止：" + trap_message 全文——session.trapped
  // 的 startsWith 判定与 DiagBand trap 详报都消费这个前缀形态）
  stopped: `受检终止：${trapLive.trapMessage}`,
  runStats: trapLive.run,
};
writeFileSync(trapPath, `${JSON.stringify(trapOut, null, 2)}\n`, "utf8");

// 语义摘要（审阅 P3：1.6MB JSON 的 git diff 事实上不可人工逐行审定——
// 审定走本摘要 + golden diff 抽样：帧数/标注健康位/锚点帧数组值/trap 位）
const labeledCount = live.frames.filter((f) => f["algorithm_step"] !== null && f["algorithm_step"] !== undefined).length;
const midLineLabeled = live.frames.filter((f, i) => {
  const has = f["algorithm_step"] !== null && f["algorithm_step"] !== undefined;
  const next = live.frames[i + 1];
  return has && next !== undefined && next["code_line"] === f["code_line"];
}).length;
const anchorFrame = live.frames[idx] as Record<string, unknown> | undefined;
if (anchorFrame === undefined) throw new Error(`[e08-export] idx=${idx} 越界（帧域 [0,${live.frames.length})）——锚点帧缺失`);
const anchorSnap = (anchorFrame["array_snapshots"] as Array<{ name?: unknown; elements?: unknown }> | undefined)?.[0];

console.log(`core.json 已重导（审定走下方语义摘要 + golden diff 抽样，非逐行 diff）：${path.relative(process.cwd(), corePath)}`);
console.log(`  frames: ${live.frames.length} 帧（${shape.frameFields.length} 字段：${shape.frameFields.join(",")}）`);
console.log(`  标注健康位: 标注帧 ${labeledCount} / 行中间帧带标注 ${midLineLabeled}（单批口径应恒 0——非 0 即行末不变量崩塌，见 e08_live 头注口径声明）`);
console.log(`  idx: ${idx}${argIdx !== -1 ? "（--idx 显式）" : "（缺省=首个 swap 帧）"} | 锚点帧 code_line=${String(anchorFrame["code_line"])} label=${JSON.stringify(anchorFrame["semantic_label"])} 快照=${JSON.stringify(anchorSnap?.elements ?? "(无)")}`);
console.log(`  label 值域: ${shape.labelValues.length} 种 | label_id 值域: ${shape.labelIds.length} 种 | phase 值域: ${shape.phases.join(",")}`);
console.log(`  outputs.stdout: ${JSON.stringify(live.outputs.stdout)} | stderr: ${live.outputs.stderr.length} B | note: ${live.outputs.note.length} B`);
console.log(`  memory 键: ${Object.keys(live.memory).join(",")}`);
console.log(`  catalog: ${live.catalog.length} 卡 | semantic_labels: ${live.semanticLabels.length} 条`);
console.log(`diagband-trap.json 已重导：${path.relative(process.cwd(), trapPath)}`);
console.log(`  frames 全量 ${trapLive.frames.length} 帧 | idx=trap 帧 ${trapLive.frames.length - 1} | trap 帧 step_index=${String(trapFrame["step_index"])} label_id=${JSON.stringify(trapFrame["semantic_label_id"])} | runStats: ${JSON.stringify(trapLive.run)}`);
console.log(`连坐：vite build --ssr + e08-update.mts 重冻 golden → e08-shape.test.mts 必须绿`);
