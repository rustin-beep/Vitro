#!/usr/bin/env node
// vm_diff —— D 级 diff 驱动（stdout + 返回码 + 1MB 最终映像）
//（#273 差分族重构批；原 scripts/vm_diff/main.go）。
//
// **整体接管型 target**（走 DiffTarget.override，不套骨架默认流程）：它有骨架
// 没有的六件事——三通道比对、known/skip 双清单（skip=不跑，fork=跑了不比）、
// 内存差异区间机判（顶部 4KB 栈窗口）、多 backend（native/wasm）、stdin 伴生注入、
// 无位置参数默认遍历五语料。骨架只提供工具（语料扫描 / sha / 输出协议）。
//
// **不迁（oracle 侧）**：runOracle / compare 的 oracle 分支 / freezeDigest
//（需 vivo_cli）。工序④删区后 oracle 永不存在，`--freeze` 必然 fail。
// **freshness 口径勘正（2026-11-01 审阅 v2 S05-C2；2026-11-14 批 3 连坐再勘）**：
// 本文件自 2026-10-23 起 native 臂已改**预编译 run.exe 直跑**（原「moon run
// 消除假绿死角」的论证随之失效——exe 直跑不自带构建检查）。CI 由 build-
// artifacts 每轮重建闭环；本地侧 S05-C2 曾以**软警告**（warnStaleExe 不判红）
// 兜陈旧——2026-11-14 实锤其不阻断形态漏拦（陈旧 run.exe 产出 DIFF=2 假红，
// 见 341 行段注），native 臂已升级 **ensureFresh 复核构建硬门禁**（mtime 只作
// 触发、内容 hash 由 moon 增量把关）；wasm 臂因 wasmopt 后置链维持软警告。
//
// 三通道（golden 模式 = mb 当前值 ≡ 清单登记值）：
//   1. stdout：剥引擎标记行后的纯程序输出（sha16）
//   2. 返回码：`// EXIT N`
//   3. 1MB 映像：argv 区（0xF000..0x10000）脱敏后 sha16
// known 分叉例在 golden 模式下与普通例同走三通道比对（known_diffs.json 登记
// 分叉归因并供 diff_ledger 对账；其 digest / memory_stack_only 为 oracle 时代
// 档案字段，无消费方）。曾声称的 known_mb_digest「整例指纹漂移即降级 DIFF」
// 机制从未启用（golden 全零条目、读侧死路径），2026-11-01 审阅 v2 S05-C5 删除。
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import crypto from "node:crypto";
import { spawnSync } from "node:child_process";
import { makeFail } from "../../internal/genio.mts";
import { ensureFresh } from "../../internal/freshness.mts";
import type { DiffTarget } from "../../internal/diffgate.mts";

export function fatal(msg: string): never {
  return makeFail("vm_diff: ", 1)(msg);
}

const DIGEST_REL = "scripts/vm_diff/golden_digest.json";
const SKIP_REL = "scripts/vm_diff/skip_list.json";
const KNOWN_REL = "scripts/vm_diff/known_diffs.json";
const WASM_SHELL = "moonbit/_build/js/release/build/cmd/vitro_wasm/vitro_wasm.js";
/** wasm 臂引擎产物：壳 js__load__gateway 的默认解析目标（VITRO_WASM_MOD 可覆盖）。 */
const WASM_ENGINE = "moonbit/_build/wasm-gc/release/build/gateway/wasm/wasm.wasm";
/** native 臂被测物：预编译 exe 直跑（Go 版同路径；CI 由 build artifact 保证存在）。 */
const RUN_EXE = "moonbit/_build/native/release/build/cmd/run/run.exe";
const DEFAULT_CORPORA = ["baseline", "knr", "leetcode", "gap", "llm_scale", "chibicc_port"]; // chibicc_port：#437 语料扩充窗口 2026-11-03 接线

