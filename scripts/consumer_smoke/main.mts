#!/usr/bin/env node
// consumer_smoke —— 消费侧冒烟闸（审阅 v2 A8 批，refs #438；同业 wax `embed-smoke.sh` /
// pure-py 假想下游的 Vitro 对位）。
//
// 用法（仓库根）：
//   node scripts/consumer_smoke/main.mts                                   # 两桥产物消费侧冒烟（缺省路径）
//   node scripts/consumer_smoke/main.mts --wasm <wasm.wasm> --langpack <langpack.js>
//   node scripts/consumer_smoke/main.mts --selftest                        # J9：篡改基线三路必红
//
// 定位：pkg_deps / moonbit_surface 是**静态声明面**（moon.pkg import 块、pub 符号扫描）；
// 本闸是**消费侧实证层**——以两座出口桥的真实下游身份装载产物、按产物字节枚举链接面、
// 真调用一帧，证「链接面不带」（wax 的量化语义：消费者不会被迫供给/编译它不该碰的东西）。
// 与 scripts/wasm_gateway/host.mts 的分工：host.mts 守 NDJSON 全链 + 教学 trap 断言 +
// 体积上限（includes 子集断言 / 功能性 import 为空）；本闸守**精确集**——
//   wasm 桥（gateway/wasm，wasm-gc）：
//     W1 裸编译 import 模块集 ⊆ baseline.allowed_import_modules（宿主被迫供给规范外桥 = 红）
//     W2 wasm:js-string 函数名集 == baseline.js_string_functions（供给面最小性，多/少皆红）
//     W3 export 函数名集 == pkg_deps rules.json bridges[gateway/wasm/export.mbt]（源码登记 ↔ 产物
//        字节双向对账——pkg_deps 判据⑤看源码，本闸看产物，两者相等才闭环）
//     W4 以最小供给（builtins 选项 + "_" 常量）实例化并真调用 ping + compile 一帧
//   js 桥（teaching/langpack，js）：
//     L1 动态 import() 导出键集 == bridges[teaching/langpack/export.mbt]
//     L2 texts_json() 可解析且顶层键集 == baseline.payload_top_keys
//
// 口径陷阱：node ≥23 在带 builtins 编译选项下 Module.imports() 报空（内建化）——链接面枚举
// 必须**裸编译**（`new WebAssembly.Module(buf)` 无选项）；实例化才用带选项编译。
// rc：0 绿 / 1 判红（契约漂移） / 2 致命（产物缺席、基线损坏——先构建：
//   `cd moonbit && moon build --release --target wasm-gc gateway/wasm && moon build --release --target js teaching/langpack`）。
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../internal/capi.mts";
import { instantiateGateway } from "../wasm_load.mts";
import type { GatewayExports } from "../wasm_load.mts";

export const BASELINE_PATH = "scripts/consumer_smoke/baseline.json";
export const BRIDGES_RULES_PATH = "scripts/moonbit/pkg_deps/rules.json";
export const WASM_BRIDGE_FILE = "gateway/wasm/export.mbt";
export const LANGPACK_BRIDGE_FILE = "teaching/langpack/export.mbt";

export interface Baseline {
  schema: 1;
  wasm: { allowed_import_modules: string[]; js_string_functions: string[] };
  langpack: { payload_top_keys: string[] };
}

export interface Bridges {
  files: Record<string, string[]>;
}

function fatal(msg: string): never {
  process.stderr.write(`consumer_smoke: ${msg}\n`);
  process.exit(2);
}

function byteSort(xs: readonly string[]): string[] {
  return [...xs].sort((a, b) => Buffer.compare(Buffer.from(a, "utf8"), Buffer.from(b, "utf8")));
}

export function sameSet(a: readonly string[], b: readonly string[]): boolean {
  const sa = byteSort(a);
  const sb = byteSort(b);
  return sa.length === sb.length && sa.every((x, i) => x === sb[i]);
}

