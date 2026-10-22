// page.mts —— 页面骨架、左侧目录树、右侧大纲、目录清单页（Go page.go 移植）。
import { escAttr, escHTML, renderOutline } from "./render.mts";
import type { OutlineItem } from "./render.mts";
import {
  countWords,
  dirLabel,
  encodeSegment,
  fmtTime,
  humanSize,
  naturalLess,
  pathBase,
  readingLabel,
  relHref,
} from "./paths.mts";

export interface Doc {
  rel: string;
  out: string;
  title: string;
  mtime: Date;
  size: number;
  lines: number;
  html: string;
  outline: OutlineItem[];
  text: string;
  source: string;
  sha1: string;
}

const pageTemplate = `<!DOCTYPE html>
<html lang="zh-CN" data-color-mode="light" data-preview="vitro-docs-preview">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="generator" content="vitro docs_preview">
<meta name="doc-source" content="__SOURCE__">
<title>__TITLE__ · Vitro docs</title>
<link rel="stylesheet" href="__ASSETS__style.css">
</head>
<body>
<header class="topbar">
  <button class="icon-btn" id="nav-toggle" type="button" title="显示 / 隐藏目录树" aria-label="显示或隐藏目录树">☰</button>
  <div class="crumbs" title="__SOURCE__">__CRUMBS__</div>
  <div class="topbar-search">
    <input id="search" type="search" placeholder="搜索文档（按 / 聚焦）" autocomplete="off">
    <div class="search-hits" id="search-hits" hidden></div>
  </div>
  <div class="topbar-right">
    <a class="icon-btn gh" href="__GHURL__" target="_blank" rel="noopener" title="在 GitHub 上查看源文件">GitHub ↗</a>
    <button class="icon-btn" id="theme-toggle" type="button" title="切换明暗主题（自动 / 浅色 / 深色）">◐</button>
    <button class="icon-btn" id="outline-toggle" type="button" title="显示 / 隐藏大纲">☰☰</button>
  </div>
</header>
<div class="layout" id="layout">
  <aside class="sidebar" id="sidebar">
    <div class="site-brand">
      <a class="brand-link" href="__BRANDHREF__">Vitro <span>docs</span></a>
      <div class="brand-sub">教学 C 子集引擎 · 白箱后端</div>
    </div>
    __NAV__
  </aside>
  <main class="content">
    <div class="doc-head">
      <nav class="breadcrumbs">__BREADCRUMBS__</nav>
      <div class="chips">__CHIPS__</div>
      __DOCTITLE_BLOCK__
      <div class="doc-meta">
        <span class="meta-left"><span>__WORDS__ 字</span><span class="dot">·</span><span>约 __READMIN__ 阅读</span></span>
        <span class="meta-right"><span title="源文件最后修改">__MTIME__</span></span>
      </div>
    </div>
    <article class="markdown-body" id="doc">__BODY__</article>
    <footer class="doc-foot">
      <a class="edit-link" href="__GHURL__" target="_blank" rel="noopener">✎ 在 GitHub 上编辑此页</a>
      <span class="foot-meta">最后更新 __MTIME__ · <code>__SOURCE__</code></span>
    </footer>
  </main>
  <aside class="outline-wrap" id="outline-wrap">
    <div class="outline-title">大纲</div>
    <nav class="outline" id="outline">__OUTLINE__</nav>
  </aside>
</div>
<script src="__ASSETS__app.js" defer></script>
</body>
</html>
`;

export interface PageTemplateData {
  title: string;
  source: string;
  assets: string;
  nav: string;
  chips: string;
  mtime: string;
  body: string;
  outline: string;
  ghURL: string;
  crumbs: string;
  breadcrumbs: string;
  docTitle: string;
  words: string;
  readMin: string;
  brandHref: string;
}

