// vitro_clang_diff —— TheAlgorithms/C(fork)逐文件 Vitro vs Clang 对比勘探
//
// 纪律: flag 包 / fail loud / 零第三方依赖 / 判定型默认 Go(AGENTS.md 全域纪律 8)。
// 产物: <out>/report.md + <out>/result.json —— 产物不进 Vitro 仓库(协议污染红线:
//
//	result.json 的诊断 message 可引用源码 token; 本仓只收测量签名 gold_signatures.json)。
//
// 三种模式:
//
//	勘探:  -repo <fork克隆> -out <目录>            全量对比(需 Clang+Vitro serve exe)
//	聚合:  -aggregate <result.json>                result → gold_signatures.json(只取码计数,
//	                                                不透传诊断 message——GPL 红线)
//	合规:  -check                                     仓内 gold_signatures.json 格式+渗漏扫描
//	                                                (CI hygiene; 不跑勘探本身)
//
// provenance 锚: 上游 TheAlgorithms/C@e5dad3f(2023-09 终态) → fork
//
//	rustin-beep/C 分支 vitro-probe-baseline(89 文件探针态——补 include/反注释
//	struct 模板)。gold_signatures.json 基线 = 该分支态的测量。
//
// 流程(坑位固化自 2026-10-01 实机审阅批次 batch11~22):
//
//	P1 walk *.c → P2 Clang 真值(-std=c11 -Wall -Wextra -fsyntax-only, 15s)
//	→ P3 Vitro serve 连发(JSON-lines; 拿带码诊断+W 警告——cmd/run 丢警告的坑)
//	→ P4 剥壳重试(仅 Vitro 红桶; stdbool→#define bool int+true/false——true 漏定义坑)
//	→ P5 双绿桶运行对比(Clang 编译运行 vs moon run cmd/run; 输出 Latin-1 还原+归一——
//	   Latin-1 通道坑; rand( 含文件标 rand-diff 预期; client_server 网络目录跳运行——挂起坑)
//	→ P6 报告(分桶/码 top/层分布/W 清单/运行对比)。
//
// 用法: go run vitro_clang_diff.go -repo D:/code/C -out _diff_out [-filter cipher/] [-limit N]
package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

type Diag struct {
	Severity string `json:"severity"`
	Code     string `json:"code"`
	Line     int    `json:"line"`
	Column   int    `json:"column"`
	Message  string `json:"message"`
}

type FileResult struct {
	Path       string `json:"path"`
	ClangOK    bool   `json:"clang_ok"`
	ClangErrs  int    `json:"clang_errors"`
	ClangWarns int    `json:"clang_warnings"`
	ClangFirst string `json:"clang_first_error,omitempty"`
	VitroDiags []Diag `json:"vitro_diags,omitempty"`
	VitroErrs  int    `json:"vitro_errors"`
	VitroWarns int    `json:"vitro_warnings"`
	Layer      string `json:"vitro_layer,omitempty"` // ok/lex/parse/typeck
	Stripped   bool   `json:"stripped_try"`
	StripLayer string `json:"strip_layer,omitempty"`
	StripErrs  int    `json:"strip_errors,omitempty"`
	RunCmp     string `json:"run_compare,omitempty"` // match/mismatch/clang_only/vitro_only/timeout/skip_net/rand_diff
	RunDetail  string `json:"run_detail,omitempty"`
}

var (
	flagRepo   = flag.String("repo", "", "外部 C 仓库根(必填)")
	flagOut    = flag.String("out", "_diff_out", "输出目录(仓库外)")
	flagFilter = flag.String("filter", "", "路径子串过滤")
	flagLimit  = flag.Int("limit", 0, "最多处理文件数, 0=全部")
	flagBatch  = flag.Int("batch", 25, "serve 连发批大小")
	flagVitro  = flag.String("vitro", "D:/code/Vitro", "Vitro 仓库根(serve/cwd)")
	flagAgg    = flag.String("aggregate", "", "聚合模式: 输入 result.json 路径, 产 gold_signatures.json")
	flagCheck  = flag.Bool("check", false, "合规模式: 校验仓内 gold_signatures.json(格式+无源码文本渗漏)")
)

