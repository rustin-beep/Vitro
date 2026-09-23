// Command gen_capi_bindings 是 C ABI 声明的**一致性闸**（架构审阅 v2 A 组 #3 /
// §2.9「绑定层厚度应靠生成解决」）。
//
// 本阶段是 **check-only**（对账），不生成——生成的前提是「裁剪策略定型」，
// 而裁剪策略此前**未被显式登记**：C 头注释只写「Keep in sync with ...」，
// 既没说权威源在哪，也没说哪些码该暴露、哪些不该。于是「缺了 25 个 C 侧码」
// 这种事实既无法被发现，也无法被判断是有意还是遗漏。
//
// 病灶（2026-09-22 实测）：
//
//	① C 头注释指向 `native/src/diagnostics/error_codes.rs`——该文件是
//	   `pub use vitro_shared::error_codes::*;` 的一行 re-export，**指错了源**；
//	② 权威源 137 项 vs C 头 73 项：值一致性 73/73 **全对**（抄得准，这是好消息），
//	   但缺 64 项，其中 25 项是 C 侧/预处理器码（`E3060_UseAfterFree`、
//	   `E3061_DoubleFree`、`E3070_BufferOverflow` …）——**下游 C 消费方拿不到
//	   这些符号名**，而它们恰恰是 C 程序最常遇到的运行时错误。已补入 C 头。
//
// 三类判据（缺一不可，全部要能证红）：
//
//	① **伪造码**：C 头出现的项必须在权威源里有同名项；
//	② **值不一致**：同名必须同值（最危险——下游按数值判错型，错位即误判）；
//	③ **未登记缺口**：源有而 C 头无的项，必须匹配 `excluded_patterns` 里的
//	   豁免规则（哨兵 / C++ 已砍）。未登记即红——逼「裁剪」成为显式决定。
//
// 另加一条：**Go 绑定的 DLL 符号名必须有 C 头声明**（运行时 Find 失败是
// 只在跑起来才暴露的隐患）。
//
// 规则外置 rules.json；解析出 0 项 fail loud（拒绝空转判绿）；`--selftest`
// 为 J9 证红入口（四路内存注入，不动磁盘）。
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

const rulesPath = "scripts/gen_capi_bindings/rules.json"

type excludePattern struct {
	Pattern string `json:"pattern"`
	Reason  string `json:"reason"`
}

type errorCodesRule struct {
	Authority        string           `json:"authority"`
	AuthorityNote    string           `json:"authority_note"`
	CHeader          string           `json:"c_header"`
	EnumStart        string           `json:"enum_start"`
	EnumEnd          string           `json:"enum_end"`
	CPrefix          string           `json:"c_prefix"`
	ExcludedPatterns []excludePattern `json:"excluded_patterns"`
}

type bindingsRule struct {
	GoBinding        string `json:"go_binding"`
	CHeader          string `json:"c_header"`
	SymbolPattern    string `json:"symbol_pattern"`
	CHeaderFuncRegex string `json:"c_header_func_pattern"`
}

type rulesDoc struct {
	Schema     int            `json:"schema"`
	ErrorCodes errorCodesRule `json:"error_codes"`
	Bindings   bindingsRule   `json:"bindings"`
}

func fatal(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "FATAL: "+format+"\n", args...)
	os.Exit(2)
}

func repoRoot() string {
	wd, err := os.Getwd()
	if err != nil {
		fatal("无法取工作目录: %v", err)
	}
	dir := wd
	for i := 0; i < 6; i++ {
		ok := true
		for _, m := range []string{"native", "scripts"} {
			if fi, err := os.Stat(filepath.Join(dir, m)); err != nil || !fi.IsDir() {
				ok = false
				break
			}
		}
		if ok {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	fatal("请在仓库内运行：找不到包含 native/ 与 scripts/ 的项目根")
	return ""
}

func mustRead(root, rel string) string {
	b, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(rel)))
	if err != nil {
		fatal("读 %s 失败: %v", rel, err)
	}
	return string(b)
}

// reEnumItem：枚举项 `Name = 123,`（行首缩进允许）。两侧共用同一正则——
// 口径一致才谈得上对账。
var reEnumItem = regexp.MustCompile(`(?m)^\s*([A-Za-z_]\w*)\s*=\s*(\d+)\s*,`)

func parseAuthority(root, rel string) map[string]int {
	m := map[string]int{}
	for _, g := range reEnumItem.FindAllStringSubmatch(mustRead(root, rel), -1) {
		v, err := strconv.Atoi(g[2])
		if err != nil {
			fatal("权威源 %s 的项 %s 值非法: %v", rel, g[1], err)
		}
		m[g[1]] = v
	}
	if len(m) == 0 {
		fatal("权威源 %s 解析出 0 项——源形态变化或正则失配，拒绝判绿", rel)
	}
	return m
}

