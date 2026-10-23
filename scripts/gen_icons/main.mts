#!/usr/bin/env node
// 图标几何层生成器（#273 存量 Go 重写批）。
//
// 真源 = 手写 moonbit/icons/<id>.svg（只读，不反向改写）；产物 =
// moonbit/icons/icons.json（几何层）+ moonbit/icons/icons_gen.mbt（MoonBit
// 数据单源）+ 可选 demo/js/icons.ts（-demo）。规则单源 =
// scripts/icon_catalog/rules.json。幂等：id 字典序 + 最短往返浮点 + LF。
//
//   node scripts/gen_icons/main.mts [-check] [-demo]
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../internal/capi.mts";

interface Rules {
  assets_dir: string;
  index_tsv: string;
  geometry_json: string;
  icons_mbt: string;
  demo_ts: string;
  svg_attrs: Record<string, string>;
  geometry_schema: string;
  scale_formula: string;
}
interface IconEntry {
  title: string;
  category: string;
  scope: string;
  paths: string[];
}
interface Geometry {
  schema: string;
  digest: string;
  viewBox: string;
  stroke_width: number;
  stroke_linecap: string;
  stroke_linejoin: string;
  fill: string;
  scale_formula: string;
  icons: Map<string, IconEntry>;
}

const ELEM_RE = /<(path|circle|rect)\b([^>]*?)\/?>/gs;
const ATTR_RE = /([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*"([^"]*)"/g;
const TITLE_RE = /<title>([\s\S]*?)<\/title>/;
const NUM_RE = /^-?[0-9.]+$/;

function fatal(msg: string): never {
  process.stderr.write("FATAL: " + msg + "\n");
  process.exit(2);
}
function fail(msg: string): never {
  process.stderr.write("FAIL: " + msg + "\n");
  process.exit(1);
}

// n 用最短往返格式化，且先把运算结果收敛到 1e-6（Go：Round(f*1e6)/1e6 +
// FormatFloat 'f', -1；"-0" → "0"）。
export function n(f: number): string {
  const r = (Math.sign(f) * Math.round(Math.abs(f) * 1e6)) / 1e6;
  if (r === 0 || Object.is(r, -0)) return "0";
  return String(r);
}

function mustFloat(s: string): number {
  const t = s.trim();
  if (t === "" || Number.isNaN(Number(t))) fatal(`规则里的描边宽度不是数字：${JSON.stringify(s)}`);
  return Number(t);
}

// Go encoding/json 的 float 形态（'f' -1；|x|<1e-6 或 >=1e21 走 'e' -1）。
function goJSONFloat(f: number): string {
  if (!Number.isFinite(f)) fatal(`JSON 不支持非有限数 ${f}`);
  if (f === 0) return "0";
  const abs = Math.abs(f);
  if (abs < 1e-6 || abs >= 1e21) {
    return f.toExponential().replace(/e([+-])0+(\d)/, "e$1$2");
  }
  return String(f);
}

// Go encoding/json 字符串（HTML 三字符与 U+2028/U+2029 转义）。
function goJSONString(s: string): string {
  return JSON.stringify(s).replace(/[<>&\u2028\u2029]/g, (c) => {
    switch (c) {
      case "<":
        return "\\u003c";
      case ">":
        return "\\u003e";
      case "&":
        return "\\u0026";
      case "\u2028":
        return "\\u2028";
      default:
        return "\\u2029";
    }
  });
}

export function extractPaths(svg: string): string[] {
  const out: string[] = [];
  for (const m of svg.matchAll(ELEM_RE)) {
    const tag = m[1] ?? "";
    const raw = m[2] ?? "";
    const attrs = new Map<string, string>();
    for (const am of raw.matchAll(ATTR_RE)) attrs.set(am[1] ?? "", am[2] ?? "");
    if (tag === "path") {
      const d = (attrs.get("d") ?? "").trim();
      if (d === "") throw new Error("path 缺 d");
      out.push(d);
    } else if (tag === "circle") {
      const cx = numAttr(attrs, "cx");
      const cy = numAttr(attrs, "cy");
      const r = numAttr(attrs, "r");
      out.push(
        `M${n(cx - r)} ${n(cy)}a${n(r)} ${n(r)} 0 1 0 ${n(2 * r)} 0a${n(r)} ${n(r)} 0 1 0 ${n(-2 * r)} 0z`
      );
    } else if (tag === "rect") {
      if (attrs.has("rx")) throw new Error("rect 带 rx（契约要求手写为 path）");
      const x = numAttr(attrs, "x");
      const y = numAttr(attrs, "y");
      const w = numAttr(attrs, "width");
      const h = numAttr(attrs, "height");
      out.push(`M${n(x)} ${n(y)}h${n(w)}v${n(h)}h${n(-w)} 0z`);
    }
  }
  return out;
}

