// demo_ui_lint · 裸值棘轮（Go→.mts 重写，refs #273；原 raw.go 273 行）
//
// 动机：token 单源（tokens.json → tokens.css）解决了「值从哪来」，样式契约闸
// 解决了「组件有没有接上」，但**新代码仍可以直接写裸 hex / 裸 px 字号**绕过两者
// ——设计稿 Do/Don't 第一条就是禁裸值，此前只有散文约束、没有机判。
//
// 形态选择：**棘轮（ratchet）**而不是「全仓禁裸」。存量债务（app.css 里成片的
// 9–21px 字号与阴影 rgba）一次清零不现实，但可以让它**只减不增**：
//   - 基线 = 当前裸值多重集（file + kind + literal + count），入库；
//   - 新增 / 用量增加 → 红（必须改用 var(--vr-*) 或字号 token）；
//   - 存量减少 / 消失 → 也红（僵尸基线：跑 -update-raw 收窄，基线不许留旧债）。
// 判定面只取 CSS 面（demo/src 的 .css 与 .svelte 的 <style> 块），跳过 @generated
// 生成物（tokens.css 的定义天然是裸值）；TS/JS 面不扫——注释里的 issue 号
// （#122 一类）会被误认为色值，文本闸在那一面没有可靠抽取口径。
//
// 颜色 = #rgb/#rrggbb/#rrggbbaa + rgb()/rgba()/hsl()/hsla()；字号 = font-size
// 声明里的裸 px（其余几何 px 不管——布局 px 属实现细节，字号才是 token 面）。
//
// 迁移口径（#292 批）：写盘键序按 Go struct 字段序（`_comment`/`note`/`surface`/
// `entries`）显式构造；序列化走 `goJSONMarshalIndent`（SetEscapeHTML 口径）。
import fs from "node:fs";
import path from "node:path";
import { byteCompare, goFields, goJSONMarshalIndent } from "../internal/text.mts";
import { walkDirSorted } from "../internal/capi.mts";
import type { Issue } from "./main.mts";

export interface RawEntry {
  file: string;
  /** color | font-px */
  kind: string;
  literal: string;
  count: number;
}

export interface RawBaselineFile {
  _comment?: string;
  note?: string;
  surface?: string[];
  entries?: RawEntry[];
}

const RE_RAW_HEX = /#[0-9a-fA-F]{3,8}\b/g;
/** 捕获完整函数调用，不只函数名：旧形态只记 `rgba()`，改分量/alpha 不红
 *  （2026-10-23 审阅 P3）。函数参数允许跨行，落基线前压空白。 */
const RE_RAW_FN = /\b((?:rgba?|hsla?)\s*\([^)]*\))/gi;
const RE_RAW_FONT_SIZE = /font-size\s*:\s*([^;{}]*)/g;
const RE_RAW_PX = /\d+(?:\.\d+)?px/;
/** 与主闸同口径的 CSS 注释剥除（Go 版跨包复用 reCSSComment）。 */
const RE_CSS_COMMENT = /\/\*[\s\S]*?\*\//g;
const RE_STYLE_BLOCK = /<style[^>]*>([\s\S]*?)<\/style>/g;

const DEFAULT_COMMENT =
  "demo_ui_lint 裸值棘轮基线（#222 P0 第三批，2026-10-21）——只能收窄：清理存量后跑 -update-raw 重写；新增裸值/用量增加/僵尸条目一律红。";
const DEFAULT_NOTE =
  "判定面 = demo/src 的 .css 与 .svelte 的 <style> 块（跳过 @generated 生成物）；颜色 = hex/rgb()/rgba()/hsl()/hsla()，字号 = font-size 里的裸 px。";
const DEFAULT_SURFACE = ["demo/src/**/*.css", "demo/src/**/*.svelte <style>"];

export function rawKey(e: RawEntry): string {
  return e.file + "\x00" + e.kind + "\x00" + e.literal;
}

export function aggregateRaw(input: readonly RawEntry[]): RawEntry[] {
  const m = new Map<string, RawEntry>();
  for (const e of input) {
    const k = rawKey(e);
    const cur = m.get(k);
    if (cur !== undefined) {
      cur.count += e.count;
      continue;
    }
    m.set(k, { ...e });
  }
  const out = [...m.values()];
  out.sort((a, b) => {
    if (a.file !== b.file) return byteCompare(a.file, b.file);
    if (a.kind !== b.kind) return byteCompare(a.kind, b.kind);
    return byteCompare(a.literal, b.literal);
  });
  return out;
}

