package main

// page.go —— 页面骨架、左侧目录树、右侧大纲、目录清单页。

import (
	"regexp"
	"sort"
	"strings"
	"time"
)

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
`

type pageTemplateData struct {
	title       string
	source      string
	assets      string
	nav         string
	chips       string
	mtime       string
	lines       string
	size        string
	body        string
	outline     string
	ghURL       string
	crumbs      string
	breadcrumbs string
	docTitle    string
	words       string
	readMin     string
	brandHref   string
}

func renderPage(d pageTemplateData) string {
	docTitleBlock := ""
	if d.docTitle != "" {
		docTitleBlock = `<h1 class="doc-title">` + d.docTitle + `</h1>`
	}
	r := strings.NewReplacer(
		"__TITLE__", escHTML(d.title),
		"__SOURCE__", escHTML(d.source),
		"__ASSETS__", d.assets,
		"__NAV__", d.nav,
		"__CHIPS__", d.chips,
		"__MTIME__", escHTML(d.mtime),
		"__LINES__", d.lines,
		"__SIZE__", d.size,
		"__BODY__", d.body,
		"__OUTLINE__", d.outline,
		"__GHURL__", d.ghURL,
		"__CRUMBS__", escHTML(d.crumbs),
		"__BREADCRUMBS__", d.breadcrumbs,
		"__DOCTITLE_BLOCK__", docTitleBlock,
		"__WORDS__", d.words,
		"__READMIN__", d.readMin,
		"__BRANDHREF__", d.brandHref,
		"__BUILT__", time.Now().Format("2006-01-02 15:04"),
	)
	return r.Replace(pageTemplate)
}

// ---------------------------------------------------------------------------
// 目录树
// ---------------------------------------------------------------------------

type navNode struct {
	rel   string
	dirs  map[string]*navNode
	order []string
	files []*doc
}

func renderNav(docs []*doc, dirs []string, dirMap map[string]string, pageDir, activeRel string) string {
	root := &navNode{dirs: map[string]*navNode{}}
	for _, d := range dirs {
		if d == "." {
			continue
		}
		cur := root
		for _, part := range strings.Split(d, "/") {
			cur = cur.child(part)
		}
		cur.rel = d
	}
	for _, d := range docs {
		cur := root
		parts := strings.Split(d.rel, "/")
		for _, part := range parts[:len(parts)-1] {
			cur = cur.child(part)
		}
		cur.files = append(cur.files, d)
	}

	var b strings.Builder
	b.WriteString(`<ul class="nav-list nav-root">`)
	sort.Slice(root.files, func(i, j int) bool {
		return naturalLess(strings.ToLower(root.files[i].rel), strings.ToLower(root.files[j].rel))
	})
	for _, d := range root.files {
		class := "nav-link nav-root-link"
		if d.rel == activeRel {
			class += " is-active"
		}
		b.WriteString(`<li><a class="` + class + `" href="` + relHref(pageDir, d.out) + `">` +
			escHTML(d.title) + `</a></li>`)
	}
	names := append([]string(nil), root.order...)
	sort.Slice(names, func(i, j int) bool {
		// archive 组永远沉底（对外呈现"当前有效"优先；组内仍按名称序）
		ai, aj := names[i] == "archive", names[j] == "archive"
		if ai != aj {
			return aj
		}
		return naturalLess(names[i], names[j])
	})
	for _, name := range names {
		writeNavNode(&b, root.dirs[name], dirMap, pageDir, activeRel)
	}
	b.WriteString(`</ul>`)
	return b.String()
}

func (n *navNode) child(name string) *navNode {
	if c, ok := n.dirs[name]; ok {
		return c
	}
	c := &navNode{dirs: map[string]*navNode{}}
	n.dirs[name] = c
	n.order = append(n.order, name)
	return c
}

func writeNavNode(b *strings.Builder, n *navNode, dirMap map[string]string, pageDir, activeRel string) {
	open := true
	if strings.HasPrefix(n.rel, "archive") {
		open = false
	}
	active := activeRel != "" && n.rel != "" && strings.HasPrefix(activeRel+"/", n.rel+"/")
	if active {
		open = true
	}
	b.WriteString(`<li class="nav-dir"><details`)
	if open {
		b.WriteString(` open`)
	}
	b.WriteString(` data-group="` + escAttr(n.rel) + `"><summary>`)
	if page, ok := dirMap[n.rel]; ok {
		b.WriteString(`<a class="nav-dir-a" href="` + relHref(pageDir, page) + `">` +
			escHTML(dirLabel(n.rel)) + `</a>`)
	} else {
		b.WriteString(`<span class="nav-dir-a">` + escHTML(dirLabel(n.rel)) + `</span>`)
	}
	b.WriteString(`<span class="nav-cnt">` + strconvItoa(countNav(n)) + `</span></summary><ul class="nav-list">`)

	sort.Slice(n.files, func(i, j int) bool {
		return naturalLess(strings.ToLower(n.files[i].rel), strings.ToLower(n.files[j].rel))
	})
	for _, d := range n.files {
		if d.rel == "README.md" {
			continue
		}
		class := "nav-link"
		if d.rel == activeRel {
			class += " is-active"
		}
		title := d.rel + "（" + d.mtime.Format("2006-01-02 15:04") + "）"
		b.WriteString(`<li><a class="` + class + `" href="` + relHref(pageDir, d.out) + `" title="` +
			escAttr(title) + `">` + escHTML(d.title) + `</a></li>`)
	}
	names := append([]string(nil), n.order...)
	sort.Slice(names, func(i, j int) bool { return naturalLess(names[i], names[j]) })
	for _, name := range names {
		writeNavNode(b, n.dirs[name], dirMap, pageDir, activeRel)
	}
	b.WriteString(`</ul></details></li>`)
}

