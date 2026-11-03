// coverage_snapshot.test.mts —— 解析/聚合/闭合校验/趋势/基线序列化（fixture）+ 真实基线与首采对账
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import {
  BASELINE_PATH,
  aggregateByPackage,
  judgeMeasurementDomain,
  packageOf,
  parseBaseline,
  parseFullSummary,
  pct,
  renderTrend,
  serializeBaseline,
  trend,
} from "./main.mts";
import type { Baseline } from "./main.mts";
import { projectRoot } from "../internal/capi.mts";

const MAIN = path.join(import.meta.dirname, "main.mts");

const SAMPLE = [
  "fs\\fs.mbt: 11/11",
  "vm\\trap.mbt: 168/266",
  "lexer\\internal\\pp\\x.mbt: 3/9",
  "lexer\\internal\\pp\\y.mbt: 7/15",
  "Total: 189/301",
].join("\n");

test("parseFullSummary：反斜杠归一 / Total 闭合 / 非数据行忽略", () => {
  const snap = parseFullSummary(SAMPLE + "\n(一些进度输出)\n");
  assert.deepEqual([...snap.files.keys()].sort(), ["fs/fs.mbt", "lexer/internal/pp/x.mbt", "lexer/internal/pp/y.mbt", "vm/trap.mbt"]);
  assert.deepEqual(snap.total, { covered: 189, total: 301 });
  // 口径陷阱①（R5g §1.6）：用错 summary（缺 100% 文件）→ 之和不闭合，必须 throw
  const broken = SAMPLE.replace("fs\\fs.mbt: 11/11\n", "");
  assert.throws(() => parseFullSummary(broken), /不闭合/);
  assert.throws(() => parseFullSummary("没有 Total 行"), /无 Total/);
});

test("aggregateByPackage：目录聚合 + 字节序键 + packageOf", () => {
  assert.equal(packageOf("fs/fs.mbt"), "fs");
  assert.equal(packageOf("solo.mbt"), "(root)");
  const pkgs = aggregateByPackage(parseFullSummary(SAMPLE));
  assert.deepEqual(Object.keys(pkgs), ["fs", "lexer/internal/pp", "vm"]);
  assert.deepEqual(pkgs["lexer/internal/pp"], { covered: 10, total: 24 });
});

test("serializeBaseline → parseBaseline 往返 + 键序确定性（两次序列化逐字节相等）", () => {
  const b: Baseline = {
    schema: 1,
    as_of: "2026-11-02",
    commit: "5233ad65",
    total: { covered: 189, total: 301 },
    packages: { vm: { covered: 168, total: 266 }, fs: { covered: 11, total: 11 }, ast: { covered: 100, total: 120 } },
    missing_packages: { prefix: ["cmd"], exact: { gateway: "r" } },
  };
  const s1 = serializeBaseline(b);
  const s2 = serializeBaseline(parseBaseline(s1));
  assert.equal(s1, s2, "往返后序列化逐字节相等（基线 diff 即评审物）");
  assert.ok(s1.indexOf('"fs"') < s1.indexOf('"vm"'), "包键按字节序");
  assert.ok(s1.endsWith("\n"), "末行换行");
  assert.throws(() => parseBaseline('{"schema":2}'), /schema/);
  // P3-1：旧基线（无 missing_packages 段）→ fail loud（前向不兼容即环境破坏，禁静默 default）
  const oldNoWl = JSON.parse(JSON.stringify(b));
  delete (oldNoWl as Partial<Baseline>).missing_packages;
  assert.throws(() => parseBaseline(JSON.stringify(oldNoWl)), /missing_packages/);
});

test("trend + renderTrend：变动/新增/消失/持平四形态与 Δ 算术", () => {
  const base: Baseline = {
    schema: 1,
    as_of: "2026-11-01",
    commit: "aaaa1111",
    total: { covered: 100, total: 200 },
    packages: { a: { covered: 50, total: 100 }, gone: { covered: 10, total: 20 } },
    missing_packages: { prefix: [], exact: {} },
  };
  const now = { a: { covered: 70, total: 110 }, fresh: { covered: 5, total: 10 } };
  const t = trend(base, now, { covered: 130, total: 220 });
  assert.deepEqual(t.total, { pkg: "TOTAL", base: { covered: 100, total: 200 }, now: { covered: 130, total: 220 }, dCovered: 30, dPct: (100 * 130) / 220 - 50 });
  const byPkg = new Map(t.rows.map((r) => [r.pkg, r]));
  assert.equal(byPkg.get("a")!.dCovered, 20);
  assert.equal(byPkg.get("fresh")!.dCovered, null);
  assert.equal(byPkg.get("gone")!.dCovered, null);
  const md = renderTrend(base, t, "bbbb2222");
  assert.match(md, /\+30 行/);
  assert.match(md, /\*\*新增包\*\*/);
  assert.match(md, /\*\*包消失\*\*/);
  assert.match(md, /不判红/);
});

