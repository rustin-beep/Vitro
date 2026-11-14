#!/usr/bin/env node
// ci_checklist —— 「存在即接入」注册表闸（Go→.mts 重写，refs #273；原 #71 防线续批 2026-10-11）。
//
// 单一真源 = 文件系统：scripts/** 下每个含 `package main` 的 .go 文件即一个
// 可 go run 的判定型驱动；对账目标 = 全部 workflow 里 `go run ./scripts/...`
// 与 `node scripts/...mts` 活行。**双向红**：
//   ① 漏登记：驱动存在但零活行引用（例外表可豁免，reason 必填）；
//   ② 悬空：活行引用的驱动不存在（go run 按驱动集判、node 按文件存在性判
//      ——形态分流见活行集段注释，2026-11-01 审阅 v2 S13b-P1/R1e-R2 修复）；
//   ③ 僵尸例外：例外驱动同时被活行引用；幽灵例外：例外驱动不在
//      驱动集∪活行集∪磁盘 三者之并（死条目即红，S13b-P2）；
//   ④ moon test 目标面：全部 `moon test` 活行的 --target 并集必须覆盖四目标
//      {js, native, wasm, wasm-gc}（后端集加员连坐测试面，AGENTS §14）。
//
// 用法：node scripts/ci_checklist/main.mts [-repo <仓库根>]
// 退出码：0 对账一致 / 1 任一向红 / 2 环境错。
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../internal/capi.mts";

export interface Exception {
  driver: string;
  reason: string;
  kind?: string;
}

// .stryker-tmp = Stryker sandbox（mutation gate 把 scripts/ 整树复制进去再跑测试）
// ——不剪枝则 sandbox 内的驱动副本全被当「漏登记」，本闸的真实仓库端到端测试在
// Stryker initial run 里必红 ⇒ mutation gate 对本文件任何改动恒 FATAL（PR #416
// CI 实锤 + 本地复现：sandbox-*/backend_triage 等数十条漏登记）。
const PRUNE = new Set(["_build", "__pycache__", "node_modules", "bin", ".stryker-tmp"]);

const MOON_TARGETS = ["js", "native", "wasm", "wasm-gc"];

const LIVE_RE = /go run (\.\/)?scripts\/[a-zA-Z0-9_/${}.-]+/g;
const NODE_RE = /node (\.\/)?scripts\/[a-zA-Z0-9_/${}.-]+\.mts/g;
const PKG_MAIN_RE = /^package main\b/m;
const MOON_TEST_RE = /^\s*moon test\b[^\n]*/gm;
const TARGET_RE = /--target (\S+)/g;

function toSlash(p: string): string {
  return p.split(path.sep).join("/");
}

function die(msg: string, code = 2): never {
  process.stderr.write(msg + "\n");
  process.exit(code);
}

export interface CheckInput {
  repo: string;
}

