#!/usr/bin/env node
// wasmenc_emitgate —— REHOST 批 1c 产物闸（设计单 §3.2 批 1 验收面①③）：
// 全语料「153/154 码表 → wasm 子集」发射成功率 100% + 装载核对全过 +
// wabt 内容级验证全过（垫收证人模块）——三级判定的 .mts 驱动。
//
// 消费链：cmd/dump_wasm（native exe，ensureFresh 新鲜度门禁）逐语料目录
// 批跑出 JSONL → 本脚本逐行判定：
//   1. ok:true → module（垫收证人模块字节——批 2a：MoonBit 侧
//      assemble_witness_module 按组效应垫收〔组独立 block + 前垫 + drop
//      收〕+ import 段镜像〔env.vitro_host_call @ 函数索引 0〕段拼装）→
//      wabt readWasm + **`m.validate()` 内容级验证**——类型检查/栈平衡/
//      指令签名全过（PR #505 审阅 P1-2 的升级件：批 1c readWasm 只解码
//      不校验〔类型错/栈下溢均放行〕，垫收前物理上过不了 validate）。
//      watcheck 模板级（wat ↔ 发射字节逐字节对拍）仍为第二证人；J9 面：
//      非法样本（翻转一字节）validate 必红〔批 2a 亲证〕。
//   2. stage=emit|verify → RED（禁译面——deferred.json 按名登记豁免，
//      首版空：全语料摸底 0 例〔2026-11-13，9 语料目录 955+ 例〕）；
//   3. stage=lex|parse|type|gen → 计数不判红（编译失败面是 codegen_diff
//      既有防线的验收域——负例语料编译失败属预期，本闸只管「编译成功
//      例必须可发射且合法」）。
//
// 用法：node scripts/wasmenc_emitgate/main.mts [--dir corpus/baseline ...]
// （无参 = 全目录集；CI 每轮全量）。
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { ensureFresh } from "../internal/freshness.mts";
import { projectRoot } from "../internal/capi.mts";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));

/// 语料目录集（cpp 无 .c 文件、llm_multifile 为工程模式〔多文件工程〕——
/// 单文件循环不适用，两目录不入集，口径登记于此）
export const CORPUS_DIRS: ReadonlyArray<string> = [
  "baseline",
  "chibicc_port",
  "codegen_skeleton",
  "gap",
  "knr",
  "leetcode",
  "llm_scale",
  "mutator_probe",
  "template_generated",
] as const;

/// dump_wasm JSONL 行（ok / emit / verify / 编译失败四形态的宽松并集）
export interface DumpLine {
  file: string;
  ok: boolean;
  stage?: string;
  groups?: number;
  bytes?: number;
  verify?: string;
  hex?: string;
  /// 垫收证人模块字节 hex（批 2a——wasm-validate 内容级验证的载体）
  module?: string;
  gip?: number;
  op?: string;
  reason?: string;
  kind?: string;
  detail?: string;
  errors?: string[];
}

/// uleb128 编码（证人壳 code 段尺寸用）
export function uleb(n: number): number[] {
  const out: number[] = [];
  let v = n;
  do {
    let b = v & 0x7f;
    v >>>= 7;
    if (v !== 0) b |= 0x80;
    out.push(b);
  } while (v !== 0);
  return out;
}

/// 禁译表（EmitError 豁免面——「目录/文件名」键；首版空：全语料摸底 0 例）
function loadDeferred(): Set<string> {
  const raw = JSON.parse(fs.readFileSync(path.join(scriptDir, "deferred.json"), "utf8")) as string[];
  return new Set(raw);
}

/// 基线钉住（审阅 P2-1：绿项基数对账——ok 数下跌即红，扫描面退化/目录
/// 改名/管线整体退到编译失败时闸不再全绿；**增长**（新增语料/新增可发
/// 射面）不红——改本文件随批提交）
interface Baseline {
  [dir: string]: number;
}

function loadBaseline(): Baseline {
  return JSON.parse(fs.readFileSync(path.join(scriptDir, "baseline.json"), "utf8")) as Baseline;
}

/// 递归数目录下 .c 条数（与 dump_wasm 的 collect_c_files 同口径——审阅
/// P3-1 后两端口径必须一致，否则条数对账假红）
function countCFiles(dir: string): number {
  let n = 0;
  for (const name of fs.readdirSync(dir)) {
    const full = path.join(dir, name);
    if (fs.statSync(full).isDirectory()) {
      n += countCFiles(full);
    } else if (name.endsWith(".c")) {
      n += 1;
    }
  }
  return n;
}

/// 判定一目录的 JSONL 行集 → 红项清单（emit/verify 失败 + wabt 验证失败）
export function judgeLines(
  lines: ReadonlyArray<DumpLine>,
  dirLabel: string,
  deferred: ReadonlySet<string>,
  validateModule: (moduleHex: string, file: string) => string | null,
): { reds: string[]; okN: number; compileFail: number } {
  const reds: string[] = [];
  let okN = 0;
  let compileFail = 0;
  for (const l of lines) {
    const key = `${dirLabel}/${l.file}`;
    if (l.ok) {
      okN += 1;
      // 垫收证人模块（批 2a）——缺字段 = 产物形态破损，空字节过
      // readWasm 自然红（fail loud，不静默放行）
      const err = validateModule(l.module ?? "", key);
      if (err !== null) reds.push(`${key}: wabt 验证红——${err}`);
      continue;
    }
    if (l.stage === "emit" || l.stage === "verify") {
      if (deferred.has(key)) continue;
      if (l.stage === "emit") {
        reds.push(`${key}: 发射失败 gip=${l.gip ?? "?"} op=${l.op ?? "?"} reason=${l.reason ?? "?"}（禁译面须在 deferred.json 登记）`);
      } else {
        reds.push(`${key}: 装载核对红 ${l.kind ?? ""} ${l.detail ?? ""}`);
      }
      continue;
    }
    compileFail += 1;
  }
  return { reds, okN, compileFail };
}

