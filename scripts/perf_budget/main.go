// Command perf_budget 是**性能假设预算闸**：把「某项性能优化为什么不做」
// 所依赖的**规模前提**变成可机判的红线。
//
// 动机（2026-09-22 S5 收尾批）：typeck 的 O2 债（`compute_type_size` 每次
// 调用重建 struct/union 定义表）经实测裁定**不做缓存化**，依据是语料规模
// 小到成本不可测（全 600 语料 struct 定义最多 2 个、成员访问最多 37 次）。
// 但「规模小」是个**会过期的前提**——语料一旦长出 struct 密集的大程序
// （或 C# 批引入类），该裁决的依据即失效，而**没有任何机制会提醒**。
//
// 本闸把该前提写进规则并断言：每个 counter 的**单文件计数最大值**必须
// 不超其预算。超阈即红，输出 `on_exceed` 指回裁决所在（代码注释 + CHANGELOG），
// 迫使重估——**这正是「机制写在注释里」的反面**：裁决可以写在注释里，
// 但裁决的**前提**必须有人守。
//
// 与 facts 的分工：facts 管「文档数字 ↔ 机器真值」的对账；本闸管
// 「性能裁决的规模前提是否仍成立」，是阈值断言而非一致性比对。
//
// 规则外置 rules.json（改计数器/预算只改 JSON）；0 语料文件即 fail loud
// （拒绝空转判绿）；`--selftest` 为 J9 证红入口。
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

const rulesPath = "scripts/perf_budget/rules.json"

// dirTier：counter 的按目录预算档（#236 分档预算，2026-10-21）——文件按
// 所属 corpus_dir 前缀匹配档位（未匹配用顶层 max_per_file）；每档独立
// 判红。档位语义 = 显式建模新规模面（如千行压力语料），不允许全局抬
// 上限稀释存量裁决前提（_tier_note 在 rules.json）。
type dirTier struct {
	Dirs       []string `json:"dirs"`
	MaxPerFile int      `json:"max_per_file"`
}

type counter struct {
	ID         string    `json:"id"`
	Pattern    string    `json:"pattern"`
	MaxPerFile int       `json:"max_per_file"`
	DirTiers   []dirTier `json:"dir_tiers"`
}

type metric struct {
	ID          string    `json:"id"`
	Concept     string    `json:"concept"`
	AsOf        string    `json:"as_of"`
	DecisionRef string    `json:"decision_ref"`
	Counters    []counter `json:"counters"`
	OnExceed    string    `json:"on_exceed"`
}