func countNav(n *navNode) int {
	total := len(n.files)
	for _, c := range n.dirs {
		total += countNav(c)
	}
	return total
}

func strconvItoa(n int) string {
	if n == 0 {
		return "0"
	}
	var buf [20]byte
	i := len(buf)
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	return string(buf[i:])
}

func dirLabel(rel string) string {
	if rel == "." || rel == "" {
		return "docs"
	}
	if i := strings.LastIndex(rel, "/"); i >= 0 {
		return rel[i+1:]
	}
	return rel
}

func chipsFor(rel string) string {
	if rel == "README.md" {
		return `<span class="chip chip-root">文档索引</span>`
	}
	top := rel
	if i := strings.Index(rel, "/"); i >= 0 {
		top = rel[:i]
	}
	switch top {
	case "current":
		return `<span class="chip chip-current">当前有效</span>`
	case "spec":
		return `<span class="chip chip-spec">协议承诺</span>`
	case "archive":
		return `<span class="chip chip-archive">历史归档</span>` +
			`<span class="chip chip-warn">内容可能已过时 · 不再维护</span>`
	default:
		return `<span class="chip chip-other">` + escHTML(top) + `</span>`
	}
}

// breadcrumbsFor 生成博客式面包屑（参考 tokenizers-moonbit 文档站形态）：
// 「首页 › current › 02-构建与上手 › 快速入门」——目录段链接到目录清单页
// （dirMap 命中时），末段为当前页纯文本。pageDir = 当前页输出目录（相对链接基准）。
func breadcrumbsFor(rel, pageDir string, dirMap map[string]string) string {
	var b strings.Builder
	if home := dirMap["."]; home != "" {
		b.WriteString(`<a class="crumb crumb-home" href="` + relHref(pageDir, home) + `">首页</a>`)
	}
	parts := strings.Split(rel, "/")
	for i, seg := range parts {
		b.WriteString(`<span class="crumb-sep">›</span>`)
		if i == len(parts)-1 {
			name := strings.TrimSuffix(seg, ".md")
			b.WriteString(`<span class="crumb is-here">` + escHTML(name) + `</span>`)
			continue
		}
		dirRel := strings.Join(parts[:i+1], "/")
		if page, ok := dirMap[dirRel]; ok {
			b.WriteString(`<a class="crumb" href="` + relHref(pageDir, page) + `">` + escHTML(seg) + `</a>`)
		} else {
			b.WriteString(`<span class="crumb">` + escHTML(seg) + `</span>`)
		}
	}
	return b.String()
}

// countWords 统计「字数」：CJK 字符按字计，非 CJK 连续字母/数字段按词计。
func countWords(text string) int {
	total := 0
	inWord := false
	for _, r := range text {
		if r >= 0x2E80 { // CJK 及全角区
			total++
			inWord = false
			continue
		}
		if isWordSepASCII(r) {
			inWord = false
			continue
		}
		if !inWord {
			total++
			inWord = true
		}
	}
	return total
}

func isWordSepASCII(r rune) bool {
	switch {
	case r == ' ' || r == '\t' || r == '\n' || r == '\u00a0':
		return true
	case r >= '!' && r <= '/':
		return true
	case r >= ':' && r <= '@':
		return true
	case r >= '[' && r <= '`':
		return true
	case r >= '{' && r <= '~':
		return true
	}
	return false
}

// readingLabel 阅读时长口径：400 字/分钟，不足 1 分钟显示「小于 1 分钟」。
func readingLabel(words int) string {
	if words < 400 {
		return "小于 1 分钟"
	}
	return strconvItoa((words+399)/400) + " 分钟"
}

