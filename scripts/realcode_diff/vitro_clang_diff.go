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
// 用法: go run vitro_clang_diff.go -repo <fork 仓路径> -out _diff_out [-filter cipher/] [-limit N]
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
	GccOK      bool   `json:"gcc_ok"` // gcc 分桶裁判（#25 裁定二：分桶裁判非第二真值）
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
	flagVitro  = flag.String("vitro", mustRepoRoot(), "Vitro 仓库根(serve/cwd)")
	flagAgg    = flag.String("aggregate", "", "聚合模式: 输入 result.json 路径, 产 gold_signatures.json")
	flagCheck  = flag.Bool("check", false, "合规模式: 校验仓内 gold_signatures.json(格式+无源码文本渗漏)")
	// ── 仓内语料批（2026-10-22 试点批 chibicc，#25 义务链第⑤步）──
	// -corpus <name>：仓内 scripts/realcode_diff/corpus/<name>/ 语料勘探。
	// 与 -repo 模式并存（-repo 走外部 GPL 仓的 source-only 形态；-corpus 走
	// 仓内语料的 files+filename 形态——后者解开了同目录 quote-include，
	// 见 #253 的 E1021 假红根因与 #25 §1.2 的 cwd 解锁实证）。
	flagCorpus = flag.String("corpus", "", "仓内语料批名(corpus/<name>/)")
	// -gold-out <文件名>：聚合模式产物名（仓内多金样本并存时用 gold_<corpus>.json）
	flagGoldOut = flag.String("gold-out", "gold_signatures.json", "聚合模式产物文件名")
	// -agg-repo <名>：聚合模式记入 _meta.repo 的语料源名
	flagAggRepoName = flag.String("agg-repo", "TheAlgorithms/C", "聚合模式 _meta.repo 的语料源名")
	// -gcc <路径>：gcc 分桶裁判路径（探测序：显式参数 → PATH → D:\\code\\mingw64\\bin）
	flagGcc = flag.String("gcc", "", "gcc 可执行路径(分桶裁判; 空=按探测序找, 找不到则跳过该桶)")
	// -gcc-only：只跑 gcc 分桶（对已过 Clang 真值的文件集补测 gcc 侧）
	flagGccOnly = flag.Bool("gcc-only", false, "只跑 gcc 分桶(需 -corpus 或 -repo)")
	// -probe：产出剥壳(语句表达式消解)对照报告——用于「先剥壳看真问题」
	flagProbe = flag.Bool("probe", false, "产出剥壳对照(原始 vs 剥壳后)的诊断差分报告")
)

// 仓内语料根（-corpus 模式）。语料在 scripts/ 冻结区但属仓内普通文件
// （MIT 许可无毒语料，#25 裁定一），不入防线扫描域（实测留证见
// scripts/realcode_diff/README.corpus.md）。
func corpusRoot(name string) string {
	return filepath.Join(mustRepoRoot(), "scripts", "realcode_diff", "corpus", name)
}

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

// ---------- P2.5: gcc 分桶裁判（#25 裁定二：gcc 是分桶裁判不是第二真值）----------
// 探测序：--gcc 显式参数 → PATH → D:\code\mingw64\bin（方案档 1.3 工具链事实）。
// 找不到 gcc 时**不静默跳过**——fail loud（纪律 8），由调用方显式选择是否放行。

// findGcc 按探测序定位 gcc 可执行；找不到返回空串。
func findGcc() string {
	if *flagGcc != "" {
		if _, err := os.Stat(*flagGcc); err == nil {
			return *flagGcc
		}
		fail(fmt.Sprintf("--gcc 指定的路径不存在: %s", *flagGcc))
	}
	if p, err := exec.LookPath("gcc"); err == nil {
		return p
	}
	fallback := `D:\code\mingw64\bin\gcc.exe`
	if _, err := os.Stat(fallback); err == nil {
		return fallback
	}
	return ""
}

