package main

// 图标资产契约闸 —— 判定型脚本（零第三方依赖、规则外置 rules.json、fail loud）。
//
// 用法（flag 必须写在任何位置参数之前）：
//
//	go run ./scripts/icon_catalog        # 校验并打印摘要
//	go run ./scripts/icon_catalog -v     # 额外逐条打印通过的检查项
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
//  9. 几何层 assets/icons.json 的 digest 与现算一致（生成物同步）
//
// 退出码：0 全绿 / 1 有违规（逐条列 stderr）/ 2 用法或环境错（fail loud，不静默 default）。

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

type Rules struct {
	AssetsDir   string `json:"assets_dir"`
	IndexTsv    string `json:"index_tsv"`
	GeometryJSON string `json:"geometry_json"`
	SvgAttrs    map[string]string `json:"svg_attrs"`

	AllowedElements []string `json:"allowed_elements"`
	RectForbidden   []string `json:"rect_forbidden_attrs"`

	ForbidColorLiteral     bool `json:"forbid_color_literal"`
	ForbidNamedColor       bool `json:"forbid_named_color"`
	ForbidZeroLengthSubpath bool `json:"forbid_zero_length_subpath"`
	ForbidAriaHidden       bool `json:"forbid_aria_hidden"`
	RequireTitle           bool `json:"require_title"`
	RequireDesc            bool `json:"require_desc"`

	TsvColumns         []string `json:"tsv_columns"`
	Categories         []string `json:"categories"`
	Scopes             []string `json:"scopes"`
	EmojiRequiredScopes []string `json:"emoji_required_scopes"`
	EmojiMustBeUnique   bool     `json:"emoji_must_be_unique"`

	GeometrySchema string `json:"geometry_schema"`
	NamedColors    []string `json:"named_colors"`
}

var (
	colorLiteralRe = regexp.MustCompile(`#[0-9a-fA-F]{3,8}\b|rgba?\(|hsla?\(`)
	zeroLenSubRe   = regexp.MustCompile(`[hv]0*\.0+`)
	elemRe         = regexp.MustCompile(`(?s)<(path|circle|rect|line|polyline|polygon|ellipse|text|g|image|use|script|style)\b`)
	attrRe         = regexp.MustCompile(`([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*"([^"]*)"`)
	titleRe        = regexp.MustCompile(`(?s)<title>(.*?)</title>`)
	descRe         = regexp.MustCompile(`(?s)<desc>(.*?)</desc>`)
	svgOpenRe      = regexp.MustCompile(`(?s)<svg\b([^>]*)>`)
	idRe           = regexp.MustCompile(`^[a-z][a-z0-9]*(-[a-z0-9]+)*$`)
)

type tsvRow struct {
	cols []string
}

