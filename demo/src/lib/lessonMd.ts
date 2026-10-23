// lessonMd —— 课程叙述解析器（demo 消费端，TS 零 npm）。
//
// 切分线（2026-10-15 用户授权实施）：course/*.md 是 **demo 自家资产**
// （非引擎包资产），消费端解析自家格式合规（#125「TS 仅消费端合法」；
// parser.c 的三模式全部是随包引擎资产 schema——给包外 demo 内容加模式
// 属边界反向污染，故解析不走 parser.c）。
//
// schema（与 course/ 真源对齐，version 字段留演进空间）：
//   frontmatter：--- 围栏 key: value（id/kind/order 必填语义由消费方校验；
//     title 也入 meta——2026-10-16 E-08 换真值批补收：真源 frontmatter 事实
//     携带 title（basic/bubble 等试点课实证），此前按「正文承载」不读是缺口，
//     消费端（E-08 golden / lessonNotes）需要全链真源化的标题）
//   正文：## / ### 标题、段落、- 无序列表、1. 有序列表、``` 围栏代码、
//         GFM 表格——行内样式（粗体/行内码）v1 保持原样文本，token 化留 v2
//         （version 字段即为此留）。
//   可选：body 顶部 `<!-- vitri-scenes v1 ... -->` 分镜元数据（2026-10-21
//         拍板：scene 真源 = lesson.md，不建 beats.ts）；解析时从 blocks
//         剥离，CourseNote / E-08 渲染面逐字节不变。

export interface LessonMeta {
  id: string;
  kind: string;
  order: number;
  title?: string;
  famId?: string;
  stdin?: string;
}

export type Block =
  | { type: "h2" | "h3" | "p"; text: string }
  | { type: "ul" | "ol"; items: string[] }
  | { type: "code"; lang: string; text: string }
  | { type: "table"; rows: string[][] };

/** 分镜（scene）：lesson.md body 顶部 `vitri-scenes` 注释块的解析产物。
 *  与 blocks 同源、不新增正文段落——注释在解析时剥离，CourseNote / E-08
 *  渲染面保持逐字节不变。
 *  - v1：from/to 是 viewFrames 下标（闭区间）——写死数字。
 *  - v2（#238）：from/to 为**锚点表达式**（`@first_swap±K` 等，完整词汇表
 *    见 lib/scenes.ts resolveScenes）——帧流就绪后由 resolveScenes 动态
 *    求值（帧数随程序参数变化，写死下标结构性必错：课程曾写死 0..41
 *    vs 引擎实测 914 帧，89.5% 帧落幕外）。锚点形态时 from/to 解析期存
 *    -1 占位 + fromAnchor/toAnchor 留原文；消费方必须经 resolveScenes
 *    （sceneIndexAt 对 -1 天然「不猜」）。 */
export interface Scene {
  id: string;
  title: string;
  from: number;
  to: number;
  /** v2 锚点表达式（如 `@first_swap-1`）；v1 数字形态无此字段。 */
  fromAnchor?: string;
  toAnchor?: string;
  lines: [number, number];
  note: string;
}

export interface LessonDoc {
  version: 1;
  meta: LessonMeta;
  blocks: Block[];
  /** 无 scene 元数据的课 = []，消费方回退现有长文。 */
  scenes: Scene[];
}

// ── 行内样式 token（v2 兑现——头注 schema 留的演进位）──────────────
// 支持 **粗体** 与 `行内码` 两种（课程真源实际使用的全集）；嵌套/转义不
// 支持（教学文案不需要）。消费端（CourseNote）用 Svelte 分支渲染，零
// innerHTML——XSS 面与块级同源（#125 归零原则不因 token 化回退）。
export type Inline =
  | { t: "text"; s: string }
  | { t: "bold"; s: string }
  | { t: "code"; s: string };

const INLINE_RE = /(\*\*[^*]+\*\*|`[^`]+`)/g;

/** 行内文本 → token 序列。无任何标记时返回单 text 段（零开销快路径）。 */
export function parseInline(text: string): Inline[] {
  if (!text.includes("**") && !text.includes("`")) return [{ t: "text", s: text }];
  return text
    .split(INLINE_RE)
    .filter((seg) => seg !== "")
    .map((seg): Inline => {
      if (seg.startsWith("**") && seg.endsWith("**") && seg.length > 4) return { t: "bold", s: seg.slice(2, -2) };
      if (seg.startsWith("`") && seg.endsWith("`") && seg.length > 2) return { t: "code", s: seg.slice(1, -1) };
      return { t: "text", s: seg };
    });
}

export class LessonParseError extends Error {}

