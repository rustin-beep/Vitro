#!/usr/bin/env node
// engine —— #368 第三层试点：MoonBit 引擎面 diff 级 mutant 闸（typeck 先行）。
//
// 形态（试点观察期，report-only）：对 diff 触达的 moonbit/<pkg>/*.mbt 改动行
// 生成**行级算子突变**（比较符/边界/逻辑联结/布尔常量/整数字面量 ±1——
// MoonBit 无现成 mutation 工具，文本算子是可落地的最近似），逐突变体跑
// 两级杀阵：
//   第一级 `moon test -p vitro/engine/<pkg>`（wbtest 锚——增量编译只重建
//   改动包，~35s/突变体）；
//   第二级（仅第一级全绿时）`diff_gate typeck corpus/baseline`（digest 锚
//   ——#368 突变抽查 M3 实证：锚可能在 digest 不在 wbtest，杀阵必须全锚面）。
// survived = 两级全绿 ⇒ 零锚面清单（新扩散面机判定义）。**survived 不阻断**
// （观察期人工定性：真缺口补锚 / 等价突变入 engine_equivalents.json 白名单
// ——耦合对〔双保险各删一侧无行为差〕成对登记，#368 实测 M4/M12 形态）。
//
// 关键纪律：
//   - 快照还原而非 git checkout（工作区可能有并发未提交改动——MoonBit 侧
//     批经常带 wbtest 未提交件，checkout 会抹掉）；
//   - 每次写入后 sleep ≥1.2s（moon 增量编译按 mtime，同秒改写漏检假绿）；
//   - 编译失败 ≠ killed：moon test 输出无 "Total tests:" 行判 CompileError，
//     该突变体弃置单列（防「文本算子打坏语法被当成有锚」）；
//   - 白名单匹配（file + op + 行号 ±2）豁免已定性等价突变，J9 先证会报再豁免。
//
// 用法（cwd 任意，仓库根判定同 capi；MOON_CC 建议外部设 clang——digest 级
// 走 moon run native）：
//   node scripts/mutation_gate/engine.mts --pkg typeck [--base origin/master] [--files expr.mts,...]
//   node scripts/mutation_gate/engine.mts --pkg typeck --files typeck/context.mbt --only typeck/context.mbt:186  # J9 定点重放
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { projectRoot, fatal } from "../internal/capi.mts";

/** 算子：在单个 token 出现点上的文本替换 */
export interface Mutant {
  file: string; // 相对 moonbit/ 的 posix 路径（pkg/xxx.mbt）
  line: number; // 1-based
  col: number; // 1-based（token 起点）
  from: string;
  to: string;
  op: string;
}

const OPS: Array<{ op: string; from: string; to: string }> = [
  { op: "EQ_TO_NEQ", from: "==", to: "!=" },
  { op: "NEQ_TO_EQ", from: "!=", to: "==" },
  { op: "LT_TO_LE", from: "<", to: "<=" },
  { op: "GT_TO_GE", from: ">", to: ">=" },
  { op: "AND_TO_OR", from: "&&", to: "||" },
  { op: "OR_TO_AND", from: "||", to: "&&" },
  { op: "TRUE_TO_FALSE", from: "true", to: "false" },
  { op: "FALSE_TO_TRUE", from: "false", to: "true" },
];

/** 行内裸 token 出现位置（不在字符串/注释内、不与相邻字符构成更长 token）。 */
export function findTokenOccurrences(line: string, token: string): number[] {
  const cols: number[] = [];
  const code = codePart(line);
  for (let i = 0; i + token.length <= code.length; i++) {
    if (code.slice(i, i + token.length) !== token) continue;
    if (isInsideString(code, i)) continue;
    const prev = code[i - 1] ?? "";
    const next = code[i + token.length] ?? "";
    if (/[A-Za-z0-9_]/.test(prev) || /[A-Za-z0-9_]/.test(next)) continue;
    if (token === "<" && (prev === "<" || prev === "=" || prev === "-" || next === "=" || next === "<")) continue;
    if (token === ">" && (prev === ">" || prev === "=" || next === "=" || next === ">")) continue;
    if (token === "=" && (prev === "=" || prev === "!" || prev === "<" || prev === ">" || next === "=")) continue;
    if (token === "!" && next === "=") continue;
    if (token === "|" && next === "|") continue;
    if (token === "&" && next === "&") continue;
    cols.push(i + 1);
  }
  return cols;
}

