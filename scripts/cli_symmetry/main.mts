#!/usr/bin/env node
// cli_symmetry：CLI 四子命令参数面对称性冒烟闸（审阅 v2 批 A7 / R1a 处方 R5，2026-11-02）。
//
// 背景（R1a ④ M5「子命令族门禁不对称」形态）：病 87 批给 run 补了未知旗标 fail loud、
// compile/step 跟进（残留⑤/⑦式清单打补丁），**四子命令修了三家漏 api**——`vitro api
// --zz-bogus help` 未知旗标被静默吞（rc=0，用户以为生效）；`api help ping zz-extra`
// 多余位置参数同吞（F4 三形态实测 2026-11-02）。参数面单源 CLI_PROTOCOL_V1 的
// 「fail loud」条目此前零逐命令可执行断言。本闸对 run/compile/step/api × 三臂
// （wasm 壳 / js / native）跑标准探针对拍**声明表**——任何漂移（修复或倒退）都红：
//
//   ① 三臂 rc 必须**彼此一致**（对称性本体——某臂独走即红）
//   ② 三臂 rc 必须等于声明表 want（声明 = 现状快照 + reason；修复后 rc 变化 →
//     与声明分叉 → 红 → 显式改声明（此时 reason 提醒清账/升级为硬锁面））
//   ③ want=4 的条目额外断言输出含 fail loud 字样（未知旗标/多余/用法——防
//     「rc 对但文案撒谎」）
//   ④ 声明表引用的命令/探针不存在（改名）→ 红清账
//
// dump 四家门禁不对称（F5）由 twin_fingerprint 闸静态看守（dump 四家在 CI 零构建，
// 行为探针成本不值——R1a 探针 3 已实证形态）。
//
// 用法（**仓库根**，前置三臂产物在位）：
//   node scripts/cli_symmetry/main.mts             # 报告（矩阵三臂真值）
//   node scripts/cli_symmetry/main.mts -check      # 判定（CI 门禁用）
//   node scripts/cli_symmetry/main.mts --selftest  # J9：声明表双路注入必红
//
// fail loud：产物缺失 → exit 2；判据不过 → exit 1。
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../internal/capi.mts";

export const RULES_PATH = "scripts/cli_symmetry/rules.json";

export interface Probe {
  name: string;
  /** argv 模板：FILE 占位符替换为语料文件 */
  argv: string[];
  note?: string;
}

export interface MatrixCell {
  want: 0 | 4;
  reason?: string;
  issue?: string;
  /** 覆写探针 argv 模板（api 等不收文件的命令面） */
  argv?: string[];
}

export interface RulesDoc {
  schema: number;
  corpus_file: string;
  arms: Record<string, { kind: "node" | "exe"; path: string; argv_prefix?: string[] }>;
  probes: Record<string, Probe>;
  commands: string[];
  matrix: Record<string, MatrixCell>;
}

export interface ArmResult {
  arm: string;
  rc: number;
  out: string;
}

function fatal(msg: string): never {
  throw new Error(`cli_symmetry: ${msg}`);
}

function cellKey(cmd: string, probe: string): string {
  return `${cmd}|${probe}`;
}

/** 定位三臂可执行入口（与 vitro_cli_smoke 同款路径约定）。 */
export function resolveArms(rd: RulesDoc): Record<string, { exe: string; argv: string[] }> {
  const out: Record<string, { exe: string; argv: string[] }> = {};
  for (const [name, arm] of Object.entries(rd.arms)) {
    const p = path.join(projectRoot(), arm.path);
    if (!fs.existsSync(p)) {
      fatal(`前置产物缺失 ${p}（先构建三臂：见 vitro_cli_smoke 头注）`);
    }
    if (arm.kind === "exe") out[name] = { exe: p, argv: [] };
    else out[name] = { exe: process.execPath, argv: [p, ...(arm.argv_prefix ?? [])] };
  }
  return out;
}

/** 跑一臂一探针，返回 (rc, 合流输出)——臂名由 probeCell 装配。 */
export function runArm(arm: { exe: string; argv: string[] }, cmd: string, probeArgv: string[], corpusFile: string): { rc: number; out: string } {
  const argv = [...arm.argv, cmd, ...probeArgv.map((a) => (a === "FILE" ? corpusFile : a))];
  const r = spawnSync(arm.exe, argv, { cwd: projectRoot(), maxBuffer: 16 * 1024 * 1024, input: "" });
  if (r.error !== undefined) fatal(`启动失败 ${arm.exe} ${argv.join(" ")}: ${r.error.message}`);
  const out = `${r.stdout?.toString("utf8") ?? ""}\n${r.stderr?.toString("utf8") ?? ""}`;
  return { rc: r.status ?? -1, out };
}