function numAttr(attrs: Map<string, string>, k: string): number {
  const s = attrs.get(k);
  if (s === undefined) throw new Error(`缺属性 ${k}`);
  const t = s.trim();
  if (!NUM_RE.test(t)) throw new Error(`属性 ${k}=${JSON.stringify(s)} 非数字`);
  const v = Number(t);
  if (Number.isNaN(v)) throw new Error(`属性 ${k}=${JSON.stringify(s)} 非数字`);
  return v;
}

export function readTsv(p: string): Map<string, [string, string]> {
  const b = fs.readFileSync(p);
  const s = b.toString("utf8");
  if (s.includes("\r\n")) throw new Error("含 CRLF 行尾");
  const lines = s.replace(/\n+$/, "").split("\n");
  const out = new Map<string, [string, string]>();
  for (const ln of lines.slice(1)) {
    if (ln.trim() === "") continue;
    const cs = ln.split("\t");
    if (cs.length < 5) throw new Error(`列数不足：${ln}`);
    out.set(cs[0] ?? "", [cs[1] ?? "", cs[2] ?? ""]);
  }
  return out;
}

export function digestOf(ids: string[], byID: Map<string, Buffer>): string {
  const h = crypto.createHash("sha256");
  for (const id of ids) {
    h.update(Buffer.from(id, "utf8"));
    h.update(Buffer.from([0]));
    h.update(byID.get(id) ?? Buffer.alloc(0));
    h.update(Buffer.from([0]));
  }
  return "sha256:" + h.digest("hex");
}

// marshalGeo 对齐 Go json.MarshalIndent(g, "", "  ") + 额外尾随换行。
export function marshalGeo(g: Geometry): string {
  const L: string[] = [];
  L.push("{");
  L.push(`  "schema": ${goJSONString(g.schema)},`);
  L.push(`  "digest": ${goJSONString(g.digest)},`);
  L.push(`  "viewBox": ${goJSONString(g.viewBox)},`);
  L.push(`  "stroke_width": ${goJSONFloat(g.stroke_width)},`);
  L.push(`  "stroke_linecap": ${goJSONString(g.stroke_linecap)},`);
  L.push(`  "stroke_linejoin": ${goJSONString(g.stroke_linejoin)},`);
  L.push(`  "fill": ${goJSONString(g.fill)},`);
  L.push(`  "scale_formula": ${goJSONString(g.scale_formula)},`);
  const keys = [...g.icons.keys()].sort();
  if (keys.length === 0) {
    L.push('  "icons": {}');
  } else {
    L.push('  "icons": {');
    keys.forEach((id, i) => {
      const e = g.icons.get(id) as IconEntry;
      L.push(`    ${goJSONString(id)}: {`);
      L.push(`      "title": ${goJSONString(e.title)},`);
      L.push(`      "category": ${goJSONString(e.category)},`);
      L.push(`      "scope": ${goJSONString(e.scope)},`);
      if (e.paths.length === 0) {
        L.push('      "paths": []');
      } else {
        L.push('      "paths": [');
        e.paths.forEach((p, j) => {
          L.push(`        ${goJSONString(p)}${j < e.paths.length - 1 ? "," : ""}`);
        });
        L.push("      ]");
      }
      L.push(`    }${i < keys.length - 1 ? "," : ""}`);
    });
    L.push("  }");
  }
  L.push("}");
  return L.join("\n") + "\n\n";
}