/** 解析 lesson.md 全文。fail loud：缺 frontmatter 围栏 / 缺必填字段直接抛。 */
export function parseLessonMd(src: string): LessonDoc {
  const s = src.replace(/\r\n/g, "\n").replace(/^\uFEFF/, "");
  if (!s.startsWith("---\n")) throw new LessonParseError("缺 frontmatter 开栏");
  const rest = s.slice(4);
  const end = rest.indexOf("\n---");
  if (end < 0) throw new LessonParseError("缺 frontmatter 收栏");
  const meta: LessonMeta = { id: "", kind: "", order: 0 };
  for (const line of rest.slice(0, end).split("\n")) {
    const t = line.trim();
    if (!t || t.startsWith("#")) continue;
    const ci = t.indexOf(":");
    if (ci < 0) throw new LessonParseError(`frontmatter 行非 key: value 形态: ${t}`);
    const k = t.slice(0, ci).trim();
    const v = trimQuotes(t.slice(ci + 1).trim());
    if (k === "id") meta.id = v;
    else if (k === "kind") meta.kind = v;
    else if (k === "order") meta.order = Number.parseInt(v, 10) || 0;
    else if (k === "title") meta.title = v; // 2026-10-16 补收（见头注 schema 说明）
    else if (k === "famId") meta.famId = v;
    else if (k === "stdin") meta.stdin = v;
    // 其余展示字段不进 meta；未知字段静默跳过（宽容读取——
    // 与 gen_course 的 fail loud 生成期校验分属两道：读取宽容、生成严格）
  }
  if (!meta.id || !meta.kind) throw new LessonParseError("frontmatter 缺 id 或 kind");

  const body = rest.slice(end + 4).replace(/^\n+/, "");
  const sceneDoc = extractScenes(body);
  return { version: 1, meta, blocks: parseBlocks(sceneDoc.body.split("\n")), scenes: sceneDoc.scenes };
}

/** 从 body 顶部剥离 `<!-- vitri-scenes v1|v2 ... -->` 并解析。
 *  只在 body 开头识别（正文中间的注释按普通段落保留）；格式错误 fail loud，
 *  由 lessonNotes 的 catch 兜底为诚实的「无叙述」而不是半截 scene。
 *  v2 锚点行（#238）：第 3 列为锚点表达式（`@word(:arg)?(±K)?` 或纯数字
 *  ——纯数字在 v2 里同样合法），静态校验只做形态与纯数字段的重叠；锚点段
 *  的重叠/乱序由课源保证（resolveScenes 后 sceneIndexAt 顺序扫描，重叠时
 *  靠前的幕赢）。 */
function extractScenes(body: string): { body: string; scenes: Scene[] } {
  const prefix = body.match(/^<!--\s*vitri-scenes\b/);
  if (!prefix) return { body, scenes: [] };
  const head = body.match(/^<!--\s*vitri-scenes\s+v(\d+)[^\n]*\n/);
  if (!head) throw new LessonParseError("scene 元数据缺版本行（vitri-scenes v1）");
  if (head[1] !== "1" && head[1] !== "2") throw new LessonParseError(`不支持的 scene 版本 v${head[1]}`);
  const ver = Number.parseInt(head[1], 10);
  const close = body.indexOf("\n-->", head[0].length);
  if (close < 0) throw new LessonParseError("scene 元数据未闭合");
  const raw = body.slice(head[0].length, close);
  const rest = body.slice(close + 4).replace(/^\n+/, "");
  const scenes: Scene[] = [];
  const ids = new Set<string>();
  let prevTo = -1;
  const anchorExpr = /^(@[A-Za-z_][\w]*(?::[\w]+)?(?:[+-]\d+)?|@\d+)$/;
  for (const line of raw.split("\n")) {
    const t = line.trim();
    if (!t) continue;
    // v2：头内注释行忽略——判据是「不含 |」（注释无竖线分隔、幕行必有
    // 4 个）；比「数字起首」稳（注释以数字起〔如「20 变实测分解」〕不误判
    // 幕行，含 | 的行一律走 5 段解析——id 形态错即红，不静默吞，fail-loud）。
    if (ver === 2 && !t.includes("|")) continue;
    const m = t.match(/^([^|]+)\|([^|]+)\|([^|]+)\|([^|]+)\|(.*)$/);
    if (!m) throw new LessonParseError(`scene 行不是 5 段形态: ${t}`);
    const id = m[1].trim();
    const title = m[2].trim();
    const ft = m[3].trim();
    const fromTo = ft.match(/^(\S+)\.\.(\S+)$/);
    const lineRange = m[4].trim().match(/^(\d+)\.\.(\d+)$/);
    if (!id || !title) throw new LessonParseError(`scene 缺 id 或 title: ${t}`);
    if (ids.has(id)) throw new LessonParseError(`scene id 重复: ${id}`);
    if (!fromTo || !lineRange) throw new LessonParseError(`scene 范围须为 a..b: ${t}`);
    const l0 = Number.parseInt(lineRange[1], 10);
    const l1 = Number.parseInt(lineRange[2], 10);
    if (l0 < 1 || l1 < l0) throw new LessonParseError(`scene 行区间非法: ${t}`);
    // v1 / v2 纯数字：静态数字直存；v2 锚点：-1 占位 + 原文（resolveScenes 求值）
    const numeric = (s: string): number | null => /^\d+$/.test(s) ? Number.parseInt(s, 10) : null;
    const fromN = numeric(fromTo[1]);
    const toN = numeric(fromTo[2]);
    if (ver === 1 && (fromN === null || toN === null)) {
      throw new LessonParseError(`v1 scene 帧范围须为数字 a..b: ${t}`);
    }
    if (ver === 2 && (fromN === null) !== (toN === null)) {
      throw new LessonParseError(`v2 scene 帧范围两端须同为数字或同为锚点: ${t}`);
    }
    if (ver === 2 && fromN === null) {
      if (!anchorExpr.test(fromTo[1]) || !anchorExpr.test(fromTo[2])) {
        throw new LessonParseError(`v2 锚点形态非法（@word(:arg)?(±K)?）: ${t}`);
      }
    }
    if (fromN !== null && toN !== null && fromN > toN) {
      throw new LessonParseError(`scene 帧范围非法: ${t}`);
    }
    if (fromN !== null && toN !== null && fromN <= prevTo) {
      throw new LessonParseError(`scene 帧范围重叠或乱序: ${id}`);
    }
    const scene: Scene = {
      id,
      title,
      from: fromN ?? -1,
      to: toN ?? -1,
      lines: [l0, l1],
      note: m[5].trim(),
    };
    if (fromN === null) {
      scene.fromAnchor = fromTo[1];
      scene.toAnchor = fromTo[2];
    } else {
      prevTo = toN as number;
    }
    ids.add(id);
    scenes.push(scene);
  }
  if (scenes.length === 0) throw new LessonParseError("scene 元数据为空");
  return { body: rest, scenes };
}

