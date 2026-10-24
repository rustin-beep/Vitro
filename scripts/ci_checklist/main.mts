#!/usr/bin/env node
// ci_checklist —— 「存在即接入」注册表闸（Go→.mts 重写，refs #273；原 #71 防线续批 2026-10-11）。
//
// 单一真源 = 文件系统：scripts/** 下每个含 `package main` 的 .go 文件即一个
// 可 go run 的判定型驱动；对账目标 = 全部 workflow 里 `go run ./scripts/...`
// 与 `node scripts/...mts` 活行。**双向红**：
//   ① 漏登记：驱动存在但零活行引用（例外表可豁免，reason 必填）；
//   ② 悬空：活行引用的驱动不存在；
//   ③ 僵尸例外：例外驱动同时被活行引用；
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

const PRUNE = new Set(["_build", "__pycache__", "node_modules", "bin"]);

/** matrix 模板行（gates-diff）：driver 枚举在 matrix.include 段，静态展开。 */
const MATRIX_DRIVERS = ["parser_diff", "lexer_diff", "typeck_diff", "codegen_diff", "vm_diff", "clang_direct"];
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

  // ── 驱动集：scripts/** 含 package main 的 .go + 带 shebang 的 main.mts ──
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
      // 第二扫描面：main.mts + node shebang（排除 .test.mts 与被 import 的库）
      if (ent.name.endsWith("main.mts") && !ent.name.endsWith(".test.mts")) {
        let body: string;
        try {
          body = fs.readFileSync(p, "utf8");
        } catch {
          continue;
        }
        if (body.startsWith("#!/usr/bin/env node")) {
          const rel = toSlash(path.relative(repo, path.dirname(p)));
          if (!driverSet.has(rel)) {
            driverSet.add(rel);
            drivers.push(rel);
            mtsDrivers.push(rel);
          }
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
  const liveSet = new Set<string>();
  for (const wb of wfBytes.values()) {
    for (const m of wb.matchAll(LIVE_RE)) {
      let p = (m[0] ?? "").replace(/^go run /, "").replace(/^\.\//, "");
      if (p.includes("${{")) {
        for (const d of MATRIX_DRIVERS) {
          if (wb.includes("- driver: " + d)) liveSet.add("scripts/" + d);
        }
        continue;
      }
      if (p.endsWith(".go")) {
        p = p.slice(0, p.lastIndexOf("/"));
      }
      liveSet.add(p);
    }
    for (const m of wb.matchAll(NODE_RE)) {
      const p = (m[0] ?? "").replace(/^node /, "").replace(/^\.\//, "");
      const dir = toSlash(path.dirname(p));
      liveSet.add(dir);
      if (!driverSet.has(dir)) {
        driverSet.add(dir);
        drivers.push(dir);
        mtsDrivers.push(dir);
      }
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
  // ② 悬空（排序输出：Go 侧 map 序随机，此处收紧可复现性）
  for (const p of [...liveSet].sort()) {
    const found = drivers.some((d) => d === p || d.startsWith(p + "/"));
    if (!found) {
      lines.push(`悬空: workflow 活行 ./${p} 但该驱动不存在`);
      failed = true;
    }
  }
  // ③ 僵尸例外
  for (const e of exceptions) {
    if (liveSet.has(e.driver)) {
      lines.push(`僵尸例外: ${e.driver} 已被 ci.yml 活行引用，例外条目应删`);
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

  const summary = `ci_checklist: PASS——驱动 ${drivers.length}（.go ${drivers.length - mtsDrivers.length} / .mts ${mtsDrivers.length}）/ 活行 ${liveSet.size} / 例外 ${exceptions.length} 三向对账 + moon test 目标面（${targetUnion.size} 目标齐）一致`;
  return { failed, lines, summary };
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