/** argv 区脱敏窗（评审 P3 收窄：载荷实测 ~50B，4KB 余量 ~80×）。 */
const ARGV_MASK_LO = 0xf000;
const ARGV_MASK_HI = 0x10000;
// 内存差异区间机判（knownEntry.memory_stack_only + 顶部 4KB 栈窗口）**未迁**——
// 它在 Go 版的 compare() 里，只服务 oracle 双侧路径（随删区不可达）；golden 模式
// 的 known 例与普通例同走三通道比对，无特殊分支。

const MOON_RUN_TIMEOUT_MS = 120_000;
const MOON_RUN_ATTEMPTS = 3;

interface Case {
  rel: string;
  file: string;
}

interface DigestEntry {
  src_sha?: string;
  exit_code: number;
  stdout_sha: string;
  memory_sha?: string;
  compile_fail?: boolean;
}

interface DigestDoc {
  version: number;
  note: string;
  cases: Record<string, DigestEntry>;
}

interface SkipEntry {
  case: string;
  reason: string;
}
/** digest / memory_stack_only 为 oracle 时代档案字段（golden 模式无消费方，S05-C5）。 */
interface KnownEntry {
  case: string;
  digest: string;
  reason: string;
  memory_stack_only?: boolean;
}

interface RunResult {
  text: string;
  exitCode: number;
  memoryPath: string;
  compileFail: boolean;
}

function sha16(s: string | Buffer): string {
  return crypto.createHash("sha256").update(s).digest("hex").slice(0, 16);
}

/** 语料内相对名 → 清单键（"corpus/name.c"；外部路径取 basename）。 */
export function relOf(file: string, corpora: string[] = DEFAULT_CORPORA): string {
  const dir = path.basename(path.dirname(file));
  const base = path.basename(file);
  return corpora.includes(dir) ? `${dir}/${base}` : base;
}

/** stdin 伴生：同名 .in。 */
export function stdinFor(file: string): string {
  const p = file.replace(/\.c$/, ".in");
  return p !== file && fs.existsSync(p) ? p : "";
}

/**
 * CRLF 归一 + 首尾空行剥 + **不加尾换行**（join("\n")）。
 * 顺序照 Go：先剥尾部再剥首部。加了尾换行会让 printf 无换行的用例
 * 全错——清单里 `sha256("0")` 这种值即判据（2026-10-23 实测 gap 2 例）。
 */
function normalizeLines(lines: string[]): string {
  const kept = lines.map((l) => l.replace(/\r$/, ""));
  while (kept.length > 0 && kept[kept.length - 1] === "") kept.pop();
  while (kept.length > 0 && kept[0] === "") kept.shift();
  return kept.join("\n");
}

/**
 * 从 cmd/run 输出提取纯程序输出：按**精确前缀**剥引擎标记行（`// TRAP ` /
 * `// COMPILE-ERROR ` / `// FIX ` / `// COMPILE-WARNING ` / `// COMPILE-HINT ` /
 * `// NOTE ` / `// STDERR `），再剥末行 `// EXIT N`。
 * 不按 `// ` 前缀整行剥——程序 printf("// hi") 是合法输出。
 */
export function extractMoonBitStdout(s: string): string {
  const kept: string[] = [];
  for (const line of s.split("\n")) {
    const t = line.replace(/\r$/, "");
    const marks = [
      "// TRAP ",
      "// COMPILE-ERROR ",
      "// FIX ",
      "// COMPILE-WARNING ",
      "// COMPILE-HINT ",
      "// NOTE ",
      "// STDERR ",
    ];
    if (marks.some((m) => t.startsWith(m))) continue;
    kept.push(line);
  }
  // 先剥尾部空行再判末行：split("\n") 在尾换行后留空串，直接看末元素会漏剥 EXIT
  while (kept.length > 0 && (kept[kept.length - 1] ?? "").replace(/\r$/, "") === "") kept.pop();
  const n = kept.length;
  if (n > 0 && (kept[n - 1] ?? "").replace(/\r$/, "").startsWith("// EXIT ")) kept.pop();
  return normalizeLines(kept);
}

/**
 * Moon 侧两流合流（单源）——#394 审阅 P3-② 下沉 internal（2026-10-31）：
 * 实现与完整头注在 scripts/internal/moon_output.mts（原落本文件，被
 * clang_direct 跨驱动 import 的结构债）。此处 re-export 维持既有
 * import 面（本文件内部消费 + clang_direct/main.mts + vm.test.mts 锚）。
 */
