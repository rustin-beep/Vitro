// parser.test.mts —— 合成语料模式（三个）+ 分叉语义（threshold C 族整体 fork）
// + presence 源指纹档 + 真实仓库四模式对拍。
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { THRESHOLD_SAMPLE_COUNT, parserTarget } from "./parser.mts";
import { projectRoot } from "../../internal/capi.mts";
import { loadModesDigest } from "../../internal/modesdigest.mts";
import type { Fail } from "../../internal/diffgate.mts";

const boom: Fail = (msg: string): never => {
  throw new Error(msg);
};

const run = (args: string[]) =>
  spawnSync(process.execPath, [path.join(projectRoot(), "scripts/diff_gate/main.mts"), "parser", ...args], {
    cwd: projectRoot(),
    encoding: "utf8",
  });

test("threshold 样本数 = A/B 族 7 + C 族 16 = 23（与入库 golden 节对账）", () => {
  const d = loadModesDigest(projectRoot(), "scripts/parser_diff/golden_digest.json", "", boom);
  const sec = d.modes.threshold;
  assert.ok(sec !== undefined);
  assert.equal(Object.keys(sec.resp_hashes).length, THRESHOLD_SAMPLE_COUNT);
  assert.equal(THRESHOLD_SAMPLE_COUNT, 23);
});

test("三个合成模式都在 target 声明里，且各自 seed 的样本数与 golden 节一致", () => {
  const syn = parserTarget.syntheticModes;
  assert.ok(syn !== undefined);
  assert.deepEqual(Object.keys(syn).sort(), ["--legal-deep", "--pathological", "--threshold"]);
  const counts: Record<string, number> = {};
  for (const [flag, mode] of Object.entries(syn)) {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-psyn-"));
    try {
      mode.prepare(tmp);
      counts[flag] = fs.readdirSync(tmp).filter((n) => n.endsWith(".c")).length;
    } finally {
      fs.rmSync(tmp, { recursive: true, force: true });
    }
  }
  assert.deepEqual(counts, { "--pathological": 12, "--legal-deep": 2, "--threshold": 23 });
});

test("parser 的语料口径：只吃 .c（.h/.in 不入 sources）且源指纹档 = presence", () => {
  assert.deepEqual(parserTarget.corpusExts, [".c"]);
  assert.equal(parserTarget.sourcesPolicy, "presence");
});

test("真实仓库：corpus 模式 PASS 487 + fork 1", () => {
  const r = run(["corpus/baseline"]);
  assert.equal(r.status, 0, r.stderr);
  const want = Object.keys(loadModesDigest(projectRoot(), "scripts/parser_diff/golden_digest.json", "", boom).modes["corpus-baseline"]?.resp_hashes ?? {}).length - 1;
  assert.match(r.stdout, new RegExp(`PASS——${want} 个 case hash 与冻结基线一致（语料 baseline，1 例 known-fork 跳过）`));
});

test("真实仓库：--pathological 12 / --legal-deep 2", () => {
  const p = run(["--pathological"]);
  assert.equal(p.status, 0, p.stderr);
  assert.match(p.stdout, /PASS——12 个 case hash/);

  const l = run(["--legal-deep"]);
  assert.equal(l.status, 0, l.stderr);
  assert.match(l.stdout, /PASS——2 个 case hash/);
});

test("真实仓库：--threshold 只比 A/B 族 7 条，C 族 16 条整体 fork", () => {
  const r = run(["--threshold"]);
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /PASS——7 个 case hash 与冻结基线一致（语料 threshold，16 例 known-fork 跳过）/);
  // C 族单列说明（裁定 b）
  assert.match(r.stdout, /FORK\(known-golden-skip\) shape_ptrarr_guard\.c/);
});

test("合成模式不接受语料位置参数（fail loud，退出码 2）", () => {
  const r = run(["--pathological", "corpus/baseline"]);
  assert.equal(r.status, 2);
  assert.match(r.stderr, /本模式不接受语料位置参数/);
});
