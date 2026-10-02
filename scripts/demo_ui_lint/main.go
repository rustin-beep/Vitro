// Command demo_ui_lint 对 demo/ 静态三件套做字符串契约对账（防线维护批新增）。
//
// 动机（2026-10-02 demo UI 批实测三 bug 的归因）：三个实锤 bug 全部是
// **JS↔CSS 的字符串契约**或 CSS 本体问题——TS 类型系统一个都拦不住，对症
// 防线是文本对账闸：
//
//   A. CSS 变量：var(--x) 引用 ⊆ 定义（css 定义 ∪ JS/HTML setProperty）∪ 白名单
//      ——实锤先例：--fg-muted 引用不存在的变量，静默回退 inherit。
//   B. 类名：classList 写操作字面量对「元素候选类闭包 ∪ CSS 复合单元 ∪ JS
//      生成面 ∪ 白名单」对账。CSS 单元 = 复合选择器里同属一个元素的段
//      （.tab.active 的 {tab,active}）——单元必须整体落在元素候选类集内才
//      为该元素提供定义，专抓「操作了永不生效的类」形态（实锤先例：
//      $("stdin-row").classList.add("active") 只有 .tab.active 定义，
//      #stdin-row 永远没有 tab 类，行永不显示）。
//   C. getElementById 字面量 id ⊆ html id 集 ∪ 动态前缀白名单（防静默 null）。
//
// 规则外置 rules.json：动态 className 拼接簇（"pill " + kind 一类静态不可
// 提取的写操作，显式登记合法类集）、动态 id 前缀、显式白名单；**僵尸条目
// （登记的类/id 已无任何引用或定义）无条件红**。
//
// 判定型脚本纪律：Go 零第三方依赖、fail loud（exit 1 列出全部未命中）、
// -selftest 内存注入证红（不落盘）。
//
// 用法：go run ./scripts/demo_ui_lint [-demo demo] [-rules scripts/demo_ui_lint/rules.json]
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// ── 规则外置 ─────────────────────────────────────────────

type dynClassRule struct {
	Where   string   `json:"where"`   // 登记说明（哪处动态拼接）
	Classes []string `json:"classes"` // 该拼接可能产生的全部类名
}

type dynIDRule struct {
	Prefix string   `json:"prefix"` // $("tab-" + ...) 的字面量前缀
	IDs    []string `json:"ids"`    // 可能拼出的全部 id
}

type rules struct {
	DynamicClassAssigns []dynClassRule `json:"dynamic_class_assigns"`
	DynamicIDPrefixes   []dynIDRule    `json:"dynamic_id_prefixes"`
	ClassWhitelist      []string       `json:"class_whitelist"`
	VarWhitelist        []string       `json:"var_whitelist"`
}

// ── 提取器 ───────────────────────────────────────────────

var reCSSComment = regexp.MustCompile(`/\*[\s\S]*?\*/`)
var reCSSRule = regexp.MustCompile(`([^{}]+)\{`)
var reCSSCompound = regexp.MustCompile(`[#.][A-Za-z_][\w-]*`)
var reCSSVarDef = regexp.MustCompile(`(--[\w-]+)\s*:`)
var reCSSVarUse = regexp.MustCompile(`var\((--[\w-]+)`)

var reHTMLTag = regexp.MustCompile(`<([a-z]+)[^>]*>`)
var reAttrID = regexp.MustCompile(`\bid="([\w-]+)"`)
var reAttrClass = regexp.MustCompile(`\bclass="([^"]*)"`)

var reJSClassListChain = regexp.MustCompile(`(?:\$\(|getElementById\(|querySelector\()["']#?([\w-]+)["']\)\.classList\.(add|remove|toggle|contains)\(([^)]*)\)`)
var reJSVarBind = regexp.MustCompile(`(?:const|let|var)\s+(\w+)\s*=\s*(?:\$\(|getElementById\(|querySelector\()["']#?([\w-]+)["']\)`)
var reJSClassListVar = regexp.MustCompile(`(\w+)\.classList\.(add|remove|toggle|contains)\(([^)]*)\)`)
var reJSClassNameLit = regexp.MustCompile(`\.className\s*=\s*"([^"]*)"`)
var reJSGetByID = regexp.MustCompile(`(?:\$\(|getElementById\()["']([\w-]+)["']\)`)
var reJSGetByIDDyn = regexp.MustCompile(`(?:\$\(|getElementById\()["']([\w-]+)["']\s*\+`)
var reJSGenClass = regexp.MustCompile(`class=\\?"([^"\\$]+)\\?"`)
var reQuotedArgs = regexp.MustCompile(`"([^"]+)"`)
var reCSSVarUseNoFB = regexp.MustCompile(`var\((--[\w-]+)\s*\)`)
var reJSInlineStyleVar = regexp.MustCompile(`style=\\?"[^"\\$]*?(--[\w-]+)`)


