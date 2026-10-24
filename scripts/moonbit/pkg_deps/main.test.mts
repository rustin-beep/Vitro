// pkg_deps.test.mts —— 依赖解析 / 分层匹配 / 环检测 / 判据红路（fixture）+ 真实三模式
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { findCycle, longestPrefixLevel, loadRules, parseDeps, scan, verdict } from "./main.mts";
import type { PkgInfo, RulesDoc } from "./main.mts";
import { projectRoot } from "../../internal/capi.mts";

const MAIN = path.join(import.meta.dirname, "main.mts");

function tmp(files: Record<string, string>): string {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-pd-"));
  for (const [rel, body] of Object.entries(files)) {
    fs.mkdirSync(path.dirname(path.join(root, rel)), { recursive: true });
    fs.writeFileSync(path.join(root, rel), body);
  }
  return root;
}

function rules(over: Partial<RulesDoc> = {}): RulesDoc {
  return { schema: 1, root: "root", module: "vitro/engine", levels: {}, exempt_prefixes: [], ...over };
}

test("parseDeps：只留同 module 前缀 / 去 self / 去重 / 排序", () => {
  const root = tmp({
    "root/a/moon.pkg": [
      'import { "vitro/engine/b", "moonbitlang/core/json", "vitro/engine/c", "vitro/engine/a", "vitro/engine/b" }',
      'for "test" { import { "vitro/engine/d" } }',
      "",
    ].join("\n"),
  });
  const deps = parseDeps(path.join(root, "root/a/moon.pkg"), "vitro/engine", "a");
  assert.deepEqual(deps, ["b", "c", "d"]);
});

test("longestPrefixLevel：子包继承父包层号，未匹配返回 -1", () => {
  const levels = { lexer: 1, "lexer/internal": 2 };
  assert.deepEqual(longestPrefixLevel("lexer/internal/pp", levels), { key: "lexer/internal", level: 2 });
  assert.deepEqual(longestPrefixLevel("lexer", levels), { key: "lexer", level: 1 });
  assert.deepEqual(longestPrefixLevel("unknown", levels), { key: "", level: -1 });
});

test("verdict：越层 / 未登记 / 空集 三路红（手工构图，不依赖 scan 的 cwd）", () => {
  const rd = rules({ levels: { low: 1, high: 5 } });
  const mk = (name: string, deps: string[], level: number, key: string): PkgInfo => ({ name, deps, level, levelKey: key, exempt: false });
  // low(L1) → high(L5)：向上越层
  const up = new Map([["low", mk("low", ["high"], 1, "low")], ["high", mk("high", [], 5, "high")]]);
  assert.equal(verdict(rd, up, ["high", "low"]), false);
  // 同一条边但层号反过来（向下）：绿
  const down = new Map([["low", mk("low", ["high"], 5, "low")], ["high", mk("high", [], 1, "high")]]);
  assert.equal(verdict(rd, down, ["high", "low"]), true);
  // high 未登记层号
  const unreg = new Map([["low", mk("low", ["high"], 5, "low")], ["high", mk("high", [], -1, "")]]);
  assert.equal(verdict(rd, unreg, ["high", "low"]), false);
  // 零依赖 → 空集不得绿
  const noDeps = new Map([["low", mk("low", [], 5, "low")], ["high", mk("high", [], 1, "high")]]);
  assert.equal(verdict(rd, noDeps, ["high", "low"]), false);
});

test("findCycle：造 A→B→A 必须报环；无环返回空", () => {
  const pkg = (name: string, deps: string[]): PkgInfo => ({ name, deps, level: 1, levelKey: name, exempt: false });
  const cyc = new Map([["a", pkg("a", ["b"])], ["b", pkg("b", ["a"])]]);
  assert.deepEqual(findCycle(cyc, ["a", "b"]), ["a", "b", "a"]);
  const dag = new Map([["a", pkg("a", ["b"])], ["b", pkg("b", [])]]);
  assert.deepEqual(findCycle(dag, ["a", "b"]), []);
});

test("真实仓库端到端：默认 / -check / --selftest 全绿；未知参数 exit 2", () => {
  const root = projectRoot();
  const rd = loadRules();
  const { pkgs, order } = scan(rd);
  assert.ok(pkgs.size > 10);
  assert.equal(verdict(rd, pkgs, order), true, "真实包图应满足三判据");
  for (const args of [[], ["-check"], ["--selftest"]]) {
    const r = spawnSync(process.execPath, [MAIN, ...args], { cwd: root, encoding: "utf8" });
    assert.equal(r.status, 0, `${args.join(" ") || "(默认)"}: ${r.stdout}${r.stderr}`);
  }
  assert.equal(spawnSync(process.execPath, [MAIN, "--nope"], { cwd: root, encoding: "utf8" }).status, 2);
});