export { mergeMoonOutput } from "../../internal/moon_output.mts";
import { mergeMoonOutput } from "../../internal/moon_output.mts";

/** 映像 sha16（argv 区脱敏后）。 */
export function memorySHA(p: string): string {
  let b: Buffer;
  try {
    b = fs.readFileSync(p);
  } catch {
    return "";
  }
  for (let i = ARGV_MASK_LO; i < ARGV_MASK_HI && i < b.length; i++) b[i] = 0;
  return sha16(b);
}

function digestOf(r: RunResult): { exit: number; stdout: string; mem: string; cf: boolean } {
  const stdout = extractMoonBitStdout(r.text);
  return {
    exit: r.exitCode,
    stdout: sha16(Buffer.from(stdout, "latin1")),
    mem: r.memoryPath === "" ? "" : memorySHA(r.memoryPath),
    cf: r.compileFail,
  };
}

export interface VmRunOpts {
  root: string;
  backend: "native" | "wasm";
  fail?: (msg: string) => never;
}

/** 跑单例被测物：native 走**预编译 run.exe 直跑**（Go 版同路径），wasm 走 node 壳。 */
export function runOne(file: string, opts: VmRunOpts): RunResult {
  const fail = opts.fail ?? fatal;
  const root = opts.root;
  const tmp = path.join(os.tmpdir(), `vmem_${process.pid}_${Date.now()}_${Math.random().toString(36).slice(2)}.bin`);
  const args = [file];
  // stdin 判断走绝对路径（CI 的 cwd 是 scripts/，相对路径会找不到）；
  // 但传给 exe 的 -i 值用**相对**路径——argv 内容会进映像，口径须与 Go 版一致。
  const inAbs = stdinFor(path.join(root, file));
  if (inAbs !== "") args.push("-i", path.relative(root, inAbs));
  args.push("--dump-memory", tmp);

  // native 用预编译 exe：**不用 moon run**——moon run 把子进程输出与自己的构建
  // 输出混在同一流里（构建警告 + 源码片段），任何过滤规则都会连带丢掉程序自己
  // 写到 stderr 的输出（2026-10-23 实测全量 8 例 DIFF，其中 7 例 stdout 提取成空串）。
  // exe 直跑的 stderr 只有程序输出 + `// ` 协议标记，与 Go 版口径逐字节一致，
  // 且单次 ~20ms（moon run ~125ms）。
  let cmd: string;
  let cmdArgs: string[];
  let cwd = root;
  if (opts.backend === "wasm") {
    cmd = "node";
    cmdArgs = [path.join(root, WASM_SHELL), "run", ...args];
  } else {
    // 相对路径：Go 版 exec.Command(filepath.FromSlash(runnerExe), path) 同口径——
    // argv 内容（含路径串）会残留在映像里，绝对 vs 相对会让 memory_sha 不同
    // （2026-10-23 实测 kr_5_10.c 单例 DIFF 即此）。
    cmd = RUN_EXE;
    cmdArgs = args;
    if (!fs.existsSync(cmd)) {
      fail(`${RUN_EXE} 不存在——先跑 cd moonbit && moon build --release --target native cmd/run`);
    }
  }

  for (let attempt = 1; ; attempt++) {
    const r = spawnSync(cmd, cmdArgs, {
      cwd,
      // latin1：每字节一字符，**不做 UTF-8 替换**——Go 的 []byte→string 零拷贝保留
      // 原始字节，stdout_sha 是对原始字节算的。utf8 解码会把 0xC8 这类高位字节变成
      // U+FFFD，编码回去是 3 字节，hash 必错（2026-10-23 实测 3 例 DIFF）。
      encoding: "latin1",
      timeout: MOON_RUN_TIMEOUT_MS,
      maxBuffer: 64 * 1024 * 1024,
    });

    const timedOut = r.error !== undefined && (r.error as NodeJS.ErrnoException).code === "ETIMEDOUT";
    if (timedOut) {
      if (attempt >= MOON_RUN_ATTEMPTS) {
        process.stderr.write(`vm_diff: Moon 侧运行超时（120s×${MOON_RUN_ATTEMPTS} 次）：${file}\n`);
        return { text: "// RUN-TIMEOUT", exitCode: 0, memoryPath: tmp, compileFail: false };
      }
      process.stderr.write(`vm_diff: Moon 侧超时，重试 ${attempt}/${MOON_RUN_ATTEMPTS - 1}：${file}\n`);
      continue;
    }

    // stdout + stderr 合并（#129 后标记行走 stderr）；wasm 臂的 backend 标注行剥除。
    // 走 exe 直跑时 stderr 只有协议标记与程序自身输出，**不再按前缀过滤**。
    const text = mergeMoonOutput(r.stdout ?? "", r.stderr ?? "");
    const compileFail = text.includes("// COMPILE-ERROR");
    let exitCode = 0;
    for (const line of text.trim().split("\n")) {
      if (line.startsWith("// EXIT ")) {
        const m = /^\/\/ EXIT (-?\d+)/.exec(line);
        if (m !== null) exitCode = Number(m[1]);
      }
    }
    return { text, exitCode, memoryPath: tmp, compileFail };
  }
}

