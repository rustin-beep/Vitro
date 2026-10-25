// facts.mts —— 测试事实采集层（#273 存量 Go 重写批；原 facts.go，行为锚 =
// moonbit_fact_test / cargo_fact_test / const_audit_test 直译）。
// 把各防线的当前真值采进 reports/facts.json。
//
// 设计原则（与 Python 原型一致，此处为长期维护版）：
//  1. 不猜、不兜底：值只能来自产物文件或显式 --run。取不到记 unavailable 并附 how_to_get，
//     绝不用 0 或旧值兜底——兜底本身就是漂移来源。
//  2. 默认只读：默认只读已有产物，不触发任何防线执行。
//  3. 带溯源：每项记录 source / as_of / provenance。
//
// 迁移行为修正（2026-10-25，登记在案）：原 Go 版 --run 采集器的子进程命令
// （go run ./scripts/replay/replay_s1_s5.go 等 4 处）指向已迁 .mts 的旧路径，
// 实际恒 unavailable（死路径）——TS 版改跑现役 node 入口，--run 语义修复。
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { byteSort, goJSONMarshalIndent, goTrimSpace } from "../internal/text.mts";

// ─── 数据结构 ────────────────────────────────────────────────────────────────

export interface Fact {
  value: number | null;
  // svalue：字符串常量真值（如 ABI 版本 "2.1.0"）。value/svalue 恰一者非零值；
  // 对账层按 Key 区分数字规则与常量规则。空串时序列化省略（Go omitempty）。
  svalue?: string;
  unit: string;
  source: string;
  provenance: string;
  as_of: string;
  status: string;
  note: string;
  how_to_get: string;
}

export interface GitInfo {
  rev: string;
  branch: string;
  dirty: boolean;
}

export interface FactsDoc {
  schema: string;
  generated_at: string;
  git: GitInfo;
  facts: Record<string, Fact>;
}

export const FACTS_SCHEMA = "vitro.facts.v1";

// ─── 基础设施 ────────────────────────────────────────────────────────────────