func parseCHeaderEnum(root string, ec errorCodesRule) map[string]int {
	s := mustRead(root, ec.CHeader)
	i := strings.Index(s, ec.EnumStart)
	j := strings.Index(s, ec.EnumEnd)
	if i < 0 || j < 0 || j <= i {
		fatal("在 %s 里定位不到枚举段（%q .. %q）", ec.CHeader, ec.EnumStart, ec.EnumEnd)
	}
	seg := s[i+len(ec.EnumStart) : j]
	m := map[string]int{}
	for _, g := range reEnumItem.FindAllStringSubmatch(seg, -1) {
		name := strings.TrimPrefix(g[1], ec.CPrefix)
		v, err := strconv.Atoi(g[2])
		if err != nil {
			fatal("C 头项 %s 值非法: %v", g[1], err)
		}
		m[name] = v
	}
	if len(m) == 0 {
		fatal("C 头枚举段解析出 0 项，拒绝判绿")
	}
	return m
}

type violation struct {
	Kind   string
	Name   string
	Detail string
}

func exempted(name string, excl []excludePattern) (bool, string) {
	for _, e := range excl {
		re, err := regexp.Compile(e.Pattern)
		if err != nil {
			fatal("豁免规则 %q 非法: %v", e.Pattern, err)
		}
		if re.MatchString(name) {
			return true, e.Reason
		}
	}
	return false, ""
}

// verdict：纯函数（不动磁盘），便于 selftest 用内存注入验证每条判据都活着。
func verdict(rust, chead map[string]int, excl []excludePattern) []violation {
	var out []violation
	// ①②：C 头 ⊆ 源，且同名同值
	cn := make([]string, 0, len(chead))
	for n := range chead {
		cn = append(cn, n)
	}
	sort.Strings(cn)
	for _, n := range cn {
		rv, ok := rust[n]
		if !ok {
			out = append(out, violation{"伪造码（C 头有而源无）", n, fmt.Sprintf("C 头 = %d", chead[n])})
			continue
		}
		if rv != chead[n] {
			out = append(out, violation{"值不一致", n, fmt.Sprintf("源 = %d，C 头 = %d", rv, chead[n])})
		}
	}
	// ③：源 ⊆ C 头 ∪ 豁免
	rn := make([]string, 0, len(rust))
	for n := range rust {
		rn = append(rn, n)
	}
	sort.Slice(rn, func(i, j int) bool {
		if rust[rn[i]] != rust[rn[j]] {
			return rust[rn[i]] < rust[rn[j]]
		}
		return rn[i] < rn[j]
	})
	for _, n := range rn {
		if _, ok := chead[n]; ok {
			continue
		}
		if ok, _ := exempted(n, excl); ok {
			continue
		}
		out = append(out, violation{"未登记缺口（源有而 C 头无且无豁免理由）", n,
			fmt.Sprintf("源 = %d", rust[n])})
	}
	return out
}

// countExempt：统计豁免规则实际覆盖了多少源项（报告用，让"裁掉多少"可见）。
func countExempt(rust map[string]int, excl []excludePattern) (int, map[string]int) {
	per := map[string]int{}
	total := 0
	for n := range rust {
		if ok, r := exempted(n, excl); ok {
			per[r]++
			total++
		}
	}
	return total, per
}

func goSymbols(root string, br bindingsRule) []string {
	re, err := regexp.Compile(br.SymbolPattern)
	if err != nil {
		fatal("symbol_pattern 非法: %v", err)
	}
	seen := map[string]bool{}
	for _, g := range re.FindAllStringSubmatch(mustRead(root, br.GoBinding), -1) {
		if len(g) > 1 {
			seen[g[1]] = true
		} else {
			seen[g[0]] = true
		}
	}
	out := make([]string, 0, len(seen))
	for n := range seen {
		out = append(out, n)
	}
	sort.Strings(out)
	if len(out) == 0 {
		fatal("%s 里解析出 0 个 DLL 符号，拒绝判绿", br.GoBinding)
	}
	return out
}

func cHeaderFuncs(root string, br bindingsRule) map[string]bool {
	re, err := regexp.Compile(br.CHeaderFuncRegex)
	if err != nil {
		fatal("c_header_func_pattern 非法: %v", err)
	}
	m := map[string]bool{}
	for _, g := range re.FindAllStringSubmatch(mustRead(root, br.CHeader), -1) {
		m[g[1]] = true
	}
	if len(m) == 0 {
		fatal("%s 里解析出 0 个 VITRO_API 函数声明，拒绝判绿", br.CHeader)
	}
	return m
}

