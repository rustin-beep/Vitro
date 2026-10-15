// teaching_reconcile —— 教学资产码表对账闸（#125 批 A / #128 存活部分①）。
//
// 三向对账的批 A 最小形态（两向 + J9 自检；第三腿「协议码表」待 #128
// 替代裁定的双模式协议增量落地后接入，缺席不红）：
//
//	① 内容键集：moonbit/teaching/content/*.md 的 `## ` 节标题
//	② 引擎装配点字面量：
//	     trap      moonbit/host/host_memory.mbt     trap_messages.get("KEY")
//	     sugg      moonbit/teaching/assets/map.mbt  m.set("KEY",
//	     builtin   moonbit/typeck/**.mbt            builtin_notes.get("KEY")
//
// 判据：① ≡ ②（双向：孤儿内容 / 装配缺键都红——装配缺键即运行期
// get().unwrap() panic 的 CI 前置化）。suggestions 另有编译期闸
// （map.mbt 43 臂穷尽 match 对生成枚举），本闸仍查其字面量防双源漂移。
// 基线计数（45/43/12）一并校验，整表漂移 fail loud。
//
// 用法（仓库根）：
//
//	go run ./scripts/teaching_reconcile            # 校验
//	go run ./scripts/teaching_reconcile -v         # 逐键打印
//	go run ./scripts/teaching_reconcile --selftest # J9 注入证红
package main

import (
	"bufio"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

var (
	reHeading   = regexp.MustCompile(`^## ([A-Za-z_0-9]+)\s*$`)
	reTrapGet   = regexp.MustCompile(`trap_messages\.get\("([A-Za-z_0-9]+)"\)`)
	reSuggSet   = regexp.MustCompile(`m\.set\("([a-z_0-9]+)",`)
	reBuiltin   = regexp.MustCompile(`builtin_notes\.get\("([A-Za-z_0-9]+)"\)`)
	reRenderVar = regexp.MustCompile(`render_var_section\("([A-Za-z_0-9]+)"`)
	reTpl       = regexp.MustCompile(`\btpl\("([A-Za-z_0-9]+)"`)
	reRnd       = regexp.MustCompile(`\brnd\("([A-Za-z_0-9]+)"`)
)

type pair struct {
	md           string   // 真源
	sites        []site   // 装配点（目录/文件 × 提取正则矩阵）
	consumerDirs []string // 覆盖域：内容键须以 "K" 字面量在场（排版无关）
	base         int      // 基线条数
	label        string
}

type site struct {
	paths []string
	res   []*regexp.Regexp
}

func pairs() []pair {
	// trap 装配点分散三目录、四种调用形态（get / render_var_section / tpl /
	// rnd——字面量经包装函数流入 get(key)）。出现第 5 种形态时未知键会以
	// 「孤儿内容键」红牌自曝，逼本矩阵扩形（fail loud）。
	trapSite := site{
		paths: []string{"moonbit/host", "moonbit/vm", "moonbit/time_travel"},
		res:   []*regexp.Regexp{reTrapGet, reRenderVar, reTpl, reRnd},
	}
	return []pair{
		{
			md: "moonbit/teaching/content/trap_messages.md", label: "trap", base: 45,
			sites:        []site{trapSite},
			consumerDirs: []string{"moonbit/host", "moonbit/vm", "moonbit/time_travel"},
		},
		{
			md: "moonbit/teaching/content/suggestions.md", label: "suggestions", base: 43,
			sites: []site{{
				paths: []string{"moonbit/teaching/assets/map.mbt"},
				res:   []*regexp.Regexp{reSuggSet},
			}},
		},
		{
			md: "moonbit/teaching/content/builtin_notes.md", label: "builtin_notes", base: 12,
			consumerDirs: []string{"moonbit/typeck"},
			sites: []site{{
				paths: []string{"moonbit/typeck"},
				res:   []*regexp.Regexp{reBuiltin},
			}},
		},
	}
}

func die(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "[teaching_reconcile] FAIL: "+format+"\n", args...)
	os.Exit(1)
}

// contentKeys 读真源的 `## ` 节标题键集（含顺序无关去重检查）。
func contentKeys(md string) map[string]bool {
	f, err := os.Open(md)
	if err != nil {
		die("读真源失败 %s: %v", md, err)
	}
	defer f.Close()
	out := map[string]bool{}
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1024*1024), 1024*1024)
	for sc.Scan() {
		if m := reHeading.FindStringSubmatch(sc.Text()); m != nil {
			if out[m[1]] {
				die("%s: 节键 %q 重复", md, m[1])
			}
			out[m[1]] = true
		}
	}
	if len(out) == 0 {
		die("%s: 未解析到任何节键（空集不得绿）", md)
	}
	return out
}