const toSlash = (p: string): string => p.split(path.sep).join("/");

/**
 * 把扫描到的文件路径归一为基线口径（相对仓库根，posix）。
 * 旧实现直接 ToSlash(p)：`-demo <绝对路径>` 会把 File 写成绝对路径，与
 * 基线 `demo/src/...` 全不匹配，实测 56 条假红（2026-10-23 审阅 P3）。
 *
 * Go 版此处靠 `filepath.Rel(root, p)`，而 `p` 相对、`root` 绝对时 Rel 会**报错**
 * 回落 ToSlash(p)——即「相对 demoDir 时原样落相对路径」是刻意形态，非疏漏。
 * 下方 `path.isAbsolute` 混合判定即复刻这条分流（含跨盘符报错面）。
 */
export function relForBaseline(demoDir: string, p: string): string {
  const absDemo = path.resolve(demoDir);
  if (!path.isAbsolute(p)) return toSlash(p); // Go Rel 对「绝对 root + 相对 p」报错回落
  const root = path.dirname(absDemo);
  const rel = path.relative(root, p);
  if (rel === "") return ".";
  if (path.parse(rel).root !== "") return toSlash(p); // 跨盘符：Go Rel 报错回落
  return toSlash(rel);
}

/** 扫 demo/src 的 CSS 面（.css + .svelte <style>），跳过生成物。 */
export function collectRawLiterals(demoDir: string): RawEntry[] {
  const out: RawEntry[] = [];
  const root = path.join(demoDir, "src");
  walkDirSorted(root, (full, name, isDir) => {
    if (isDir) return;
    const isCSS = name.endsWith(".css");
    const isSvelte = name.endsWith(".svelte");
    if (!isCSS && !isSvelte) return;
    const buf = fs.readFileSync(full);
    // Go 侧 head = text[:300]（**字节**切片，可能切断 UTF-8 序列）；@generated
    // 判定只做子串搜索，截断产出的替换字符不影响结论。
    const head = buf.subarray(0, 300).toString("utf8");
    if (head.includes("@generated")) return; // 生成物：tokens.css 的色值本来就是裸值
    let text = buf.toString("utf8");
    if (isSvelte) {
      let sb = "";
      for (const m of text.matchAll(RE_STYLE_BLOCK)) sb += (m[1] ?? "") + "\n";
      text = sb;
    }
    text = text.replace(RE_CSS_COMMENT, "");
    const rel = relForBaseline(demoDir, full);
    for (const m of text.matchAll(RE_RAW_HEX)) out.push({ file: rel, kind: "color", literal: m[0], count: 1 });
    for (const m of text.matchAll(RE_RAW_FN)) {
      out.push({ file: rel, kind: "color", literal: goFields(m[1] ?? "").join(" "), count: 1 });
    }
    for (const m of text.matchAll(RE_RAW_FONT_SIZE)) {
      const v = RE_RAW_PX.exec(m[1] ?? "");
      if (v !== null) out.push({ file: rel, kind: "font-px", literal: v[0], count: 1 });
    }
  });
  return aggregateRaw(out);
}

export function checkRaw(actual: readonly RawEntry[], baseline: readonly RawEntry[]): Issue[] {
  const out: Issue[] = [];
  const bm = new Map<string, RawEntry>();
  for (const e of baseline) bm.set(rawKey(e), e);
  const am = new Map<string, RawEntry>();
  for (const e of actual) am.set(rawKey(e), e);
  for (const [k, a] of am) {
    const b = bm.get(k);
    if (b === undefined) {
      out.push({
        kind: "raw",
        msg: `新增裸值 ${a.literal}（${a.kind}，${a.file}）——改用 var(--vr-*) / --vr-fs 字号 token，或先把它加进 tokens.json`,
      });
      continue;
    }
    if (a.count > b.count) {
      out.push({
        kind: "raw",
        msg: `裸值用量增加 ${a.file}（${a.literal}，${b.count} → ${a.count} 次）——棘轮只减不增`,
      });
    }
  }
  for (const [k, b] of bm) {
    const a = am.get(k);
    if (a === undefined) {
      out.push({
        kind: "raw",
        // Go 原文保留 `go run` 处方（改文案即破逐字对拍；终局批统一改写）
        msg: `僵尸基线 ${b.file}（${b.kind}，${b.literal}）已消失——跑 go run ./scripts/demo_ui_lint -update-raw 收窄`,
      });
      continue;
    }
    if (a.count < b.count) {
      out.push({
        kind: "raw",
        msg: `裸值用量减少 ${b.file}（${b.literal}，${b.count} → ${a.count} 次）——僵尸基线，跑 -update-raw 收窄`,
      });
    }
  }
  out.sort((x, y) => byteCompare(x.msg, y.msg));
  return out;
}

