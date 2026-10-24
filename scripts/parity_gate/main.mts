#!/usr/bin/env node
// parity_gate —— 双轨 Go ↔ .mts 对拍闸（#273 / #292 审阅：把"对拍"从一次性手工证据变成 CI 防线）。
//
// 背景：迁移期 Go 版与 .mts 版并存，但此前对拍只在人肉批次里跑过一次——
// 「CI 全绿」只证明断言自洽，证明不了两侧判定等价。本闸把并存期的等价性
// 变成机判：每个双轨脚本按配置表跑同一组参数，比对 stdout / stderr / **真实退出码**。
//
// 为什么用 `go build` 而不是 `go run`：`go run` 会把程序的非零退出码折成 1、
// 并在 stderr 补一行 `exit status N`——比 rc 会被它骗（本仓已实测踩过）。
//
// 口径（归一化后才比，避免假红）：
//   - 路径分隔符统一 `/`；
//   - 剥离 `exit status N` 残留行（若实现回退到 go run 形态）；
//   - 其余一律逐字比。
//
// 用法：
//   node scripts/parity_gate/main.mts             # 全量对拍（CI 形态）
//   node scripts/parity_gate/main.mts --selftest  # 注入必然差异，证明闸会红
//
// 退出码：0 全等价 / 1 有差异（逐条列） / 2 用法或环境错。
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../internal/capi.mts";

export interface Target {
  /** 仓库相对目录（Go main.go 与 .mts 同目录） */
  dir: string;
  /** 参数组；每组是一次完整的 argv */
  modes: string[][];
}

/**
 * 双轨清单。新增双轨脚本时在此登记一行——**未登记 = 无对拍**，
 * 这也是本闸的诚实边界：它只覆盖表内条目，不是"全仓自动发现"。
 * 网络依赖的脚本（vendor_drift）不进 CI 对拍：CI 出网策略与本地不同，
 * 会变成不稳定假红；它的等价性靠本机 `node --use-system-ca` 手工对拍 + PR 记录。
 */
export const TARGETS: Target[] = [
  { dir: "scripts/icon_catalog", modes: [[], ["-v"]] },
  { dir: "scripts/diff_ledger", modes: [[], ["--selftest"]] },
  { dir: "scripts/editorconfig_check", modes: [[]] },
  { dir: "scripts/ci_checklist", modes: [[], ["-repo", "."]] },
  // #289 批（教学线 + 文本闸）：合并 master 后纳入
  { dir: "scripts/teaching_phase_vocab", modes: [[], ["-selftest"]] },
  { dir: "scripts/teaching_reconcile", modes: [[], ["-v"], ["-selftest"]] },
  { dir: "scripts/host_contract_map", modes: [[], ["-strict"], ["-selftest"]] },
  { dir: "scripts/skill_path_check", modes: [[], ["-selftest"]] },
  { dir: "scripts/gen_demo_tokens", modes: [["-check"], ["-selftest"]] },
];

/**
 * 未纳入对拍的双轨目录 + 原因。**必须穷举**：自动发现的每个「main.go + main.mts」
 * 目录要么在 TARGETS，要么在此表——否则闸报「未归类」红（#292 审阅质疑：全做还是
 * 留白？答案是把「不做」也变成显式登记，不允许黑箱跳过）。
 */
