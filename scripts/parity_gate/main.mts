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
//   node scripts/parity_gate/main.mts                     # 全量对拍（CI 静态 job 形态：只跑无产物依赖目标）
//   node scripts/parity_gate/main.mts --only <dir>[,<dir>] # 点名跑（artifact 组必须这样跑：缺产物即 rc 2 硬红）
//   node scripts/parity_gate/main.mts --selftest           # 注入必然差异，证明闸会红
//
// 双轨判定：同目录**基名相同**的 `.go` + `.mts`（main 与非 main 一视同仁）；两侧基名
// 不同的历史批（gen_diag.go ↔ main.mts）用 `goEntry`/`tsEntry` 显式登记。
//
// **freshness 门禁目标的本地注意**：带 ensureFresh 的目标（protocol_frames 等）在产物
// 陈旧时，首侧（go）会触发重建 → 第二侧（ts）已看不到「旧于源」行 ⇒ 单次差异属状态性
// 假红；先构建或重跑一次即可（CI 每轮全新构建，无此问题）。
//
// 退出码：0 全等价 / 1 有差异（逐条列） / 2 用法、产物或环境错。
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../internal/capi.mts";
import { byteCompare } from "../internal/text.mts";

export interface Target {
  /** 仓库相对目录（Go main.go 与 .mts 同目录） */
  dir: string;
  /** 参数组；每组是一次完整的 argv */
  modes: string[][];
  /** 双轨文件名基（默认 "main"）——两侧同名时用这个简写（如 moonbit_surface） */
  entry?: string;
  /** Go 侧文件名基（默认 = entry）——两侧**基名不同**的双轨（如 gen_diag.go ↔ main.mts） */
  goEntry?: string;
  /** .mts 侧文件名基（默认 = entry） */
  tsEntry?: string;
  /**
   * **已知非确定行**的屏蔽正则（源码字符串，作用于整行）：两侧取值依赖采样时刻/
   * 采样后端的行（如 RSS 峰值 MB）在比对前整行丢弃。仅用于「测得值本身不可比、
   * 但判定行可比」的场合——屏蔽面必须在批注里写明理由。
   */
  maskLines?: string;
  /**
   * 先跑一次 Go 侧**丢弃输出**再比对：带 `ensureFresh` 的目标在产物陈旧时，首跑会
   * 打印「旧于源」并触发重建，第二跑就没这行了——不预热则两侧必然不对称（状态性
   * 假红）。预热只让**新鲜度噪声**消失；判定面差异仍会被比对到。
   */
  warmup?: boolean;
  /**
   * 产物前置（仓库相对路径）。带此字段 = **artifact 组**：不进默认跑（静态 job
   * 没产物时会两侧同报「前置产物缺失」空转绿——那是假绿，不是等价）；只在
   * 构建过产物的 job 里用 `--only <dir>` 显式跑，且缺任一产物即 rc 2 硬红。
   */
  requires?: string[];
  /**
   * 只在 `--only` 点名时跑的**理由**（如「需四臂 release 产物」「需 moon 现场编译、
   * 单价高」）。带此字段 = 不进默认跑，避免给静态 job 加冷编译/空转成本。
   */
  exclusive?: string;
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
  { dir: "scripts/moonbit/single_source", modes: [[], ["-check"], ["--selftest"]] },
  { dir: "scripts/moonbit/libc_single_source", modes: [[], ["-check"], ["--selftest"]] },
  { dir: "scripts/moonbit/pkg_deps", modes: [[], ["-check"], ["--selftest"]] },
  { dir: "scripts/perf_budget", modes: [[], ["-check"], ["--selftest"]] },
  { dir: "scripts/moonbit/mbti_sync", modes: [[], ["-check"], ["--selftest"]] },
  // warmup：protocol_frames 带 ensureFresh（产物陈旧时首跑会重建，两侧不对称）
  { dir: "scripts/protocol_frames", modes: [[], ["--selftest"]], warmup: true },
  {
    dir: "scripts/demo_ui_lint",
    // 红 fixture（13 条 >12）是刻意保留的：n>12 越过 Go sort 的插入排序阈值，
    // 「同 kind 保持插入序」这条契约要靠它锁（Go 版已改 SliceStable，见 main.go）。
    modes: [
      [],
      ["-selftest"],
      [
        "-demo",
        "scripts/demo_ui_lint/testdata/red",
        "-rules",
        "scripts/demo_ui_lint/testdata/red/rules.json",
        "-raw-baseline",
        "scripts/demo_ui_lint/testdata/red/raw_baseline.json",
      ],
    ],
  },
  // #289 批（教学线 + 文本闸）：合并 master 后纳入
  { dir: "scripts/teaching_phase_vocab", modes: [[], ["-selftest"]] },
  { dir: "scripts/teaching_reconcile", modes: [[], ["-v"], ["-selftest"]] },
  { dir: "scripts/host_contract_map", modes: [[], ["-strict"], ["-selftest"]] },
  { dir: "scripts/skill_path_check", modes: [[], ["-selftest"]] },
  { dir: "scripts/gen_demo_tokens", modes: [["-check"], ["-selftest"]] },
  {
    // 单文件非 main 命名的双轨（entry 显式登记）；两形态同强度，-check 仅兼容旧调用
    dir: "scripts/moonbit/moonbit_surface",
    entry: "moonbit_surface",
    modes: [[], ["-check"]],
  },
  // ── 基名不同但已成双轨：此前 parity 自动发现（同基名）看不见 → 补登记 ─────
  // 这批是更早迁移批的产物（Go 文件名 = 包名，.mts 统一叫 main.mts），长期只有
  // 人工验证、无对拍闸。登记后实测：本 5 个逐字等价；gen_diag / gen_diagnostics
  // 两款**有意不迁** legacy 对账臂（452/850 行死代码，2026-10-23 裁定），删区态
  // Go 打「对账臂豁免」而 .mts 打自己的 check OK 行 → 见 EXCLUDED 的同名条目。
  { dir: "scripts/moonbit/gen_host_route", goEntry: "gen_host_route", tsEntry: "main", modes: [["-check"]] },
  { dir: "scripts/moonbit/gen_protocol_fields", goEntry: "gen_protocol_fields", tsEntry: "main", modes: [["-check"]] },
  { dir: "scripts/moonbit/gen_stubs", goEntry: "gen_stubs", tsEntry: "main", modes: [["-check"]] },
  { dir: "scripts/moonbit/host_route_coverage", goEntry: "host_route_coverage", tsEntry: "main", modes: [[]] },
  { dir: "scripts/moonbit/source_hygiene", goEntry: "source_hygiene", tsEntry: "main", modes: [[]] },
  {
    // 全量跑一轮 ~9 分钟/侧（318 变体 × clang/js/native）⇒ 对拍走 testdata 迷你规则
    // （21 变体 ≈ 40s/侧）：生成计划由 testdata/variants 的 Go 金样本逐字节锁、判定
    // 流水线由这轮真跑锁。`-regen` 让两侧都从干净缓存起（否则首侧生成/次侧「缓存命中」
    // 行不同）。
    dir: "scripts/corpus_fuzz",
    modes: [
      ["-regen", "-rules", "scripts/corpus_fuzz/testdata/mini_rules.json", "-baseline", "scripts/corpus_fuzz/testdata/mini_baseline.json"],
    ],
    exclusive: "需 clang + cmd/run release exe + launcher（corpus fuzz job 具备）",
  },
  {
    // 需 debug cmd/serve exe。两模式：主跑（68 断言）+ 豁免面审计轮（D19：豁免全失效
    // 真跑，原豁免条目 FAIL = 合法证明——这本身就是豁免面的证红路径）。
    // maskLines：RSS 4 行「seek(…) 后提交峰值 ≈ N MB」是**测得值**（Go 走 psapi、
    // 本版走 CIM 同一计数器；采样时刻差异可致 ±1MB），屏蔽后判定行仍逐字可比。
    dir: "scripts/serve_smoke",
    modes: [["-moonbit"], ["-moonbit", "-audit-exemptions"]],
    exclusive: "需 debug cmd/serve exe（gates-native 的 serve 步先建）",
    warmup: true,
    maskLines: "^\\s+seek\\(\\s*\\d+\\) 后提交峰值 ≈ \\d+ MB（预算 \\d+ MB）$",
  },
  // ── artifact 组：需四臂产物，只在构建过产物的 job 里 `--only` 跑 ──────
  { dir: "scripts/toolchain_probe", entry: "toolchain_probe", modes: [[]] },
  {
    // 只对拍 `-check`（指纹比对，确定性）：优化路径的收尾行含**耗时**，不可逐字比；
    // 冷缓存时「下载…」行只在首侧出现——故本目标准入条件 = tools/cache 已预热
    // （CI 的 wasm-opt 步先跑优化再点名对拍）。
    dir: "scripts/wasmopt",
    modes: [["-check", "moonbit/_build/wasm-gc/release/build/gateway/wasm/wasm.wasm"]],
    exclusive: "需预热 tools/cache（冷缓存下载行只在首侧出现）与 wasm 产物（wasm-opt 步之后）",
  },
  {
    // 非 main 命名（replay_s1_s5.go）；`-moonbit` 需 debug serve exe，
    // `--selftest` 纯判定口径埋雷（无产物依赖）。`--backend wasm` 不进对拍：
    // 它的 ensureFresh 会**重建**产物（状态性），后跑的一侧必然看不到陈旧行。
    dir: "scripts/replay",
    entry: "replay_s1_s5",
    modes: [["-moonbit"], ["--selftest"]],
    exclusive: "需 debug cmd/serve exe（gates-native 的 serve 步先建）",
  },
  {
    dir: "scripts/moonbit/libc_boot_diff",
    // 默认（golden 基线比）+ --selftest（本仓 oracle 已删区，selftest 亦落 golden 路径）。
    // 单价：`moon run --target native cmd/dump_compile` 会现场编译引擎——不进默认跑。
    modes: [[], ["--selftest"]],
    exclusive: "需 moon 现场编译 dump_compile（gates-native 已有工具链与构建缓存）",
  },
  {
    dir: "scripts/vitro_cli_smoke",
    // 默认（内置 5 fixture × 三臂）+ --corpus 2（语料级循环面）。
    // 全量 --corpus 30 留给 CI 的 cli_smoke slice（对拍只验等价，不重复全量跑）。
    modes: [[], ["--corpus", "2"]],
    exclusive: "需四臂 release 产物（gates-wasm 的 cli_smoke slice 是唯一齐备处）",
    requires: [
      "moonbit/_build/js/release/build/cmd/vitro_wasm/vitro_wasm.js",
      "moonbit/_build/native/release/build/cmd/vitro/vitro.exe",
      "moonbit/_build/wasm-gc/release/build/gateway/wasm/wasm.wasm",
      "moonbit/_build/js/release/build/cmd/vitro_js/vitro_js.js",
    ],
  },
];