const MBT_TEMPLATE = (ids: string[], icons: Map<string, IconEntry>, digest: string, attrs: Record<string, string>): string => {
  const q = (s: string): string => JSON.stringify(s);
  let out = "";
  out += "// @generated by scripts/gen_icons —— 禁手改（真源 = moonbit/icons/<id>.svg）。\n";
  out += "// 图标资产 MoonBit 单源（issue #27 方案 C）：digest 与 moonbit/icons/icons.json\n";
  out += "// 同源同值，gen_icons -check 锁两产物字节一致。本包 L0 纯数据零依赖。\n";
  out += `// digest ${digest}\n`;
  out += "\n///|\n/// icons.get 帧契约常量（icons/v1——几何层契约的 MoonBit 单源）。\nconst ICONS_SCHEMA : String = \"icons/v1\"\n\n///|\n/// 资产表 digest（52 枚 svg 按 id 字典序逐个 sha256 汇总，与 icons.json 同算法同值）。\n";
  out += `const ICONS_DIGEST : String = ${q(digest)}\n`;
  out += `\nconst ICONS_VIEWBOX : String = ${q(attrs["viewBox"] ?? "")}\n`;
  out += `\n///|\n/// 描边宽度（相对 24 viewBox；消费端换算 strokeWidth = ${attrs["stroke-width"] ?? ""} × S / 24）。\nconst ICONS_STROKE_WIDTH_TEXT : String = ${q(attrs["stroke-width"] ?? "")}\n`;
  out += `\nconst ICONS_STROKE_LINECAP : String = ${q(attrs["stroke-linecap"] ?? "")}\n`;
  out += `\nconst ICONS_STROKE_LINEJOIN : String = ${q(attrs["stroke-linejoin"] ?? "")}\n`;
  out += `\nconst ICONS_FILL : String = ${q(attrs["fill"] ?? "")}\n`;
  out += String.raw`
///|
/// 全量几何表（id 字典序插入——Map 迭代序 = 插入序，emitter 全量输出序单源；
/// d 属性字符集不含引号/反斜杠，仍统一走 mbt_escape 防御）。
let icon_paths_table : Map[String, Array[String]] = {
  let m : Map[String, Array[String]] = Map([])
`;
  for (const id of ids) {
    const paths = (icons.get(id) as IconEntry).paths.map((p) => `"${p.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`);
    out += `  m.set(${q(id)}, [${paths.join(", ")}])\n`;
  }
  out += String.raw`  m
}

///|
/// icons.get 帧 emitter（显式序列化，字段序单点：schema / digest / viewBox /
/// stroke_width / stroke_linecap / stroke_linejoin / fill / icons）。
/// ids 空数组 = 全量（字典序）；否则按请求序输出、重复 id 跳过、
/// 任一未知 id 整帧拒绝（返回 None——调用方转 invalid-params，fail loud）。
pub fn export_icons_json(ids : Array[String]) -> String? {
  let buf = StringBuilder()
  buf.write_string("{\"schema\":\"\{ICONS_SCHEMA}\"")
  buf.write_string(",\"digest\":\"\{ICONS_DIGEST}\"")
  buf.write_string(",\"viewBox\":\"\{ICONS_VIEWBOX}\"")
  buf.write_string(",\"stroke_width\":\{ICONS_STROKE_WIDTH_TEXT}")
  buf.write_string(",\"stroke_linecap\":\"\{ICONS_STROKE_LINECAP}\"")
  buf.write_string(",\"stroke_linejoin\":\"\{ICONS_STROKE_LINEJOIN}\"")
  buf.write_string(",\"fill\":\"\{ICONS_FILL}\"")
  buf.write_string(",\"icons\":{")
  if ids.length() == 0 {
    let mut first = true
    for id, paths in icon_paths_table {
      if first {
        first = false
      } else {
        buf.write_string(",")
      }
      write_icon_entry(buf, id, paths)
    }
  } else {
    let seen : Map[String, Bool] = Map([])
    let mut first = true
    for id in ids {
      if seen.get(id).unwrap_or(false) {
        continue
      }
      seen.set(id, true)
      match icon_paths_table.get(id) {
        None => return None
        Some(paths) => {
          if first {
            first = false
          } else {
            buf.write_string(",")
          }
          write_icon_entry(buf, id, paths)
        }
      }
    }
  }
  buf.write_string("}}")
  Some(buf.to_string())
}

///|
/// 单图标条目（{"paths":[...]}——paths = path d 字面量数组）。
fn write_icon_entry(buf : StringBuilder, id : String, paths : Array[String]) -> Unit {
  buf.write_string("\"\{id}\":{\"paths\":[")
  for i, p in paths {
    if i > 0 {
      buf.write_string(",")
    }
    buf.write_string("\"\{p}\"")
  }
  buf.write_string("]}")
}
`;
  return out;
};