func main() {
	verbose := flag.Bool("v", false, "额外逐条打印通过的检查项")
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "用法：go run ./scripts/icon_catalog [-v]\n")
		flag.PrintDefaults()
	}
	flag.Parse()

	rulesPath := "scripts/icon_catalog/rules.json"
	raw, err := os.ReadFile(rulesPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "FATAL: 读不到规则文件 %s：%v\n", rulesPath, err)
		os.Exit(2)
	}
	var rules Rules
	if err := json.Unmarshal(raw, &rules); err != nil {
		fmt.Fprintf(os.Stderr, "FATAL: 规则文件解析失败 %s：%v\n", rulesPath, err)
		os.Exit(2)
	}
	if rules.AssetsDir == "" || rules.IndexTsv == "" {
		fmt.Fprintf(os.Stderr, "FATAL: 规则缺 assets_dir / index_tsv（fail loud，不猜默认值）\n")
		os.Exit(2)
	}

	var errs []string
	var passes []string
	fail := func(format string, a ...any) { errs = append(errs, fmt.Sprintf(format, a...)) }
	pass := func(format string, a ...any) { passes = append(passes, fmt.Sprintf(format, a...)) }

	// 1) 资产面：逐 svg 契约校验
	entries, err := os.ReadDir(rules.AssetsDir)
	if err != nil {
		fmt.Fprintf(os.Stderr, "FATAL: 读不到资产目录 %s：%v\n", rules.AssetsDir, err)
		os.Exit(2)
	}
	ids := []string{}
	svgBytes := map[string][]byte{}
	allowed := map[string]bool{}
	for _, e := range rules.AllowedElements {
		allowed[e] = true
	}
	forbiddenRect := map[string]bool{}
	for _, a := range rules.RectForbidden {
		forbiddenRect[a] = true
	}
	named := map[string]bool{}
	for _, c := range rules.NamedColors {
		named[strings.ToLower(c)] = true
	}

	for _, e := range entries {
		name := e.Name()
		if e.IsDir() || !strings.HasSuffix(name, ".svg") {
			continue
		}
		id := strings.TrimSuffix(name, ".svg")
		ids = append(ids, id)
		b, rerr := os.ReadFile(filepath.Join(rules.AssetsDir, name))
		if rerr != nil {
			fail("%s: 读取失败：%v", id, rerr)
			continue
		}
		svgBytes[id] = b
		text := string(b)

		if !idRe.MatchString(id) {
			fail("%s: id 命名不合法（应 kebab-case，小写字母开头）", id)
		}
		m := svgOpenRe.FindStringSubmatch(text)
		if m == nil {
			fail("%s: 找不到 <svg> 根标签", id)
			continue
		}
		attrs := map[string]string{}
		for _, am := range attrRe.FindAllStringSubmatch(m[1], -1) {
			attrs[am[1]] = am[2]
		}
		for k, want := range rules.SvgAttrs {
			if attrs[k] != want {
				fail("%s: 属性 %s=%q，契约要求 %q", id, k, attrs[k], want)
			}
		}

		if rules.ForbidColorLiteral && colorLiteralRe.MatchString(text) {
			fail("%s: 出现具体色值（契约只允许 currentColor 占位）", id)
		}
		if rules.ForbidNamedColor {
			for k, v := range attrs {
				if (k == "stroke" || k == "fill") && named[strings.ToLower(v)] {
					fail("%s: 出现具名色 %s=%q", id, k, v)
				}
			}
		}
		for _, em := range elemRe.FindAllStringSubmatch(text, -1) {
			tag := em[1]
			if !allowed[tag] {
				fail("%s: 图元白名单外的 <%s>", id, tag)
			}
		}
		for _, rm := range regexp.MustCompile(`<rect\b[^>]*>`).FindAllString(text, -1) {
			ra := map[string]string{}
			for _, am := range attrRe.FindAllStringSubmatch(rm, -1) {
				ra[am[1]] = am[2]
			}
			for _, fa := range rules.RectForbidden {
				if _, has := ra[fa]; has {
					fail("%s: <rect> 带 %s（带 rx 的圆角矩形必须手写为 path）", id, fa)
				}
			}
		}
		if rules.ForbidZeroLengthSubpath && zeroLenSubRe.MatchString(text) {
			fail("%s: 零长度子路径（禁靠 round cap 画点，跨端会消失）", id)
		}
		if rules.ForbidAriaHidden && strings.Contains(text, "aria-hidden") {
			fail("%s: 资产不得写死 aria-hidden（会废掉 <title>，由消费方按场景注入）", id)
		}
		title := ""
		if rules.RequireTitle {
			tm := titleRe.FindStringSubmatch(text)
			if tm == nil {
				fail("%s: 缺 <title>", id)
			} else {
				title = strings.TrimSpace(tm[1])
			}
		}
		if rules.RequireDesc {
			dm := descRe.FindStringSubmatch(text)
			if dm == nil {
				fail("%s: 缺 <desc>", id)
			} else if strings.TrimSpace(dm[1]) != id {
				fail("%s: <desc>=%q 必须等于 id（双向自证）", id, strings.TrimSpace(dm[1]))
			}
		}
		svgTitles[id] = title
	}
	sort.Strings(ids)
	pass("资产契约：%d 个 svg 逐个校验（属性 / 色值 / 图元白名单 / title+desc 自证）", len(ids))

	// 2) index.tsv 校验
	tRows, terr := readTsv(rules.IndexTsv, rules.TsvColumns)
	if terr != nil {
		fail("index.tsv: %v", terr)
	} else {
		tsvIDs := map[string]bool{}
		emojiSeen := map[string]string{}
		for _, r := range tRows {
			id, cat, scope, emo, desc := r.cols[0], r.cols[1], r.cols[2], r.cols[3], r.cols[4]
			if tsvIDs[id] {
				fail("index.tsv: id 重复 %q", id)
			}
			tsvIDs[id] = true
			if !contains(rules.Categories, cat) {
				fail("index.tsv: %s 的 category=%q 越界", id, cat)
			}
			if !contains(rules.Scopes, scope) {
				fail("index.tsv: %s 的 scope=%q 越界", id, scope)
			}
			if contains(rules.EmojiRequiredScopes, scope) {
				if strings.TrimSpace(emo) == "" {
					fail("index.tsv: %s 的 scope=%s 必须有 emoji 兼容别名", id, scope)
				} else if rules.EmojiMustBeUnique {
					if prev, dup := emojiSeen[emo]; dup {
						fail("index.tsv: emoji %q 重复（%s 与 %s）", emo, prev, id)
					} else {
						emojiSeen[emo] = id
					}
				}
			}
			if title, ok := svgTitles[id]; ok && title != strings.TrimSpace(desc) {
				fail("index.tsv: %s 的 desc=%q 与 svg <title>=%q 不一致", id, strings.TrimSpace(desc), title)
			}
		}
		pass("清单值域：%d 行（category / scope / emoji 兼容别名 / desc 与 title 一致）", len(tRows))

		// 3) 双向对账
		for _, id := range ids {
			if !tsvIDs[id] {
				fail("孤儿资产 %s.svg：index.tsv 无此 id", id)
			}
		}
		for _, r := range tRows {
			if _, ok := svgBytes[r.cols[0]]; !ok {
				fail("缺资产 %s.svg：index.tsv 有此 id", r.cols[0])
			}
		}
		pass("双向对账：孤儿 0 / 缺件 0")
	}

	// 4) 几何层 digest 同步
	if rules.GeometryJSON != "" {
		gb, gerr := os.ReadFile(rules.GeometryJSON)
		if gerr != nil {
			fail("几何层缺失 %s：%v（跑 go run ./scripts/gen_icons 生成）", rules.GeometryJSON, gerr)
		} else {
			var geo struct {
				Digest string `json:"digest"`
			}
			if jerr := json.Unmarshal(gb, &geo); jerr != nil {
				fail("几何层 %s 解析失败：%v", rules.GeometryJSON, jerr)
			} else if geo.Digest != digestOf(ids, svgBytes) {
				fail("几何层 digest 过期：文件=%s 现算=%s（跑 gen_icons 同步）", geo.Digest, digestOf(ids, svgBytes))
			} else {
				pass("几何层 digest 同步：%s", geo.Digest[:min(23, len(geo.Digest))])
			}
		}
	}

	if *verbose {
		for _, p := range passes {
			fmt.Println("  ok  " + p)
		}
	}
	if len(errs) > 0 {
		sort.Strings(errs)
		fmt.Fprintf(os.Stderr, "FAIL（%d 项）：\n", len(errs))
		for _, e := range errs {
			fmt.Fprintf(os.Stderr, "  - %s\n", e)
		}
		os.Exit(1)
	}
	fmt.Printf("OK：%d 个图标，契约全绿\n", len(ids))
}