/**
 * 「混合目录」：同目录既有 `.go`（非 _test）又有 `.mts`，但**没有任何同基名配对**
 * ——自动发现看不见它们（审阅 P3-2 实测 bar.go + main.mts 曾静默通过）。这类目录
 * 必须显式归类：进 TARGETS（带 goEntry/tsEntry）或进 EXCLUDED 写原因。
 */
export function discoverMixedDirs(): string[] {
  const root = projectRoot();
  const out: string[] = [];
  const walk = (rel: string): void => {
    const abs = path.join(root, rel);
    let ents: fs.Dirent[];
    try {
      ents = fs.readdirSync(abs, { withFileTypes: true });
    } catch {
      return;
    }
    const goFiles = ents.filter((e) => e.isFile() && e.name.endsWith(".go") && !e.name.endsWith("_test.go")).map((e) => e.name);
    const mtsFiles = ents.filter((e) => e.isFile() && e.name.endsWith(".mts")).map((e) => e.name);
    const paired = goFiles.some((g) => mtsFiles.includes(g.slice(0, -3) + ".mts"));
    if (goFiles.length > 0 && mtsFiles.length > 0 && !paired) out.push(rel);
    for (const e of ents) if (e.isDirectory()) walk(`${rel}/${e.name}`);
  };
  walk("scripts");
  return out.sort(byteCompare);
}

