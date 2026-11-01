// ci_checklist.test.mts —— 四向对账红路（临时仓库 fixture）+ 真实仓库端到端
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { check } from "./main.mts";
import { projectRoot } from "../internal/capi.mts";

const MAIN = path.join(import.meta.dirname, "main.mts");

interface Fixture {
  root: string;
  edit(rel: string, s: string): void;
}

/** 最小仓库：1 个已接线驱动 + 四目标 moon test + 空例外表 = 绿。 */
function makeFixture(extra: (f: Fixture) => void = () => {}): Fixture {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-cc-"));
  const w = (rel: string, s: string): void => {
    fs.mkdirSync(path.dirname(path.join(root, rel)), { recursive: true });
    fs.writeFileSync(path.join(root, rel), s);
  };
  w(".github/workflows/ci.yml", [
    "steps:",
    "  - run: go run ./scripts/alpha",
    "  - run: |",
    "      moon test --target js",
    "      moon test --target native",
    "      moon test",
    "      moon test --target wasm-gc",
    "",
  ].join("\n"));
  w("scripts/alpha/main.go", "package main\n\nfunc main() {}\n");
  w("scripts/ci_checklist/exceptions.json", "[]");
  const f: Fixture = { root, edit: (rel, s) => w(rel, s) };
  extra(f);
  return f;
}

test("绿：一驱动 + 四目标齐 + 空例外表", () => {
  const f = makeFixture();
  const r = check(f.root);
  assert.equal(r.failed, false, r.lines.join("\n"));
  assert.match(r.summary, /驱动 1（\.go 1 \/ \.mts 0）/);
  assert.match(r.summary, /moon test 目标面（4 目标齐）/);
});

test("J9 ①漏登记：新驱动无活行 → 红", () => {
  const f = makeFixture((x) => {
    fs.mkdirSync(path.join(x.root, "scripts/beta"), { recursive: true });
    fs.writeFileSync(path.join(x.root, "scripts/beta/main.go"), "package main\n");
  });
  const r = check(f.root);
  assert.equal(r.failed, true);
  assert.match(r.lines.join("\n"), /漏登记: scripts\/beta（scripts 下存在 main 驱动，ci.yml 零活行/);
});

test("J9 ②悬空：活行引用不存在的驱动 → 红", () => {
  const f = makeFixture((x) => {
    x.edit(".github/workflows/ci.yml", "steps:/n  - run: go run ./scripts/ghost\n  - run: moon test --target js\n  - run: moon test --target native\n  - run: moon test\n  - run: moon test --target wasm-gc\n");
  });
  const r = check(f.root);
  assert.equal(r.failed, true);
  assert.match(r.lines.join("\n"), /悬空: workflow 活行 go run \.\/scripts\/ghost 但该驱动不存在/);
});

test("J9 ②悬空（node 形态，S13b-P1/R1e-R2 2026-11-01）：node 活行文件不存在 → 红", () => {
  // 修复前形态：node 活行目录被 force-add 进驱动集，悬空检查恒 found——
  // 全部现役 node 活行上②结构性空转（ghost 探针：go 形态红、node 形态零报告）。
  const f = makeFixture((x) => {
    x.edit(
      ".github/workflows/ci.yml",
      "steps:/n  - run: node scripts/ghost_mts/main.mts --probe\n  - run: moon test --target js\n  - run: moon test --target native\n  - run: moon test\n  - run: moon test --target wasm-gc\n",
    );
  });
  const r = check(f.root);
  assert.equal(r.failed, true, "node 形态悬空必须红（修复前 force-add 形态恒绿——本锚即其 J9 证据）");
  assert.match(r.lines.join("\n"), /悬空: workflow 活行 node scripts\/ghost_mts\/main\.mts 但该文件不存在/);
});

