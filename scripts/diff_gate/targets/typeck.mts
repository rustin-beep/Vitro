#!/usr/bin/env node
// typeck_diff —— S4 类型检查层差分对拍（E1–E4）（#273 差分族重构批；
// 原 scripts/typeck_diff/main.go）。
//
// 与 lexer 的三处真差异（都在本文件内自持）：
//   ① digest 形状 = `version/note/modes`，节名 `corpus-<name>`，节内
//      `sources/resp_hashes`（lexer 是扁平的 version/sources/tsvs）
//   ② 判红退出码 = **2**（lexer 是 1）——各驱动历史行为不同，不统一
//   ③ 语料集只吃 `.c`（listCFiles 口径；lexer 吃 .c/.h/.in）
// 另有两例 known-fork（有意分叉），golden 比对时跳过并单列。
//
// E1/E4 为全响应逐字节比对（经 canonicalize 归一）；E2/E3 投影一致则必然一致，
// 由 E4 覆盖（详见原 Go 版头注）。
import fs from "node:fs";
import path from "node:path";
import { canonicalize } from "../../internal/canonicalize.mts";
import {
  moonDump,
  sha16,
  type DiffTarget,
  type Fail,
  type GateContext,
  type GoldenStore,
} from "../../internal/diffgate.mts";
import { makeFail } from "../../internal/genio.mts";
import {
  loadModesDigest,
  makeModesStore,
  saveModesDigest,
  serializeModesDigest,
  type ModesDigest,
  type ModesSec,
} from "../../internal/modesdigest.mts";

/** 判红出口：typeck 历史口径是 exit 2（与 lexer 的 1 不同，保持原样）。 */
export function fatal(msg: string): never {
  return makeFail("typeck_diff: ", 2)(msg);
}

const GOLDEN_REL = "scripts/typeck_diff/golden_digest.json";
const NOTE = "freeze 时已全量对拍；golden = mb 归一 hash ≡ 清单；fork 例 golden 跳过";
const MODE_PREFIX = "corpus-";

/** 有意分叉例（形状校验走现模式 / wbtest 锚，不参与 golden 比对）。 */
const KNOWN_FORKS: Record<string, string> = {
  "function_pointer_return_ptr.c":
    "局部函数指针双层→C 单层（F3-v2）——typeck 消费面放大（W3055 分叉）",
  "kr_5_11.c": "局部函数原型双层→C 单层（F3-v2）——typeck 消费面放大",
};

export type TypeckSec = ModesSec;
export type TypeckDigest = ModesDigest;

export function loadTypeckDigest(root: string, fail: Fail = fatal): TypeckDigest {
  return loadModesDigest(root, GOLDEN_REL, NOTE, fail);
}

export function serializeTypeckDigest(d: TypeckDigest): string {
  return serializeModesDigest(d);
}

export function saveTypeckDigest(root: string, d: TypeckDigest, fail: Fail = fatal): void {
  saveModesDigest(root, GOLDEN_REL, d, fail);
}

function makeTypeckGolden(root: string): GoldenStore {
  return makeModesStore(root, GOLDEN_REL, NOTE, "先 --freeze", (n) => MODE_PREFIX + n, fatal);
}

export { makeTypeckGolden };

// ---- 差异面：dump 与归一 ----

/** 单样本产物定位：`<stem>.c.typeck.json` 优先，退 `<stem>.typeck.json`。 */
function typeckRawOf(moonDir: string, file: string, fail: Fail): Buffer {
  const base = path.basename(file);
  const stem = base.slice(0, base.length - path.extname(base).length);
  for (const name of [`${stem}.c.typeck.json`, `${stem}.typeck.json`]) {
    const p = path.join(moonDir, name);
    if (fs.existsSync(p)) return fs.readFileSync(p);
  }
  return fail(`MoonBit 侧输出缺失: ${stem}`);
}

export function runTypeckCases(ctx: GateContext, fail: Fail = fatal): Map<string, string> {
  // 注意：typeck 喂**原语料目录**（不喂 LF 归一副本）——与原 Go 版一致，
  // 行尾敏感性由 sources 的 sha8（归一后）单独把关。
  moonDump(ctx.root, "cmd/dump_typeck", [ctx.corpus, ctx.workDir], fail);
  const out = new Map<string, string>();
  for (const f of fs.readdirSync(ctx.corpus).filter((n) => n.endsWith(".c")).sort()) {
    const raw = typeckRawOf(ctx.workDir, f, fail);
    out.set(f, sha16(canonicalize(raw)));
  }
  return out;
}

export const typeckTarget: DiffTarget = {
  name: "typeck_diff",
  fail: fatal,
  golden: (root: string) => makeTypeckGolden(root),
  corpusExts: [".c"],
  knownForks: KNOWN_FORKS,
  runCases: (ctx: GateContext) => runTypeckCases(ctx),
};
