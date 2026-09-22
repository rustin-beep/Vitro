// pkg_deps：MoonBit 包依赖方向断言（S5 收尾批 · 架构审阅 v2 A 组 #6）。
//
// 总计划 §4 的硬约束是「依赖严格单向无环」，并按 L0–L9 分层给出包图——
// 但此前**零 CI 校验**：越层或成环的依赖可以静默进来（口头纪律，不是
// 机判）。本闸把它变成红线。
//
// 用法（**仓库根**）：
//
//	go run ./scripts/moonbit/pkg_deps            # 分层与依赖报告 + 判定
//	go run ./scripts/moonbit/pkg_deps -check     # 判定（CI 门禁用）
//	go run ./scripts/moonbit/pkg_deps --selftest # J9：注入越层边必红
//
// 判据（分层表见 rules.json，源 = 总计划 §4）：
//
//	① 每个包必须能匹配到层号（新包未登记 → 红，fail loud；禁止静默放行）
//	② 任一模块内依赖 D 满足 level(D) <= level(P)（同层允许，向上越层即红）
//	③ 跨包依赖图无环（DFS 回边即红）
//	④ 空集不得绿：解析出 0 个包或 0 条依赖 → 红（防"扫描失效→全绿"）
//
// cmd/* 为差分工具层，豁免方向检查（仍参与环检测）。
// 外部分依赖（moonbitlang/*）不参与判定。
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

const rulesPath = "scripts/moonbit/pkg_deps/rules.json"

type rulesDoc struct {
	Schema         int            `json:"schema"`
	Root           string         `json:"root"`
	Module         string         `json:"module"`
	Levels         map[string]int `json:"levels"`
	ExemptPrefixes []string       `json:"exempt_prefixes"`
}

var (
	reImportBlock = regexp.MustCompile(`(?s)import\s*\{(.*?)\}`)
	reQuoted      = regexp.MustCompile(`"([^"]+)"`)
)

// pkgInfo：一个包的依赖声明。
type pkgInfo struct {
	name         string // 相对 root，如 "lexer/internal/pp"
	deps         []string
	level        int
	levelKey     string
	exempt       bool
	testDepsSeen bool
}

func main() {
	selftest, check := false, false
	for _, a := range os.Args[1:] {
		switch a {
		case "--selftest":
			selftest = true
		case "-check":
			check = true
		default:
			fatal("未知参数: %s（可用：-check / --selftest）", a)
		}
	}

	raw, err := os.ReadFile(rulesPath)
	if err != nil {
		fatal("读规则失败（须在仓库根运行）: %v", err)
	}
	var rd rulesDoc
	if err := json.Unmarshal(raw, &rd); err != nil {
		fatal("规则解析失败: %v", err)
	}
	if rd.Schema != 1 {
		fatal("规则 schema 不支持: %d（期望 1）", rd.Schema)
	}

	pkgs, order := scan(rd)
	if len(pkgs) == 0 {
		fatal("未发现任何包（root=%s）——检查工作目录或 rules.json 的 root", rd.Root)
	}

	if !check {
		report(rd, pkgs, order)
	}

	if selftest {
		os.Exit(selftestRun(rd, pkgs, order))
	}
	if verdict(rd, pkgs, order) {
		fmt.Printf("pkg_deps: PASS（%d 包，分层方向与无环均成立）\n", len(pkgs))
		return
	}
	fmt.Println("pkg_deps: FAIL——依赖方向违规（详见上方）")
	os.Exit(1)
}