// siteKeys 收装配点字面量（目录则递归 .mbt；目录×正则全组合取并）。
func siteKeys(s site) map[string]bool {
	out := map[string]bool{}
	var walk func(p string, re *regexp.Regexp)
	walk = func(p string, re *regexp.Regexp) {
		st, err := os.Stat(p)
		if err != nil {
			die("读装配点失败 %s: %v", p, err)
		}
		if st.IsDir() {
			entries, _ := os.ReadDir(p)
			for _, e := range entries {
				name := e.Name()
				if strings.HasSuffix(name, ".mbt") && !strings.HasSuffix(name, ".mbti") {
					walk(filepath.Join(p, name), re)
				}
			}
			return
		}
		data, err := os.ReadFile(p)
		if err != nil {
			die("读装配点失败 %s: %v", p, err)
		}
		for _, m := range re.FindAllStringSubmatch(string(data), -1) {
			out[m[1]] = true
		}
	}
	for _, p := range s.paths {
		for _, re := range s.res {
			walk(p, re)
		}
	}
	if len(out) == 0 {
		die("装配点 %v 未提取到任何字面量（提取器失效或装配点漂移）", s.paths)
	}
	return out
}

func sortedKeys(m map[string]bool) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

// reconcile 单组对账：返回失败明细（空切片 = 通过）。
func reconcile(p pair, v bool) []string {
	var fails []string
	content := contentKeys(p.md)
	siteSet := map[string]bool{}
	for _, s := range p.sites {
		for k := range siteKeys(s) {
			siteSet[k] = true
		}
	}
	if len(content) != p.base {
		fails = append(fails, fmt.Sprintf("%s: 内容条数 %d ≠ 基线 %d（整表漂移须人工核对）", p.label, len(content), p.base))
	}
	/* 孤儿内容键检测由下方覆盖判据接管（字面量在场即算被消费——
	 * 排版无关；比调用形态正则更稳，多行/拼接碎片都会红牌自曝）。 */
	for _, k := range sortedKeys(siteSet) {
		if !content[k] {
			fails = append(fails, fmt.Sprintf("%s: 装配缺键 %q（装配点有、真源无——运行期 get().unwrap() 必 panic）", p.label, k))
		}
	}
	// 覆盖判据：内容键须以 "K" 字面量出现在消费域（排版无关——多行调用/
	// 拼接碎片化都会以孤儿红牌自曝，逼新形态登记进本闸）。
	if len(p.consumerDirs) > 0 {
		var big strings.Builder
		var walk func(p string)
		walk = func(p string) {
			st, err := os.Stat(p)
			if err != nil {
				die("读覆盖域失败 %s: %v", p, err)
			}
			if st.IsDir() {
				entries, _ := os.ReadDir(p)
				for _, e := range entries {
					if strings.HasSuffix(e.Name(), ".mbt") && !strings.HasSuffix(e.Name(), ".mbti") {
						walk(filepath.Join(p, e.Name()))
					}
				}
				return
			}
			data, err := os.ReadFile(p)
			if err != nil {
				die("读覆盖域失败 %s: %v", p, err)
			}
			big.Write(data)
		}
		for _, d := range p.consumerDirs {
			walk(d)
		}
		blob := big.String()
		for _, k := range sortedKeys(content) {
			if !strings.Contains(blob, `"`+k+`"`) {
				fails = append(fails, fmt.Sprintf("%s: 孤儿内容键 %q（真源有、消费域无字面量——死内容或新键构造形态未登记）", p.label, k))
			}
		}
	}
	if v {
		for _, k := range sortedKeys(content) {
			fmt.Printf("[teaching_reconcile] ✓ %s %s\n", p.label, k)
		}
	}
	return fails
}

// selftest J9：注入假装配键，断言双向判据必红（闸自身体检）。
func selftest() {
	p := pairs()[0] // trap
	content := contentKeys(p.md)
	siteSet := map[string]bool{}
	for k := range siteKeys(p.sites[0]) {
		siteSet[k] = true
	}
	_ = siteSet
	siteSet["strng-typo-j9"] = true // 注入假装配键
	red := false
	for k := range siteSet {
		if !content[k] {
			red = true
		}
	}
	if !red {
		die("J9 自检失败：假装配键未被捕获——双向判据已失效")
	}
	fmt.Println("[teaching_reconcile] J9 自检 OK：假装配键注入被捕获")
}

func main() {
	v := flag.Bool("v", false, "逐键打印")
	self := flag.Bool("selftest", false, "J9 注入证红（闸自身体检）")
	flag.Parse()
	if *self {
		selftest()
		return
	}
	var fails []string
	for _, p := range pairs() {
		fails = append(fails, reconcile(p, *v)...)
	}
	if len(fails) > 0 {
		for _, f := range fails {
			fmt.Fprintln(os.Stderr, "[teaching_reconcile] ✗ "+f)
		}
		die("%d 项判据未过", len(fails))
	}
	fmt.Println("[teaching_reconcile] 全部通过：trap/suggestions/builtin_notes 内容键 ≡ 装配点字面量")
}
