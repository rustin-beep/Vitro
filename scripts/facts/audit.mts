// audit.mts —— 文档数字对账层（#273 存量 Go 重写批；原 audit.go，行为锚 =
// 8 个直译测试）。用事实台账比对文档里的测试数字，并**精确替换**漂移项。
//
// 核心判据（本工具的世界观）：文档里的"测试数字"有三种，混着人肉同步必然漂移。
//
//	CURRENT   裸数字（无日期、无 as-of 词）  → 必须等于真值，否则判漂移
//	AS-OF     带日期 / "截至" / "原记" 等     → 冻结，不参与对账
//	DERIVED   普查派生（中位行数、步数…）     → 需重跑专项脚本，本工具不覆盖
//
// 判定为双层：文件级（文件名含 裁定/决议/评估报告/工作记录…）+ 行级（含日期或 as-of 词）。
//
// 口径（#273 纪律 8）：行内偏移一律 UTF-16 自洽体系（start/end/近邻距离同口径，
// 切片结果与 Go 字节口径等价——中文前后缀的 isWordByte 判定两侧一致）；跨文件
// 排序走 byteCompare（UTF-8 字节字典序）。
import fs from "node:fs";
import path from "node:path";
import { byteCompare, byteSort, goTrimSpace } from "../internal/text.mts";
import type { FactsDoc } from "./facts.mts";

// retiredKeys：Rust 退役键（工序④删区 2026-10-05）——真值源永久消失，
// 待采集（--run 可补）语义不适用；引用面按历史句豁免，不进 Pending 红。
const RETIRED_KEYS = new Set([
  "shadow_c_cases", "shadow_c_match", "shadow_c_known_issue",
  "shadow_c_gap_extension", "shadow_c_gaps",
  "replay_assertions", "serve_smoke_assertions",
  "cargo_test_passed", "cargo_test_suites",
  "shadow_cpp_cases",
]);

// ─── 对账规则 ────────────────────────────────────────────────────────────────

export interface Rule {
  key: string;
  label: string;
  context: RegExp;
  exclude: RegExp | null;
  lo: number;
  hi: number;
  unit: string;
}

// 2026-10-12 带宽 5000-8000→1000-1600：真值面随 oracle 退役改四目录
// 稳定语料（随机 2400 例生成路死亡——golden 清单不认临时目录名），
// 1298=822+162+276+38（四目录冻结基线）。
export function rules(): Rule[] {
  const mk = (key: string, label: string, ctx: string, exc: string, lo: number, hi: number, unit: string): Rule => {
    const r: Rule = { key, label, context: new RegExp(ctx, "i"), exclude: null, lo, hi, unit };
    if (exc !== "") r.exclude = new RegExp(exc, "i");
    return r;
  };
  return [
    mk("shadow_c_cases", "C 影子用例总数", `影子|shadow`,
      `C\\+\\+|shadow_verify_cpp|cpp_shadow`, 400, 900, "用例"),
    mk("shadow_cpp_cases", "C++ 影子用例总数",
      `C\\+\\+.*(影子|shadow)|shadow_verify_cpp|cpp_shadow|C\\+\\+ 侧`,
      ``, 30, 250, "用例"),
    mk("cpp_e2e_cases", "C++ E2E 用例数", `C\\+\\+\\s*E2E|cases/cpp`,
      `影子|shadow`, 30, 250, "用例"),
    mk("replay_assertions", "回放断言数", `回放|replay|S1[-–]S5|S1/S5`,
      ``, 20, 200, "条"),
    mk("serve_smoke_assertions", "serve 冒烟断言数",
      `serve_smoke|serve 冒烟|协议断言|项断言`, ``, 10, 150, "项"),
    // "passed" 分支 2026-09-29 收紧为 `\d+\s*passed`：裸 passed 会命中
    // facts 键名 `moonbit_test_passed`（README.mbt.md:47 moon 分解式行
    // 因此被误圈进 cargo Manual/Suspect，--strict 假红）——真实 cargo 行
    // 是 "1027 passed" 数字紧邻形态；锚 TestCargoRuleIgnoresFactsKeyName。
    mk("cargo_test_passed", "cargo test 用例数", `cargo test|\\d+\\s*passed|全绿|rust 单测`,
      ``, 500, 2500, "用例"),
    mk("cargo_test_suites", "cargo test 套件数", `套件`, `断言|项断言`, 20, 200, "个"),
    // T6/T5 审阅（2026-09-19）：moonbit README 测试数防漂移——发布面
    // 审阅实证 0.1.0 的 README 计数过期（53 vs 实跑 58），纳入机判。
    // 上限 500 → 2000（2026-09-29）：0.7.0 实测 508 越上限被滤出候选，
    // README.mbt.md:47 整行无候选等于真值 → Suspect 假红；S8/S9 后
    // 测试数仍会涨，带宽给足。锚 TestMoonbitTruthInRange。
    mk("moonbit_test_passed", "MoonBit 测试数", `moon\\s*test|moonbit[^\\n]*测试|测试[^\\n]*moonbit`, ``, 40, 2000, "用例"),
    // S2（2026-09-19）：词法差分 TSV 总数防漂移——随机 2400 例 ×2 层 +
    // baseline 363×2 + K&R 81×2 = 5688；语料增删会移动真值，文档数字须随动。
    mk("moonbit_lexer_diff_tsv", "词法差分 TSV 数", `差分[^\\n]*TSV|TSV[^\\n]*差分|逐字节一致[^\\n]*TSV|词法差分`, ``, 1000, 1600, "个"),
    // S3（2026-09-19）：解析差分样本总数防漂移——baseline 363 + K&R 81
    // + leetcode 138 + gap 15 = 597；语料增删会移动真值，文档数字须随动。
    // 2026-10-21 连坐：对抗生成域批（c2cb5be1）语料增长至真值 710，
    // 带宽上限 700→750（机械放宽，非语义变更）。
    mk("moonbit_parser_diff_samples", "解析差分样本数", `解析差分[^\\n]*样本|样本[^\\n]*解析差分|AST[^\\n]*诊断序列|parser_diff`, ``, 500, 750, "个"),
  ];
}

// ─── SVG data-fact 对账（2026-09-20）────────────────────────────────────────
//
// docs/ 下入库 SVG 由 scripts/gen_svg 从 facts 台账生成（已迁 .mts，与本工具
// 同源读 reports/facts.json），跑批快照数字以 data-fact="key" 显式绑定真值。
// 与 md 通道的差异：
//   - 显式属性锚定，天然免除语境正则的歧义——不需要 Context/Lo/Hi；
//   - 判定看 <text> 文本段的全部数字（含一位数——known_issue 3 这类小计数；
//     md 通道的 reNum=\d{2,6} 在这里会漏）；
//   - 漂移**不进自动 sync**（interactiveSync 跳过 .svg 命中）：SVG 的修复
//     动作是重跑 node scripts/gen_svg/main.mts，手改数字会破坏模板一致性、
//     下次再生成即回退。
interface SvgFactMeta { label: string; unit: string }

