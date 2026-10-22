// render.mts —— docs 站 Markdown 渲染层（#273 批二：mdrender 退役，marked 承接）。
//
// 契约（与退役的 Go mdrender 对齐，见 scripts/docs_preview 历史）：标题 id 走
// GitHub slugger 规则（含 -1/-2 去重）、代码块沿用 tok-* 高亮外壳、表格加
// .table-wrap 外框、链接目标经宿主 rewriter 改写（代码块内容绝不参与改写）。
//
// **渲染差异（诚实记录）**：块级 HTML 细节由 marked（CommonMark+GFM）决定，
// 与手写 mdrender 不逐字节一致；行为面（标题锚点/目录大纲/链接改写/代码转义/
// 表格/任务列表）由 render.test.mts 与全站构建验证。
import { Marked, Renderer, Tokenizer } from "marked";
import type { Tokens } from "marked";
import { escHTML, highlightCode } from "./highlight.mts";

export { escHTML };

export interface OutlineItem {
  l: number;
  i: string;
  t: string;
}

export type HrefRewriter = (dest: string, rel: string) => string;

export interface RenderOptions {
  rewrite?: HrefRewriter;
  rel?: string;
}

export function escAttr(s: string): string {
  let out = "";
  for (const c of s) {
    if (c === "&") out += "&amp;";
    else if (c === "<") out += "&lt;";
    else if (c === ">") out += "&gt;";
    else if (c === '"') out += "&quot;";
    else out += c;
  }
  return out;
}

const RE_ALNUM = /^[\p{L}\p{N}]$/u;
const RE_MARK = /^\p{M}$/u;

// slugify 对齐 GitHub：小写 → 去掉非字母数字（保留汉字/标记/下划线/连字符/空格）→ 空格转连字符。
export function slugify(text: string): string {
  let out = "";
  for (const ch of text.trim().toLowerCase()) {
    if (ch === " " || ch === "-" || ch === "_") out += ch;
    else if (RE_ALNUM.test(ch) || RE_MARK.test(ch)) out += ch;
  }
  return out.trim().replace(/ /g, "-");
}

// plainInline 去掉行内标记，得到标题的可见文本（供 slug 使用，对齐 github-slugger）。
export function plainInline(s: string): string {
  let out = "";
  for (let i = 0; i < s.length; i++) {
    const ch = s[i] ?? "";
    if (ch === "`" || ch === "*" || ch === "_" || ch === "~") continue;
    if (ch === "\\") {
      if (i + 1 < s.length && isASCIIPunct(s[i + 1] ?? "")) {
        out += s[i + 1];
        i++;
        continue;
      }
      out += ch;
      continue;
    }
    if (ch === "[") {
      const parsed = bracketLabel(s, i);
      if (!parsed) {
        out += ch;
        continue;
      }
      out += parsed.label;
      i = parsed.end - 1;
      continue;
    }
    out += ch;
  }
  return out;
}

function isASCIIPunct(ch: string): boolean {
  const c = ch.charCodeAt(0);
  return (c >= 33 && c <= 47) || (c >= 58 && c <= 64) || (c >= 91 && c <= 96) || (c >= 123 && c <= 126);
}

function bracketLabel(s: string, i: number): { label: string; end: number } | null {
  let depth = 0;
  let end = -1;
  for (let j = i; j < s.length; j++) {
    if (s[j] === "\\") {
      j++;
      continue;
    }
    if (s[j] === "[") depth++;
    else if (s[j] === "]") {
      depth--;
      if (depth === 0) end = j;
    }
    if (end >= 0) break;
  }
  if (end < 0) return null;
  const label = s.slice(i + 1, end);
  let k = end + 1;
  while (k < s.length && s[k] === " ") k++;
  if (s[k] === "(") {
    let d = 0;
    while (k < s.length) {
      if (s[k] === "(") d++;
      if (s[k] === ")") {
        d--;
        if (d === 0) {
          k++;
          break;
        }
      }
      k++;
    }
  }
  return { label, end: k };
}

function alignAttr(a: string | null | undefined): string {
  return a ? ` align="${a}"` : "";
}

