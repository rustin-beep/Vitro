// diffgate.mts —— 差分对拍驱动的共享骨架（#273 差分族重构批）。
//
// 族 A（五个 golden 对拍驱动：lexer / parser / typeck / codegen / vm）的共用面：
//   语料 LF 归一副本 → 跑 mb 侧 dump → 每 case 取 sha16 → 与冻结清单比对
//   （缺失/多余/hash 不符三态）→ 红/绿；外加 --freeze-mb 入账与 --selftest
//   注入证红。
//
// **digest 形状是 target 私有的**（2026-10-23 实测纠正）：lexer 是
// `version/sources/tsvs`，typeck 是 `version/note/modes`（modes 下再分
// sources/resp_hashes）——issue 坑表「三个 diff 脚本 digest 顶层结构互不相同」
// 即此。故骨架只消费 GoldenStore 的**语义**（本语料段的 sources + cases），
// 不碰 JSON 形状；序列化与顶层键序由各 target 自持（键序 = Go struct 字段声明序，
// 不是字典序）。
//
// 历史面裁定：原 Go 版的 `--freeze`（需 Rust oracle）与「默认全量双侧逐字节
// 对拍」在工序④删区后已成死代码——oracle 不存在时默认模式先转 golden 并 exit，
// 后面的 rust↔mb 比对段永远不可达。本骨架不迁那两段。
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import crypto from "node:crypto";
import { spawnSync } from "node:child_process";
import { projectRoot } from "./capi.mts";

export interface Fail {
  (msg: string): never;
}

export interface GateContext {
  root: string;
  /** 原始语料绝对路径 */
  corpus: string;
  /** 语料段名（digest 的一级键，各 target 自定义拼法） */
  corpusName: string;
  /** LF 归一副本目录（喂给 mb dump） */
  normDir: string;
  /** 产物临时目录 */
  workDir: string;
  /** 本 target 的语料后缀集（来源闸与归一副本共用） */
  exts: string[];
}

/** 一个语料段的对拍面：源文件指纹 + case 产物指纹。 */
export interface GoldenSection {
  /** 文件名 → sha8（LF 归一后） */
  sources: Record<string, string>;
  /** case 名 → sha16 */
  cases: Record<string, string>;
}

/**
 * golden 存取钩子。形状（分节方式、字段名、是否附 .json.mbt 变体）由 target
 * 自持；骨架只按语义取用。
 */
export interface GoldenStore {
  /** 读当前语料段；缺段返回 null（措辞由 missingHint 给） */
  load(corpusName: string): GoldenSection | null;
  /** 写回（仅 --freeze-mb 用） */
  save(corpusName: string, sec: GoldenSection): void;
  /** 缺语料段时的处置提示（各驱动历史措辞不同：先 --freeze-mb / 先 --freeze） */
  missingHint: string;
}

/**
 * 合成语料模式（parser 的 `--pathological` / `--legal-deep` / `--threshold`）：
 * 收 flag 后**不吃 corpus 位置参数**，自己往临时目录写语料再当 corpus 跑同一套
 * golden 比对——digest 里对应独立节（section）。
 */
export interface SyntheticMode {
  /** digest 节名（如 "pathological"） */
  section: string;
  /** 往 tmpDir 写入语料文件 */
  prepare(tmpDir: string): void;
}

