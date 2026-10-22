// corpus_fuzz——存量语料的对抗随机分叉防线（2026-10-18 立项，#183 深挖批同日制）。
//
// 动机：对抗分叉对拍挖虫效率实证（本日三波：探针六/七批邻面两虫 +
// C11 6.7.9p11 全线语法缺失），但对抗用例入库会污染语料域/freeze 面，
// 不入库又无回归防护——本驱动把「种子 = 存量语料 × 文本级变异算子」
// 的分叉对拍制度化：**CI 动态生成（不落库）+ 指纹基线锁定（已知分叉
// 豁免入库）+ 新指纹/桶恶化即红**。
//
// 判据：clang -O0 × vitro-native × vitro-js 三方对拍，分桶——
//
//	AGREE          三方一致（含双拒）
//	ARM_DIVERGENCE js/native 不一致（最高优先桶）
//	VITRO_REJECT   clang 接受而 vitro 拒（误拒面）
//	VITRO_TRAP     clang 正常而 vitro trap
//	WRONG_VALUE    输出不一致
//	CLANG_REJECT   clang 拒而 vitro 接受（误收面）
//
// 指纹 = "suite/seed|mutator" → bucket。fuzz_baseline.json 入库锁定
// （-freeze 生成；已知未修病条目带 issue 标注归档）；跑出**基线外指纹**
// （新种子入抽样/新算子）或**桶恶化**即 rc=1 fail loud——同桶内输出
// 字节变化不判红（值漂移由既有 digest 闸管，本闸只管桶级回归与新病）。
//
// 桶恶化序（低→高）：AGREE < CLANG_REJECT < VITRO_REJECT < VITRO_TRAP
// < WRONG_VALUE < ARM_DIVERGENCE——基线桶低、现桶高即红。
//
// 缓存：.corpus_fuzz_cache/（gitignored）存变体源；键 = 种子集合 hash
// + 规则 hash——键匹配时 gen 零成本复用，对拍恒真跑（被测物每次新）。
//
// 契约（生成器 -check 硬契约 skill）：flag 包；-freeze 落盘幂等；未知
// 规则键/未知算子名 fail loud；规则外置 rules.json（单源）。
package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

// ── 规则（rules.json 单源）──

type Rules struct {
	SeedsPerSuite   int             `json:"seeds_per_suite"`   // 每 suite 抽样种子数
	MutatorsPerSeed int             `json:"mutators_per_seed"` // 每种子应用算子数
	Seed            int64           `json:"seed"`              // 抽样种子（确定性复现）
	Mutators        []string        `json:"mutators"`
	Suites          []string        `json:"suites"`
	Generators      []GeneratorRule `json:"generators"` // 域生成器（2026-10-19：凭空造域对抗，与算子互补）
}

type GeneratorRule struct {
	Name  string `json:"name"`
	Count int    `json:"count"`
}

type BaselineEntry struct {
	Bucket string `json:"bucket"`
	Issue  string `json:"issue,omitempty"`
	Note   string `json:"note,omitempty"`
}

type Baseline struct {
	Entries map[string]BaselineEntry `json:"entries"`
}

const (
	runnerExe = "moonbit/_build/native/release/build/cmd/run/run.exe"
	vitroSh   = "scripts/bin/vitro"
	cacheDir  = ".corpus_fuzz_cache"
)

// ── 确定性随机 ──

type detRand struct{ state uint64 }

func (r *detRand) next() uint64 {
	r.state = r.state*6364136223846793005 + 1442695040888963407
	return r.state >> 33
}

func (r *detRand) intn(n int) int {
	if n <= 0 {
		return 0
	}
	return int(r.next() % uint64(n))
}

// ── 可用字符掩码（跳过注释与字符串/字符字面量区域的文本级变异前提）──

func codeMask(src string) []bool {
	m := make([]bool, len(src))
	i, n := 0, len(src)
	for i < n {
		c := src[i]
		switch {
		case c == '/' && i+1 < n && src[i+1] == '/':
			for i < n && src[i] != '\n' {
				i++
			}
		case c == '/' && i+1 < n && src[i+1] == '*':
			i += 2
			for i+1 < n && !(src[i] == '*' && src[i+1] == '/') {
				i++
			}
			i += 2
		case c == '"' || c == '\'':
			q := c
			m[i] = true // 引号本体可用（变异保守）
			i++
			for i < n && src[i] != q {
				if src[i] == '\\' {
					i++
				}
				i++
			}
			if i < n {
				i++
			}
		default:
			m[i] = true
			i++
		}
	}
	return m
}