var svgTitles = map[string]string{}

func contains(list []string, v string) bool {
	for _, x := range list {
		if x == v {
			return true
		}
	}
	return false
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func digestOf(ids []string, svgBytes map[string][]byte) string {
	h := sha256.New()
	for _, id := range ids {
		h.Write([]byte(id))
		h.Write([]byte{0})
		h.Write(svgBytes[id])
		h.Write([]byte{0})
	}
	return "sha256:" + hex.EncodeToString(h.Sum(nil))
}

func readTsv(path string, cols []string) ([]tsvRow, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("读取失败 %v", err)
	}
	if strings.Contains(string(b), "\r\n") {
		return nil, fmt.Errorf("含 CRLF 行尾（须在 .gitattributes 锁 text eol=lf）")
	}
	lines := strings.Split(strings.TrimRight(string(b), "\n"), "\n")
	if len(lines) == 0 {
		return nil, fmt.Errorf("空文件")
	}
	if !equalCols(strings.Split(lines[0], "\t"), cols) {
		return nil, fmt.Errorf("表头不符：%v（契约 %v）", strings.Split(lines[0], "\t"), cols)
	}
	out := []tsvRow{}
	for i, ln := range lines[1:] {
		if strings.TrimSpace(ln) == "" {
			continue
		}
		cs := strings.Split(ln, "\t")
		if len(cs) != len(cols) {
			return nil, fmt.Errorf("第 %d 行列数=%d（应 %d）：%s", i+2, len(cs), len(cols), ln)
		}
		out = append(out, tsvRow{cols: cs})
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("无数据行")
	}
	return out, nil
}

func equalCols(got, want []string) bool {
	if len(got) != len(want) {
		return false
	}
	for i := range got {
		if got[i] != want[i] {
			return false
		}
	}
	return true
}
