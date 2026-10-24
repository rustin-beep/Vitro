// perf_budget.test.mts —— 注释剥离 / 分档 / 阈值红路 + 真实三模式
import { test } from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { collectFiles, loadRules, scan, stripComments, tierOf, validateDirTiers } from "./main.mts";
import type { Counter } from "./main.mts";
import { projectRoot } from "../internal/capi.mts";

const MAIN = path.join(import.meta.dirname, "main.mts");

test("stripComments：块注释与行注释都换成空格（保留代码与字符串）", () => {
  assert.equal(stripComments("a /* x */ b // y\nc").replace(/\s+/g, " ").trim(), "a b c");
  assert.equal(stripComments('s = "http://x"\n').includes("http"), true);
});

test("tierOf：首个前缀命中；无命中落顶层档", () => {
  const c: Counter = {
    id: "c", pattern: "x", max_per_file: 9,
    dir_tiers: [{ dirs: ["big"], max_per_file: 100 }, { dirs: ["huge"], max_per_file: 999 }],
  };
  assert.deepEqual(tierOf(c, "corpus/big/a.c"), { tier: c.dir_tiers[0], label: "big" });
  assert.equal(tierOf(c, "corpus/other/a.c").label, "");
  assert.equal(tierOf(c, "corpus/other/a.c").tier.max_per_file, 9);
});

test("真实规则：语料非空 / 档位目录存在 / scan 产出每档一条 finding", () => {
  const root = projectRoot();
  const rd = loadRules(root);
  validateDirTiers(rd); // 档位目录写错会 fatal，这里能走到下一行即通过
  const files = collectFiles(root, rd);
  assert.ok(files.length > 0);
  const { findings, files: n } = scan(root, rd);
  assert.equal(n, files.length);
  assert.ok(findings.length >= rd.metrics.length);
  for (const f of findings) assert.equal(f.exceed, f.maxCount > f.limit, f.counter);
  assert.deepEqual(findings.filter((f) => f.exceed).map((f) => f.counter), [], "真实预算下不应超阈");
});

test("J9：把某 counter 预算压到 0 → 该档必判超阈（内存注入，不写盘）", () => {
  const root = projectRoot();
  const rd = loadRules(root);
  const inj = { ...rd, metrics: rd.metrics.map((m) => ({ ...m, counters: m.counters.map((c) => ({ ...c, max_per_file: 0 })) })) };
  const { findings } = scan(root, inj);
  assert.ok(findings.some((f) => f.exceed), "预算压 0 后必须有 finding 超阈，否则闸门失效");
});

test("真实仓库端到端：默认 / -check / --selftest 全绿；未知参数 exit 2", () => {
  const root = projectRoot();
  for (const args of [[], ["-check"], ["--selftest"]]) {
    const r = spawnSync(process.execPath, [MAIN, ...args], { cwd: root, encoding: "utf8" });
    assert.equal(r.status, 0, `${args.join(" ") || "(默认)"}: ${r.stdout}${r.stderr}`);
  }
  assert.equal(spawnSync(process.execPath, [MAIN, "--nope"], { cwd: root, encoding: "utf8" }).status, 2);
});