test("P2-1（PR #452 审阅）：分母增、分子不变的覆盖下降必须进「变动」组，不得错归持平", () => {
  // 审阅探针形态：50/100 → 50/110（新增 10 行零覆盖，-4.5pt）——dCovered=0 的下降形态
  const base: Baseline = { schema: 1, as_of: "d", commit: "a", total: { covered: 50, total: 100 }, packages: { p: { covered: 50, total: 100 } }, missing_packages: { prefix: [], exact: {} } };
  const t = trend(base, { p: { covered: 50, total: 110 } }, { covered: 50, total: 110 });
  const md = renderTrend(base, t, "b");
  assert.match(md.split("\n").find((l) => l.startsWith("| p "))!, /-4\.5 pt/);
  assert.match(md, /变动 1 包 \/ 持平 0 包/, "纯分母变化的下降形态必须计入变动组（原 dCovered 单判把它错归持平并沉底）");
});

test("P3-1（PR #452 审阅）：judgeMeasurementDomain 三路——白名单外缺席红 / 僵尸条目红 / 恰等绿", () => {
  const wl = { prefix: ["cmd"], exact: { gateway: "r" } };
  const disk = ["cmd/vitro", "gateway", "ast", "vm"];
  // 绿：磁盘 − 产物 = {cmd/vitro, gateway} 恰等白名单展开
  assert.deepEqual(judgeMeasurementDomain(disk, ["ast", "vm"], wl), []);
  // 红：新包零测量未登记（vm 缺席且不在白名单）
  assert.equal(judgeMeasurementDomain(disk, ["ast"], wl).filter((f) => f.kind === "unregistered-missing" && f.detail.startsWith("vm")).length, 1);
  // 红：白名单具名已进产物（条目失效）
  assert.equal(judgeMeasurementDomain(disk, ["ast", "vm", "gateway"], wl).filter((f) => f.kind === "zombie-whitelist" && f.detail.includes("已进产物")).length, 1);
  // 红：白名单具名磁盘不存在（僵尸）
  const wl2 = { prefix: [], exact: { gone_pkg: "r" } };
  assert.equal(judgeMeasurementDomain(["ast"], ["ast"], wl2).filter((f) => f.kind === "zombie-whitelist" && f.detail.includes("不存在")).length, 1);
});

test("真实基线在场且首采数字对账（R5g 互证锚）", () => {
  const b = parseBaseline(fs.readFileSync(path.join(projectRoot(), BASELINE_PATH), "utf8"));
  // **重锚连坐义务（PR #452 审阅 P3-7）**：`--update-baseline` 重锚后本 test 的
  // commit/covered/total/codegen 四个数字锚必须同步改——重锚 = 改两处（基线 + 本锚），是刻意的评审闸非冗余
  assert.equal(b.commit, "5233ad65", "首采基点 = A8 批基（origin/master 5233ad65）");
  assert.equal(b.total.covered, 18480, "首采 covered（--run 链亲采，worktree 5233ad65）");
  assert.equal(b.total.total, 30648, "首采 total");
  assert.match(pct(b.total), /^60\.3%$/);
  assert.ok(Object.keys(b.packages).length >= 25, "逐包面完整（29 包口径）");
  // codegen 19.0% 与 R5g 报告 §1.3 小数点后一位互证（审阅 v2 已知最大薄区，B 轮修复标的地）
  assert.deepEqual(b.packages["codegen"], { covered: 824, total: 4326 });
  // 测量域白名单（P3-1）：cmd 前缀 + 三具名，恰等 46−29=17 差集
  assert.deepEqual(b.missing_packages.prefix, ["cmd"]);
  assert.deepEqual([...Object.keys(b.missing_packages.exact)].sort(), ["gateway", "gateway/wasm", "teaching/langpack"]);
});

test("--from 端到端：fixture 趋势产出 + rc=0（vs 真实基线，全部「包消失/新增」形态亦不判红）；未知参数 exit 2", () => {
  const root = projectRoot();
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vitro-covsnap-"));
  const fx = path.join(dir, "full_summary.txt");
  fs.writeFileSync(fx, SAMPLE + "\n");
  const out = path.join(dir, "out");
  const r = spawnSync(process.execPath, [MAIN, "--from", fx, "--out", out], { cwd: root, encoding: "utf8" });
  assert.equal(r.status, 0, `${r.stdout}${r.stderr}`);
  assert.match(r.stdout, /189\/301/);
  assert.match(r.stdout, /不判红/);
  assert.ok(fs.existsSync(path.join(out, "trend.md")));
  assert.ok(fs.existsSync(path.join(out, "per_package.json")));
  assert.equal(spawnSync(process.execPath, [MAIN, "--nope"], { cwd: root, encoding: "utf8" }).status, 2);
  // 闭合校验红路走进程：用错 summary 口径的文本 → rc=2 fail loud
  const bad = path.join(dir, "bad.txt");
  fs.writeFileSync(bad, "a\\b.mbt: 1/2\nTotal: 5/9\n");
  const rb = spawnSync(process.execPath, [MAIN, "--from", bad, "--out", out], { cwd: root, encoding: "utf8" });
  assert.equal(rb.status, 2);
  assert.match(rb.stderr, /不闭合/);
});
