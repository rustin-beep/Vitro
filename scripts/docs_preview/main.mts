// docs_preview —— docs/ 全量 Markdown → 纯静态 HTML 站点（#273 批二：Go → .mts）。
//
// 用法（仓库根目录）：
//
//	node scripts/docs_preview/main.mts              # 增量构建（默认输出 tmp/docs_preview）
//	node scripts/docs_preview/main.mts -open        # 构建后打开首页
//	node scripts/docs_preview/main.mts -watch       # 常驻监听：新增 / 修改 / 删除 md 自动重建
//	node scripts/docs_preview/main.mts -force       # 忽略缓存全量重建
//	node scripts/docs_preview/main.mts -out DIR     # 自定义输出目录
//	node scripts/docs_preview/main.mts -section current  # 只渲染指定顶层子树（对外部署口径）
//
// 产物（默认 tmp/docs_preview/，已被 .gitignore 忽略，不污染仓库）：
//
//	index.html               docs/README.md 的渲染结果（入口）
//	<原目录结构>/*.html       每篇 md 一个页面
//	<目录>/index.html        无 README 的目录 = 目录清单页
//	assets/                  样式 / 脚本 / 检索索引（构建期从 assets/ 释放）
//	_report.txt              构建报告：文档数、断链明细（诚实记录，不静默吞掉）
//
// 渲染口径：marked（CommonMark+GFM）+ 标题 GitHub slugger id + tok-* 词法高亮
// （见 render.mts / highlight.mts）；与退役的 Go mdrender 行为面契约由
// render.test.mts 锁。
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { spawn, spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { extractDocTitle, extractOutline, firstHeadingText, htmlToText, renderMarkdown } from "./render.mts";
import type { OutlineItem } from "./render.mts";
import {
  breadcrumbsFor,
  chipsFor,
  type Doc,
  renderDirPage,
  renderNav,
  renderOutline,
  renderPage,
} from "./page.mts";
import {
  countWords,
  dashPath,
  depthOf,
  dirLabel,
  encodePath,
  fmtTime,
  naturalLess,
  readingLabel,
  relHref,
} from "./paths.mts";

const repoSlug = "rustin-beep/Vitro";
const repoURL = "https://github.com/" + repoSlug;
// 渲染器版本：改动渲染逻辑后 +1（缓存整体失效）。
// v11：mdrender → marked + 移植高亮器（#273 批二）。
const rendererVersion = 11;

const rootDir = path.resolve(import.meta.dirname, "../..");
const docsDir = path.join(rootDir, "docs");
let repoBranch = "HEAD";
let sectionFilter = "";

interface CacheEntry {
  sha1: string;
  title: string;
  html: string;
  outline: OutlineItem[];
  text: string;
  missing?: string[];
}

interface CacheFile {
  renderer: number;
  entries: Record<string, CacheEntry>;
}

interface Options {
  out: string;
  open: boolean;
  watch: boolean;
  force: boolean;
  quiet: boolean;
  section: string;
}

function die(msg: string): never {
  console.error("[docs_preview] " + msg);
  process.exit(1);
}

function parseArgs(argv: string[]): Options {
  const opts: Options = {
    out: path.join("tmp", "docs_preview"),
    open: false,
    watch: false,
    force: false,
    quiet: false,
    section: "",
  };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i] ?? "";
    const eq = arg.indexOf("=");
    const flag = eq >= 0 ? arg.slice(0, eq) : arg;
    const inline = eq >= 0 ? arg.slice(eq + 1) : "";
    const value = (): string => {
      if (inline !== "") return inline;
      const next = argv[++i];
      if (next === undefined) die(`参数缺值: ${flag}`);
      return next;
    };
    switch (flag) {
      case "-out":
        opts.out = value();
        break;
      case "-open":
        opts.open = true;
        break;
      case "-watch":
        opts.watch = true;
        break;
      case "-force":
        opts.force = true;
        break;
      case "-quiet":
        opts.quiet = true;
        break;
      case "-section":
        opts.section = value();
        break;
      default:
        die(`未知参数: ${arg}`);
    }
  }
  return opts;
}

function detectBranch(): string {
  const r = spawnSync("git", ["rev-parse", "--abbrev-ref", "HEAD"], { cwd: rootDir, encoding: "utf8" });
  const s = (r.stdout ?? "").trim();
  return s !== "" ? s : "HEAD";
}

