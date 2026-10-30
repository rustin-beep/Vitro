#!/usr/bin/env node
// gen_protocol_ts.mts —— 从权威源生成 `@vitro/protocol` 的 TS 类型定义与字段集
// 元数据（#273 存量 Go 重写批；原 go scripts/gen_protocol_ts，架构审阅 v2 A 组
// #9 / §7.5）。
//
// 动机（E-08 的「结构性一半」）：L9 外置把教学正确性移到了防线之外。TS 侧的
// **字段级错误**（字段名写错 / 字段缺失 / 版本不匹配）本可在编译期即红——前提
// 是 TS 侧有**从权威源生成**的类型，而不是手抄。手抄就是又一处分叉温床。
//
// 权威源（2026-10-05 删区后勘正——#118）：moonbit/protocol/types.mbt（MoonBit
// 结构体，protocol 包零依赖自持）。moonbit/docs/spec/STEP_PAYLOAD_SCHEMA_V0_1.md 是
// **表述层**（人工维护的 markdown 表格）。故取「从实现生成 + 与文档双向对账」：
// 任一方向不同步都判红——把「文档与实现是否一致」变成机器判据。
//
// 判据：
//   ① -check 幂等：磁盘产物 == 现场生成（否则红，提示重跑生成）
//   ② 字段集双向对账：MoonBit 生成源字段集 == schema 文档表格字段集
//   ③ 空集不得绿：解析出 0 字段、0 类型一律 fail loud
//
// 规则外置 scripts/gen_protocol_ts/rules.json；--selftest 三路内存注入证红。
//
// 用法：node scripts/gen_protocol_ts/main.mts [-check] [-selftest]
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { projectRoot, fatal } from "../internal/capi.mts";

const RULES_PATH = "scripts/gen_protocol_ts/rules.json";

export interface TypeSpec {
  name: string;
  kind: string;
}
export interface RulesDoc {
  schema: number;
  schema_version: string;
  frozen_anchor: string;
  schema_doc: string;
  type_sources: string[];
  types: TypeSpec[];
  out_ts: string;
  out_meta: string;
}

export interface ProtoField {
  name: string;
  ty: string;
}
/** 原 Go 版命名为 rustType（Rust 真源时代的遗留）；生成源已收拢 MoonBit 侧。 */
export interface ProtoType {
  name: string;
  kind: string; // "struct" | "enum"
  fields: ProtoField[];
  variants: string[];
  source: string;
}