function loadJSON<T>(root: string, rel: string, fail: (m: string) => never): T {
  const p = path.join(root, rel);
  try {
    return JSON.parse(fs.readFileSync(p, "utf8")) as T;
  } catch (e) {
    return fail(`读 ${rel} 失败: ${(e as Error).message}`);
  }
}

/** 均匀抽 N（覆盖字母序范围）。 */
export function sampleN(all: string[], n: number): string[] {
  const out: string[] = [];
  const step = all.length / n;
  for (let i = 0; i < n; i++) {
    const idx = Math.min(Math.trunc(i * step), all.length - 1);
    const v = all[idx];
    if (v !== undefined) out.push(v);
  }
  return out;
}

/** 主流程（override 入口）。返回退出码。 */
export function runVm(argv: string[], root: string): number {
  const fail = fatal;
  let corpora: string[] = DEFAULT_CORPORA;
  let sample = 0;
  let explicit: string[] = [];
  let backend: "native" | "wasm" = "native";
  let golden = false;
  let freezeMB = false;
  let selftest = false;
  let pruneStale = false;

  for (let i = 0; i < argv.length; i++) {
    const a = argv[i] ?? "";
    if (a === "--corpus" && i + 1 < argv.length) {
      corpora = [argv[++i] ?? ""];
    } else if (a === "--sample" && i + 1 < argv.length) {
      sample = Number.parseInt(argv[++i] ?? "0", 10) || 0;
    } else if (a === "--cases" && i + 1 < argv.length) {
      explicit = (argv[++i] ?? "").split(",");
    } else if (a === "--freeze") {
      fail("--freeze 已随工序④（Rust oracle 删区）退役——新用例入账用 --freeze-mb");
    } else if (a === "--freeze-mb") {
      freezeMB = true;
    } else if (a === "--refresh") {
      fail("--refresh 已删除——--freeze-mb 默认含存量重算，直接去掉本旗重跑");
    } else if (a === "--selftest") {
      selftest = true;
    } else if (a === "--backend" && i + 1 < argv.length) {
      const v = argv[++i];
      if (v !== "native" && v !== "wasm") fail(`--backend 取值 native|wasm，得到 ${JSON.stringify(v ?? "")}`);
      backend = v === "wasm" ? "wasm" : "native";
    } else if (a === "--golden") {
      golden = true;
    } else if (a === "--prune-stale") {
      pruneStale = true;
    } else {
      fail(`未知参数 ${JSON.stringify(a)}`);
    }
  }
  void golden;

  if (backend === "wasm") {
    if (!fs.existsSync(path.join(root, WASM_SHELL))) {
      fail(`${WASM_SHELL} 不存在（wasm 臂需 build 产物：moon build --release --target js cmd/vitro_wasm）`);
    }
    // 引擎产物存在性 fail loud（2026-11-01 审阅 v2 S05-C1）：原实现只查壳不查
    // 引擎 wasm——缺引擎时全部例呈「stdout 同一 hash=壳错误输出」的同文误导性
    // DIFF（方向红但形态谎报行为漂移）；与 native 臂的 run.exe 缺件检查对称。
    if ((process.env.VITRO_WASM_MOD ?? "") === "" && !fs.existsSync(path.join(root, WASM_ENGINE))) {
      fail(
        `${WASM_ENGINE} 不存在（wasm 臂引擎产物，壳默认加载它——先 moon build --release --target wasm-gc gateway/wasm && node scripts/wasmopt/main.mts <产物>；或 VITRO_WASM_MOD 显式指定）`,
      );
    }
  }
  process.stderr.write(
    "vm_diff: [裁判切换] oracle 面已随工序④退役——本判定固定走 --golden 冻结基线（结构裁判自 oracle 切为 digest 清单；正确性主锚仍为 Clang/shadow）\n",
  );
  // REHOST 批 3 连坐（2026-11-14）：native 臂新鲜度从 S05-C2 软警告升级为
  // ensureFresh **复核构建硬门禁**（freshness.mts 单源——clang_direct/
  // rundiff/step_invariant 等九处现役同源）。本会话实锤：release run.exe
  // 陈旧（exe 日期早于 #511 的 lexer 改动，依赖面源码变更不触发本地重建）
  // 混过软警告（打了不阻断）产出 DIFF=2 假红，三提交 worktree 归因才闭环。
  // 复核构建形态消化 S05-C2 的假阳性顾虑：checkout 刷源 mtime → 触发复核
  // → moon 增量按内容 hash 判 up-to-date 秒过（mtime 只作触发不作证据）；
  // 真陈旧 → 自动重建 → 假红根除。wasm 臂维持软警告：其产物链含 wasmopt
  // 后置覆盖（CI build-artifacts 步骤序 build→wasmopt→-check），自动重建
  // 会以裸产物覆盖优化产物——升级待 freshness 支持构建后置钩子另批。
  if (backend === "native") {
    ensureFresh("vm_diff", path.join(root, RUN_EXE), [
      "build",
      "--release",
      "--target",
      "native",
      "cmd/run",
    ]);
  } else {
    warnStaleExe(root, backend);
  }

  const skips = loadJSON<SkipEntry[]>(root, SKIP_REL, fail);
  const known = loadJSON<KnownEntry[]>(root, KNOWN_REL, fail);

  // ---- 用例收集 ----
  const cases: Case[] = [];
  if (explicit.length > 0) {
    for (const f of explicit) {
      let file = f;
      if (!path.isAbsolute(f) && !f.includes("/") && !f.includes("\\")) {
        let found = false;
        for (const c of corpora) {
          const p = path.join(root, "corpus", c, f);
          if (fs.existsSync(p)) {
            file = p;
            found = true;
            break;
          }
        }
        if (!found) fail(`--cases 路径不存在: ${f}（相对仓库根，如 corpus/baseline/x.c）`);
      }
      cases.push({ rel: relOf(file, corpora), file: path.relative(root, file) });
    }
  } else {
    for (const c of corpora) {
      const dir = path.join(root, "corpus", c);
      if (!fs.existsSync(dir)) fail(`读语料目录失败 ${dir}`);
      let names = fs
        .readdirSync(dir)
        .filter((n) => n.endsWith(".c"))
        .sort();
      if (sample > 0 && names.length > sample) names = sampleN(names, sample);
      for (const n of names) cases.push({ rel: `${c}/${n}`, file: path.relative(root, path.join(dir, n)) });
    }
  }
  if (cases.length === 0) fail("无用例");

  // 全量模式 = 未 --cases 且未 --sample 且语料集为默认五套
  const full =
    explicit.length === 0 &&
    sample === 0 &&
    corpora.length === DEFAULT_CORPORA.length &&
    corpora.every((c, i) => c === DEFAULT_CORPORA[i]);

  // 静态白名单防腐化：条目名不在本轮用例集合即红（仅全量模式）
  if (full) {
    const names = new Set(cases.map((c) => path.basename(c.rel)));
    for (const e of skips) if (!names.has(e.case)) fail(`skip 白名单空转条目 ${e.case}——语料中不存在（删除或修正）`);
    for (const e of known) if (!names.has(e.case)) fail(`known 白名单空转条目 ${e.case}——语料中不存在（删除或修正）`);
  }

  const doc = loadJSON<DigestDoc>(root, DIGEST_REL, fail);
  if (doc.version !== 1) fail("清单坏或版本不识");

  // ---- golden 僵死条目防腐化（PR #416 审阅 P2-3，2026-11-02）----
  // vm 只遍历语料：清单中语料已不存在的键永不校验，而汇总「共 N」令人误以为全
  // 覆盖（实锤：#387 GPL 出仓 45 份删语料未连坐清单 ⇒ 807 条中 46 条僵死，全在
  // baseline）。skip/known 有静态防腐化而 golden 没有——补 cases ⊆ 语料集（全量
  // 模式）；清理走 --prune-stale（纯减法：只删语料不存在的键，不动任何存活 hash，
  // 与「重冻」语义严格区分）。
  if (pruneStale) {
    if (!full) return fail("--prune-stale 须在全量模式跑（默认五语料，不带 --corpus/--sample/--cases）——非全量会把本轮外语料全判僵死");
    const live = new Set(cases.map((c) => c.rel));
    const stale = Object.keys(doc.cases).filter((k) => !live.has(k));
    if (stale.length === 0) return fail("--prune-stale: 零僵死条目——清单已与语料对齐，无需清理");
    for (const k of stale) delete doc.cases[k];
    writeDigest(root, doc, fail);
    process.stdout.write(
      `vm_diff --prune-stale: 删除 ${stale.length} 条语料已不存在的僵死条目 → ${DIGEST_REL}（纯减法；存活 ${Object.keys(doc.cases).length} 条 hash 零改动）\n${stale.map((k) => "  - " + k).join("\n")}\n`,
    );
    return 0;
  }
  if (full) {
    const live = new Set(cases.map((c) => c.rel));
    const stale = Object.keys(doc.cases).filter((k) => !live.has(k));
    if (stale.length > 0) {
      return fail(
        `golden 僵死条目 ${stale.length} 条（语料已删而清单未连坐，永不校验）——跑 node scripts/diff_gate/main.mts vm --prune-stale 清理；首 5 条：${stale.slice(0, 5).join(", ")}`,
      );
    }
  }

  // ---- --freeze-mb：mb 侧三通道入账 ----
  if (freezeMB) {
    let added = 0;
    let refreshed = 0;
    let skipped = 0;
    const prev = new Set(Object.keys(doc.cases));
    for (const c of cases) {
      const base = path.basename(c.rel);
      if (skips.some((e) => e.case === base)) {
        process.stdout.write(`SKIP  ${c.rel}（skip 清单——不入账）\n`);
        continue;
      }
      const r = runOne(c.file, { root, backend, fail });
      const d = digestOf(r);
      doc.cases[c.rel] = {
        src_sha: srcSHAOf(path.join(root, c.file)),
        exit_code: d.exit,
        stdout_sha: d.stdout,
        memory_sha: d.mem,
        compile_fail: d.cf,
      };
      fs.rmSync(r.memoryPath, { force: true });
      if (prev.has(c.rel)) {
        process.stdout.write(`REFRESH ${c.rel}（exit=${d.exit} stdout=${d.stdout} mem=${d.mem} cf=${String(d.cf)}）\n`);
        refreshed++;
      } else {
        process.stdout.write(`ADD ${c.rel}（exit=${d.exit} stdout=${d.stdout} mem=${d.mem} cf=${String(d.cf)}）\n`);
        added++;
      }
      skipped++;
    }
    if (added === 0 && refreshed === 0) fail(`--freeze-mb: 无新例可入账（${Math.max(0, skipped - added - refreshed)} 例均已在清单）`);
    writeDigest(root, doc, fail);
    process.stdout.write(
      `\nvm_diff --freeze-mb: 新增 ${added} 例 / 重算 ${refreshed} 例 → ${DIGEST_REL}（正确性背书 = clang_direct + moon test；映像为白箱回归锚）\n`,
    );
    return 0;
  }

  // ---- golden 比对 ----
  if (selftest && cases.length > 0) {
    // 篡改目标 = 首个非 compile_fail 例（2026-11-01 审阅 v2 S05-A1 修复）：
    // 原实现篡改 cases[0]——gap 语料首例 complex_number.c 是 cf 例，比对循环的
    // 「双侧编译失败——等价」短路先于任何通道字段，篡改被吞、exit 0 假绿（探针
    // 实锤：打印「已篡改」后 SAME=21 全绿）。cf 例不参与三通道字段比对。
    const t = cases.find((c) => doc.cases[c.rel]?.compile_fail !== true);
    // return fail(...)：fail 是属性调用，TS 不认 never，需显式 return 收窄（同上文口径）
    if (t === undefined) {
      return fail("--selftest: 本轮用例全部为 compile_fail 例——篡改面为空（换语料或 --cases 指定非 cf 例）");
    }
    const e = doc.cases[t.rel];
    if (e !== undefined) {
      e.stdout_sha = "deadbeef12345678";
      process.stdout.write(`[selftest][golden] 已篡改清单条目: ${t.rel} ——随后比对必须 FAIL\n`);
    }
  }

  let same = 0;
  let diff = 0;
  let skipN = 0;
  for (const c of cases) {
    const base = path.basename(c.rel);
    const skipReason = skips.find((e) => e.case === base);
    if (skipReason !== undefined) {
      process.stdout.write(`SKIP  ${c.rel}（${skipReason.reason}）\n`);
      skipN++;
      continue;
    }
    const e = doc.cases[c.rel];
    // return fail(...)：fail 是属性调用，TS 不认 never，需显式 return 收窄
    if (e === undefined) return fail(`清单缺例 ${c.rel}——重跑 --freeze-mb`);

    const r = runOne(c.file, { root, backend, fail });
    const d = digestOf(r);
    fs.rmSync(r.memoryPath, { force: true });

    if (d.cf && e.compile_fail === true) {
      process.stdout.write(`SAME  ${c.rel}（双侧编译失败——等价）\n`);
      same++;
      continue;
    }
    if (d.exit === e.exit_code && d.stdout === e.stdout_sha && d.mem === (e.memory_sha ?? "") && d.cf === (e.compile_fail === true)) {
      process.stdout.write(`SAME  ${c.rel}\n`);
      same++;
      continue;
    }
    process.stdout.write(
      `DIFF  ${c.rel}：与冻结基线不符（exit ${d.exit}≠${e.exit_code} / stdout ${d.stdout}≠${e.stdout_sha} / memory ${d.mem}≠${e.memory_sha ?? ""}）——全文对照见 frozen-oracle-snapshot 分支\n`,
    );
    diff++;
  }
  process.stdout.write(
    `\nvm_diff[golden]: SAME=${same} DIFF=${diff} SKIP=${skipN}（共 ${same + diff + skipN}）\n`,
  );

  // **不迁动态白名单防腐化**：Go 版那段（跑完全量后检查 known.hit / skip.hit）
  // 位于 `os.Exit(runAgainstDigest(cases))` 之后，只在 oracle 双侧对拍路径执行——
  // 该路径随工序④删区永不可达。2026-10-23 实测：Go 版全量 733 例 exit 0 且不报
  // 任何「空转」，而早期 TS 版在 golden 末尾做了同样检查，多报 4 个 known 条目。
  // 静态防腐化（跑之前查条目名是否在语料内）在 golden 路径**保留**——Go 版那段
  // 在 freeze/golden 分支之前。
  return diff > 0 ? 1 : 0;
}