interface CollectResult {
  docs: Doc[];
  dirs: string[];
}

function collectDocs(): CollectResult {
  if (!fs.existsSync(docsDir) || !fs.statSync(docsDir).isDirectory()) die(`找不到文档目录：${docsDir}`);
  const docs: Doc[] = [];

  const walk = (dir: string): void => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) {
        walk(p);
        continue;
      }
      if (!e.name.toLowerCase().endsWith(".md")) continue;
      const rel = path.relative(docsDir, p).split(path.sep).join("/");
      // -section 过滤（对外部署口径）：只保留根 README + 指定顶层子树
      if (sectionFilter !== "" && rel !== "README.md" && !rel.startsWith(sectionFilter + "/")) continue;
      const info = fs.statSync(p);
      const data = fs.readFileSync(p);
      const sha1 = crypto.createHash("sha1").update(data).digest("hex");
      const out = rel === "README.md" ? "index.html" : rel.slice(0, rel.length - path.extname(rel).length) + ".html";
      const source = data.toString("utf8");
      docs.push({
        rel,
        out,
        title: path.basename(rel, ".md"),
        mtime: info.mtime,
        size: info.size,
        lines: (source.match(/\n/g) ?? []).length + 1,
        html: "",
        outline: [],
        text: "",
        source,
        sha1,
      });
    }
  };
  walk(docsDir);
  docs.sort((a, b) => (a.rel < b.rel ? -1 : a.rel > b.rel ? 1 : 0));

  const dirs: string[] = ["."];
  const walkDirs = (dir: string): void => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      if (!e.isDirectory()) continue;
      const p = path.join(dir, e.name);
      const rel = path.relative(docsDir, p).split(path.sep).join("/");
      if (sectionFilter !== "" && rel !== sectionFilter && !rel.startsWith(sectionFilter + "/")) continue;
      dirs.push(rel);
      walkDirs(p);
    }
  };
  walkDirs(docsDir);
  dirs.sort((a, b) => (naturalLess(a, b) ? -1 : 1));
  return { docs, dirs };
}

// ---------------------------------------------------------------------------
// 链接改写
// ---------------------------------------------------------------------------

const schemeRe = /^[a-zA-Z][a-zA-Z0-9+.-]*:/;

class Rewriter {
  missing: Array<[string, string]> = [];
  private readonly docMap: Map<string, string>;
  private readonly dirMap: Map<string, string>;

  constructor(docMap: Map<string, string>, dirMap: Map<string, string>) {
    this.docMap = docMap;
    this.dirMap = dirMap;
  }

  mapHref(valueRaw: string, docRel: string): string {
    let docDir = path.posix.dirname(docRel);
    if (docDir === ".") docDir = "";
    const value = valueRaw.trim();
    if (value === "" || value.startsWith("#")) return value;
    if (value.startsWith("//") || schemeRe.test(value)) return value;
    if (value.startsWith("/")) {
      const rel = value.slice(1);
      return repoURLFor(rel, isDir(path.join(rootDir, rel)));
    }

    let pathPart = value;
    const hashAt = pathPart.indexOf("#");
    if (hashAt >= 0) pathPart = pathPart.slice(0, hashAt);
    const queryAt = pathPart.indexOf("?");
    if (queryAt >= 0) pathPart = pathPart.slice(0, queryAt);
    const frag = value.slice(pathPart.length);
    if (pathPart === "") return value;

    let decoded = pathPart;
    try {
      decoded = decodeURIComponent(pathPart);
    } catch {
      decoded = pathPart;
    }
    // Go path.Clean 口径：折叠 ./ 与尾部斜杠（dirMap 键不带尾斜杠）
    const joined = path.posix.normalize(path.posix.join(docDir, decoded));
    const target = joined.length > 1 ? joined.replace(/\/+$/, "") : joined;

    // 相对基准 = 当前文档输出页所在目录（不是目标自己的目录）
    let srcDir = "";
    const srcPage = this.docMap.get(docRel);
    if (srcPage !== undefined) {
      const pd = path.posix.dirname(srcPage);
      if (pd !== ".") srcDir = pd;
    }

    if (target.startsWith("..")) {
      const repoRel = path.posix.normalize(path.posix.join("docs", target));
      return repoURLFor(repoRel, isDir(path.join(rootDir, repoRel)));
    }

    const abs = path.join(docsDir, target);
    if (fs.existsSync(abs) && fs.statSync(abs).isDirectory()) {
      const page = this.dirMap.get(target);
      if (page !== undefined) return relHref(srcDir, page) + frag;
      return repoURLFor(path.posix.join("docs", target), true);
    }

    if (decoded.toLowerCase().endsWith(".md")) {
      const page = this.docMap.get(target);
      if (page !== undefined) return relHref(srcDir, page) + frag;
      this.missing.push([docRel, value]);
      return repoURLFor(path.posix.join("docs", target), false);
    }
    if (fs.existsSync(abs)) this.missing.push([docRel, value]);
    return repoURLFor(path.posix.join("docs", target), false);
  }
}