const SVG_FACT_META: Record<string, SvgFactMeta> = {
  shadow_c_cases:         { label: "C 影子用例总数（SVG 锚）", unit: "用例" },
  shadow_c_match:         { label: "C match 数（SVG 锚）", unit: "用例" },
  shadow_c_known_issue:   { label: "C known_issue 数（SVG 锚）", unit: "用例" },
  shadow_c_gap_extension: { label: "C gap_extension 数（SVG 锚）", unit: "用例" },
  shadow_c_gaps:          { label: "C 非预期差异数（SVG 锚）", unit: "处" },
  shadow_cpp_cases:       { label: "C++ 影子用例总数（SVG 锚）", unit: "用例" },
  shadow_cpp_match:       { label: "C++ 一致数（SVG 锚）", unit: "用例" },
  shadow_cpp_clang_fail:  { label: "C++ clang_compile_fail 数（SVG 锚）", unit: "用例" },
};

const RE_DATA_FACT = /data-fact="([a-z0-9_]+)"/g;
// 锚后最近的文本节点：gen_svg 以 <tspan data-fact=…>n</tspan> 逐数字锚定
// （一行多锚零歧义），兜底匹配 </text>（整行单锚的历史形态）。
const RE_SVG_TEXT_TAIL = /^[^>]*>([^<]*)<\/(?:tspan|text)>/;
const RE_SVG_NUM = /\d+/g;

// ─── 文档分级 ────────────────────────────────────────────────────────────────

const RE_HIST_FILE = /裁定|决议|评估报告|工作记录|维护方案|追踪|审计计划|回执|登记|埋雷|事故|整备|审阅报告|执行记录|复审|CHANGELOG|ARCHIVE/i;
const RE_DATE = /\d{4}-\d{2}-\d{2}|\d{4}\/\d{1,2}\/\d{1,2}|\d{8}/g;
const RE_ASOF_WORD = /as[- ]?of|截至|原记|彼时|当时|历史|已废弃|旧口径|陈旧口径|归档|已过时|已被.*取代|口径已/i;
const RE_PHASE = /(Phase|Stage|阶段|第)\s*\d+/g;
const RE_NUM = /\d{2,6}/g;
// 数字绑定实测结果：直接替换会**伪造测量**（如"632 用例实测 103.6s"改成 671
// 就变成假记录）。此类应标 as-of，而不是改数字。
const RE_MEASURE = /实测|耗时|冷启动|加速比|吞吐|性能|基准/;
// HTML 嵌入标签行（<img ... width="900">）：行内数字是**布局参数**（显示
// 宽度）而非文档陈述——图览批实测："影子"alt + width=900 被 shadow_c_cases
// 规则当 900 用例判漂移（README.md:44 / 影子验证框架.md:13，区间恰含 900/880）。
// 嵌入图内的真数字由 SVG data-fact 通道对账（tspan 锚），标签行整体跳过。
const RE_HTML_TAG_LINE = /<img\b|width="/;
// 数字带分解式：只换总数会让算式不成立（如 "636 个用例（617 + vitro_better 16 + 3）"）。
// 两个数字之间有加号即算分解式（中间允许夹少量说明词）；"C++" 因加号旁无数字不会误触发。
const RE_BREAKDOWN = /\d[^+＋\n]{0,24}[+＋][^+＋\n]{0,24}\d/;

function splitLinesKeep(p: string): string[] {
  return fs.readFileSync(p, "utf8").split("\n");
}

function relOf(root: string, p: string): string {
  return path.relative(root, p).replaceAll("\\", "/");
}

// failLoud：auditDocs/scanFiles 的库内急停（Go 版 os.Exit(2) 直译；文案对齐）。
function failLoud(msg: string): never {
  process.stderr.write(msg + "\n");
  process.exit(2);
}

// exemptDocEntry：文档豁免白名单条目（2026-09-26 用户裁定机制）——**只用于
// "不维护仅查看"的文档**（外部项目事实调查记录等：行内数字是第三方项目的
// 快照，既不该连坐 Vitro 真值、也不该被改写）；需维护文档一律走统一格式
// （日期/as-of 词），禁入本清单。白名单条目指向不存在的文件即红（防腐化，
// 与 vm_diff skip/known 白名单同构）；清单文件缺失视为空（向后兼容）。
interface ExemptDocEntry { path: string; reason: string }

export function loadExemptDocs(root: string): Map<string, string> | null {
  const p = path.join(root, "scripts", "facts", "exempt_docs.json");
  let data: string;
  try {
    data = fs.readFileSync(p, "utf8");
  } catch (e) {
    if ((e as NodeJS.ErrnoException).code === "ENOENT") return null;
    throw e;
  }
  let entries: ExemptDocEntry[];
  try {
    entries = JSON.parse(data) as ExemptDocEntry[];
  } catch (e) {
    throw new Error("exempt_docs.json 解析失败: " + (e as Error).message);
  }
  const out = new Map<string, string>();
  for (const e of entries) {
    if (e.path === "" || e.reason === "") {
      throw new Error("exempt_docs.json 条目缺 path/reason: " + JSON.stringify(e));
    }
    if (!fs.existsSync(path.join(root, ...e.path.split("/")))) {
      throw new Error("豁免白名单条目指向不存在的文件 " + e.path + "（删除或修正）");
    }
    out.set(e.path, e.reason);
  }
  return out;
}

// suspectExemptEntry：--strict Suspect 兜底的行级豁免白名单条目（2026-10-01
// 接线批，模块审阅 09 P2-1 处方①——CI 启用 --strict 前先把合法误报面显式过闸）。
// Suspect = Manual 桶中"整行无一个数字对上真值"的行，已知合法形态（1.0 里程碑
// 未来值行等）在此登记：path 定位文件（slash 相对路径，同 exempt_docs）、
// contains 作行内容锚（行号会漂，不锚行号）。防腐化双向：条目指向不存在的
// 文件 → 加载即红；条目 contains 本轮扫描零命中 → StaleSuspectExempts
// （check 无条件红）——白名单不能沉淀为僵尸豁免面。
export interface SuspectExemptEntry { path: string; contains: string; reason: string }