// extractDocTitle 从渲染后的正文抠出第一个 <h1>（内部 HTML 作文档大标题，
// h1 本身从 body 移除——由模板统一排版）。无 h1 返回空串。
func extractDocTitle(body string) (title, rest string) {
	loc := h1Re.FindStringIndex(body)
	if loc == nil {
		return "", body
	}
	inner := h1Re.FindStringSubmatch(body)[1]
	rest = body[:loc[0]] + body[loc[1]:]
	return strings.TrimSpace(inner), rest
}

// ---------------------------------------------------------------------------
// 大纲
// ---------------------------------------------------------------------------

var (
	headingRe = regexp.MustCompile(`(?s)<h([1-6])([^>]*)>(.*?)</h[1-6]>`)
	idRe      = regexp.MustCompile(`\sid="([^"]*)"`)
	// RE2 不支持反向引用，script/style 用显式分支
	tagRe = regexp.MustCompile(`(?s)<script[^>]*>.*?</script>|<style[^>]*>.*?</style>|<[^>]+>`)
	h1Re  = regexp.MustCompile(`(?s)<h1[^>]*>(.*?)</h1>`)
)

func extractOutline(html string, maxLevel int) []outlineItem {
	var items []outlineItem
	for _, m := range headingRe.FindAllStringSubmatch(html, -1) {
		level := int(m[1][0] - '0')
		if level > maxLevel {
			continue
		}
		id := ""
		if sm := idRe.FindStringSubmatch(m[2]); sm != nil {
			id = sm[1]
		}
		text := strings.TrimSpace(unescapeEntities(tagRe.ReplaceAllString(m[3], "")))
		if text == "" || id == "" {
			continue
		}
		items = append(items, outlineItem{Level: level, ID: id, Text: text})
	}
	return items
}

func renderOutline(items []outlineItem) string {
	if len(items) == 0 {
		return `<div class="outline-empty">（本文无标题）</div>`
	}
	var b strings.Builder
	for _, it := range items {
		b.WriteString(`<a class="lv` + strconvItoa(it.Level) + `" href="#` + escAttr(it.ID) + `">` +
			escHTML(it.Text) + `</a>`)
	}
	return b.String()
}

func htmlToText(html string) string {
	t := tagRe.ReplaceAllString(html, " ")
	t = unescapeEntities(t)
	var b strings.Builder
	space := false
	for _, r := range t {
		if r == ' ' || r == '\t' || r == '\n' || r == '\u00a0' {
			if !space {
				b.WriteByte(' ')
				space = true
			}
			continue
		}
		space = false
		b.WriteRune(r)
	}
	return strings.TrimSpace(b.String())
}

func firstHeadingText(html string) string {
	if m := h1Re.FindStringSubmatch(html); m != nil {
		return strings.TrimSpace(unescapeEntities(tagRe.ReplaceAllString(m[1], "")))
	}
	return ""
}

// ---------------------------------------------------------------------------
// 目录清单页
// ---------------------------------------------------------------------------

func renderDirPage(docs []*doc, subdirs []string, rel string) string {
	var b strings.Builder
	b.WriteString(`<h1 id="dir-index">` + escHTML(dirLabel(rel)) + `/ 目录</h1>` + "\n")
	b.WriteString(`<p>本目录共 ` + strconvItoa(len(docs)) + ` 篇文档`)
	if len(subdirs) > 0 {
		b.WriteString(`、` + strconvItoa(len(subdirs)) + ` 个子目录`)
	}
	b.WriteString(`。</p>` + "\n")
	b.WriteString(`<div class="table-wrap"><table><thead><tr><th>文件</th><th>标题</th><th>修改时间</th><th>大小</th></tr></thead><tbody>`)
	for _, d := range subdirs {
		b.WriteString(`<tr><td class="col-n"><a href="` + encodeSegment(dirLabel(d)) + `/index.html">` +
			escHTML(dirLabel(d)) + `/</a></td><td class="col-t">目录</td><td class="col-m">—</td><td class="col-m">—</td></tr>`)
	}
	sort.Slice(docs, func(i, j int) bool {
		return naturalLess(strings.ToLower(docs[i].rel), strings.ToLower(docs[j].rel))
	})
	for _, d := range docs {
		name := pathBase(d.rel)
		b.WriteString(`<tr><td class="col-n"><a href="` + encodeSegment(strings.TrimSuffix(name, ".md")) + `.html">` +
			escHTML(name) + `</a></td><td class="col-t">` + escHTML(d.title) +
			`</td><td class="col-m">` + d.mtime.Format("2006-01-02 15:04") +
			`</td><td class="col-m">` + humanSize(d.size) + `</td></tr>`)
	}
	b.WriteString(`</tbody></table></div>` + "\n")
	return b.String()
}

func pathBase(p string) string {
	if i := strings.LastIndex(p, "/"); i >= 0 {
		return p[i+1:]
	}
	return p
}