function repoURLFor(repoRel: string, isDirectory: boolean): string {
  const verb = isDirectory ? "tree" : "blob";
  // Go path.Join 口径：尾部斜杠会被 Clean 掉（目录链接不产出 docs/archive/ 形态）
  const clean = path.posix.normalize(repoRel).replace(/\/+$/, "");
  return repoURL + "/" + verb + "/" + repoBranch + "/" + encodePath(clean);
}

function isDir(p: string): boolean {
  try {
    return fs.statSync(p).isDirectory();
  } catch {
    return false;
  }
}

// ---------------------------------------------------------------------------
// 构建
// ---------------------------------------------------------------------------

function build(outDir: string, doOpen: boolean, force: boolean, quiet: boolean): void {
  const started = performance.now();
  const { docs, dirs } = collectDocs();
  if (docs.length === 0) die("docs/ 下没有 Markdown 文件");

  const docMap = new Map<string, string>();
  for (const d of docs) docMap.set(d.rel, d.out);
  const dirMap = new Map<string, string>();
  for (const rel of dirs) dirMap.set(rel, rel === "." ? "index.html" : rel + "/index.html");

  const cachePath = path.join(outDir, ".cache.json");
  let entries: Record<string, CacheEntry> = {};
  if (!force) {
    try {
      const cf = JSON.parse(fs.readFileSync(cachePath, "utf8")) as CacheFile;
      if (cf.renderer === rendererVersion && cf.entries) entries = cf.entries;
    } catch {
      entries = {};
    }
  }

  const rw = new Rewriter(docMap, dirMap);
  let rebuilt = 0;

  for (const d of docs) {
    const hit = entries[d.rel];
    if (!force && hit && hit.sha1 === d.sha1) {
      d.title = hit.title;
      d.html = hit.html;
      d.outline = hit.outline;
      d.text = hit.text;
      continue;
    }
    rw.missing = [];
    const body = renderMarkdown(d.source, { rewrite: (dest, rel) => rw.mapHref(dest, rel), rel: d.rel });
    d.html = body;
    d.outline = extractOutline(body, 3);
    d.text = htmlToText(body);
    const t = firstHeadingText(body);
    if (t !== "") d.title = t;
    entries[d.rel] = {
      sha1: d.sha1,
      title: d.title,
      html: d.html,
      outline: d.outline,
      text: d.text,
      missing: rw.missing.map((p) => p[1]),
    };
    rebuilt++;
  }

  const seen = new Set<string>();
  for (const d of docs) {
    const pageDir = path.posix.dirname(d.out) === "." ? "" : path.posix.dirname(d.out);
    const { title: docTitle, rest: body } = extractDocTitle(d.html);
    const words = countWords(d.text);
    const page = renderPage({
      title: d.title,
      source: "docs/" + d.rel,
      assets: "../".repeat(depthOf(pageDir)) + "assets/",
      nav: renderNav(docs, dirs, dirMap, pageDir, d.rel),
      chips: chipsFor(d.rel),
      mtime: fmtTime(d.mtime),
      body,
      outline: renderOutline(d.outline),
      ghURL: repoURL + "/blob/" + repoBranch + "/" + encodePath("docs/" + d.rel),
      crumbs: "docs/" + d.rel,
      breadcrumbs: breadcrumbsFor(d.rel, pageDir, dirMap),
      docTitle,
      words: String(words),
      readMin: readingLabel(words),
      brandHref: relHref(pageDir, docMap.get("README.md") ?? "index.html"),
    });
    writeFile(path.join(outDir, d.out), page);
    seen.add(d.out);
  }

  for (const rel of dirs) {
    const children = docs.filter((d) => path.posix.dirname(d.rel) === rel && path.posix.basename(d.rel) !== "README.md");
    const subdirs = dirs.filter((dd) => {
      if (dd === ".") return false;
      return (rel === "." && !dd.includes("/")) || path.posix.dirname(dd) === rel;
    });
    const pageOut = dirMap.get(rel) ?? "index.html";
    if (rel === "." && docMap.get("README.md") === pageOut) continue;
    const body = renderDirPage(children, subdirs, rel);
    const pageDir = path.posix.dirname(pageOut) === "." ? "" : path.posix.dirname(pageOut);
    const title = dirLabel(rel) + "/ 目录";
    const page = renderPage({
      title,
      source: "docs/" + dirLabel(rel),
      assets: "../".repeat(depthOf(pageDir)) + "assets/",
      nav: renderNav(docs, dirs, dirMap, pageDir, ""),
      chips: '<span class="chip chip-root">目录清单</span>',
      mtime: "—",
      body,
      outline: renderOutline(extractOutline(body, 3)),
      ghURL: repoURL + "/tree/" + repoBranch + "/docs" + dashPath(rel),
      crumbs: "docs/" + dashPath(rel),
      breadcrumbs: breadcrumbsFor(path.posix.join(rel, "README.md").replace(/\/$/, ""), pageDir, dirMap),
      docTitle: "",
      words: "—",
      readMin: "—",
      brandHref: relHref(pageDir, docMap.get("README.md") ?? "index.html"),
    });
    writeFile(path.join(outDir, pageOut), page);
    seen.add(pageOut);
  }

  const assetsOut = path.join(outDir, "assets");
  fs.mkdirSync(assetsOut, { recursive: true });
  for (const name of ["style.css", "app.js"]) {
    fs.copyFileSync(path.join(rootDir, "scripts/docs_preview/assets", name), path.join(assetsOut, name));
  }
  fs.writeFileSync(path.join(assetsOut, "search-index.js"), buildSearchIndex(docs));

  const removed = cleanupStale(outDir, seen);
  fs.mkdirSync(outDir, { recursive: true });
  fs.writeFileSync(cachePath, JSON.stringify({ renderer: rendererVersion, entries }));

  const broken: Array<[string, string]> = [];
  for (const d of docs) {
    const e = entries[d.rel];
    if (!e) continue;
    for (const tgt of e.missing ?? []) broken.push([d.rel, tgt]);
  }
  const brokenSorted = dedupePairs(broken);
  const report: string[] = [
    "Vitro docs 本地预览构建报告",
    "生成时间：" + fmtTime(new Date()) + ":" + String(new Date().getSeconds()).padStart(2, "0"),
    "输出目录：" + outDir,
    `文档总数：${docs.length}（本次重渲染 ${rebuilt}，缓存命中 ${docs.length - rebuilt}）`,
    `目录页：${dirs.length}，清理陈旧页：${removed}`,
    `指向仓库内 docs 之外目标的链接（按 GitHub 地址输出）：${brokenSorted.length}`,
  ];
  if (brokenSorted.length > 0) {
    report.push("", "链接明细（源文档 → 目标；docs 外的源码/脚本文件只能指向 GitHub）：");
    for (const [src, tgt] of brokenSorted) report.push("  " + src + " → " + tgt);
  }
  writeFile(path.join(outDir, "_report.txt"), report.join("\n") + "\n");

  if (!quiet) for (const line of report.slice(0, 6)) console.log("[docs_preview] " + line);
  console.log(
    `[docs_preview] 完成，耗时 ${((performance.now() - started) / 1000).toFixed(2)}s → 双击打开：${path.join(outDir, "index.html")}`
  );
  if (doOpen) openInBrowser(path.join(outDir, "index.html"));
}