/** 单元格真值：三臂跑齐（cell.argv 覆写探针模板）。 */
export function probeCell(
  arms: Record<string, { exe: string; argv: string[] }>,
  cmd: string,
  probe: Probe,
  corpusFile: string,
  overrideArgv?: string[],
): ArmResult[] {
  const argv = overrideArgv ?? probe.argv;
  const results: ArmResult[] = [];
  for (const [name, arm] of Object.entries(arms)) {
    const r = runArm(arm, cmd, argv, corpusFile);
    results.push({ arm: name, rc: r.rc, out: r.out });
  }
  return results;
}

/** fail loud 文案字样（审阅 P2-1 收窄，2026-11-02）：对齐四子命令实际输出——run「未知旗标或缺值」/
 * compile「未知旗标或多余参数」/ step「未知旗标：」「多余位置参数」/ api「用法错: …」。
 * 旧形态含裸「用法」过宽（正常 usage 输出也算命中，两臂哑失败可被第三臂的正常 usage 掩盖）。 */
const FAIL_LOUD_RE = /未知旗标|多余位置参数|多余参数|用法错/;

/** 全判据：三臂一致 + 与声明一致 + rc4 须有 fail loud 文案 + 声明引用有效。 */
export function verdict(rd: RulesDoc, cells: Record<string, ArmResult[]>): { ok: boolean; issues: string[] } {
  const issues: string[] = [];
  for (const cmd of rd.commands) {
    for (const [probeName, probe] of Object.entries(rd.probes)) {
      const key = cellKey(cmd, probeName);
      const cell = rd.matrix[key];
      const rs = cells[key];
      if (cell === undefined) {
        issues.push(`[声明缺格] ${key} 无期望声明——新命令/新探针必须全矩阵声明（对称面不许有暗格）`);
        continue;
      }
      if (rs === undefined || rs.length === 0) {
        issues.push(`[真值缺] ${key} 三臂真值未跑齐`);
        continue;
      }
      // ① 三臂一致
      const rcs = new Set(rs.map((r) => r.rc));
      if (rcs.size > 1) {
        issues.push(`[臂间分叉] ${key} 三臂 rc 不一致: ${rs.map((r) => `${r.arm}=${r.rc}`).join(" ")}——对称性本体失守`);
        continue;
      }
      const rc = rs[0]?.rc ?? -1;
      // ② 与声明一致（漂移双向红：修复后忘改声明 / 防线倒退）
      if (rc !== cell.want) {
        const hint = cell.want === 0 ? `声明为现状 rc=0（${cell.reason ?? "?"}）——若已修复请把 want 升为 4 并清 reason（锁面）` : `声明 rc=4（fail loud 契约）——防线倒退或壳映射错`;
        issues.push(`[rc 漂移] ${key} 实测 rc=${rc} ≠ 声明 want=${cell.want}。${hint}`);
      }
      // ③ rc4 须有 fail loud 文案——**every 而非 some**（审阅 P2-1 修复，2026-11-02）：
      // 某臂壳映射 rc=4 却吞文案时 some 放行（两臂哑失败不可见）；三臂壳逻辑单源
      // （cmd/lib/cli），任一臂哑即异常。
      if (cell.want === 4 && rc === 4) {
        const dumb = rs.filter((r) => !FAIL_LOUD_RE.test(r.out)).map((r) => r.arm);
        if (dumb.length > 0) {
          issues.push(`[哑失败] ${key} rc=4 但臂 [${dumb.join(", ")}] 输出无 fail loud 字样（未知旗标/多余位置参数/用法错）——rc 对但文案撒谎`);
        }
      }
      void probe;
    }
  }
  // ④ 声明表僵尸格
  for (const key of Object.keys(rd.matrix)) {
    const [cmd, probeName] = key.split("|");
    if (cmd === undefined || probeName === undefined || !rd.commands.includes(cmd) || rd.probes[probeName] === undefined) {
      issues.push(`[僵尸声明] ${key} 引用的命令/探针不存在（改名后忘删）`);
    }
  }
  return { ok: issues.length === 0, issues };
}

export function allCells(rd: RulesDoc, arms: Record<string, { exe: string; argv: string[] }>): Record<string, ArmResult[]> {
  const corpusFile = path.join(projectRoot(), rd.corpus_file);
  if (!fs.existsSync(corpusFile)) fatal(`语料文件缺失 ${corpusFile}`);
  const out: Record<string, ArmResult[]> = {};
  for (const cmd of rd.commands) {
    for (const [probeName, probe] of Object.entries(rd.probes)) {
      const cell = rd.matrix[cellKey(cmd, probeName)];
      out[cellKey(cmd, probeName)] = probeCell(arms, cmd, probe, corpusFile, cell?.argv);
    }
  }
  return out;
}