// MoonBit 侧（生成源）：`pub(all) struct Name {` / `pub(all) enum Name {`；
// 字段行 `mut? name : Type`（mut 是存储细节非 wire 形态——剥离）；enum 变体行
// 带尾注（`Valid // 指向有效内存…`——剥注释）。
const MB_STRUCT_HEAD = /^pub\(all\)\s+struct\s+([A-Za-z_]\w*)\s*\{/gm;
const MB_ENUM_HEAD = /^pub\(all\)\s+enum\s+([A-Za-z_]\w*)\s*\{/gm;
const MB_FIELD = /^\s*(?:mut\s+)?([a-z_]\w*)\s*:\s*(.+?)\s*$/gm;
const MB_VARIANT = /^\s*([A-Z]\w*)\s*(?:\/\/[^\n]*)?$/;
const TICK_NAME = /`([A-Za-z_][A-Za-z0-9_]*)`/g;

function root(): string {
  return projectRoot();
}

function mustRead(rel: string): string {
  try {
    return fs.readFileSync(path.join(root(), rel), "utf8");
  } catch (e) {
    return fatal(`读 ${rel} 失败: ${(e as Error).message}`);
  }
}

/**
 * 判定层错误（throw 而非 exit）：解析/对账类失败在 node:test 里要能断言红，
 * 故内部函数一律 throw，由 main 统一 catch 后转 fatal（退出码与消息不变）。
 * IO 层（读不到文件 / 写盘失败）仍直接 fatal——那是环境问题不是判据。
 */
function fail(msg: string): never {
  throw new Error(msg);
}

/** 从 head 之后的首个 `{` 起，返回配对 `}` 前的体。 */
export function blockBody(src: string, headEnd: number): { body: string; ok: boolean } {
  const i = src.indexOf("{", headEnd);
  if (i < 0) return { body: "", ok: false };
  const start = i;
  let depth = 0;
  for (let j = start; j < src.length; j++) {
    const c = src[j];
    if (c === "{") depth++;
    else if (c === "}") {
      depth--;
      if (depth === 0) return { body: src.slice(start + 1, j), ok: true };
    }
  }
  return { body: "", ok: false };
}

/**
 * 从 MoonBit protocol 包源提取类型定义（生成源）：head 定位（按名字找**名为
 * name 的那个**定义）→ blockBody 花括号配对 → 字段/变体逐行提取；0 字段 /
 * 0 变体 fail loud。
 */
export function parseMoonbitTypes(
  files: string[],
  want: Map<string, TypeSpec>,
  read: (rel: string) => string = mustRead,
): Map<string, ProtoType> {
  const out = new Map<string, ProtoType>();
  for (const rel of files) {
    const src = read(rel);
    for (const [name, spec] of want) {
      if (out.has(name)) continue;
      const head = spec.kind === "struct" ? MB_STRUCT_HEAD : MB_ENUM_HEAD;
      head.lastIndex = 0;
      let loc: RegExpExecArray | null = null;
      for (let m = head.exec(src); m !== null; m = head.exec(src)) {
        loc = m[1] === name ? m : null;
        if (loc !== null) break;
      }
      if (loc === null) continue;
      // head 正则含 `\s*\{`——回到 `{` 再配对
      const headEnd = loc.index + loc[0].length - 1;
      const { body, ok } = blockBody(src, headEnd);
      if (!ok) fail(`${rel} 的 ${name} 体定位失败（花括号不配对？）`);

      const pt: ProtoType = { name, kind: spec.kind, fields: [], variants: [], source: rel };
      if (spec.kind === "struct") {
        MB_FIELD.lastIndex = 0;
        let f: RegExpExecArray | null;
        while ((f = MB_FIELD.exec(body)) !== null) {
          const ty = (f[2] ?? "").trim();
          if (ty.startsWith("(")) {
            fail(
              `${rel} 的 struct ${name} 字段 ${f[1]} 是元组形态 (${ty})——协议字段禁元组（wire 面无可比性），拒绝判绿`,
            );
          }
          pt.fields.push({ name: f[1] ?? "", ty });
        }
        if (pt.fields.length === 0) fail(`${rel} 的 struct ${name} 解析出 0 字段——拒绝空转`);
      } else {
        for (const line of body.split("\n")) {
          const t = line.trim();
          if (t === "" || t.startsWith("//")) continue;
          const vm = MB_VARIANT.exec(t);
          if (vm !== null) pt.variants.push(vm[1] ?? "");
        }
        if (pt.variants.length === 0) fail(`${rel} 的 enum ${name} 解析出 0 变体——拒绝空转`);
      }
      out.set(name, pt);
    }
  }
  for (const name of want.keys()) {
    if (!out.has(name)) {
      fail(`类型 ${name} 在 type_sources（${files.join(", ")}）里找不到 pub(all) 定义`);
    }
  }
  return out;
}

/**
 * schema 文档里「### N.M `TypeName`」/「## N. ... `TypeName`」标题后**首个
 * markdown 表格**的第一列字段名集合。
 */
export function parseDocFields(doc: string, known: Set<string>): Map<string, Set<string>> {
  const out = new Map<string, Set<string>>();
  let cur = "";
  let inTable = false;
  for (const l of doc.split("\n")) {
    const t = l.trim();
    if (t.startsWith("#")) {
      // 标题里出现的已知类型名即绑定目标（取首个匹配）
      cur = "";
      for (const m of t.matchAll(TICK_NAME)) {
        const n = m[1] ?? "";
        if (known.has(n)) {
          cur = n;
          break;
        }
      }
      inTable = false;
      continue;
    }
    if (cur === "") continue;
    if (!t.startsWith("|")) {
      // 表格结束（首个表格之后的内容忽略——同小节后续表格不混入）
      if (inTable) {
        cur = "";
        inTable = false;
      }
      continue;
    }
    const cells = t.split("|");
    if (cells.length < 2) continue;
    const first = cells[1] ?? "";
    if (first.includes("---")) {
      // 分隔行
      inTable = true;
      continue;
    }
    if (!inTable) continue;
    let set = out.get(cur);
    if (set === undefined) {
      set = new Set<string>();
      out.set(cur, set);
    }
    // 第一列形如 `name` 或 `extra0` / `extra1` / `extra2`
    for (const m of first.matchAll(TICK_NAME)) set.add(m[1] ?? "");
  }
  return out;
}

/**
 * MoonBit 类型 → TS 类型。元组形态由解析器前置 fail loud，此处不再兜底。
 */
export function tsTypeMB(t: string): string {
  const s = t.trim();
  switch (s) {
    // Int32/UInt32 = moon 0.1.20261012+ fmt 对 Int/UInt 类型位的归一化拼写
    //（同型别名，f4dee085 批 183 文件化后协议源为规范形）——TS 侧与 Int/UInt
    // 同折叠 number（JS number 双精度无损容纳 32 位）
    case "Int":
    case "Int32":
    case "UInt":
    case "UInt32":
    case "UInt64":
    case "Int64":
    case "Double":
      return "number";
    case "String":
      return "string";
    case "Bool":
      return "boolean";
  }
  if (s.startsWith("Array[") && s.endsWith("]")) {
    const inner = tsTypeMB(s.slice(6, -1));
    return inner.includes(" | ") ? `(${inner})[]` : `${inner}[]`;
  }
  if (s.endsWith("?")) return tsTypeMB(s.slice(0, -1)) + " | null";
  return s;
}

export function genTS(rd: RulesDoc, types: Map<string, ProtoType>): string {
  const b: string[] = [];
  b.push("// @generated by scripts/gen_protocol_ts —— 禁手改（git/diff 工具链按 @generated 识别）。\n");
  b.push("//\n");
  b.push(
    "// 权威源（MoonBit protocol 包结构体——S7 批四号切换；受 protocol 包 v0.1 十四字段\n",
  );
  b.push("// 白名单锚 + 本生成器双向对账〔MoonBit ↔ schema 文档〕守护）：\n");
  for (const s of rd.type_sources) b.push("//   - " + s + "\n");
  b.push(`// schema：${rd.schema_doc}（v${rd.schema_version}，冻结锚 \`${rd.frozen_anchor}\`）\n`);
  b.push("// 再生成：`node scripts/gen_protocol_ts/main.mts`；幂等校验：`-check`\n");
  b.push("\n");
  b.push("/// StepPayload schema 版本（与 schema 文档冻结版本一致）。\n");
  b.push(`export const SCHEMA_VERSION = "${rd.schema_version}";\n`);

  // 先枚举，再 struct（消费顺序友好）
  const enums: string[] = [];
  const structs: string[] = [];
  for (const t of rd.types) {
    if (t.kind === "enum") enums.push(t.name);
    else structs.push(t.name);
  }
  enums.sort();
  // struct 按 rules 里的声明顺序（StepPayload 在最后，先出子结构）
  for (const n of structs) {
    const pt = types.get(n) as ProtoType;
    b.push(`\n/// \`${n}\`（源：${pt.source}）\n`);
    b.push(`export interface ${n} {\n`);
    for (const f of pt.fields) b.push(`  ${f.name}: ${tsTypeMB(f.ty)};\n`);
    b.push("}\n");
  }
  for (const n of enums) {
    const pt = types.get(n) as ProtoType;
    b.push(`\n/// \`${n}\`（源：${pt.source}）——字符串字面量联合（与 Rust serde 序列化一致）\n`);
    b.push(`export const ${n} = {\n`);
    for (const v of pt.variants) b.push(`  ${v}: "${v}",\n`);
    b.push("} as const;\n");
    b.push(`export type ${n} = (typeof ${n})[keyof typeof ${n}];\n`);
  }
  return b.join("");
}

/** 字段集元数据（供**无 tsc 环境**下的运行时校验 / 消费者自查用）。 */
export function genMeta(rd: RulesDoc, types: Map<string, ProtoType>): string {
  const b: string[] = [];
  b.push("// @generated by scripts/gen_protocol_ts —— 禁手改（git/diff 工具链按 @generated 识别）。\n");
  b.push("// 字段集元数据：无 TypeScript 工具链的消费方（或运行时自检）可据此校验字段名。\n\n");
  b.push(`export const SCHEMA_VERSION = "${rd.schema_version}";\n\n`);
  b.push("export const ENUMS = {\n");
  for (const t of rd.types) {
    if (t.kind !== "enum") continue;
    const vs = (types.get(t.name) as ProtoType).variants;
    b.push(`  ${t.name}: [${vs.map((v) => `"${v}"`).join(", ")}],\n`);
  }
  b.push("};\n\n");
  b.push("export const FIELDS = {\n");
  for (const t of rd.types) {
    if (t.kind !== "struct") continue;
    const fs2 = (types.get(t.name) as ProtoType).fields;
    b.push(`  ${t.name}: [${fs2.map((f) => `"${f.name}"`).join(", ")}],\n`);
  }
  b.push("};\n");
  return b.join("");
}

/** 生成源 = MoonBit protocol 包；文档对账表同载。 */
function loadAll(
  rd: RulesDoc,
): { types: Map<string, ProtoType>; docFields: Map<string, Set<string>> } {
  const want = new Map<string, TypeSpec>();
  for (const t of rd.types) want.set(t.name, t);
  const types = parseMoonbitTypes(rd.type_sources, want);
  const known = new Set(want.keys());
  const doc = mustRead(rd.schema_doc);
  if (!doc.includes("v" + rd.schema_version)) {
    fail(`${rd.schema_doc} 里找不到版本串 v${rd.schema_version}——schema 版本与规则不符`);
  }
  const docFields = parseDocFields(doc, known);
  if (docFields.size === 0) {
    fail(`${rd.schema_doc} 解析出 0 个类型字段表——文档形态变化或解析失配，拒绝判绿`);
  }
  return { types, docFields };
}

/** 实现字段集（现 = MoonBit 生成源）↔ 文档字段集 双向对账。 */
export function fieldSetMismatch(
  rd: RulesDoc,
  types: Map<string, ProtoType>,
  docFields: Map<string, Set<string>>,
): string[] {
  const out: string[] = [];
  for (const t of rd.types) {
    if (t.kind !== "struct") continue;
    const doc = docFields.get(t.name);
    if (doc === undefined) {
      out.push(`${t.name}：文档里找不到该类型的字段表（文档未收录？）`);
      continue;
    }
    const impl = new Set<string>();
    const order: string[] = [];
    for (const f of (types.get(t.name) as ProtoType).fields) {
      impl.add(f.name);
      order.push(f.name);
    }
    for (const n of order) {
      if (!doc.has(n)) out.push(`${t.name}：Rust 有字段 ${n} 而文档未列`);
    }
    const dnames = [...doc].sort();
    for (const n of dnames) {
      if (!impl.has(n)) out.push(`${t.name}：文档列了 ${n} 而 Rust 无此字段`);
    }
  }
  return out;
}

function writeOrCheck(rd: RulesDoc, rel: string, content: string, checkOnly: boolean): boolean {
  const abs = path.join(root(), rel);
  if (checkOnly) {
    let old: string;
    try {
      old = fs.readFileSync(abs, "utf8");
    } catch (e) {
      process.stdout.write(`  !! ${rel} 不存在或不可读（${(e as Error).message}）——请跑 \`node scripts/gen_protocol_ts/main.mts\`\n`);
      return false;
    }
    // 行尾归一化：core.autocrlf=true 的 checkout 会把 LF 产物翻成 CRLF，
    // 逐字节比较即假红（与 toolchain_probe 2026-09-22 假红同款）。
    if (old.split("\r\n").join("\n") !== content) {
      process.stdout.write(
        `  !! ${rel} 与现场生成不一致（产物陈旧 / 手工改过）——请跑 \`node scripts/gen_protocol_ts/main.mts\`\n`,
      );
      return false;
    }
    return true;
  }
  try {
    fs.mkdirSync(path.dirname(abs), { recursive: true });
    fs.writeFileSync(abs, content, { mode: 0o644 });
  } catch (e) {
    fatal(`写 ${rel} 失败: ${(e as Error).message}`);
  }
  return true;
}

function selftest(rd: RulesDoc): number {
  const { types, docFields } = loadAll(rd);

  // 基线
  const ts = genTS(rd, types);
  const meta = genMeta(rd, types);
  let baseOK = true;
  const readNorm = (rel: string): string | null => {
    try {
      return fs.readFileSync(path.join(root(), rel), "utf8").split("\r\n").join("\n");
    } catch {
      return null;
    }
  };
  if (readNorm(rd.out_ts) !== ts) {
    process.stdout.write("gen_protocol_ts: selftest ABORT——基线产物与现场生成不一致，先跑生成再自证\n");
    baseOK = false;
  }
  if (readNorm(rd.out_meta) !== meta) {
    process.stdout.write("gen_protocol_ts: selftest ABORT——基线 meta 产物不一致，先跑生成再自证\n");
    baseOK = false;
  }
  if (fieldSetMismatch(rd, types, docFields).length > 0) {
    process.stdout.write(
      `gen_protocol_ts: selftest ABORT——基线字段对账就红（${fieldSetMismatch(rd, types, docFields).length} 处），无法归因\n`,
    );
    baseOK = false;
  }
  if (!baseOK) return 2;

  // 选一个 struct 作注入目标
  const target = rd.types.find((t) => t.kind === "struct")?.name ?? "";
  if (target === "") fatal("rules.types 里没有 struct——selftest 无注入目标（规则面退化）");

  let failed = 0;

  // ① 生成物注入：给某类型多一个字段 → 生成文本必不同
  const cp = new Map<string, ProtoType>();
  for (const [k, v] of types) cp.set(k, { ...v, fields: [...v.fields] });
  (cp.get(target) as ProtoType).fields.push({ name: "__selftest_probe", ty: "Int" });
  if (genTS(rd, cp) === ts) {
    process.stdout.write("gen_protocol_ts: selftest FAIL——注入新字段后生成文本不变，生成器漏字段\n");
    failed++;
  } else {
    process.stdout.write("gen_protocol_ts: selftest ok——注入 MoonBit 新字段被判红（生成文本变化）\n");
  }

  // ② 文档对账注入：文档少一个字段
  const dcp = new Map<string, Set<string>>();
  for (const [k, v] of docFields) dcp.set(k, new Set(v));
  const targetDoc = dcp.get(target);
  if (targetDoc !== undefined && targetDoc.size > 0) {
    targetDoc.delete(targetDoc.values().next().value as string);
    if (fieldSetMismatch(rd, types, dcp).length === 0) {
      process.stdout.write("gen_protocol_ts: selftest FAIL——文档删字段后仍判绿，对账失效\n");
      failed++;
    } else {
      process.stdout.write("gen_protocol_ts: selftest ok——文档缺字段被判红（双向对账生效）\n");
    }
  }

  // ③ 反向：文档多出一个实现没有的字段
  const dcp2 = new Map<string, Set<string>>();
  for (const [k, v] of docFields) dcp2.set(k, new Set(v));
  const targetDoc2 = dcp2.get(target);
  if (targetDoc2 !== undefined) targetDoc2.add("__selftest_fabricated");
  if (fieldSetMismatch(rd, types, dcp2).length === 0) {
    process.stdout.write("gen_protocol_ts: selftest FAIL——文档多字段后仍判绿，反向对账失效\n");
    failed++;
  } else {
    process.stdout.write("gen_protocol_ts: selftest ok——文档多出字段被判红（反向对账生效）\n");
  }

  if (failed > 0) return 1;
  process.stdout.write(`gen_protocol_ts: selftest PASS——3 路注入全部判红（注入目标 ${target}）\n`);
  return 0;
}

function main(): void {
  try {
    run();
  } catch (e) {
    fatal(e instanceof Error ? e.message : String(e));
  }
}

function run(): void {
  const argv = process.argv.slice(2);
  const check = argv.includes("-check") || argv.includes("--check");
  const doSelftest = argv.includes("-selftest") || argv.includes("--selftest");
  for (const a of argv) {
    if (!["-check", "--check", "-selftest", "--selftest"].includes(a)) {
      fatal(`未知参数 ${a}（用法：node scripts/gen_protocol_ts/main.mts [-check] [-selftest]）`);
    }
  }

  let rd: RulesDoc;
  try {
    rd = JSON.parse(mustRead(RULES_PATH)) as RulesDoc;
  } catch (e) {
    return fatal(`解析规则失败: ${(e as Error).message}`);
  }
  if (rd.types.length === 0 || rd.out_ts === "" || rd.schema_doc === "") {
    fatal("规则缺 types / out_ts / schema_doc");
  }

  if (doSelftest) process.exit(selftest(rd));

  const { types, docFields } = loadAll(rd);
  const ts = genTS(rd, types);
  const meta = genMeta(rd, types);

  let nFields = 0;
  for (const t of rd.types) {
    if (t.kind === "struct") nFields += (types.get(t.name) as ProtoType).fields.length;
  }
  process.stdout.write(
    `gen_protocol_ts: 解析 ${rd.types.length} 类型 / ${nFields} 字段（源 ${rd.type_sources.length} 文件）\n`,
  );

  const mis = fieldSetMismatch(rd, types, docFields);
  if (mis.length === 0) {
    process.stdout.write(`  ok MoonBit ↔ schema 文档（${rd.schema_doc}）字段集双向一致\n`);
  } else {
    for (const m of mis) process.stdout.write(`  !! ${m}\n`);
  }

  const okTS = writeOrCheck(rd, rd.out_ts, ts, check);
  const okMeta = writeOrCheck(rd, rd.out_meta, meta, check);
  if (!check) {
    process.stdout.write(
      `  ✓ 已写入 ${rd.out_ts}（${Buffer.byteLength(ts, "utf8")} 字节）与 ${rd.out_meta}（${Buffer.byteLength(meta, "utf8")} 字节）\n`,
    );
  }

  if (mis.length > 0 || !okTS || !okMeta) {
    process.stdout.write("gen_protocol_ts: FAIL——生成物或字段对账不一致\n");
    process.exit(1);
  }
  if (check) {
    process.stdout.write("gen_protocol_ts: PASS——产物新鲜 + 双向对账一致（MoonBit 生成源 ↔ schema 文档）\n");
  } else {
    process.stdout.write("gen_protocol_ts: 生成完成\n");
  }
}

// 入口守卫：被 node:test import 时只取纯函数，不落盘
if (
  process.argv[1] !== undefined &&
  pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url
) {
  main();
}