func fail(format string, a ...any) {
	fmt.Fprintf(os.Stderr, "FATAL: "+format+"\n", a...)
	os.Exit(2)
}

// ---------- P2: Clang 真值 ----------
func clangCheck(path string) (ok bool, errs, warns int, first string) {
	cmd := exec.Command("clang", "-std=c11", "-Wall", "-Wextra", "-fsyntax-only", path)
	out, err := runWithTimeout(cmd, 15*time.Second)
	if err != nil && !strings.Contains(out, "error") && !strings.Contains(out, "warning") {
		return false, 1, 0, "clang 执行失败: " + err.Error() // 工具层失败(如缺头/链接需求在 syntax-only 不发生)
	}
	for _, l := range strings.Split(out, "\n") {
		if strings.Contains(l, "error:") {
			errs++
			if first == "" {
				first = strings.TrimSpace(l)
			}
		} else if strings.Contains(l, "warning:") && !strings.Contains(l, "_CRT_SECURE") && !strings.Contains(l, "deprecated") {
			warns++
		}
	}
	return errs == 0, errs, warns, first
}

func runWithTimeout(cmd *exec.Cmd, d time.Duration) (string, error) {
	var out strings.Builder
	cmd.Stdout = &out
	cmd.Stderr = &out
	if err := cmd.Start(); err != nil {
		return out.String(), err
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	select {
	case <-time.After(d):
		cmd.Process.Kill()
		return out.String(), fmt.Errorf("timeout %v", d)
	case e := <-done:
		return out.String(), e
	}
}

// ---------- P3: Vitro serve 连发(keys 与 paths 一一对应) ----------
func serveBatchKeys(_ string, keys, paths []string) (map[string][]Diag, error) {
	res := map[string][]Diag{}
	cmd := exec.Command("moon", "run", "--target", "native", "moonbit/cmd/serve")
	cmd.Dir = *flagVitro // moon 必须在 Vitro 仓库根运行
	stdin, _ := cmd.StdinPipe()
	stdout, _ := cmd.StdoutPipe()
	if err := cmd.Start(); err != nil {
		return nil, fmt.Errorf("serve 启动失败(检查 moon/cwd): %w", err)
	}
	payload := &strings.Builder{}
	for i, p := range paths {
		src, e := os.ReadFile(p)
		if e != nil {
			return nil, e
		}
		payload.WriteString(fmt.Sprintf(`{"id":%d,"method":"compile","params":{"source":%s}}`+"\n", i+1, mustJSON(string(src))))
	}
	go func() {
		stdin.Write([]byte(payload.String()))
		stdin.Close()
	}()
	sc := bufio.NewScanner(stdout)
	sc.Buffer(make([]byte, 1024*1024), 64*1024*1024)
	got := 0
	for sc.Scan() && got < len(keys) {
		line := strings.TrimSpace(sc.Text())
		if !strings.HasPrefix(line, "{") {
			continue
		}
		var resp struct {
			ID     int `json:"id"`
			Result struct {
				Diagnostics []Diag `json:"diagnostics"`
			} `json:"result"`
		}
		if e := json.Unmarshal([]byte(line), &resp); e != nil {
			continue
		}
		if resp.ID-1 >= 0 && resp.ID-1 < len(keys) {
			res[keys[resp.ID-1]] = resp.Result.Diagnostics
			got++
		}
	}
	cmd.Process.Kill()
	if got < len(keys) {
		return res, fmt.Errorf("serve 响应不足: %d/%d", got, len(keys))
	}
	return res, nil
}

func mustJSON(s string) string {
	b, _ := json.Marshal(s)
	return string(b)
}

// ---------- P4: 剥壳(stdbool→int + true/false; 教训: 漏 true/false Clang 必红) ----------
var stripRe = regexp.MustCompile(`(?m)^(\s*)#include <stdbool\.h>`)

func stripStdbool(src string) (string, bool) {
	if !strings.Contains(src, "#include <stdbool.h>") {
		return src, false
	}
	out := stripRe.ReplaceAllString(src, "$1#define bool int\n$1#define true 1\n$1#define false 0")
	return out, true
}

// ---------- 层判定(码段粗分: E1xxx=lex/常量 E2xxx=parse E3xxx=typeck) ----------
func layerOf(diags []Diag) string {
	layer := "ok"
	for _, d := range diags {
		if d.Severity != "error" || len(d.Code) < 2 {
			continue
		}
		switch {
		case strings.HasPrefix(d.Code, "E1"):
			if layer == "ok" || layer == "parse" || layer == "typeck" {
				layer = "lex"
			}
		case strings.HasPrefix(d.Code, "E2"):
			if layer == "ok" || layer == "typeck" {
				layer = "parse"
			}
		case strings.HasPrefix(d.Code, "E3"):
			layer = "typeck"
		}
	}
	return layer
}

// ---------- P5: 运行对比 ----------
var ansiRe = regexp.MustCompile(`\033\[[0-9;]*m`)

func normalize(b []byte) []byte {
	b = ansiRe.ReplaceAll(b, nil)
	b = regexp.MustCompile(`(?m)// EXIT \d+\s*$`).ReplaceAll(b, nil)
	// 过滤 moon 工具链 Warning 块(冷缓存重编译时混进 stdout; 增量缓存时不出现)
	warnBlock := regexp.MustCompile(`(?m)^Warning: \[\d+\][\s\S]*?─{5,}╯\s*$`)
	b = warnBlock.ReplaceAll(b, nil)
	var kept []string
	for _, l := range strings.Split(string(b), "\n") {
		t := strings.TrimSpace(l)
		if strings.HasPrefix(t, "Warning") || strings.HasPrefix(t, "╭─") || strings.HasPrefix(t, "│") || strings.HasPrefix(t, "╰") {
			continue
		}
		kept = append(kept, strings.TrimRight(l, " \t\r"))
	}
	return []byte(strings.TrimSpace(strings.Join(kept, "\n")))
}

func latin1Restore(path string) []byte {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	s := string(raw)
	out := make([]byte, 0, len(s))
	for _, ch := range s {
		if ch < 256 {
			out = append(out, byte(ch))
		} else {
			out = append(out, '?')
		}
	}
	return out
}

func runCompare(repoRoot, cfile, tmpDir string, skipNet, hasRand bool) (verdict, detail string) {
	if skipNet {
		return "skip_net", "网络程序跳过运行"
	}
	// Clang 侧
	exe := filepath.Join(tmpDir, "a.exe")
	build := exec.Command("clang", "-std=c11", "-O2", "-o", exe, cfile)
	if out, err := runWithTimeout(build, 30*time.Second); err != nil {
		return "clang_build_fail", firstLine(out + " | err=" + err.Error())
	}
	cr := exec.Command(exe)
	cr.Dir = tmpDir
	cout, err := runWithTimeout(cr, 10*time.Second)
	if err != nil {
		if strings.Contains(err.Error(), "timeout") {
			return "clang_timeout", ""
		}
		return "clang_run_fail", fmt.Sprintf("%v | out=%s", err, firstLine(cout))
	}
	// Vitro 侧
	vr := exec.Command("moon", "run", "--target", "native", "moonbit/cmd/run", "--", cfile)
	vr.Dir = *flagVitro
	voutRaw, err := runWithTimeout(vr, 120*time.Second)
	if err != nil {
		if strings.Contains(err.Error(), "timeout") {
			return "vitro_timeout", ""
		}
		return "vitro_run_fail", firstLine(voutRaw)
	}
	// 落盘走 Latin-1 还原(cmd/run 通道坑) —— 经由临时文件
	tmp := filepath.Join(tmpDir, "vout.txt")
	os.WriteFile(tmp, []byte(voutRaw), 0644)
	vbytes := latin1Restore(tmp)
	vn := normalize(vbytes)
	cn := normalize([]byte(cout))
	if hasRand {
		if vnEqualIgnoreDigits(vn, cn) {
			return "rand_diff_match", "rand 驱动行外一致"
		}
		return "rand_diff", fmt.Sprintf("rand 序列差异(允许): V %dB / C %dB", len(vn), len(cn))
	}
	if string(vn) == string(cn) {
		return "match", fmt.Sprintf("输出逐字节一致(%dB)", len(cn))
	}
	return "mismatch", fmt.Sprintf("输出不一致: V %dB / C %dB", len(vn), len(cn))
}

func vnEqualIgnoreDigits(a, b []byte) bool {
	re := regexp.MustCompile(`\d+`)
	return string(re.ReplaceAll(a, []byte("#"))) == string(re.ReplaceAll(b, []byte("#")))
}

func firstLine(s string) string {
	s = strings.TrimSpace(s)
	if i := strings.Index(s, "\n"); i > 0 {
		s = s[:i]
	}
	if len(s) > 120 {
		s = s[:120]
	}
	return s
}

// ---------- main ----------
func main() {
	flag.Parse()
	if *flagCheck {
		os.Exit(runCheck())
	}
	if *flagAgg != "" {
		os.Exit(runAggregate(*flagAgg))
	}
	if *flagRepo == "" {
		fail("必填 -repo（或用 -aggregate/-check 模式）")
	}
	os.MkdirAll(*flagOut, 0755)

	// P1 walk
	var all []string
	filepath.Walk(*flagRepo, func(p string, info os.FileInfo, e error) error {
		if e == nil && strings.HasSuffix(p, ".c") {
			all = append(all, p)
		}
		return nil
	})
	sort.Strings(all)
	if *flagFilter != "" {
		var f []string
		for _, p := range all {
			if strings.Contains(filepath.ToSlash(p), *flagFilter) {
				f = append(f, p)
			}
		}
		all = f
	}
	if *flagLimit > 0 && len(all) > *flagLimit {
		all = all[:*flagLimit]
	}
	fmt.Fprintf(os.Stderr, "文件数: %d\n", len(all))

	repoAbs, _ := filepath.Abs(*flagRepo)
	results := make([]FileResult, 0, len(all))
	tmpDirAbs, _ := filepath.Abs(filepath.Join(*flagOut, "_tmp"))
	tmpDir := tmpDirAbs
	os.MkdirAll(tmpDir, 0755)

	// P2 Clang
	var green []string
	for _, p := range all {
		rel, _ := filepath.Rel(repoAbs, p)
		rel = filepath.ToSlash(rel)
		ok, errs, warns, first := clangCheck(p)
		r := FileResult{Path: rel, ClangOK: ok, ClangErrs: errs, ClangWarns: warns, ClangFirst: first}
		results = append(results, r)
		if ok {
			green = append(green, p)
		}
	}
	fmt.Fprintf(os.Stderr, "Clang 绿: %d / 红: %d\n", len(green), len(all)-len(green))

	// P3 serve(分批)
	served := map[string][]Diag{}
	for i := 0; i < len(green); i += *flagBatch {
		end := i + *flagBatch
		if end > len(green) {
			end = len(green)
		}
		batch := green[i:end]
		keys := make([]string, len(batch))
		for k, p := range batch {
			keys[k] = relOf(repoAbs, p)
		}
		res, err := serveBatchKeys(repoAbs, keys, batch)
		if err != nil {
			fail("serve 批失败(%d..%d): %v", i, end, err)
		}
		for k, v := range res {
			served[k] = v
		}
		fmt.Fprintf(os.Stderr, "serve %d/%d\n", end, len(green))
	}

	// P4 分桶 + 剥壳重试(临时文件绝对路径 serve, key=原路径)
	var vitroRed []string
	stripSrc := map[string]string{} // orig rel → stripped src
	for _, p := range green {
		diags := served[relOf(repoAbs, p)]
		errs := 0
		for _, d := range diags {
			if d.Severity == "error" {
				errs++
			}
		}
		if errs == 0 {
			continue
		}
		vitroRed = append(vitroRed, p)
		rel := relOf(repoAbs, p)
		if s2, changed := stripStdbool(readFile(p)); changed {
			stripSrc[rel] = s2
		}
	}
	// 剥壳按序 serve, 结果写回 results
	if len(stripSrc) > 0 {
		var rels []string
		for rel := range stripSrc {
			rels = append(rels, rel)
		}
		sort.Strings(rels)
		for i := 0; i < len(rels); i += *flagBatch {
			end := i + *flagBatch
			if end > len(rels) {
				end = len(rels)
			}
			keys, paths := []string{}, []string{}
			for _, rel := range rels[i:end] {
				tmp := filepath.Join(tmpDir, fmt.Sprintf("strip_%d.c", len(paths)))
				os.WriteFile(tmp, []byte(stripSrc[rel]), 0644)
				keys = append(keys, rel)
				paths = append(paths, tmp)
			}
			res, err := serveBatchKeys(repoAbs, keys, paths)
			if err != nil {
				fmt.Fprintf(os.Stderr, "剥壳批失败: %v\n", err)
				continue
			}
			for ri := range results {
				if diags, ok := res[results[ri].Path]; ok {
					errs := 0
					for _, d := range diags {
						if d.Severity == "error" {
							errs++
						}
					}
					results[ri].Stripped = true
					results[ri].StripErrs = errs
					results[ri].StripLayer = layerOf(diags)
				}
			}
			fmt.Fprintf(os.Stderr, "剥壳 %d/%d\n", end, len(rels))
		}
	}

	// 回填诊断到 results
	for ri := range results {
		if diags, ok := served[results[ri].Path]; ok {
			results[ri].VitroDiags = diags
			for _, d := range diags {
				if d.Severity == "error" {
					results[ri].VitroErrs++
				} else {
					results[ri].VitroWarns++
				}
			}
			results[ri].Layer = layerOf(diags)
		}
	}

	// P5 运行对比(双绿桶: Vitro 也无 error)
	for _, p := range green {
		rel := relOf(repoAbs, p)
		diags := served[rel]
		errs := 0
		for _, d := range diags {
			if d.Severity == "error" {
				errs++
			}
		}
		if errs > 0 {
			continue
		}
		for ri := range results {
			if results[ri].Path != rel {
				continue
			}
			skipNet := strings.Contains(rel, "client_server") || strings.Contains(strings.ToLower(rel), "socket") || strings.Contains(strings.ToLower(rel), "networking")
			hasRand := containsWord(readFile(p), "rand(")
			verdict, detail := runCompare(repoAbs, p, tmpDir, skipNet, hasRand)
			results[ri].RunCmp = verdict
			results[ri].RunDetail = detail
			fmt.Fprintf(os.Stderr, "run: %s → %s\n", rel, verdict)
		}
	}

	// P6 报告
	writeReport(*flagOut, results)
	jsonBytes, _ := json.MarshalIndent(results, "", "  ")
	os.WriteFile(filepath.Join(*flagOut, "result.json"), jsonBytes, 0644)
	fmt.Fprintf(os.Stderr, "完成: %s/report.md\n", *flagOut)
}

func relOf(repo, p string) string {
	r, _ := filepath.Rel(repo, p)
	return filepath.ToSlash(r)
}

func readFile(p string) string {
	b, e := os.ReadFile(p)
	if e != nil {
		return ""
	}
	return string(b)
}

func containsWord(s, w string) bool { return strings.Contains(s, w) }

func writeReport(out string, results []FileResult) {
	bucket := func(f func(FileResult) bool) (n int) {
		for _, r := range results {
			if f(r) {
				n++
			}
		}
		return
	}
	total := len(results)
	clangRed := bucket(func(r FileResult) bool { return !r.ClangOK })
	bothGreen := bucket(func(r FileResult) bool { return r.ClangOK && r.VitroErrs == 0 })
	vitroRed := bucket(func(r FileResult) bool { return r.ClangOK && r.VitroErrs > 0 })

	codeCount := map[string]int{}
	warnFiles := map[string][]string{}
	layerCount := map[string]int{}
	for _, r := range results {
		layerCount[r.Layer]++
		for _, d := range r.VitroDiags {
			if d.Severity == "error" {
				codeCount[d.Code]++
			} else if d.Code != "" {
				warnFiles[d.Code] = append(warnFiles[d.Code], r.Path)
			}
		}
	}

	var b strings.Builder
	fmt.Fprintf(&b, "# Vitro vs Clang 对比勘探报告\n\n生成: %s\n\n", time.Now().Format("2006-01-02 15:04:05"))
	fmt.Fprintf(&b, "## 分桶\n\n| 桶 | 数量 |\n|---|---|\n")
	fmt.Fprintf(&b, "| 总文件 | %d |\n| Clang 红(平台差异/真错/链接需求) | %d |\n| 双绿 | %d |\n| Vitro 红(Clang 绿) | %d |\n\n", total, clangRed, bothGreen, vitroRed)

	fmt.Fprintf(&b, "## Vitro 诊断码 top\n\n| 码 | 次数 |\n|---|---|\n")
	type kv struct {
		k string
		v int
	}
	var kvs []kv
	for k, v := range codeCount {
		kvs = append(kvs, kv{k, v})
	}
	sort.Slice(kvs, func(i, j int) bool { return kvs[i].v > kvs[j].v })
	for _, x := range kvs {
		fmt.Fprintf(&b, "| %s | %d |\n", x.k, x.v)
	}

	fmt.Fprintf(&b, "\n## 层分布(Clang 绿样本)\n\n| 层 | 数量 |\n|---|---|\n")
	for _, l := range []string{"ok", "typeck", "parse", "lex", ""} {
		if layerCount[l] > 0 {
			fmt.Fprintf(&b, "| %s | %d |\n", l, layerCount[l])
		}
	}

	if len(warnFiles) > 0 {
		fmt.Fprintf(&b, "\n## W 警告(serve 通道)\n\n| 码 | 文件 |\n|---|---|\n")
		for k, v := range warnFiles {
			fmt.Fprintf(&b, "| %s | %s |\n", k, strings.Join(v, ", "))
		}
	}

	fmt.Fprintf(&b, "\n## 运行对比(双绿桶)\n\n")
	runCount := map[string]int{}
	for _, r := range results {
		if r.RunCmp != "" {
			runCount[r.RunCmp]++
		}
	}
	for k, v := range runCount {
		fmt.Fprintf(&b, "- %s: %d\n", k, v)
	}
	fmt.Fprintf(&b, "\n### 不一致明细\n\n")
	for _, r := range results {
		if r.RunCmp == "mismatch" || r.RunCmp == "vitro_run_fail" || r.RunCmp == "clang_build_fail" {
			fmt.Fprintf(&b, "- `%s`: %s — %s\n", r.Path, r.RunCmp, r.RunDetail)
		}
	}

	fmt.Fprintf(&b, "\n## Clang 红明细(前 40)\n\n")
	n := 0
	for _, r := range results {
		if !r.ClangOK && n < 40 {
			fmt.Fprintf(&b, "- `%s`: %s\n", r.Path, r.ClangFirst)
			n++
		}
	}

	fmt.Fprintf(&b, "\n## Vitro 红明细(层+首诊断, 前 60)\n\n")
	n = 0
	for _, r := range results {
		if r.ClangOK && r.VitroErrs > 0 && n < 60 {
			first := ""
			for _, d := range r.VitroDiags {
				if d.Severity == "error" {
					first = fmt.Sprintf("%s %d:%d %s", d.Code, d.Line, d.Column, d.Message)
					break
				}
			}
			fmt.Fprintf(&b, "- `%s` [%s] 剥壳层=%s/%d: %s\n", r.Path, r.Layer, map[bool]string{true: r.StripLayer, false: "-"}[r.Stripped], r.StripErrs, first)
			n++
		}
	}

	os.WriteFile(filepath.Join(out, "report.md"), []byte(b.String()), 0644)
}

// ---------- 聚合模式: result.json → gold_signatures.json ----------
// 复现链补齐（原聚合过程是临时脚本，2026-10-02 入仓工具化）。只取测量
// 事实（码计数/层/运行判定），**不透传诊断 message**——message 可引用
// 源码 token，是 result.json 不入库的原因（GPL 红线）。

type goldFile struct {
	ClangOK   bool           `json:"clang_ok"`
	VitroErrs int            `json:"vitro_errs"`
	VitroWarn int            `json:"vitro_warns"`
	Codes     map[string]int `json:"codes"`
	Layer     string         `json:"layer"`
	Run       string         `json:"run"`
}

func runAggregate(resultPath string) int {
	b, err := os.ReadFile(resultPath)
	if err != nil {
		fail(fmt.Sprintf("读取 result.json 失败: %v", err))
	}
	var rs []FileResult
	if err := json.Unmarshal(b, &rs); err != nil {
		fail(fmt.Sprintf("result.json 解析失败: %v", err))
	}
	files := map[string]goldFile{}
	buckets := map[string]int{"clang_red": 0, "both_green": 0, "vitro_red": 0}
	for _, r := range rs {
		codes := map[string]int{}
		for _, d := range r.VitroDiags {
			if d.Code != "" {
				codes[d.Code]++
			}
		}
		bucket := "vitro_red"
		if !r.ClangOK {
			bucket = "clang_red"
		} else if r.VitroErrs == 0 {
			bucket = "both_green"
		}
		buckets[bucket]++
		files[r.Path] = goldFile{
			ClangOK:   r.ClangOK,
			VitroErrs: r.VitroErrs,
			VitroWarn: r.VitroWarns,
			Codes:     codes,
			Layer:     r.Layer,
			Run:       r.RunCmp,
		}
	}
	out := map[string]any{
		"_meta": map[string]any{
			"as_of":   time.Now().Format("2006-01-02"),
			"repo":    "TheAlgorithms/C",
			"note":    "金样本签名清单——只存诊断码/数量/运行判定签名,不存源码文本(GPL 红线)。E1021×104 为勘探方法限制(serve 无 base_dir),断言时应豁免。",
			"total":   len(rs),
			"buckets": buckets,
		},
		"files": files,
	}
	ob, _ := json.MarshalIndent(out, "", "  ")
	dst := filepath.Join(filepath.Dir(resultPath), "gold_signatures.json")
	if err := os.WriteFile(dst, append(ob, '\n'), 0644); err != nil {
		fail(fmt.Sprintf("写出失败: %v", err))
	}
	fmt.Fprintf(os.Stderr, "聚合完成: %d 文件 → %s\n", len(rs), dst)
	return 0
}

// ---------- 合规模式: gold_signatures.json 校验（CI hygiene） ----------
// 三道: ①格式合法（_meta 必含 source_fork/source_commit, files 字段类型）
// ②无源码文本渗漏（字符串值白名单: run 判定词/层名/诊断码格式/E 数字;
//   _meta.note 例外但限长）③fail loud——任何不符 exit 1。

// 值域 = result.json 实测全集（2026-10-02 全量统计——注释里的枚举不全，
// 以测量为准；新判定词出现时此处红，人工评估后扩）。
var checkRunWords = map[string]bool{
	"": true, "match": true, "mismatch": true, "clang_build_fail": true,
	"clang_timeout": true, "clang_run_fail": true, "rand_diff_match": true,
	"rand_diff": true,
}

var checkLayerWords = map[string]bool{
	"": true, "ok": true, "lex": true, "parse": true, "typeck": true,
}

func runCheck() int {
	path := filepath.Join(mustRepoRoot(), "scripts", "realcode_diff", "gold_signatures.json")
	b, err := os.ReadFile(path)
	if err != nil {
		fail(fmt.Sprintf("金样本缺失: %v", err))
	}
	var g map[string]any
	if err := json.Unmarshal(b, &g); err != nil {
		fail(fmt.Sprintf("金样本 JSON 解析失败: %v", err))
	}
	meta, ok := g["_meta"].(map[string]any)
	if !ok {
		fail("_meta 缺失或非对象")
	}
	for _, k := range []string{"source_fork", "source_commit", "total"} {
		if _, ok := meta[k]; !ok {
			fail(fmt.Sprintf("_meta.%s 缺失（provenance 锚）", k))
		}
	}
	files, ok := g["files"].(map[string]any)
	if !ok || len(files) == 0 {
		fail("files 缺失或为空")
	}
	for name, v := range files {
		e, ok := v.(map[string]any)
		if !ok {
			fail(fmt.Sprintf("files.%s 非对象", name))
		}
		if s, ok := e["run"].(string); !ok || !checkRunWords[s] {
			fail(fmt.Sprintf("files.%s.run 非法值域: %v", name, e["run"]))
		}
		if s, ok := e["layer"].(string); !ok || !checkLayerWords[s] {
			fail(fmt.Sprintf("files.%s.layer 非法值域: %v", name, e["layer"]))
		}
		if codes, ok := e["codes"].(map[string]any); ok {
			for c, n := range codes {
				// 码形态 = 引擎三族（E 错误/W 警告/H 提示——gen_diag 137 码位
				// 全表；v2 勘探起 hints 也入签名）。首字母白名单 + 全数字。
				if len(c) != 5 || (c[0] != 'E' && c[0] != 'W' && c[0] != 'H') || !isAllDigits(c[1:]) {
					fail(fmt.Sprintf("files.%s.codes 键非诊断码形态: %q", name, c))
				}
				if f, ok := n.(float64); !ok || f < 1 {
					fail(fmt.Sprintf("files.%s.codes[%s] 计数非法", name, c))
				}
			}
		} else {
			fail(fmt.Sprintf("files.%s.codes 缺失", name))
		}
		// 渗漏兜底: schema 键集白名单——条目只许六键（run/layer 已过值域、
		// codes 已过码形态、其余为 bool/int），任何未知键（如透传 message）
		// 即红，字符串值超 8 字符亦红（合法值域词最长 16 字符已在前查过，
		// 此处只拦未知键的渗漏形态）。
		for k2, v2 := range e {
			switch k2 {
			case "clang_ok", "vitro_errs", "vitro_warns", "codes", "layer", "run":
			default:
				fail(fmt.Sprintf("files.%s 未知键 %q（schema 白名单外——疑透传诊断文案）", name, k2))
			}
			if s, ok := v2.(string); ok && k2 != "run" && k2 != "layer" && len(s) > 8 {
				fail(fmt.Sprintf("files.%s.%s 字符串超长(疑源码渗漏): %.60q", name, k2, s))
			}
		}
	}
	if note, ok := meta["note"].(string); ok && len(note) > 300 {
		fail("_meta.note 超长")
	}
	fmt.Fprintf(os.Stderr, "gold_signatures.json 合规 OK: %d 文件条目（格式/值域/零渗漏）\n", len(files))
	return 0
}

func isAllDigits(s string) bool {
	if s == "" {
		return false
	}
	for _, c := range s {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

// mustRepoRoot: 从可执行文件定位不可靠（go run 临时目录），按环境变量与
// 常见路径回退查找 scripts/realcode_diff 形态（先例 probeutil.MustFindCLI）。
func mustRepoRoot() string {
	if v := os.Getenv("VITRO_ROOT"); v != "" {
		return v
	}
	for _, cand := range []string{".", "..", "../..", "D:/code/Vitro"} {
		if _, err := os.Stat(filepath.Join(cand, "scripts", "realcode_diff")); err == nil {
			abs, _ := filepath.Abs(cand)
			return abs
		}
	}
	fail("无法定位仓库根（请设 VITRO_ROOT）")
	return ""
}