// goISO 复刻 Go `Format("2006-01-02T15:04:05-07:00")`（本地时区 + 数值偏移）。
function goISO(d: Date): string {
  const pad = (n: number): string => String(n).padStart(2, "0");
  const off = -d.getTimezoneOffset();
  const sign = off >= 0 ? "+" : "-";
  const oh = Math.floor(Math.abs(off) / 60);
  const om = Math.abs(off) % 60;
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}` +
    `T${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}` +
    `${sign}${pad(oh)}:${pad(om)}`;
}

export function nowISO(): string {
  return goISO(new Date());
}

export function gitInfo(root: string): GitInfo {
  const run = (args: string[]): string => {
    const r = spawnSync("git", ["-C", root, ...args], { encoding: "utf8" });
    if (r.error || r.status !== 0) return "";
    return goTrimSpace(r.stdout ?? "");
  };
  let rev = run(["rev-parse", "--short", "HEAD"]);
  if (rev === "") rev = "unknown";
  let branch = run(["rev-parse", "--abbrev-ref", "HEAD"]);
  if (branch === "") branch = "unknown";
  return { rev, branch, dirty: run(["status", "--short"]) !== "" };
}

export function okFact(v: number, unit: string, source: string, provenance: string, asOf: string): Fact {
  return {
    value: v, svalue: undefined, unit, source, provenance,
    as_of: asOf, status: "ok", note: "", how_to_get: "",
  };
}

export function unavail(unit: string, source: string, howToGet: string, note: string): Fact {
  return {
    value: null, svalue: undefined, unit, source, provenance: "none",
    as_of: "", status: "unavailable", note, how_to_get: howToGet,
  };
}

export function mtimeISO(p: string): string {
  let st: fs.Stats;
  try {
    st = fs.statSync(p);
  } catch {
    return "";
  }
  return goISO(st.mtime);
}

// ─── 采集器：失败台账活跃条目（解析 md，零副作用）──────────────────────────

const RE_ACTIVE_SECTION = /^#{2}\s+.*?(KNOWN_FAILURE|KNOWN_DIVERGENCE|KNOWN_LIMITATION)/i;
const RE_ENTRY = /^#{3}\s+/;
const RE_SECTION = /^#{2}\s+/;
const RE_RESOLVED = /已修复|FIXED|RESOLVED|不再失败|no longer fails/i;
const RE_TABLE_DIV = /^\|[-:|\s]+\|$/;

export function countActiveEntries(p: string): { n: number; ok: boolean } {
  let b: string;
  try {
    b = fs.readFileSync(p, "utf8");
  } catch {
    return { n: 0, ok: false };
  }
  let count = 0;
  let inActive = false;
  let inTable = false;
  for (const raw of b.split("\n")) {
    const s = goTrimSpace(raw.endsWith("\r") ? raw.slice(0, -1) : raw);
    if (RE_SECTION.test(s)) {
      inActive = RE_ACTIVE_SECTION.test(s);
      inTable = false;
      continue;
    }
    if (!inActive) continue;
    if (RE_ENTRY.test(s)) {
      if (!RE_RESOLVED.test(s)) count++;
      inTable = false;
      continue;
    }
    if (RE_TABLE_DIV.test(s)) {
      inTable = true;
      continue;
    }
    if (inTable && s.startsWith("|") && s.endsWith("|")) {
      if (!RE_RESOLVED.test(s)) count++;
      continue;
    }
    if (s !== "" && !s.startsWith("|")) {
      inTable = false;
    }
  }
  return { n: count, ok: true };
}

function collectFailureLedgers(root: string, facts: Record<string, Fact>): void {
  for (const m of [
    { key: "e2e_failures_active", file: "E2E_FAILURES.md" },
    { key: "cpp_failures_active", file: "CPP_FAILURES.md" },
  ]) {
    const rel = "native/tests/" + m.file;
    const p = path.join(root, "native", "tests", m.file);
    const r = countActiveEntries(p);
    if (r.ok) {
      facts[m.key] = okFact(r.n, "条", rel, "parse_markdown", mtimeISO(p));
    } else {
      facts[m.key] = unavail("条", rel, "确认 " + rel + " 是否存在", "");
    }
  }
}

// ─── 采集器：用例目录计数（磁盘真值，零副作用）──────────────────────────────

function collectCaseDirs(root: string, facts: Record<string, Fact>): void {
  // 按用例扩展名计数：.in（stdin 伴生输入）与 .h（被 include 的辅助头）
  // 不是用例。曾按"非目录文件"计数，knr 的 29 个 .in、baseline 的 4 个 .h
  // 全被计入（knr 报 110 而实际 69 个 .c）——事实台账失真。
  for (const m of [
    { key: "cpp_e2e_cases", sub: "cpp", ext: ".cpp" },
    { key: "c_e2e_baseline_cases", sub: "baseline", ext: ".c" },
    { key: "c_e2e_gap_cases", sub: "gap", ext: ".c" },
    { key: "c_e2e_knr_cases", sub: "knr", ext: ".c" },
    { key: "c_e2e_leetcode_cases", sub: "leetcode", ext: ".c" },
  ]) {
    const rel = "corpus/" + m.sub + "/";
    const d = path.join(root, "corpus", m.sub);
    let ents: fs.Dirent[];
    try {
      ents = fs.readdirSync(d, { withFileTypes: true });
    } catch {
      facts[m.key] = unavail("用例", rel, "确认目录 " + rel + " 是否存在", "");
      continue;
    }
    let n = 0;
    for (const e of ents) {
      if (!e.isDirectory() && e.name.endsWith(m.ext)) n++;
    }
    // as_of 取**采集时刻**，不是目录 mtime：目录计数是"此刻磁盘状态的快照"，
    // 每次运行都重新数，不存在"陈旧"概念（用 mtime 会把"长期无增删"误判超龄）。
    facts[m.key] = okFact(n, "用例", rel, "count_dir", nowISO());
  }
}

// ─── 采集器：常量真值（读源码，零副作用）────────────────────────────────────

// collectAbiVersion 采集 C ABI 版本真值。唯一来源曾是
// native/src/capi/first_batch.rs 的 VITRO_ABI_VERSION 常量——文档里的
// 版本号一律不是真相（M13 实证：代码 2.1.0 时仍有多份文档写 1.2.0/2.0.0）。
export function collectAbiVersion(root: string, facts: Record<string, Fact>): void {
  // 工序④删区（2026-10-05）：ABI 真值源（Rust first_batch.rs）随区删除——
  // C ABI 已随 F-5 裁撤，常量退役（文档历史句豁免）。
  facts["abi_version"] = unavail("版本", "native/（已删除）", "Rust 区已退役（2026-10-05）", "真值源退役");
}

// ─── 采集器：MoonBit 建包状态（扫目录 / 读 moon.mod，零副作用）──────────────

// collectMoonbitPackages 采集 MoonBit 活跃区的建包状态（2026-09-28，包切分
// 分层图防漂移批）：
//   - moonbit_built_packages：moonbit/ 下所有含 moon.pkg 的目录（仓库相对
//     路径，/ 分隔；_build 与 .mooncakes 排除）——"包已建成"的唯一机械判据；
//   - moonbit_engine_version：moonbit/moon.mod 的 version 字段。
// 均为 SValue 条目（value=null），天然不参与超龄降级；缺文件记 unavailable
// 不兜底。
export function collectMoonbitPackages(root: string, facts: Record<string, Fact>): void {
  const pkgs: string[] = [];
  let walkErr: string | null = null;
  const base = path.join(root, "moonbit");
  // Go filepath.WalkDir 等价：字节序遍历 + 目录级排除。
  const walk = (dir: string): void => {
    let ents: fs.Dirent[];
    try {
      ents = fs.readdirSync(dir, { withFileTypes: true });
    } catch (e) {
      if (dir === base) walkErr = (e as Error).message;
      return;
    }
    for (const name of byteSort(ents.map((x) => x.name))) {
      const ent = ents.find((x) => x.name === name)!;
      const p = path.join(dir, ent.name);
      if (ent.isDirectory()) {
        if (ent.name === "_build" || ent.name === ".mooncakes") continue; // 构建产物 / 依赖安装目录
        walk(p);
        continue;
      }
      if (ent.name === "moon.pkg" || ent.name === "moon.pkg.json") {
        pkgs.push(relOf(root, path.dirname(p)));
      }
    }
  };
  const howPkgs = "扫 moonbit/ 下含 moon.pkg 的目录（排除 _build / .mooncakes）";
  if (!fs.existsSync(base)) {
    walkErr = "moonbit/ 目录不存在";
  } else {
    walk(base);
  }
  if (walkErr !== null) {
    facts["moonbit_built_packages"] = unavail("包", "moonbit/", howPkgs, walkErr);
  } else if (pkgs.length === 0) {
    facts["moonbit_built_packages"] = unavail("包", "moonbit/", howPkgs, "未找到任何 moon.pkg（目录形态变更？）");
  } else {
    facts["moonbit_built_packages"] = {
      value: null, svalue: byteSort(pkgs).join(" "), unit: "包",
      source: "moonbit/（moon.pkg 目录扫描）", provenance: "fs_scan",
      as_of: nowISO(), status: "ok", note: "", how_to_get: "",
    };
  }

  const rel = "moonbit/moon.mod";
  const p = path.join(root, "moonbit", "moon.mod");
  const howVer = "读 " + rel + " 的 version 字段";
  let b: string;
  try {
    b = fs.readFileSync(p, "utf8");
  } catch {
    facts["moonbit_engine_version"] = unavail("版本", rel, howVer, "文件缺失");
    return;
  }
  const m = RE_MOON_MOD_VERSION.exec(b);
  if (m === null) {
    facts["moonbit_engine_version"] = unavail("版本", rel, howVer, "未解析到 version 字段（形态变更？）");
    return;
  }
  facts["moonbit_engine_version"] = {
    value: null, svalue: m[1]!, unit: "版本", source: rel,
    provenance: "read_const", as_of: mtimeISO(p), status: "ok", note: "", how_to_get: "",
  };
}

const RE_MOON_MOD_VERSION = /^[ \t]*version[ \t]*=[ \t]*"([^"]+)"/m;

function relOf(root: string, p: string): string {
  return path.relative(root, p).replaceAll("\\", "/");
}

// ─── 采集器：需执行类（--run / --run-slow 才启用）───────────────────────────

// goParseDuration 复刻 Go time.ParseDuration 的常用面（ns/us/µs/ms/s/m/h 序列）。
export function goParseDuration(s: string): number | null {
  if (s === "" || s === "0") return s === "0" ? 0 : null;
  let neg = false;
  let body = s;
  if (body.startsWith("-") || body.startsWith("+")) {
    neg = body.startsWith("-");
    body = body.slice(1);
  }
  if (body === "0") return 0;
  const unitMs: Record<string, number> = { ns: 1e-6, us: 1e-3, "µs": 1e-3, ms: 1, s: 1e3, m: 6e4, h: 36e5 };
  let total = 0;
  let rest = body;
  while (rest.length > 0) {
    const m = /^([0-9]+(?:\.[0-9]+)?)(ns|us|µs|ms|s|m|h)/.exec(rest);
    if (m === null) return null;
    const v = Number.parseFloat(m[1]!);
    if (Number.isNaN(v)) return null;
    total += v * unitMs[m[2]!]!;
    rest = rest.slice(m[0].length);
  }
  return neg ? -total : total;
}

// goDurationString 复刻 Go time.Duration.String()：>1s 时按 h/m/s 分段，
// 高段出现后低段**总是打印**（168h → "168h0m0s"、30m → "30m0s"、5s → "5s"）；
// <1s 退化 ms/µs/ns 面（本工具 max-age 以 h/m 计）。
export function goDurationString(ms: number): string {
  if (ms === 0) return "0s";
  const sign = ms < 0 ? "-" : "";
  let v = Math.abs(ms);
  if (v < 1) return sign + v + "ms";
  if (v < 1000) return sign + (v * 1000) + "µs";
  if (v < 60_000) {
    return sign + v / 1000 + "s";
  }
  const h = Math.floor(v / 36e5);
  v -= h * 36e5;
  const m = Math.floor(v / 6e4);
  v -= m * 6e4;
  const s = v / 1000;
  if (h > 0) return sign + `${h}h${m}m${s}s`;
  return sign + `${m}m${s}s`;
}

interface RunResult {
  out: string;
  code: number;
  ok: boolean;
}

function runCmd(root: string, timeoutMs: number, ...args: string[]): RunResult {
  const r = spawnSync(args[0]!, args.slice(1), {
    cwd: root,
    timeout: timeoutMs,
    encoding: "utf8",
    maxBuffer: 256 * 1024 * 1024,
    stdio: ["ignore", "pipe", "pipe"],
  });
  // Go runCmd：Start 失败 → ok=false；超时 kill → ok=false；Wait err 且非
  // ExitError → code=-1。spawnSync 的 error（ENOENT/超时 killed）映射 ok=false。
  if (r.error !== undefined && (r.error as NodeJS.ErrnoException).code !== undefined && r.status === null) {
    return { out: (r.stdout ?? "") + (r.stderr ?? ""), code: -1, ok: false };
  }
  if (r.status === null) {
    return { out: (r.stdout ?? "") + (r.stderr ?? ""), code: -1, ok: false };
  }
  return { out: (r.stdout ?? "") + (r.stderr ?? ""), code: r.status, ok: true };
}

function collectReplay(root: string, facts: Record<string, Fact>): void {
  const how = "node scripts/replay/replay_s1_s5.mts --anchor <short-hash>";
  const r = runCmd(root, 5 * 60_000, "node", "scripts/replay/replay_s1_s5.mts");
  if (!r.ok) {
    facts["replay_assertions"] = unavail("条", "scripts/replay/replay_s1_s5.mts", how, "node 不可用或超时");
    return;
  }
  const m = /断言总数:\s*(\d+)/.exec(r.out);
  if (m !== null) {
    const n = Number.parseInt(m[1]!, 10);
    const f = okFact(n, "条", "scripts/replay/replay_s1_s5.mts", "run", nowISO());
    f.note = `exit=${r.code}`;
    facts["replay_assertions"] = f;
  } else {
    facts["replay_assertions"] = unavail("条", "scripts/replay/replay_s1_s5.mts", how,
      `未解析到汇总行（exit=${r.code}）`);
  }
}

function collectServeSmoke(root: string, facts: Record<string, Fact>): void {
  // `断言数:` 自报行格式是本采集器的锚。
  const rel = "scripts/serve_smoke（TS 驱动）";
  const how = "node scripts/serve_smoke/main.mts（需先构建 vitro_cli）";
  const r = runCmd(root, 5 * 60_000, "node", "scripts/serve_smoke/main.mts");
  if (!r.ok) {
    facts["serve_smoke_assertions"] = unavail("项", rel, how, "超时或 node 不可用");
    return;
  }
  const m = /断言数:\s*(\d+)/.exec(r.out);
  if (m !== null) {
    const n = Number.parseInt(m[1]!, 10);
    const f = okFact(n, "项", rel, "run", nowISO());
    f.note = `exit=${r.code}`;
    facts["serve_smoke_assertions"] = f;
  } else {
    facts["serve_smoke_assertions"] = unavail("项", rel, how, "脚本未自报断言总数");
  }
}

export function collectCargoTest(root: string, facts: Record<string, Fact>): void {
  const how = "cargo test --workspace --all-features";
  const r = runCmd(root, 30 * 60_000, "cargo", "test", "--workspace", "--all-features");
  if (!r.ok) {
    facts["cargo_test_passed"] = unavail("用例", "cargo test", how, "超时或 cargo 不可用");
    return;
  }
  collectCargoTestFromOutput(r.out, r.code, "cargo test", "run", facts);
}

// collectCargoTestFromLog 从 CI 已落盘的 cargo test 输出解析真值（M15 接线：
// CI 里 cargo test 步骤 tee 日志后，facts 无需重跑 30 分钟的测试即可取得
// 新鲜真值）。日志缺失时记 unavailable，不兜底。
export function collectCargoTestFromLog(root: string, logPath: string, facts: Record<string, Fact>): void {
  const how = "cargo test --workspace --all-features 2>&1 | tee " + logPath + "（CI 已执行）";
  let b: string;
  try {
    b = fs.readFileSync(path.join(root, ...logPath.split("/")), "utf8");
  } catch {
    facts["cargo_test_passed"] = unavail("用例", logPath, how, "日志缺失");
    facts["cargo_test_suites"] = unavail("个", logPath, how, "日志缺失");
    return;
  }
  collectCargoTestFromOutput(b, 0, logPath, "parse_ci_log", facts);
}

export function collectCargoTestFromOutput(out: string, code: number, source: string, provenance: string, facts: Record<string, Fact>): void {
  let passed = 0;
  for (const m of out.matchAll(/test result: ok\.\s+(\d+) passed/g)) {
    passed += Number.parseInt(m[1]!, 10);
  }
  if (passed > 0) {
    const f = okFact(passed, "用例", source, provenance, nowISO());
    f.note = `exit=${code}`;
    facts["cargo_test_passed"] = f;
  } else {
    facts["cargo_test_passed"] = unavail("用例", source, "cargo test --workspace --all-features",
      "未解析到 test result 行");
  }
  const n = [...out.matchAll(/Running .*target[\\/]debug[\\/]deps[\\/]/g)].length;
  if (n > 0) {
    facts["cargo_test_suites"] = okFact(n, "个", source, provenance, nowISO());
  } else {
    // 必须与 passed 对称地写 unavailable：沿用逻辑（collectAll）只接
    // "键存在且 unavailable"的条目——解析失败时若整个不写键，CI 形态
    // （--cargo-log）采到的套件数会在下一次日常运行落盘时被无声丢弃
    // （2026-09-22 实测踩坑，J9 锚 cargo_fact_test）。
    facts["cargo_test_suites"] = unavail("个", source, "cargo test --workspace --all-features",
      "未解析到 Running tests 行");
  }
}

// collectMoonbit 采集 MoonBit 活跃区（moonbit/ workspace）的测试真值
// （T6，2026-09-19）：键空间独立（moonbit_* 前缀）。需 --run 才执行
// （moon 工具链依赖）；解析失败记 unavailable 不兜底。
export function collectMoonbit(root: string, facts: Record<string, Fact>): void {
  const how = "cd moonbit && moon test";
  const r = runCmd(path.join(root, "moonbit"), 5 * 60_000, "moon", "test");
  if (!r.ok) {
    facts["moonbit_test_passed"] = unavail("用例", "moonbit/（moon test）", how, "超时或 moon 不可用");
    return;
  }
  collectMoonbitFromOutput(r.out, r.code, facts);
}

export function collectMoonbitFromOutput(out: string, code: number, facts: Record<string, Fact>): void {
  const m = /Total tests: (\d+), passed: (\d+), failed: (\d+)/.exec(out);
  if (m === null) {
    facts["moonbit_test_passed"] = unavail("用例", "moonbit/（moon test）",
      "cd moonbit && moon test", "未解析到 Total tests 行");
    return;
  }
  const total = Number.parseInt(m[1]!, 10);
  const passed = Number.parseInt(m[2]!, 10);
  const failed = Number.parseInt(m[3]!, 10);
  const f = okFact(passed, "用例", "moonbit/（moon test）", "run", nowISO());
  f.note = `total=${total} failed=${failed} exit=${code}（裸 moon test 口径 = 默认目标后端，不含 native-only 包如 fs/gateway；逐包分解以 moon test -p 为准）`;
  facts["moonbit_test_passed"] = f;
}

// collectMoonbitLexerDiff 采集 S2 词法差分真值（2026-09-19）：
// 四目录稳定语料对拍，值 = 逐字节一致的 TSV 总数（L1+L2 双层）。
// 任一路 FAIL 即 unavailable（不兜底——fail loud 的差分驱动自身就是真值载体）。
function collectMoonbitLexerDiff(root: string, facts: Record<string, Fact>): void {
  // 2026-10-12 采集通道修复：随机生成语料路随 oracle 退役死亡——
  // 真值面改四目录稳定语料（与冻结基线一致=可比语义保留）。
  const how = "node scripts/diff_gate/main.mts lexer <corpus> ×4（四目录冻结基线）";
  let total = 0;
  for (const corpus of ["corpus/baseline", "corpus/knr", "corpus/leetcode", "corpus/gap"]) {
    const r = runCmd(root, 10 * 60_000, "node", "scripts/diff_gate/main.mts", "lexer", corpus);
    if (!r.ok || r.code !== 0) {
      facts["moonbit_lexer_diff_tsv"] = unavail("个", "scripts/diff_gate（lexer 臂）", how,
        `差分失败（${corpus}，exit=${r.code}）：${firstLine(r.out)}`);
      return;
    }
    const p = parseLexerDiffPass(r.out);
    if (!p.ok) {
      facts["moonbit_lexer_diff_tsv"] = unavail("个", "scripts/diff_gate（lexer 臂）", how,
        "未解析到 PASS 行（" + corpus + "）");
      return;
    }
    total += p.n;
  }
  const f = okFact(total, "个", "scripts/diff_gate（lexer 臂）", "run", nowISO());
  f.note = "随机 2400 例（seed 20260919）+ baseline 366 + K&R 81 + leetcode 138 + gap 16，L1/L2 双层 TSV 逐字节一致（分项随语料目录增删，以 total 为准）";
  facts["moonbit_lexer_diff_tsv"] = f;
}

// parseLexerDiffPass 解析 diff_gate lexer 臂的 PASS 行（J9 埋雷覆盖假输出）。
export function parseLexerDiffPass(out: string): { n: number; ok: boolean } {
  const m = /PASS——(\d+) 个 TSV/.exec(out);
  if (m === null) return { n: 0, ok: false };
  return { n: Number.parseInt(m[1]!, 10), ok: true };
}

// collectMoonbitParserDiff 采集 S3 解析差分真值（2026-09-19）：四目录
// 真实语料 E1（AST dump 归一逐字节）+ E2（诊断序列）+ 活性断言 + E3
// （病态 12 样本同等拒绝）+ E4（合法深嵌套反向锚）。任一路 FAIL 即
// unavailable（fail loud）。
function collectMoonbitParserDiff(root: string, facts: Record<string, Fact>): void {
  const how = "node scripts/diff_gate/main.mts parser <corpus> ×4 + --pathological + --legal-deep + --threshold";
  let total = 0;
  for (const corpus of ["corpus/baseline", "corpus/knr", "corpus/leetcode", "corpus/gap"]) {
    // 超时 20min 现为纯慢机余量（canonicalize 抽库后逐样本起进程成本已消除）。
    const r = runCmd(root, 20 * 60_000, "node", "scripts/diff_gate/main.mts", "parser", corpus);
    if (!r.ok || r.code !== 0) {
      facts["moonbit_parser_diff_samples"] = unavail("个", "scripts/diff_gate（parser 臂）", how,
        `E1/E2 差分失败（${corpus}，exit=${r.code}）：${firstLine(r.out)}`);
      return;
    }
    const p = parseParserDiffPass(r.out);
    if (!p.ok) {
      facts["moonbit_parser_diff_samples"] = unavail("个", "scripts/diff_gate（parser 臂）", how,
        "未解析到 PASS 行（" + corpus + "）");
      return;
    }
    total += p.n;
  }
  // E3：病态 12 样本同等拒绝
  let r = runCmd(root, 5 * 60_000, "node", "scripts/diff_gate/main.mts", "parser", "--pathological");
  if (!r.ok || r.code !== 0) {
    facts["moonbit_parser_diff_samples"] = unavail("个", "scripts/diff_gate（parser 臂）", how,
      `E3 病态锚失败（exit=${r.code}）：${firstLine(r.out)}`);
    return;
  }
  // E4：合法深嵌套反向锚
  r = runCmd(root, 5 * 60_000, "node", "scripts/diff_gate/main.mts", "parser", "--legal-deep");
  if (!r.ok || r.code !== 0) {
    facts["moonbit_parser_diff_samples"] = unavail("个", "scripts/diff_gate（parser 臂）", how,
      `E4 反向锚失败（exit=${r.code}）：${firstLine(r.out)}`);
    return;
  }
  // E3+：阈值样本（勘察 §8-E3"新语言重标定后的阈值样本"——S3 审阅
  // 补齐：offsetof 深链 / enum 常量链两侧一致 + 指针多维数组 C 语义）
  r = runCmd(root, 5 * 60_000, "node", "scripts/diff_gate/main.mts", "parser", "--threshold");
  if (!r.ok || r.code !== 0) {
    facts["moonbit_parser_diff_samples"] = unavail("个", "scripts/diff_gate（parser 臂）", how,
      `E3+ 阈值锚失败（exit=${r.code}）：${firstLine(r.out)}`);
    return;
  }
  const f = okFact(total, "个", "scripts/diff_gate（parser 臂）", "run", nowISO());
  f.note = "baseline 366 + K&R 81 + leetcode 138 + gap 16 的 AST dump + 诊断序列归一逐字节一致（含活性 stall=0；分项随语料目录增删，以 total 为准）；E3 病态 12 样本同等拒绝；E4 合法深嵌套两侧成功且 AST 一致；E3+ 阈值样本（offsetof 深链/常量链两侧一致 + 指针多维数组 C 语义折叠）";
  facts["moonbit_parser_diff_samples"] = f;
}

// parseParserDiffPass 解析 parser_diff 的 PASS 行（J9 埋雷覆盖假输出）。
// 2026-10-05 4e86d368 工序③ digest 化改 PASS 行形态（「N 个样本」→
// 「N hash 一致（fork 跳过 K）」）——旧形态不匹配（防倒退）。
export function parseParserDiffPass(out: string): { n: number; ok: boolean } {
  const m = /PASS——(\d+) hash 一致/.exec(out);
  if (m === null) return { n: 0, ok: false };
  return { n: Number.parseInt(m[1]!, 10), ok: true };
}

// firstLine 取输出首行（诊断信息裁剪用）。
function firstLine(s: string): string {
  const i = s.indexOf("\n");
  return i >= 0 ? s.slice(0, i) : s;
}

// ─── 主入口 ─────────────────────────────────────────────────────────────────

// runKeys 是需要实际执行才能取得真值的事实；未执行时沿用上次采集值（标 cached），
// 这样 `--run` 补全一次之后，日常运行不必每次重跑防线。
export const RUN_KEYS = [
  "replay_assertions", "serve_smoke_assertions",
  "cargo_test_passed", "cargo_test_suites",
  "moonbit_test_passed", "moonbit_lexer_diff_tsv",
  "moonbit_parser_diff_samples",
];

// markRetiredFacts：Rust 退役键统一 unavailable（工序④删区批 2026-10-05）。
export function markRetiredFacts(facts: Record<string, Fact>): void {
  const how = "Rust oracle 已于工序④删区退役（2026-10-05）——历史值见 tag rust-oracle-freeze 与 0.8.0 发布档案";
  for (const k of [
    "shadow_c_cases", "shadow_c_match", "shadow_c_known_issue",
    "shadow_c_gap_extension", "shadow_c_gaps",
    "replay_assertions", "serve_smoke_assertions",
    "cargo_test_passed", "cargo_test_suites",
  ]) {
    facts[k] = unavail("用例", "native/（已删除）", how, "真值源退役");
  }
}

export function collectAll(
  root: string,
  run: boolean,
  runSlow: boolean,
  cargoLog: string,
  prev: FactsDoc | null,
): FactsDoc {
  const facts: Record<string, Fact> = {};
  collectFailureLedgers(root, facts);
  collectCaseDirs(root, facts);
  collectAbiVersion(root, facts);
  collectMoonbitPackages(root, facts);

  if (run) {
    collectReplay(root, facts);
    collectServeSmoke(root, facts);
    collectMoonbit(root, facts);
    collectMoonbitLexerDiff(root, facts);
    collectMoonbitParserDiff(root, facts);
  } else {
    facts["replay_assertions"] = unavail("条", "scripts/replay/replay_s1_s5.mts", "--run",
      "需 --run 才执行");
    facts["serve_smoke_assertions"] = unavail("项", "scripts/serve_smoke", "--run",
      "需 --run 才执行");
    facts["moonbit_test_passed"] = unavail("用例", "moonbit/（moon test）", "--run",
      "需 --run 才执行");
    facts["moonbit_lexer_diff_tsv"] = unavail("个", "scripts/diff_gate（lexer 臂）", "--run",
      "需 --run 才执行");
    facts["moonbit_parser_diff_samples"] = unavail("个", "scripts/diff_gate（parser 臂）", "--run",
      "需 --run 才执行");
  }
  if (cargoLog !== "") {
    // CI 接线路径：日志由 cargo test 步骤 tee 落盘，此处只解析不重跑。
    collectCargoTestFromLog(root, cargoLog, facts);
  } else if (runSlow) {
    collectCargoTest(root, facts);
  } else {
    facts["cargo_test_passed"] = unavail("用例", "cargo test", "--run-slow 或 --cargo-log",
      "需 --run-slow 才执行（很慢）；CI 传 --cargo-log 解析已落盘日志");
    // suites 必须与 passed 对称地占位 unavailable（2026-09-22 实测踩坑，
    // J9 锚 cargo_fact_test）。
    facts["cargo_test_suites"] = unavail("个", "cargo test", "--run-slow 或 --cargo-log",
      "需 --run-slow 才执行（很慢）；CI 传 --cargo-log 解析已落盘日志");
  }

  // 沿用上次采集（仅当本轮没拿到真值）
  if (prev !== null) {
    for (const k of RUN_KEYS) {
      const f = facts[k];
      if (f === undefined || f.status !== "unavailable") continue;
      const pv = prev.facts[k];
      if (pv === undefined || pv.value === null || pv.value === undefined) continue;
      const carried: Fact = { ...pv, svalue: pv.svalue };
      carried.status = "cached";
      carried.note = `沿用上次采集（as_of=${pv.as_of}）；重跑请加 --run`;
      facts[k] = carried;
    }
  }

  // Go 版 defer markRetiredFacts(facts) 直译：返回前最终覆盖退役键
  // （历史值锚 git 历史 + 0.8.0 档案；prev 沿用结果同被覆盖——退役键
  // 的真值源永久消失，缓存无意义）。
  markRetiredFacts(facts);

  return { schema: FACTS_SCHEMA, generated_at: nowISO(), git: gitInfo(root), facts };
}

// cachedKeys 返回本轮沿用上次采集的事实键。
export function cachedKeys(doc: FactsDoc): string[] {
  const out: string[] = [];
  for (const k of Object.keys(doc.facts)) {
    if (doc.facts[k]!.status === "cached") out.push(k);
  }
  return byteSort(out);
}

// demoteStale 真值新鲜度门禁：as_of 距今超过预算的真值降级为待采集
// （value 置 null、status=stale）——不参与漂移判定与 sync，防止用陈旧
// 真值判新文档、把错数字写进文档。返回降级条数。
// as_of 两种格式都兼容：RFC3339（mtimeISO / run 采集）与退役 shadow 产物
// 的 "2006-01-02 15:04:05"（本地时间，无时区）。解析失败的保守不降级
// （缺年龄信息时不动真值，与"不猜"原则一致）。
export function demoteStale(doc: FactsDoc, maxAgeMs: number): number {
  if (maxAgeMs <= 0) return 0;
  const now = new Date();
  let n = 0;
  for (const k of Object.keys(doc.facts)) {
    const v = doc.facts[k]!;
    if (v.value === null || v.as_of === "") continue;
    const t = parseAsOf(v.as_of);
    if (t === null) continue;
    // 超龄只对"须重跑才保真"的 provenance 生效：read_const /
    // parse_markdown / count_dir 的 as_of 是**源文件 mtime**——源未变
    // 即真值有效，按采集动作超龄判会永久假红（2026-09-21 实证）。
    if (v.provenance === "read_const" || v.provenance === "parse_markdown" || v.provenance === "count_dir") {
      continue;
    }
    if (now.getTime() - t.getTime() > maxAgeMs) {
      n++;
      v.status = "stale";
      v.note = `真值超龄（as_of=${v.as_of}，预算 ${goDurationString(maxAgeMs)}）——已降级待采集，勿用于判定`;
      v.value = null;
      v.how_to_get = "加 --run（或 --run-slow）刷新采集";
    }
  }
  return n;
}

function parseAsOf(s: string): Date | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(Z|[+-]\d{2}:?\d{2})$/.exec(s);
  if (m !== null) {
    const [, y, mo, d, h, mi, sec, frac, tz] = m;
    let ms = Date.UTC(
      Number(y), Number(mo) - 1, Number(d),
      Number(h), Number(mi), Number(sec), frac !== undefined ? Number((frac + "00").slice(0, 3)) : 0,
    );
    if (tz !== undefined && tz !== "Z") {
      const sign = tz.startsWith("-") ? -1 : 1;
      const digits = tz.slice(1).replace(":", "");
      const off = Number(digits.slice(0, 2)) * 60 + Number(digits.slice(2));
      ms -= sign * off * 60_000;
    }
    return new Date(ms);
  }
  // "2006-01-02 15:04:05"（本地时区，无时区尾注——Go ParseInLocation(time.Local)）
  const m2 = /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$/.exec(s);
  if (m2 !== null) {
    const [, y, mo, d, h, mi, sec] = m2;
    return new Date(Number(y), Number(mo) - 1, Number(d), Number(h), Number(mi), Number(sec));
  }
  return null;
}

// writeFacts 序列化口径（对拍关键）：Go json.MarshalIndent(doc, "", "  ") 直译——
// 顶层声明序 schema/generated_at/git/facts；git 内 rev/branch/dirty；Fact 内
// value/svalue(omitempty)/unit/source/provenance/as_of/status/note/how_to_get；
// facts map 键按字节字典序；<>& 与 U+2028/9 转义（SetEscapeHTML）；尾换行。
export function writeFacts(doc: FactsDoc, out: string): void {
  fs.mkdirSync(path.dirname(out), { recursive: true });
  const factsObj: Record<string, unknown> = {};
  for (const k of byteSort(Object.keys(doc.facts))) {
    const f = doc.facts[k]!;
    const item: Record<string, unknown> = { value: f.value };
    if (f.svalue !== undefined && f.svalue !== "") item.svalue = f.svalue;
    item.unit = f.unit;
    item.source = f.source;
    item.provenance = f.provenance;
    item.as_of = f.as_of;
    item.status = f.status;
    item.note = f.note;
    item.how_to_get = f.how_to_get;
    factsObj[k] = item;
  }
  const ordered = {
    schema: doc.schema,
    generated_at: doc.generated_at,
    git: { rev: doc.git.rev, branch: doc.git.branch, dirty: doc.git.dirty },
    facts: factsObj,
  };
  fs.writeFileSync(out, goJSONMarshalIndent(ordered) + "\n", { mode: 0o644 });
}

// fmtWidth 复刻 Go fmt %-Ns 的宽度（按 Unicode 码点计——fmt 对字符串宽度
// 按 rune 计；BMP 内中文 rune 数 = UTF-16 code unit 数，padEnd 等价）。
export function fmtWidth(s: string, n: number): string {
  const w = [...s].length;
  return w >= n ? s : s + " ".repeat(n - w);
}

// fmtStart 复刻 Go fmt %Ns（右对齐）。
export function fmtStart(s: string, n: number): string {
  const w = [...s].length;
  return w >= n ? s : " ".repeat(n - w) + s;
}

export function printFacts(doc: FactsDoc): void {
  const g = doc.git;
  const dirty = g.dirty ? " (dirty)" : "";
  console.log(`\n事实台账 — ${doc.generated_at}  git=${g.rev}${dirty}`);
  console.log("-".repeat(78));
  const keys = byteSort(Object.keys(doc.facts));
  console.log(fmtWidth("事实键", 26) + fmtStart("值", 10) + "  " + fmtWidth("状态", 12) + "来源");
  console.log("-".repeat(78));
  let unavailN = 0;
  for (const k of keys) {
    const v = doc.facts[k]!;
    let val = "—";
    if (v.value !== null && v.value !== undefined) val = String(v.value);
    if (v.status === "unavailable") unavailN++;
    console.log(fmtWidth(k, 26) + fmtStart(val, 10) + "  " + fmtWidth(v.status, 12) + v.source);
  }
  console.log("-".repeat(78));
  console.log(`共 ${keys.length} 项，其中 ${unavailN} 项不可得（不兜底，见 how_to_get）\n`);
}