function trimQuotes(v: string): string {
  return v.length >= 2 && (v[0] === '"' || v[0] === "'") && v[v.length - 1] === v[0] ? v.slice(1, -1) : v;
}

function parseBlocks(lines: string[]): Block[] {
  const blocks: Block[] = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    const t = line.trim();
    if (!t) {
      i += 1;
      continue;
    }
    if (t.startsWith("```")) {
      const lang = t.slice(3).trim();
      const buf: string[] = [];
      i += 1;
      while (i < lines.length && !lines[i].trim().startsWith("```")) {
        buf.push(lines[i]);
        i += 1;
      }
      blocks.push({ type: "code", lang, text: buf.join("\n") });
      i += 1;
      continue;
    }
    if (line.startsWith("## ")) {
      blocks.push({ type: "h2", text: line.slice(3).trim() });
      i += 1;
      continue;
    }
    if (line.startsWith("### ")) {
      blocks.push({ type: "h3", text: line.slice(4).trim() });
      i += 1;
      continue;
    }
    if (/^\|.*\|\s*$/.test(line) && i + 1 < lines.length && /^\|[\s:|-]+\|\s*$/.test(lines[i + 1])) {
      // GFM 表格：第二行为分隔栏
      const rows: string[][] = [splitTableRow(line)];
      i += 2;
      while (i < lines.length && /^\|.*\|\s*$/.test(lines[i])) {
        rows.push(splitTableRow(lines[i]));
        i += 1;
      }
      blocks.push({ type: "table", rows });
      continue;
    }
    if (/^[-*] /.test(t)) {
      blocks.push({ type: "ul", items: collectList(lines, i, /^\s*[-*] /, t.slice(2)) });
      i = skipList(lines, i, /^\s*[-*] /);
      continue;
    }
    if (/^\d+\. /.test(t)) {
      blocks.push({ type: "ol", items: collectList(lines, i, /^\s*\d+\. /, t.replace(/^\d+\. /, "")) });
      i = skipList(lines, i, /^\s*\d+\. /);
      continue;
    }
    // 段落：连续非空非结构行合并
    const buf = [t];
    i += 1;
    while (i < lines.length && lines[i].trim() && !/^(#{2,3} |[-*] |\d+\. |```|\|)/.test(lines[i].trim())) {
      buf.push(lines[i].trim());
      i += 1;
    }
    blocks.push({ type: "p", text: buf.join(" ") });
  }
  return blocks;
}

function splitTableRow(line: string): string[] {
  return line
    .trim()
    .replace(/^\||\|$/g, "")
    .split("|")
    .map((c) => c.trim());
}

function collectList(lines: string[], start: number, re: RegExp, first: string): string[] {
  const items = [first];
  let i = start + 1;
  while (i < lines.length) {
    const m = lines[i].match(re);
    if (m) {
      items.push(lines[i].trim().replace(re, ""));
      i += 1;
    } else if (lines[i].trim() && /^\s{2,}/.test(lines[i])) {
      // 续行并入上一条
      items[items.length - 1] += " " + lines[i].trim();
      i += 1;
    } else break;
  }
  return items;
}

function skipList(lines: string[], i: number, re: RegExp): number {
  i += 1;
  while (i < lines.length && (re.test(lines[i].trim()) || (lines[i].trim() && /^\s{2,}/.test(lines[i])))) i += 1;
  return i;
}