export interface DiffTarget {
  /** lexer / parser / typeck / codegen / vm */
  name: string;
  /** 判红出口（**退出码按各驱动历史行为**：lexer=1，typeck/parser=2）——与入口用法错分流 */
  fail: Fail;
  /** golden 存取工厂：传 root 以便测试注入临时仓库根（override 型可不给） */
  golden?(root: string): GoldenStore;
  /**
   * 跑 mb 侧 dump，返回 case 名 → sha256 前 16 位（键 = 单 case 标识，不含语料段）。
   * 「怎么跑、产物落在哪、怎么归一」是各驱动唯一的真差异面（override 型可不给）。
   */
  runCases?(ctx: GateContext): Map<string, string>;
  /** 语料文件后缀集（默认 .c/.h/.in）；typeck 只吃 .c（listCFiles 口径） */
  corpusExts?: string[];
  /** 有意分叉例：golden 比对跳过并单列说明。可给表，也可给按（语料节, case）判定的函数 */
  knownForks?:
    | Record<string, string>
    | ((corpusName: string, caseName: string) => string | undefined);
  /**
   * 语料源指纹的判定档：
   * - `strict`（默认）：sha8 全等，注释/空白改动即要求重冻
   * - `presence`：只查「新样本不在清单」（parser 的 2026-10-23 口径——行为回归由
   *   resp_hash 承担，source map 只作冻结留档）
   */
  sourcesPolicy?: "strict" | "presence";
  /**
   * 额外 CLI 布尔 flag（如 codegen 的 `--baseline`）。骨架按白名单识别并透传，
   * 未列出的 `--xxx` 仍按未知参数 fail loud。
   */
  extraFlags?: string[];
  /**
   * case 级比对之外的判定面（codegen 的 slot_strategy / verify / manifest）。
   * 在 runCases 之后调用；返回错误清单，非空即红。
   * 需要产物中间态时由 target 自持（单进程单次运行，闭包缓存即可）。
   */
  extraChecks?(ctx: GateContext): string[];
  /** 合成语料模式：flag → 模式（命中时不接受 corpus 位置参数） */
  syntheticModes?: Record<string, SyntheticMode>;
  /**
   * **完全接管**（逃生舱）：给了就在 runGate 最前面调用它，跳过默认的
   * 语料解析 / golden 比对 / freeze 流程，argv 原样交给 target，返回值即退出码。
   *
   * 用于**形态根本不同**的驱动——vm_diff（三通道比对 + 预编译 exe + 新鲜度门禁
   * + known/skip 双清单 + 多 backend + 内存差异区间机判）与 codegen_diff
   * （cases 是判定记录表 + dump 段需 RawMessage 保真 u64 + 四类非 case 级校验）。
   * 这两个只复用本模块的工具函数（语料归一 / sha / digest 序列化），不复用流程。
   *
   * 判据同 genio：配置面不得超过被替换的代码——当 3 个以上钩子都要为目标驱动
   * 定制时，说明它不在同一抽象层，应当整体接管。
   */
  override?: (argv: string[], root: string) => number;
}

export const DEFAULT_CORPUS_EXT = [".c", ".h", ".in"];

/** 语料段文件名清单（默认后缀集；顺序稳定）。 */
export function corpusFiles(corpus: string, exts: string[] = DEFAULT_CORPUS_EXT): string[] {
  return fs
    .readdirSync(corpus)
    .filter((n) => exts.some((e) => n.endsWith(e)))
    .sort();
}

/** 语料复制到 dst 并行尾归一为 LF。 */
export function normalizeCorpusTo(
  corpus: string,
  dst: string,
  exts: string[] = DEFAULT_CORPUS_EXT,
): string {
  fs.mkdirSync(dst, { recursive: true });
  for (const n of corpusFiles(corpus, exts)) {
    fs.writeFileSync(path.join(dst, n), toLF(fs.readFileSync(path.join(corpus, n))));
  }
  return dst;
}

/** 语料指纹表（LF 归一的 sha8）——与 Go 版 corpusSHAs 同口径。 */
export function corpusSHAs(
  corpus: string,
  exts: string[] = DEFAULT_CORPUS_EXT,
): Record<string, string> {
  const out: Record<string, string> = {};
  for (const n of corpusFiles(corpus, exts)) {
    out[n] = sha8(toLF(fs.readFileSync(path.join(corpus, n))));
  }
  return out;
}

export function toLF(b: Buffer): Buffer {
  return Buffer.from(b.toString("latin1").replace(/\r\n/g, "\n"), "latin1");
}

export function sha8(b: Buffer): string {
  return crypto.createHash("sha256").update(b).digest("hex").slice(0, 8);
}