// 掩码内查找子串
func indexMasked(src, sub string, m []bool, from int) int {
	for i := from; i+len(sub) <= len(src); i++ {
		if strings.HasPrefix(src[i:], sub) && m[i] && m[i+len(sub)-1] {
			return i
		}
	}
	return -1
}

func isIdentCh(b byte) bool {
	return b == '_' || (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z') || (b >= '0' && b <= '9')
}

// 首个裸十进制整数字面量（掩码内、非标识符中段、非预处理行）——
// 返回 [start,end)；找不到返 -1
func firstIntLit(src string, m []bool) (int, int) {
	lineStart := true
	for i := 0; i < len(src); i++ {
		if src[i] == '\n' {
			lineStart = true
			continue
		}
		if lineStart {
			j := i
			for j < len(src) && (src[j] == ' ' || src[j] == '\t') {
				j++
			}
			if j < len(src) && src[j] == '#' {
				for j < len(src) && src[j] != '\n' {
					j++
				}
				i = j - 1
				continue
			}
			lineStart = false
		}
		if !m[i] || (i > 0 && isIdentCh(src[i-1])) {
			continue
		}
		if src[i] >= '0' && src[i] <= '9' {
			j := i
			for j < len(src) && src[j] >= '0' && src[j] <= '9' {
				j++
			}
			if j >= len(src) || !isIdentCh(src[j]) {
				return i, j
			}
		}
	}
	return -1, -1
}

// ── 变异算子（无匹配 → 原样返回；对拍 AGREE，无害锁定）──

type mutator struct {
	name string
	fn   func(src string, r *detRand) string
}

func withMask(src string, f func(m []bool) string) string {
	return f(codeMask(src))
}

var mutators = []mutator{
	{"brace_wrap", func(src string, r *detRand) string {
		return withMask(src, func(m []bool) string {
			s, e := firstIntLit(src, m)
			if s < 0 {
				return src
			}
			// 前溯最近赋值号（同一行内、跳过空白）
			k := s - 1
			for k >= 0 && (src[k] == ' ' || src[k] == '\t') {
				k--
			}
			if k < 0 || src[k] != '=' || (k-1 >= 0 && src[k-1] == '=') {
				return src
			}
			return src[:k+1] + " {" + src[s:e] + "}" + src[e:]
		})
	}},
	{"char_escape", func(src string, r *detRand) string {
		m := codeMask(src)
		escapes := []string{`'\n'`, `'\''`, `'\"'`, `'\\'`, `'\t'`, `'\0'`}
		repl := escapes[r.intn(len(escapes))]
		for i := 0; i+3 <= len(src); i++ {
			if m[i] && src[i] == '\'' && src[i+2] == '\'' &&
				src[i+1] != '\\' && src[i+1] != '\'' {
				return src[:i] + repl + src[i+3:]
			}
		}
		return src
	}},
	{"init_partial", func(src string, r *detRand) string {
		// 首个多元素初始化列表去尾元素（部分填充面）
		m := codeMask(src)
		for i := 0; i < len(src); i++ {
			if !m[i] || src[i] != '{' || i+1 >= len(src) || !m[i+1] {
				continue
			}
			// 同行内找配对 '}'（仅处理单层扁平短列表）
			depth := 0
			j := i
			for ; j < len(src) && src[j] != '\n'; j++ {
				if !m[j] {
					continue
				}
				if src[j] == '{' {
					depth++
				} else if src[j] == '}' {
					depth--
					if depth == 0 {
						break
					}
				}
			}
			if j >= len(src) || depth != 0 {
				continue
			}
			inner := src[i+1 : j]
			comma := strings.LastIndex(inner, ",")
			if comma > 0 {
				return src[:i+1] + inner[:comma] + src[j:]
			}
		}
		return src
	}},
	{"static_inject", func(src string, r *detRand) string {
		// 函数体内首个 4 空格缩进的声明行加 static（#171/#179 面）
		lines := strings.Split(src, "\n")
		for idx, ln := range lines {
			t := strings.TrimLeft(ln, " ")
			if len(t) > 0 && t[0] != '/' && t[0] != '*' && t[0] != '#' &&
				strings.HasPrefix(ln, "    ") && !strings.HasPrefix(ln, "        ") &&
				(strings.HasPrefix(t, "int ") || strings.HasPrefix(t, "char ") ||
					strings.HasPrefix(t, "double ") || strings.HasPrefix(t, "long ")) {
				if strings.Contains(ln, "static") {
					continue
				}
				lines[idx] = "    static " + t
				return strings.Join(lines, "\n")
			}
		}
		return src
	}},
	{"brace_strip", func(src string, r *detRand) string {
		// #183 逆面：首个 `= {<int>}` 解包（单元素包裹 ≡ 裸形态）
		m := codeMask(src)
		for i := 0; i < len(src); i++ {
			if !m[i] || src[i] != '{' || i+1 >= len(src) || !m[i+1] {
				continue
			}
			j := strings.IndexByte(src[i:], '}')
			if j < 0 {
				break
			}
			inner := src[i+1 : i+j]
			t := strings.TrimSpace(inner)
			if t != "" && isAllDigits(t) {
				k := i - 1
				for k >= 0 && (src[k] == ' ' || src[k] == '	') {
					k--
				}
				if k >= 0 && src[k] == '=' {
					return src[:i+1] + t + src[i+j:]
				}
			}
			i += j
		}
		return src
	}},
	{"nested2flat", func(src string, r *detRand) string {
		// #179/#180 等价变换：嵌套 {{a,b},{c,d}} 拍平（brace elision
		// 两侧语义必须同值——任何分叉 = elision 实现病）
		m := codeMask(src)
		for i := 0; i+1 < len(src); i++ {
			if !m[i] || src[i] != '{' || src[i+1] != '{' {
				continue
			}
			// 找本组配对外层 '}'
			depth := 0
			j := i
			for ; j < len(src); j++ {
				if !m[j] {
					continue
				}
				if src[j] == '{' {
					depth++
				} else if src[j] == '}' {
					depth--
					if depth == 0 {
						break
					}
				}
			}
			if j >= len(src) || depth != 0 {
				continue
			}
			inner := src[i+1 : j]
			flat := strings.Map(func(c rune) rune {
				if c == '{' || c == '}' {
					return -1
				}
				return c
			}, inner)
			return src[:i+1] + flat + src[j:]
		}
		return src
	}},
	{"memset_zero", func(src string, r *detRand) string {
		// 首个 `{0}` 整体初始化展开为 `{0,0,0}`（#19 零初始化族邻面）
		m := codeMask(src)
		idx := indexMasked(src, "= {0}", m, 0)
		if idx < 0 {
			return src
		}
		return src[:idx] + "= {0, 0, 0}" + src[idx+5:]
	}},

	// ── 第二批算子（2026-10-18 存量语料形态域盘点补充）：
	// 等价变换类（换向/换写法——两侧应同值，任何分叉 = 引擎病） +
	// 域扩张类（宽度/符号/精度/邻界——暴露窄化/提升/位模式缺陷）──

	{"cmp_swap", func(src string, r *detRand) string {
		// 首个比较换向：`a < b` → `b > a`（等价变换）
		m := codeMask(src)
		for _, op := range []string{" <= ", " >= ", " < ", " > "} {
			rev := map[string]string{" < ": " > ", " > ": " < ", " <= ": " >= ", " >= ": " <= "}[op]
			j := indexMasked(src, op, m, 0)
			if j < 0 {
				continue
			}
			a, b := j-1, j+len(op)
			for a > 0 && !isSep(src[a-1]) {
				a--
			}
			for b < len(src) && !isSep(src[b]) {
				b++
			}
			if a < j && b > j+len(op) {
				return src[:a] + src[j+len(op):b] + rev + src[a:j] + src[b:]
			}
		}
		return src
	}},
	{"div2shift", func(src string, r *detRand) string {
		// 首个 `/ 2` → `>> 1`（负数域：-3/2=-1 vs -3>>1=-2——两侧
		// 应同现此差，任何额外分叉 = 引擎病）
		m := codeMask(src)
		idx := indexMasked(src, "/ 2", m, 0)
		if idx < 0 {
			return src
		}
		return src[:idx] + ">> 1" + src[idx+3:]
	}},
	{"paren_wrap", func(src string, r *detRand) string {
		// 首个二元算术段加括号（解析等价）
		m := codeMask(src)
		for _, op := range []string{" + ", " - ", " * "} {
			j := indexMasked(src, op, m, 0)
			if j < 0 {
				continue
			}
			a, b := j-1, j+len(op)
			for a > 0 && !isSep(src[a-1]) {
				a--
			}
			for b < len(src) && !isSep(src[b]) {
				b++
			}
			if a < j && b > j+len(op) {
				return src[:a] + "(" + src[a:b] + ")" + src[b:]
			}
		}
		return src
	}},
	{"cast_strip", func(src string, r *detRand) string {
		// 首个单类型 cast 剥除（显式转隐式应同值）
		m := codeMask(src)
		for _, t := range []string{"(int)", "(char)", "(double)", "(long)", "(unsigned)"} {
			j := indexMasked(src, t, m, 0)
			if j < 0 {
				continue
			}
			return src[:j] + src[j+len(t):]
		}
		return src
	}},
}

// 裸类型声明替换首处（跳过 unsigned/long/short 前缀语境与标识符中段）
func replaceFirstBareType(src, from, to string) string {
	m := codeMask(src)
	idx := indexMasked(src, from, m, 0)
	for idx >= 0 {
		pre := ""
		if idx >= 9 {
			pre = src[idx-9 : idx]
		}
		if !strings.HasSuffix(pre, "unsigned ") && !strings.HasSuffix(pre, "long ") &&
			!strings.HasSuffix(pre, "short ") && (idx == 0 || !isIdentCh(src[idx-1])) {
			return src[:idx] + to + src[idx+len(from):]
		}
		idx = indexMasked(src, from, m, idx+1)
	}
	return src
}

func isAllDigits(s string) bool {
	if s == "" {
		return false
	}
	for i := 0; i < len(s); i++ {
		if s[i] < '0' || s[i] > '9' {
			return false
		}
	}
	return true
}

func isSep(b byte) bool {
	return b == ' ' || b == '\t' || b == '\n' || b == '\r' || b == ';' ||
		b == ',' || b == '(' || b == ')' || b == '{' || b == '}' ||
		b == '[' || b == ']' || b == '=' || b == '<' || b == '>' ||
		b == '+' || b == '-' || b == '*' || b == '/' || b == '%'
}

func mutatorByName(name string) (mutator, bool) {
	for _, mu := range mutators {
		if mu.name == name {
			return mu, true
		}
	}
	return mutator{}, false
}

// ── 进程对拍 ──

type outcome struct {
	status string // OK / REJECT / TRAP / CRASH
	out    string
}

func norm(s string) string {
	return strings.ReplaceAll(strings.ReplaceAll(s, "\r\n", "\n"), "\r", "")
}

func runCmd(args []string, dir string) (string, string, int) {
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, args[0], args[1:]...)
	cmd.Dir = dir
	// 显式空 stdin（Windows 上 nil = 继承父句柄——scanf 族变体会挂死
	// 等终端输入，freeze 17min 不归实锤）；空管道 = 立即 EOF（batch 口径）
	cmd.Stdin = bytes.NewReader(nil)
	var ob, eb strings.Builder
	cmd.Stdout = &ob
	cmd.Stderr = &eb
	rc := 0
	if err := cmd.Run(); err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			rc = ee.ExitCode()
		} else {
			rc = -98 // 超时/无法启动（ctx deadline）——单例有界
		}
	}
	return ob.String(), eb.String(), rc
}