export function renderDemoTs(ids: string[], icons: Map<string, IconEntry>, digest: string): string {
  const q = (s: string): string => JSON.stringify(s);
  let out = "";
  out += "// @generated by scripts/gen_icons —— 禁手改（真源 = moonbit/icons/<id>.svg）\n";
  out += "// 契约：viewBox 24 / stroke 1.8 / currentColor；本表只存 body 片段，消费方自行套 svg 壳。\n";
  out += `// digest ${digest}\n`;
  out += "// 本地表优先（#27 拍板）：渲染一律用本表；icons.get 帧只做 digest 对拍，\n";
  out += "// 不一致 = 版本漂移信号（console.warn，不回退引擎表）。\n";
  out += `export const ICONS_DIGEST = ${q(digest)};\n`;
  out += "export const ICONS: Record<string, string> = {\n";
  for (const id of ids) {
    const body = (icons.get(id) as IconEntry).paths.map((p) => `<path d="${p}"/>`).join("");
    out += `  ${q(id)}: '${body}',\n`;
  }
  out += "};\n";
  return out;
}

function writeIconsMbt(file: string, content: string): void {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, content);
  const fmt = spawnSync("moon", ["fmt", path.basename(file)], { cwd: path.dirname(file), encoding: "utf8" });
  if (fmt.status !== 0) throw new Error(`moon fmt 失败（moon 须在 PATH）: exit ${fmt.status}\n${(fmt.stdout ?? "") + (fmt.stderr ?? "")}`);
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  const args = process.argv.slice(2);
  let check = false;
  let demo = false;
  for (const a of args) {
    if (a === "-check" || a === "--check") check = true;
    else if (a === "-demo" || a === "--demo") demo = true;
    else {
      process.stderr.write(`用法：node scripts/gen_icons/main.mts [-check] [-demo]\n`);
      process.exit(2);
    }
  }
  const root = projectRoot();
  let rules: Rules;
  try {
    rules = JSON.parse(fs.readFileSync(path.join(root, "scripts/icon_catalog/rules.json"), "utf8")) as Rules;
  } catch (e) {
    fatal(`读不到规则文件 scripts/icon_catalog/rules.json：${e instanceof Error ? e.message : String(e)}`);
  }
  if (!rules.assets_dir || !rules.geometry_json) fatal("规则缺 assets_dir / geometry_json（fail loud）");

  let meta: Map<string, [string, string]>;
  try {
    meta = readTsv(path.join(root, rules.index_tsv));
  } catch (e) {
    fatal(`index.tsv: ${e instanceof Error ? e.message : String(e)}`);
  }
  const assetsDir = path.join(root, rules.assets_dir);
  let entries: fs.Dirent[];
  try {
    entries = fs.readdirSync(assetsDir, { withFileTypes: true });
  } catch (e) {
    fatal(`读不到资产目录 ${rules.assets_dir}：${e instanceof Error ? e.message : String(e)}`);
  }
  const ids: string[] = [];
  const byID = new Map<string, Buffer>();
  for (const e of entries) {
    if (e.isDirectory() || !e.name.endsWith(".svg")) continue;
    const id = e.name.slice(0, -4);
    let b: Buffer;
    try {
      b = fs.readFileSync(path.join(assetsDir, e.name));
    } catch (err) {
      fatal(`读取 ${e.name} 失败：${err instanceof Error ? err.message : String(err)}`);
    }
    ids.push(id);
    byID.set(id, b);
  }
  ids.sort();

  const geo: Geometry = {
    schema: rules.geometry_schema,
    digest: digestOf(ids, byID),
    viewBox: rules.svg_attrs["viewBox"] ?? "",
    stroke_width: mustFloat(rules.svg_attrs["stroke-width"] ?? ""),
    stroke_linecap: rules.svg_attrs["stroke-linecap"] ?? "",
    stroke_linejoin: rules.svg_attrs["stroke-linejoin"] ?? "",
    fill: rules.svg_attrs["fill"] ?? "",
    scale_formula: rules.scale_formula,
    icons: new Map(),
  };
  for (const id of ids) {
    const text = (byID.get(id) as Buffer).toString("utf8");
    let paths: string[];
    try {
      paths = extractPaths(text);
    } catch (e) {
      fatal(`${id}.svg 图元解析失败：${e instanceof Error ? e.message : String(e)}`);
    }
    if (paths.length === 0) fatal(`${id}.svg 没有可用图元`);
    const title = TITLE_RE.exec(text)?.[1]?.trim() ?? "";
    const m = meta.get(id);
    geo.icons.set(id, { title, category: m?.[0] ?? "", scope: m?.[1] ?? "", paths });
  }
  const out = marshalGeo(geo);
  const geometryPath = path.join(root, rules.geometry_json);
  const mbtPath = rules.icons_mbt ? path.join(root, rules.icons_mbt) : "";
  const demoTsPath = rules.demo_ts ? path.join(root, rules.demo_ts) : "";

  if (check) {
    let cur: Buffer;
    try {
      cur = fs.readFileSync(geometryPath);
    } catch (e) {
      fail(`几何层缺失 ${rules.geometry_json}：${e instanceof Error ? e.message : String(e)}`);
    }
    if (!cur.equals(Buffer.from(out, "utf8"))) {
      fail(`几何层与真源不一致（${cur.length} B vs ${Buffer.byteLength(out)} B），跑 node scripts/gen_icons/main.mts 同步`);
    }
    if (mbtPath) {
      let curMbt: Buffer;
      try {
        curMbt = fs.readFileSync(mbtPath);
      } catch (e) {
        fail(`icons_gen.mbt 缺失 ${rules.icons_mbt}：${e instanceof Error ? e.message : String(e)}（跑 gen_icons 生成）`);
      }
      try {
        writeIconsMbt(mbtPath, MBT_TEMPLATE(ids, geo.icons, geo.digest, rules.svg_attrs));
      } catch (e) {
        fail(`icons_gen.mbt 写盘失败：${e instanceof Error ? e.message : String(e)}`);
      }
      const now = fs.readFileSync(mbtPath);
      const nowLF = now.toString("latin1").replace(/\r\n/g, "\n");
      const curLF = curMbt.toString("latin1").replace(/\r\n/g, "\n");
      // 文件参数 fmt 可能改变形态：无论成败都还原（-check 零副作用）
      fs.writeFileSync(mbtPath, curMbt);
      if (nowLF !== curLF) fail(`icons_gen.mbt 与真源不一致，跑 node scripts/gen_icons/main.mts 同步`);
    }
    if (demoTsPath && fs.existsSync(demoTsPath)) {
      const curTs = fs.readFileSync(demoTsPath, "utf8");
      const want = renderDemoTs(ids, geo.icons, geo.digest);
      if (curTs.replace(/\r\n/g, "\n") !== want.replace(/\r\n/g, "\n")) {
        fail(`${rules.demo_ts} 与真源不一致，跑 node scripts/gen_icons/main.mts -demo 同步`);
      }
    }
    console.log(`OK：几何层与真源一致（${ids.length} 个图标，digest ${geo.digest}）`);
  } else {
    try {
      fs.writeFileSync(geometryPath, out);
    } catch (e) {
      fail(`写 ${rules.geometry_json} 失败：${e instanceof Error ? e.message : String(e)}`);
    }
    console.log(`生成 ${rules.geometry_json}：${ids.length} 个图标，${Buffer.byteLength(out)} B，digest ${geo.digest}`);
    if (mbtPath) {
      try {
        writeIconsMbt(mbtPath, MBT_TEMPLATE(ids, geo.icons, geo.digest, rules.svg_attrs));
      } catch (e) {
        fail(`写 ${rules.icons_mbt} 失败：${e instanceof Error ? e.message : String(e)}`);
      }
      console.log(`生成 ${rules.icons_mbt}：${ids.length} 个图标（MoonBit 数据单源，icons.get 数据面）`);
    }
    if (demo) {
      if (!demoTsPath) fatal("规则未配 demo_ts");
      try {
        fs.mkdirSync(path.dirname(demoTsPath), { recursive: true });
        fs.writeFileSync(demoTsPath, renderDemoTs(ids, geo.icons, geo.digest));
      } catch (e) {
        fail(`写 ${rules.demo_ts} 失败：${e instanceof Error ? e.message : String(e)}`);
      }
      console.log(`生成 ${rules.demo_ts}：${ids.length} 个图标（内联 body 片段，消费方自行套 svg 壳）`);
    }
  }
}