test("J9 ②悬空（node 形态·绿路径）：文件存在的散件活行不红（非 main.mts 亦合法）", () => {
  const f = makeFixture((x) => {
    fs.mkdirSync(path.join(x.root, "scripts/util_probe"), { recursive: true });
    fs.writeFileSync(path.join(x.root, "scripts/util_probe/run.mts"), "#!/usr/bin/env node\n");
    // 在既有 ci.yml（go run alpha 活行 + 四目标块形态 moon test）上追加 node 散件活行
    const ci = fs.readFileSync(path.join(x.root, ".github/workflows/ci.yml"), "utf8");
    fs.writeFileSync(path.join(x.root, ".github/workflows/ci.yml"), ci + "  - run: node scripts/util_probe/run.mts\n");
  });
  const r = check(f.root);
  assert.equal(r.failed, false, r.lines.join("\n"));
});

test("J9 ③幽灵例外（S13b-P2 2026-11-01）：例外指向不存在的驱动 → 红", () => {
  // 修复前形态：③只查僵尸向（被活行引用），纯虚构条目 rc=0 通过——例外表
  // 只增不减零验活（五条 superseded-by-mts 幽灵即此形态存活）。
  const f = makeFixture((x) => {
    x.edit(
      "scripts/ci_checklist/exceptions.json",
      JSON.stringify([{ driver: "scripts/totally_ghost_never_existed", reason: "r" }]),
    );
  });
  const r = check(f.root);
  assert.equal(r.failed, true);
  assert.match(r.lines.join("\n"), /幽灵例外: scripts\/totally_ghost_never_existed 既非驱动也无活行且磁盘上不存在/);
});

test("J9 ③僵尸例外：例外驱动同时被引用 → 红", () => {
  const f = makeFixture((x) => {
    x.edit("scripts/ci_checklist/exceptions.json", JSON.stringify([{ driver: "scripts/alpha", reason: "r" }]));
  });
  const r = check(f.root);
  assert.equal(r.failed, true);
  assert.match(r.lines.join("\n"), /僵尸例外: scripts\/alpha 已被 ci.yml 活行引用/);
});

test("J9 例外缺 reason → 直接判红（exit 1 语义）", () => {
  const f = makeFixture((x) => {
    x.edit("scripts/ci_checklist/exceptions.json", JSON.stringify([{ driver: "scripts/x" }]));
  });
  const r = spawnSync(process.execPath, [MAIN, "-repo", f.root], { encoding: "utf8" });
  assert.equal(r.status, 1);
  assert.match(r.stderr, /例外表|缺 reason/);
});

test("J9 ④目标面缺口：缺 --target wasm-gc → 红", () => {
  const f = makeFixture((x) => {
    x.edit(".github/workflows/ci.yml", "steps:/n  - run: go run ./scripts/alpha\n  - run: moon test --target js\n  - run: moon test --target native\n");
  });
  const r = check(f.root);
  assert.equal(r.failed, true);
  assert.match(r.lines.join("\n"), /目标面缺口: .*缺 --target wasm-gc/);
});

test("main.mts 也算驱动（shebang 判据）；.test.mts 不算", () => {
  const f = makeFixture((x) => {
    fs.mkdirSync(path.join(x.root, "scripts/gamma"), { recursive: true });
    fs.writeFileSync(path.join(x.root, "scripts/gamma/main.mts"), "#!/usr/bin/env node\nconsole.log(1);\n");
    fs.writeFileSync(path.join(x.root, "scripts/gamma/main.test.mts"), "#!/usr/bin/env node\n");
  });
  const r = check(f.root);
  assert.match(r.lines.join("\n"), /漏登记: scripts\/gamma/);
  assert.match(r.summary, /\.mts 1/, "有 shebang 的 main.mts 计入 mtsDrivers（与 Go 版同口径）");
});

test("真实仓库端到端：默认绿 + 未知参数 exit 2", () => {
  const root = projectRoot();
  const def = spawnSync(process.execPath, [MAIN], { cwd: root, encoding: "utf8" });
  assert.equal(def.status, 0, def.stdout + def.stderr);
  assert.match(def.stdout, /ci_checklist: PASS——驱动 \d+（\.go \d+ \/ \.mts \d+）\/ 活行 \d+ \/ 例外 \d+ 三向对账/);
  const bad = spawnSync(process.execPath, [MAIN, "--nope"], { cwd: root, encoding: "utf8" });
  assert.equal(bad.status, 2);
});