/**
 * 未纳入对拍的双轨目录 + 原因。**必须穷举**：自动发现的每个「main.go + main.mts」
 * 目录要么在 TARGETS，要么在此表——否则闸报「未归类」红（#292 审阅质疑：全做还是
 * 留白？答案是把「不做」也变成显式登记，不允许黑箱跳过）。
 */
export const EXCLUDED: Record<string, string> = {
  "scripts/realcode_diff":
    "混合目录但**非双轨**：`vitro_clang_diff.go`（Go 版真值源闸）与 `compare_gold.mts`（golden 比对工具）是两个无关程序，不存在「同一驱动两实现」；待 realcode_diff 迁移时再按 goEntry/tsEntry 登记",
  "scripts/moonbit/gen_diag":
    "基名不同（gen_diag.go ↔ main.mts）+ **有意不迁** legacy 对账臂（452 行死代码，2026-10-23 裁定）：删区态 Go 打「legacy 源已删区（工序④），对账臂豁免」而 .mts 直接打 check OK——文案差异属既定设计，不做逐字对拍",
  "scripts/moonbit/gen_diagnostics":
    "基名不同（gen_diagnostics.go ↔ main.mts）+ 有意不迁 legacy 对账臂（约 850 行 + 20 个 .rs 解析器，2026-10-23 裁定）；理由同上（删区豁免行 vs check OK 行）",
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
/**
 * 归一：CRLF→LF、去 `go run` 包装的 `exit status N` 行、去尾随空行。
 *
 * **不再做「全文 `\`→`/`」**（#292 审阅 P3-1）：那是结构性假绿面——`\2014` 与
 * `/2014` 会被判等价（CSS 转义 vs 路径）。两侧都跑在同一平台、同一 path.join 口径，
 * 路径分隔符本就一致；若将来某目标真的跨平台打印分叉，应当在**该目标**上显式处理，
 * 而不是全局放宽。
 */
export function normalize(s: string): string {
  return s
    .split(/\r?\n/)
    .filter((l) => !/^exit status \d+$/.test(l.trim()))
    .join("\n")
    .replace(/\n+$/, "");
}

/** 自动发现「同目录同时存在 main.go 与 main.mts」的双轨目录（仓库相对）。 */
export function discoverDualDirs(): Array<{ dir: string; entry: string }> {
  const root = projectRoot();
  const out: Array<{ dir: string; entry: string }> = [];
  const walk = (rel: string): void => {
    const abs = path.join(root, rel);
    for (const ent of fs.readdirSync(abs, { withFileTypes: true })) {
      if (ent.isDirectory()) {
        const sub = `${rel}/${ent.name}`;
        walk(sub);
        continue;
      }
      // 双轨判定：同目录同基名的 .go 与 .mts（main 与非 main 命名一视同仁）
      if (!ent.name.endsWith(".go") || ent.name.endsWith("_test.go")) continue;
      const entry = ent.name.slice(0, -3);
      if (entry === "") continue;
      if (!fs.existsSync(path.join(abs, entry + ".mts"))) continue;
      out.push({ dir: rel, entry });
    }
  };
  walk("scripts");
  return out.sort((a, b) => (a.dir + "/" + a.entry < b.dir + "/" + b.entry ? -1 : 1));
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

/**
 * 「未归类」明细的行格式（可单测）。历史 bug：直接把 {dir, entry} 对象插值 ⇒ 输出
 * `[object Object]`，定位全失（#292 审阅 P2-2）。类型上已收窄为 string[]，此处再给
 * 一条断言兜底。
 */
export function formatUnclassified(entries: readonly string[]): string {
  return entries.map((e) => `  - ${e}`).join("\n");
}

/** 按 maskLines 正则丢弃整行（无 mask 时原样返回）。 */
export function maskText(s: string, maskSrc: string | undefined): string {
  if (maskSrc === undefined || maskSrc === "") return s;
  const re = new RegExp(maskSrc);
  return s
    .split("\n")
    .filter((l) => !re.test(l))
    .join("\n");
}

export function compareOne(
  dir: string,
  mode: string[],
  goBin: string,
  entry = "main",
  maskSrc?: string,
): { diff: Mismatch[]; goMs: number; tsMs: number } {
  const modeLabel = mode.length === 0 ? "(默认)" : mode.join(" ");
  const t0 = performance.now();
  const g = run(goBin, mode);
  const t1 = performance.now();
  const t = run(process.execPath, [`${dir}/${entry}.mts`, ...mode]);
  const t2 = performance.now();
  const out: Mismatch[] = [];
  if (g.rc !== t.rc) out.push({ dir, mode: modeLabel, field: "rc", goVal: String(g.rc), tsVal: String(t.rc) });
  for (const field of ["stdout", "stderr"] as const) {
    const a = maskText(normalize(g[field]), maskSrc);
    const b = maskText(normalize(t[field]), maskSrc);
    if (a !== b) out.push({ dir, mode: modeLabel, field, goVal: a, tsVal: b });
  }
  return { diff: out, goMs: t1 - t0, tsMs: t2 - t1 };
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
  let only: string[] | null = null;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i] ?? "";
    if (a === "--selftest" || a === "-selftest") selftest = true;
    else if (a === "--only") {
      const v = argv[i + 1];
      if (v === undefined || v === "") {
        process.stderr.write("parity_gate: --only 需要逗号分隔的仓库相对目录\n");
        return 2;
      }
      only = v.split(",").map((s) => s.trim()).filter((s) => s !== "");
      i++;
    } else {
      process.stderr.write(`parity_gate: 未知参数 ${JSON.stringify(a)}\n`);
      return 2;
    }
  }
  projectRoot();
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "parity_gate_"));
  try {
    // 自动发现双轨目录：每个都必须在 TARGETS 或 EXCLUDED 中（未归类 = 红）
    const known = new Set([...TARGETS.map((t) => t.dir), ...Object.keys(EXCLUDED)]);
        // 两类都要归类（P3-2 修）：① 同基名成对（可直接对拍）；② 同目录有 .go 与 .mts 但
    // 基名不同（须显式 goEntry/tsEntry 才可比，否则**静默跳过**——审阅实测 bar.go+main.mts
    // 曾静默通过）。
    const unclassified: string[] = [
      ...discoverDualDirs()
        .filter((d) => !known.has(d.dir))
        .map((d) => `${d.dir}/${d.entry}`),
      ...discoverMixedDirs()
        .filter((dir) => !known.has(dir))
        .map((dir) => `${dir}（基名不同：须在 TARGETS 显式 goEntry/tsEntry，或入 EXCLUDED 写明原因）`),
    ];
    if (unclassified.length > 0) {
      process.stderr.write(
        `parity_gate: ${unclassified.length} 个双轨目录未归类（须入 TARGETS 或 EXCLUDED 并写明原因）：\n${formatUnclassified(unclassified)}\n`,
      );
      return 1;
    }

    const all: Mismatch[] = [];
    let cases = 0;
    let goTotal = 0;
    let tsTotal = 0;

    // 选取面：默认跑 artifact-free 目标（静态 job 无产物）；`--only` 点名跑
    // 指定目标（跨两组，供产物就绪的 job 用）。
    let selected: Target[];
    if (only === null) {
      selected = TARGETS.filter((t) => t.requires === undefined && t.exclusive === undefined);
      const skipped = TARGETS.filter((t) => t.requires !== undefined || t.exclusive !== undefined);
      if (skipped.length > 0) {
        process.stdout.write(
          `parity_gate: 跳过 ${skipped.length} 个点名目标（在对应 job 用 --only 跑）：${skipped.map((t) => t.dir).join(", ")}\n`,
        );
      }
    } else {
      const known = new Set(TARGETS.map((t) => t.dir));
      const unknown = only.filter((d) => !known.has(d));
      if (unknown.length > 0) {
        process.stderr.write(`parity_gate: --only 含未登记目录 ${unknown.join(", ")}（须先入 TARGETS）\n`);
        return 2;
      }
      selected = TARGETS.filter((t) => only.includes(t.dir));
      // 点名跑 = 断言产物就绪：缺产物硬红，绝不空转绿
      for (const t of selected) {
        for (const rel of t.requires ?? []) {
          if (!fs.existsSync(path.join(projectRoot(), rel))) {
            process.stderr.write(`parity_gate: ${t.dir} 产物缺失 ${rel}——artifact 组须在构建过产物的 job 里跑\n`);
            return 2;
          }
        }
      }
    }

    const wall0 = performance.now();
    for (const t of selected) {
      const goEntry = t.goEntry ?? t.entry ?? "main";
      const tsEntry = t.tsEntry ?? t.entry ?? "main";
      const goMain = path.join(projectRoot(), t.dir, goEntry + ".go");
      const tsMain = path.join(projectRoot(), t.dir, tsEntry + ".mts");
      if (!fs.existsSync(goMain) || !fs.existsSync(tsMain)) {
        process.stderr.write(`parity_gate: ${t.dir} 不是双轨（缺 ${goEntry}.go 或 ${tsEntry}.mts）——表项应删或补齐\n`);
        return 2;
      }
      const goBin = buildGo(t.dir, tmp);
      if (t.warmup === true && t.modes.length > 0) {
        // 预热：只为把「产物陈旧 → 重建」这一步提前做掉（输出丢弃）
        run(goBin, t.modes[0] as string[]);
      }
      for (const mode of t.modes) {
        cases++;
        const r = compareOne(t.dir, mode, goBin, tsEntry, t.maskLines);
        goTotal += r.goMs;
        tsTotal += r.tsMs;
        const diff = r.diff;
        if (diff.length > 0) all.push(...diff);
        else process.stdout.write(`  ok  ${t.dir} ${mode.length === 0 ? "(默认)" : mode.join(" ")}\n`);
      }
    }

    if (selftest) {
      // 注入必然差异：Go 与 TS 对未知参数的文案不同（flag 包 vs 手写解析）
      // ——用它对拍，闸**必须**报差异，否则说明比对逻辑空转。
      const probe: Mismatch[] = compareOne("scripts/icon_catalog", ["--definitely-bogus"], buildGo("scripts/icon_catalog", tmp)).diff;
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
    const wall = performance.now() - wall0;
    const ratio = goTotal > 0 ? tsTotal / goTotal : 0;
    process.stdout.write(`parity_gate: PASS（${selected.length} 个双轨脚本 × ${cases} 组参数，stdout/stderr/rc 全等价）\n`);
    // 双边计时：一次对拍 = go 侧 + ts 侧（理论 ≈ 单边 2×；不含 go build）
    process.stdout.write(
      `  耗时（同口径，不含 go build）：go 侧 ${Math.round(goTotal)} ms / ts 侧 ${Math.round(tsTotal)} ms` +
        `（ts/go = ${ratio.toFixed(2)}×）/ 双边累计 ${Math.round(goTotal + tsTotal)} ms / 含编译墙钟 ${Math.round(wall)} ms\n`,
    );
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
