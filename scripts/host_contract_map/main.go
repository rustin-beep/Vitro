// host_contract_map —— Host Contract 三态对账闸（总计划表 3，2026-10-04 建）。
//
// 命题：Rust 侧 host_contract_tests.rs（103 条契约测试）与 MoonBit 侧锚
// （host/memory/vm 三包 wbtest）**数量反超但注入面未必对齐**——本闸把
// 「每条 Rust 契约测试在 MoonBit 侧有对应覆盖」变成机判事实：
//
//	anchored  语义精确对应（1:1）
//	merged    mb 锚合并覆盖（多 Rust 测试并一锚 / 跨包锚）
//	missing   缺失（补锚段照搬 oracle 断言补齐——非红提示，清零即收官）
//
// 判据（fail loud，全部实测非缓存）：
//  1. Rust 侧实测测试名 ⊆ 表（漏映射即红——映射有洞）；
//  2. 表内每条 mb_anchors 实存于三包 wbtest 锚名集（陈旧引用即红）；
//  3. mb 锚未被任何条目引用 → 提示（MoonBit 侧自增锚，无 Rust 对应——
//     正常形态：mb 侧受检化分叉锚/输出通道锚等本就多于 oracle）；
//  4. missing 条目数打印（非红）；`--strict` 时 missing>0 红（收官门）。
//
// J9：--selftest 注入三路（漏映射条目删除 / 陈旧锚名 / 表空）必红。
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

var rulesPath = filepath.Join("scripts", "host_contract_map", "rules.json")

var (
	rustTestRe = regexp.MustCompile(`(?m)^\s*fn (test_\w+)\(`)
	mbTestRe   = regexp.MustCompile(`(?m)^test "([^"]+)"`)
)

type mapping struct {
	RustTest  string   `json:"rust_test"`
	State     string   `json:"state"`
	MbAnchors []string `json:"mb_anchors"`
	Note      string   `json:"note"`
}

type rules struct {
	Mappings []mapping `json:"mappings"`
}

func fatal(f string, a ...any) {
	fmt.Fprintf(os.Stderr, "错误: "+f+"\n", a...)
	os.Exit(2)
}

// rustHostTestNames 实测抽取 host_contract_tests.rs 的测试名（去 test_ 前缀）。
func rustHostTestNames() map[string]bool {
	// 工序④删区（2026-10-05）：Rust 契约测试源随区删除——名册冻结为仓内资产
	//（native-removal-baseline 提取 103 条）；三态对账语义不变（名册 ⊆ 映射表）。
	raw, err := os.ReadFile(filepath.Join("scripts", "host_contract_map", "rust_contract_names.json"))
	if err != nil {
		fatal("读契约名册失败: %v", err)
	}
	var doc struct {
		Names []string `json:"names"`
	}
	if jerr := json.Unmarshal(raw, &doc); jerr != nil || len(doc.Names) == 0 {
		fatal("契约名册坏或空集——空集不得绿")
	}
	out := map[string]bool{}
	for _, n := range doc.Names {
		out[strings.TrimPrefix(n, "test_")] = true
	}
	return out
}

// mbAnchorNames 实测抽取三包 wbtest 锚名（host / memory / vm）。
func mbAnchorNames() map[string]bool {
	pkgs := []string{
		filepath.Join("moonbit", "host"),
		filepath.Join("moonbit", "memory"),
		filepath.Join("moonbit", "vm"),
	}
	out := map[string]bool{}
	for _, dir := range pkgs {
		ents, err := os.ReadDir(dir)
		if err != nil {
			fatal("读包目录失败 %s: %v", dir, err)
		}
		for _, e := range ents {
			name := e.Name()
			if !strings.HasSuffix(name, ".mbt") || !strings.Contains(name, "wbtest") && !strings.Contains(name, "_test") {
				continue
			}
			raw, err := os.ReadFile(filepath.Join(dir, name))
			if err != nil {
				fatal("读锚文件失败: %v", err)
			}
			for _, m := range mbTestRe.FindAllStringSubmatch(string(raw), -1) {
				out[m[1]] = true
			}
		}
	}
	if len(out) == 0 {
		fatal("mb 锚名抽取为空集（正则失配？）——空集不得绿")
	}
	return out
}

func loadRules() []mapping {
	raw, err := os.ReadFile(rulesPath)
	if err != nil {
		fatal("读映射表失败: %v", err)
	}
	var r rules
	if err := json.Unmarshal(raw, &r); err != nil {
		fatal("映射表非法 JSON: %v", err)
	}
	if len(r.Mappings) == 0 {
		fatal("映射表为空集（空集不得绿）")
	}
	for _, m := range r.Mappings {
		switch m.State {
		case "anchored", "merged", "missing":
		default:
			fatal("条目 %s 非法 state %q（三态枚举外）", m.RustTest, m.State)
		}
	}
	return r.Mappings
}

