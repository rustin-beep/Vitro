// wasmenc_emitgate —— REHOST 批 1c 产物闸（设计单 §3.2 批 1 验收面①③）：
// 全语料「153/154 码表 → wasm 子集」发射成功率 100% + 装载核对全过 +
// wabt 二进制验证全过（证人壳拼装）——三级判定的 .mts 驱动。
//
// 消费链：cmd/dump_wasm（native exe，ensureFresh 新鲜度门禁）逐语料目录
// 批跑出 JSONL → 本脚本逐行判定：
//   1. ok:true → hex（指令区字节）拼证人壳（type ()->()/memory 16 页/
//      6 globals 装载约定/locals 4 runs/export main）→ wabt readWasm
//      二进制验证——「发射字节 = 合法 wasm」的第三方证人（wasm-validate
//      内容级；watcheck 是更强的逐字节恒等，但语料面只有本闸全覆盖）；
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

/// 证人壳拼装：指令区字节 → 完整合法 wasm 模块（validate-only，非产物——
/// 段结构固定：type ()->() / memory {16,16} / 6 globals（G_PC..G_RET i32 +
/// G_RV i64，装载约定单源 = wasmenc template.mbt 全局槽表）/ export main /
/// code（locals 4 runs = 3×i32+i64+f64+f32，批 1b 装载约定）。批 2 模块
/// 组装（dispatch-loop 语义模块）不是本面——本壳只证「指令区字节在合法
/// 模块语境下过二进制验证」。
export function buildWitnessModule(instrs: ReadonlyArray<number>): number[] {
  const globals: number[] = [];
  for (let i = 0; i < 5; i += 1) globals.push(0x7f, 0x01, 0x41, 0x00, 0x0b);
  globals.push(0x7e, 0x01, 0x42, 0x00, 0x0b);
  const locals: number[] = [0x04, 0x03, 0x7f, 0x01, 0x7e, 0x01, 0x7c, 0x01, 0x7d];
  const body = [...locals, ...instrs, 0x0b];
  const codeBody = [0x01, ...uleb(body.length), ...body];
  const seg = (id: number, payload: ReadonlyArray<number>): number[] => [id, ...uleb(payload.length), ...payload];
  return [
    0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
    ...seg(0x01, [0x01, 0x60, 0x00, 0x00]),
    ...seg(0x03, [0x01, 0x00]),
    ...seg(0x05, [0x01, 0x01, 0x10, 0x10]),
    ...seg(0x06, [0x06, ...globals]),
    ...seg(0x07, [0x01, 0x04, 0x6d, 0x61, 0x69, 0x6e, 0x00, 0x00]),
    ...seg(0x0a, codeBody),
  ];
}

/// 禁译表（EmitError 豁免面——「目录/文件名」键；首版空：全语料摸底 0 例）
function loadDeferred(): Set<string> {
  const raw = JSON.parse(fs.readFileSync(path.join(scriptDir, "deferred.json"), "utf8")) as string[];
  return new Set(raw);
}

/// 判定一目录的 JSONL 行集 → 红项清单（emit/verify 失败 + wabt 验证失败）
export function judgeLines(
  lines: ReadonlyArray<DumpLine>,
  dirLabel: string,
  deferred: ReadonlySet<string>,
  validateHex: (hex: string, file: string) => string | null,
): { reds: string[]; okN: number; compileFail: number } {
  const reds: string[] = [];
  let okN = 0;
  let compileFail = 0;
  for (const l of lines) {
    const key = `${dirLabel}/${l.file}`;
    if (l.ok) {
      okN += 1;
      const hex = l.hex ?? "";
      const err = validateHex(hex, key);
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

async function loadWabtValidate(): Promise<(hex: string, file: string) => string | null> {
  const wabtInit = (await import("wabt")).default;
  const wabt = await wabtInit();
  return (hex: string, file: string): string | null => {
    const instrs = Buffer.from(hex, "hex");
    const mod = buildWitnessModule(Array.from(instrs));
    try {
      const m = wabt.readWasm(new Uint8Array(mod), {});
      m.destroy();
      return null;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      return `${file} ${msg.split("\n").slice(0, 2).join(" | ").slice(0, 160)}`;
    }
  };
}

export async function main(): Promise<number> {
  const root = projectRoot();
  const argv = process.argv.slice(2);
  const dirs = argv.filter((a, i) => i > 0 || a !== "--dir");
  const corpusDirs = argv.length > 0 ? dirs : CORPUS_DIRS;
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
    const { reds, okN, compileFail } = judgeLines(lines, d, deferred, validateHex);
    totalOk += okN;
    totalCompile += compileFail;
    totalReds.push(...reds);
    console.log(`${d.padEnd(20)} ${String(lines.length).padStart(4)} 例：发射+核对+验证 ${okN} ok / 编译期 ${compileFail}（既有防线域）/ 红 ${reds.length}`);
    for (const red of reds.slice(0, 5)) console.log(`  RED ${red}`);
  }
  console.log(`wasmenc_emitgate: 发射成功 ${totalOk} / 编译期 ${totalCompile} / 红 ${totalReds.length}（禁译表 ${deferred.size} 条）`);
  return totalReds.length === 0 ? 0 : 1;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  process.exit(await main());
}