/**
 * 本地 freshness 软警告（S05-C2，2026-11-01 审阅 v2；2026-11-14 批 3 连坐
 * 后 **wasm 臂专用**——native 臂已升 ensureFresh 复核构建硬门禁，见 341 行
 * 段注）：exe 直跑不自带构建检查——moonbit/ 全树（排除 _build）最新 .mbt
 * mtime 新于被测产物时提示「测的可能是旧产物」。不判红：mtime 是提示不是
 * 证据（checkout 会刷源码 mtime）；CI 由 build-artifacts 每轮重建闭环，
 * 不触此警告。
 */
function warnStaleExe(root: string, backend: "native" | "wasm"): void {
  const rel = backend === "native" ? RUN_EXE : WASM_ENGINE;
  let prodM: number;
  try {
    prodM = fs.statSync(path.join(root, rel)).mtimeMs;
  } catch {
    return; // 缺件由各自的存在性检查 fail loud
  }
  let newest = 0;
  const walk = (d: string): void => {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      // _build = 构建产物；tools = 工具缓存（binaryen 等，gitignored）——均非源码
      if (e.name === "_build" || e.name === "tools") continue;
      const p = path.join(d, e.name);
      if (e.isDirectory()) walk(p);
      // *_gen.mbt = @generated 产物（新鲜度由各自 -check 闸保证，生成器重跑只
      // 刷 mtime 不改语义）；*_wbtest.mbt = 白盒测试文件（只进 moon test 构建，
      // 不进 release 产物）——均非被测产物的输入，不计入（两者均实测误报过）
      else if (e.name.endsWith(".mbt") && !e.name.endsWith("_gen.mbt") && !e.name.endsWith("_wbtest.mbt")) {
        newest = Math.max(newest, fs.statSync(p).mtimeMs);
      }
    }
  };
  try {
    walk(path.join(root, "moonbit"));
  } catch {
    return;
  }
  if (newest > prodM) {
    process.stderr.write(
      `vm_diff: ⚠ moonbit/ 源码新于 ${rel}（本地 freshness 软警告——测的可能是旧产物；重建：cd moonbit && MOON_CC=clang moon build --release --target native cmd/run / wasm-gc gateway/wasm 等）\n`,
    );
  }
}