export function loadSuspectExemptions(root: string): SuspectExemptEntry[] {
  const p = path.join(root, "scripts", "facts", "suspect_exemptions.json");
  let data: string;
  try {
    data = fs.readFileSync(p, "utf8");
  } catch (e) {
    if ((e as NodeJS.ErrnoException).code === "ENOENT") return [];
    throw e;
  }
  let entries: SuspectExemptEntry[];
  try {
    entries = JSON.parse(data) as SuspectExemptEntry[];
  } catch (e) {
    throw new Error("suspect_exemptions.json 解析失败: " + (e as Error).message);
  }
  for (const e of entries) {
    if (e.path === "" || e.contains === "" || e.reason === "") {
      throw new Error("suspect_exemptions.json 条目缺 path/contains/reason: " + JSON.stringify(e));
    }
    if (!fs.existsSync(path.join(root, ...e.path.split("/")))) {
      throw new Error("Suspect 豁免条目指向不存在的文件 " + e.path + "（删除或修正）");
    }
  }
  return entries;
}

// scanFiles 扫描目标文档：docs/ 全部 + 根目录 md（归档目录与豁免白名单跳过）。
export function scanFiles(root: string): string[] {
  const out: string[] = [];
  const docsDir = path.join(root, "docs");
  const walk = (dir: string): void => {
    let ents: fs.Dirent[];
    try {
      ents = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return; // Go WalkDir 逐项 err 吞掉：读不到的子树跳过
    }
    for (const e of byteSort(ents.map((x) => x.name))) {
      const ent = ents.find((x) => x.name === e)!;
      const p = path.join(dir, ent.name);
      if (ent.isDirectory()) {
        if (relOf(root, p).includes("archive")) continue; // filepath.SkipDir
        walk(p);
        continue;
      }
      if (p.endsWith(".md") || p.endsWith(".svg")) out.push(relOf(root, p));
    }
  };
  if (fs.existsSync(docsDir)) walk(docsDir);
  for (const n of ["AGENTS.md", "README.md", "moonbit/README.md", "moonbit/README.mbt.md"]) {
    if (fs.existsSync(path.join(root, ...n.split("/")))) out.push(n);
  }
  const sorted = byteSort(out);
  let exempt: Map<string, string> | null;
  try {
    exempt = loadExemptDocs(root);
  } catch (e) {
    // P2-5（2026-09-26 审阅）：此前 `_` 吞错——头注声称的「条目指向不
    // 存在文件即红」从不打印，坏白名单被静默当空表。fail loud。
    failLoud("facts: 豁免白名单加载失败（fail loud）：" + (e as Error).message);
  }
  if (exempt !== null) {
    return sorted.filter((f) => !exempt!.has(f));
  }
  return sorted;
}

export function classifyFile(rel: string): "ARCHIVE" | "AS-OF" | "CURRENT" {
  if (rel.includes("/archive/") || path.basename(rel).startsWith("ARCHIVE_")) {
    return "ARCHIVE";
  }
  // docs/spec/ 是对外承诺的协议文档（wire format / 验收快照）：其中的
  // 数字是 as-of 时点记录（且可能引用已退役的旧驱动路径），改数字等于
  // 往旧快照里塞新事实——按行级日期判冻结之外，文件级整体按 AS-OF 处理。
  if (rel.startsWith("docs/spec/")) return "AS-OF";
  if (RE_HIST_FILE.test(path.basename(rel))) return "AS-OF";
  return "CURRENT";
}

// classifyLine 行级冻结判据：命中阶段序号 / 日期 / as-of 词 ⇒ 整行免对账。
//
// **格式裁定（2026-10-04 拍板，用户）**：冻结豁免被门面现值句搭便车 = 文档格式
// 问题，不是闸的缺陷——处置是改文档，不给机制加兜底。现值行（当前状态陈述）
// 不写日期、写活数字，留在对账管束内；历史叙述 / 快照行继续享受冻结豁免。
function classifyLine(line: string): boolean {
  RE_PHASE.lastIndex = 0;
  if (RE_PHASE.test(line)) return true;
  RE_DATE.lastIndex = 0;
  return RE_DATE.test(line) || RE_ASOF_WORD.test(line);
}

// blankOut 用等长空格抹掉匹配片段，保持行内索引体系不变（UTF-16 自洽：
// 替换串与匹配串等长，数字位置在 masked 行内与原行同位）。
function blankOut(s: string, re: RegExp): string {
  RE_RESET(re);
  return s.replace(re, (m) => " ".repeat(m.length));
}

function RE_RESET(re: RegExp): void {
  re.lastIndex = 0;
}

// matchAllOf：Go FindAllStringIndex 的 JS 等价（克隆正则跑全局匹配——
// 共享正则的 lastIndex 不被推进，无 g 的存储正则也能全局匹配）。
function matchAllOf(re: RegExp, s: string): RegExpMatchArray[] {
  const g = new RegExp(re.source, re.flags.includes("g") ? re.flags : re.flags + "g");
  g.lastIndex = 0;
  return [...s.matchAll(g)];
}

function isWordByte(b: string): boolean {
  return b === "_" || b === "." ||
    (b >= "0" && b <= "9") || (b >= "a" && b <= "z") || (b >= "A" && b <= "Z");
}

export interface NumSpan {
  start: number;
  end: number;
  value: number;
}

// hitContainsTruth：整行候选数字中是否有任一个等于真值。
// 用于 Manual 桶兜底（FactAudit.Suspect）：已正确维护的分解式行（子项或总数）
// 必含真值；整行无一个对上 ⇒ 几乎必然是漏连坐。
function hitContainsTruth(cands: NumSpan[], truth: number): boolean {
  return cands.some((c) => c.value === truth);
}

// numberSpans 提取候选数字：先抹掉日期与阶段序号，再按 16 进制安全的边界检查过滤。
export function numberSpans(line: string): NumSpan[] {
  const masked = blankOut(blankOut(line, RE_PHASE), RE_DATE);
  const out: NumSpan[] = [];
  for (const m of matchAllOf(RE_NUM, masked)) {
    const s = m.index!;
    const e = s + m[0].length;
    if (s > 0 && isWordByte(masked[s - 1]!)) continue;
    if (e < masked.length && isWordByte(masked[e]!)) continue;
    const v = Number.parseInt(masked.slice(s, e), 10);
    if (Number.isNaN(v)) continue;
    out.push({ start: s, end: e, value: v });
  }
  return out;
}

// ─── 对账 ────────────────────────────────────────────────────────────────────

export interface Hit {
  key: string;
  file: string;
  lineNo: number;
  spans: NumSpan[];
  text: string;
  cooccur: string[];
  warn: string;
}