// exeBase：可执行目录查找（本地 Git Bash 有 clang；CI windows 也有）
// 槽位隔离（2026-10-22，CI 39800866009 三红根）：变异体程序此前以仓库根
// 为 cwd 运行——写文件的语料把 test.txt 落回根域，后续 freeze 轮在污染
// 环境入账 AGREE 假象、CI 干净检出真值 WRONG_VALUE 桶恶化红（file_fopen/
// fread 族两连坐）。运行 cwd 改 workdir（=cacheDir，KEY 漂移时整体清）：
// 变异体间的顺序文件耦合消除、本地与 CI 同判（clang_direct P1-1 同款）。
func clangOutcome(src string, workdir string) outcome {
	exe := filepath.Join(workdir, "a.exe")
	_, errtxt, rc := runCmd([]string{"clang", "-O0", src, "-o", exe}, ".")
	if rc != 0 {
		// 编译失败重试（clang_direct 同判据，2026-10-22 CI 39800866009）：
		// Defender 实时扫描锁 a.exe 令 clang 非零退出（calloc_basic|
		// paren_wrap 的 CI CLANG_REJECT 瞬态形态）——1s/2s 退避重试 2 次
		// 仍失败才接受（真确定性失败只多花 3s）
		for attempt := 0; attempt < 2; attempt++ {
			time.Sleep(time.Duration(1000<<attempt) * time.Millisecond)
			_, errtxt, rc = runCmd(
				[]string{"clang", "-O0", src, "-o", exe},
				".",
			)
			if rc == 0 {
				break
			}
		}
	}
	if rc != 0 {
		return outcome{"REJECT", norm(errtxt)}
	}
	out, _, rc2 := runCmd([]string{absPath(exe)}, workdir)
	os.Remove(exe)
	if rc2 != 0 {
		// 崩溃域（Windows 异常码，如 0xC0000005≈3.2e9）与合法非零 return
		//（main 返回 0..255）区分——合法 return 保留 stdout 并入比对（与
		// vitro 口径对齐：退出码本就不进比对）。此前一切非零都丢 stdout
		// 只留 EXIT 码，合法 `return 3` 的程序被误判 WRONG_VALUE（假阳性
		// 实锤：strcpy_retval_chain|init_partial 三方 stdout 实为逐字节一致）。
		if rc2 > 255 || rc2 < 0 {
			return outcome{"OK", "EXIT:" + strconv.Itoa(rc2)}
		}
		return outcome{"OK", norm(out)}
	}
	return outcome{"OK", norm(out)}
}