/** 同集绿 / 新色红 / 新字号红 / 僵尸红 / 用量增加 / 色值分量变化 + 绝对路径归一。 */
export function selftestRaw(): string | null {
  const base: RawEntry[] = [
    { file: "demo/src/a.css", kind: "color", literal: "#fff", count: 1 },
    { file: "demo/src/a.css", kind: "color", literal: "rgba(0, 0, 0, .5)", count: 1 },
    { file: "demo/src/a.css", kind: "font-px", literal: "12px", count: 2 },
  ];
  const same = checkRaw(base, base);
  if (same.length !== 0) return `同集应绿，得到 ${same.length} 条：${same[0]?.msg ?? ""}`;
  const cases: Array<{ name: string; act: RawEntry[] }> = [
    { name: "新增色值", act: [...base, { file: "demo/src/a.css", kind: "color", literal: "#123456", count: 1 }] },
    { name: "新增字号", act: [...base, { file: "demo/src/b.svelte", kind: "font-px", literal: "9.5px", count: 1 }] },
    {
      name: "用量增加",
      act: [
        { file: "demo/src/a.css", kind: "color", literal: "#fff", count: 1 },
        { file: "demo/src/a.css", kind: "color", literal: "rgba(0, 0, 0, .5)", count: 1 },
        { file: "demo/src/a.css", kind: "font-px", literal: "12px", count: 3 },
      ],
    },
    {
      name: "色值分量变化",
      act: [
        { file: "demo/src/a.css", kind: "color", literal: "#fff", count: 1 },
        { file: "demo/src/a.css", kind: "color", literal: "rgba(0, 0, 0, .6)", count: 1 },
        { file: "demo/src/a.css", kind: "font-px", literal: "12px", count: 2 },
      ],
    },
    { name: "僵尸基线", act: [{ file: "demo/src/a.css", kind: "color", literal: "#fff", count: 1 }] },
  ];
  for (const c of cases) {
    if (checkRaw(c.act, base).length === 0) return `${c.name} 未被判红——棘轮失效`;
  }
  // 绝对路径归一：-demo <绝对路径> 不得把 File 写成绝对路径（审阅 P3）
  const wd = process.cwd();
  const p = path.join(wd, "demo", "src", "a.css");
  const got = relForBaseline(path.join(wd, "demo"), p);
  const want = "demo/src/a.css";
  if (got !== want) return `绝对路径归一失效：${JSON.stringify(got)} != ${JSON.stringify(want)}`;
  return null;
}

export function loadRawBaseline(p: string): RawEntry[] {
  const f = JSON.parse(fs.readFileSync(p, "utf8")) as RawBaselineFile;
  return f.entries ?? []; // Go nil slice 等价：缺键 = 空基线（零值口径，不是静默 default）
}

export function writeRawBaseline(p: string, entries: readonly RawEntry[]): void {
  // 键序 = Go struct 字段序（json.MarshalIndent 按声明序输出）
  const f: RawBaselineFile = {
    _comment: DEFAULT_COMMENT,
    note: DEFAULT_NOTE,
    surface: [...DEFAULT_SURFACE],
    entries: entries.map((e) => ({ file: e.file, kind: e.kind, literal: e.literal, count: e.count })),
  };
  fs.writeFileSync(p, goJSONMarshalIndent(f) + "\n", "utf8");
}

export function countRawKind(entries: readonly RawEntry[], kind: string): number {
  let n = 0;
  for (const e of entries) if (e.kind === kind) n++;
  return n;
}