export function sha16(b: Buffer): string {
  return crypto.createHash("sha256").update(b).digest("hex").slice(0, 16);
}

/** `moon -C moonbit run --target native <sub> -- <args…>` */
export function moonDump(root: string, sub: string, args: string[], fail: Fail): void {
  const r = spawnSync("moon", ["-C", "moonbit", "run", "--target", "native", sub, "--", ...args], {
    cwd: root,
    encoding: "utf8",
  });
  if (r.status !== 0) {
    fail(`moon run ${sub} 执行失败: exit ${r.status}\n${(r.stdout ?? "") + (r.stderr ?? "")}`);
  }
}

// ---- 模式解析 ----

interface Modes {
  golden: boolean;
  freezeMB: boolean;
  selftest: boolean;
  /** target 声明的额外布尔 flag（如 --baseline） */
  extra: Set<string>;
}

export function parseGateArgs(
  argv: string[],
  usage: string,
  fail: Fail,
  extraFlags: string[] = [],
  requireCorpus = true,
): { corpus: string; modes: Modes } {
  const modes: Modes = { golden: false, freezeMB: false, selftest: false, extra: new Set() };
  let corpus = "";
  for (const a of argv) {
    if (a === "--golden") modes.golden = true;
    else if (a === "--freeze-mb") modes.freezeMB = true;
    else if (a === "--selftest") modes.selftest = true;
    else if (extraFlags.includes(a)) modes.extra.add(a);
    else if (a === "--freeze") {
      fail("--freeze 已随工序④（Rust oracle 删区）退役——新用例入账用 --freeze-mb");
    } else if (a === "--refresh") {
      fail("--refresh 已删除——--freeze-mb 默认含存量重算，直接去掉本旗重跑");
    } else if (a.startsWith("--") || corpus !== "") {
      fail(`未知/重复参数 ${JSON.stringify(a)}`);
    } else corpus = a;
  }
  if (requireCorpus && corpus === "") fail(usage);
  if (!requireCorpus && corpus !== "") {
    fail(`本模式不接受语料位置参数（收到 ${JSON.stringify(corpus)}）`);
  }
  if (modes.golden && modes.freezeMB) {
    fail("--golden 与 --freeze-mb 互斥（比对 vs 入账）");
  }
  return { corpus, modes };
}

