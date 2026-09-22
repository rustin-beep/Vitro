// single_source：单一真相源清单校验器（架构审阅 v2 A 组 #7 / 判据 C-04）。
//
// 用法（**仓库根**）：
//
//	go run ./scripts/moonbit/single_source            # 报告清单 + 判定
//	go run ./scripts/moonbit/single_source -check     # 判定（CI 门禁用）
//	go run ./scripts/moonbit/single_source --selftest # J9：注入第二份实现必红
//
// 为什么需要它（C-04 的裁决要点）：项目 L1 判据「同一概念多真相来源」只覆盖
// **仓内同语言重复**（R3 审计已收口），**不覆盖跨语言孪生**——迁移期每个单源在
// MoonBit 侧都有一份孪生，同步义务纯人工（"照搬不私改"）。本闸把这份清单
// 入版本控制并做机判，让「悄悄长出第二份实现」变成红。
//
// 两类条目：
//
//	enforced   —— 本闸可直接判：全仓按 def_pattern 扫定义点，命中**文件集**
//	              必须等于 allowed_def_files。多一处 → 第二份真相（红）；
//	              少一处 → 单源被删/改名（红）。
//	registered —— 单源形态是"生成物"或"另有专用闸门"，本闸只校验声明的两侧
//	              路径存在，并把检测锚点登记在案（供人查"这条谁在守"）。
//
// 判定：任一条目失败即红；列表为空（解析不到条目）亦红（空集不得绿）。
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

const rulesPath = "scripts/moonbit/single_source/rules.json"

type entry struct {
	ID                 string   `json:"id"`
	Concept            string   `json:"concept"`
	Kind               string   `json:"kind"`
	DefPattern         string   `json:"def_pattern"`
	ExcludeLinePattern string   `json:"exclude_line_pattern"`
	AllowedDefFiles    []string `json:"allowed_def_files"`
	RustSource      string   `json:"rust_source"`
	MoonbitSource   string   `json:"moonbit_source"`
	Sync            string   `json:"sync"`
	Consumers       []string `json:"consumers"`
	Anchor          string   `json:"anchor"`
	UpstreamRef     string   `json:"upstream_ref"`
}

type rulesDoc struct {
	Schema            int      `json:"schema"`
	SearchRoots       []string `json:"search_roots"`
	SearchExcludeDirs []string `json:"search_exclude_dirs"`
	Entries           []entry  `json:"entries"`
}

// result：单条目的判定结果（report / selftest / 判定共用）。
type result struct {
	e       entry
	ok      bool
	hits    []string
	missing []string
	extra   []string
	msg     string
}

func main() {
	check, selftest := false, false
	for _, a := range os.Args[1:] {
		switch a {
		case "-check":
			check = true
		case "--selftest":
			selftest = true
		default:
			fatal("未知参数: %s（可用：-check / --selftest）", a)
		}
	}
	rd := loadRules()
	if len(rd.Entries) == 0 {
		fatal("清单为空——空集不得绿")
	}

	// 收集 all：每条目的判定结果
	results := make([]result, 0, len(rd.Entries))
	for _, e := range rd.Entries {
		r := result{e: e, ok: true}
		// 声明的两侧路径必须存在（非空者）
		for _, p := range []string{e.RustSource, e.MoonbitSource} {
			if p == "" {
				continue
			}
			if _, err := os.Stat(filepath.FromSlash(p)); err != nil {
				r.ok = false
				r.msg += fmt.Sprintf("声明的源路径不存在: %s\n", p)
			}
		}
		if e.Kind == "enforced" {
			if e.DefPattern == "" || len(e.AllowedDefFiles) == 0 {
				r.ok = false
				r.msg += "enforced 条目缺 def_pattern / allowed_def_files\n"
			} else {
				hits := scanDefs(rd, e.DefPattern, e.ExcludeLinePattern)
				r.hits = hits
				allow := map[string]bool{}
				for _, f := range e.AllowedDefFiles {
					allow[canon(f)] = true
				}
				hitSet := map[string]bool{}
				for _, h := range hits {
					hitSet[h] = true
				}
				for h := range hitSet {
					if !allow[h] {
						r.extra = append(r.extra, h)
					}
				}
				for a := range allow {
					if !hitSet[a] {
						r.missing = append(r.missing, a)
					}
				}
				sort.Strings(r.extra)
				sort.Strings(r.missing)
				if len(r.extra) > 0 || len(r.missing) > 0 {
					r.ok = false
				}
			}
		} else if e.Kind != "registered" {
			r.ok = false
			r.msg += fmt.Sprintf("未知 kind: %s\n", e.Kind)
		}
		results = append(results, r)
	}

	if selftest {
		os.Exit(selftestRun(rd, results))
	}
	if !check {
		report(rd, results)
	}

	bad := 0
	for _, r := range results {
		if !r.ok {
			bad++
		}
	}
	if bad > 0 {
		if check {
			// -check 模式只打失败项（CI 日志可读）
			for _, r := range results {
				if !r.ok {
					printEntry(r, true)
				}
			}
		}
		fmt.Printf("single_source: FAIL——%d/%d 条单源未通过\n", bad, len(results))
		os.Exit(1)
	}
	fmt.Printf("single_source: PASS——%d 条单源清单全部成立（定义点唯一性 + 两侧路径在）\n", len(results))
}