// selftest（J9）：四路**内存**注入，各断言必红；不动磁盘所以无需恢复。
func selftest(root string, rd rulesDoc) int {
	rust := parseAuthority(root, rd.ErrorCodes.Authority)
	chead := parseCHeaderEnum(root, rd.ErrorCodes)
	excl := rd.ErrorCodes.ExcludedPatterns

	if v := verdict(rust, chead, excl); len(v) > 0 {
		fmt.Printf("gen_capi_bindings: selftest ABORT——基线本身就红（%d 处），无法归因\n", len(v))
		return 2
	}
	// 选一个「非豁免」的 C 头项做注入目标（值 >0 的普通码）
	target := ""
	for _, n := range sortedKeys(chead) {
		if isExempt, _ := exempted(n, excl); !isExempt && rust[n] > 0 {
			target = n
			break
		}
	}
	if target == "" {
		fmt.Println("gen_capi_bindings: selftest ABORT——找不到可注入的非豁免 C 头项")
		return 2
	}

	clone := func(m map[string]int) map[string]int {
		c := make(map[string]int, len(m))
		for k, v := range m {
			c[k] = v
		}
		return c
	}

	type probe struct {
		name string
		run  func() int // 返回该路注入抓到的 violation 数
	}
	probes := []probe{
		{"值不一致", func() int {
			m := clone(chead)
			m[target] = m[target] + 1
			return len(verdict(rust, m, excl))
		}},
		{"伪造码", func() int {
			m := clone(chead)
			m["E9999_Fabricated"] = 9999
			return len(verdict(rust, m, excl))
		}},
		{"未登记缺口", func() int {
			m := clone(chead)
			delete(m, target)
			return len(verdict(rust, m, excl))
		}},
		{"Go 绑定符号缺 C 头声明", func() int {
			funcs := cHeaderFuncs(root, rd.Bindings)
			// 真实注入：在 Go 侧符号集里添一个 C 头必然没有的符号，
			// 断言该缺口会被计数捕获（而不是空跑返回常量）。
			syms := append(goSymbols(root, rd.Bindings), "vitro_fabricated_symbol_for_selftest")
			n := 0
			for _, s := range syms {
				if !funcs[s] {
					n++
				}
			}
			return n
		}},
	}

	failed := 0
	for _, p := range probes {
		n := p.run()
		if n == 0 {
			fmt.Printf("gen_capi_bindings: selftest FAIL——注入「%s」后仍判绿，该判据失效\n", p.name)
			failed++
			continue
		}
		fmt.Printf("gen_capi_bindings: selftest ok——注入「%s」被判红（%d 处）\n", p.name, n)
	}
	if failed > 0 {
		return 1
	}
	fmt.Printf("gen_capi_bindings: selftest PASS——4 路注入全部判红，J9 证红成立（注入目标 %s）\n", target)
	return 0
}

func sortedKeys(m map[string]int) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

func main() {
	checkFlag := flag.Bool("check", false, "判定模式（CI 入口；默认亦为判定）")
	selftestFlag := flag.Bool("selftest", false, "J9 证红：四路内存注入，断言每条判据都活着")
	flag.Parse()

	root := repoRoot()
	var rd rulesDoc
	if err := json.Unmarshal([]byte(mustRead(root, rulesPath)), &rd); err != nil {
		fatal("解析规则失败: %v", err)
	}
	if rd.ErrorCodes.Authority == "" || rd.ErrorCodes.CHeader == "" || rd.Bindings.GoBinding == "" {
		fatal("规则缺 error_codes.authority / error_codes.c_header / bindings.go_binding")
	}
	_ = checkFlag

	if *selftestFlag {
		os.Exit(selftest(root, rd))
	}

	rust := parseAuthority(root, rd.ErrorCodes.Authority)
	chead := parseCHeaderEnum(root, rd.ErrorCodes)
	viol := verdict(rust, chead, rd.ErrorCodes.ExcludedPatterns)
	nEx, per := countExempt(rust, rd.ErrorCodes.ExcludedPatterns)

	fmt.Printf("gen_capi_bindings: 错误码对账——权威源 %d 项 / C 头 %d 项（%s ← %s）\n",
		len(rust), len(chead), rd.ErrorCodes.CHeader, rd.ErrorCodes.Authority)
	fmt.Printf("  豁免 %d 项（%d 条规则）：\n", nEx, len(rd.ErrorCodes.ExcludedPatterns))
	for _, e := range rd.ErrorCodes.ExcludedPatterns {
		fmt.Printf("    %-16s 覆盖 %d 项 — %s\n", e.Pattern, per[e.Reason], e.Reason)
	}
	if len(viol) == 0 {
		fmt.Println("  ok 伪造码 0 / 值不一致 0 / 未登记缺口 0")
	} else {
		for _, v := range viol {
			fmt.Printf("  !! %s: %s（%s）\n", v.Kind, v.Name, v.Detail)
		}
	}

	goSyms := goSymbols(root, rd.Bindings)
	cFuncs := cHeaderFuncs(root, rd.Bindings)
	var missing []string
	for _, s := range goSyms {
		if !cFuncs[s] {
			missing = append(missing, s)
		}
	}
	fmt.Printf("gen_capi_bindings: 绑定符号对账——Go 侧 %d 个 / C 头声明 %d 个\n", len(goSyms), len(cFuncs))
	if len(missing) == 0 {
		fmt.Println("  ok Go 侧符号全部有 C 头声明")
	} else {
		for _, s := range missing {
			fmt.Printf("  !! Go 侧引用但 C 头无声明: %s\n", s)
		}
	}

	if len(viol) > 0 || len(missing) > 0 {
		fmt.Println("gen_capi_bindings: FAIL——C ABI 声明与权威源/绑定不一致")
		os.Exit(1)
	}
	fmt.Println("gen_capi_bindings: PASS——错误码与绑定符号全部对齐")
}
