// demo_ui_lint · 裸值棘轮（#222 P0 第三批，2026-10-21）
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

package main

import (
	"encoding/json"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

type rawEntry struct {
	File    string `json:"file"`
	Kind    string `json:"kind"` // color | font-px
	Literal string `json:"literal"`
	Count   int    `json:"count"`
}

type rawBaselineFile struct {
	Comment string     `json:"_comment"`
	Note    string     `json:"note"`
	Surface []string   `json:"surface"`
	Entries []rawEntry `json:"entries"`
}

var (
	reRawHex      = regexp.MustCompile(`#[0-9a-fA-F]{3,8}\b`)
	reRawFn       = regexp.MustCompile(`\b(rgba?|hsla?)\(`)
	reRawFontSize = regexp.MustCompile(`font-size\s*:\s*([^;{}]*)`)
	reRawPx       = regexp.MustCompile(`\d+(?:\.\d+)?px`)
	reStyleBlock  = regexp.MustCompile(`(?s)<style[^>]*>(.*?)</style>`)
)

func rawKey(e rawEntry) string { return e.File + "\x00" + e.Kind + "\x00" + e.Literal }

func aggregateRaw(in []rawEntry) []rawEntry {
	m := map[string]*rawEntry{}
	for _, e := range in {
		k := rawKey(e)
		if cur, ok := m[k]; ok {
			cur.Count += e.Count
			continue
		}
		cp := e
		m[k] = &cp
	}
	out := make([]rawEntry, 0, len(m))
	for _, e := range m {
		out = append(out, *e)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].File != out[j].File {
			return out[i].File < out[j].File
		}
		if out[i].Kind != out[j].Kind {
			return out[i].Kind < out[j].Kind
		}
		return out[i].Literal < out[j].Literal
	})
	return out
}

// collectRawLiterals 扫 demo/src 的 CSS 面（.css + .svelte <style>），跳过生成物。
func collectRawLiterals(demoDir string) ([]rawEntry, error) {
	var out []rawEntry
	root := filepath.Join(demoDir, "src")
	err := filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}
		name := d.Name()
		isCSS := strings.HasSuffix(name, ".css")
		isSvelte := strings.HasSuffix(name, ".svelte")
		if !isCSS && !isSvelte {
			return nil
		}
		b, err := os.ReadFile(p)
		if err != nil {
			return err
		}
		text := string(b)
		head := text
		if len(head) > 300 {
			head = head[:300]
		}
		if strings.Contains(head, "@generated") {
			return nil // 生成物：tokens.css 的色值本来就是裸值
		}
		if isSvelte {
			var sb strings.Builder
			for _, m := range reStyleBlock.FindAllStringSubmatch(text, -1) {
				sb.WriteString(m[1])
				sb.WriteString("\n")
			}
			text = sb.String()
		}
		text = reCSSComment.ReplaceAllString(text, "")
		rel := filepath.ToSlash(p)
		for _, m := range reRawHex.FindAllString(text, -1) {
			out = append(out, rawEntry{rel, "color", m, 1})
		}
		for _, m := range reRawFn.FindAllStringSubmatch(text, -1) {
			out = append(out, rawEntry{rel, "color", m[1] + "()", 1})
		}
		for _, m := range reRawFontSize.FindAllStringSubmatch(text, -1) {
			if v := reRawPx.FindString(m[1]); v != "" {
				out = append(out, rawEntry{rel, "font-px", v, 1})
			}
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return aggregateRaw(out), nil
}

func checkRaw(actual, baseline []rawEntry) []issue {
	var out []issue
	bm := map[string]rawEntry{}
	for _, e := range baseline {
		bm[rawKey(e)] = e
	}
	am := map[string]rawEntry{}
	for _, e := range actual {
		am[rawKey(e)] = e
	}
	for k, a := range am {
		b, ok := bm[k]
		if !ok {
			out = append(out, issue{"raw", fmt.Sprintf("新增裸值 %s（%s，%s）——改用 var(--vr-*) / --vr-fs 字号 token，或先把它加进 tokens.json", a.Literal, a.Kind, a.File)})
			continue
		}
		if a.Count > b.Count {
			out = append(out, issue{"raw", fmt.Sprintf("裸值用量增加 %s（%s，%d → %d 次）——棘轮只减不增", a.File, a.Literal, b.Count, a.Count)})
		}
	}
	for k, b := range bm {
		a, ok := am[k]
		if !ok {
			out = append(out, issue{"raw", fmt.Sprintf("僵尸基线 %s（%s，%s）已消失——跑 go run ./scripts/demo_ui_lint -update-raw 收窄", b.File, b.Kind, b.Literal)})
			continue
		}
		if a.Count < b.Count {
			out = append(out, issue{"raw", fmt.Sprintf("裸值用量减少 %s（%s，%d → %d 次）——僵尸基线，跑 -update-raw 收窄", b.File, b.Literal, b.Count, a.Count)})
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].msg < out[j].msg })
	return out
}

// selftestRaw：四路内存证红（同集绿 / 新色红 / 新字号红 / 僵尸红）+ 增量红。
func selftestRaw() error {
	base := []rawEntry{
		{"demo/src/a.css", "color", "#fff", 1},
		{"demo/src/a.css", "font-px", "12px", 2},
	}
	if got := checkRaw(base, base); len(got) != 0 {
		return fmt.Errorf("同集应绿，得到 %d 条：%v", len(got), got[0].msg)
	}
	cases := []struct {
		name string
		act  []rawEntry
	}{
		{"新增色值", append(append([]rawEntry{}, base...), rawEntry{"demo/src/a.css", "color", "#123456", 1})},
		{"新增字号", append(append([]rawEntry{}, base...), rawEntry{"demo/src/b.svelte", "font-px", "9.5px", 1})},
		{"用量增加", []rawEntry{
			{"demo/src/a.css", "color", "#fff", 1},
			{"demo/src/a.css", "font-px", "12px", 3},
		}},
		{"僵尸基线", []rawEntry{{"demo/src/a.css", "color", "#fff", 1}}},
	}
	for _, c := range cases {
		if got := checkRaw(c.act, base); len(got) == 0 {
			return fmt.Errorf("%s 未被判红——棘轮失效", c.name)
		}
	}
	return nil
}

func loadRawBaseline(path string) ([]rawEntry, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var f rawBaselineFile
	if err := json.Unmarshal(b, &f); err != nil {
		return nil, err
	}
	return f.Entries, nil
}

func writeRawBaseline(path string, entries []rawEntry) error {
	f := rawBaselineFile{
		Comment: "demo_ui_lint 裸值棘轮基线（#222 P0 第三批，2026-10-21）——只能收窄：清理存量后跑 -update-raw 重写；新增裸值/用量增加/僵尸条目一律红。",
		Note:    "判定面 = demo/src 的 .css 与 .svelte 的 <style> 块（跳过 @generated 生成物）；颜色 = hex/rgb()/rgba()/hsl()/hsla()，字号 = font-size 里的裸 px。",
		Surface: []string{"demo/src/**/*.css", "demo/src/**/*.svelte <style>"},
		Entries: entries,
	}
	b, err := json.MarshalIndent(f, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, append(b, '\n'), 0o644)
}

func countRawKind(entries []rawEntry, kind string) int {
	n := 0
	for _, e := range entries {
		if e.Kind == kind {
			n++
		}
	}
	return n
}