// selftestRun：J9 埋雷。先确认基线绿（否则注入后的红无法归因），再给第一条
// enforced 条目注入一个**虚构的第二份实现文件**，必须变红。
func selftestRun(rd rulesDoc, results []result) int {
	for _, r := range results {
		if !r.ok {
			fmt.Println("single_source: selftest ABORT——基线不绿，注入后的红无法归因")
			return 2
		}
	}
	idx := -1
	for i, r := range results {
		if r.e.Kind == "enforced" {
			idx = i
			break
		}
	}
	if idx < 0 {
		fmt.Println("single_source: selftest ABORT——清单无 enforced 条目")
		return 2
	}
	e := results[idx].e
	fake := "moonbit/ast/__selftest_second_copy.mbt"
	hitSet := map[string]bool{fake: true}
	for _, h := range results[idx].hits {
		hitSet[h] = true
	}
	allow := map[string]bool{}
	for _, f := range e.AllowedDefFiles {
		allow[canon(f)] = true
	}
	extra := 0
	for h := range hitSet {
		if !allow[h] {
			extra++
		}
	}
	fmt.Printf("single_source: selftest 已注入第二份实现 %s（条目 %s）\n", fake, e.ID)
	if extra == 0 {
		fmt.Println("single_source: selftest FAIL——注入的第二份实现未被判定为多出，闸门失效")
		return 1
	}
	fmt.Println("single_source: selftest PASS——注入的第二份实现被捕获（红），J9 证红成立")
	return 0
}

func report(rd rulesDoc, results []result) {
	fmt.Println("单一真相源清单（跨语言孪生层；判据 C-04 —— L1 只覆盖同语言重复）")
	for _, r := range results {
		printEntry(r, false)
	}
}

func printEntry(r result, onlyFail bool) {
	mark := "OK "
	if !r.ok {
		mark = "BAD"
	}
	fmt.Printf("  [%s][%s] %s — %s\n", mark, r.e.Kind, r.e.ID, r.e.Concept)
	fmt.Printf("        rust  : %s\n", orNone(r.e.RustSource))
	fmt.Printf("        moon  : %s\n", orNone(r.e.MoonbitSource))
	fmt.Printf("        sync  : %s\n", r.e.Sync)
	if r.e.Kind == "enforced" {
		fmt.Printf("        定义点: %d 处命中（allowed %d）\n", len(r.hits), len(r.e.AllowedDefFiles))
	}
	fmt.Printf("        anchor: %s\n", r.e.Anchor)
	if len(r.e.Consumers) > 0 {
		fmt.Printf("        消费点: %s\n", strings.Join(r.e.Consumers, ", "))
	}
	if r.e.UpstreamRef != "" {
		fmt.Printf("        上游  : %s\n", r.e.UpstreamRef)
	}
	if !r.ok {
		if r.msg != "" {
			fmt.Printf("        !! %s", r.msg)
		}
		if len(r.extra) > 0 {
			fmt.Printf("        !! 多出第二份实现: %s\n", strings.Join(r.extra, ", "))
		}
		if len(r.missing) > 0 {
			fmt.Printf("        !! 单源缺失（声明有而实际无）: %s\n", strings.Join(r.missing, ", "))
		}
	}
}

// scanDefs：在 search_roots 下按 pattern 逐行匹配**定义点**，返回命中的
// 文件集（相对仓库根、POSIX 风格）。跳过注释行（`//` `///` `#` 开头）——
// 文档注释里提到函数名不算实现。只扫 .rs / .mbt。
func scanDefs(rd rulesDoc, pattern, excludeLine string) []string {
	re, err := regexp.Compile(pattern)
	if err != nil {
		fatal("def_pattern 非法 %q: %v", pattern, err)
	}
	var reExcl *regexp.Regexp
	if excludeLine != "" {
		reExcl, err = regexp.Compile(excludeLine)
		if err != nil {
			fatal("exclude_line_pattern 非法 %q: %v", excludeLine, err)
		}
	}
	exclude := map[string]bool{}
	for _, d := range rd.SearchExcludeDirs {
		exclude[d] = true
	}
	hits := map[string]bool{}
	for _, root := range rd.SearchRoots {
		_ = filepath.Walk(filepath.FromSlash(root), func(path string, info os.FileInfo, err error) error {
			if err != nil {
				return nil
			}
			if info.IsDir() {
				if exclude[info.Name()] {
					return filepath.SkipDir
				}
				return nil
			}
			ext := filepath.Ext(path)
			if ext != ".rs" && ext != ".mbt" {
				return nil
			}
			data, err := os.ReadFile(path)
			if err != nil {
				return nil
			}
			for _, line := range strings.Split(string(data), "\n") {
				t := strings.TrimSpace(line)
				if strings.HasPrefix(t, "//") || strings.HasPrefix(t, "#") {
					continue
				}
				if reExcl != nil && reExcl.MatchString(line) {
					continue // 方法形态（含 self）——非自由函数定义，见 rules 的 _exclude_note
				}
				if re.MatchString(line) {
					rel, err := filepath.Rel(".", path)
					if err != nil {
						rel = path
					}
					hits[canon(rel)] = true
					return nil
				}
			}
			return nil
		})
	}
	out := make([]string, 0, len(hits))
	for h := range hits {
		out = append(out, h)
	}
	sort.Strings(out)
	return out
}

func canon(p string) string {
	return filepath.ToSlash(filepath.Clean(p))
}

func orNone(s string) string {
	if s == "" {
		return "(无——见 note)"
	}
	return s
}

func loadRules() rulesDoc {
	raw, err := os.ReadFile(rulesPath)
	if err != nil {
		fatal("读清单失败（须在仓库根运行）: %v", err)
	}
	var rd rulesDoc
	if err := json.Unmarshal(raw, &rd); err != nil {
		fatal("清单解析失败: %v", err)
	}
	if rd.Schema != 1 {
		fatal("清单 schema 不支持: %d（期望 1）", rd.Schema)
	}
	if len(rd.SearchRoots) == 0 {
		fatal("清单缺 search_roots")
	}
	return rd
}

func fatal(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "single_source: "+format+"\n", args...)
	os.Exit(2)
}