/// 垫收证人模块的内容级验证器（wabt `m.validate()`——类型/栈/指令签名
/// 全检；批 2a 升级件：readWasm 只解码不校验，见头注。node:test 的 J9
/// 锚消费——非法样本必红的自证）。
export async function loadWabtValidate(): Promise<(moduleHex: string, file: string) => string | null> {
  const wabtInit = (await import("wabt")).default;
  const wabt = await wabtInit();
  return (moduleHex: string, file: string): string | null => {
    const mod = Buffer.from(moduleHex, "hex");
    if (mod.length === 0) {
      return `${file} 垫收证人模块缺失（module 字段为空——产物形态破损）`;
    }
    try {
      const m = wabt.readWasm(new Uint8Array(mod), {});
      try {
        m.validate();
      } finally {
        m.destroy();
      }
      return null;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      return `${file} ${msg.split("\n").slice(0, 2).join(" | ").slice(0, 160)}`;
    }
  };
}

export async function main(): Promise<number> {
  const root = projectRoot();
  // argv 解析（审阅 P2-1 勘正：旧过滤逻辑把 --dir 吃掉后可剩空集 →
  // 「0 例 0 红 exit 0」fail-open——现剥旗取位置参；裸旗〔--dir 后无值〕
  // 与空目录集均 fail loud，不给静默全量或 0 例全绿）
  const rawArgv = process.argv.slice(2);
  if (rawArgv[rawArgv.length - 1] === "--dir") {
    console.error("--dir 后缺目录参数——fail loud");
    return 1;
  }
  const argv = rawArgv.filter((a) => a !== "--dir");
  const corpusDirs = argv.length > 0 ? argv : [...CORPUS_DIRS];
  if (corpusDirs.length === 0) {
    console.error("目录集为空——fail loud，不给 0 例全绿");
    return 1;
  }
  const baseline = loadBaseline();
  const exe = path.join(root, "moonbit", "_build", "native", "debug", "build", "cmd", "dump_wasm", "dump_wasm.exe");
  ensureFresh("emitgate", exe, ["build", "--target", "native", "cmd/dump_wasm"]);
  const validateHex = await loadWabtValidate();
  const deferred = loadDeferred();
  const totalReds: string[] = [];
  let totalOk = 0;
  let totalCompile = 0;
  for (const d of corpusDirs) {
    const corpusDir = path.join(root, "corpus", d);
    if (!fs.existsSync(corpusDir)) {
      console.error(`语料目录不存在：${d}`);
      return 1;
    }
    const r = spawnSync(exe, [corpusDir], { encoding: "utf8", maxBuffer: 256 * 1024 * 1024 });
    if (r.status !== 0) {
      console.error(`dump_wasm 跑 ${d} 失败：rc=${r.status} ${String(r.stderr).slice(0, 200)}`);
      return 1;
    }
    const lines: DumpLine[] = r.stdout
      .trim()
      .split("\n")
      .filter((x) => x.length > 0)
      .map((x) => JSON.parse(x) as DumpLine);
    // 条数对账（审阅 P2-1）：磁盘 .c 条数 vs dump_wasm 产物行数——
    // 扫描面退化（目录改名/过滤器失效/管线整体静默）即红
    const diskN = countCFiles(corpusDir);
    if (diskN !== lines.length) {
      console.error(`RED ${d}: 磁盘 .c ${diskN} != dump 行 ${lines.length}——扫描面退化（递归/过滤/管线故障）`);
      totalReds.push(`${d}: 条数对账红（磁盘 ${diskN} vs dump ${lines.length}）`);
    }
    const { reds, okN, compileFail } = judgeLines(lines, d, deferred, validateHex);
    totalOk += okN;
    totalCompile += compileFail;
    totalReds.push(...reds);
    // 基线钉住（审阅 P2-1）：ok 数低于基线即红（增长不红）
    const floorOk = baseline[d];
    if (floorOk !== undefined && okN < floorOk) {
      totalReds.push(`${d}: ok 基线红（${okN} < 基线 ${floorOk}）——发射成功率退化`);
    }
    console.log(`${d.padEnd(20)} ${String(lines.length).padStart(4)} 例：发射+核对+验证 ${okN} ok（基线 ${floorOk ?? "-"}）/ 编译期 ${compileFail}（既有防线域）/ 红 ${reds.length}`);
    for (const red of reds.slice(0, 5)) console.log(`  RED ${red}`);
  }
  console.log(`wasmenc_emitgate: 发射成功 ${totalOk} / 编译期 ${totalCompile} / 红 ${totalReds.length}（禁译表 ${deferred.size} 条）`);
  return totalReds.length === 0 ? 0 : 1;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  process.exit(await main());
}