export function hitValue(h: Hit): number {
  return h.spans[0]!.value;
}

export interface FactAudit {
  rule: Rule;
  truth: number | null;
  matched: number;
  drift: Hit[];
  frozen: Hit[];
  pending: Hit[];
  // Manual：数字分解式 / 绑定实测结果的行。子项落在 Lo/Hi 区间内时
  // 与总数无法机判区分（`671 个用例（664 + 3 + 4）` 的 664 会被误判
  // 漂移），自动替换又会改断算式/伪造测量——归入人工维护，不判 drift
  // 不自动 sync，报告常显提醒。
  manual: Hit[];
  // Suspect：Manual 的子集——**行内所有候选数字都不等于真值**的那些。
  // 语义 = "整行没有任何一个数字能对上真值" ⇒ 该分解式行几乎必然漏了连坐。
  // **不判红，只提醒**（默认 check 显式列出；`check --strict` 判红，CI 已接线）。
  suspect: Hit[];
  // SuspectExempted：Suspect 子集中被 suspect_exemptions.json 登记豁免的
  // 行（2026-10-01 接线批）——--strict 判红的显式过闸面，豁免必须留痕可见。
  suspectExempted: Hit[];
}

// ─── 常量对账（M13 细化，2026-09-18）─────────────────────────────────────────
//
// 背景（§7A 复核 M13 实证）：ABI 版本代码升至 2.1.0 后，多份 CURRENT 文档
// 仍写 1.2.0 / 2.0.0——数字对账规则只抓区间整数，抓不住 "x.y.z" 版本串。
// 机械化为三条：行提及 vitro_abi_version 或 "ABI 版本" 且含 x.y.z → 参与判定；
// 行级豁免（日期/as-of 词 + 迁移箭头 + 历史标记词）；非豁免行的**全部**版本串
// 必须等于真值。漂移处置一律人工（不进 sync 自动替换）。

export interface ConstRule {
  key: string;
  label: string;
  context: RegExp;
  exempt: RegExp;
  unit: string;
}

export function constRules(): ConstRule[] {
  return [{
    key: "abi_version",
    label: "ABI 版本（vitro_abi_version）",
    context: /vitro_abi_version|ABI/,
    exempt: /→|->|首批|历史|曾|当时|彼时|追加|条目|已升|旧版|更名时|彼时|迁移自|升级自/,
    unit: "版本",
  }];
}

const RE_VERSION = /\d+\.\d+\.\d+/g;

export interface ConstHit {
  key: string;
  file: string;
  lineNo: number;
  found: string[];
  text: string;
}

export interface ConstAudit {
  rule: ConstRule;
  truth: string;
  hasTruth: boolean;
  matched: number;
  drift: ConstHit[];
  frozen: ConstHit[];
}

export interface BrokenRef {
  file: string;
  lineNo: number;
  path: string;
  text: string;
}

export interface AuditResult {
  audits: FactAudit[];
  truthOf: Record<string, number>;
  driftN: number;
  frozenN: number;
  pendingN: number;
  manualN: number;
  // SuspectN：Manual 桶中整行无数字对上真值的处数（兜底提醒；仅 --strict 判红）。
  suspectN: number;
  // SuspectExemptedN：被 suspect_exemptions.json 豁免的 Suspect 行数
  // （--strict 过闸面——豁免留痕，报告常显）。
  suspectExemptedN: number;
  // StaleSuspectExempts：白名单条目本轮扫描零命中（目标文件已无该 Suspect
  // 行）——僵尸豁免面，check 无条件红（防腐化，2026-10-01 接线批）。
  staleSuspectExempts: string[];
  scanN: number;
  // 坏引用：文档指向不存在的脚本文件（CURRENT 层才算；as-of/归档里的
  // 旧路径是有意的历史叙述）。
  broken: BrokenRef[];
  // 常量对账（版本号等字符串真值），与数字对账平行；DriftN 已并入其
  // 漂移计数，check 同样一票红。
  consts: ConstAudit[];
}

// auditConst 常量对账：只扫 CURRENT 层文档（AS-OF 文件的版本号是有意的
// 时点记载——裁定/登记文档引用"当时代码是什么版本"正是复核的证据链）。
export function auditConst(root: string, doc: FactsDoc): ConstAudit[] {
  const rs = constRules();
  const files = scanFiles(root);
  const out: ConstAudit[] = [];
  for (const r of rs) {
    const f = doc.facts[r.key];
    const a: ConstAudit = {
      rule: r, truth: "", hasTruth: false, matched: 0, drift: [], frozen: [],
    };
    if (f !== undefined && f.svalue !== undefined && f.svalue !== "") {
      a.truth = f.svalue;
      a.hasTruth = true;
    }
    for (const rel of files) {
      if (classifyFile(rel) !== "CURRENT") continue;
      let lines: string[];
      try {
        lines = splitLinesKeep(path.join(root, ...rel.split("/")));
      } catch {
        continue;
      }
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i]!.endsWith("\r") ? lines[i]!.slice(0, -1) : lines[i]!;
        if (!r.context.test(line)) continue;
        RE_VERSION.lastIndex = 0;
        const vers = matchAllOf(RE_VERSION, line).map((m) => m[0]);
        if (vers.length === 0) continue;
        const h: ConstHit = {
          key: r.key, file: rel, lineNo: i + 1, found: vers, text: goTrimSpace(line),
        };
        if (!a.hasTruth) continue; // 真值不可得：待采集，不判（unavail 由台账自报）
        const ok = vers.every((v) => v === a.truth);
        if (ok) {
          a.matched++;
          continue;
        }
        if (classifyLine(line) || r.exempt.test(line)) {
          a.frozen.push(h);
        } else {
          a.drift.push(h);
        }
      }
    }
    out.push(a);
  }
  return out;
}

