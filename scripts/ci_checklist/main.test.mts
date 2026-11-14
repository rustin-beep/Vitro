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
    x.edit(".github/workflows/ci.yml", "steps:\n  - run: go run ./scripts/ghost\n  - run: moon test --target js\n  - run: moon test --target native\n  - run: moon test\n  - run: moon test --target wasm-gc\n");
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
      "steps:\n  - run: node scripts/ghost_mts/main.mts --probe\n  - run: moon test --target js\n  - run: moon test --target native\n  - run: moon test\n  - run: moon test --target wasm-gc\n",
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
    x.edit(".github/workflows/ci.yml", "steps:\n  - run: go run ./scripts/alpha\n  - run: moon test --target js\n  - run: moon test --target native\n");
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

test("Stryker sandbox（scripts/.stryker-tmp）不进扫描面（PR #416 mutation gate FATAL 治本）", () => {
  // mutation gate 把 scripts/ 整树复制进 .stryker-tmp/sandbox-*/ 再跑本闸的端到端
  // 测试——不剪枝则副本驱动全判「漏登记」，Stryker initial run 必红 ⇒ 本文件任何
  // 改动都让 mutation gate 基础设施红（2026-11-02 PR #416 CI 实锤 + 本地复现）。
  const f = makeFixture((x) => {
    fs.mkdirSync(path.join(x.root, "scripts/.stryker-tmp/sandbox-abc/ghost"), { recursive: true });
    fs.writeFileSync(path.join(x.root, "scripts/.stryker-tmp/sandbox-abc/ghost/main.mts"), "#!/usr/bin/env node\n");
  });
  const r = check(f.root);
  assert.equal(r.failed, false, r.lines.join("\n"));
  assert.match(r.summary, /驱动 1（\.go 1 \/ \.mts 0）/, "sandbox 副本不得计入驱动集");
});

test("真实仓库端到端：默认绿 + 未知参数 exit 2", () => {
  const root = projectRoot();
  const def = spawnSync(process.execPath, [MAIN], { cwd: root, encoding: "utf8" });
  assert.equal(def.status, 0, def.stdout + def.stderr);
  assert.match(def.stdout, /ci_checklist: PASS——驱动 \d+（\.go \d+ \/ \.mts \d+）\/ 活行 \d+ \/ 例外 \d+ 三向对账/);
  const bad = spawnSync(process.execPath, [MAIN, "--nope"], { cwd: root, encoding: "utf8" });
  assert.equal(bad.status, 2);
});

// ── ⑤ ci-summary 三面对账（2026-11-14 PR #513 审阅 P1-1：第三次同形复发后机判化）──
import { checkCiSummary } from "./main.mts";

function summaryCi(needs: string, envJobs: string[], pairs: string[]): string {
  const env = envJobs.map((j) => `          ${j.toUpperCase().replace(/-/g, "_")}: \${{ needs.${j}.result }}`).join("\n");
  const pairLines = pairs.map((p) => `            "${p}:$${p.toUpperCase().replace(/-/g, "_")}"`).join(" ");
  return [
    "on: {push: {branches: [master]}}",
    "jobs:",
    "  build-artifacts:",
    "    runs-on: ubuntu-latest",
    "  gate-a:",
    "    runs-on: ubuntu-latest",
    "  nightly-x:",
    "    runs-on: ubuntu-latest",
    "    if: github.event_name == 'schedule'",
    "  ci-summary:",
    "    needs: [" + needs + "]",
    "    runs-on: ubuntu-latest",
    "    steps:",
    "      - run: |",
    env,
    "          pairs=(" + pairLines + ")",
  ].join("\n");
}

const EXEMPT = new Map<string, string>([["mutation-gate", "观察期"]]);

test("⑤ 绿：gate job 全入 needs/env/pairs + schedule-only 自动豁免", () => {
  const ci = summaryCi("build-artifacts, gate-a", ["build-artifacts", "gate-a"], ["build", "gatea"]);
  assert.equal(checkCiSummary(ci, EXEMPT), null);
});

test("⑤ J9 漏 needs：gate job 未入 ci-summary → 红（PR #513 green_probe 同形）", () => {
  const ci = summaryCi("build-artifacts", ["build-artifacts", "gate-a"], ["build", "gatea"]);
  const r = checkCiSummary(ci, EXEMPT);
  assert.match(r as string, /漏 needs: gate-a/);
});

test("⑤ J9 env 失衡：needs 有而 env 无 → 红", () => {
  const ci = summaryCi("build-artifacts, gate-a", ["build-artifacts"], ["build", "gatea"]);
  const r = checkCiSummary(ci, EXEMPT);
  assert.match(r as string, /env 缺失: gate-a/);
});

test("⑤ J9 pairs 失衡：循环数 != needs 数 → 红（2026-10-30 同形）", () => {
  const ci = summaryCi("build-artifacts, gate-a", ["build-artifacts", "gate-a"], ["build"]);
  const r = checkCiSummary(ci, EXEMPT);
  assert.match(r as string, /pairs 1 != needs 2/);
});

test("⑤ 显式豁免表：mutation-gate 不入 needs 不红（观察期注记）", () => {
  const ci = [
    "on: {push: {branches: [master]}}",
    "jobs:",
    "  mutation-gate:",
    "    runs-on: ubuntu-latest",
    "  ci-summary:",
    "    needs: []",
    "    runs-on: ubuntu-latest",
  ].join("\n");
  assert.equal(checkCiSummary(ci, EXEMPT), null);
});

test("J9 ①漏登记（.mts 无 shebang 形态，2026-11-14 #512 彻查）：main.mts 文件名即驱动——shebang 缺失不得逃逸驱动集", () => {
  // 前科：gen_course（S08-6 2026-11-01 补 shebang 个案）/wasmenc_emitgate
  // /wasmenc_rundiff（#505/#512）无 shebang 落库，三向对账对它们零检出力
  // （活行碰巧在场故未爆——防线盲而非行为缺口）。判据修复 = 文件名即驱动
  //（shebang 只是可执行直跑标记，非驱动身份判据）。修复前形态：无 shebang
  // 的 main.mts 不进驱动集，本锚「漏登记红」断言 failed=false 即证红。
  const f = makeFixture((x) => {
    fs.mkdirSync(path.join(x.root, "scripts/noshebang"), { recursive: true });
    fs.writeFileSync(path.join(x.root, "scripts/noshebang/main.mts"), "// 判定驱动但无 shebang 头\n");
  });
  const r = check(f.root);
  assert.equal(r.failed, true);
  assert.match(r.lines.join("\n"), /漏登记: scripts\/noshebang/);
});

test("无 shebang main.mts + 活行在场 → 不误伤（文件名即驱动的正向面）", () => {
  const f = makeFixture((x) => {
    fs.mkdirSync(path.join(x.root, "scripts/noshebang2"), { recursive: true });
    fs.writeFileSync(path.join(x.root, "scripts/noshebang2/main.mts"), "// 判定驱动但无 shebang 头\n");
    x.edit(".github/workflows/ci.yml", "steps:\n  - run: go run ./scripts/alpha\n  - run: node scripts/noshebang2/main.mts\n  - run: |\n      moon test --target js\n      moon test --target native\n      moon test\n      moon test --target wasm-gc\n");
  });
  const r = check(f.root);
  assert.equal(r.failed, false, r.lines.join("\n"));
  assert.match(r.summary, /\.mts 1/);
});
