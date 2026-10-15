// lessonMd —— 课程叙述解析器（demo 消费端，TS 零 npm）。
//
// 切分线（2026-10-15 用户授权实施）：course/*.md 是 **demo 自家资产**
// （非引擎包资产），消费端解析自家格式合规（#125「TS 仅消费端合法」；
// parser.c 的三模式全部是随包引擎资产 schema——给包外 demo 内容加模式
// 属边界反向污染，故解析不走 parser.c）。
//
// schema（与 course/ 真源对齐，version 字段留演进空间）：
//   frontmatter：--- 围栏 key: value（id/kind/order 必填语义由消费方校验）
//   正文：## / ### 标题、段落、- 无序列表、1. 有序列表、``` 围栏代码、
//         GFM 表格——行内样式（粗体/行内码）v1 保持原样文本，token 化留 v2
//         （version 字段即为此留）。

export interface LessonMeta {
  id: string;
  kind: string;
  order: number;
  famId?: string;
  stdin?: string;
}

export type Block =
  | { type: "h2" | "h3" | "p"; text: string }
  | { type: "ul" | "ol"; items: string[] }
  | { type: "code"; lang: string; text: string }
  | { type: "table"; rows: string[][] };

export interface LessonDoc {
  version: 1;
  meta: LessonMeta;
  blocks: Block[];
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
    else if (k === "famId") meta.famId = v;
    else if (k === "stdin") meta.stdin = v;
    // title 等展示字段不进 meta（正文承载）；未知字段静默跳过（宽容读取——
    // 与 gen_course 的 fail loud 生成期校验分属两道：读取宽容、生成严格）
  }
  if (!meta.id || !meta.kind) throw new LessonParseError("frontmatter 缺 id 或 kind");

  const body = rest.slice(end + 4).replace(/^\n+/, "");
  return { version: 1, meta, blocks: parseBlocks(body.split("\n")) };
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