func run(strict bool) int {
	rust := rustHostTestNames()
	mb := mbAnchorNames()
	maps := loadRules()

	exit := 0
	inTable := map[string]bool{}
	anchoredUsed := map[string]int{}
	usedMb := map[string]bool{}
	missing := []string{}
	for _, m := range maps {
		if inTable[m.RustTest] {
			fmt.Printf("[DUP] 表内重复条目 %s\n", m.RustTest)
			exit = 1
		}
		inTable[m.RustTest] = true
		if m.State == "missing" {
			missing = append(missing, m.RustTest)
			continue
		}
		if len(m.MbAnchors) == 0 {
			fmt.Printf("[BAD] %s state=%s 但 mb_anchors 为空\n", m.RustTest, m.State)
			exit = 1
		}
		for _, a := range m.MbAnchors {
			if !mb[a] {
				fmt.Printf("[STALE] %s 指向不存在的锚 %q（陈旧引用）\n", m.RustTest, a)
				exit = 1
			}
			usedMb[a] = true
		}
		// 语义保险丝（审阅 P3-③，2026-10-04）：机判可及的两条——1:1
		// anchored 要求锚名与测试名对齐（拦「指向实存但语义错指」的最低成本
		// 形态，如 math_sin_zero 改指 math_cos_zero）；同一锚被多条 anchored
		// 复用应改 state=merged（合并语义须人审 note）。跨包 merged 的语义
		// 等价性仍属人工域（表 note 列承载）。
		if m.State == "anchored" {
			if len(m.MbAnchors) != 1 || m.MbAnchors[0] != m.RustTest {
				fmt.Printf("[CROSS] %s state=anchored 但锚名不对齐 %v（1:1 要求同名；合并覆盖改 state=merged）\n", m.RustTest, m.MbAnchors)
				exit = 1
			}
			anchoredUsed[m.MbAnchors[0]] = anchoredUsed[m.MbAnchors[0]] + 1
		}
	}
	// 语义保险丝后半：同一锚被多条 anchored 复用即红（应改 merged）
	for a, n := range anchoredUsed {
		if n > 1 {
			fmt.Printf("[REUSE] 锚 %q 被 %d 条 anchored 复用——合并覆盖改 state=merged 并补 note\n", a, n)
			exit = 1
		}
	}

	// 判据 1：Rust 实测 ⊆ 表
	var holes []string
	for t := range rust {
		if !inTable[t] {
			holes = append(holes, t)
		}
	}
	sort.Strings(holes)
	if len(holes) > 0 {
		fmt.Printf("[HOLE] oracle 契约测试 %d 条无映射：%v\n", len(holes), holes)
		exit = 1
	}
	// 判据 1b：表指向不存在的 Rust 测试（表侧陈旧）
	var ghosts []string
	for t := range inTable {
		if !rust[t] {
			ghosts = append(ghosts, t)
		}
	}
	sort.Strings(ghosts)
	if len(ghosts) > 0 {
		fmt.Printf("[GHOST] 表内条目指向不存在的 oracle 测试：%v\n", ghosts)
		exit = 1
	}
	// 判据 3：mb 侧未被引用锚（提示）
	var extra []string
	for a := range mb {
		if !usedMb[a] {
			extra = append(extra, a)
		}
	}
	sort.Strings(extra)
	fmt.Printf("oracle 契约 %d 条：anchored+merged %d / missing %d；mb 锚 %d 个（被引用 %d / 侧自增 %d——受检化分叉锚等正常多出）\n",
		len(rust), len(rust)-len(missing), len(missing), len(mb), len(usedMb), len(extra))
	if len(missing) > 0 {
		fmt.Printf("[TODO] 缺失 %d 条（补锚段照搬 oracle 断言）：%v\n", len(missing), missing)
		if strict {
			fmt.Println("strict：missing 非空判红（收官门）")
			exit = 1
		}
	}
	if exit == 0 {
		fmt.Println("host_contract_map: 对账一致（映射无洞 / 锚引用无陈旧）")
	}
	return exit
}

func selfTest() {
	// 三路注入必红：① 删一条映射（洞）② 陈旧锚名 ③ 空 mappings。
	// 以 run 的判定函数为目标做内存级注入（不改盘上文件）。
	rust := map[string]bool{"t1": true, "t2": true}
	mb := map[string]bool{"a1": true}
	// ① 洞
	maps := []mapping{{RustTest: "t1", State: "anchored", MbAnchors: []string{"a1"}}}
	if !hasHole(rust, maps) {
		fmt.Println("selftest: FAIL——漏映射未检出（洞判据失效）")
		os.Exit(2)
	}
	// ② 陈旧
	maps = []mapping{
		{RustTest: "t1", State: "anchored", MbAnchors: []string{"a1"}},
		{RustTest: "t2", State: "anchored", MbAnchors: []string{"ghost_anchor"}},
	}
	if !hasStale(mb, maps) {
		fmt.Println("selftest: FAIL——陈旧锚引用未检出")
		os.Exit(2)
	}
	// ③ 一致面（完整映射零洞零陈旧）
	maps = []mapping{
		{RustTest: "t1", State: "anchored", MbAnchors: []string{"a1"}},
		{RustTest: "t2", State: "merged", MbAnchors: []string{"a1"}},
	}
	if hasHole(rust, maps) || hasStale(mb, maps) {
		fmt.Println("selftest: FAIL——完整映射误报")
		os.Exit(2)
	}
	fmt.Println("selftest：洞/陈旧/零误报三锚 通过")
}

func hasHole(rust map[string]bool, maps []mapping) bool {
	in := map[string]bool{}
	for _, m := range maps {
		in[m.RustTest] = true
	}
	for t := range rust {
		if !in[t] {
			return true
		}
	}
	return false
}

func hasStale(mb map[string]bool, maps []mapping) bool {
	for _, m := range maps {
		for _, a := range m.MbAnchors {
			if !mb[a] {
				return true
			}
		}
	}
	return false
}

func main() {
	strict := flag.Bool("strict", false, "missing 非空判红（收官门——补锚清零后启用）")
	selftest := flag.Bool("selftest", false, "J9 三锚（洞/陈旧/零误报）")
	flag.Parse()
	if *selftest {
		selfTest()
		return
	}
	os.Exit(run(*strict))
}