// classListArgs 提取调用的类名实参：只认带引号的字面量串。
// toggle("empty", expr) 的第二参（布尔表达式）自然被排除；
// add("a", "b") 多类名照常展开；非字面量实参返回空（由调用方降级处理）。
func classListArgs(s string) []string {
	out := []string{}
	for _, m := range reQuotedArgs.FindAllStringSubmatch(s, -1) {
		out = append(out, m[1])
	}
	return out
}

type compoundUnit struct {
	id      string            // 复合段中的 #id（可空）
	classes map[string]bool   // 复合段中的类
	raw     string            // 原文（报错用）
}

// parseCSS 返回：复合单元全集、变量定义集。@media 头剥离后规则提取不受嵌套影响。
func parseCSS(text string) ([]compoundUnit, map[string]bool) {
	text = reCSSComment.ReplaceAllString(text, "")
	text = regexp.MustCompile(`@media[^{]*\{`).ReplaceAllString(text, "")
	units := []compoundUnit{}
	vars := map[string]bool{}
	for _, m := range reCSSRule.FindAllStringSubmatch(text, -1) {
		sel := strings.TrimSpace(m[1])
		if sel == "" || strings.HasPrefix(sel, "@") {
			continue
		}
		for _, one := range strings.Split(sel, ",") {
			u := compoundUnit{classes: map[string]bool{}, raw: strings.TrimSpace(one)}
			for _, tok := range reCSSCompound.FindAllString(one, -1) {
				if tok[0] == '#' {
					u.id = tok[1:]
				} else {
					u.classes[tok[1:]] = true
				}
			}
			if len(u.classes) > 0 || u.id != "" {
				units = append(units, u)
			}
		}
	}
	for _, m := range reCSSVarDef.FindAllStringSubmatch(text, -1) {
		vars[m[1]] = true
	}
	return units, vars
}

// ── 主逻辑 ───────────────────────────────────────────────

type issue struct {
	kind string
	msg  string
}