export function loadBaseline(p: string): Baseline {
  const j = JSON.parse(fs.readFileSync(p, "utf8")) as Partial<Baseline>;
  if (j.schema !== 1) throw new Error(`baseline schema 不支持：${String(j.schema)}`);
  if (!j.wasm || !Array.isArray(j.wasm.allowed_import_modules) || !Array.isArray(j.wasm.js_string_functions)) throw new Error("baseline.wasm 缺字段");
  if (!j.langpack || !Array.isArray(j.langpack.payload_top_keys)) throw new Error("baseline.langpack 缺字段");
  if (j.wasm.js_string_functions.length === 0 || j.langpack.payload_top_keys.length === 0) throw new Error("baseline 空集不得绿");
  return { schema: 1, wasm: j.wasm, langpack: j.langpack };
}

export function loadBridges(p: string): Bridges {
  const j = JSON.parse(fs.readFileSync(p, "utf8")) as { bridges?: Bridges };
  if (!j.bridges || typeof j.bridges.files !== "object") throw new Error("pkg_deps rules.json 无 bridges 登记表（判据⑤脱管）");
  return j.bridges;
}

/** 产物字节层链接面（裸编译）：模块 → 名集；exports 函数名集。 */
export function linkSurface(buf: Uint8Array<ArrayBuffer>): { imports: Map<string, string[]>; exports: string[] } {
  const bare = new WebAssembly.Module(buf);
  const imports = new Map<string, string[]>();
  for (const i of WebAssembly.Module.imports(bare)) {
    const arr = imports.get(i.module) ?? [];
    arr.push(i.name);
    imports.set(i.module, arr);
  }
  const exports = WebAssembly.Module.exports(bare)
    .filter((e) => e.kind === "function")
    .map((e) => e.name);
  return { imports, exports: byteSort(exports) };
}

export type Finding = { id: string; ok: boolean; detail: string };

/** W1–W3 纯判定（产物面 + 基线 + bridges）；W4/L1/L2 在 run() 里真调用。 */
export function judgeWasmSurface(surf: { imports: Map<string, string[]>; exports: string[] }, b: Baseline, bridges: Bridges): Finding[] {
  const out: Finding[] = [];
  const mods = byteSort([...surf.imports.keys()]);
  const stray = mods.filter((m) => !b.wasm.allowed_import_modules.includes(m));
  out.push({
    id: "W1 import 模块集 ⊆ 允许集",
    ok: stray.length === 0 && mods.includes("_"),
    detail: stray.length > 0 ? `规范外模块 ${stray.join(", ")}（宿主被迫供给）` : mods.includes("_") ? `模块集 [${mods.join(", ")}]` : "「_」常量模块缺席（产物形态变/装载层失配）",
  });
  const js = surf.imports.get("wasm:js-string") ?? [];
  out.push({
    id: "W2 js-string 函数集 == 基线",
    ok: sameSet(js, b.wasm.js_string_functions),
    detail: `产物 [${byteSort(js).join(", ")}] vs 基线 [${byteSort(b.wasm.js_string_functions).join(", ")}]`,
  });
  const want = bridges.files[WASM_BRIDGE_FILE] ?? [];
  out.push({
    id: "W3 export 函数集 == bridges 登记（源码↔产物）",
    ok: want.length > 0 && sameSet(surf.exports, want),
    detail: `产物 [${surf.exports.join(", ")}] vs bridges [${byteSort(want).join(", ")}]`,
  });
  return out;
}

export function judgeLangpack(exportKeys: readonly string[], payloadTopKeys: readonly string[], b: Baseline, bridges: Bridges): Finding[] {
  const want = bridges.files[LANGPACK_BRIDGE_FILE] ?? [];
  return [
    {
      id: "L1 langpack 导出键集 == bridges 登记",
      ok: want.length > 0 && sameSet(exportKeys, want),
      detail: `import() 得 [${byteSort(exportKeys).join(", ")}] vs bridges [${byteSort(want).join(", ")}]`,
    },
    {
      id: "L2 texts_json() 顶层键集 == 基线",
      ok: sameSet(payloadTopKeys, b.langpack.payload_top_keys),
      detail: `载荷 [${byteSort(payloadTopKeys).join(", ")}] vs 基线 [${byteSort(b.langpack.payload_top_keys).join(", ")}]`,
    },
  ];
}