/** 剥行内注释：返回首个字符串外 `//` 之前的部分（不改变前缀长度）。 */
export function codePart(line: string): string {
  let inStr: string | null = null;
  for (let i = 0; i < line.length; i++) {
    const c = line[i] ?? "";
    if (inStr !== null) {
      if (c === "\\") i++;
      else if (c === inStr) inStr = null;
      continue;
    }
    if (c === '"' || c === "'") inStr = c;
    else if (c === "/" && line[i + 1] === "/") return line.slice(0, i);
  }
  return line;
}

/** 位置是否在字符串字面量内（行内近似——MoonBit 串单行足够）。 */
export function isInsideString(code: string, pos: number): boolean {
  let inStr: string | null = null;
  for (let i = 0; i < pos; i++) {
    const c = code[i] ?? "";
    if (inStr !== null) {
      if (c === "\\") i++;
      else if (c === inStr) inStr = null;
      continue;
    }
    if (c === '"' || c === "'") inStr = c;
  }
  return inStr !== null;
}

/** 整数字面量 ±1 突变（跳过字符串内与 0x/小数邻接位）。 */
export function findIntLiteralMutants(line: string): Array<{ col: number; from: string; to: string }> {
  const code = codePart(line);
  const out: Array<{ col: number; from: string; to: string }> = [];
  const re = /\b\d+\b/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(code)) !== null) {
    if (isInsideString(code, m.index)) continue;
    const prev = code[m.index - 1] ?? "";
    if (prev === "x" || prev === "X" || prev === ".") continue;
    const raw = m[0] ?? "";
    out.push({ col: m.index + 1, from: raw, to: String(Number(raw) + 1) });
  }
  return out;
}

/** 由「文件行数组 + 变更行号集」生成全部突变体（确定性：行序→列序→算子序）。 */
export function generateMutants(lines: string[], changedLines: Set<number>, file: string): Mutant[] {
  const mutants: Mutant[] = [];
  for (const ln of [...changedLines].sort((a, b) => a - b)) {
    const line = lines[ln - 1] ?? "";
    if (line.trim().startsWith("//") || line.trim().startsWith("*") || line.trim().startsWith("/*")) continue;
    for (const op of OPS) {
      for (const col of findTokenOccurrences(line, op.from)) {
        mutants.push({ file, line: ln, col, from: op.from, to: op.to, op: op.op });
      }
    }
    for (const it of findIntLiteralMutants(line)) {
      mutants.push({ file, line: ln, col: it.col, from: it.from, to: it.to, op: "INT_PLUS1" });
    }
  }
  return mutants;
}

export function applyMutant(lines: string[], mu: Mutant): string[] {
  const line = lines[mu.line - 1] ?? "";
  const idx = mu.col - 1;
  const replaced = line.slice(0, idx) + mu.to + line.slice(idx + mu.from.length);
  const out = [...lines];
  out[mu.line - 1] = replaced;
  return out;
}

export interface EquivEntry {
  file: string;
  op: string;
  line: number; // 与突变体行号差 ≤2 即匹配（diff 位移容差）
  reason: string;
  pair?: string; // 耦合对另一侧描述
}

export function isWhitelisted(mu: Mutant, list: EquivEntry[]): EquivEntry | null {
  return list.find((e) => e.file === mu.file && e.op === mu.op && Math.abs(e.line - mu.line) <= 2) ?? null;
}

function sleep(ms: number): void {
  const t0 = Date.now();
  while (Date.now() - t0 < ms) {
    // 同步占位（脚本语境）
  }
}

function run(cmd: string, args: string[], opts: { cwd: string }): { status: number | null; stdout: string; stderr: string } {
  const r = spawnSync(cmd, args, { cwd: opts.cwd, encoding: "utf8", env: process.env });
  return { status: r.status, stdout: r.stdout ?? "", stderr: r.stderr ?? "" };
}

export interface MutantResult {
  mutant: Mutant;
  verdict: "killed-wbtest" | "killed-digest" | "survived" | "compile-error" | "whitelisted";
  killedBy?: string;
}

function usage(msg?: string): never {
  if (msg !== undefined) process.stderr.write("参数错: " + msg + "\n");
  process.stderr.write(
    "用法: node scripts/mutation_gate/engine.mts --pkg typeck [--base origin/master] [--files typeck/expr.mts,...] [--max-mutants N] [--only file.mbt:line]\n",
  );
  process.exit(2);
}