func main() {
	demoDir := flag.String("demo", "demo", "demo 目录")
	rulesPath := flag.String("rules", "scripts/demo_ui_lint/rules.json", "规则文件")
	selftest := flag.Bool("selftest", false, "内存注入三路证红后即退出（不读盘）")
	flag.Parse()

	var rl rules
	if *selftest {
		rl = selftestRules()
	} else {
		b, err := os.ReadFile(*rulesPath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "demo_ui_lint: 规则文件不可读: %v\n", err)
			os.Exit(2)
		}
		if err := json.Unmarshal(b, &rl); err != nil {
			fmt.Fprintf(os.Stderr, "demo_ui_lint: 规则文件坏 JSON: %v\n", err)
			os.Exit(2)
		}
	}

	read := func(name, src string) string {
		if *selftest {
			return src
		}
		b, err := os.ReadFile(filepath.Join(*demoDir, name))
		if err != nil {
			fmt.Fprintf(os.Stderr, "demo_ui_lint: %s 不可读: %v\n", name, err)
			os.Exit(2)
		}
		return string(b)
	}
	html := read("index.html", selftestHTML)
	css := read("style.css", selftestCSS)
	js := read("app.js", selftestJS)

	var issues []issue

	// ── 定义面收集 ──
	htmlIDs := map[string]bool{}
	htmlClassByID := map[string]map[string]bool{} // id → 静态类
	htmlClassAll := map[string]bool{}
	for _, tag := range reHTMLTag.FindAllString(html, -1) {
		idm := reAttrID.FindStringSubmatch(tag)
		clm := reAttrClass.FindStringSubmatch(tag)
		cls := map[string]bool{}
		if clm != nil {
			for _, c := range strings.Fields(clm[1]) {
				cls[c] = true
				htmlClassAll[c] = true
			}
		}
		if idm != nil {
			htmlIDs[idm[1]] = true
			htmlClassByID[idm[1]] = cls
		}
	}

	cssUnits, cssVarDefs := parseCSS(css)

	// html 元素的静态类集也构成复合单元（<button class="tab active"> 的
	// {tab,active} 与 css .tab.active 等价）——html 豁免不走全局集，
	// 走同一套单元判定，否则 active 类在 html 出现一次就全元素放行
	// （stdin-row 实锤漏报形态）。
	for _, tag := range reHTMLTag.FindAllString(html, -1) {
		idm := reAttrID.FindStringSubmatch(tag)
		clm := reAttrClass.FindStringSubmatch(tag)
		if clm == nil {
			continue
		}
		u := compoundUnit{classes: map[string]bool{}, raw: "html:" + tag}
		if idm != nil {
			u.id = idm[1]
		}
		for _, c := range strings.Fields(clm[1]) {
			u.classes[c] = true
		}
		cssUnits = append(cssUnits, u)
	}

	// JS 生成面：innerHTML/模板里的 class="..." + className 字面量 + classList 字面量
	jsGenClasses := map[string]bool{}
	for _, m := range reJSGenClass.FindAllStringSubmatch(js, -1) {
		for _, c := range strings.Fields(m[1]) {
			jsGenClasses[c] = true
		}
	}

	// 变量绑定：const el = $("id")。同名变量绑定到多个不同 id 时视为歧义
	// （JS 无块级作用域分析，forEach 参数遮蔽等形态不可靠）——不锚定，走降级全局检查。
	varBind := map[string]string{}
	varAmbiguous := map[string]bool{}
	{
		binds := map[string]map[string]bool{}
		for _, m := range reJSVarBind.FindAllStringSubmatch(js, -1) {
			if binds[m[1]] == nil {
				binds[m[1]] = map[string]bool{}
			}
			binds[m[1]][m[2]] = true
		}
		for name, ids := range binds {
			if len(ids) == 1 {
				for id := range ids {
					varBind[name] = id
				}
			} else {
				varAmbiguous[name] = true
			}
		}
	}

	// 元素候选类闭包：静态类 ∪ 该元素全部 classList add/remove/toggle 字面量 ∪ className 字面量 ∪ 动态簇
	candidate := func(id string) map[string]bool {
		set := map[string]bool{}
		for c := range htmlClassByID[id] {
			set[c] = true
		}
		for _, m := range reJSClassListChain.FindAllStringSubmatch(js, -1) {
			if m[1] == id && m[2] != "contains" {
				for _, c := range classListArgs(m[3]) {
					set[c] = true
				}
			}
		}
		for _, m := range reJSClassListVar.FindAllStringSubmatch(js, -1) {
			if varBind[m[1]] == id && m[2] != "contains" {
				for _, c := range classListArgs(m[3]) {
					set[c] = true
				}
			}
		}
		for _, m := range reJSClassNameLit.FindAllStringSubmatch(js, -1) {
			_ = m // className 整体赋值不并入候选（覆盖语义），仅进生成面
		}
		for _, r := range rl.DynamicClassAssigns {
			for _, c := range r.Classes {
				set[c] = true
			}
		}
		return set
	}

	// ── 检查 B：classList 写操作类名对账 ──
	checkClassWrite := func(anchorID, kind, args, at string) {
		if kind == "contains" {
			return // 读操作保守不查（恒 false 也算 bug，但避免误报面扩大）
		}
		for _, c := range classListArgs(args) {
			if !validClass(c, anchorID, candidate, cssUnits, jsGenClasses, htmlClassAll, rl) {
				issues = append(issues, issue{"class", fmt.Sprintf("%s: %s 类名 %q 对元素 #%s 永不生效（无匹配 CSS 单元/生成面/白名单）", at, kind, c, anchorID)})
			}
		}
	}

	for _, m := range reJSClassListChain.FindAllStringSubmatch(js, -1) {
		checkClassWrite(m[1], m[2], m[3], "app.js classList")
	}
	for _, m := range reJSClassListVar.FindAllStringSubmatch(js, -1) {
		if id, ok := varBind[m[1]]; ok && !varAmbiguous[m[1]] {
			checkClassWrite(id, m[2], m[3], "app.js classList")
		}
		// 未锚定/歧义绑定的调用（querySelector 结果、forEach 参数遮蔽等）降级：
		// 类名须全局有定义
		if _, ok := varBind[m[1]]; !ok || varAmbiguous[m[1]] {
			if m[2] != "contains" {
				for _, c := range classListArgs(m[3]) {
					if !classKnownAnywhere(c, cssUnits, jsGenClasses, htmlClassAll, rl) {
						issues = append(issues, issue{"class", fmt.Sprintf("app.js classList: 类名 %q 全库无定义（未锚定元素，降级全局检查）", c)})
					}
				}
			}
		}
	}

	// ── 检查 A：CSS 变量对账 ──
	// 定义面 = css --x: 定义 ∪ JS/HTML setProperty ∪ JS innerHTML 内联 style="--x:…"
	// ∪ 白名单。带回退值的 var(--x, fb) 引用按 CSS 语义跳过（未定义时回退兜底，
	// 不是契约破坏——--fg-muted 实锤形态是无回退引用）。
	varDefs := map[string]bool{}
	for v := range cssVarDefs {
		varDefs[v] = true
	}
	for _, m := range regexp.MustCompile(`setProperty\(\s*"([\w-]+)"`).FindAllStringSubmatch(js, -1) {
		varDefs[m[1]] = true
	}
	for _, m := range regexp.MustCompile(`setProperty\(\s*"([\w-]+)"`).FindAllStringSubmatch(html, -1) {
		varDefs[m[1]] = true
	}
	for _, m := range reJSInlineStyleVar.FindAllStringSubmatch(js, -1) {
		varDefs[m[1]] = true
	}
	for _, w := range rl.VarWhitelist {
		varDefs[w] = true
	}
	varWithFallback := map[string]bool{}
	for _, m := range regexp.MustCompile(`var\(([\w-]+)\s*,`).FindAllStringSubmatch(css, -1) {
		varWithFallback[m[1]] = true
	}
	checkVars := func(text, file string) {
		for _, m := range reCSSVarUse.FindAllStringSubmatch(text, -1) {
			if varWithFallback[m[1]] {
				continue // 带回退值，未定义也不破坏渲染
			}
			if !varDefs[m[1]] {
				issues = append(issues, issue{"var", fmt.Sprintf("%s: var(%s) 引用未定义变量", file, m[1])})
			}
		}
	}
	checkVars(css, "style.css")
	checkVars(js, "app.js")
	checkVars(html, "index.html")

	// ── 检查 C：getElementById 字面量 id 对账 ──
	dynIDs := map[string]bool{}
	for _, r := range rl.DynamicIDPrefixes {
		for _, id := range r.IDs {
			dynIDs[id] = true
		}
	}
	for _, m := range reJSGetByID.FindAllStringSubmatch(js, -1) {
		id := m[1]
		if !htmlIDs[id] && !dynIDs[id] {
			issues = append(issues, issue{"id", fmt.Sprintf("app.js: $(%q) 在 index.html 无此 id", id)})
		}
	}
	for _, m := range reJSGetByIDDyn.FindAllStringSubmatch(js, -1) {
		prefix := m[1]
		covered := false
		for _, r := range rl.DynamicIDPrefixes {
			if r.Prefix == prefix {
				covered = true
			}
		}
		if !covered {
			issues = append(issues, issue{"id", fmt.Sprintf("app.js: 动态 id 前缀 %q+ 未在 rules.json 登记", prefix)})
		}
	}

	// ── 僵尸条目：白名单/动态簇登记的类与 id 必须仍有真实引用或定义 ──
	allClassNames := map[string]bool{}
	for c := range htmlClassAll {
		allClassNames[c] = true
	}
	for _, u := range cssUnits {
		for c := range u.classes {
			allClassNames[c] = true
		}
	}
	for c := range jsGenClasses {
		allClassNames[c] = true
	}
	for _, m := range reJSClassListChain.FindAllStringSubmatch(js, -1) {
		for _, c := range classListArgs(m[3]) {
			allClassNames[c] = true
		}
	}
	for _, r := range rl.DynamicClassAssigns {
		for _, c := range r.Classes {
			if !allClassNames[c] {
				issues = append(issues, issue{"zombie", fmt.Sprintf("rules.json: dynamic_class_assigns(%s) 登记的类 %q 全库无引用无定义（僵尸条目）", r.Where, c)})
			}
		}
	}
	for _, w := range rl.ClassWhitelist {
		if !allClassNames[w] {
			issues = append(issues, issue{"zombie", fmt.Sprintf("rules.json: class_whitelist 登记的 %q 全库无引用无定义（僵尸条目）", w)})
		}
	}
	for _, r := range rl.DynamicIDPrefixes {
		for _, id := range r.IDs {
			if !htmlIDs[id] {
				issues = append(issues, issue{"zombie", fmt.Sprintf("rules.json: dynamic_id_prefixes(%s) 登记的 id %q 在 index.html 不存在（僵尸条目）", r.Prefix, id)})
			}
		}
	}

	// ── selftest 预期三路红 ──
	if *selftest {
		kinds := map[string]int{}
		for _, i := range issues {
			kinds[i.kind]++
		}
		if kinds["class"] < 1 || kinds["var"] < 1 || kinds["zombie"] < 1 {
			fmt.Fprintf(os.Stderr, "demo_ui_lint: -selftest 未达到三路证红（class=%d var=%d zombie=%d）——闸失效\n", kinds["class"], kinds["var"], kinds["zombie"])
			os.Exit(1)
		}
		fmt.Printf("demo_ui_lint: -selftest 三路证红 OK（class=%d var=%d zombie=%d id=%d）\n", kinds["class"], kinds["var"], kinds["zombie"], kinds["id"])
		return
	}

	if len(issues) > 0 {
		sort.Slice(issues, func(i, j int) bool { return issues[i].kind < issues[j].kind })
		for _, i := range issues {
			fmt.Fprintf(os.Stderr, "[demo_ui_lint][%s] %s\n", i.kind, i.msg)
		}
		fmt.Fprintf(os.Stderr, "demo_ui_lint: %d 条未命中——字符串契约对账红\n", len(issues))
		os.Exit(1)
	}
	fmt.Println("demo_ui_lint: 类名/CSS 变量/id 三路对账全部通过")
}