function writeFile(p: string, content: string): void {
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, content);
}

// cleanupStale 依据上一轮 manifest 删除本轮不再产出的页面。
function cleanupStale(outDir: string, seen: Set<string>): number {
  const manifestPath = path.join(outDir, ".manifest.json");
  let removed = 0;
  try {
    const prev = JSON.parse(fs.readFileSync(manifestPath, "utf8")) as { files?: string[] };
    for (const f of prev.files ?? []) {
      if (seen.has(f)) continue;
      const full = path.join(outDir, f);
      try {
        if (fs.statSync(full).isFile()) {
          fs.rmSync(full);
          removed++;
        }
      } catch {
        // 已不存在：无害
      }
    }
  } catch {
    // 无 manifest：首次构建
  }
  fs.mkdirSync(outDir, { recursive: true });
  fs.writeFileSync(manifestPath, JSON.stringify({ files: [...seen].sort() }));
  return removed;
}

function buildSearchIndex(docs: Doc[]): string {
  const list = docs.map((d) => ({
    p: d.out,
    t: d.title,
    s: "docs/" + d.rel,
    h: d.outline.map((h) => ({ i: h.i, t: h.t })),
    x: d.text,
  }));
  const s = JSON.stringify(list).replaceAll("</", "<\\/");
  return "window.__VITRO_DOCS_INDEX = " + s + ";\n";
}