function main(): void {
  const argv = process.argv.slice(2);
  let pkg = "";
  let base = "origin/master";
  let filesOverride: string[] | null = null;
  let maxMutants = 40;
  let onlyLine: string | null = null;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i] ?? "";
    const next = argv[i + 1];
    if (a === "--pkg" && next) { pkg = next; i++; }
    else if (a === "--base" && next) { base = next; i++; }
    else if (a === "--files" && next) { filesOverride = next.split(",").map((s) => s.trim()).filter(Boolean); i++; }
    else if (a === "--max-mutants" && next) { maxMutants = Number(next); i++; }
    else if (a === "--only" && next) { onlyLine = next; i++; }
    else usage("未知参数或缺值: " + a);
  }
  if (pkg === "") usage("--pkg 必填（试点=typeck）");
  const root = projectRoot();
  const moonbitDir = path.join(root, "moonbit");
  const enginePkg = `vitro/engine/${pkg}`;
  const outDir = path.join(root, "tmp", "mutation_gate_engine");
  fs.mkdirSync(outDir, { recursive: true });

  // 1) 目标文件与行号（--files 路径相对 moonbit/，如 typeck/expr.mbt）
  const targets: Array<{ file: string; changed: Set<number> }> = [];
  if (filesOverride !== null) {
    for (const f of filesOverride) targets.push({ file: normalize(f), changed: new Set() });
  } else {
    const diff = run("git", ["-C", root, "diff", "--unified=0", base, "HEAD", "--", `moonbit/${pkg}`], { cwd: root });
    if (diff.status !== 0) fatal("git diff 失败: " + diff.stderr);
    targets.push(...parseEngineDiff(diff.stdout));
  }
  const realTargets = targets.filter((t) => !t.file.endsWith("_wbtest.mbt") && !t.file.endsWith("pkg.generated.mbti"));
  if (realTargets.length === 0) {
    process.stdout.write(`engine-mutant-gate[${pkg}]: 无可突变面（diff 零源行）\n`);
    return;
  }

  // 2) 突变体生成（--files 无行集 → 整文件；白名单豁免；--only 定点过滤）
  const snapshots = new Map<string, string[]>();
  const all: Mutant[] = [];
  for (const t of realTargets) {
    const abs = path.join(moonbitDir, t.file);
    const lines = fs.readFileSync(abs, "utf8").split("\n");
    snapshots.set(t.file, lines);
    const changed = t.changed.size > 0 ? t.changed : new Set(lines.map((_, i) => i + 1));
    all.push(...generateMutants(lines, changed, t.file));
  }
  const equivPath = path.join(root, "scripts", "mutation_gate", "engine_equivalents.json");
  const equivs: EquivEntry[] = fs.existsSync(equivPath)
    ? (JSON.parse(fs.readFileSync(equivPath, "utf8")) as EquivEntry[])
    : [];
  const onlyParts = onlyLine !== null ? onlyLine.split(":") : null;
  const onlyFile = onlyParts?.[0] ?? "";
  const onlyLn = onlyParts !== null && onlyParts.length > 1 ? Number(onlyParts[1]) : -1;
  const whitelistedCount = all.filter((mu) => isWhitelisted(mu, equivs) !== null).length;
  const selected = all
    .filter((mu) => onlyParts === null || (mu.file === onlyFile && mu.line === onlyLn))
    .filter((mu) => isWhitelisted(mu, equivs) === null)
    .slice(0, maxMutants);
  process.stdout.write(
    `engine-mutant-gate[${pkg}]: 目标 ${realTargets.length} 文件 / 突变体 ${all.length}（白名单豁免 ${whitelistedCount}，本轮跑 ${selected.length}）\n`,
  );

  // 3) 杀阵基线先验（红基线上判锚 = 全部假 survived）
  const baseline = run("moon", ["test", "-p", enginePkg], { cwd: moonbitDir });
  if (baseline.status !== 0 || !baseline.stdout.includes("Total tests:")) {
    fatal(`基线 moon test 红（杀阵先验失败）: exit ${baseline.status}\n${baseline.stdout.slice(-500)}`);
  }

  // 4) 逐突变体：apply → 一级 wbtest → 二级 digest → 快照还原
  const results: MutantResult[] = [];
  try {
    for (const mu of selected) {
      const lines = snapshots.get(mu.file);
      if (lines === undefined) continue;
      const abs = path.join(moonbitDir, mu.file);
      const tag = "  [" + mu.file + ":" + mu.line + ":" + mu.op + " " + mu.from + "→" + mu.to + "] ";
      fs.writeFileSync(abs, applyMutant(lines, mu).join("\n"));
      sleep(1300); // moon mtime 增量漏检防线
      const t1 = run("moon", ["test", "-p", enginePkg], { cwd: moonbitDir });
      fs.writeFileSync(abs, lines.join("\n"));
      if (!t1.stdout.includes("Total tests:")) {
        process.stdout.write(tag + "compile-error\n");
        results.push({ mutant: mu, verdict: "compile-error" });
        continue;
      }
      if (t1.status !== 0) {
        const firstFail = /FAILED:?\s*(.*)/.exec(t1.stdout)?.[1] ?? "";
        process.stdout.write(tag + "killed-wbtest（" + firstFail.slice(0, 70) + "）\n");
        results.push({ mutant: mu, verdict: "killed-wbtest", killedBy: firstFail.slice(0, 90) });
        continue;
      }
      const digest = run(process.execPath, [path.join("scripts", "diff_gate", "main.mts"), "typeck", "corpus/baseline"], {
        cwd: root,
      });
      if (digest.status !== 0) {
        process.stdout.write(tag + "killed-digest\n");
        results.push({ mutant: mu, verdict: "killed-digest", killedBy: "typeck digest" });
      } else {
        process.stdout.write(tag + "SURVIVED\n");
        results.push({ mutant: mu, verdict: "survived" });
      }
    }
  } finally {
    for (const [f, lines] of snapshots) fs.writeFileSync(path.join(moonbitDir, f), lines.join("\n"));
  }

  // 5) 报告
  const by = (v: MutantResult["verdict"]) => results.filter((r) => r.verdict === v);
  const report = {
    pkg,
    mutantsTotal: all.length,
    whitelisted: whitelistedCount,
    ran: results.length,
    killedWbtest: by("killed-wbtest").length,
    killedDigest: by("killed-digest").length,
    survived: by("survived").length,
    compileError: by("compile-error").length,
    survivedList: by("survived").map((r) => `${r.mutant.file}:${r.mutant.line}:${r.mutant.op} ${r.mutant.from}→${r.mutant.to}`),
  };
  fs.writeFileSync(path.join(outDir, "report.json"), JSON.stringify(report, null, 1));
  process.stdout.write(
    `engine-mutant-gate[${pkg}]: killed-wbtest ${report.killedWbtest} / killed-digest ${report.killedDigest} / **survived ${report.survived}** / compile-error ${report.compileError}（report-only 不阻断）；报告 tmp/mutation_gate_engine/report.json\n`,
  );
}