func validClass(c, anchorID string, candidate func(string) map[string]bool, units []compoundUnit, gen, htmlAll map[string]bool, rl rules) bool {
	if gen[c] {
		return true // JS 模板自产自销
	}
	for _, w := range rl.ClassWhitelist {
		if w == c {
			return true
		}
	}
	cand := candidate(anchorID)
	for _, u := range units {
		if _, has := u.classes[c]; !has {
			continue
		}
		// 单类单元（.muted 这类全局工具类）对任何元素合法；
		// 多类复合单元必须整体落在元素候选闭包内（.tab.active 对无 tab 类的元素不生效）
		if len(u.classes) == 1 && u.id == "" {
			return true
		}
		if unitValidFor(u, cand, anchorID) {
			return true
		}
	}
	return false
}

// 单元对锚点元素有效：单元 #id 匹配（或无 id）且全部类 ⊆ 元素候选类闭包
func unitValidFor(u compoundUnit, cand map[string]bool, id string) bool {
	if u.id != "" && u.id != id {
		return false
	}
	for c := range u.classes {
		if !cand[c] {
			return false
		}
	}
	return true
}

func classKnownAnywhere(c string, units []compoundUnit, gen, htmlAll map[string]bool, rl rules) bool {
	if gen[c] || htmlAll[c] {
		return true
	}
	for _, w := range rl.ClassWhitelist {
		if w == c {
			return true
		}
	}
	for _, u := range units {
		if _, has := u.classes[c]; has {
			return true
		}
	}
	return false
}

// ── -selftest 注入源（三路各埋一雷）────────────────────────

func selftestRules() rules {
	return rules{
		DynamicClassAssigns: []dynClassRule{{Where: "st", Classes: []string{"ghost-class"}}},
		DynamicIDPrefixes:   []dynIDRule{{Prefix: "tab-", IDs: []string{"tab-result"}}},
	}
}

const selftestHTML = `<div id="box" class="tab"></div><div id="tab-result"></div>`
const selftestCSS = `:root { --real: 1px; } .tab.on { color: red; }`
const selftestJS = `$("box").classList.add("phantom-class");
document.getElementById("no-such-id").onclick = null;
const v = "var(--no-such-var)";`