/** 全量对账（返回 { failed, lines }，由 main 决定打印与退出码）。 */
export function check(repo: string): { failed: boolean; lines: string[]; summary: string } {
  const ciPath = path.join(repo, ".github", "workflows", "ci.yml");
  let ciBytes: string;
  try {
    ciBytes = fs.readFileSync(ciPath, "utf8");
  } catch (e) {
    die(`ci_checklist: 读 ci.yml 失败: ${e instanceof Error ? e.message : String(e)}`);
  }
  const wfBytes = new Map<string, string>([["ci.yml", ciBytes]]);
  const wfRoot = path.join(repo, ".github", "workflows");
  try {
    for (const name of fs.readdirSync(wfRoot)) {
      if (!name.endsWith(".yml") || wfBytes.has(name)) continue;
      try {
        wfBytes.set(name, fs.readFileSync(path.join(wfRoot, name), "utf8"));
      } catch {
        // 与 Go 同：单个 workflow 读失败不阻断
      }
    }
  } catch {
    // workflows 目录缺失不阻断（CI 里必有）
  }

  // ── 驱动集：scripts/** 含 package main 的 .go + main.mts（文件名即驱动）──
  const driverSet = new Set<string>();
  const drivers: string[] = [];
  const mtsDrivers: string[] = [];
  const scriptsRoot = path.join(repo, "scripts");
  const walk = (dir: string): void => {
    for (const ent of fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : 1))) {
      const p = path.join(dir, ent.name);
      if (ent.isDirectory()) {
        if (PRUNE.has(ent.name)) continue;
        walk(p);
        continue;
      }
      if (ent.name.endsWith("_test.go")) continue;
      // 第二扫描面：main.mts 文件名即驱动（2026-11-14 #512 彻查修复：原判据
      // 额外要求 shebang 首行——无 shebang 的 main.mts 静默逃逸驱动集，「存在
      // 即接入」对账对它们零检出力〔前科：gen_course S08-6 补个案未根治判据；
      // wasmenc_emitgate/wasmenc_rundiff #505/#512 重蹈——REHOST 批 3 连坐根治〕
      // ——shebang 只是可执行直跑标记，非驱动身份判据。排除 .test.mts。）
      if (ent.name.endsWith("main.mts") && !ent.name.endsWith(".test.mts")) {
        const rel = toSlash(path.relative(repo, path.dirname(p)));
        if (!driverSet.has(rel)) {
          driverSet.add(rel);
          drivers.push(rel);
          mtsDrivers.push(rel);
        }
        continue;
      }
      let body: string;
      try {
        body = fs.readFileSync(p, "utf8");
      } catch {
        continue;
      }
      if (PKG_MAIN_RE.test(body)) {
        const rel = toSlash(path.relative(repo, path.dirname(p)));
        if (!driverSet.has(rel)) {
          driverSet.add(rel);
          drivers.push(rel);
        }
      }
    }
  };
  try {
    walk(scriptsRoot);
  } catch (e) {
    die(`ci_checklist: 扫描 scripts 失败: ${e instanceof Error ? e.message : String(e)}`);
  }

  // ── 活行集 ──
  // ② 悬空判据按形态分流（2026-11-01 审阅 v2 S13b-P1/R1e-R2 修复）：原实现对
  // node 活行 force-add 其目录进驱动集——被检引用自己就在 drivers 里，悬空检查
  // 恒 found，全部现役 node 活行上防线结构性空转（ghost 探针实锤：go run 形态
  // 红、同不存在程度的 node 形态零报告）。现改为：
  //   go run 活行 → 驱动集判据（package main 目录形态，历史行为保留）；
  //   node  活行 → 文件存在性判据（引用的 .mts 在磁盘上不存在即红，含非
  //                main.mts 散件）；目录仍进 liveSet 供 ①③ 判据豁免。
  // 含 ${{ 的动态形态静态不可判，跳过（现役零活行——go run 已随 #273 迁移批
  // 2026-10-25 清零；原 MATRIX_DRIVERS 静态展开表因缺 realcode_corpus 漂移且
  // 无消费面，随之删除——复活 matrix 形态时须先补静态展开来源）。
  const liveSet = new Set<string>();
  const liveNodeFiles: string[] = [];
  const liveGoDirs: string[] = [];
  for (const wb of wfBytes.values()) {
    for (const m of wb.matchAll(LIVE_RE)) {
      let p = (m[0] ?? "").replace(/^go run /, "").replace(/^\.\//, "");
      if (p.includes("${{")) continue;
      if (p.endsWith(".go")) {
        p = p.slice(0, p.lastIndexOf("/"));
      }
      liveSet.add(p);
      liveGoDirs.push(p);
    }
    for (const m of wb.matchAll(NODE_RE)) {
      const p = (m[0] ?? "").replace(/^node /, "").replace(/^\.\//, "");
      const dir = toSlash(path.dirname(p));
      liveSet.add(dir);
      liveNodeFiles.push(p);
    }
  }

  // ── 例外表 ──
  const exPath = path.join(scriptsRoot, "ci_checklist", "exceptions.json");
  let exBytes: string;
  try {
    exBytes = fs.readFileSync(exPath, "utf8");
  } catch (e) {
    die(`ci_checklist: 读例外表失败: ${e instanceof Error ? e.message : String(e)}`);
  }
  let exceptions: Exception[];
  try {
    exceptions = JSON.parse(exBytes) as Exception[];
  } catch {
    die("ci_checklist: 例外表 JSON 坏");
  }
  const exSet = new Set<string>();
  for (const e of exceptions) {
    if (!e.reason) die(`ci_checklist: 例外 ${e.driver} 缺 reason（例外必须自证）`, 1);
    exSet.add(e.driver);
  }

  const lines: string[] = [];
  let failed = false;

  // ① 漏登记（例外豁免）
  for (const d of drivers) {
    if (liveSet.has(d) || exSet.has(d)) continue;
    lines.push(`漏登记: ${d}（scripts 下存在 main 驱动，ci.yml 零活行——要么接线要么进例外表自证）`);
    failed = true;
  }
  // ② 悬空（排序输出：Go 侧 map 序随机，此处收紧可复现性）——形态分流见活行集段
  for (const p of [...liveGoDirs].sort()) {
    const found = drivers.some((d) => d === p || d.startsWith(p + "/"));
    if (!found) {
      lines.push(`悬空: workflow 活行 go run ./${p} 但该驱动不存在`);
      failed = true;
    }
  }
  for (const p of [...liveNodeFiles].sort()) {
    if (!fs.existsSync(path.join(repo, p))) {
      lines.push(`悬空: workflow 活行 node ${p} 但该文件不存在`);
      failed = true;
    }
  }
  // ③ 僵尸例外（被活行引用）+ 幽灵例外（S13b-P2 2026-11-01：原检查只查僵尸向，
  // 对「例外指向的驱动已不存在」的死条目零检出——superseded-by-mts 五条的 Go
  // 驱动已删而例外残留即此形态，纯虚构条目探针 rc=0 通过。幽灵判据 = 不在
  // 驱动集∪活行集∪磁盘 三者之并）
  for (const e of exceptions) {
    if (liveSet.has(e.driver)) {
      lines.push(`僵尸例外: ${e.driver} 已被 ci.yml 活行引用，例外条目应删`);
      failed = true;
    } else if (!driverSet.has(e.driver) && !fs.existsSync(path.join(repo, e.driver))) {
      lines.push(`幽灵例外: ${e.driver} 既非驱动也无活行且磁盘上不存在——死条目（删除或修正）`);
      failed = true;
    }
  }
  // ④ moon test 目标面
  const targetUnion = new Set<string>();
  for (const line of ciBytes.match(MOON_TEST_RE) ?? []) {
    if (line.includes("--target ")) {
      for (const m of line.matchAll(TARGET_RE)) targetUnion.add(m[1] ?? "");
    } else {
      targetUnion.add("wasm"); // 裸 moon test 默认目标 = wasm
    }
  }
  for (const want of MOON_TARGETS) {
    if (!targetUnion.has(want)) {
      lines.push(
        `目标面缺口: ci.yml 全部 moon test 活行的目标并集缺 --target ${want}（后端集加员须连坐测试面——AGENTS §14 三臂强制）`,
      );
      failed = true;
    }
  }

  // ⑤ ci-summary 三面对账（2026-11-14 PR #513 审阅 P1-1：第三次同形复发后机判化——
  // 「闸的闸面漏登记」形态：新 gate job 自己的 check 会红，但汇总判据看不见它，
  // 红或被 skip 时 ci-summary 仍判绿 ⇒ 防遮蔽机制对新闸失效。前科：10-30
  // backend-triage、10-31 release-preflight（ci.yml ci-summary 段注记）、
  // 11-14 green_probe。判据三面：
  //   A. gate job 集 ⊆ needs（漏登记即红）；
  //   B. env 的 needs.<job>.result 集 == needs 集（三面互证——2026-10-30
  //      「needs 11 而循环 10」失衡形态）；
  //   C. pairs 条数 == needs 数。
  // 豁免面：schedule-only job（if: github.event_name == 'schedule'——PR/push
  // 面不触发，needs 它们会恒 skipped 假红）自动免；mutation-gate 观察期
  // 显式豁免（ci.yml ci-summary 段注记），复活时摘除。
  const SUMMARY_EXEMPT = new Map<string, string>([
    ["mutation-gate", "观察期不入 needs（ci.yml ci-summary 段注记 2026-10-31）"],
  ]);
  const summaryResult = checkCiSummary(ciBytes, SUMMARY_EXEMPT);
  if (summaryResult !== null) {
    lines.push(summaryResult);
    failed = true;
  }

  const summary = `ci_checklist: PASS——驱动 ${drivers.length}（.go ${drivers.length - mtsDrivers.length} / .mts ${mtsDrivers.length}）/ 活行 ${liveSet.size} / 例外 ${exceptions.length} 三向对账 + moon test 目标面（${targetUnion.size} 目标齐）+ ci-summary 三面一致`;
  return { failed, lines, summary };
}

/** ⑤ 单独成函数供单测：返回 null = 一致；非 null = 红描述（可能多行拼一串）。 */
export function checkCiSummary(
  ciBytes: string,
  exempt: ReadonlyMap<string, string>,
): string | null {
  // job 集：两空格缩进的 `id:` 行——只从 `^jobs:` 之后扫（`on:` 触发器块
  // 同为两空格键形态，push/pull_request 等会被误判成 job）
  const jobsAnchor = ciBytes.search(/^jobs:/m);
  if (jobsAnchor < 0) return null; // 无 jobs 段的最小 fixture：本判据不适用
  const jobArea = ciBytes.slice(jobsAnchor);
  const jobRe = /^  ([a-z0-9][a-z0-9_-]*):$/gm;
  const jobs = new Map<string, string>(); // id → 段文本（供 schedule 检测）
  for (const m of jobArea.matchAll(jobRe)) {
    const id = m[1] as string;
    const start = (m.index ?? 0) + m[0].length;
    const next = jobArea.slice(start).search(/^  [a-z0-9][a-z0-9_-]*:$/m);
    jobs.set(id, next < 0 ? jobArea.slice(start) : jobArea.slice(start, start + next));
  }
  const summaryBody = jobs.get("ci-summary");
  if (summaryBody === undefined) return null; // 无 ci-summary 的最小 fixture：本判据不适用
  // schedule-only 自动豁免 + 显式豁免表
  const gateJobs: string[] = [];
  for (const [id, body] of jobs) {
    if (id === "ci-summary") continue;
    if (/if:\s*github\.event_name\s*==\s*'schedule'/.test(body)) continue;
    if (exempt.has(id)) continue;
    gateJobs.push(id);
  }
  // A. needs
  const needsM = summaryBody.match(/needs:\s*\[([^\]]*)\]/);
  if (needsM === null) return "ci-summary 三面: needs 行缺失或非数组形态";
  const needsSet = new Set(
    (needsM[1] ?? "")
      .split(",")
      .map((s) => s.trim())
      .filter((s) => s !== ""),
  );
  const missing = gateJobs.filter((j) => !needsSet.has(j));
  // B. env 面
  const envSet = new Set<string>();
  for (const m of summaryBody.matchAll(/\$\{\{\s*needs\.([a-z0-9_-]+)\.result\s*\}\}/g)) {
    envSet.add(m[1] as string);
  }
  // C. pairs 面（"name:$VAR" 形态计数）
  const pairsCount = [...summaryBody.matchAll(/"[a-z0-9_-]+:\$\{?[A-Z_0-9]+\}?"/g)].length;
  const bad: string[] = [];
  if (missing.length > 0) {
    bad.push(`漏 needs: ${missing.join(", ")}（gate job 未入 ci-summary needs——红/被 skip 时汇总仍绿，防遮蔽失效）`);
  }
  const envOnly = [...envSet].filter((j) => !needsSet.has(j));
  if (envOnly.length > 0) bad.push(`env 多出: ${envOnly.join(", ")}`);
  const needsOnly = [...needsSet].filter((j) => !envSet.has(j));
  if (needsOnly.length > 0) bad.push(`env 缺失: ${needsOnly.join(", ")}（needs 有而 env 无——三面失衡）`);
  if (pairsCount !== needsSet.size) {
    bad.push(`pairs ${pairsCount} != needs ${needsSet.size}（循环面与 needs 失衡——2026-10-30 同形）`);
  }
  return bad.length > 0 ? `ci-summary 三面: ${bad.join("；")}` : null;
}

export function main(argv: string[]): number {
  let repo = "";
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i] ?? "";
    if (a === "-repo" || a === "--repo") {
      const v = argv[++i];
      if (v === undefined) {
        process.stderr.write("ci_checklist: -repo 缺值\n");
        return 2;
      }
      repo = v;
    } else {
      process.stderr.write(`ci_checklist: 未知参数 ${JSON.stringify(a)}\n`);
      return 2;
    }
  }
  const root = repo === "" ? projectRoot() : path.resolve(repo);
  const { failed, lines, summary } = check(root);
  for (const l of lines) process.stdout.write(l + "\n");
  if (failed) {
    process.stdout.write("ci_checklist: FAIL——存在即接入对账不符\n");
    return 1;
  }
  process.stdout.write(summary + "\n");
  return 0;
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  process.exit(main(process.argv.slice(2)));
}
