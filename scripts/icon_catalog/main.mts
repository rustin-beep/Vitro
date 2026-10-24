#!/usr/bin/env node
// icon_catalog —— 图标资产契约闸（Go→.mts 重写，refs #273）。
//
// 判定型脚本纪律：stdlib 优先、规则外置 rules.json、fail loud、禁止静默 default。
//
// 用法（flag 必须写在任何位置参数之前）：
//   node scripts/icon_catalog/main.mts        # 校验并打印摘要
//   node scripts/icon_catalog/main.mts -v     # 额外逐条打印通过的检查项
//
// 检查面（全部来自 rules.json，改规则即改契约）：
//  1. 每个 svg 的契约属性齐全（viewBox / width / height / fill / stroke / 描边三项）
//  2. 零具体色值：禁 #hex / rgb() / hsl() / 具名色；stroke 只允许 currentColor
//  3. 图元白名单：只允许 path / circle / rect；rect 禁带 rx|ry
//  4. 禁零长度子路径（h.01 之类靠 round cap 画点的技巧，跨端会整个消失）
//  5. 带 <title>（中文语义）且与 index.tsv 的 desc 一致；带 <desc>（英文 id）且等于文件名
//  6. 禁在资产上写死 aria-hidden（会废掉 <title>）
//  7. index.tsv 五列表头 / 值域（category / scope）/ 非空 emoji / id 命名合法
//  8. 双向对账：孤儿资产（svg 无 tsv 行）、缺资产（tsv 行无 svg）
//  9. 几何层 moonbit/icons/icons.json 的 digest 与现算一致（生成物同步）
// 10. 协议值域对账：catalog.json 的 icon 值 ⊆ index.tsv id 集
//
// 退出码：0 全绿 / 1 有违规（逐条列 stderr）/ 2 用法或环境错（fail loud）。
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../internal/capi.mts";

export const RULES_PATH = "scripts/icon_catalog/rules.json";

export interface Rules {
  assets_dir: string;
  index_tsv: string;
  geometry_json: string;
  catalog_json: string;
  svg_attrs: Record<string, string>;
  allowed_elements: string[];
  rect_forbidden_attrs: string[];
  forbid_color_literal: boolean;
  forbid_named_color: boolean;
  forbid_zero_length_subpath: boolean;
  forbid_aria_hidden: boolean;
  require_title: boolean;
  require_desc: boolean;
  tsv_columns: string[];
  categories: string[];
  scopes: string[];
  emoji_required_scopes: string[];
  emoji_must_be_unique: boolean;
  named_colors: string[];
}

const RE_COLOR = /#[0-9a-fA-F]{3,8}\b|rgba?\(|hsla?\(/;
const RE_ZERO_LEN = /[hv]0*\.0+/;
const RE_ELEM = /<(path|circle|rect|line|polyline|polygon|ellipse|text|g|image|use|script|style)\b/gs;
const RE_ATTR = /([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*"([^"]*)"/g;
const RE_TITLE = /<title>(.*?)<\/title>/s;
const RE_DESC = /<desc>(.*?)<\/desc>/s;
const RE_SVG_OPEN = /<svg\b([^>]*)>/s;
const RE_RECT = /<rect\b[^>]*>/g;
const RE_ID = /^[a-z][a-z0-9]*(-[a-z0-9]+)*$/;

function fatal(msg: string): never {
  process.stderr.write(`FATAL: ${msg}\n`);
  process.exit(2);
}

/** 字节序排序（Go sort.Strings 口径）。 */
function byteSort(xs: string[]): string[] {
  return [...xs].sort((a, b) => Buffer.compare(Buffer.from(a, "utf8"), Buffer.from(b, "utf8")));
}

export function digestOf(ids: string[], svgBytes: Map<string, Buffer>): string {
  const h = crypto.createHash("sha256");
  for (const id of ids) {
    h.update(Buffer.from(id, "utf8"));
    h.update(Buffer.from([0]));
    h.update(svgBytes.get(id) ?? Buffer.alloc(0));
    h.update(Buffer.from([0]));
  }
  return "sha256:" + h.digest("hex");
}

export interface TsvRow {
  cols: string[];
}