function dedupePairs(pairs: Array<[string, string]>): Array<[string, string]> {
  const seen = new Set<string>();
  const out: Array<[string, string]> = [];
  for (const p of pairs) {
    const k = p[0] + "\0" + p[1];
    if (seen.has(k)) continue;
    seen.add(k);
    out.push(p);
  }
  out.sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : a[1] < b[1] ? -1 : a[1] > b[1] ? 1 : 0));
  return out;
}

function openInBrowser(p: string): void {
  const abs = path.resolve(p);
  const cmd =
    process.platform === "win32"
      ? { bin: "rundll32", args: ["url.dll,FileProtocolHandler", abs] }
      : process.platform === "darwin"
        ? { bin: "open", args: [abs] }
        : { bin: "xdg-open", args: [abs] };
  try {
    spawn(cmd.bin, cmd.args, { detached: true, stdio: "ignore" }).unref();
  } catch (e) {
    console.error(`[docs_preview] 自动打开失败（${String(e)}），请手动双击 ${abs}`);
  }
}

// ---------------------------------------------------------------------------
// 监听
// ---------------------------------------------------------------------------

function snapshot(): Map<string, number> {
  const snap = new Map<string, number>();
  const walk = (dir: string): void => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) walk(p);
      else if (e.name.toLowerCase().endsWith(".md")) snap.set(p, fs.statSync(p).mtimeMs);
    }
  };
  walk(docsDir);
  return snap;
}

function snapEqual(a: Map<string, number>, b: Map<string, number>): boolean {
  if (a.size !== b.size) return false;
  for (const [k, v] of a) if (b.get(k) !== v) return false;
  return true;
}

function watchLoop(outDir: string, force: boolean, quiet: boolean): void {
  console.log(`[docs_preview] 监听 ${docsDir}（Ctrl+C 退出）：新增 / 修改 / 删除 md 自动重建。`);
  try {
    build(outDir, false, force, quiet);
  } catch (e) {
    console.error("[docs_preview] " + String(e));
  }
  let prev = snapshot();
  setInterval(() => {
    const cur = snapshot();
    if (snapEqual(prev, cur)) return;
    let added = 0;
    let changed = 0;
    let gone = 0;
    for (const [k, v] of cur) {
      if (!prev.has(k)) added++;
      else if (prev.get(k) !== v) changed++;
    }
    for (const k of prev.keys()) if (!cur.has(k)) gone++;
    console.log(`[docs_preview] 变动：新增 ${added} / 修改 ${changed} / 删除 ${gone}`);
    try {
      build(outDir, false, false, quiet);
    } catch (e) {
      console.error("[docs_preview] " + String(e));
    }
    prev = cur;
  }, 1500);
}

// ---------------------------------------------------------------------------

export { build, collectDocs, Rewriter, repoURLFor };

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;

if (invokedDirectly) {
  const opts = parseArgs(process.argv.slice(2));
  sectionFilter = opts.section;
  repoBranch = detectBranch();
  const outDir = path.isAbsolute(opts.out) ? opts.out : path.join(rootDir, opts.out);

  if (opts.watch) {
    watchLoop(outDir, opts.force, opts.quiet);
  } else {
    try {
      build(outDir, opts.open, opts.force, opts.quiet);
    } catch (e) {
      die(String(e));
    }
  }
}