export function renderPage(d: PageTemplateData): string {
  const docTitleBlock = d.docTitle ? `<h1 class="doc-title">${d.docTitle}</h1>` : "";
  const repl: Record<string, string> = {
    __TITLE__: escHTML(d.title),
    __SOURCE__: escHTML(d.source),
    __ASSETS__: d.assets,
    __NAV__: d.nav,
    __CHIPS__: d.chips,
    __MTIME__: escHTML(d.mtime),
    __BODY__: d.body,
    __OUTLINE__: d.outline,
    __GHURL__: d.ghURL,
    __CRUMBS__: escHTML(d.crumbs),
    __BREADCRUMBS__: d.breadcrumbs,
    __DOCTITLE_BLOCK__: docTitleBlock,
    __WORDS__: d.words,
    __READMIN__: d.readMin,
    __BRANDHREF__: d.brandHref,
  };
  return pageTemplate.replace(/__[A-Z_]+__/g, (m) => repl[m] ?? m);
}

// ---------------------------------------------------------------------------
// 目录树
// ---------------------------------------------------------------------------

interface NavNode {
  rel: string;
  dirs: Map<string, NavNode>;
  order: string[];
  files: Doc[];
}

function newNode(): NavNode {
  return { rel: "", dirs: new Map(), order: [], files: [] };
}

function child(n: NavNode, name: string): NavNode {
  const hit = n.dirs.get(name);
  if (hit) return hit;
  const c = newNode();
  n.dirs.set(name, c);
  n.order.push(name);
  return c;
}

export function renderNav(
  docs: Doc[],
  dirs: string[],
  dirMap: Map<string, string>,
  pageDir: string,
  activeRel: string
): string {
  const root = newNode();
  for (const d of dirs) {
    if (d === ".") continue;
    let cur = root;
    for (const part of d.split("/")) cur = child(cur, part);
    cur.rel = d;
  }
  for (const d of docs) {
    let cur = root;
    const parts = d.rel.split("/");
    for (const part of parts.slice(0, -1)) cur = child(cur, part);
    cur.files.push(d);
  }

  const out: string[] = ['<ul class="nav-list nav-root">'];
  root.files.sort((a, b) => (naturalLess(a.rel.toLowerCase(), b.rel.toLowerCase()) ? -1 : 1));
  for (const d of root.files) {
    let cls = "nav-link nav-root-link";
    if (d.rel === activeRel) cls += " is-active";
    out.push(`<li><a class="${cls}" href="${relHref(pageDir, d.out)}">${escHTML(d.title)}</a></li>`);
  }
  const names = [...root.order];
  names.sort((a, b) => {
    // archive 组永远沉底（对外呈现"当前有效"优先；组内仍按名称序）
    const ai = a === "archive";
    const bi = b === "archive";
    if (ai !== bi) return ai ? 1 : -1;
    return naturalLess(a, b) ? -1 : 1;
  });
  for (const name of names) {
    const n = root.dirs.get(name);
    if (n) out.push(writeNavNode(n, dirMap, pageDir, activeRel));
  }
  out.push("</ul>");
  return out.join("");
}

function writeNavNode(n: NavNode, dirMap: Map<string, string>, pageDir: string, activeRel: string): string {
  let open = !n.rel.startsWith("archive");
  const active = activeRel !== "" && n.rel !== "" && `${activeRel}/`.startsWith(`${n.rel}/`);
  if (active) open = true;
  const out: string[] = [`<li class="nav-dir"><details${open ? " open" : ""} data-group="${escAttr(n.rel)}"><summary>`];
  const page = dirMap.get(n.rel);
  if (page !== undefined) {
    out.push(`<a class="nav-dir-a" href="${relHref(pageDir, page)}">${escHTML(dirLabel(n.rel))}</a>`);
  } else {
    out.push(`<span class="nav-dir-a">${escHTML(dirLabel(n.rel))}</span>`);
  }
  out.push(`<span class="nav-cnt">${countNav(n)}</span></summary><ul class="nav-list">`);

  n.files.sort((a, b) => (naturalLess(a.rel.toLowerCase(), b.rel.toLowerCase()) ? -1 : 1));
  for (const d of n.files) {
    if (d.rel === "README.md") continue;
    let cls = "nav-link";
    if (d.rel === activeRel) cls += " is-active";
    const title = `${d.rel}（${fmtTime(d.mtime)}）`;
    out.push(
      `<li><a class="${cls}" href="${relHref(pageDir, d.out)}" title="${escAttr(title)}">${escHTML(d.title)}</a></li>`
    );
  }
  const names = [...n.order];
  names.sort((a, b) => (naturalLess(a, b) ? -1 : 1));
  for (const name of names) {
    const c = n.dirs.get(name);
    if (c) out.push(writeNavNode(c, dirMap, pageDir, activeRel));
  }
  out.push("</ul></details></li>");
  return out.join("");
}