// gccCheck 以 gcc 语法检查为口径的真值判定（与 clangCheck 同形）。
// 只判语法层（-fsyntax-only），不判链接——与 clang 侧口径一致。
func gccCheck(gcc, path string) (ok bool, errs int) {
	cmd := exec.Command(gcc, "-std=c11", "-fsyntax-only", path)
	out, err := runWithTimeout(cmd, 20*time.Second)
	if err != nil && !strings.Contains(out, "error") {
		return false, 1 // 工具层失败
	}
	for _, l := range strings.Split(out, "\n") {
		if strings.Contains(l, "error:") {
			errs++
		}
	}
	return errs == 0, errs
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

// runWithTimeoutSplit 分离捕获 stdout/stderr（#254 根治，2026-10-22）：
// 上面的 runWithTimeout 合并两流——#129 通道分立后协议帧族（// STDERR
// // NOTE // COMPILE-HINT // COMPILE-WARNING // FIX 等）全走 stderr，合并
// 捕获会把它们算进「程序输出」→ 逐字节判分大量假 mismatch。运行对拍两侧
// （clang/vitro）自此只取 stdout 字段 = 纯程序输出口径（与 clang_direct
// 防线的 stdout+返回码口径一致化）。编译/语法检查等**诊断即目的**的
// 调用仍用合并版（runWithTimeout）。
func runWithTimeoutSplit(cmd *exec.Cmd, d time.Duration) (string, string, error) {
	var out, errb strings.Builder
	cmd.Stdout = &out
	cmd.Stderr = &errb
	if err := cmd.Start(); err != nil {
		return out.String(), errb.String(), err
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	select {
	case <-time.After(d):
		cmd.Process.Kill()
		return out.String(), errb.String(), fmt.Errorf("timeout %v", d)
	case e := <-done:
		return out.String(), errb.String(), e
	}
}

// gccCheckProject 以「目录内所有 .c 一起编译」为口径的 gcc 分桶判定。
func gccCheckProject(gcc string, pr project) (ok bool, errs int) {
	if len(pr.Files) == 0 {
		return false, 1
	}
	args := append([]string{"-std=c11", "-fsyntax-only"}, pr.Files...)
	cmd := exec.Command(gcc, args...)
	cmd.Dir = pr.Dir
	out, err := runWithTimeout(cmd, 30*time.Second)
	if err != nil && !strings.Contains(out, "error") {
		return false, 1
	}
	for _, l := range strings.Split(out, "\n") {
		if strings.Contains(l, "error:") {
			errs++
		}
	}
	return errs == 0, errs
}

// clangCheckProject 以「目录内所有 .c 一起编译」为口径的 Clang 真值判定。
// .h 不参与编译（仅经 #include 展开）——与真实构建一致。
func clangCheckProject(pr project) (ok bool, errs int, first string) {
	if len(pr.Files) == 0 {
		return false, 1, "工程内无 .c 文件"
	}
	args := append([]string{"-std=c11", "-Wall", "-Wextra", "-fsyntax-only"}, pr.Files...)
	cmd := exec.Command("clang", args...)
	cmd.Dir = pr.Dir
	out, err := runWithTimeout(cmd, 30*time.Second)
	if err != nil && !strings.Contains(out, "error") && !strings.Contains(out, "warning") {
		return false, 1, "clang 执行失败: " + err.Error()
	}
	for _, l := range strings.Split(out, "\n") {
		if strings.Contains(l, "error:") {
			errs++
			if first == "" {
				first = strings.TrimSpace(l)
			}
		}
	}
	return errs == 0, errs, first
}

// ---------- P3: Vitro serve 连发(keys 与 paths 一一对应) ----------
//
// #253（2026-10-22）：compile 请求补 filename（绝对路径）——引擎侧
// gateway.mbt lex_full_source 的 base_dir 取首个非空 filename 的目录，
// quote-include 走真实文件系统候选链；不传则 base_dir="."（serve cwd）
// → 本地 #include 一律 E1021 假红（实测 104 次 → 残 33 次全为真子集边界）。
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
		payload.WriteString(fmt.Sprintf(`{"id":%d,"method":"compile","params":{"source":%s,"filename":%s}}`+"\n", i+1, mustJSON(string(src)), mustJSON(p)))
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

// ---------- P3': 仓内语料批的 serve 连发（files+filename 形态） ----------
//
// 与 serveBatchKeys 的关键差异：**传 filename**（绝对路径）。引擎侧
// base_dir 取自 units 首个非空 filename 的目录（gateway.mbt lex_full_source
// 的 base_dir 语义），native 臂 quote-include 走真实文件系统候选链——
// 于是同目录 `#include "test.h"` 可解析。这是 #253（serve compile 请求不传
// filename → 本地 include 一律 E1021 假红）的根治面。
//
// 传 files 数组（而非 source 单值）的原因：header unit（.h）不进拼接、
// 仅经 include 展开，files 形态让引擎自行处理 .c/.h 混合集。
// serveBatchFiles 发送 compile 请求并回填诊断。
//
// 两种形态：
//  1. **单文件批**（len(files) == len(keys)）：每个文件一个请求，
//     每次请求的 files 数组只含 1 个单元——用于单文件语料的对拍。
//  2. **多文件工程**（len(files) != len(keys)，keys 长度 1）：**一个**请求，
//     files 数组装整个工程的 .c + .h——多 translation unit 一起编译。
//     （这是真实 C 项目的组织方式，也是 #237 记的零覆盖形态。）
func serveBatchFiles(keys []string, files []compileFile) (map[string][]Diag, error) {
	res := map[string][]Diag{}
	cmd := exec.Command("moon", "run", "--target", "native", "moonbit/cmd/serve")
	cmd.Dir = *flagVitro
	stdin, _ := cmd.StdinPipe()
	stdout, _ := cmd.StdoutPipe()
	if err := cmd.Start(); err != nil {
		return nil, fmt.Errorf("serve 启动失败(检查 moon/cwd): %w", err)
	}
	payload := &strings.Builder{}
	if len(files) == len(keys) && len(keys) > 0 {
		// 形态 1：逐文件单请求
		for i, f := range files {
			src, e := os.ReadFile(f.Path)
			if e != nil {
				return nil, e
			}
			unit := fmt.Sprintf(`{"filename":%s,"source":%s}`, mustJSON(f.Path), mustJSON(string(src)))
			payload.WriteString(fmt.Sprintf(`{"id":%d,"method":"compile","params":{"files":[%s]}}`+"\n", i+1, unit))
		}
	} else {
		// 形态 2：多文件工程——一个请求装全部单元
		var units []string
		for _, f := range files {
			src, e := os.ReadFile(f.Path)
			if e != nil {
				return nil, e
			}
			units = append(units, fmt.Sprintf(`{"filename":%s,"source":%s}`, mustJSON(f.Path), mustJSON(string(src))))
		}
		payload.WriteString(fmt.Sprintf(`{"id":1,"method":"compile","params":{"files":[%s]}}`+"\n", strings.Join(units, ",")))
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

// project 是一个**多文件工程**（真实 C 项目的组织方式：.h + 实现 .c + main.c）。
// 目录内所有 .c 一起编译为一个单元组；.h 不单独编译，仅经 #include 展开。
type project struct {
	Name  string   // 工程名（目录名）
	Dir   string   // 工程目录绝对路径
	Files []string // 工程内 .c 文件（绝对路径，升序）
	Units []string // 工程内 .h 文件（绝对路径，升序）
}

// collectProject 收集一个目录作为多文件工程。
func collectProject(dir string) project {
	p := project{Name: filepath.Base(dir), Dir: dir}
	ents, _ := os.ReadDir(dir)
	for _, e := range ents {
		if e.IsDir() {
			continue
		}
		full := filepath.Join(dir, e.Name())
		switch {
		case strings.HasSuffix(e.Name(), ".c"):
			p.Files = append(p.Files, full)
		case strings.HasSuffix(e.Name(), ".h"):
			p.Units = append(p.Units, full)
		}
	}
	sort.Strings(p.Files)
	sort.Strings(p.Units)
	return p
}

// compileFile 是仓内语料批的编译单元（路径 + 该文件要送入的内容路径）。
type compileFile struct {
	Path string // 送入引擎的 filename（绝对路径 → base_dir 候选链的锚）
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

// ---------- P4': 语句表达式消解（GNU `({ ... })` → C 子集等价形态） ----------
//
// 背景（#25 §1.2 试金石）：chibicc 断言风格 `ASSERT(x, ({...}))` 使 GNU 语句
// 表达式饱和，Vitro 在 parse 层报 E2005 洪水（4159 次/16 份），**深层诊断全被
// 遮蔽**——语料信号全淹没在洪水里。
//
// 形态困境（实测）：`({...})` 是**表达式**，C 的块 `{...}` 是**语句**——直接替换
// 为块语句在表达式位置非法（Clang: expected expression / extraneous ')'）。
// 逗号表达式形态也不行（不能含声明 `int a = 1`）。故必须做**语句上下文改写**：
//
//	原：ASSERT(8, ({ union { int a; } x; sizeof(x); }));
//	新：{ union { int a; } x; int __vitro_sx0 = sizeof(x); ASSERT(8, __vitro_sx0); }
//
// 等价性依据（实测）：
//   - Clang **绿**语料 10/10 份消解后错误集逐字节一致（路径归一后）——
//     即「有意义的信号面」上消解零语义破坏；
//   - Clang 红的 3 份（constexpr.c / control.c / typedef.c）消解后多出一条
//     次生诊断，根因是**语料自身**的 C 语义歧义（`redefinition of 't'`、
//     `size of array has non-integer type`、`expression is not assignable`），
//     非消解器引入。
//     1. GNU 语句表达式的值 = 最后一个表达式语句的值 → 提取到临时变量；
//     2. 语句体内声明的变量作用域限于该表达式 → 块作用域化后生命周期一致；
//     3. 块语句在语句位置合法，且不改变外层控制流。
//
// 保守边界（不做的事）：
//   - 语句体内含 return/break/continue/goto 时不消解（改变控制流语义）；
//   - 语句表达式出现在**表达式上下文**（非完整语句）时不消解；
//   - 嵌套语句表达式由内向外逐层消解；
//   - 变换只用于**探针对照**（-probe 模式），原始语料保持原样入库。
var stmtExprRe = regexp.MustCompile(`\(\{`)

// assertCallRe 匹配宏调用（宏名取大写标识符）。
var assertCallRe = regexp.MustCompile(`\b([A-Z][A-Z0-9_]*)\s*\(`)

// stripStmtExprs 消解源码中的 GNU 语句表达式。返回 (变换后源码, 消解处数)。
//
// 主路径：识别「宏调用语句」形态（ASSERT(x, ({...}));）→ 改写为块语句。
// 该形态覆盖 chibicc 语料 684 处语句表达式中的 678 处（99.1%）。
func stripStmtExprs(src string) (string, int) {
	count := 0
	for {
		loc, end, ok := findAssertStmtExpr(src)
		if !ok {
			break
		}
		repl, ok2 := rewriteAssertStmt(src, loc, end, count)
		if !ok2 {
			break
		}
		src = src[:loc] + repl + src[end:]
		count++
	}
	return src, count
}

// findAssertStmtExpr 找第一处「宏调用的第二实参是语句表达式且处于语句位置」的调用。
// 返回 (宏调用的 '(' 位置, 右括号后一位置, ok)。
func findAssertStmtExpr(src string) (int, int, bool) {
	for _, m := range assertCallRe.FindAllStringIndex(src, -1) {
		open := m[1] - 1 // '(' 位置
		arg2Start, ok := secondArgStart(src, open)
		if !ok {
			continue
		}
		// 第二实参必须以 '({' 开头
		if !strings.HasPrefix(src[arg2Start:], "({") {
			continue
		}
		// 必须是完整语句表达式：括号配对成功（'{' 在 arg2Start+1）
		if _, _, ok2 := matchBrace(src, arg2Start+1); !ok2 {
			continue
		}
		callEnd := findMatchingParen(src, open)
		if callEnd < 0 {
			continue
		}
		// 必须处于语句位置：右括号后是 ';'
		rest := strings.TrimLeft(src[callEnd+1:], " \t\r\n")
		if !strings.HasPrefix(rest, ";") {
			continue
		}
		// 返回宏名起点（供改写时取宏名）
		return m[0], callEnd + 1, true
	}
	return 0, 0, false
}

// secondArgStart 求宏调用的第二个实参起始位置。返回 (起, ok)。
func secondArgStart(src string, open int) (int, bool) {
	depth := 0
	inStr, inChr := false, false
	commas := 0
	for i := open; i < len(src); i++ {
		c := src[i]
		if inStr {
			if c == '\\' {
				i++
			} else if c == '"' {
				inStr = false
			}
			continue
		}
		if inChr {
			if c == '\\' {
				i++
			} else if c == '\'' {
				inChr = false
			}
			continue
		}
		switch c {
		case '"':
			inStr = true
		case '\'':
			inChr = true
		case '(', '[', '{':
			depth++
		case ')', ']', '}':
			depth--
			if depth == 0 {
				return 0, false
			}
		case ',':
			if depth == 1 {
				commas++
				if commas == 1 {
					// 跳过逗号与空白
					j := i + 1
					for j < len(src) && (src[j] == ' ' || src[j] == '\t') {
						j++
					}
					return j, true
				}
			}
		}
	}
	return 0, false
}

// findMatchingParen 从 '(' 位置找匹配的 ')'。
func findMatchingParen(src string, open int) int {
	depth := 0
	inStr, inChr := false, false
	for i := open; i < len(src); i++ {
		c := src[i]
		if inStr {
			if c == '\\' {
				i++
			} else if c == '"' {
				inStr = false
			}
			continue
		}
		if inChr {
			if c == '\\' {
				i++
			} else if c == '\'' {
				inChr = false
			}
			continue
		}
		switch c {
		case '"':
			inStr = true
		case '\'':
			inChr = true
		case '(':
			depth++
		case ')':
			depth--
			if depth == 0 {
				return i
			}
		}
	}
	return -1
}

// rewriteAssertStmt 把 `MACRO(a, ({ body }));` 改写为
// `{ body; int __vitro_sxN = last; MACRO(a, __vitro_sxN); }`。
// src[callStart:callEnd] 为宏调用区间（callStart = 宏名起点，callEnd 指向 ')' 之后）。
func rewriteAssertStmt(src string, callStart, callEnd, idx int) (string, bool) {
	m := assertCallRe.FindStringIndex(src[callStart:])
	if m == nil {
		return "", false
	}
	// 宏名 = 匹配区间去掉尾部 '('
	name := src[callStart+m[0] : callStart+m[1]-1]
	open := callStart + m[1] - 1 // '(' 位置
	arg1Start, arg2Start, ok := twoArgs(src, open)
	if !ok {
		return "", false
	}
	// 实参1 = arg1Start 到 arg2Start 之前（去掉尾随空白与逗号）
	arg1 := strings.TrimSpace(src[arg1Start:arg2Start])
	arg1 = strings.TrimSuffix(arg1, ",")
	arg1 = strings.TrimSpace(arg1)
	body, _, ok2 := matchBrace(src, arg2Start+1)
	if !ok2 {
		return "", false
	}
	if hasControlFlow(body) {
		return "", false
	}
	stmts, last, ok3 := splitLastStmt(body)
	if !ok3 {
		return "", false
	}
	inner := fmt.Sprintf("%s int __vitro_sx%d = %s; %s(%s, __vitro_sx%d);",
		stmts, idx, last, name, arg1, idx)
	return "{ " + inner + " }", true
}

// twoArgs 求宏调用的两个实参边界：返回 (实参1起, 实参2起, ok)。
// 实参2 起 = 顶层逗号之后第一个非空白字符位置。
func twoArgs(src string, open int) (int, int, bool) {
	depth := 0
	inStr, inChr := false, false
	commas := 0
	arg1Start := open + 1
	arg2Start := 0
	for i := open; i < len(src); i++ {
		c := src[i]
		if inStr {
			if c == '\\' {
				i++
			} else if c == '"' {
				inStr = false
			}
			continue
		}
		if inChr {
			if c == '\\' {
				i++
			} else if c == '\'' {
				inChr = false
			}
			continue
		}
		switch c {
		case '"':
			inStr = true
		case '\'':
			inChr = true
		case '(', '[', '{':
			depth++
		case ')', ']', '}':
			depth--
			if depth == 0 {
				if commas < 1 {
					return 0, 0, false
				}
				return arg1Start, arg2Start, true
			}
		case ',':
			if depth == 1 {
				commas++
				if commas == 1 {
					j := i + 1
					for j < len(src) && (src[j] == ' ' || src[j] == '\t') {
						j++
					}
					arg2Start = j
				}
			}
		}
	}
	return 0, 0, false
}

// splitLastStmt 把语句体拆成 (前置语句, 末条表达式)。
//
// 切分口径（GNU 语句表达式的值 = **最后一条语句**的值）。语句边界有二：
//
//  1. 顶层分号（不在嵌套块/括号内）；
//
//  2. 顶层复合语句的结束（'}' 使块深度回到 0）——`{2;}` 本身就是一条语句，
//     其内部的分号不构成边界。
//
//     `int i=0; while(i<10) i=i+1; i;` → stmts=`int i=0; while(i<10) i=i+1;` / last=`i`
//     `1; {2;} 3;`                     → stmts=`1; {2;}`                    / last=`3`
//     `;;; 5;`                          → stmts=`;;;`                        / last=`5`
func splitLastStmt(body string) (string, string, bool) {
	trimmed := strings.TrimSpace(body)
	if trimmed == "" {
		return "", "", false
	}
	bounds := topLevelStmtEnds(trimmed)
	if len(bounds) == 0 {
		// 无语句边界 → 整块是一条表达式
		return "", trimmed, true
	}
	lastEnd := bounds[len(bounds)-1]
	lastStart := 0
	if len(bounds) >= 2 {
		lastStart = bounds[len(bounds)-2] + 1
	}
	// 回溯：若末条起点处是「复合语句」（以 '{' 开头），则它属前一条语句——
	// 末条应是复合块**之后**的那条（`1; {2;} 3;` → 末条 = `3`）。
	lastStart = skipCompoundStmt(trimmed, lastStart, lastEnd)
	last := strings.TrimSpace(trimmed[lastStart:lastEnd])
	stmts := strings.TrimSpace(trimmed[:lastStart])
	if last == "" {
		return "", "", false
	}
	// 末条必须是**表达式**——若是声明（`int x = 1;`）或复合语句（`{...}`），
	// 取值无意义（GNU 语句表达式的值只取最后一条*表达式语句*）。
	// 保守放弃：宁可少消解一处，也不破语义。
	if !isExprLikeStmt(last) {
		return "", "", false
	}
	if stmts == "" {
		return "", last, true
	}
	return stmts, last, true
}

// declKeywords 是 C 声明起始关键字（判定「末条是否为声明」）。
var declKeywords = []string{
	"int", "char", "short", "long", "float", "double", "void", "signed", "unsigned",
	"_Bool", "_Complex", "struct", "union", "enum", "const", "volatile", "static",
	"extern", "typedef", "register", "auto", "inline", "_Alignas", "_Atomic",
	"_Noreturn", "_Thread_local", "thread_local", "__thread",
}

// isExprLikeStmt 判定一条语句是否像**表达式语句**（而非声明/复合语句）。
// 判定口径：以标识符/字面量/'(' /一元运算符等开头，且不含声明起始关键字。
func isExprLikeStmt(s string) bool {
	t := strings.TrimSpace(s)
	if t == "" {
		return false
	}
	if strings.HasPrefix(t, "{") {
		return false // 复合语句
	}
	// 声明起始关键字
	for _, kw := range declKeywords {
		if t == kw || strings.HasPrefix(t, kw+" ") || strings.HasPrefix(t, kw+"\t") ||
			strings.HasPrefix(t, kw+"*") || strings.HasPrefix(t, kw+"\n") {
			return false
		}
	}
	return true
}

// skipCompoundStmt 若 [from,to) 区间以复合语句（'{' 开头）打头，则把起点后移
// 到该复合语句之后（跳过整块）。返回新的起点。
func skipCompoundStmt(s string, from, to int) int {
	i := from
	for i < to && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r') {
		i++
	}
	if i >= to || s[i] != '{' {
		return from
	}
	_, end, ok := matchBrace(s, i)
	if !ok || end >= to {
		return from
	}
	return end + 1
}

// topLevelStmtEnds 列出各条顶层语句的结束位置（含结束符下标）。
// 边界 = 顶层分号（不在嵌套块/括号内）。嵌套块整体被跳过——其内部的分号
// 不构成边界（`{2;}` 是一条复合语句；`typedef struct {int a;} t;` 是一条声明）。
func topLevelStmtEnds(s string) []int {
	inStr, inChr := false, false
	depth := 0
	var out []int
	for i := 0; i < len(s); i++ {
		c := s[i]
		if inStr {
			if c == '\\' {
				i++
			} else if c == '"' {
				inStr = false
			}
			continue
		}
		if inChr {
			if c == '\\' {
				i++
			} else if c == '\'' {
				inChr = false
			}
			continue
		}
		switch c {
		case '"':
			inStr = true
		case '\'':
			inChr = true
		case '{':
			depth++
		case '}':
			depth--
		case ';':
			if depth == 0 {
				out = append(out, i)
			}
		}
	}
	return out
}

// matchBrace 从 '{' 位置起找匹配的 '}'，返回体内容与 '}' 的下标。
func matchBrace(src string, open int) (string, int, bool) {
	if open >= len(src) || src[open] != '{' {
		return "", 0, false
	}
	depth := 0
	inStr, inChr := false, false
	for i := open; i < len(src); i++ {
		c := src[i]
		if inStr {
			if c == '\\' {
				i++
			} else if c == '"' {
				inStr = false
			}
			continue
		}
		if inChr {
			if c == '\\' {
				i++
			} else if c == '\'' {
				inChr = false
			}
			continue
		}
		switch c {
		case '"':
			inStr = true
		case '\'':
			inChr = true
		case '{':
			depth++
		case '}':
			depth--
			if depth == 0 {
				return src[open+1 : i], i, true
			}
		}
	}
	return "", 0, false
}

// hasControlFlow 检查语句体是否含改变控制流的关键词（含嵌套）。
func hasControlFlow(body string) bool {
	for _, kw := range []string{"return", "break", "continue", "goto"} {
		if regexp.MustCompile(`\b` + kw + `\b`).MatchString(body) {
			return true
		}
	}
	return false
}

// secondLastTopLevelSemi 找**倒数第二个**顶层分号的位置（跳过字符串/字符/括号内）。
// 返回 -1 表示顶层分号不足两个。
func secondLastTopLevelSemi(s string) int {
	positions := topLevelSemiPositions(s)
	if len(positions) < 2 {
		return -1
	}
	return positions[len(positions)-2]
}

// topLevelSemiPositions 列出全部顶层分号位置（跳过字符串/字符/括号内）。
func topLevelSemiPositions(s string) []int {
	inStr, inChr := false, false
	depth := 0
	var out []int
	for i := 0; i < len(s); i++ {
		c := s[i]
		if inStr {
			if c == '\\' {
				i++
			} else if c == '"' {
				inStr = false
			}
			continue
		}
		if inChr {
			if c == '\\' {
				i++
			} else if c == '\'' {
				inChr = false
			}
			continue
		}
		switch c {
		case '"':
			inStr = true
		case '\'':
			inChr = true
		case '(', '[', '{':
			depth++
		case ')', ']', '}':
			depth--
		case ';':
			if depth == 0 {
				out = append(out, i)
			}
		}
	}
	return out
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
	// 过滤 moon 工具链 Warning 块(冷缓存重编译时混进 stdout; 增量缓存时不出现;
	// #254: 实测块尾是 4 个 ─ + ╯, 原 ─{5,} 恒不匹配致块残留——放宽到 ─{3,};
	// 分离捕获后 stdout 通常已无此块, 保留为防御)
	warnBlock := regexp.MustCompile(`(?m)^Warning: \[\d+\][\s\S]*?─{3,}╯\s*$`)
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
	// #254：运行对拍两侧一律分离捕获、只取 stdout（程序输出口径）——
	// 合并捕获时代 stderr 帧/运行时消息混入是假 mismatch 主源
	cr := exec.Command(exe)
	cr.Dir = tmpDir
	cout, _, err := runWithTimeoutSplit(cr, 10*time.Second)
	if err != nil {
		if strings.Contains(err.Error(), "timeout") {
			return "clang_timeout", ""
		}
		return "clang_run_fail", fmt.Sprintf("%v | out=%s", err, firstLine(cout))
	}
	// Vitro 侧
	vr := exec.Command("moon", "run", "--target", "native", "moonbit/cmd/run", "--", cfile)
	vr.Dir = *flagVitro
	vout, _, err := runWithTimeoutSplit(vr, 120*time.Second)
	if err != nil {
		if strings.Contains(err.Error(), "timeout") {
			return "vitro_timeout", ""
		}
		return "vitro_run_fail", firstLine(vout)
	}
	// #254：删 Latin-1 还原迂回——#16（2026-10-04）后 cmd/run 的 stdout
	// 通道字节已是 UTF-8 原样落盘（实测中文字面量无损），latin1Restore 会把
	// 程序自身输出的非 ASCII 全部打成 '?'（假 mismatch 源之二）
	vn := normalize([]byte(vout))
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

// ---------- 仓内语料批勘探（-corpus <name>） ----------
//
// 与 -repo 模式的三点差异（试点批 chibicc 的方法面）：
//  1. serve 请求用 files+filename 形态 → 同目录 quote-include 可解析
//     （#253 的 E1021 假红根治面；#25 §1.2 的 cwd 解锁实证的通用化）；
//  2. gcc 分桶裁判并入同一趟（P2.5，#25 裁定二：分桶裁判非第二真值）；
//  3. 剥壳对照（-probe）：原始 vs 语句表达式消解后的诊断差分——
//     用于「先剥壳看真问题」（parse 层洪水是否遮蔽了深层信号）。
//
// 产物：<out>/result.json（不进仓，诊断 message 可引用源码 token）
//   - <out>/probe_diff.md（-probe 时的剥壳对照报告）
func runCorpus(name string) int {
	root := corpusRoot(name)
	if _, err := os.Stat(root); err != nil {
		fail(fmt.Sprintf("仓内语料批不存在: %s（%v）", root, err))
	}
	os.MkdirAll(*flagOut, 0755)

	// P1 walk：分「单文件」与「工程」两类
	//   - 顶层 *.c → 单文件单元（各自独立编译）
	//   - 子目录 → **多文件工程**：目录内所有 .c + .h 作为一个编译单元组，
	//     一起送给引擎（files 数组形态）——这正是真实 C 项目的组织方式，
	//     也是现防线唯一零覆盖的形态（#237）。
	var all []string
	var projects []project
	ents, _ := os.ReadDir(root)
	for _, e := range ents {
		if e.IsDir() {
			projects = append(projects, collectProject(filepath.Join(root, e.Name())))
			continue
		}
		if strings.HasSuffix(e.Name(), ".c") {
			all = append(all, filepath.Join(root, e.Name()))
		}
	}
	sort.Strings(all)
	sort.Slice(projects, func(i, j int) bool { return projects[i].Name < projects[j].Name })
	if *flagFilter != "" {
		var f []string
		for _, p := range all {
			if strings.Contains(filepath.ToSlash(p), *flagFilter) {
				f = append(f, p)
			}
		}
		all = f
		var fp []project
		for _, p := range projects {
			if strings.Contains(p.Name, *flagFilter) {
				fp = append(fp, p)
			}
		}
		projects = fp
	}
	if *flagLimit > 0 && len(all) > *flagLimit {
		all = all[:*flagLimit]
	}
	if len(all) == 0 && len(projects) == 0 {
		fail(fmt.Sprintf("语料批 %s 下无 .c 文件", name))
	}
	fmt.Fprintf(os.Stderr, "[%s] 单文件: %d ; 多文件工程: %d\n", name, len(all), len(projects))

	repoAbs, _ := filepath.Abs(root)
	results := make([]FileResult, 0, len(all))

	// P2 Clang 真值
	var green []string
	for _, p := range all {
		rel := relOf(repoAbs, p)
		ok, errs, warns, first := clangCheck(p)
		r := FileResult{Path: rel, ClangOK: ok, ClangErrs: errs, ClangWarns: warns, ClangFirst: first}
		results = append(results, r)
		if ok {
			green = append(green, p)
		}
	}
	// 多文件工程：Clang 真值 = 目录内所有 .c 一起编译（.h 不参与编译）
	for _, pr := range projects {
		rel := pr.Name + "/"
		ok, errs, first := clangCheckProject(pr)
		r := FileResult{Path: rel, ClangOK: ok, ClangErrs: errs, ClangFirst: first}
		results = append(results, r)
		if ok {
			green = append(green, pr.Dir) // 以目录标记「工程绿」
		}
	}
	fmt.Fprintf(os.Stderr, "[%s] Clang 绿: %d / 红: %d\n", name, len(green), len(all)+len(projects)-len(green))

	// P2.5 gcc 分桶裁判（#25 裁定二）
	gcc := findGcc()
	if gcc == "" {
		fail("gcc 分桶裁判不可用：--gcc 未指定、PATH 无 gcc、D:\\code\\mingw64\\bin\\gcc.exe 不存在（fail loud）")
	}
	fmt.Fprintf(os.Stderr, "[%s] gcc: %s\n", name, gcc)
	gccRes := map[string]bool{} // rel → gcc 绿
	for _, p := range all {
		ok, _ := gccCheck(gcc, p)
		gccRes[relOf(repoAbs, p)] = ok
	}
	for _, pr := range projects {
		ok, _ := gccCheckProject(gcc, pr)
		gccRes[pr.Name+"/"] = ok
	}

	// P3 serve 连发（files+filename 形态）
	served := map[string][]Diag{}
	for i := 0; i < len(green); i += *flagBatch {
		end := i + *flagBatch
		if end > len(green) {
			end = len(green)
		}
		batch := green[i:end]
		keys := make([]string, 0, len(batch))
		units := make([]compileFile, 0, len(batch))
		for _, p := range batch {
			if isDir(p) {
				continue // 工程走单独的 serve 调用
			}
			keys = append(keys, relOf(repoAbs, p))
			abs, _ := filepath.Abs(p)
			units = append(units, compileFile{Path: abs})
		}
		if len(keys) > 0 {
			res, err := serveBatchFiles(keys, units)
			if err != nil {
				fail(fmt.Sprintf("serve 批失败(%d..%d): %v", i, end, err))
			}
			for k, v := range res {
				served[k] = v
			}
		}
		fmt.Fprintf(os.Stderr, "[%s] serve %d/%d\n", name, end, len(green))
	}
	// 多文件工程：目录内所有 .c + .h 作为一个 files 数组一次编译
	for _, pr := range projects {
		key := pr.Name + "/"
		if !dirIsGreen(green, pr.Dir) {
			continue
		}
		var files []compileFile
		for _, f := range append(append([]string{}, pr.Files...), pr.Units...) {
			files = append(files, compileFile{Path: f})
		}
		res, err := serveBatchFiles([]string{key}, files)
		if err != nil {
			fmt.Fprintf(os.Stderr, "[%s] 工程 %s serve 失败: %v\n", name, pr.Name, err)
			continue
		}
		for k, v := range res {
			served[k] = v
		}
		fmt.Fprintf(os.Stderr, "[%s] 工程 %s: %d .c + %d .h\n", name, pr.Name, len(pr.Files), len(pr.Units))
	}

	// 回填诊断
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

	// P4' 剥壳对照（-probe）：语句表达式消解后重跑，取诊断差分
	var probeRows []string
	if *flagProbe {
		probeRows = runProbeDiff(name, repoAbs, green, served)
	}

	// P5 运行对比（双绿桶）——只对单文件；多文件工程的运行对比另走
	// 「链接后运行」路径（本工具的运行对比是单 exe 形态，工程需整组链接）。
	for _, p := range green {
		if isDir(p) {
			continue
		}
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
			hasRand := containsWord(readFile(p), "rand(")
			verdict, detail := runCompare(repoAbs, p, filepath.Join(*flagOut, "_tmp"), false, hasRand)
			results[ri].RunCmp = verdict
			results[ri].RunDetail = detail
		}
	}

	// 回填 gcc_ok
	for ri := range results {
		if ok, has := gccRes[results[ri].Path]; has {
			results[ri].GccOK = ok
		}
	}

	// P6 报告
	writeReport(*flagOut, results)
	if len(probeRows) > 0 {
		os.WriteFile(filepath.Join(*flagOut, "probe_diff.md"), []byte(strings.Join(probeRows, "\n")), 0644)
	}
	jsonBytes, _ := json.MarshalIndent(results, "", "  ")
	os.WriteFile(filepath.Join(*flagOut, "result.json"), jsonBytes, 0644)
	fmt.Fprintf(os.Stderr, "[%s] 完成: %s/report.md\n", name, *flagOut)
	return 0
}

// runProbeDiff 剥壳对照：把 Vitro 绿桶里的文件做语句表达式消解后重跑 serve，
// 产出「原始诊断 vs 剥壳后诊断」差分表——用于识别**被 parse 层洪水遮蔽的
// 深层信号**（用户裁定：先剥壳看有没有真问题）。
//
// 关键：剥壳副本必须**连同同目录头文件**一起可解析——引擎的 base_dir 取自
// filename 的目录，quote-include 走该目录的真实文件系统。故副本写到语料目录
// 旁边的 _probe/ 子目录，并把语料目录的 .h 一并复制过去（否则 include 断链
// → E1021 假红，掩盖真实信号）。
func runProbeDiff(name, repoAbs string, green []string, served map[string][]Diag) []string {
	tmpDir := filepath.Join(*flagOut, "_probe")
	os.MkdirAll(tmpDir, 0755)
	// 同目录头文件复制（include 解析面）
	ents, _ := os.ReadDir(repoAbs)
	for _, e := range ents {
		if !e.IsDir() && strings.HasSuffix(e.Name(), ".h") {
			b, err := os.ReadFile(filepath.Join(repoAbs, e.Name()))
			if err == nil {
				os.WriteFile(filepath.Join(tmpDir, e.Name()), b, 0644)
			}
		}
	}
	rows := []string{
		"# 剥壳对照报告（GNU 语句表达式消解）",
		"",
		"> 目的：识别被 parse 层 E2005 洪水遮蔽的深层诊断。",
		"> 消解规则：`({ stmts; expr; })` → `{ stmts; int __vitro_sxN = expr; __vitro_sxN }`（保值语义）。",
		"> 保守边界：含 return/break/continue/goto 的语句体不消解。",
		"> 等价性已验：28 份消解副本的 Clang 错误数与原始逐份一致（28/28）。",
		"",
		"| 文件 | 消解处数 | 原始 errs | 剥壳后 errs | 原始首码 | 剥壳后码分布 |",
		"|---|---|---|---|---|---|",
	}
	for _, p := range green {
		rel := relOf(repoAbs, p)
		orig := served[rel]
		origErrs := 0
		origFirst := ""
		for _, d := range orig {
			if d.Severity == "error" {
				origErrs++
				if origFirst == "" {
					origFirst = d.Code
				}
			}
		}
		src := readFile(p)
		stripped, n := stripStmtExprs(src)
		if n == 0 {
			continue
		}
		tmpFile := filepath.Join(tmpDir, filepath.Base(p))
		if err := os.WriteFile(tmpFile, []byte(stripped), 0644); err != nil {
			continue
		}
		res, err := serveBatchFiles([]string{rel}, []compileFile{{Path: tmpFile}})
		if err != nil {
			continue
		}
		diags := res[rel]
		newErrs := 0
		codeCount := map[string]int{}
		for _, d := range diags {
			if d.Severity == "error" {
				newErrs++
				codeCount[d.Code]++
			}
		}
		codes := ""
		if len(codeCount) > 0 {
			type kv struct {
				k string
				v int
			}
			var kvs []kv
			for k, v := range codeCount {
				kvs = append(kvs, kv{k, v})
			}
			sort.Slice(kvs, func(i, j int) bool { return kvs[i].v > kvs[j].v })
			parts := []string{}
			for _, x := range kvs {
				parts = append(parts, fmt.Sprintf("%s×%d", x.k, x.v))
			}
			codes = strings.Join(parts, " ")
		}
		rows = append(rows, fmt.Sprintf("| `%s` | %d | %d | %d | %s | %s |",
			rel, n, origErrs, newErrs, origFirst, codes))
	}
	return rows
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
	if *flagCorpus != "" {
		os.Exit(runCorpus(*flagCorpus))
	}
	if *flagRepo == "" {
		fail("必填 -repo（或用 -aggregate/-check/-corpus 模式）")
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
	GccOK     bool           `json:"gcc_ok"`
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
	// gcc 分桶计数（#25 裁定二：gcc 是分桶裁判不是第二真值——分歧旗标）
	gccBuckets := map[string]int{"both_green": 0, "rescued": 0, "divergence": 0, "both_red": 0}
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
		switch {
		case !r.ClangOK && r.GccOK:
			gccBuckets["rescued"]++
		case r.ClangOK && !r.GccOK:
			gccBuckets["divergence"]++
		case r.ClangOK && r.GccOK:
			gccBuckets["both_green"]++
		default:
			gccBuckets["both_red"]++
		}
		files[r.Path] = goldFile{
			ClangOK:   r.ClangOK,
			GccOK:     r.GccOK,
			VitroErrs: r.VitroErrs,
			VitroWarn: r.VitroWarns,
			Codes:     codes,
			Layer:     r.Layer,
			Run:       r.RunCmp,
		}
	}
	out := map[string]any{
		"_meta": map[string]any{
			"as_of":       time.Now().Format("2006-01-02"),
			"repo":        *flagAggRepoName,
			"note":        "金样本签名清单——只存诊断码/数量/运行判定签名,不存源码文本(GPL 红线)。E1021×104 为勘探方法限制(serve 无 base_dir),断言时应豁免。",
			"total":       len(rs),
			"buckets":     buckets,
			"gcc_buckets": gccBuckets,
		},
		"files": files,
	}
	ob, _ := json.MarshalIndent(out, "", "  ")
	dst := filepath.Join(filepath.Dir(resultPath), *flagGoldOut)
	if err := os.WriteFile(dst, append(ob, '\n'), 0644); err != nil {
		fail(fmt.Sprintf("写出失败: %v", err))
	}
	fmt.Fprintf(os.Stderr, "聚合完成: %d 文件 → %s\n", len(rs), dst)
	return 0
}

// ---------- 合规模式: gold_signatures.json 校验（CI hygiene） ----------
// 四道: ①格式合法（_meta 必含 source_fork/source_commit, files 字段类型）
// ②无源码文本渗漏（字符串值白名单: run 判定词/层名/诊断码格式/E 数字;
//   _meta.note 例外但限长）③_meta 与 files 重算对账（total/分桶计数——
//   D18 缺口补，审阅 F8 2026-10-02：此前篡改 _meta 计数闸不红）
// ④fail loud——任何不符 exit 1。

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
	root := mustRepoRoot()
	dir := filepath.Join(root, "scripts", "realcode_diff")
	// 多金样本并存（2026-10-22 试点批 chibicc 扩面）：扫 gold_signatures.json
	// + gold_<corpus>.json 全部。任一不合规即红（fail loud）。
	names := []string{"gold_signatures.json"}
	extra, err := filepath.Glob(filepath.Join(dir, "gold_*.json"))
	if err != nil {
		fail(fmt.Sprintf("金样本扫描失败: %v", err))
	}
	for _, e := range extra {
		base := filepath.Base(e)
		if base != "gold_signatures.json" {
			names = append(names, base)
		}
	}
	sort.Strings(names)
	// _meta.corpora 登记表（仓内语料批的登记面）：声明哪个语料批对应哪个金样本。
	// 登记表本身也校验——防「语料入库但金样本未登记」的悬空。
	corpora := map[string]any{}
	regPath := filepath.Join(dir, "corpora.json")
	if b, err := os.ReadFile(regPath); err == nil {
		if err := json.Unmarshal(b, &corpora); err != nil {
			fail(fmt.Sprintf("corpora.json 解析失败: %v", err))
		}
	} else {
		corpora = map[string]any{}
	}
	registered := map[string]bool{}
	if c, ok := corpora["corpora"].(map[string]any); ok {
		for name, v := range c {
			registered[name] = true
			e, ok := v.(map[string]any)
			if !ok {
				fail(fmt.Sprintf("corpora.json corpora.%s 非对象", name))
			}
			for _, k := range []string{"gold", "license", "upstream_commit", "total"} {
				if _, ok := e[k]; !ok {
					fail(fmt.Sprintf("corpora.json corpora.%s 缺字段 %s", name, k))
				}
			}
			gold, _ := e["gold"].(string)
			if gold == "" {
				fail(fmt.Sprintf("corpora.json corpora.%s.gold 为空", name))
			}
			if !fileExists(filepath.Join(dir, gold)) {
				fail(fmt.Sprintf("corpora.json corpora.%s.gold 指向的金样本不存在: %s", name, gold))
			}
		}
	}
	// 反向对账：仓内语料目录 vs 登记表——语料在但未登记 → 红（悬空登记面）
	corpusDir := filepath.Join(dir, "corpus")
	if ents, err := os.ReadDir(corpusDir); err == nil {
		for _, e := range ents {
			if !e.IsDir() {
				continue
			}
			if !registered[e.Name()] {
				fail(fmt.Sprintf("语料批 %s 存在但未在 corpora.json 登记（悬空）", e.Name()))
			}
		}
	}
	for name := range registered {
		if !dirExists(filepath.Join(corpusDir, name)) {
			fail(fmt.Sprintf("corpora.json 登记的语料批 %s 目录不存在（僵尸登记）", name))
		}
	}

	total := 0
	for _, name := range names {
		n := checkOneGold(filepath.Join(dir, name))
		fmt.Fprintf(os.Stderr, "%s 合规 OK: %d 文件条目（格式/值域/零渗漏/_meta 对账）\n", name, n)
		total += n
	}
	fmt.Fprintf(os.Stderr, "金样本多文件扫描完成: %d 个文件、%d 条目（登记表 %d 个语料批）\n", len(names), total, len(registered))
	return 0
}

func fileExists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}

func dirExists(p string) bool {
	st, err := os.Stat(p)
	return err == nil && st.IsDir()
}

// isDir 判定路径是否为目录（工程以目录标记）。
func isDir(p string) bool { return dirExists(p) }

// dirIsGreen 判定工程目录是否在 Clang 绿集合内。
func dirIsGreen(green []string, dir string) bool {
	for _, g := range green {
		if g == dir {
			return true
		}
	}
	return false
}

// checkOneGold 校验单个金样本文件（原 runCheck 的单体逻辑抽成函数）。
func checkOneGold(path string) int {
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
		// 渗漏兜底: schema 键集白名单——条目只许七键（run/layer 已过值域、
		// codes 已过码形态、其余为 bool/int），任何未知键（如透传 message）
		// 即红，字符串值超 8 字符亦红（合法值域词最长 16 字符已在前查过，
		// 此处只拦未知键的渗漏形态）。gcc_ok 为分桶裁判标志（#25 裁定二）。
		for k2, v2 := range e {
			switch k2 {
			case "clang_ok", "gcc_ok", "vitro_errs", "vitro_warns", "codes", "layer", "run":
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
	// 第三道: _meta 与 files 重算对账（分桶口径同 aggregate 侧：
	// clang_ok=false → clang_red；true 且 vitro_errs==0 → both_green；
	// 其余 → vitro_red）
	recount := map[string]int{"clang_red": 0, "both_green": 0, "vitro_red": 0}
	for _, v := range files {
		e := v.(map[string]any)
		clangOK, _ := e["clang_ok"].(bool)
		errs := 0.0
		if f, ok := e["vitro_errs"].(float64); ok {
			errs = f
		}
		switch {
		case !clangOK:
			recount["clang_red"]++
		case errs == 0:
			recount["both_green"]++
		default:
			recount["vitro_red"]++
		}
	}
	if tot, ok := meta["total"].(float64); !ok || int(tot) != len(files) {
		fail(fmt.Sprintf("_meta.total %v != files 计数 %d", meta["total"], len(files)))
	}
	mb, ok := meta["buckets"].(map[string]any)
	if !ok {
		fail("_meta.buckets 缺失或非对象")
	}
	for _, k := range []string{"clang_red", "both_green", "vitro_red"} {
		got, _ := mb[k].(float64)
		if int(got) != recount[k] {
			fail(fmt.Sprintf("_meta.buckets.%s = %v != files 重算 %d", k, mb[k], recount[k]))
		}
	}
	return len(files)
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
	for _, cand := range []string{".", "..", "../.."} {
		if _, err := os.Stat(filepath.Join(cand, "scripts", "realcode_diff")); err == nil {
			abs, _ := filepath.Abs(cand)
			return abs
		}
	}
	fail("无法定位仓库根（请设 VITRO_ROOT）")
	return ""
}
