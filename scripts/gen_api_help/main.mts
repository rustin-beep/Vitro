#!/usr/bin/env node
// gen_api_help.mts —— gateway 权威源 → api help 双产物（#273 存量 Go 重写批；
// 原 go scripts/gen_api_help，2026-10-11，refs #67）。
//
// 动机（#67 三连试错实录）：api 方法参数形状无离线可发现路径——下游接入只能
// 读 serve_*.mbt 源码考古。#68 已把形状落进 serve_param_err 的 expected 字段
//（代码即真值）；本生成器把「方法清单（dispatch）+ 形状（serve_param_err）+
// 手写补充面（rules：简介/示例）」烘成离线 help **预渲染文本**双产物——渲染
// 逻辑单源在生成器，消费端只查表打印（逐字节同形由 -check 幂等 + vitro_cli_smoke
// 双臂对拍双锁）。
//
// 权威源与契约（照 gen_protocol_ts）：
//
//   ① 方法清单 = protocol.mbt 的 dispatch 臂（段内正则提取；空集红、
//      计数与 rules.expected_method_count 漂移红）
//   ② 形状 = gateway serve_*.mbt 的 serve_param_err 调用点（#68 机器可读
//      expected 字面量）——方法名按 message 前缀归位；「请求缺少 method」
//      是请求顶层要求非方法级，显式跳过
//   ③ 双向对账：dispatch 方法缺 rules 简介红；rules 简介无对应 dispatch
//      方法红（多/缺两个方向都咬合）
//   ④ -check 幂等：磁盘双产物 == 现场生成，否则红并给再生命令
//   ⑤ --selftest 四路内存注入证红（方法计数漂移 / 形状面可提取性 / 简介缺失 /
//      非规范形态静默塌缩）——J9 义务
//
// 产物：moonbit/cmd/lib/cli/api_help_gen.mbt（cmd/lib/cli 查表）
// 规则外置 scripts/gen_api_help/rules.json（#125 批 B 后 = 入库真源手改面）。
//
// 用法：node scripts/gen_api_help/main.mts [-check] [-selftest]
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { projectRoot, fatal } from "../internal/capi.mts";
import { goQuote, padEndRunes, sortBytes } from "../internal/gofmt.mts";

const RULES_PATH = "scripts/gen_api_help/rules.json";
const DISPATCH_PATH = "moonbit/gateway/protocol.mbt";
const GATEWAY_DIR = "moonbit/gateway";
const OUT_MBT = "moonbit/cmd/lib/cli/api_help_gen.mbt";

export interface MethodHelp {
  method: string;
  brief: string;
  example: string;
}
export interface ShapeSkipAllow {
  prefix: string;
  reason: string;
}
export interface Rules {
  schema: number;
  expected_method_count: number;
  methods: MethodHelp[];
  shape_skip_allow: ShapeSkipAllow[];
}

/** serve_param_err(id, "message", "expected") 提取形态（跨行、icons 多行同形）。 */
export interface ParamErr {
  message: string;
  expected: string;
}

const ARM_RE = /^\s{4}"([a-z_.]+)"\s*=>/gm;
const PARAM_ERR_RE = /serve_param_err\(\s*\w+,\s*"([^"]*)",\s*"([^"]*)"/g;
const FN_RE = /^(pub )?fn /m;

function root(): string {
  return projectRoot();
}

function readAll(rel: string, what = rel): string {
  try {
    return fs.readFileSync(path.join(root(), rel), "utf8");
  } catch (e) {
    return fatal(`读 ${what} 失败: ${(e as Error).message}`);
  }
}

function readJSON<T>(rel: string): T {
  const b = readAll(rel);
  try {
    return JSON.parse(b) as T;
  } catch (e) {
    return fatal(`解析 ${rel} 失败: ${(e as Error).message}`);
  }
}

/** 提取 dispatch 段的方法臂——段边界 = `fn dispatch(` 起、下一个顶层 fn 止。 */
export function extractDispatch(): { methods: string[]; errs: string[] } {
  const src = readAll(DISPATCH_PATH);
  const lines = src.split("\n");
  let start = -1;
  let end = -1;
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i] ?? "";
    if (l.startsWith("fn dispatch(")) {
      start = i;
    } else if (start >= 0 && FN_RE.test(l)) {
      end = i;
      break;
    }
  }
  if (start < 0) return { methods: [], errs: ["protocol.mbt 无 fn dispatch("] };
  if (end < 0) end = lines.length;
  const seg = lines.slice(start, end).join("\n");
  const methods: string[] = [];
  for (const m of seg.matchAll(ARM_RE)) methods.push(m[1] ?? "");
  if (methods.length === 0) {
    return { methods: [], errs: ["dispatch 段零方法臂（空集不得绿）"] };
  }
  return { methods, errs: [] };
}