function defaultWasm(root: string): string {
  const rel = path.join(root, "moonbit/_build/wasm-gc/release/build/gateway/wasm/wasm.wasm");
  const dbg = path.join(root, "moonbit/_build/wasm-gc/debug/build/gateway/wasm/wasm.wasm");
  return fs.existsSync(rel) ? rel : dbg;
}

function defaultLangpack(root: string): string {
  return path.join(root, "moonbit/_build/js/release/build/teaching/langpack/langpack.js");
}

async function consumeWasm(buf: Uint8Array<ArrayBuffer>): Promise<Finding> {
  try {
    const inst = await instantiateGateway(buf);
    const g = inst.exports as unknown as GatewayExports;
    const ping = JSON.parse(g.invoke('{"id":1,"method":"ping"}')) as { ok?: boolean };
    const src = JSON.stringify("int main(){ return 3; }\n");
    const c = JSON.parse(g.invoke(`{"id":2,"method":"compile","params":{"source":${src}}}`)) as { ok?: boolean; result?: { ok?: boolean } };
    const r = JSON.parse(g.invoke('{"id":3,"method":"run"}')) as { result?: { status?: string; return_value?: number } };
    const ok = ping.ok === true && c.ok === true && c.result?.ok === true && r.result?.status === "finished" && r.result?.return_value === 3;
    return { id: "W4 最小供给实例化 + ping/compile/run 真调用", ok, detail: ok ? `protocol ${g.protocol_version()} · engine ${g.engine_version()} · run→3` : `ping=${JSON.stringify(ping)} compile=${JSON.stringify(c).slice(0, 100)} run=${JSON.stringify(r).slice(0, 100)}` };
  } catch (e) {
    return { id: "W4 最小供给实例化 + ping/compile/run 真调用", ok: false, detail: e instanceof Error ? e.message : String(e) };
  }
}

async function consumeLangpack(p: string): Promise<{ exportKeys: string[]; topKeys: string[]; err: string | null }> {
  try {
    const m = (await import(pathToFileURL(p).href)) as Record<string, unknown>;
    const exportKeys = Object.keys(m).filter((k) => k !== "default");
    const fn = m["texts_json"];
    if (typeof fn !== "function") return { exportKeys, topKeys: [], err: "texts_json 非函数" };
    const s = (fn as () => unknown)();
    if (typeof s !== "string") return { exportKeys, topKeys: [], err: `texts_json 返回 ${typeof s}` };
    const j = JSON.parse(s) as unknown;
    if (j === null || typeof j !== "object" || Array.isArray(j)) return { exportKeys, topKeys: [], err: "载荷非对象" };
    return { exportKeys, topKeys: Object.keys(j as object), err: null };
  } catch (e) {
    return { exportKeys: [], topKeys: [], err: e instanceof Error ? e.message : String(e) };
  }
}

function printFindings(fs_: Finding[]): boolean {
  let ok = true;
  for (const f of fs_) {
    process.stdout.write(`  ${f.ok ? "PASS" : "FAIL"}  ${f.id}  ${f.detail}\n`);
    if (!f.ok) ok = false;
  }
  return ok;
}