function makeMarked(opts: RenderOptions): Marked {
  const slugs = new Map<string, number>();
  const rewrite = opts.rewrite;
  const rel = opts.rel ?? "";
  const mapHref = (dest: string): string => (rewrite ? rewrite(dest, rel) : dest);
  const slug = (base: string): string => {
    const n = slugs.get(base) ?? 0;
    slugs.set(base, n + 1);
    return n === 0 ? base : `${base}-${n}`;
  };

  const marked = new Marked({ gfm: true });
  marked.use({
    // mdrender 行为面口径（避免 GFM 扩展越界）：
    // ① 裸邮箱不自动 mailto（本仓正文大量 moonbitlang/x@0.5.5 类文本）；
    // ② 删除线只认 ~~（GFM 单 ~ 会把「批一~批五」吞成删除线）。
    tokenizer: {
      url(this: Tokenizer, src: string) {
        const t = Tokenizer.prototype.url.call(this, src);
        if (t && String(t.href).startsWith("mailto:")) return undefined;
        return t;
      },
      del(this: Tokenizer, src: string, maskedSrc: string, prevChar = "") {
        if (!src.startsWith("~~")) return undefined;
        return Tokenizer.prototype.del.call(this, src, maskedSrc, prevChar);
      },
    },
    renderer: {
      heading(this: Renderer, token: Tokens.Heading): string {
        const id = slug(slugify(plainInline(token.text)) || "section");
        return `<h${token.depth} id="${escAttr(id)}">${this.parser.parseInline(token.tokens)}</h${token.depth}>\n`;
      },
      code(token: Tokens.Code): string {
        const info = (token.lang ?? "").trim();
        const lang = info.split(/\s+/)[0] ?? "";
        if (!lang) return `<pre class="code-plain"><code>${escHTML(token.text)}</code></pre>\n`;
        return (
          `<pre class="code-hl" data-lang="${escAttr(lang)}"><code class="hl">` +
          `${highlightCode(lang, token.text)}</code></pre>\n`
        );
      },
      link(this: Renderer, token: Tokens.Link): string {
        const href = mapHref(token.href);
        const title = token.title ? ` title="${escAttr(token.title)}"` : "";
        return `<a href="${escAttr(href)}"${title}>${this.parser.parseInline(token.tokens)}</a>`;
      },
      image(token: Tokens.Image): string {
        const src = mapHref(token.href);
        const title = token.title ? ` title="${escAttr(token.title)}"` : "";
        return `<img src="${escAttr(src)}" alt="${escAttr(plainInline(token.text))}"${title}>`;
      },
      table(this: Renderer, token: Tokens.Table): string {
        let out = '<div class="table-wrap"><table>\n<thead>\n<tr>\n';
        token.header.forEach((cell, k) => {
          out += `<th${alignAttr(token.align[k] ?? null)}>${this.parser.parseInline(cell.tokens)}</th>\n`;
        });
        out += "</tr>\n</thead>\n<tbody>\n";
        for (const row of token.rows) {
          out += "<tr>\n";
          row.forEach((cell, k) => {
            out += `<td${alignAttr(token.align[k] ?? null)}>${this.parser.parseInline(cell.tokens)}</td>\n`;
          });
          out += "</tr>\n";
        }
        out += "</tbody>\n</table></div>\n";
        return out;
      },
    },
  });
  return marked;
}

export function renderMarkdown(src: string, opts: RenderOptions = {}): string {
  return makeMarked(opts).parse(src, { async: false }) as string;
}

export function renderInline(src: string, opts: RenderOptions = {}): string {
  return makeMarked(opts).parseInline(src, { async: false }) as string;
}

// fragment 是零配置片段渲染入口（课程管线等非 docs 站消费方使用）：
// 无链接改写、无文档语境，只出正文 HTML。
export function fragment(src: string): string {
  return renderMarkdown(src);
}

// ---------------------------------------------------------------------------
// HTML 后处理（大纲 / 纯文本 / 标题抽取）
// ---------------------------------------------------------------------------

const HEADING_RE = /<h([1-6])([^>]*)>([\s\S]*?)<\/h\1>/g;
const ID_RE = /\sid="([^"]*)"/;
const TAG_RE = /<script[^>]*>[\s\S]*?<\/script>|<style[^>]*>[\s\S]*?<\/style>|<[^>]+>/g;
const H1_RE = /<h1[^>]*>([\s\S]*?)<\/h1>/;

function unescapeEntities(s: string): string {
  return s
    .replaceAll("&amp;", "&")
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">")
    .replaceAll("&quot;", '"')
    .replaceAll("&#39;", "'")
    .replaceAll("&#x27;", "'");
}

export function extractOutline(html: string, maxLevel = 3): OutlineItem[] {
  const items: OutlineItem[] = [];
  for (const m of html.matchAll(HEADING_RE)) {
    const level = Number(m[1]);
    if (level > maxLevel) continue;
    const idMatch = ID_RE.exec(m[2] ?? "");
    const id = idMatch?.[1] ?? "";
    const text = unescapeEntities((m[3] ?? "").replace(TAG_RE, "")).trim();
    if (!text || !id) continue;
    items.push({ l: level, i: id, t: text });
  }
  return items;
}

export function renderOutline(items: OutlineItem[]): string {
  if (items.length === 0) return '<div class="outline-empty">（本文无标题）</div>';
  let out = "";
  for (const it of items) {
    out += `<a class="lv${it.l}" href="#${escAttr(it.i)}">${escHTML(it.t)}</a>`;
  }
  return out;
}

export function htmlToText(html: string): string {
  const t = unescapeEntities(html.replace(TAG_RE, " "));
  let out = "";
  let space = false;
  for (const ch of t) {
    if (ch === " " || ch === "\t" || ch === "\n" || ch === "\u00a0") {
      if (!space) {
        out += " ";
        space = true;
      }
      continue;
    }
    space = false;
    out += ch;
  }
  return out.trim();
}

// extractDocTitle 从渲染后的正文抠出第一个 <h1>（内部 HTML 作文档大标题，
// h1 本身从 body 移除——由模板统一排版）。无 h1 返回空串。
export function extractDocTitle(body: string): { title: string; rest: string } {
  const m = H1_RE.exec(body);
  if (!m) return { title: "", rest: body };
  const inner = m[1] ?? "";
  const start = m.index;
  const rest = body.slice(0, start) + body.slice(start + m[0].length);
  return { title: inner.trim(), rest };
}

export function firstHeadingText(body: string): string {
  const m = H1_RE.exec(body);
  if (!m) return "";
  return unescapeEntities((m[1] ?? "").replace(TAG_RE, "")).trim();
}