/** 扫 gateway 包源（排除 wbtest）提取 serve_param_err 调用点。 */
export function extractShapes(): {
  shapes: Map<string, string>;
  skipped: ParamErr[];
  errs: string[];
} {
  let entries: string[];
  try {
    entries = fs.readdirSync(path.join(root(), GATEWAY_DIR));
  } catch (e) {
    return { shapes: new Map(), skipped: [], errs: [(e as Error).message] };
  }
  // Go os.ReadDir 返回排序结果——显式补排序，防「首个命中」类口径漂移
  const found: ParamErr[] = [];
  for (const name of sortBytes(entries)) {
    if (!name.endsWith(".mbt") || name.includes("wbtest")) continue;
    const src = readAll(path.posix.join(GATEWAY_DIR, name));
    for (const m of src.matchAll(PARAM_ERR_RE)) {
      found.push({ message: m[1] ?? "", expected: m[2] ?? "" });
    }
  }
  if (found.length === 0) {
    return { shapes: new Map(), skipped: [], errs: ["零 serve_param_err 调用点（#68 收编面被删？）"] };
  }
  const { shapes, skipped } = shapeByMethod(found);
  return { shapes, skipped, errs: [] };
}

/**
 * 按 message 前缀归位方法（长方法名先试防短名误配）。
 * 「请求缺少 method 字段」不匹配任何方法 → 显式跳过（请求顶层要求）。
 * 非规范形态不吞（2026-10-17 审阅 P3-⑥：原样 return 只归位、未知形态 continue
 * 无计数无告警，config.set 未知键错误整条静默塌缩）。
 */
function shapeByMethod(found: ParamErr[]): { shapes: Map<string, string>; skipped: ParamErr[] } {
  const out = new Map<string, string>();
  const skipped: ParamErr[] = [];
  for (const p of found) {
    if (p.message.startsWith("请求缺少")) continue; // 请求顶层（非方法级 params）
    // message 形态（#68 落码）：<method> 需要… / <method> 的…
    let name = "";
    const iNeed = p.message.indexOf(" 需要");
    const iDe = p.message.indexOf(" 的 ");
    if (iNeed > 0) name = p.message.slice(0, iNeed);
    else if (iDe > 0) name = p.message.slice(0, iDe);
    if (name === "") {
      skipped.push(p); // 未知形态——须过 shape_skip_allow 显式豁免
      continue;
    }
    out.set(name, p.expected); // 同方法多形状：后者覆盖（Go 版同口径）
  }
  return { shapes: out, skipped };
}

/** 静默跳过双向闸：每条非规范形态须命中一条豁免前缀；每条豁免须被命中。 */
export function checkShapeSkips(rules: Rules, skipped: ParamErr[]): string[] {
  const errs: string[] = [];
  const used = new Set<number>();
  for (const p of skipped) {
    let hit = false;
    const allow = rules.shape_skip_allow ?? [];
    for (let i = 0; i < allow.length; i++) {
      if (p.message.startsWith(allow[i]?.prefix ?? "")) {
        hit = true;
        used.add(i);
        break;
      }
    }
    if (!hit) {
      errs.push(
        `serve_param_err 非规范形态未豁免（message=${goQuote(p.message)} expected=${goQuote(
          p.expected,
        )}）——改规范形态（<method> 需要…/<method> 的…）或在 rules.json shape_skip_allow 登记前缀+理由`,
      );
    }
  }
  const allow = rules.shape_skip_allow ?? [];
  for (let i = 0; i < allow.length; i++) {
    if (!used.has(i)) {
      errs.push(
        `shape_skip_allow 僵尸豁免（prefix=${goQuote(allow[i]?.prefix ?? "")} reason=${goQuote(
          allow[i]?.reason ?? "",
        )}）——无命中条目，删或改`,
      );
    }
  }
  return errs;
}

/** 双向对账：dispatch↔rules（多/缺都红）+ 形状面完整性。 */
export function reconcile(methods: string[], rules: Rules, shapes: Map<string, string>): string[] {
  const errs: string[] = [];
  if (methods.length !== rules.expected_method_count) {
    errs.push(
      `方法计数漂移：dispatch ${methods.length} ≠ rules.expected_method_count ${rules.expected_method_count}（增删方法须连坐 rules.json.mbt）`,
    );
  }
  const ruleSet = new Map<string, MethodHelp>();
  for (const m of rules.methods) ruleSet.set(m.method, m);
  const methodSet = new Set(methods);
  for (const m of methods) {
    if (!ruleSet.has(m)) errs.push(`dispatch 方法 '${m}' 缺 rules 简介（补 rules.json）`);
  }
  for (const name of ruleSet.keys()) {
    if (!methodSet.has(name)) errs.push(`rules 简介方法 '${name}' 不在 dispatch（僵尸条目须删）`);
  }
  // 形状完整性：shapes 的每个键必须是 dispatch 方法（两处真相源互锁）
  for (const name of shapes.keys()) {
    if (!methodSet.has(name)) {
      errs.push(`形状提取方法 '${name}' 不在 dispatch（serve_param_err 落错方法名前缀？）`);
    }
  }
  return errs;
}