/** 跑一个 target（三模式调度 + 临时目录生命周期）。 */
export function runGate(target: DiffTarget, argv: string[], usageFail: Fail): void {
  const root = projectRoot();
  // 逃生舱：形态不同的驱动整体接管（vm / codegen）
  if (target.override !== undefined) {
    const rc = target.override(argv, root);
    if (rc !== 0) process.exit(rc);
    return;
  }
  if (target.golden === undefined || target.runCases === undefined) {
    return usageFail(`内部错误：${target.name} 既未提供 override，也未提供 golden/runCases`);
  }
  const store = target.golden(root);
  const runCases = target.runCases;
  const extraFlags = target.extraFlags ?? [];
  const synModes = target.syntheticModes ?? {};
  const synFlag = Object.keys(synModes).find((k) => argv.includes(k));
  const usage =
    synFlag !== undefined
      ? `用法: node scripts/diff_gate/main.mts ${target.name} ${synFlag} [--golden|--freeze-mb|--selftest]`
      : `用法: node scripts/diff_gate/main.mts ${target.name} <corpus_dir> [--golden|--freeze-mb|--selftest${extraFlags.map((f) => "|" + f).join("")}]`;

  let corpus: string;
  let corpusName: string;
  let modes: Modes;
  let synthTmp: string | null = null;

  if (synFlag !== undefined) {
    // 合成语料模式：不吃位置参数，自己造语料到临时目录
    const syn = synModes[synFlag];
    if (syn === undefined) usageFail(`未知合成模式 ${synFlag}`);
    modes = parseGateArgs(
      argv.filter((a) => a !== synFlag),
      usage,
      usageFail,
      extraFlags,
      false,
    ).modes;
    synthTmp = fs.mkdtempSync(path.join(os.tmpdir(), `vitro_${target.name}_syn_`));
    syn.prepare(synthTmp);
    corpus = synthTmp;
    corpusName = syn.section;
  } else {
    const parsed = parseGateArgs(argv, usage, usageFail, extraFlags, true);
    modes = parsed.modes;
    corpus = path.resolve(parsed.corpus);
    if (!fs.existsSync(corpus)) usageFail(`语料目录不存在: ${parsed.corpus}`);
    corpusName = path.basename(corpus);
  }

  const workDir = fs.mkdtempSync(path.join(os.tmpdir(), `vitro_${target.name}_`));
  const normBase = fs.mkdtempSync(path.join(os.tmpdir(), `vitro_${target.name}_norm_`));
  try {
    const exts = target.corpusExts ?? DEFAULT_CORPUS_EXT;
    const normDir = normalizeCorpusTo(corpus, path.join(normBase, "src"), exts);
    const ctx: GateContext = { root, corpus, corpusName, normDir, workDir, exts };

    if (modes.freezeMB) {
      freezeMB(target, ctx, store, runCases);
      return;
    }
    // 固定走冻结基线：oracle 面已随工序④永久退役（原 Go 版的「裁判切换」是
    // 运行时探测 oracle 是否存在；此处保留同一警示前缀，但不再是探测结果）
    process.stderr.write(
      `${target.name}: [裁判切换] oracle 面已随工序④退役——本判定固定走 --golden 冻结基线（结构裁判自 oracle 切为 digest 清单；正确性主锚仍为 Clang/shadow）\n`,
    );
    const rc = compareGolden(target, ctx, store, modes.selftest, runCases);
    if (rc !== 0) process.exit(rc);
  } finally {
    fs.rmSync(workDir, { recursive: true, force: true });
    fs.rmSync(normBase, { recursive: true, force: true });
    if (synthTmp !== null) fs.rmSync(synthTmp, { recursive: true, force: true });
  }
}

/** 语料指纹闸：strict = 文件集与 sha 全等；presence = 只查新样本已登记。 */
function checkSources(
  sec: GoldenSection,
  ctx: GateContext,
  fail: Fail,
  hint: string,
  policy: "strict" | "presence",
): void {
  const cur = corpusSHAs(ctx.corpus, ctx.exts);
  const curNames = Object.keys(cur);
  const srcNames = Object.keys(sec.sources);
  if (policy === "presence") {
    for (const n of curNames) {
      if (sec.sources[n] === undefined) fail(`新样本 ${n} 不在清单（${hint}）`);
    }
    return;
  }
  if (curNames.length !== srcNames.length) {
    fail(
      `语料 ${ctx.corpusName} 文件数已变（现 ${curNames.length} ≠ 落盘 ${srcNames.length}）——${hint}`,
    );
  }
  for (const n of srcNames) {
    if (cur[n] !== sec.sources[n]) {
      fail(`语料 ${n} 已变更而清单未重刷——${hint}`);
    }
  }
}