export function selftestRun(rd: RulesDoc, cells: Record<string, ArmResult[]>): number {
  const base = verdict(rd, cells);
  if (!base.ok) {
    process.stdout.write("cli_symmetry: selftest ABORT——基线不绿\n");
    for (const s of base.issues) process.stdout.write(`  ${s}\n`);
    return 2;
  }
  let fails = 0;
  // 注入①：把在册 gap 项的声明升 rc4（真值 rc0）→ 与真值分叉必红。
  // 靶子沿革：原用 api|unknown_flag（F4 旗标位）——PR #450 锁面升级（want=4）后
  // 注入失效（want4==真值4 仍绿，2026-11-03 master CI 实锤），换 api|extra_positional
  //（F4 help 早退子面，gap 仍在册 want=0）；该 gap 升级时须再换在册 gap 或删本注入
  {
    const rd2 = JSON.parse(JSON.stringify(rd)) as RulesDoc;
    rd2.matrix["api|extra_positional"]!.want = 4;
    const r = verdict(rd2, cells);
    process.stdout.write(`  注入① api|extra_positional 声明升 rc4（真值 rc0，在册 gap）→ ${!r.ok ? "红（捕获 F4 形态）" : "仍绿（闸失效）"}\n`);
    if (r.ok) fails++;
  }
  // 注入②：把 run|unknown_flag 的声明改成 rc0（真值 rc4）→ 倒退方向分叉红
  {
    const rd2 = JSON.parse(JSON.stringify(rd)) as RulesDoc;
    rd2.matrix["run|unknown_flag"]!.want = 0;
    const r = verdict(rd2, cells);
    process.stdout.write(`  注入② run|unknown_flag 声明降 rc0（真值 rc4）→ ${!r.ok ? "红（捕获）" : "仍绿（闸失效）"}\n`);
    if (r.ok) fails++;
  }
  // 注入③：造臂间分叉（改一格真值）→ 对称性本体红
  {
    const c2 = JSON.parse(JSON.stringify(cells)) as Record<string, ArmResult[]>;
    const first = c2["run|unknown_flag"];
    if (first !== undefined && first.length > 0) first[0]!.rc = 0;
    const r = verdict(rd, c2);
    process.stdout.write(`  注入③ 真值注入臂间分叉 → ${!r.ok ? "红（捕获）" : "仍绿（闸失效）"}\n`);
    if (r.ok) fails++;
  }
  if (fails > 0) {
    process.stdout.write(`cli_symmetry: selftest FAIL——${fails} 路注入未被捕获\n`);
    return 1;
  }
  process.stdout.write("cli_symmetry: selftest PASS——三路注入全部捕获（红），J9 证红成立\n");
  return 0;
}

export function loadRules(p = RULES_PATH): RulesDoc {
  let raw: string;
  try {
    raw = fs.readFileSync(path.join(projectRoot(), p), "utf8");
  } catch (e) {
    fatal(`读规则失败: ${e instanceof Error ? e.message : String(e)}`);
  }
  let rd: RulesDoc;
  try {
    rd = JSON.parse(raw) as RulesDoc;
  } catch (e) {
    fatal(`规则解析失败: ${e instanceof Error ? e.message : String(e)}`);
  }
  if (rd.schema !== 1) fatal(`规则 schema 不支持: ${rd.schema}`);
  return rd;
}

export function main(argv: string[]): number {
  let mode = "check";
  for (const a of argv) {
    if (a === "-check" || a === "--check") mode = "check";
    else if (a === "--selftest" || a === "-selftest") mode = "selftest";
    else fatal(`未知参数: ${a}（可用：-check / --selftest）`);
  }
  const rd = loadRules();
  const arms = resolveArms(rd);
  const cells = allCells(rd, arms);
  if (mode === "selftest") return selftestRun(rd, cells);
  if (mode === "check") {
    const { ok, issues } = verdict(rd, cells);
    for (const s of issues) process.stdout.write(`  ${s}\n`);
    if (ok) {
      process.stdout.write("cli_symmetry: PASS（四子命令 × 两探针 × 三臂：臂间一致、与声明一致、rc4 均有 fail loud 文案）\n");
      return 0;
    }
    process.stdout.write("cli_symmetry: FAIL——CLI 参数面已分叉（详见上方）\n");
    return 1;
  }
  return 0;
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  try {
    process.exit(main(process.argv.slice(2)));
  } catch (e) {
    process.stderr.write(`${e instanceof Error ? e.message : String(e)}\n`);
    process.exit(2);
  }
}
