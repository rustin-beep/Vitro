// prelude_fail.test.mts —— #483 fail loud 锚：replay/serve_smoke 采集失败时
// 「产物前置缺失」与「真防线红」必须在 note 文案上分开。
//
// 修前形态（2026-11-05 实录，与 issue #483 同）：serve.exe 缺失时子脚本
// exit=1 + stderr 埋「…serve.exe 不存在——先跑 cd moonbit && moon build
// --target native cmd/serve」，facts 侧只落 note=「未解析到汇总行（exit=1）」
// ——前置因不透传，--strict 判红后极易误诊为防线红往漂移方向排查。
//
// J9：本文件先于 facts.mts 改动入库跑红（import 不到 artifactMissingNote
// → 模块加载即失败），修复后绿。
//
// PR #487 审阅 P3-2/P3-3/P3-4 处置（2026-11-05）：
// - P3-3：检测标记从 freshness 导出常量（ENSURE_FRESH_FAIL_MARKS）锚定真源，
//   形态 1 另以子进程真调 ensureFresh 捕获真实 die 行——文案改动即红，
//   手写字面量脱钩的 fail-open 面封死；
// - P3-2：修复命令从 die 行动态提取（「——先跑 …」段）——wasm 臂走同一
//   ensureFresh（产物 gateway/wasm + vitro_wasm 胶水），命令随子脚本原行
//   走，不再硬编码 native cmd/serve；
// - P3-4：ensureFresh 三种 die（产物缺失/构建失败/构建成功仍缺失）全覆盖
//   ——均属「环境前置未就绪」非防线红。
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import path from "node:path";
import { test } from "node:test";
import { artifactMissingNote } from "./facts.mts";
import { ENSURE_FRESH_FAIL_MARKS } from "../internal/freshness.mts";

const FRESHNESS_URL = pathToFileURL(path.join(import.meta.dirname, "..", "internal", "freshness.mts")).href;

// 形态 1（产物缺失）：**真源锚**——子进程真调 ensureFresh（指向必缺失路径），
// 捕获真实 die 行。freshness.mts 的 die 文案一旦改动，本测试即红（不再依赖
// 手写字面量的巧合匹配）。
function realDieLine(): string {
  const r = spawnSync(
    process.execPath,
    [
      "--input-type=module",
      "-e",
      `const { ensureFresh } = await import(${JSON.stringify(FRESHNESS_URL)});` +
        ` ensureFresh("facts483", "Z:/definitely/missing/serve.exe", ["build", "--target", "native", "cmd/serve"]);`,
    ],
    { encoding: "utf8" },
  );
  const line = (r.stderr ?? "").split("\n").find((l) => l.includes("facts483"));
  assert.ok(line !== undefined, `子进程必须产出 die 行（实得 stderr: ${r.stderr ?? "<空>"} / exit=${r.status})`);
  return line;
}

// 形态 2/3（构建失败 / 构建成功仍缺失）：由真源常量构造（die 文案在
// freshness.mts 内以常量引用拼装，文案改动编译期跟动——构造行跟随真源）。
function synthesizedDieLine(mark: string): string {
  return "serve_smoke: moonbit\_build\native\debug\build\cmd\serve\serve.exe " + mark + "（moon 缓存与磁盘不一致）——删对应 _build 目标目录后重建";
}

test("#483 形态 1 真调 ensureFresh 的真实 die 行 → 前置缺失文案（命令动态提取）", () => {
  const note = artifactMissingNote(realDieLine() + "\n");
  assert.ok(note !== null, "形态 1 真实 die 行必须命中");
  assert.ok(
    note.includes("前置缺失：先跑 cd moonbit && moon build --target native cmd/serve（见 issue #483）"),
    "note 须含从 die 行动态提取的命令（实得 " + note + "）",
  );
  assert.ok(note.includes("serve.exe"), "note 须透传子脚本原行（产物路径可见）");
});

test("#483 P3-2 命令随臂走：die 行含 wasm 臂命令时 note 提取该命令（不硬编码 cmd/serve）", () => {
  const wasmDie =
    "replay: moonbit\_build\wasm-gc\release\build\gateway\wasm\wasm.wasm 不存在——先跑 cd moonbit && moon build --release --target wasm-gc gateway/wasm";
  const note = artifactMissingNote(wasmDie + "\n");
  assert.ok(note !== null);
  assert.ok(
    note.includes("前置缺失：先跑 cd moonbit && moon build --release --target wasm-gc gateway/wasm"),
    "wasm 臂命令必须原样提取（实得 " + note + "）",
  );
});

test("#483 P3-4 形态 2/3（构建失败/构建成功仍缺失）同样归前置缺失", () => {
  const buildFail = "replay: 构建失败——修好构建前不给判定（陈旧产物假红/假绿由此封死）";
  const n1 = artifactMissingNote(buildFail + "\n");
  assert.ok(n1 !== null, "构建失败 die 须命中前置缺失判定");
  assert.ok(n1 !== null && n1.includes("前置缺失"), "形态 2 note 须以前置缺失开头（实得 " + n1 + "）");
  const stillMissing = synthesizedDieLine(ENSURE_FRESH_FAIL_MARKS[2] ?? "");
  const n2 = artifactMissingNote(stillMissing + "\n");
  assert.ok(n2 !== null, "构建成功仍缺失 die 须命中前置缺失判定");
});

test("#483 真防线红输出不误报前置缺失", () => {
  // 无 die 行的失败输出（断言失败/未自报总数）必须返回 null——
  // 否则真防线红会被误标为环境问题（反向遮蔽，比原病更糟）。
  assert.equal(artifactMissingNote("[FAIL] S3 A16 serve 退出码 1\nexit=1"), null);
  assert.equal(artifactMissingNote(""), null);
  // 相近但不完整的行（只有「不存在」无 die 标记）不命中——检测锚定
  // ensureFresh 的完整 die 标记，防误匹配。
  assert.equal(artifactMissingNote("错误: VITRO_CLI 指定的 x.exe 不存在"), null);
});