export function auditDocs(root: string, doc: FactsDoc): AuditResult {
  const rs = rules();
  const byKey = new Map<string, FactAudit>();
  const order: string[] = [];
  for (const r of rs) {
    const t = doc.facts[r.key];
    byKey.set(r.key, {
      rule: r,
      truth: t !== undefined && t.value !== null && t.value !== undefined ? t.value : null,
      matched: 0, drift: [], frozen: [], pending: [], manual: [], suspect: [], suspectExempted: [],
    });
    order.push(r.key);
  }
  // 真值越界自检的说明见 truthsInRange（模块审阅 09 P2-2 治本，2026-09-29）；
  // 判红接线在 main.mts check 流程（auditDocs 保持库函数纯净，可被测试夹具安全调用）。

  const files = scanFiles(root);
  for (const rel of files) {
    // .svg 走下方 data-fact 显式锚通道：标签行文本剥掉属性后的语境歧义
    // 大（坐标/字号数字混在行内），且生成物的修复动作是重跑生成器而非
    // 文本替换——不参与 md 规则命中与自动 sync。
    if (rel.endsWith(".svg")) continue;
    const tier = classifyFile(rel);
    if (tier === "ARCHIVE") continue;
    let lines: string[];
    try {
      lines = splitLinesKeep(path.join(root, ...rel.split("/")));
    } catch {
      continue;
    }
    for (let i = 0; i < lines.length; i++) {
      const raw = lines[i]!;
      const line = raw.endsWith("\r") ? raw.slice(0, -1) : raw;
      if (goTrimSpace(line) === "") continue;
      // HTML 嵌入标签行：width 等布局参数不参与数字对账（见 RE_HTML_TAG_LINE 注释）。
      if (RE_HTML_TAG_LINE.test(line)) continue;
      const frozen = classifyLine(line) || tier === "AS-OF";
      const spans = numberSpans(line);

      // 这一行对每个事实各命中哪些候选数字。
      // P1 批（2026-09-18）：数字**就近绑定**——每个候选数字只归属
      // （双向）距离最近的规则关键词，平局取左。
      interface KwPos { pos: number; end: number; key: string }
      const kws: KwPos[] = [];
      for (const r of rs) {
        if (!r.context.test(line)) continue;
        if (r.exclude !== null && r.exclude.test(line)) continue;
        for (const loc of matchAllOf(r.context, line)) {
          kws.push({ pos: loc.index!, end: loc.index! + loc[0].length, key: r.key });
        }
      }
      kws.sort((a, b) => a.pos - b.pos);
      // nearestKeyOf：数字 span 与哪个关键词（双向）最近。左距 = 数字
      // 起点减关键词终点；右距 = 关键词起点减数字终点。平局取右：
      // "cargo test 70 套件" 的 70 左右等距，后置的"套件"才是它的
      // 计量单位（前置的 "cargo test" 是行首状语）。
      const nearestKeyOf = (s: NumSpan): string => {
        let best = "";
        let bestDist = -1;
        for (const k of kws) {
          if (k.end <= s.start) {
            const d = s.start - k.end;
            if (bestDist < 0 || d < bestDist) {
              best = k.key;
              bestDist = d;
            }
          } else {
            const d = k.pos - s.end;
            if (bestDist < 0 || d <= bestDist) {
              best = k.key;
              bestDist = d;
            }
          }
        }
        return best;
      };
      const byRule = new Map<string, NumSpan[]>();
      for (const r of rs) {
        if (!r.context.test(line)) continue;
        if (r.exclude !== null && r.exclude.test(line)) continue;
        const c: NumSpan[] = [];
        for (const s of spans) {
          if (nearestKeyOf(s) !== r.key) continue;
          if (s.value >= r.lo && s.value <= r.hi) c.push(s);
        }
        if (c.length > 0) byRule.set(r.key, c);
      }
      if (byRule.size === 0) continue;
      for (const [key, cands] of byRule) {
        const a = byKey.get(key)!;
        const h: Hit = {
          key, file: rel, lineNo: i + 1, spans: cands, text: goTrimSpace(line),
          cooccur: [], warn: "",
        };
        if (a.truth === null) {
          if (!RETIRED_KEYS.has(h.key)) {
            a.pending.push(h); // 无真值：待采集，不判漂移（退役键豁免）
          }
          continue;
        }
        const hit = cands.some((s) => s.value !== a.truth);
        if (!hit) {
          a.matched++;
          continue;
        }
        const others: string[] = [];
        for (const k2 of byRule.keys()) {
          if (k2 !== key) others.push(byKey.get(k2)!.rule.label);
        }
        h.cooccur = byteSort(others);
        const warns: string[] = [];
        if (RE_MEASURE.test(line)) {
          warns.push("该行数字绑定了实测结果，直接替换会伪造测量——建议标 as-of 日期而非改数字");
        }
        if (RE_BREAKDOWN.test(line)) {
          warns.push("该行含数字分解式（a + b + c），只替换总数会让算式不成立——请一并核对子项");
        }
        h.warn = warns.join("；");
        if (frozen) {
          a.frozen.push(h);
        } else if (h.warn !== "") {
          // 分解式/实测行：子项与总数无法机判区分、自动替换有破坏面
          // （见 FactAudit.manual 注释）——人工维护，不判 drift。
          a.manual.push(h);
          // 兜底：整行若无一个候选数字等于真值，则几乎必然漏了连坐
          // （见 FactAudit.suspect 注释）。子项与总数机判不区分，但
          // "整行 vs 真值"这块是机判得动的。
          if (!hitContainsTruth(cands, a.truth)) {
            a.suspect.push(h);
          }
        } else {
          a.drift.push(h);
        }
      }
    }
  }

  // ── SVG data-fact 通道：docs/ 下生成 SVG 的显式数字锚 ──────────────────
  // 判据：锚所在 <text> 文本段的数字集合必须含真值（分解式行总数在行内即绿）。
  // SVG 专属 key（md 通道无规则）在此按需建 audit，与 md 通道同表呈现。
  const ensureSVGAudit = (key: string): FactAudit => {
    const existing = byKey.get(key);
    if (existing !== undefined) return existing;
    const meta = SVG_FACT_META[key]!;
    const t = doc.facts[key];
    const a: FactAudit = {
      rule: { key, label: meta.label, context: RE_DATA_FACT, exclude: null, lo: 0, hi: 0, unit: meta.unit },
      truth: t !== undefined && t.value !== null && t.value !== undefined ? t.value : null,
      matched: 0, drift: [], frozen: [], pending: [], manual: [], suspect: [], suspectExempted: [],
    };
    byKey.set(key, a);
    order.push(key);
    return a;
  };
  for (const rel of files) {
    if (!rel.endsWith(".svg")) continue;
    let lines: string[];
    try {
      lines = splitLinesKeep(path.join(root, ...rel.split("/")));
    } catch {
      continue;
    }
    for (let i = 0; i < lines.length; i++) {
      const raw = lines[i]!;
      const line = raw.endsWith("\r") ? raw.slice(0, -1) : raw;
      RE_DATA_FACT.lastIndex = 0;
      for (const m of matchAllOf(RE_DATA_FACT, line)) {
        const key = m[1]!;
        if (SVG_FACT_META[key] === undefined) {
          continue; // 未登记 key：gen_svg 只输出登记锚，防御性跳过
        }
        const a = ensureSVGAudit(key);
        const h: Hit = {
          key, file: rel, lineNo: i + 1, spans: [], text: goTrimSpace(line),
          cooccur: [],
          warn: "SVG 为生成物——重跑 node scripts/gen_svg/main.mts 后再 check（勿手改数字）",
        };
        const pos = line.indexOf(m[0]);
        if (pos >= 0) {
          const tr = RE_SVG_TEXT_TAIL.exec(line.slice(pos + m[0].length));
          if (tr !== null) {
            for (const ns of matchAllOf(RE_SVG_NUM, tr[1]!)) {
              const v = Number.parseInt(ns[0], 10);
              if (!Number.isNaN(v)) h.spans.push({ start: 0, end: 0, value: v });
            }
          }
        }
        if (a.truth === null) {
          if (!RETIRED_KEYS.has(h.key)) {
            a.pending.push(h); // 无真值：待采集，不判漂移（退役键豁免）
          }
          continue;
        }
        const found = h.spans.some((s) => s.value === a.truth);
        if (found) {
          a.matched++;
        } else {
          a.drift.push(h);
        }
      }
    }
  }

  const res: AuditResult = {
    audits: [], truthOf: {}, driftN: 0, frozenN: 0, pendingN: 0, manualN: 0,
    suspectN: 0, suspectExemptedN: 0, staleSuspectExempts: [], scanN: files.length,
    broken: [], consts: [],
  };
  // Suspect 行级豁免白名单（2026-10-01 --strict 接线批）：fail loud 同
  // loadExemptDocs；TempDir 测试夹具无该文件视为空表（向后兼容）。
  let susExempts: SuspectExemptEntry[];
  try {
    susExempts = loadSuspectExemptions(root);
  } catch (e) {
    failLoud("facts: Suspect 豁免白名单加载失败（fail loud）：" + (e as Error).message);
  }
  const exemptHit = susExempts.map(() => false);
  for (const k of order) {
    const a = byKey.get(k)!;
    // Suspect 豁免过滤（先于计数）：命中（path+contains）→ suspectExempted
    // 留痕；未命中 → 留在 suspect（--strict 判红依据不变）。
    if (a.suspect.length > 0 && susExempts.length > 0) {
      const kept: Hit[] = [];
      for (const h of a.suspect) {
        let matched = false;
        for (let ei = 0; ei < susExempts.length; ei++) {
          const e = susExempts[ei]!;
          if (e.path === h.file && h.text.includes(e.contains)) {
            exemptHit[ei] = true;
            matched = true;
            break;
          }
        }
        if (matched) {
          a.suspectExempted.push(h);
        } else {
          kept.push(h);
        }
      }
      a.suspect = kept;
    }
    res.audits.push(a);
    res.driftN += a.drift.length;
    res.manualN += a.manual.length;
    res.suspectN += a.suspect.length;
    res.suspectExemptedN += a.suspectExempted.length;
    res.frozenN += a.frozen.length;
    res.pendingN += a.pending.length;
    if (a.truth !== null) res.truthOf[k] = a.truth;
  }
  // 白名单零命中条目 = 僵尸豁免面（目标行已被改写/删除），check 无条件红。
  for (let i = 0; i < susExempts.length; i++) {
    const e = susExempts[i]!;
    if (!exemptHit[i]) {
      res.staleSuspectExempts.push(`${e.path}（contains=${goQuote(e.contains)}, reason=${e.reason}）`);
    }
  }
  // 按规则键字节序稳定排序（Go sort.SliceStable order[i]<order[j] 直译），
  // 便于人工顺序核对。
  res.audits = stableSortBy(res.audits, (a, i) => order[i]!);
  res.broken = scanBrokenRefs(root, files);
  // 常量对账（版本号）：与数字对账平行的第二轴，漂移并入 DriftN 一票红。
  res.consts = auditConst(root, doc);
  for (const c of res.consts) {
    res.driftN += c.drift.length;
    res.frozenN += c.frozen.length;
  }
  return res;
}