// vitroNative：直接 spawn run.exe（同 vm_diff 产物通道）
func vitroNative(src string) outcome {
	out, _, _ := runCmd([]string{runnerExe, src, "--json"}, ".")
	return parseVitro(out)
}

// vitroJs：统一入口壳（sh scripts/bin/vitro）
func vitroJs(src string) outcome {
	out, _, _ := runCmd([]string{"sh", vitroSh, "run", src, "--json"}, ".")
	return parseVitro(out)
}

func parseVitro(ndjson string) outcome {
	diagOK, stdout, status, trap := "", "", "", ""
	for _, line := range strings.Split(ndjson, "\n") {
		line = strings.TrimSpace(line)
		if !strings.HasPrefix(line, "{") {
			continue
		}
		var f struct {
			Type  string `json:"type"`
			Frame struct {
				Result struct {
					OK          bool   `json:"ok"`
					Delta       string `json:"delta"`
					Status      string `json:"status"`
					Trap        string `json:"trap"`
					Diagnostics []struct {
						Severity string `json:"severity"`
					} `json:"diagnostics"`
				} `json:"result"`
			} `json:"frame"`
		}
		if err := json.Unmarshal([]byte(line), &f); err != nil {
			continue
		}
		switch f.Type {
		case "diag":
			diagOK = "ok"
			if !f.Frame.Result.OK {
				diagOK = "reject"
			}
		case "stdout":
			// CI 红（2026-10-22，master a7202d19 后抽样轮换首触）：JSON delta
			// 出口把程序 stdout 的单字节 0x80–0xFF 按 Latin-1 码点转义（\u0085），
			// Go json.Unmarshal 解码成 U+0085 双字节——与 clang 侧原始单字节量纲
			// 不等，#172 锚（stdout_c1_byte_0x85）基线即被误判 WRONG_VALUE。
			// U+0080–U+00FF 折回 Latin-1 单字节（封闭域无损可逆——#66 在
			// clang_direct 退役的 latin1Fold 同款语义，此处 JSON 通道语境启用）。
			stdout = latin1Fold(f.Frame.Result.Delta)
		case "run":
			status = f.Frame.Result.Status
			trap = f.Frame.Result.Trap
		}
	}
	if diagOK == "reject" {
		return outcome{"REJECT", ""}
	}
	if diagOK == "" {
		return outcome{"CRASH", ""}
	}
	if status == "trap" {
		return outcome{"TRAP", trap}
	}
	return outcome{"OK", norm(stdout)}
}