/** 预渲染最终文本（渲染逻辑单源在此；消费端只载文本）。 */
export function render(methods: string[], rules: Rules, shapes: Map<string, string>): string {
  const ruleSet = new Map<string, MethodHelp>();
  for (const m of rules.methods) ruleSet.set(m.method, m);
  const sorted = sortBytes([...methods]);

  const lines: string[] = [];
  lines.push(`api 方法清单（${methods.length}）——api help <method> 看单方法详情：\n`);
  for (const m of sorted) {
    lines.push(`  ${padEndRunes(m, 20)} ${ruleSet.get(m)?.brief ?? ""}\n`);
  }
  const listText = lines.join("");

  const detail = new Map<string, string>();
  for (const m of sorted) {
    const r = ruleSet.get(m);
    let d = `${m}——${r?.brief ?? ""}\n`;
    const shape = shapes.get(m);
    d += shape !== undefined ? `  params: ${shape}\n` : "  params: 无必填（缺省 {}）\n";
    d += `  例: vitro api ${m} '${r?.example ?? ""}'\n`;
    detail.set(m, d.replace(/\n$/, "")); // 尾换行由打印层补——双臂同形单尾
  }

  return renderMoonBit(listText, detail);
}

function renderMoonBit(list: string, detail: Map<string, string>): string {
  let b = "";
  b += "// @generated by scripts/gen_api_help——勿手改（-check 幂等锁；再生：go run ./scripts/gen_api_help）。\n";
  b += "// #67 api help 离线可发现性出口：方法清单/形状权威源 = gateway dispatch\n";
  b += "// + serve_param_err（#68 expected 字段），简介/示例 = scripts/gen_api_help/rules。\n";
  b += "// 本文件只承载预渲染文本（渲染单源在生成器）；消费面 = cmd/lib/cli\n";
  b += "// 的 api help 子命令（wasm 臂同数据走 scripts/vitro_cli/api_help.json）。\n\n";
  b += "///|\n/// 全方法清单文本（api help 无参时打印）。\npub fn api_help_list() -> String {\n";
  b += '  "' + mbtEscape(list) + '"\n}\n\n';
  b +=
    "///|\n/// 单方法详情文本（api help <method> 时打印；未知方法 None——rc=4 用法错）。\n" +
    "/// 形参名 m 非 method：reserved_keyword 0035（#46 在册——形参避开保留字，\n" +
    "/// 协议层字段名不受影响）。\npub fn api_help_detail(m : String) -> String? {\n  match m {\n";
  for (const k of sortBytes([...detail.keys()])) {
    // match 臂体产出 moon fmt 合规形态（fmt 会把单行 Some("...") 拆为多行悬挂
    // + 尾逗号）——产出即合规，避免「fmt 改产物 / -check 再生」互斥。
    b += `    "${k}" =>\n      Some(\n        "${mbtEscape(detail.get(k) ?? "")}",\n      )\n`;
  }
  b += "    _ => None\n  }\n}\n";
  return b;
}

/** MoonBit 字符串字面量转义（顺序敏感：\ 先、然后 "、最后真实换行）。 */
export function mbtEscape(s: string): string {
  return s.split("\\").join("\\\\").split('"').join('\\"').split("\n").join("\\n");
}

function checkFile(rel: string, want: string): void {
  let got: string;
  try {
    got = fs.readFileSync(path.join(root(), rel), "utf8");
  } catch {
    fatal(`-check: ${rel} 不存在——先 go run ./scripts/gen_api_help 再生`);
  }
  if (got !== want) {
    fatal(`-check: ${rel} 与现场生成不一致——go run ./scripts/gen_api_help 再生`);
  }
}