// verdict：三条判据全过才绿；不早退，一次暴露全部违规。
func verdict(rd rulesDoc, pkgs map[string]*pkgInfo, order []string) bool {
	ok := true

	// ① 未登记分层的包
	var unregistered []string
	totalDeps := 0
	for _, n := range order {
		p := pkgs[n]
		if !p.exempt && p.levelKey == "" {
			unregistered = append(unregistered, n)
		}
		totalDeps += len(p.deps)
	}
	if len(unregistered) > 0 {
		ok = false
		fmt.Printf("  [未登记] 下列包在 rules.json 的 levels 中无匹配（新包必须登记分层）：%s\n",
			strings.Join(unregistered, ", "))
	}
	// ④ 空集不得绿
	if totalDeps == 0 {
		ok = false
		fmt.Println("  [空集] 解析出 0 条模块内依赖——扫描口径可能已失效，拒绝判定")
	}

	// ② 越层
	var violations []string
	for _, n := range order {
		p := pkgs[n]
		if p.exempt {
			continue
		}
		for _, d := range p.deps {
			dp, has := pkgs[d]
			if !has || dp.exempt {
				continue
			}
			if dp.levelKey == "" {
				continue // 已在①报
			}
			if dp.level > p.level {
				ok = false
				violations = append(violations,
					fmt.Sprintf("%s(L%d %s) → %s(L%d %s)", n, p.level, p.levelKey, d, dp.level, dp.levelKey))
			}
		}
	}
	if len(violations) > 0 {
		fmt.Printf("  [越层] %d 条依赖指向更高层（依赖必须向下或同层）：\n", len(violations))
		for _, v := range violations {
			fmt.Printf("    %s\n", v)
		}
	}

	// ③ 环
	if cycle := findCycle(pkgs, order); len(cycle) > 0 {
		ok = false
		fmt.Printf("  [成环] %s\n", strings.Join(cycle, " → "))
	}
	return ok
}

func report(rd rulesDoc, pkgs map[string]*pkgInfo, order []string) {
	fmt.Printf("MoonBit 包依赖方向（%d 包；分层源 = 总计划 §4 L0–L9）\n", len(pkgs))
	for _, n := range order {
		p := pkgs[n]
		tag := fmt.Sprintf("L%d", p.level)
		if p.exempt {
			tag = "工具层(豁免)"
		} else if p.levelKey == "" {
			tag = "未登记"
		}
		dep := "(无)"
		if len(p.deps) > 0 {
			dep = strings.Join(p.deps, ", ")
		}
		fmt.Printf("  %-24s %-14s → %s\n", n, tag, dep)
	}
}

// selftestRun：J9 埋雷。先确认基线绿，再注入一条必然越层的虚拟依赖
// （L1 的 diag 依赖 L6 的 codegen），必须判红。
func selftestRun(rd rulesDoc, pkgs map[string]*pkgInfo, order []string) int {
	if !verdict(rd, pkgs, order) {
		fmt.Println("pkg_deps: selftest ABORT——基线不绿，注入后的红无法归因")
		return 2
	}
	lo, hi, loLv, hiLv := lowestAndHighestExisting(pkgs, order)
	if lo == "" || hi == "" {
		fmt.Println("pkg_deps: selftest ABORT——分层表不足以构造越层对")
		return 2
	}
	if loLv == hiLv {
		fmt.Println("pkg_deps: selftest ABORT——实际包全在同层，无法构造越层对")
		return 2
	}
	// 深拷贝注入（不动磁盘）
	inj := make(map[string]*pkgInfo, len(pkgs))
	for k, v := range pkgs {
		cp := *v
		cp.deps = append([]string(nil), v.deps...)
		inj[k] = &cp
	}
	// 若该边已存在则不构成注入（换用 hi 的最高层包已在 lo 依赖里时）
	for _, d := range inj[lo].deps {
		if d == hi {
			fmt.Printf("pkg_deps: selftest ABORT——%s 已依赖 %s，注入无效\n", lo, hi)
			return 2
		}
	}
	inj[lo].deps = append(inj[lo].deps, hi)
	fmt.Printf("pkg_deps: selftest 已注入越层边 %s(L%d) → %s(L%d)\n", lo, loLv, hi, hiLv)
	if verdict(rd, inj, order) {
		fmt.Println("pkg_deps: selftest FAIL——注入越层边后仍判绿，闸门失效")
		return 1
	}
	fmt.Println("pkg_deps: selftest PASS——注入的越层边被捕获（红），J9 证红成立")
	return 0
}

// lowestAndHighestExisting：在**实际存在的包**中选层号最低 / 最高的
// 非豁免包（层名表含 S6–S9 未建包，不能直接当注入端点——用它会 nil）。
// 同层取字典序首个（order 已排序），由严格小于保证。
func lowestAndHighestExisting(pkgs map[string]*pkgInfo, order []string) (string, string, int, int) {
	lo, hi := "", ""
	loLv, hiLv := 1<<31-1, -1
	for _, n := range order {
		p := pkgs[n]
		if p.exempt || p.levelKey == "" {
			continue
		}
		if p.level < loLv {
			loLv, lo = p.level, n
		}
		if p.level > hiLv {
			hiLv, hi = p.level, n
		}
	}
	return lo, hi, loLv, hiLv
}