function compareGolden(
  target: DiffTarget,
  ctx: GateContext,
  store: GoldenStore,
  selftest: boolean,
  runCases: (ctx: GateContext) => Map<string, string>,
): number {
  const fail = target.fail;
  const sec = store.load(ctx.corpusName);
  // `return fail(...)` 而非裸调用：target.fail 是属性访问，TS 不认它的 never
  // 能切断控制流（只有函数声明才行），故用显式 return 收窄 sec。
  if (sec === null) return fail(`清单缺语料段 ${ctx.corpusName}（${store.missingHint}）`);

  if (selftest) {
    // J9：篡改**当前语料段**首条清单值，随后比对必红
    const k = Object.keys(sec.cases)[0];
    if (k !== undefined) {
      sec.cases[k] = "deadbeef00000000";
      process.stdout.write(`[selftest][golden] 已篡改清单条目: ${k} ——随后比对必须 FAIL\n`);
    }
  }
  checkSources(sec, ctx, fail, store.missingHint, target.sourcesPolicy ?? "strict");

  const got = runCases(ctx);
  let failures = 0;
  let matched = 0;
  let forks = 0;
  const seen = new Set<string>();
  for (const [base, want] of Object.entries(sec.cases)) {
    seen.add(base);
    const forkReason =
      typeof target.knownForks === "function"
        ? target.knownForks(ctx.corpusName, base)
        : target.knownForks?.[base];
    if (forkReason !== undefined) {
      process.stdout.write(`FORK(known-golden-skip) ${base}——${forkReason}\n`);
      forks++;
      continue;
    }
    const actual = got.get(base);
    if (actual === undefined) {
      process.stdout.write(`DIFF 缺失: MoonBit 侧无 ${base}\n`);
      failures++;
      continue;
    }
    if (actual !== want) {
      process.stdout.write(
        `DIFF ${base}: hash ${actual} ≠ 清单 ${want}（全文对照见 frozen-oracle-snapshot 分支）\n`,
      );
      failures++;
    } else matched++;
  }
  for (const base of got.keys()) {
    if (!seen.has(base)) {
      process.stdout.write(`DIFF 多余: 清单无 ${ctx.corpusName}/${base}\n`);
      failures++;
    }
  }
  // 非 case 级判定面（slot_strategy / verify / manifest 等）
  if (target.extraChecks !== undefined) {
    const errs = target.extraChecks(ctx);
    for (const e of errs) {
      process.stdout.write(`DIFF ${e}\n`);
      failures++;
    }
  }
  if (failures > 0) {
    process.stdout.write(`${target.name}[golden]: FAIL——${failures} 处差异（语料 ${ctx.corpusName}）\n`);
    return 1;
  }
  const forkNote = forks > 0 ? `，${forks} 例 known-fork 跳过` : "";
  process.stdout.write(
    `${target.name}[golden]: PASS——${matched} 个 case hash 与冻结基线一致（语料 ${ctx.corpusName}${forkNote}）\n`,
  );
  return 0;
}

/** --freeze-mb：补登新 case + 存量重算（--refresh 语义已内置）。 */
function freezeMB(
  target: DiffTarget,
  ctx: GateContext,
  store: GoldenStore,
  runCases: (ctx: GateContext) => Map<string, string>,
): void {
  const fail = target.fail;
  const sec = store.load(ctx.corpusName);
  if (sec === null) {
    return fail(`--freeze-mb: 清单缺语料段 ${ctx.corpusName}（${store.missingHint}）`);
  }
  const cur = corpusSHAs(ctx.corpus, ctx.exts);
  let srcAdded = 0;
  let srcRefreshed = 0;
  for (const [n, sha] of Object.entries(cur)) {
    const old = sec.sources[n];
    if (old === undefined) {
      sec.sources[n] = sha;
      srcAdded++;
    } else if (old !== sha) {
      sec.sources[n] = sha;
      srcRefreshed++;
    }
  }
  if (Object.keys(cur).length !== Object.keys(sec.sources).length) {
    fail(
      `--freeze-mb: 清单含已删除文件（Sources ${Object.keys(sec.sources).length} ≠ 现文件 ${Object.keys(cur).length}）——先人工清理`,
    );
  }

  const got = runCases(ctx);
  let added = 0;
  let refreshed = 0;
  for (const [base, sha] of got) {
    const old = sec.cases[base];
    if (old === undefined) {
      sec.cases[base] = sha;
      process.stdout.write(`ADD ${base}\n`);
      added++;
    } else if (old !== sha) {
      sec.cases[base] = sha;
      process.stdout.write(`REFRESH ${base}\n`);
      refreshed++;
    }
  }
  if (srcAdded === 0 && added === 0 && srcRefreshed === 0 && refreshed === 0) {
    fail("--freeze-mb: 无新例可入账");
  }
  store.save(ctx.corpusName, sec);
  process.stdout.write(
    `${target.name} --freeze-mb: Sources +${srcAdded}（重算 ${srcRefreshed}）、case +${added}（重算 ${refreshed}）（背书 = clang_direct + moon test）\n`,
  );
}
