#!/usr/bin/env node
// W4 第四臂对拍驱动：同一 wasm-gc 产物 × wasmtime（Cranelift，rs/ 供给版跑器）
// vs V8（node，host_node.mts）——gateway NDJSON 协议层逐位对拍。CI 接线 =
// 主 CI called 单元 `.github/workflows/ci-engine-gates.yml` job `arm4-wasmtime`
//（CI 拆分批 2026-11-14 起自 ci.yml 迁入；corpus deep-nomem --all 严格
// identical + synth 对抗集 --baseline 锁定）。
//
//   node scripts/wasmtime_arm/main.mts gen  [--out D] [--seed N] [--profile P] [--all | --cases a.c,b.c | --quota s=N,...] [--synth] [--shared]
//   node scripts/wasmtime_arm/main.mts run  [--out D] [--wasm P] [--exe P] [--timeout-ms N（默认 900000，0=关——单侧挂死护栏）]
//   node scripts/wasmtime_arm/main.mts diff [--out D] [--json] [--baseline F | --freeze-baseline F] [--expect-min-cases N] [--expect-min-frames N]
//   node scripts/wasmtime_arm/main.mts all  [上述全部]
//
// 产出（--out 目录）：requests.ndjson / manifest.json / responses.wasmtime.ndjson /
// responses.node.ndjson / report.json。verdict 五桶：AGREE < TRAP_BOTH（双侧 trap 且
// 归因类别同）< CASCADE（case 内单侧 trap 之后的级联字节差）< DIFF（字节不等 /
// 双侧 trap 类别异）< TRAP_ONE（单侧 trap）。每 case 首帧为实例复位标记（两侧
// 同起点；--shared 关）。
//
// 语料面：--all = corpus 根目录**全集**枚举（含工程模式目录 llm_multifile——一级
// 子目录 = 一个工程，files = .c 字节序 + .h 字节序，clang_direct #237 同约定）；
// 抽样模式配额键须为根目录名（未知 suite fail loud）。
//
// 前置：rs/ 需 `cargo build --release --locked`（rustc ≥1.97，wasmtime 50.0.1）；
// wasm 产物按 AGENTS.md 纪律 12 两件（moon build --release --target wasm-gc
// gateway/wasm + node scripts/wasmopt/main.mts <产物>）。

import { existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { join, resolve } from "node:path";
import {
  PROFILES,
  PROJECT_SUITES,
  STATIC_CASE,
  STATIC_METHODS,
  adversarialFrames,
  buildFrames,
  byteOrder,
  checkBaseline,
  collectFiles,
  compareResponses,
  frameMethods,
  freezeBaseline,
  mulberry32,
  sampleK,
  sha256Hex,
  staticFrames,
  stratifiedSample,
  synthCases,
  validateQuotaKeys,
  type CaseInput,
  type DiffReport,
  type FileEntry,
  type Manifest,
  type ManifestCase,
  type Profile,
  type SuiteFiles,
  type SynthBaseline,
} from "./lib.mts";

const REPO = resolve(import.meta.dirname, "..", "..");
const CORPUS = join(REPO, "corpus");
const DEFAULT_WASM = join(REPO, "moonbit", "_build", "wasm-gc", "release", "build", "gateway", "wasm", "wasm.wasm");
const DEFAULT_EXE = join(
  import.meta.dirname,
  "rs",
  "target",
  "release",
  process.platform === "win32" ? "wasmtime_arm.exe" : "wasmtime_arm",
);
const DEFAULT_SEED = 20261102;
/** 分层配额（≈115 份 + mustInclude）——覆盖 corpus 全部 10 个根目录（stdin / include /
 * cpp / 模板 / 规模 / 骨架 / 多文件工程）。键必须是根目录名（gen 时对账 fail loud）。 */
const DEFAULT_QUOTA: Record<string, number> = {
  baseline: 40,
  knr: 15,
  leetcode: 12,
  cpp: 8,
  gap: 6,
  template_generated: 8,
  llm_scale: 3,
  mutator_probe: 1,
  codegen_skeleton: 13,
  llm_multifile: 10,
};

interface Opts {
  cmd: string;
  out: string;
  wasm: string;
  exe: string;
  seed: number;
  cases: string[] | null;
  quota: Record<string, number>;
  profile: Profile;
  synth: boolean;
  all: boolean;
  shared: boolean;
  baseline: string | null;
  freezeBaseline: string | null;
  expectMinCases: number;
  expectMinFrames: number;
  timeoutMs: number;
  json: boolean;
}

function parseArgs(argv: string[]): Opts {
  const o: Opts = {
    cmd: argv[0] ?? "",
    out: join(REPO, "tmp", "w4"),
    wasm: DEFAULT_WASM,
    exe: DEFAULT_EXE,
    seed: DEFAULT_SEED,
    cases: null,
    quota: { ...DEFAULT_QUOTA },
    profile: "run",
    synth: false,
    all: false,
    shared: false,
    baseline: null,
    freezeBaseline: null,
    expectMinCases: 0,
    expectMinFrames: 0,
    timeoutMs: DEFAULT_TIMEOUT_MS,
    json: false,
  };
  const posInt = (flag: string, v: string): number => {
    const n = Number(v);
    if (!Number.isInteger(n) || n < 0) throw new Error(`${flag} 须为非负整数：${v}`);
    return n;
  };
  for (let i = 1; i < argv.length; i++) {
    const a = argv[i] as string;
    const next = (): string => {
      const v = argv[++i];
      if (v === undefined) throw new Error(`${a} 缺参数`);
      return v;
    };
    if (a === "--out") o.out = resolve(next());
    else if (a === "--wasm") o.wasm = resolve(next());
    else if (a === "--exe") o.exe = resolve(next());
    else if (a === "--seed") o.seed = Number(next()) >>> 0;
    else if (a === "--cases") o.cases = next().split(",").filter((s) => s.length > 0);
    else if (a === "--profile") {
      const p = next();
      if (!(PROFILES as readonly string[]).includes(p)) throw new Error(`--profile 取值 ${PROFILES.join("|")}：${p}`);
      o.profile = p as Profile;
    } else if (a === "--quota") {
      for (const kv of next().split(",")) {
        const [k, v] = kv.split("=");
        if (!k || v === undefined || !Number.isFinite(Number(v))) throw new Error(`--quota 格式 suite=N：${kv}`);
        o.quota[k] = Number(v);
      }
    } else if (a === "--json") o.json = true;
    else if (a === "--synth") o.synth = true;
    else if (a === "--all") o.all = true;
    else if (a === "--shared") o.shared = true;
    else if (a === "--baseline") o.baseline = resolve(next());
    else if (a === "--freeze-baseline") o.freezeBaseline = resolve(next());
    else if (a === "--expect-min-cases") o.expectMinCases = posInt(a, next());
    else if (a === "--expect-min-frames") o.expectMinFrames = posInt(a, next());
    else if (a === "--timeout-ms") o.timeoutMs = posInt(a, next());
    else throw new Error(`未知参数 ${a}`);
  }
  return o;
}

/** corpus 根目录全集（审阅 P2-1：「全量」不再由硬编码白名单驱动）。 */
function listCorpusRoots(): string[] {
  return readdirSync(CORPUS, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => d.name)
    .sort(byteOrder);
}

/** 工程模式：一级子目录含 ≥1 .c 即一个工程 case（名 `<suite>/<dir>`）。 */
function listProjects(suite: string): string[] {
  const dir = join(CORPUS, suite);
  if (!existsSync(dir)) return [];
  const out: string[] = [];
  for (const ent of readdirSync(dir, { withFileTypes: true })) {
    if (!ent.isDirectory()) continue;
    const hasC = readdirSync(join(dir, ent.name)).some((f) => f.endsWith(".c"));
    if (hasC) out.push(`${suite}/${ent.name}`);
  }
  return out.sort(byteOrder);
}

/** 工程 case 的 files：.c 字节序在前 + .h 字节序在后（clang_direct #237 同约定）；
 * 登记名 = basename（gateway vfs 键，与 include 查找对齐）。 */
function projectFiles(name: string): FileEntry[] {
  const dir = join(CORPUS, name);
  const names = readdirSync(dir).filter((f) => !statSync(join(dir, f)).isDirectory());
  const cs = names.filter((f) => f.endsWith(".c")).sort(byteOrder);
  const hs = names.filter((f) => f.endsWith(".h")).sort(byteOrder);
  const out: FileEntry[] = [];
  for (const f of [...cs, ...hs]) {
    const src = readOrNull(join(dir, f));
    if (src === null) throw new Error(`工程文件不可读：${name}/${f}`);
    out.push({ filename: f, source: src });
  }
  return out;
}

function listSuite(suite: string): string[] {
  if (PROJECT_SUITES.has(suite)) return listProjects(suite);
  const dir = join(CORPUS, suite);
  if (!existsSync(dir)) return [];
  const out: string[] = [];
  const walk = (rel: string): void => {
    for (const ent of readdirSync(join(dir, rel)).sort(byteOrder)) {
      const relp = rel === "" ? ent : `${rel}/${ent}`;
      const full = join(dir, relp);
      if (statSync(full).isDirectory()) walk(relp);
      else if (/\.(c|cpp|cc)$/.test(ent)) out.push(`${suite}/${relp}`);
    }
  };
  walk("");
  return out;
}

function readOrNull(p: string): string | null {
  try {
    return readFileSync(p, "utf8");
  } catch {
    return null;
  }
}

/** 特征覆盖清单：include 语料 3 份 + vm_diff golden 中 exit_code≠0 的 5 份（seed 确定）。 */
function mustIncludeList(seed: number): string[] {
  const out: string[] = [];
  const rnd = mulberry32(seed ^ 0x5eed);
  const inc = listSuite("baseline").filter((f) => /\/e2_.*\.c$/.test(f));
  out.push(...sampleK(inc, 3, rnd));
  const goldenPath = join(REPO, "scripts", "vm_diff", "golden_digest.json");
  const golden = readOrNull(goldenPath);
  if (golden !== null) {
    const g = JSON.parse(golden) as Record<string, { exit_code?: number }>;
    const abnormal = Object.keys(g)
      .filter((k) => (g[k]?.exit_code ?? 0) !== 0 && existsSync(join(CORPUS, k)))
      .sort(byteOrder);
    out.push(...sampleK(abnormal, 5, rnd));
  }
  return out;
}

function cmdGen(o: Opts): void {
  mkdirSync(o.out, { recursive: true });
  // 语料来源三选一：--synth 合成对抗集 / --cases 指定 / 分层抽样
  const inputs: { name: string; suite: string; input: CaseInput }[] = [];
  if (o.synth) {
    const filter = o.cases === null ? null : new Set(o.cases);
    for (const s of synthCases()) {
      const name = `synth/${s.name}.c`;
      if (filter !== null && !filter.has(name) && !filter.has(s.name)) continue;
      inputs.push({
        name,
        suite: "synth",
        input: { name, files: [{ filename: `${s.name}.c`, source: s.src }], stdin: s.stdin ?? null },
      });
    }
  } else {
    let names: string[];
    const roots = listCorpusRoots();
    if (o.cases !== null) {
      names = o.cases.slice().sort(byteOrder);
    } else if (o.all) {
      // 全量 = 根目录全集逐一枚举（P2-1：不经白名单）
      names = roots.flatMap((s) => listSuite(s)).sort(byteOrder);
    } else {
      validateQuotaKeys(o.quota, roots);
      const suites: SuiteFiles[] = Object.keys(o.quota).map((s) => ({ suite: s, files: listSuite(s) }));
      names = stratifiedSample(suites, { quotas: o.quota, mustInclude: mustIncludeList(o.seed) }, o.seed);
    }
    for (const name of names) {
      const suite = name.split("/")[0] ?? "";
      if (PROJECT_SUITES.has(suite)) {
        // 工程 case：目录内全部 .c/.h 作 files（多翻译单元），无 stdin 约定
        inputs.push({ name, suite, input: { name, files: projectFiles(name), stdin: null } });
        continue;
      }
      const full = join(CORPUS, name);
      const src = readOrNull(full);
      if (src === null) throw new Error(`语料不可读：${name}`);
      const files = collectFiles(full, src, readOrNull);
      const stdinPath = full.replace(/\.(c|cpp|cc)$/, ".in");
      const stdin = stdinPath !== full ? readOrNull(stdinPath) : null;
      inputs.push({ name, suite, input: { name, files, stdin } });
    }
  }
  const wasmSha = existsSync(o.wasm) ? sha256Hex(readFileSync(o.wasm)) : "";
  const cases: ManifestCase[] = [];
  const lines: string[] = [];
  // 静态族前导（一次性）——进程级表 / `_` 常量供给面 / fail-loud 错误帧；
  // synth 模式再追加请求行级对抗帧（深 JSON / 编码边界 / 参数域错误）
  {
    const sf = staticFrames();
    const methods = STATIC_METHODS.slice();
    if (o.synth) {
      const adv = adversarialFrames(sf.length + 1);
      sf.push(...adv.frames);
      methods.push(...adv.methods);
    }
    cases.push({ name: STATIC_CASE, suite: "static", has_stdin: false, file_count: 0, frame_start: 0, frame_count: sf.length, methods });
    lines.push(...sf);
  }
  const methods = frameMethods(o.profile, !o.shared);
  for (const it of inputs) {
    const frames = buildFrames(it.input, o.profile, !o.shared);
    cases.push({
      name: it.name,
      suite: it.suite,
      has_stdin: it.input.stdin !== null,
      file_count: it.input.files.length,
      frame_start: lines.length,
      frame_count: frames.length,
      methods,
    });
    lines.push(...frames);
  }
  const manifest: Manifest = { schema: "w4-manifest-v1", seed: o.seed, profile: o.profile, wasm_sha256: wasmSha, cases };
  writeFileSync(join(o.out, "requests.ndjson"), lines.join("\n") + "\n");
  writeFileSync(join(o.out, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n");
  process.stderr.write(`[w4 gen] profile=${o.profile} cases=${cases.length}(含 static) frames=${lines.length} seed=${o.seed} out=${o.out}\n`);
}

/** 单侧跑器 wall 护栏默认（ms）——corpus 全量 wasmtime 侧 ~65s、synth 轮 ~90s
 * （含 GC 病态例），CI 慢机 ~3x；900s 给足余量且远低于 CI job timeout 30min：
 * 挂死（死循环/竞态卡死/病态语料）尽早红而非拖到 job 超时零信息。--timeout-ms 0 关。 */
const DEFAULT_TIMEOUT_MS = 900_000;

function runSide(label: string, cmd: string, args: string[], cwd: string, timeoutMs: number): void {
  const t0 = performance.now();
  const r = spawnSync(cmd, args, { cwd, encoding: "buffer", maxBuffer: 1 << 30, timeout: timeoutMs > 0 ? timeoutMs : undefined });
  const ms = (performance.now() - t0).toFixed(0);
  process.stderr.write(r.stderr.toString("utf8"));
  if (r.error) {
    // spawnSync 超时走 error.code=ETIMEDOUT（status=null/signal=SIGTERM）——Node
    // 类型只标 Error，运行时带 code（ErrnoException 形态）
    if ((r.error as NodeJS.ErrnoException).code === "ETIMEDOUT") {
      throw new Error(
        `[w4 run:${label}] 超时 >${timeoutMs}ms（wall=${ms}ms 已杀）——单侧挂死或病态语料：该侧 stderr 已透传（top10 逐帧计时指向嫌疑帧），复跑加 --cases <name> 缩面定位`,
      );
    }
    throw new Error(`[w4 run:${label}] 启动失败：${r.error.message}（wall=${ms}ms）`);
  }
  if (r.signal !== null) {
    throw new Error(`[w4 run:${label}] 被信号 ${r.signal} 终止（rc=${r.status}，${ms}ms）`);
  }
  if (r.status !== 0) {
    // 失败现场保全：stdout 尾部透传（诊断应走 stderr 已全量透传；防意外走 stdout 的输出被吞）
    const tail = r.stdout.toString("utf8").slice(-2000);
    if (tail.length > 0) process.stderr.write(`[w4 run:${label}] stdout 尾部：\n${tail}\n`);
    throw new Error(`[w4 run:${label}] rc=${r.status}（${ms}ms）——上方为该侧 stderr 全量`);
  }
  process.stderr.write(`[w4 run:${label}] rc=0 wall=${ms}ms\n`);
}

function cmdRun(o: Opts): void {
  const req = join(o.out, "requests.ndjson");
  if (!existsSync(req)) throw new Error(`缺 ${req}——先 gen`);
  if (!existsSync(o.wasm)) throw new Error(`wasm 产物不存在：${o.wasm}（纪律 12 两件构建）`);
  if (!existsSync(o.exe)) throw new Error(`wasmtime 跑器不存在：${o.exe}（cd scripts/wasmtime_arm/rs && cargo build --release）`);
  const manifestPath = join(o.out, "manifest.json");
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8")) as Manifest;
  const sha = sha256Hex(readFileSync(o.wasm));
  if (manifest.wasm_sha256 !== "" && manifest.wasm_sha256 !== sha) {
    throw new Error(`wasm 产物 sha 与 manifest 不符：manifest=${manifest.wasm_sha256} 实际=${sha}（产物被重建？重新 gen 或指定同一产物）`);
  }
  manifest.wasm_sha256 = sha;
  writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + "\n");
  runSide("wasmtime", o.exe, [o.wasm, req, join(o.out, "responses.wasmtime.ndjson")], o.out, o.timeoutMs);
  runSide(
    "node",
    process.execPath,
    [join(import.meta.dirname, "host_node.mts"), o.wasm, req, join(o.out, "responses.node.ndjson")],
    o.out,
    o.timeoutMs,
  );
}

function cmdDiff(o: Opts): { report: DiffReport; ok: boolean } {
  const manifest = JSON.parse(readFileSync(join(o.out, "manifest.json"), "utf8")) as Manifest;
  const left = readFileSync(join(o.out, "responses.wasmtime.ndjson"));
  const right = readFileSync(join(o.out, "responses.node.ndjson"));
  const report = compareResponses(manifest, left, right, { left: "wasmtime", right: "node" });
  writeFileSync(join(o.out, "report.json"), JSON.stringify(report, null, 2) + "\n");
  if (o.json) {
    process.stdout.write(JSON.stringify(report) + "\n");
  } else {
    const s = report.summary;
    const lines = [
      `[w4 diff] profile=${manifest.profile} wasm=${manifest.wasm_sha256.slice(0, 16)} cases=${s.cases} frames=${s.frames}`,
      `  AGREE=${s.AGREE} TRAP_BOTH=${s.TRAP_BOTH} CASCADE=${s.CASCADE} DIFF=${s.DIFF} TRAP_ONE=${s.TRAP_ONE}`,
      `  identical=${report.identical} left_sha=${report.left_sha256.slice(0, 16)} right_sha=${report.right_sha256.slice(0, 16)} lines=${report.line_count.left}/${report.line_count.right}`,
    ];
    for (const c of report.cases) {
      if (c.verdict === "AGREE") continue;
      lines.push(`  [${c.verdict}] ${c.name}`);
      for (const f of c.frames) {
        if (f.verdict === "AGREE") continue;
        let detail = `    #${f.idx} ${f.method} ${f.verdict} len=${f.left_len}/${f.right_len} epoch=${f.epoch.left}/${f.epoch.right}`;
        if (f.first_diff) detail += ` @byte ${f.first_diff.byte_offset}`;
        if (f.left_trap) detail += ` L<${f.left_trap.slice(0, 120)}>`;
        if (f.right_trap) detail += ` R<${f.right_trap.slice(0, 120)}>`;
        lines.push(detail);
      }
    }
    process.stdout.write(lines.join("\n") + "\n");
  }
  // 抽样集塌缩自证（审阅 P2-5）：identical 对「两侧皆空」也绿——锁最小 cases/frames
  const collapsed: string[] = [];
  if (o.expectMinCases > 0 && report.summary.cases < o.expectMinCases) collapsed.push(`cases=${report.summary.cases} < ${o.expectMinCases}`);
  if (o.expectMinFrames > 0 && report.summary.frames < o.expectMinFrames) collapsed.push(`frames=${report.summary.frames} < ${o.expectMinFrames}`);
  if (collapsed.length > 0) {
    process.stdout.write(`[w4 collapse] FAIL——对拍面低于下限：${collapsed.join("；")}（语料目录/白名单/路径变动？）\n`);
    return { report, ok: false };
  }
  // 冻结基线：本轮 verdict 落盘（DIFF 拒冻）
  if (o.freezeBaseline !== null) {
    // #466 审阅 P3-3（2026-11-04）：note 追加式——目标文件已有 note 时
    // 拼接保留（模板覆盖曾丢整段梯度知识：V8 临界版本依赖面/5000 flaky
    // 勿加档等）；首冻无旧件走模板。
    const freezeDate = new Date().toISOString().slice(0, 10);
    const freezeCmd = "node scripts/wasmtime_arm/main.mts all --synth --freeze-baseline <此文件>";
    let freezeNote = `frozen ${freezeDate} from --synth; 重冻：${freezeCmd}`;
    try {
      const prev = JSON.parse(readFileSync(o.freezeBaseline, "utf8")) as { note?: string };
      if (prev.note && !prev.note.startsWith(`frozen ${freezeDate}`)) {
        freezeNote = `frozen ${freezeDate} from --synth; 重冻：${freezeCmd}
—— 前次 note 追加保留：${prev.note}`;
      }
    } catch {
      // 首冻（目标不存在/坏 JSON）——模板 note
    }
    const base = freezeBaseline(report, manifest.profile, freezeNote);
    writeFileSync(o.freezeBaseline, JSON.stringify(base, null, 2) + "\n");
    process.stderr.write(`[w4 baseline] 冻结 ${Object.keys(base.cases).length} 例 → ${o.freezeBaseline}\n`);
    return { report, ok: true };
  }
  // 基线判定：五类问题任一即红（DIFF 恒红；改善亦红指引重冻）
  if (o.baseline !== null) {
    const base = JSON.parse(readFileSync(o.baseline, "utf8")) as SynthBaseline;
    if (base.schema !== "w4-synth-baseline-v1") throw new Error(`基线 schema 不符：${base.schema}`);
    if (base.profile !== manifest.profile) throw new Error(`基线 profile=${base.profile} 与本轮 ${manifest.profile} 不符`);
    const problems = checkBaseline(report, base);
    for (const p of problems) {
      const arrow = p.from !== undefined && p.to !== undefined ? ` ${p.from}→${p.to}` : p.to !== undefined ? ` ${p.to}` : p.from !== undefined ? ` (基线 ${p.from})` : "";
      process.stdout.write(`  [baseline:${p.kind}] ${p.name}${arrow}\n`);
    }
    const ok = problems.length === 0;
    process.stdout.write(`[w4 baseline] ${ok ? "PASS" : "FAIL"}——${Object.keys(base.cases).length} 例基线 / ${problems.length} 问题${ok ? "" : "（DIFF/恶化/未登记/僵尸 必红；改善须 --freeze-baseline 重冻）"}\n`);
    return { report, ok };
  }
  return { report, ok: report.identical };
}

function main(): number {
  const o = parseArgs(process.argv.slice(2));
  switch (o.cmd) {
    case "gen":
      cmdGen(o);
      return 0;
    case "run":
      cmdRun(o);
      return 0;
    case "diff":
      return cmdDiff(o).ok ? 0 : 3;
    case "all":
      cmdGen(o);
      cmdRun(o);
      return cmdDiff(o).ok ? 0 : 3;
    default:
      process.stderr.write("usage: main.mts gen|run|diff|all [--out D] [--wasm P] [--exe P] [--seed N] [--profile run|deep-nomem|deep] [--all | --cases a.c,b.c | --quota s=N,...] [--synth] [--baseline F | --freeze-baseline F] [--json]\n");
      return 2;
  }
}

try {
  process.exitCode = main();
} catch (e) {
  process.stderr.write(`[w4] ${(e as Error).message}\n`);
  process.exitCode = 1;
}