// ---------------------------------------------------------------------------
// 扫描
// ---------------------------------------------------------------------------

func scan(rd rulesDoc) (map[string]*pkgInfo, []string) {
	pkgs := map[string]*pkgInfo{}
	root := filepath.FromSlash(rd.Root)
	err := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if !info.IsDir() {
			return nil
		}
		switch info.Name() {
		case "_build", ".mooncakes", ".git":
			return filepath.SkipDir
		}
		if _, err := os.Stat(filepath.Join(path, "moon.pkg")); err != nil {
			return nil
		}
		name := filepath.ToSlash(strings.TrimPrefix(path, root+string(filepath.Separator)))
		if name == "" || name == "." {
			return nil
		}
		deps := parseDeps(filepath.Join(path, "moon.pkg"), rd.Module, name)
		p := &pkgInfo{name: name, deps: deps}
		p.levelKey, p.level = longestPrefixLevel(name, rd.Levels)
		p.exempt = hasPrefixAny(name, rd.ExemptPrefixes)
		pkgs[name] = p
		return nil
	})
	if err != nil {
		fatal("遍历 %s 失败: %v", rd.Root, err)
	}
	order := make([]string, 0, len(pkgs))
	for n := range pkgs {
		order = append(order, n)
	}
	sort.Strings(order)
	return pkgs, order
}

// parseDeps：解析 moon.pkg 的全部 import 块（含 `for "test"`），
// 只保留同 module 前缀的依赖，映射为包名（相对 root）。
func parseDeps(pkgPath, module, selfName string) []string {
	data, err := os.ReadFile(pkgPath)
	if err != nil {
		fatal("读 %s 失败: %v", pkgPath, err)
	}
	seen := map[string]bool{}
	var out []string
	prefix := module + "/"
	for _, blk := range reImportBlock.FindAllStringSubmatch(string(data), -1) {
		for _, m := range reQuoted.FindAllStringSubmatch(blk[1], -1) {
			dep := m[1]
			if !strings.HasPrefix(dep, prefix) {
				continue // 外部分（moonbitlang/*）不判定
			}
			pkgName := strings.TrimPrefix(dep, prefix)
			if pkgName == selfName || seen[pkgName] {
				continue
			}
			seen[pkgName] = true
			out = append(out, pkgName)
		}
	}
	sort.Strings(out)
	return out
}

// longestPrefixLevel：最长前缀匹配（子包继承父包层号）。
func longestPrefixLevel(pkg string, levels map[string]int) (string, int) {
	best, bestLen := "", -1
	for k := range levels {
		if pkg == k || strings.HasPrefix(pkg, k+"/") {
			if len(k) > bestLen {
				best, bestLen = k, len(k)
			}
		}
	}
	if best == "" {
		return "", -1
	}
	return best, levels[best]
}

func hasPrefixAny(s string, prefixes []string) bool {
	for _, p := range prefixes {
		if s == p || strings.HasPrefix(s, p+"/") {
			return true
		}
	}
	return false
}

// findCycle：DFS 找一条回边路径（只走判定内的包）。空切片 = 无环。
func findCycle(pkgs map[string]*pkgInfo, order []string) []string {
	const (
		white = 0
		gray  = 1
		black = 2
	)
	color := map[string]int{}
	var stack []string
	var cycle []string

	var dfs func(n string) bool
	dfs = func(n string) bool {
		color[n] = gray
		stack = append(stack, n)
		p := pkgs[n]
		for _, d := range p.deps {
			if _, has := pkgs[d]; !has {
				continue
			}
			switch color[d] {
			case gray:
				// 回边：截取栈中从 d 起的一段
				for i, s := range stack {
					if s == d {
						cycle = append(append([]string(nil), stack[i:]...), d)
						return true
					}
				}
				cycle = []string{d, n, d}
				return true
			case white:
				if dfs(d) {
					return true
				}
			}
		}
		stack = stack[:len(stack)-1]
		color[n] = black
		return false
	}

	for _, n := range order {
		if color[n] == white {
			if dfs(n) {
				return cycle
			}
		}
	}
	return nil
}

func fatal(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "pkg_deps: "+format+"\n", args...)
	os.Exit(2)
}