type rulesDoc struct {
	Schema     int      `json:"schema"`
	CorpusRoot string   `json:"corpus_root"`
	CorpusDirs []string `json:"corpus_dirs"`
	FileExt    string   `json:"file_ext"`
	Metrics    []metric `json:"metrics"`
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
		for _, m := range []string{"corpus", "scripts"} {
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

// stripComments：粗去块注释与行注释（不处理字符串内的 `//`——本闸统计的是
// 语料规模量级，粗粒度足够，且两侧口径一致即可复现）。
var (
	reBlockComment = regexp.MustCompile(`(?s)/\*.*?\*/`)
	reLineComment  = regexp.MustCompile(`//[^\n]*`)
)

func stripComments(src string) string {
	src = reBlockComment.ReplaceAllString(src, " ")
	return reLineComment.ReplaceAllString(src, " ")
}

// collectFiles：语料目录下全部目标扩展名文件的**仓库根相对路径**（正斜杠，排序）。
func collectFiles(root string, rd rulesDoc) []string {
	ext := rd.FileExt
	if ext == "" {
		ext = ".c"
	}
	var out []string
	for _, d := range rd.CorpusDirs {
		base := filepath.Join(root, filepath.FromSlash(rd.CorpusRoot), filepath.FromSlash(d))
		if fi, err := os.Stat(base); err != nil || !fi.IsDir() {
			fatal("语料目录不存在: %s (%v)", base, err)
		}
		err := filepath.WalkDir(base, func(path string, de os.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if de.IsDir() || !strings.HasSuffix(de.Name(), ext) {
				return nil
			}
			rel, err := filepath.Rel(root, path)
			if err != nil {
				rel = path
			}
			out = append(out, filepath.ToSlash(rel))
			return nil
		})
		if err != nil {
			fatal("扫描 %s 失败: %v", base, err)
		}
	}
	sort.Strings(out)
	if len(out) == 0 {
		fatal("0 个 %s 语料文件（corpus_root/corpus_dirs/file_ext 配置有误），拒绝判绿", ext)
	}
	return out
}

type finding struct {
	Metric   string
	Counter  string
	Tier     string // 档位标签（""=顶层默认档；否则 corpus_dir 名）
	MaxCount int
	MaxFile  string
	Limit    int
	Exceed   bool
}

// tierOf：文件所属档位（counter 的 dir_tiers 首个前缀命中；无命中顶层档）。
// P3-2（审阅批 2026-10-23）：档位目录名写错/不存在时 tierOf 静默落顶层
// 档（配置空转而闸绿）——启动时逐档验证目录真实存在，fail loud。
func tierOf(c counter, f string) (dirTier, string) {
	for _, t := range c.DirTiers {
		for _, d := range t.Dirs {
			if strings.HasPrefix(f, "corpus/"+d+"/") {
				return t, d
			}
		}
	}
	return dirTier{MaxPerFile: c.MaxPerFile}, ""
}

// validateDirTiers：档位目录存在性守卫（空转根除——审阅 P3-2）。
func validateDirTiers(rd rulesDoc) {
	seen := map[string]bool{}
	for _, m := range rd.Metrics {
		for _, c := range m.Counters {
			for _, t := range c.DirTiers {
				for _, d := range t.Dirs {
					if seen[d] {
						continue
					}
					seen[d] = true
					if _, err := os.Stat("corpus/" + d); err != nil {
						fatal("dir_tiers 档位目录 corpus/%s 不存在（配置空转：文件将静默落顶层档）", d)
					}
				}
			}
		}
	}
}

func scan(root string, rd rulesDoc) ([]finding, int) {
	files := collectFiles(root, rd)
	var out []finding
	for _, m := range rd.Metrics {
		if len(m.Counters) == 0 {
			fatal("metric %q 无 counters——拒绝空转", m.ID)
		}
		for _, c := range m.Counters {
			re, err := regexp.Compile(c.Pattern)
			if err != nil {
				fatal("counter %q 的 pattern 非法: %v", c.ID, err)
			}
			// 分档聚合：档位 → (maxN, maxF)；每档一条 finding（#236）
			type agg struct {
				n int
				f string
			}
			byTier := map[string]agg{}
			tierOfKey := map[string]int{} // 档 key → 该档 max_per_file
			for _, f := range files {
				b, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(f)))
				if err != nil {
					fatal("读语料 %s 失败: %v", f, err)
				}
				n := len(re.FindAllString(stripComments(string(b)), -1))
				t, label := tierOf(c, f)
				key := label
				if label == "" {
					key = "(default)"
				}
				cur := byTier[key]
				if n > cur.n {
					byTier[key] = agg{n, f}
				}
				tierOfKey[key] = t.MaxPerFile
			}
			// 输出序稳定：default 档在前，其余按名
			keys := make([]string, 0, len(byTier))
			for k := range byTier {
				if k != "(default)" {
					keys = append(keys, k)
				}
			}
			sort.Strings(keys)
			if _, ok := byTier["(default)"]; ok {
				keys = append([]string{"(default)"}, keys...)
			}
			for _, k := range keys {
				a := byTier[k]
				label := ""
				if k != "(default)" {
					label = k
				}
				out = append(out, finding{
					Metric: m.ID, Counter: c.ID, Tier: label,
					MaxCount: a.n, MaxFile: a.f,
					Limit: tierOfKey[k], Exceed: a.n > tierOfKey[k],
				})
			}
		}
	}
	return out, len(files)
}

func report(root string, rd rulesDoc, fs []finding, nFiles int) {
	fmt.Printf("perf_budget: 语料 %d 个 %s 文件（%s/%s）\n",
		nFiles, rd.FileExt, rd.CorpusRoot, strings.Join(rd.CorpusDirs, "+"))
	for _, m := range rd.Metrics {
		fmt.Printf("  [%s] %s\n", m.ID, m.Concept)
		fmt.Printf("    基准（%s）| 裁决见 %s\n", m.AsOf, m.DecisionRef)
	}
	for _, f := range fs {
		mark := "ok  "
		if f.Exceed {
			mark = "OVER"
		}
		fmt.Printf("  %s %-26s [tier %-9s] max=%-6d limit=%-6d @ %s\n", mark, f.Counter, f.Tier, f.MaxCount, f.Limit, f.MaxFile)
	}
}