// goQuote 复刻 fmt %q 的常见形态（可打印串直接双引号包裹；反斜杠/双引号转义）。
function goQuote(s: string): string {
  return '"' + s.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
}

function stableSortBy<T>(xs: T[], keyOf: (x: T, i: number) => string): T[] {
  return xs
    .map((x, i) => ({ x, k: keyOf(x, i) }))
    .sort((a, b) => byteCompare(a.k, b.k))
    .map((p) => p.x);
}

// ─── 坏引用扫描（文档指向不存在的脚本）────────────────────────────────────

const RE_SCRIPT_REF =
  /(?:scripts|native\/tests|native\/scripts)\/[A-Za-z0-9_/.-]+\.(?:py|go|ps1)/g;

// RE_NARRATIVE_REF 叙述性引用豁免：该行本身就在说明"此脚本已删除/退役/
// 规划中"时，路径出现是历史叙述而非失效指引。"取代/接替"刻意不在词表
// （U1 复审受控实验实锤误豁免："已用 nonexistent.py 取代旧流程"——取代
// 标记的是新路径存活）；接替句的旧路径由"同句活路径"规则豁免。
const RE_NARRATIVE_REF = /不存在|已迁出|已移除|已失效|未恢复|仍缺|删除|退役|规划中/;

// 命令动词前缀：路径紧跟其后即视为祈使指引（可复现命令形态）。
const RE_CMD_VERB = /(?:python3?|py|go\s+run|cargo|bash|sh|pwsh|powershell)\s+(?:\.\/|\.\\)?$/i;