// bucketOf：三方分类
func bucketOf(c, nj, na outcome) string {
	if nj.status == "OK" && na.status == "OK" && nj.out != na.out {
		return "ARM_DIVERGENCE"
	}
	vt := nj
	if vt.status == "OK" && na.status != "OK" {
		vt = na
	} else if vt.status != "OK" && na.status == "OK" {
		vt = na
	}
	if c.status == "REJECT" {
		if vt.status == "REJECT" {
			return "AGREE"
		}
		return "CLANG_REJECT"
	}
	switch vt.status {
	case "REJECT":
		return "VITRO_REJECT"
	case "TRAP":
		return "VITRO_TRAP"
	case "CRASH":
		return "ARM_DIVERGENCE"
	}
	if vt.out == c.out {
		return "AGREE"
	}
	return "WRONG_VALUE"
}

var bucketRank = map[string]int{
	"AGREE": 0, "CLANG_REJECT": 1, "VITRO_REJECT": 2,
	"VITRO_TRAP": 3, "WRONG_VALUE": 4, "ARM_DIVERGENCE": 5,
}

// ── 主流程 ──

func die(format string, a ...any) {
	fmt.Fprintf(os.Stderr, "corpus_fuzz: "+format+"\n", a...)
	os.Exit(2)
}

func main() {
	freeze := flag.Bool("freeze", false, "首跑基线落盘（fuzz_baseline.json）")
	rulesPath := flag.String("rules", "scripts/corpus_fuzz/rules.json", "规则文件")
	basePath := flag.String("baseline", "scripts/corpus_fuzz/fuzz_baseline.json", "基线文件")
	regen := flag.Bool("regen", false, "强制重新生成变体（忽略缓存键）")
	probe := flag.String("probe", "", "单例探针：打印该变体三方解析现场（调试管道）")
	flag.Parse()
	if *probe != "" {
		c := clangOutcome(*probe, cacheDir)
		nj := vitroJs(*probe)
		na := vitroNative(*probe)
		fmt.Printf("clang: %s|%q\n", c.status, c.out)
		fmt.Printf("js:    %s|%q\n", nj.status, nj.out)
		fmt.Printf("native:%s|%q\n", na.status, na.out)
		fmt.Printf("bucket: %s\n", bucketOf(c, nj, na))
		return
	}

	ruleBytes, err := os.ReadFile(*rulesPath)
	if err != nil {
		die("读规则失败：%v", err)
	}
	var rules Rules
	if err := json.Unmarshal(ruleBytes, &rules); err != nil {
		die("规则 JSON 解析失败：%v", err)
	}
	for _, mn := range rules.Mutators {
		if _, ok := mutatorByName(mn); !ok {
			die("未知算子名 %q（规则与实现失配——fail loud）", mn)
		}
	}

	// 种子收集 + 确定性抽样
	type seedFile struct{ suite, name, path string }
	var seeds []seedFile
	for _, suite := range rules.Suites {
		dir := filepath.Join("corpus", suite)
		ents, err := os.ReadDir(dir)
		if err != nil {
			die("读套件 %s 失败：%v", suite, err)
		}
		for _, e := range ents {
			if strings.HasSuffix(e.Name(), ".c") {
				seeds = append(seeds, seedFile{suite, e.Name(), filepath.Join(dir, e.Name())})
			}
		}
	}
	sort.Slice(seeds, func(i, j int) bool { return seeds[i].path < seeds[j].path })
	pick := make([]seedFile, 0, len(seeds))
	bySuite := map[string][]seedFile{}
	for _, s := range seeds {
		bySuite[s.suite] = append(bySuite[s.suite], s)
	}
	for _, suite := range rules.Suites {
		list := bySuite[suite]
		r := &detRand{uint64(rules.Seed) + 0x9e3779b9}
		if rules.SeedsPerSuite >= len(list) {
			pick = append(pick, list...)
			continue
		}
		chosen := map[int]bool{}
		for len(chosen) < rules.SeedsPerSuite {
			chosen[r.intn(len(list))] = true
		}
		for i := range list {
			if chosen[i] {
				pick = append(pick, list[i])
			}
		}
	}
	sort.Slice(pick, func(i, j int) bool { return pick[i].path < pick[j].path })

	// 缓存键：种子集合 + 规则内容
	keySrc := []byte{}
	for _, s := range pick {
		keySrc = append(keySrc, []byte(s.path)...)
	}
	keySrc = append(keySrc, ruleBytes...)
	sum := sha256.Sum256(keySrc)
	cacheKey := hex.EncodeToString(sum[:12])
	keyFile := filepath.Join(cacheDir, "KEY")
	if !*regen {
		if b, err := os.ReadFile(keyFile); err == nil && strings.TrimSpace(string(b)) == cacheKey {
			fmt.Printf("gen：缓存命中（key=%s）——变体复用\n", cacheKey)
		}
	} else {
		_ = os.RemoveAll(cacheDir)
	}
	if _, err := os.Stat(keyFile); err != nil {
		_ = os.MkdirAll(cacheDir, 0o755)
		_ = os.WriteFile(keyFile, []byte(cacheKey), 0o644)
	}

	// 生成（或复用）+ 对拍 + 基线比对
	// 基线载入（freeze 同样读旧——合并语义：#177/#198 两批 freeze 整文件
	// 重写冲掉 43 条人工定性标注实锤；抽样集随语料数轮换，未抽到的历史
	// 条目必须留存，否则轮换回来又成「新指纹」且标注永久丢失）
	var base Baseline
	base.Entries = map[string]BaselineEntry{}
	if bb, err := os.ReadFile(*basePath); err == nil {
		if err := json.Unmarshal(bb, &base); err != nil {
			die("基线 JSON 解析失败：%v", err)
		}
	} else if !*freeze {
		die("基线缺失（首跑用 -freeze 生成）：%v", err)
	}

	newFp, worsened, agree, total := 0, 0, 0, 0
	var report []string
	for _, s := range pick {
		srcBytes, err := os.ReadFile(s.path)
		if err != nil {
			die("读种子失败 %s：%v", s.path, err)
		}
		src := string(srcBytes)
		// 每种子确定性取 MutatorsPerSeed 个算子
		r := &detRand{uint64(rules.Seed) + uint64(len(s.path))}
		pool := append([]string{}, rules.Mutators...)
		for i := len(pool) - 1; i > 0; i-- {
			j := r.intn(i + 1)
			pool[i], pool[j] = pool[j], pool[i]
		}
		if len(pool) > rules.MutatorsPerSeed {
			pool = pool[:rules.MutatorsPerSeed]
		}
		for _, mname := range pool {
			mu, _ := mutatorByName(mname)
			if os.Getenv("CF_TRACE") != "" {
				fmt.Println("TRACE:", s.suite+"/"+s.name, mname)
			}
			mut := mu.fn(src, r)
			total++
			fp := s.suite + "/" + s.name + "|" + mname
			// 变体名必须带 .c 后缀（clang 按扩展名识别输入——无后缀
			// unknown file type 假 REJECT，首跑 84% 假阳性实锤）
			stem := strings.TrimSuffix(s.name, ".c")
			variant := filepath.Join(cacheDir, fmt.Sprintf("%s_%s_%s.c", s.suite, stem, mname))
			if err := os.WriteFile(variant, []byte(mut), 0o644); err != nil {
				die("写变体失败：%v", err)
			}
			c := clangOutcome(variant, cacheDir)
			nj := vitroJs(variant)
			na := vitroNative(variant)
			bucket := bucketOf(c, nj, na)
			if bucket == "AGREE" {
				agree++
			}
			if *freeze {
				// 合并语义：只更新桶，保留人工定性标注（issue/note）
				old := base.Entries[fp]
				base.Entries[fp] = BaselineEntry{
					Bucket: bucket, Issue: old.Issue, Note: old.Note,
				}
				continue
			}
			ent, ok := base.Entries[fp]
			if !ok {
				newFp++
				report = append(report, fmt.Sprintf("  新指纹 %s → %s", fp, bucket))
				continue
			}
			if bucketRank[bucket] > bucketRank[ent.Bucket] {
				worsened++
				report = append(report, fmt.Sprintf("  桶恶化 %s：%s → %s", fp, ent.Bucket, bucket))
			}
		}
	}

	// ── 域生成器段（2026-10-19 收编）：凭空造域 × 确定性随机参数——
	// 覆盖「修复域无存量语料」的对抗盲区。键空间 gen:<域名>/<序号> 与
	// 算子段互斥；对拍/桶/收编路径与算子段完全共用。
	for _, gr := range rules.Generators {
		gen, ok := generatorByName(gr.Name)
		if !ok {
			die("未知生成器名 %q（规则与实现失配——fail loud）", gr.Name)
		}
		for i := 0; i < gr.Count; i++ {
			// 域内独立确定性：同规则 hash 同产物（缓存键掺 ruleBytes 已含）
			r := &detRand{uint64(rules.Seed)*0x9e3779b9 + uint64(len(gr.Name))*31 + uint64(i)}
			src := gen.fn(r, i)
			total++
			fp := fmt.Sprintf("gen:%s/%03d", gr.Name, i)
			variant := filepath.Join(cacheDir, fmt.Sprintf("gen_%s_%03d.c", gr.Name, i))
			if err := os.WriteFile(variant, []byte(src), 0o644); err != nil {
				die("写生成变体失败：%v", err)
			}
			c := clangOutcome(variant, cacheDir)
			nj := vitroJs(variant)
			na := vitroNative(variant)
			bucket := bucketOf(c, nj, na)
			if bucket == "AGREE" {
				agree++
			}
			if *freeze {
				old := base.Entries[fp]
				base.Entries[fp] = BaselineEntry{
					Bucket: bucket, Issue: old.Issue, Note: old.Note,
				}
				continue
			}
			ent, ok := base.Entries[fp]
			if !ok {
				newFp++
				report = append(report, fmt.Sprintf("  新指纹 %s → %s", fp, bucket))
				continue
			}
			if bucketRank[bucket] > bucketRank[ent.Bucket] {
				worsened++
				report = append(report, fmt.Sprintf("  桶恶化 %s：%s → %s", fp, ent.Bucket, bucket))
			}
		}
	}

	if *freeze {
		ob, _ := json.MarshalIndent(base, "", "  ")
		if err := os.WriteFile(*basePath, append(ob, '\n'), 0o644); err != nil {
			die("基线落盘失败：%v", err)
		}
		fmt.Printf("corpus_fuzz -freeze：基线落盘 %d 条 → %s\n", len(base.Entries), *basePath)
		return
	}

	fmt.Printf("corpus_fuzz：total=%d AGREE=%d 新指纹=%d 桶恶化=%d\n",
		total, agree, newFp, worsened)
	for _, l := range report {
		fmt.Println(l)
	}
	if newFp > 0 || worsened > 0 {
		fmt.Println("FAIL——新指纹须人工定性后 -freeze 收编（已知未修病带 issue 标注）；桶恶化=回归")
		os.Exit(1)
	}
	fmt.Println("corpus_fuzz: PASS——无新指纹、无桶恶化")
}

// latin1Fold：UTF-8 的 U+0080–U+00FF 双字节序折回 Latin-1 单字节（自
// clang_direct 迁入——#66 在彼处随出口字节直通退役，本 JSON 通道消费
// 侧重启用：程序 stdout 是字节流，经 JSON delta 码点域须折回字节域再比）。
func latin1Fold(s string) string {
	var b bytes.Buffer
	b.Grow(len(s))
	for i := 0; i < len(s); {
		c := s[i]
		if c == 0xC2 && i+1 < len(s) {
			b.WriteByte(s[i+1]) // C2 80..BF → 80..BF
			i += 2
			continue
		}
		if c == 0xC3 && i+1 < len(s) {
			b.WriteByte(s[i+1] + 0x40) // C3 80..BF → C0..FF
			i += 2
			continue
		}
		b.WriteByte(c)
		i++
	}
	return b.String()
}

// absPath：相对路径绝对化（槽位隔离后 exe 以 workdir 为 cwd 启动——
// 相对 exe 路径会在新 cwd 下解析失败，212 键假 WRONG_VALUE 实锤）。
func absPath(p string) string {
	if filepath.IsAbs(p) {
		return p
	}
	a, err := filepath.Abs(p)
	if err != nil {
		return p
	}
	return a
}