// selftest（J9 埋雷）：把全部 counter 的预算压到 0（任何 >0 计数即超），
// 断言闸门必红；改 JSON 后 defer 恢复。不动语料，避免污染其它闸门。
func selftest(root string, rd rulesDoc) int {
	abs := filepath.Join(root, filepath.FromSlash(rulesPath))
	orig, err := os.ReadFile(abs)
	if err != nil {
		fmt.Printf("perf_budget: selftest ABORT——读规则失败: %v\n", err)
		return 2
	}
	restored := false
	restore := func() {
		if restored {
			return
		}
		if err := os.WriteFile(abs, orig, 0o644); err != nil {
			fmt.Printf("perf_budget: selftest 严重——恢复 rules.json 失败: %v\n", err)
		}
		restored = true
	}
	defer restore()

	inj := rd
	inj.Metrics = make([]metric, len(rd.Metrics))
	for i, m := range rd.Metrics {
		cp := m
		cp.Counters = make([]counter, len(m.Counters))
		for j, c := range m.Counters {
			c.MaxPerFile = 0 // 任何正计数都超阈
			cp.Counters[j] = c
		}
		inj.Metrics[i] = cp
	}
	b, err := json.MarshalIndent(inj, "", "  ")
	if err != nil {
		fmt.Printf("perf_budget: selftest ABORT——序列化失败: %v\n", err)
		return 2
	}
	if err := os.WriteFile(abs, b, 0o644); err != nil {
		fmt.Printf("perf_budget: selftest ABORT——写规则失败: %v\n", err)
		return 2
	}
	fmt.Println("perf_budget: selftest 已把全部 counter 预算压到 0")

	fs, _ := scan(root, inj)
	over := 0
	for _, f := range fs {
		if f.Exceed {
			over++
		}
	}
	restore()

	if over == 0 {
		fmt.Println("perf_budget: selftest FAIL——预算压到 0 后仍无 counter 超阈，闸门失效")
		return 1
	}
	fmt.Printf("perf_budget: selftest PASS——%d/%d 个 counter 超阈被判红，J9 证红成立\n", over, len(fs))
	return 0
}

func main() {
	checkFlag := flag.Bool("check", false, "判定模式（CI 入口；默认亦为判定，保持与兄弟闸门调用形态一致）")
	selftestFlag := flag.Bool("selftest", false, "J9 证红：把预算压到 0，断言闸门必红")
	flag.Parse()

	root := repoRoot()
	raw, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(rulesPath)))
	if err != nil {
		fatal("读规则失败: %v", err)
	}
	var rd rulesDoc
	if err := json.Unmarshal(raw, &rd); err != nil {
		fatal("解析规则失败: %v", err)
	}
	validateDirTiers(rd)
	if rd.CorpusRoot == "" || len(rd.CorpusDirs) == 0 || len(rd.Metrics) == 0 {
		fatal("规则缺 corpus_root / corpus_dirs / metrics")
	}
	_ = checkFlag

	if *selftestFlag {
		os.Exit(selftest(root, rd))
	}

	fs, nFiles := scan(root, rd)
	report(root, rd, fs, nFiles)
	var over []finding
	for _, f := range fs {
		if f.Exceed {
			over = append(over, f)
		}
	}
	if len(over) == 0 {
		fmt.Println("perf_budget: PASS——全部性能假设的规模前提仍在预算内")
		return
	}
	fmt.Println()
	for _, f := range over {
		for _, m := range rd.Metrics {
			if m.ID == f.Metric {
				fmt.Printf("perf_budget: %s 超阈（%d > %d，@ %s）\n", f.Counter, f.MaxCount, f.Limit, f.MaxFile)
				fmt.Printf("  ⇒ %s\n", m.OnExceed)
			}
		}
	}
	fmt.Println("perf_budget: FAIL——性能裁决的规模前提已失效")
	os.Exit(1)
}