// scanBrokenRefs 检查文档中引用的脚本路径是否真实存在。
//
// 判据是**行级语境**而非文件层级（U1 复审修正）：
//   - 命令语境（路径紧跟 python / go run / cargo 等命令动词）= 祈使指引，
//     **任何文件层级都扫**——AS-OF 文件里的活步骤恰恰是最需要抓的；
//   - 非命令语境的路径提及：只扫 CURRENT 层——历史文档的叙述性旧路径
//     （spec 勘误注记、埋雷台账、迁出记载）是有意保留的。
//
// 两道行级豁免：
//   - 豁免词（不存在|已迁出|已移除|已失效|未恢复|仍缺|删除|退役|规划中）；
//   - 同句活路径：一行内既有活路径又有死路径（"A 接替 B"形态）→ 死路径
//     是被接替方，豁免；全死才参与判定。
//
// 存在性按三级判定：①字面路径存在；②去扩展名后是含 .go 文件的目录
// （包路径引用）；③其余即坏引用。
function scanBrokenRefs(root: string, files: string[]): BrokenRef[] {
  const out: BrokenRef[] = [];
  for (const rel of files) {
    if (rel.includes("/archive/") || path.basename(rel).startsWith("ARCHIVE_")) {
      continue; // 归档目录整体跳过（含 ARCHIVE_ 前缀的明确归档件）
    }
    const asof = classifyFile(rel) !== "CURRENT";
    let lines: string[];
    try {
      lines = splitLinesKeep(path.join(root, ...rel.split("/")));
    } catch {
      continue;
    }
    for (let i = 0; i < lines.length; i++) {
      const raw = lines[i]!;
      const line = raw.endsWith("\r") ? raw.slice(0, -1) : raw;
      RE_SCRIPT_REF.lastIndex = 0;
      const refs = matchAllOf(RE_SCRIPT_REF, line).map((m) => m[0]);
      if (refs.length === 0) continue;
      const dead: string[] = [];
      let alive = false;
      for (const m of refs) {
        if (scriptRefAlive(root, m)) {
          alive = true;
        } else {
          dead.push(m);
        }
      }
      if (dead.length === 0) continue;
      if (alive) continue; // 接替句：同句有活路径，死路径是被接替方
      let isCmd = false;
      for (const m of dead) {
        if (inCommandContext(line, m)) {
          isCmd = true;
          break;
        }
      }
      if (asof && !isCmd) continue; // 历史文档的非命令叙述：有意保留的旧路径
      if (RE_NARRATIVE_REF.test(line)) {
        continue; // 行自身说明该脚本已死（"原命令 xxx 已失效"等）
      }
      for (const m of dead) {
        out.push({ file: rel, lineNo: i + 1, path: m, text: goTrimSpace(line) });
      }
    }
  }
  out.sort((a, b) => {
    if (a.file !== b.file) return byteCompare(a.file, b.file);
    return a.lineNo - b.lineNo;
  });
  return out;
}

// inCommandContext 判定路径 ref 在行内是否处于命令语境
// （其前方紧邻窗口内以命令动词结尾）。
function inCommandContext(line: string, ref: string): boolean {
  const idx = line.indexOf(ref);
  if (idx <= 0) return false;
  const start = Math.max(0, idx - 24);
  return RE_CMD_VERB.test(line.slice(start, idx));
}

function scriptRefAlive(root: string, ref: string): boolean {
  const p = path.join(root, ...ref.split("/"));
  if (fs.existsSync(p)) return true;
  // 包路径引用：xxx.go 不存在但 xxx/ 是含 .go 文件的目录
  if (ref.endsWith(".go")) {
    const dir = p.slice(0, -".go".length);
    let ents: fs.Dirent[];
    try {
      ents = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return false;
    }
    if (ents.some((e) => !e.isDirectory() && e.name.endsWith(".go"))) return true;
  }
  return false;
}

// allDrift 展开为按位置排序的待改清单。
export function allDrift(r: AuditResult): Hit[] {
  const out: Hit[] = [];
  for (const a of r.audits) out.push(...a.drift);
  out.sort((a, b) => {
    if (a.file !== b.file) return byteCompare(a.file, b.file);
    return a.lineNo - b.lineNo;
  });
  return out;
}

export function labelOf(r: AuditResult, key: string): string {
  for (const a of r.audits) {
    if (a.rule.key === key) return a.rule.label;
  }
  return key;
}

export function unitOf(r: AuditResult, key: string): string {
  for (const a of r.audits) {
    if (a.rule.key === key) return a.rule.unit;
  }
  return "";
}

// ─── 报告渲染 ────────────────────────────────────────────────────────────────

export function renderReport(root: string, doc: FactsDoc, res: AuditResult, verbose: boolean): string {
  const b: string[] = [];
  b.push("# 文档测试数字漂移报告\n\n");
  b.push("> 生成时间: " + nowISO() + "\n");
  const dirty = doc.git.dirty ? " (dirty)" : "";
  b.push("> 基线: `" + doc.git.rev + dirty + "`  真值源: `reports/facts.json`\n\n");
  b.push("判据：**CURRENT 文档中的裸数字（无日期、无 as-of 词）必须等于真值**；" +
    "带日期或位于历史文档中的数字视为 as-of 快照，冻结不对账。\n\n");
  b.push("## 摘要\n\n");
  b.push("| 事实 | 真值 | 一致命中 | 漂移（需修） | 冻结（as-of） | 待采集 |\n");
  b.push("|------|------|----------|--------------|---------------|--------|\n");
  for (const a of res.audits) {
    let truth = "—";
    if (a.truth !== null) {
      truth = String(a.truth);
    } else {
      const f = doc.facts[a.rule.key];
      if (f !== undefined && f.status === "stale") {
        // 区分"从无真值"（需 --run 采集）与"真值超龄被降级"（需先刷新产物）
        truth = "— ⏰超龄";
      }
    }
    b.push(`| ${a.rule.label} | ${truth} | ${a.matched} | ${a.drift.length} | ${a.frozen.length} | ${a.pending.length} |\n`);
  }
  b.push("\n");

  b.push("## 漂移明细（CURRENT 文档，需与真值对齐）\n\n");
  if (res.driftN === 0) {
    b.push("无漂移。\n\n");
  } else {
    for (const a of res.audits) {
      if (a.drift.length === 0) continue;
      b.push(`### ${a.rule.label} — 真值 **${a.truth}** ${a.rule.unit}（${a.drift.length} 处）\n\n`);
      for (const h of a.drift) {
        let extra = "";
        if (h.cooccur.length > 0) {
          extra = " — ⚠ 同行还含 **" + h.cooccur.join(" / ") + "**，改这行时别漏";
        }
        b.push(`- \`${h.file}:${h.lineNo}\` 出现 **${hitValue(h)}**${extra}\n`);
        b.push("  > " + h.text + "\n");
        if (h.warn !== "") {
          b.push("  > ⚠ " + h.warn + "\n");
        }
      }
      b.push("\n");
    }
  }

  if (res.consts.length > 0) {
    b.push("## 常量对账（版本号等字符串真值）\n\n");
    b.push("判据：陈述\"当前现值\"的句子必须等于源码真值；记录\"历史事件\"的句子" +
      "（迁移箭头 → / 首批 / 曾 / 当时 等）豁免。**漂移一律人工修**——自动替换会把" +
      "事件句篡改成假历史，改写句子形态（补时点标记）是语义决策。\n\n");
    for (const c of res.consts) {
      const truth = c.hasTruth ? c.truth : "—";
      b.push(`### ${c.rule.label} — 真值 **${truth}**（一致 ${c.matched} / 漂移 ${c.drift.length} / 冻结 ${c.frozen.length}）\n\n`);
      for (const h of c.drift) {
        b.push(`- \`${h.file}:${h.lineNo}\` 出现 ${h.found.join("、")}\n`);
        b.push("  > " + h.text + "\n");
      }
      b.push("\n");
    }
  }

  if (verbose) {
    b.push("## 冻结命中（as-of 快照，不参与对账）\n\n");
    for (const a of res.audits) {
      if (a.frozen.length === 0) continue;
      b.push(`### ${a.rule.label}（${a.frozen.length} 处）\n\n`);
      for (const h of a.frozen) {
        b.push(`- \`${h.file}:${h.lineNo}\` = ${hitValue(h)}\n`);
      }
      b.push("\n");
    }
  }

  if (res.broken.length > 0) {
    b.push("## 坏引用（CURRENT 文档指向不存在的脚本）\n\n");
    b.push("数字冻住不等于路径永远有效：退役驱动留在文档里，读者按图索骥会扑空。\n\n");
    for (const r of res.broken) {
      b.push(`- \`${r.file}:${r.lineNo}\` → \`${r.path}\`\n`);
      b.push("  > " + r.text + "\n");
    }
    b.push("\n");
  }

  if (res.manualN > 0) {
    b.push("## 人工维护（分解式 / 实测数字行）\n\n");
    b.push("子项落在判定区间内时与总数无法机判区分，自动替换会改断算式或伪造测量——\n");
    b.push("这些行不参与漂移判定与自动 sync，真值变化时请人工核对整行。\n\n");
    if (res.suspectN > 0) {
      b.push(`⚠️ 其中 **${res.suspectN} 处整行无任何数字等于真值**（标 ❗）：\n`);
      b.push("已正确维护的分解式行至少会有一个数字（子项或总数）对上真值；\n");
      b.push("整行都对不上，几乎必然是漏连坐（但未来值/里程碑目标行会是误报，请人工判别）。\n\n");
    }
    for (const a of res.audits) {
      if (a.manual.length === 0) continue;
      b.push(`### ${a.rule.label} — 真值 **${a.truth}** ${a.rule.unit}（${a.manual.length} 处）\n\n`);
      const suspect = new Set(a.suspect.map((h) => `${h.file}:${h.lineNo}`));
      for (const h of a.manual) {
        const mark = suspect.has(`${h.file}:${h.lineNo}`) ? " ❗整行无数字等于真值" : "";
        b.push(`- \`${h.file}:${h.lineNo}\`（首数 ${hitValue(h)}）${mark}\n`);
        b.push("  > " + h.text + "\n");
      }
      b.push("\n");
    }
  }
  return b.join("");
}