function normalize(p: string): string {
  return p.replaceAll("\\", "/");
}

/** 解析引擎侧 diff：moonbit/<pkg>/xxx.mbt → {file: "<pkg>/xxx.mbt", changed}（wbtest/非 .mbt 剔除）。 */
export function parseEngineDiff(diffText: string): Array<{ file: string; changed: Set<number> }> {
  const out = new Map<string, Set<number>>();
  let current: string | null = null;
  for (const line of diffText.split("\n")) {
    if (line.startsWith("+++ b/")) {
      const f = normalize(line.slice("+++ b/".length));
      const rel = f.startsWith("moonbit/") ? f.slice("moonbit/".length) : f;
      current = rel.endsWith(".mbt") && !rel.endsWith("_wbtest.mbt") ? rel : null;
      if (current !== null && !out.has(current)) out.set(current, new Set());
      continue;
    }
    if (line.startsWith("@@") && current !== null) {
      const m = /\+(\d+)(?:,(\d+))? @@/.exec(line);
      if (m !== null) {
        const start = Number(m[1] ?? 0);
        const count = m[2] === undefined ? 1 : Number(m[2]);
        const set = out.get(current);
        for (let i = 0; i < count && set !== undefined; i++) set.add(start + i);
      }
    }
  }
  return [...out.entries()].map(([file, changed]) => ({ file, changed }));
}

if (normalize(process.argv[1] ?? "").endsWith("mutation_gate/engine.mts")) {
  main();
}
