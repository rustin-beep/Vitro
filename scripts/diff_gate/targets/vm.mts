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
//（需 vivo_cli）/ 新鲜度门禁。工序④删区后 oracle 永不存在，`--freeze` 必然
// fail；而**新鲜度门禁的动机随 moon run 消失**——实测 node spawnSync 下
// moon run 稳定（8+5 次全 0，`--dump-memory` 产精确 1MB，`-i` 注入有效，
// 单次 ~125ms），moon run 自带构建检查，「构建失败照跑旧 exe 报假绿」的死角
// 不存在。wasm 臂仍消费 build 产物（CI 由 build job 保证），故只查存在性。
//
// 三通道（golden 模式 = mb 当前值 ≡ 清单登记值）：
//   1. stdout：剥引擎标记行后的纯程序输出（sha16）
//   2. 返回码：`// EXIT N`
//   3. 1MB 映像：argv 区（0xF000..0x10000）脱敏后 sha16
// known 分叉例额外登记 mb 侧整例指纹（known_mb_digest），漂移即降级 DIFF。
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import crypto from "node:crypto";
import { spawnSync } from "node:child_process";
import { makeFail } from "../../internal/genio.mts";
import type { DiffTarget } from "../../internal/diffgate.mts";

export function fatal(msg: string): never {
  return makeFail("vm_diff: ", 1)(msg);
}

const DIGEST_REL = "scripts/vm_diff/golden_digest.json";
const SKIP_REL = "scripts/vm_diff/skip_list.json";
const KNOWN_REL = "scripts/vm_diff/known_diffs.json";
const WASM_SHELL = "moonbit/_build/js/release/build/cmd/vitro_wasm/vitro_wasm.js";
/** native 臂被测物：预编译 exe 直跑（Go 版同路径；CI 由 build artifact 保证存在）。 */
const RUN_EXE = "moonbit/_build/native/release/build/cmd/run/run.exe";
const DEFAULT_CORPORA = ["baseline", "knr", "leetcode", "gap", "llm_scale"];

/** argv 区脱敏窗（评审 P3 收窄：载荷实测 ~50B，4KB 余量 ~80×）。 */
const ARGV_MASK_LO = 0xf000;
const ARGV_MASK_HI = 0x10000;
// 内存差异区间机判（knownEntry.memory_stack_only + 顶部 4KB 栈窗口）**未迁**——
// 它在 Go 版的 compare() 里，只服务 oracle 双侧路径（随删区不可达）；golden 模式
// 的 known 例走 known_mb_digest 整体指纹，不涉及区间判定。

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
  known_mb_digest?: string;
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

/** known 分叉例的整例指纹（exit + stdout + mem + cf）。 */
export function mbWholeDigest(exit: number, stdoutSHA: string, memSHA: string, cf: boolean): string {
  return sha16(`${exit}|${stdoutSHA}|${memSHA}|${String(cf)}`);
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
    let text = r.stdout ?? "";
    for (const line of (r.stderr ?? "").split("\n")) {
      if (line.startsWith("[vitro] backend=")) continue;
      text += line + "\n";
    }
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
    } else {
      fail(`未知参数 ${JSON.stringify(a)}`);
    }
  }
  void golden;

  if (backend === "wasm" && !fs.existsSync(path.join(root, WASM_SHELL))) {
    fail(`${WASM_SHELL} 不存在（wasm 臂需 build 产物：moon build --release --target js cmd/vitro_wasm）`);
  }
  process.stderr.write(
    "vm_diff: [裁判切换] oracle 面已随工序④退役——本判定固定走 --golden 冻结基线（结构裁判自 oracle 切为 digest 清单；正确性主锚仍为 Clang/shadow）\n",
  );

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
    const k = cases[0]?.rel ?? "";
    const e = doc.cases[k];
    if (e !== undefined && (e.known_mb_digest ?? "") === "") {
      e.stdout_sha = "deadbeef12345678";
      process.stdout.write(`[selftest][golden] 已篡改清单条目: ${k} ——随后比对必须 FAIL\n`);
    }
  }

  let same = 0;
  let knownN = 0;
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
    const whole = mbWholeDigest(d.exit, d.stdout, d.mem, d.cf);
    if ((e.known_mb_digest ?? "") !== "") {
      if (whole === e.known_mb_digest) {
        process.stdout.write(`DIFF-KNOWN ${c.rel}（mb 分叉指纹一致；归因见 known_diffs.json）\n`);
        knownN++;
      } else {
        process.stdout.write(
          `DIFF  ${c.rel}：known 分叉形状已变（登记 mb 指纹 ${e.known_mb_digest ?? ""} 实测 ${whole}）——重新归因后重跑 --freeze-mb\n`,
        );
        diff++;
      }
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
    `\nvm_diff[golden]: SAME=${same} DIFF-KNOWN=${knownN} DIFF=${diff} SKIP=${skipN}（共 ${same + knownN + diff + skipN}）\n`,
  );

  // **不迁动态白名单防腐化**：Go 版那段（跑完全量后检查 known.hit / skip.hit）
  // 位于 `os.Exit(runAgainstDigest(cases))` 之后，只在 oracle 双侧对拍路径执行——
  // 该路径随工序④删区永不可达。2026-10-23 实测：Go 版全量 733 例 exit 0 且不报
  // 任何「空转」，而早期 TS 版在 golden 末尾做了同样检查，多报 4 个 known 条目。
  // 静态防腐化（跑之前查条目名是否在语料内）在 golden 路径**保留**——Go 版那段
  // 在 freeze/golden 分支之前。
  return diff > 0 ? 1 : 0;
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
      if ((e.known_mb_digest ?? "") !== "") parts.push(`      "known_mb_digest": ${q(e.known_mb_digest ?? "")}`);
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