// ─── 精确替换 ────────────────────────────────────────────────────────────────

// ruleByKey 取回事实键对应的规则（applyHit 需要 Lo/Hi/Context/Exclude）。
function ruleByKey(key: string): Rule | null {
  for (const r of rules()) {
    if (r.key === key) return r;
  }
  return null;
}

// applyHit 只替换该行内**落在候选区间且不等于真值**的数字，其余字节原样保留。
//
// 关键：候选区间在**替换前基于当前文件内容重新计算**，不复用 audit 时的
// Hit.spans——同一行被多条规则命中时，先替换的那条若改变了长度，后续条目的
// 旧偏移会整体失真（实测会把 "78 个用例" 切成 "781个用例"）。重新定位即可免疫。
export function applyHit(root: string, h: Hit, truth: number): void {
  const p = path.join(root, ...h.file.split("/"));
  const lines = splitLinesKeep(p);
  const idx = h.lineNo - 1;
  if (idx < 0 || idx >= lines.length) {
    throw new Error(`${h.file}:${h.lineNo} 越界`);
  }
  let line = lines[idx]!;

  const r = ruleByKey(h.key);
  if (r === null) {
    throw new Error(`未知事实键 ${goQuote(h.key)}`);
  }
  // 安全网：前序条目可能已改写该行，若它不再匹配本规则就不许动手。
  if (!r.context.test(line) || (r.exclude !== null && r.exclude.test(line))) {
    throw new Error(`${h.file}:${h.lineNo} 已不再匹配规则 ${h.key}（可能已被其他条目改动），请重跑`);
  }

  const spans: NumSpan[] = [];
  for (const s of numberSpans(line)) {
    if (s.value >= r.lo && s.value <= r.hi) spans.push(s);
  }
  // 倒序替换，避免前面的替换影响后面的偏移
  for (let i = spans.length - 1; i >= 0; i--) {
    const s = spans[i]!;
    if (s.value === truth) continue;
    if (s.start < 0 || s.end > line.length || s.start >= s.end) continue;
    line = line.slice(0, s.start) + String(truth) + line.slice(s.end);
  }
  lines[idx] = line;
  fs.writeFileSync(p, lines.join("\n"), { mode: 0o644 });
}

// truthsInRange 真值越界自检（模块审阅 09 P2-2 治本，2026-09-29）：
// 候选数字先按 [Lo,Hi] 过滤，真值越界 ⇒ 行内候选被滤空 ⇒ 整行不进任何桶
// ——静默盲区（09 号 E11 实证）。本函数把「带宽过时」从静默变成可判定的
// 错误，check 流程据此一次性红、逼人改区间。
// 返回 {key, truth, lo, hi, out}；全部在界 out=false。
// 锚 TestTruthInRangeSelfCheck。
export function truthsInRange(rs: Rule[], doc: FactsDoc): { key: string; truth: number; lo: number; hi: number; out: boolean } {
  for (const r of rs) {
    const t = doc.facts[r.key];
    if (t !== undefined && t.value !== null && t.value !== undefined && (t.value < r.lo || t.value > r.hi)) {
      return { key: r.key, truth: t.value, lo: r.lo, hi: r.hi, out: true };
    }
  }
  return { key: "", truth: 0, lo: 0, hi: 0, out: false };
}

// findAudit：测试助手——按 key 取 audit。
export function findAudit(res: AuditResult, key: string): FactAudit | undefined {
  return res.audits.find((a) => a.rule.key === key);
}

// nowISO：报告首行时间戳（与 facts.mts 的采集时间戳同口径）。
function nowISO(): string {
  const d = new Date();
  const pad = (n: number): string => String(n).padStart(2, "0");
  const off = -d.getTimezoneOffset();
  const sign = off >= 0 ? "+" : "-";
  const oh = Math.floor(Math.abs(off) / 60);
  const om = Math.abs(off) % 60;
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}` +
    `T${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}` +
    `${sign}${pad(oh)}:${pad(om)}`;
}