function countNav(n: NavNode): number {
  let total = n.files.length;
  for (const c of n.dirs.values()) total += countNav(c);
  return total;
}

export function chipsFor(rel: string): string {
  if (rel === "README.md") return '<span class="chip chip-root">文档索引</span>';
  let top = rel;
  const i = rel.indexOf("/");
  if (i >= 0) top = rel.slice(0, i);
  switch (top) {
    case "current":
      return '<span class="chip chip-current">当前有效</span>';
    case "spec":
      return '<span class="chip chip-spec">协议承诺</span>';
    case "archive":
      return (
        '<span class="chip chip-archive">历史归档</span>' +
        '<span class="chip chip-warn">内容可能已过时 · 不再维护</span>'
      );
    default:
      return `<span class="chip chip-other">${escHTML(top)}</span>`;
  }
}

// breadcrumbsFor 生成博客式面包屑（参考 tokenizers-moonbit 文档站形态）：
// 「首页 › current › 02-构建与上手 › 快速入门」——目录段链接到目录清单页
// （dirMap 命中时），末段为当前页纯文本。pageDir = 当前页输出目录（相对链接基准）。
export function breadcrumbsFor(rel: string, pageDir: string, dirMap: Map<string, string>): string {
  const out: string[] = [];
  const home = dirMap.get(".");
  if (home !== undefined) out.push(`<a class="crumb crumb-home" href="${relHref(pageDir, home)}">首页</a>`);
  const parts = rel.split("/");
  parts.forEach((seg, i) => {
    out.push('<span class="crumb-sep">›</span>');
    if (i === parts.length - 1) {
      const name = seg.replace(/\.md$/, "");
      out.push(`<span class="crumb is-here">${escHTML(name)}</span>`);
      return;
    }
    const dirRel = parts.slice(0, i + 1).join("/");
    const page = dirMap.get(dirRel);
    if (page !== undefined) out.push(`<a class="crumb" href="${relHref(pageDir, page)}">${escHTML(seg)}</a>`);
    else out.push(`<span class="crumb">${escHTML(seg)}</span>`);
  });
  return out.join("");
}

// ---------------------------------------------------------------------------
// 目录清单页
// ---------------------------------------------------------------------------

export function renderDirPage(docs: Doc[], subdirs: string[], rel: string): string {
  const out: string[] = [];
  out.push(`<h1 id="dir-index">${escHTML(dirLabel(rel))}/ 目录</h1>\n`);
  out.push(`<p>本目录共 ${docs.length} 篇文档`);
  if (subdirs.length > 0) out.push(`、${subdirs.length} 个子目录`);
  out.push("。</p>\n");
  out.push(
    '<div class="table-wrap"><table><thead><tr><th>文件</th><th>标题</th><th>修改时间</th><th>大小</th></tr></thead><tbody>'
  );
  for (const d of subdirs) {
    out.push(
      `<tr><td class="col-n"><a href="${encodeSegment(dirLabel(d))}/index.html">` +
        `${escHTML(dirLabel(d))}/</a></td><td class="col-t">目录</td><td class="col-m">—</td><td class="col-m">—</td></tr>`
    );
  }
  docs.sort((a, b) => (naturalLess(a.rel.toLowerCase(), b.rel.toLowerCase()) ? -1 : 1));
  for (const d of docs) {
    const name = pathBase(d.rel);
    out.push(
      `<tr><td class="col-n"><a href="${encodeSegment(name.replace(/\.md$/, ""))}.html">` +
        `${escHTML(name)}</a></td><td class="col-t">${escHTML(d.title)}` +
        `</td><td class="col-m">${fmtTime(d.mtime)}` +
        `</td><td class="col-m">${humanSize(d.size)}</td></tr>`
    );
  }
  out.push("</tbody></table></div>\n");
  return out.join("");
}

export { countWords, readingLabel, renderOutline };