export const EXCLUDED: Record<string, string> = {
  "scripts/canonicalize": "需 stdin 输入才有判定面（默认无参 rc=1 等输入）；stdin 对拍另议",
  "scripts/gen_api_help": "生成器写盘（moonbit/cmd/lib/cli/api_help_gen.mbt）；对拍应走 -check 模式，未验证",
  "scripts/gen_demo_algorithms": "生成器写盘（demo/algorithms.js）；-check 语义未验证",
  "scripts/gen_icons": "生成器写盘（moonbit/icons/icons_gen.mbt）；-check 语义未验证",
  "scripts/gen_protocol_ts": "生成器写盘（protocol/ 产物）；-check 语义未验证",
  "scripts/gen_svg": "生成器写盘（docs/**/*.svg 15 张）+ 依赖 reports/facts.json",
  "scripts/moonbit/gen_libc_data": "生成器写盘（moonbit/vm/libc_data_gen.mbt）",
  "scripts/moonbit/testcount": "依赖 moon test 实跑真值（CI hygiene 才有），本地无产物时不可比",
  "scripts/moonbit/vendor_drift": "出网依赖：CI 与本地出网策略不同，纳入会变不稳定假红；等价性靠本机 --use-system-ca 手工对拍",
  "scripts/precompile_bytecode_libc": "生成模式已随 Rust oracle 退役（需 checkout tag rust-oracle-freeze）",
  "scripts/teaching_gen_check": "需 vitro js 臂产物 + 每次 ~6s 跑 3 产物与 7 负例；CI gen slice 已单独跑它，对拍另议",
  "scripts/course_catalog": "需 demo/algorithms.js（gitignored 发射产物）先发射；lesson.c 分支还需 vitro/clang",
  "scripts/teaching_annotation_diff": "需 native cmd/serve 产物 + 82 模板全量（约 25s/次），单价过高，另设批次",
};

/** 归一化：分隔符 + 剥离 go run 的退出码噪音行。 */
export function normalize(s: string): string {
  return s
    .split(/\r?\n/)
    .filter((l) => !/^exit status \d+$/.test(l.trim()))
    .join("\n")
    .split("\\")
    .join("/")
    .replace(/\n+$/, "");
}

/** 自动发现「同目录同时存在 main.go 与 main.mts」的双轨目录（仓库相对）。 */
export function discoverDualDirs(): string[] {
  const root = projectRoot();
  const out: string[] = [];
  const walk = (rel: string): void => {
    const abs = path.join(root, rel);
    for (const ent of fs.readdirSync(abs, { withFileTypes: true })) {
      if (!ent.isDirectory()) continue;
      const sub = `${rel}/${ent.name}`;
      if (fs.existsSync(path.join(root, sub, "main.go")) && fs.existsSync(path.join(root, sub, "main.mts"))) {
        out.push(sub);
      }
      if (rel.split("/").length < 2) walk(sub);
    }
  };
  walk("scripts");
  return out.sort();
}

export interface RunResult {
  stdout: string;
  stderr: string;
  rc: number;
}