function selftestAll(): void {
  let fail = 0;
  const { methods: orig } = extractDispatch();

  // 路 1：方法计数漂移（dispatch 增删未连坐 rules）
  if (orig.length === 0) {
    process.stdout.write("selftest 路 1 跳过（提取面空）\n");
  } else {
    const rules = readJSON<Rules>(RULES_PATH);
    const err = checkCount(orig.length, rules.expected_method_count + 1);
    if (err === null) {
      process.stdout.write("selftest 路 1 FAIL：计数漂移未红\n");
      fail++;
    } else {
      process.stdout.write(`selftest 路 1 OK（计数漂移红：${err}）\n`);
    }
  }

  // 路 2：形状字面量篡改（serve_param_err expected 改字 → 归位/对账面变化）
  const shapeRes = extractShapes();
  if (shapeRes.shapes.size === 0) {
    process.stdout.write("selftest 路 2 跳过（形状面空）\n");
  } else {
    process.stdout.write(
      `selftest 路 2 OK（形状面 ${shapeRes.shapes.size} 条可提取——篡改检测由 -check 幂等与 reconcile 承担）\n`,
    );
  }

  // 路 3：rules 简介缺失（dispatch 方法无简介 → reconcile 红）
  const rules3 = readJSON<Rules>(RULES_PATH);
  rules3.methods = rules3.methods.slice(0, Math.max(0, rules3.methods.length - 1));
  const errs3 = reconcile(orig, rules3, shapeRes.shapes);
  if (errs3.length === 0) {
    process.stdout.write("selftest 路 3 FAIL：简介缺失未红\n");
    fail++;
  } else {
    process.stdout.write(`selftest 路 3 OK（简介缺失红：${errs3[0]}）\n`);
  }

  // 路 4（2026-10-17 审阅 P3-⑥）：非规范形态静默塌缩闸——未豁免跳过红 +
  // 僵尸豁免红（双向）
  const rules4 = readJSON<Rules>(RULES_PATH);
  rules4.shape_skip_allow = [];
  const errs4 = checkShapeSkips(rules4, [
    { message: "config.set 收到未知配置键 'zzz'", expected: "keys:白名单" },
  ]);
  if (errs4.length === 0) {
    process.stdout.write("selftest 路 4 FAIL：未豁免跳过未红\n");
    fail++;
  } else {
    process.stdout.write(`selftest 路 4 OK（未豁免跳过红：${errs4[0]}）\n`);
  }

  const errs5 = checkShapeSkips({ shape_skip_allow: [{ prefix: "zzz 前缀", reason: "r" }] } as Rules, []);
  if (errs5.length === 0) {
    process.stdout.write("selftest 路 4 FAIL：僵尸豁免未红\n");
    fail++;
  } else {
    process.stdout.write(`selftest 路 4 OK（僵尸豁免红：${errs5[0]}）\n`);
  }

  if (fail > 0) process.exit(2);
  process.stdout.write("gen_api_help selftest 全过\n");
}

function checkCount(got: number, want: number): string | null {
  return got !== want ? `dispatch ${got} ≠ expected ${want}` : null;
}

function writeFile(rel: string, content: string): void {
  const p = path.join(root(), rel);
  try {
    fs.writeFileSync(p, content, { mode: 0o644 });
  } catch (e) {
    fatal(`写 ${p} 失败: ${(e as Error).message}`);
  }
}

function main(): void {
  const argv = process.argv.slice(2);
  const check = argv.includes("-check") || argv.includes("--check");
  const selftest = argv.includes("-selftest") || argv.includes("--selftest");
  for (const a of argv) {
    if (!["-check", "--check", "-selftest", "--selftest"].includes(a)) {
      fatal(`未知参数 ${a}（用法：node scripts/gen_api_help/main.mts [-check] [-selftest]）`);
    }
  }

  if (selftest) {
    selftestAll();
    return;
  }

  const d = extractDispatch();
  if (d.errs.length > 0) fatal(`dispatch 提取失败: ${d.errs.join(" / ")}`);

  const rules = readJSON<Rules>(RULES_PATH);
  if (rules.methods.length === 0) fatal("rules.methods 空集不得绿");

  const s = extractShapes();
  if (s.errs.length > 0) fatal(`serve_param_err 提取失败: ${s.errs.join(" / ")}`);

  const recErr = reconcile(d.methods, rules, s.shapes);
  if (recErr.length > 0) fatal(`双向对账不符:\n  ${recErr.join("\n  ")}`);

  const skipErr = checkShapeSkips(rules, s.skipped);
  if (skipErr.length > 0) fatal(`形状面豁免对账不符（静默塌缩闸）:\n  ${skipErr.join("\n  ")}`);

  const mbtSrc = render(d.methods, rules, s.shapes);

  if (check) {
    checkFile(OUT_MBT, mbtSrc);
    process.stdout.write("gen_api_help: check OK（产物与现场生成逐字节一致）\n");
    return;
  }
  writeFile(OUT_MBT, mbtSrc);
  process.stdout.write(`gen_api_help: 产物已再生（${d.methods.length} 方法）→ ${OUT_MBT}\n`);
}

// 入口守卫：被 node:test import 时只取纯函数，不落盘
if (
  process.argv[1] !== undefined &&
  pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url
) {
  main();
}