/** J9：真产物 + 篡改基线三路（js-string 少一 / 允许集去 js-string / bridges export 注入假名）各自必红。 */
function selftest(surf: { imports: Map<string, string[]>; exports: string[] }, b: Baseline, bridges: Bridges): number {
  if (!judgeWasmSurface(surf, b, bridges).every((f) => f.ok)) {
    process.stdout.write("consumer_smoke: selftest ABORT——基线不绿，注入后的红无法归因\n");
    return 2;
  }
  const probes: Array<[string, Baseline, Bridges]> = [
    ["js-string 少一函数", { ...b, wasm: { ...b.wasm, js_string_functions: b.wasm.js_string_functions.slice(1) } }, bridges],
    ["允许集剔除 wasm:js-string", { ...b, wasm: { ...b.wasm, allowed_import_modules: ["_"] } }, bridges],
    ["bridges export 注入假名", b, { files: { ...bridges.files, [WASM_BRIDGE_FILE]: [...(bridges.files[WASM_BRIDGE_FILE] ?? []), "zz_fake"] } }],
  ];
  for (const [label, pb, pbr] of probes) {
    if (judgeWasmSurface(surf, pb, pbr).every((f) => f.ok)) {
      process.stdout.write(`consumer_smoke: selftest FAIL——篡改「${label}」后仍判绿，闸门失效\n`);
      return 1;
    }
  }
  process.stdout.write("consumer_smoke: selftest PASS——三路篡改（js-string 少一/允许集收窄/export 注入）全部被捕获（红）\n");
  return 0;
}

export async function main(argv: string[]): Promise<number> {
  const root = projectRoot();
  let wasmPath = "";
  let lpPath = "";
  let self = false;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]!;
    if (a === "--wasm") wasmPath = argv[++i] ?? fatal("--wasm 缺参数");
    else if (a === "--langpack") lpPath = argv[++i] ?? fatal("--langpack 缺参数");
    else if (a === "--selftest") self = true;
    else fatal(`未知参数: ${a}（可用：--wasm <p> / --langpack <p> / --selftest）`);
  }
  if (wasmPath === "") wasmPath = defaultWasm(root);
  if (lpPath === "") lpPath = defaultLangpack(root);
  if (!fs.existsSync(wasmPath)) fatal(`wasm 产物缺席：${wasmPath}——先 cd moonbit && moon build --release --target wasm-gc gateway/wasm`);
  let b: Baseline;
  let bridges: Bridges;
  try {
    b = loadBaseline(path.join(root, BASELINE_PATH));
    bridges = loadBridges(path.join(root, BRIDGES_RULES_PATH));
  } catch (e) {
    fatal(e instanceof Error ? e.message : String(e));
  }
  // 严格档：Buffer<ArrayBufferLike> 不可赋 BufferSource（SharedArrayBuffer 联合）——拷贝为 ArrayBuffer 支撑
  const buf = new Uint8Array(fs.readFileSync(wasmPath));
  const surf = linkSurface(buf);
  if (self) return selftest(surf, b, bridges);

  process.stdout.write(`consumer_smoke: wasm 桥 ${path.relative(root, wasmPath)}（${buf.length} B）\n`);
  let ok = printFindings(judgeWasmSurface(surf, b, bridges));
  ok = printFindings([await consumeWasm(buf)]) && ok;

  if (!fs.existsSync(lpPath)) fatal(`langpack 产物缺席：${lpPath}——先 cd moonbit && moon build --release --target js teaching/langpack`);
  process.stdout.write(`consumer_smoke: js 桥 ${path.relative(root, lpPath)}（${fs.statSync(lpPath).size} B）\n`);
  const lp = await consumeLangpack(lpPath);
  if (lp.err !== null) {
    ok = printFindings([{ id: "L0 langpack 动态 import() 真消费", ok: false, detail: lp.err }]) && ok;
  } else {
    ok = printFindings(judgeLangpack(lp.exportKeys, lp.topKeys, b, bridges)) && ok;
  }
  process.stdout.write(ok ? "consumer_smoke: PASS（两桥消费侧契约成立：链接面精确集 + 真调用）\n" : "consumer_smoke: FAIL——消费侧契约漂移（详见上方；改出口面须连坐 pkg_deps bridges / 本闸 baseline.json）\n");
  return ok ? 0 : 1;
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  main(process.argv.slice(2)).then((rc) => process.exit(rc), (e) => fatal(e instanceof Error ? e.message : String(e)));
}