function run(cmd: string, args: string[]): RunResult {
  const r = spawnSync(cmd, args, { cwd: projectRoot(), encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  return { stdout: r.stdout ?? "", stderr: r.stderr ?? "", rc: r.status ?? -1 };
}

/** 编 Go 侧为独立产物（真实退出码）。 */
function buildGo(dir: string, outDir: string): string {
  const name = process.platform === "win32" ? "go-arm.exe" : "go-arm";
  const out = path.join(outDir, name);
  const r = spawnSync("go", ["build", "-o", out, `./${dir}`], { cwd: projectRoot(), encoding: "utf8" });
  if (r.status !== 0) {
    process.stderr.write(`parity_gate: go build 失败 ${dir}\n${r.stdout ?? ""}${r.stderr ?? ""}\n`);
    process.exit(2);
  }
  return out;
}

export interface Mismatch {
  dir: string;
  mode: string;
  field: "rc" | "stdout" | "stderr";
  goVal: string;
  tsVal: string;
}

export function compareOne(dir: string, mode: string[], goBin: string): Mismatch[] {
  const modeLabel = mode.length === 0 ? "(默认)" : mode.join(" ");
  const g = run(goBin, mode);
  const t = run(process.execPath, [`${dir}/main.mts`, ...mode]);
  const out: Mismatch[] = [];
  if (g.rc !== t.rc) out.push({ dir, mode: modeLabel, field: "rc", goVal: String(g.rc), tsVal: String(t.rc) });
  for (const field of ["stdout", "stderr"] as const) {
    const a = normalize(g[field]);
    const b = normalize(t[field]);
    if (a !== b) out.push({ dir, mode: modeLabel, field, goVal: a, tsVal: b });
  }
  return out;
}

function firstDiffLine(a: string, b: string): string {
  const la = a.split("\n");
  const lb = b.split("\n");
  for (let i = 0; i < Math.max(la.length, lb.length); i++) {
    if ((la[i] ?? "") !== (lb[i] ?? "")) {
      return `第 ${i + 1} 行：go=${JSON.stringify(la[i] ?? "<缺行>")} ts=${JSON.stringify(lb[i] ?? "<缺行>")}`;
    }
  }
  return "内容相同（不应到此）";
}

export function main(argv: string[]): number {
  let selftest = false;
  for (const a of argv) {
    if (a === "--selftest" || a === "-selftest") selftest = true;
    else {
      process.stderr.write(`parity_gate: 未知参数 ${JSON.stringify(a)}\n`);
      return 2;
    }
  }
  projectRoot();
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "parity_gate_"));
  try {
    // 自动发现双轨目录：每个都必须在 TARGETS 或 EXCLUDED 中（未归类 = 红）
    const known = new Set([...TARGETS.map((t) => t.dir), ...Object.keys(EXCLUDED)]);
    const unclassified = discoverDualDirs().filter((d) => !known.has(d));
    if (unclassified.length > 0) {
      process.stderr.write(`parity_gate: ${unclassified.length} 个双轨目录未归类（须入 TARGETS 或 EXCLUDED 并写明原因）：
`);
      for (const d of unclassified) process.stderr.write(`  - ${d}
`);
      return 1;
    }

    const all: Mismatch[] = [];
    let cases = 0;
    for (const t of TARGETS) {
      const goMain = path.join(projectRoot(), t.dir, "main.go");
      const tsMain = path.join(projectRoot(), t.dir, "main.mts");
      if (!fs.existsSync(goMain) || !fs.existsSync(tsMain)) {
        process.stderr.write(`parity_gate: ${t.dir} 不是双轨（缺 main.go 或 main.mts）——表项应删或补齐\n`);
        return 2;
      }
      const goBin = buildGo(t.dir, tmp);
      for (const mode of t.modes) {
        cases++;
        const diff = compareOne(t.dir, mode, goBin);
        if (diff.length > 0) all.push(...diff);
        else process.stdout.write(`  ok  ${t.dir} ${mode.length === 0 ? "(默认)" : mode.join(" ")}\n`);
      }
    }

    if (selftest) {
      // 注入必然差异：Go 与 TS 对未知参数的文案不同（flag 包 vs 手写解析）
      // ——用它对拍，闸**必须**报差异，否则说明比对逻辑空转。
      const probe: Mismatch[] = compareOne("scripts/icon_catalog", ["--definitely-bogus"], buildGo("scripts/icon_catalog", tmp));
      if (probe.length === 0) {
        process.stderr.write("parity_gate selftest FAIL：注入的已知差异未被捕获（闸空转）\n");
        return 1;
      }
      process.stdout.write(`parity_gate selftest OK：已知差异被捕获（${probe.length} 处，字段 ${probe.map((p) => p.field).join("/")}）\n`);
    }

    if (all.length > 0) {
      process.stderr.write(`parity_gate: ${all.length} 处不一致（${cases} 组参数）\n`);
      for (const m of all) {
        if (m.field === "rc") {
          process.stderr.write(`  ✗ ${m.dir} ${m.mode} rc：go=${m.goVal} ts=${m.tsVal}\n`);
        } else {
          process.stderr.write(`  ✗ ${m.dir} ${m.mode} ${m.field}：${firstDiffLine(m.goVal, m.tsVal)}\n`);
        }
      }
      return 1;
    }
    process.stdout.write(`parity_gate: PASS（${TARGETS.length} 个双轨脚本 × ${cases} 组参数，stdout/stderr/rc 全等价）\n`);
    return 0;
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  process.exit(main(process.argv.slice(2)));
}