function srcSHAOf(file: string): string {
  const h = crypto.createHash("sha256");
  for (const p of [file, stdinFor(file)]) {
    if (p === "") continue;
    h.update(fs.readFileSync(p));
  }
  return h.digest("hex").slice(0, 8);
}

function writeDigest(root: string, doc: DigestDoc, fail: (m: string) => never): void {
  const p = path.join(root, DIGEST_REL);
  try {
    // Go MarshalIndent：struct 字段序（version → note → cases）+ map 键字节序
    const caseKeys = Object.keys(doc.cases).sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
    const q = (s: string): string => JSON.stringify(s);
    const entryBody = (e: DigestEntry): string => {
      const parts: string[] = [];
      if (e.src_sha !== undefined) parts.push(`      "src_sha": ${q(e.src_sha)}`);
      parts.push(`      "exit_code": ${e.exit_code}`);
      parts.push(`      "stdout_sha": ${q(e.stdout_sha)}`);
      if (e.memory_sha !== undefined && e.memory_sha !== "") parts.push(`      "memory_sha": ${q(e.memory_sha)}`);
      if (e.compile_fail === true) parts.push(`      "compile_fail": true`);
      return "{\n" + parts.join(",\n") + "\n    }";
    };
    const casesBody =
      caseKeys.length === 0
        ? "{}"
        : "{\n" + caseKeys.map((k) => `    ${q(k)}: ${entryBody(doc.cases[k] ?? { exit_code: 0, stdout_sha: "" })}`).join(",\n") + "\n  }";
    const out = `{\n  "version": ${doc.version},\n  "note": ${q(doc.note)},\n  "cases": ${casesBody}\n}\n`;
    fs.writeFileSync(p, out, { mode: 0o644 });
  } catch (e) {
    fail(`写清单失败: ${(e as Error).message}`);
  }
}

export const vmTarget: DiffTarget = {
  name: "vm_diff",
  fail: fatal,
  override: (argv: string[], root: string) => runVm(argv, root),
};