export function readTsv(root: string, p: string, cols: string[]): TsvRow[] {
  let raw: string;
  try {
    // 根须由调用方贯穿（不用 projectRoot 全局——fixture 测试与 -root 注入都靠它）
    raw = fs.readFileSync(path.isAbsolute(p) ? p : path.join(root, p), "utf8");
  } catch (e) {
    throw new Error(`读取失败 ${e instanceof Error ? e.message : String(e)}`);
  }
  if (raw.includes("\r\n")) throw new Error("含 CRLF 行尾（须在 .gitattributes 锁 text eol=lf）");
  const lines = raw.replace(/\n+$/, "").split("\n");
  if (lines.length === 0) throw new Error("空文件");
  const header = (lines[0] ?? "").split("\t");
  if (header.length !== cols.length || header.some((c, i) => c !== cols[i])) {
    throw new Error(`表头不符：[${header.join(" ")}]（契约 [${cols.join(" ")}]）`);
  }
  const out: TsvRow[] = [];
  for (let i = 1; i < lines.length; i++) {
    const ln = lines[i] ?? "";
    if (ln.trim() === "") continue;
    const cs = ln.split("\t");
    if (cs.length !== cols.length) {
      throw new Error(`第 ${i + 1} 行列数=${cs.length}（应 ${cols.length}）：${ln}`);
    }
    out.push({ cols: cs });
  }
  if (out.length === 0) throw new Error("无数据行");
  return out;
}

export interface RunResult {
  errs: string[];
  passes: string[];
  /** 资产数（OK 行用） */
  iconCount: number;
}

/** 全量校验（导出供测试直接注入 / 断言）。 */
export function run(root: string, rulesPath = RULES_PATH): RunResult {
  let rawRules: string;
  try {
    rawRules = fs.readFileSync(path.isAbsolute(rulesPath) ? rulesPath : path.join(root, rulesPath), "utf8");
  } catch (e) {
    fatal(`读不到规则文件 ${rulesPath}：${e instanceof Error ? e.message : String(e)}`);
  }
  let rules: Rules;
  try {
    rules = JSON.parse(rawRules) as Rules;
  } catch (e) {
    fatal(`规则文件解析失败 ${rulesPath}：${e instanceof Error ? e.message : String(e)}`);
  }
  if (!rules.assets_dir || !rules.index_tsv) {
    fatal("规则缺 assets_dir / index_tsv（fail loud，不猜默认值）");
  }

  const errs: string[] = [];
  const passes: string[] = [];
  const fail = (msg: string): void => void errs.push(msg);
  const pass = (msg: string): void => void passes.push(msg);

  // 1) 资产面：逐 svg 契约校验
  let entries: string[];
  try {
    entries = fs.readdirSync(path.join(root, rules.assets_dir));
  } catch (e) {
    fatal(`读不到资产目录 ${rules.assets_dir}：${e instanceof Error ? e.message : String(e)}`);
  }
  const ids: string[] = [];
  const svgBytes = new Map<string, Buffer>();
  const svgTitles = new Map<string, string>();
  const allowed = new Set(rules.allowed_elements);
  const named = new Set(rules.named_colors.map((c) => c.toLowerCase()));

  for (const name of entries) {
    if (!name.endsWith(".svg")) continue;
    const st = fs.statSync(path.join(root, rules.assets_dir, name));
    if (st.isDirectory()) continue;
    const id = name.slice(0, -".svg".length);
    ids.push(id);
    let b: Buffer;
    try {
      b = fs.readFileSync(path.join(root, rules.assets_dir, name));
    } catch (e) {
      fail(`${id}: 读取失败：${e instanceof Error ? e.message : String(e)}`);
      continue;
    }
    svgBytes.set(id, b);
    const text = b.toString("utf8");

    if (!RE_ID.test(id)) fail(`${id}: id 命名不合法（应 kebab-case，小写字母开头）`);
    const m = RE_SVG_OPEN.exec(text);
    if (m === null) {
      fail(`${id}: 找不到 <svg> 根标签`);
      continue;
    }
    const attrs = new Map<string, string>();
    for (const am of (m[1] ?? "").matchAll(RE_ATTR)) attrs.set(am[1] ?? "", am[2] ?? "");
    for (const [k, want] of Object.entries(rules.svg_attrs)) {
      const got = attrs.get(k);
      if (got !== want) fail(`${id}: 属性 ${k}=${JSON.stringify(got ?? "")}，契约要求 ${JSON.stringify(want)}`);
    }

    if (rules.forbid_color_literal && RE_COLOR.test(text)) {
      fail(`${id}: 出现具体色值（契约只允许 currentColor 占位）`);
    }
    if (rules.forbid_named_color) {
      for (const [k, v] of attrs) {
        if ((k === "stroke" || k === "fill") && named.has(v.toLowerCase())) {
          fail(`${id}: 出现具名色 ${k}=${JSON.stringify(v)}`);
        }
      }
    }
    for (const em of text.matchAll(RE_ELEM)) {
      const tag = em[1] ?? "";
      if (!allowed.has(tag)) fail(`${id}: 图元白名单外的 <${tag}>`);
    }
    for (const rm of text.match(RE_RECT) ?? []) {
      const ra = new Map<string, string>();
      for (const am of rm.matchAll(RE_ATTR)) ra.set(am[1] ?? "", am[2] ?? "");
      for (const fa of rules.rect_forbidden_attrs) {
        if (ra.has(fa)) fail(`${id}: <rect> 带 ${fa}（带 rx 的圆角矩形必须手写为 path）`);
      }
    }
    if (rules.forbid_zero_length_subpath && RE_ZERO_LEN.test(text)) {
      fail(`${id}: 零长度子路径（禁靠 round cap 画点，跨端会消失）`);
    }
    if (rules.forbid_aria_hidden && text.includes("aria-hidden")) {
      fail(`${id}: 资产不得写死 aria-hidden（会废掉 <title>，由消费方按场景注入）`);
    }
    let title = "";
    if (rules.require_title) {
      const tm = RE_TITLE.exec(text);
      if (tm === null) fail(`${id}: 缺 <title>`);
      else title = (tm[1] ?? "").trim();
    }
    if (rules.require_desc) {
      const dm = RE_DESC.exec(text);
      if (dm === null) fail(`${id}: 缺 <desc>`);
      else if ((dm[1] ?? "").trim() !== id) fail(`${id}: <desc>=${JSON.stringify((dm[1] ?? "").trim())} 必须等于 id（双向自证）`);
    }
    svgTitles.set(id, title);
  }
  const sortedIds = byteSort(ids);
  pass(`资产契约：${ids.length} 个 svg 逐个校验（属性 / 色值 / 图元白名单 / title+desc 自证）`);

  // 2) index.tsv 校验（tsvIDs 供段 5 复用）
  const tsvIDs = new Set<string>();
  let tRows: TsvRow[] | null = null;
  try {
    tRows = readTsv(root, rules.index_tsv, rules.tsv_columns);
  } catch (e) {
    fail(`index.tsv: ${e instanceof Error ? e.message : String(e)}`);
  }
  if (tRows !== null) {
    const emojiSeen = new Map<string, string>();
    for (const r of tRows) {
      const id = r.cols[0] ?? "";
      const cat = r.cols[1] ?? "";
      const scope = r.cols[2] ?? "";
      const emo = r.cols[3] ?? "";
      const desc = r.cols[4] ?? "";
      if (tsvIDs.has(id)) fail(`index.tsv: id 重复 ${JSON.stringify(id)}`);
      tsvIDs.add(id);
      if (!rules.categories.includes(cat)) fail(`index.tsv: ${id} 的 category=${JSON.stringify(cat)} 越界`);
      if (!rules.scopes.includes(scope)) fail(`index.tsv: ${id} 的 scope=${JSON.stringify(scope)} 越界`);
      if (rules.emoji_required_scopes.includes(scope)) {
        if (emo.trim() === "") fail(`index.tsv: ${id} 的 scope=${scope} 必须有 emoji 兼容别名`);
        else if (rules.emoji_must_be_unique) {
          const prev = emojiSeen.get(emo);
          if (prev !== undefined) fail(`index.tsv: emoji ${JSON.stringify(emo)} 重复（${prev} 与 ${id}）`);
          else emojiSeen.set(emo, id);
        }
      }
      const title = svgTitles.get(id);
      if (title !== undefined && title !== desc.trim()) {
        fail(`index.tsv: ${id} 的 desc=${JSON.stringify(desc.trim())} 与 svg <title>=${JSON.stringify(title)} 不一致`);
      }
    }
    pass(`清单值域：${tRows.length} 行（category / scope / emoji 兼容别名 / desc 与 title 一致）`);

    // 3) 双向对账
    for (const id of sortedIds) {
      if (!tsvIDs.has(id)) fail(`孤儿资产 ${id}.svg：index.tsv 无此 id`);
    }
    for (const r of tRows) {
      const id = r.cols[0] ?? "";
      if (!svgBytes.has(id)) fail(`缺资产 ${id}.svg：index.tsv 有此 id`);
    }
    pass("双向对账：孤儿 0 / 缺件 0");
  }

  // 4) 几何层 digest 同步
  if (rules.geometry_json) {
    let gb: string | null = null;
    try {
      gb = fs.readFileSync(path.join(root, rules.geometry_json), "utf8");
    } catch (e) {
      fail(`几何层缺失 ${rules.geometry_json}：${e instanceof Error ? e.message : String(e)}（跑 node scripts/gen_icons/main.mts 生成）`);
    }
    if (gb !== null) {
      let digest = "";
      try {
        digest = (JSON.parse(gb) as { digest?: string }).digest ?? "";
      } catch (e) {
        fail(`几何层 ${rules.geometry_json} 解析失败：${e instanceof Error ? e.message : String(e)}`);
      }
      if (digest !== "") {
        const now = digestOf(sortedIds, svgBytes);
        if (digest !== now) {
          fail(`几何层 digest 过期：文件=${digest} 现算=${now}（跑 gen_icons 同步）`);
        } else {
          pass(`几何层 digest 同步：${digest.slice(0, Math.min(23, digest.length))}`);
        }
      }
    }
  }

  // 5) 协议 icon 值域对账（#27 §3.4：icon 字段值域 = 资产表 id 集）
  if (rules.catalog_json) {
    let cb: string;
    try {
      cb = fs.readFileSync(path.join(root, rules.catalog_json), "utf8");
    } catch (e) {
      fail(`catalog 源缺失 ${rules.catalog_json}：${e instanceof Error ? e.message : String(e)}`);
      cb = "";
    }
    if (cb !== "") {
      let cat: { entries?: Array<{ code: number; icon: string }> };
      try {
        cat = JSON.parse(cb) as typeof cat;
      } catch (e) {
        fail(`catalog 源 ${rules.catalog_json} 解析失败：${e instanceof Error ? e.message : String(e)}`);
        cat = {};
      }
      const entries = cat.entries ?? [];
      let bad = 0;
      for (const e of entries) {
        if (!tsvIDs.has(e.icon)) {
          fail(`E${e.code} 的 icon=${JSON.stringify(e.icon)} 不在资产表（index.tsv 无此 id）`);
          bad++;
        }
      }
      if (bad === 0) pass(`协议值域对账：${entries.length} 条 catalog icon 全部在册`);
    }
  }

  return { errs, passes, iconCount: ids.length };
}

export function main(argv: string[]): number {
  let verbose = false;
  for (const a of argv) {
    if (a === "-v" || a === "--v") verbose = true;
    else {
      // 用法错 = exit 2（Go flag 包同口径）
      process.stderr.write(`用法：node scripts/icon_catalog/main.mts [-v]\n`);
      return 2;
    }
  }
  const r = run(projectRoot());
  if (verbose) for (const p of r.passes) process.stdout.write("  ok  " + p + "\n");
  if (r.errs.length > 0) {
    process.stderr.write(`FAIL（${r.errs.length} 项）：\n`);
    for (const e of byteSort(r.errs)) process.stderr.write("  - " + e + "\n");
    return 1;
  }
  process.stdout.write(`OK：${r.iconCount} 个图标，契约全绿\n`);
  return 0;
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  process.exit(main(process.argv.slice(2)));
}
