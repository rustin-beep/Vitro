// clang_direct：§7.1 层 2 直拍防线（2026-09-26 落地——原排期 S7 稳定片期，
// 用户拍板前移至 S6 收官窗口：减少 0.6.0 发包前的 bug 概率）。
//
// 真值源 = Clang 本尊（非 Rust oracle）：编译并运行语料得 golden，与
// MoonBit cmd/run 的 stdout + 返回码比对。与 vm_diff 的分工——
//
//	vm_diff      = 引擎 vs Rust oracle（同构对拍，抓迁移偏差）；
//	clang_direct = 引擎 vs Clang（真值直拍，抓两侧共同偏差——oracle 本身
//	               错而 Clang 对的形态只有本防线能抓）。
//
// 形态复刻（§7.1 层 2 定义：shadow_verify 的 Clang 侧设施全复用、被测物换
// cmd/run exe、输出比对复用 vm_diff 提取器——"新写仅绑定层"。Go main 包
// 不可被 import，故为**形态复刻**而非进程内复用；口径变更须双侧同步：
// 本文件 ↔ scripts/vm_diff/main.go（MoonBit 提取/新鲜度门禁）↔
// scripts/shadow_verify/main.go（Clang 缓存/重试/并发口径）。
//
// Clang 侧口径（照搬 shadow_verify）：
//   - 编译参数 clangCompileArgs 同款（-Wno-implicit-function-declaration +
//     非 Windows 加 -lm）；
//   - 编译失败/环境异常重试 3 次（500ms×attempt 递增；程序自身 exit != 0
//     是确定性行为不重试）；瞬态异常（超时/启动失败）不落缓存；
//   - 编译产物 per-case 唯一命名 + worker 槽位隔离目录（Windows 同名 exe
//     映像竞态，shadow 并行化实证）；
//   - 结果缓存 .clang_cache_cd/（与 shadow 的 .clang_cache/ 同级共存、
//     key 空间不相交——schema 前缀 cd1；key = 源码+stdin+clang 版本+参数）。
//
// MoonBit 侧口径（照搬 vm_diff）：
//   - cmd/run exe 预编译直跑 + 新鲜度门禁（mtime 触发 + 构建复核）；
//   - stdout 提取：剥 `// EXIT N` / `// TRAP` / `// COMPILE-ERROR` 标记行；
//   - **Latin-1 归一**（本防线特有）：cmd/run 把程序输出的每字节按 Latin-1
//     落 UTF-8 文本（0xC8 → U+00C8 → 0xC3 0x88），与 Clang 的原字节比对前
//     须还原：MoonBit 侧 0xC2/0xC3 引导的双字节序折回单字节（U+0080–U+00FF
//     封闭域，无损可逆）。putchar(≥128) 族差异由此直面真值。
//
// verdict：SAME（含双侧编译失败等价）/ DIFF-known（known_direct.json，
// case+digest 锁定，digest 漂移降级红防白名单腐化；条目转绿即红逼移除）/
// DIFF（红）。known 台账配方沿用 shadow KNOWN_FAILURE_CASES 双向监控。
//
// 用法：go run ./scripts/clang_direct [--sample N | --corpus dir | --cases f1.c,...] [--jobs N]
//
//	（默认四语料全量 baseline+knr+leetcode+gap = 601 例；--jobs 默认 min(CPU,8)）
package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
	"time"
)

const runnerExe = "moonbit/_build/native/release/build/cmd/run/run.exe"

const clangCacheDir = ".clang_cache_cd"

const cacheSchema = "cd1"

const clangPath = "clang"

const clangRetry = 3

const clangRunTimeout = 10 * time.Second

var corporaDefault = []string{"baseline", "knr", "leetcode", "gap"}

// knownEntry：已归因差异（case + digest + reason；digest = 差异内容 sha256
// 前 8 位——漂移即降级 DIFF 逼重新归因）。
type knownEntry struct {
	Case   string `json:"case"`
	Digest string `json:"digest"`
	Reason string `json:"reason"`
}

type knownList struct {
	entries []knownEntry
	hit     map[string]bool
}

type clangResult struct {
	compileFail bool
	abnormal    bool // 瞬态环境异常（不落缓存）
	stdout      string
	exitCode    int
}

type moonResult struct {
	compileFail bool
	stdout      string // 已 Latin-1 归一（还原单字节）
	exitCode    int
	memoryPath  string // --dump-memory 产物（正向证据：恰 1MB）
}

type caseRef struct {
	rel  string
	path string
}

func main() {
	corpora := corporaDefault
	sample := 0
	jobs := 0
	var explicit []string
	args := os.Args[1:]
	for i := 0; i < len(args); i++ {
		switch {
		case args[i] == "--corpus" && i+1 < len(args):
			i++
			corpora = []string{args[i]}
		case args[i] == "--sample" && i+1 < len(args):
			i++
			fmt.Sscanf(args[i], "%d", &sample)
		case args[i] == "--cases" && i+1 < len(args):
			i++
			explicit = strings.Split(args[i], ",")
		case args[i] == "--jobs" && i+1 < len(args):
			i++
			fmt.Sscanf(args[i], "%d", &jobs)
		default:
			fmt.Fprintf(os.Stderr, "clang_direct: 未知参数 %q\n", args[i])
			os.Exit(2)
		}
	}

	// 前置：runner 存在 + 新鲜度门禁（vm_diff 同款：mtime 触发 + 构建复核）
	if !fileExists(runnerExe) {
		fmt.Fprintf(os.Stderr, "clang_direct: %s 不存在——先跑 cd moonbit && moon build --release --target native cmd/run\n", runnerExe)
		os.Exit(2)
	}
	if stale := findStaleSource(runnerExe); stale != "" {
		fmt.Fprintf(os.Stderr, "clang_direct: %s 旧于源 %s——跑构建复核...\n", runnerExe, stale)
		cmd := exec.Command("moon", "build", "--release", "--target", "native", "cmd/run")
		cmd.Dir = "moonbit"
		if out, err := cmd.CombinedOutput(); err != nil {
			fmt.Fprintf(os.Stderr, "clang_direct: 构建复核失败：%v\n%s（判失败前先看全量输出——| head 会 SIGPIPE 截断）\n", err, tailAll(out))
			os.Exit(2)
		}
		if !fileExists(runnerExe) {
			fmt.Fprintf(os.Stderr, "clang_direct: 构建成功但 %s 仍缺失\n", runnerExe)
			os.Exit(2)
		}
	}

	// clang 可用性 fail fast（shadow 门禁同款纪律：缺失即 exit 2，不静默跳过）
	if _, err := exec.LookPath(clangPath); err != nil {
		fmt.Fprintf(os.Stderr, "clang_direct: 未找到 %s——Clang 是本防线真值源，缺失即红（安装或修正 PATH）\n", clangPath)
		os.Exit(2)
	}
	clangVersion := clangVersionString()

	cases := collectCases(corpora, sample, explicit)
	if len(cases) == 0 {
		fmt.Fprintln(os.Stderr, "clang_direct: 无用例")
		os.Exit(1)
	}

	known := loadKnown()
	// 白名单防腐化（静态部分）：known 条目名不在用例集合即红（全量模式才判）
	if fullCorpusRun(corpora, explicit, sample) {
		names := map[string]bool{}
		for _, c := range cases {
			names[filepath.Base(c.rel)] = true
		}
		for _, e := range known.entries {
			if !names[e.Case] {
				fmt.Fprintf(os.Stderr, "clang_direct: known 白名单空转条目 %s——语料中不存在（删除或修正）\n", e.Case)
				os.Exit(1)
			}
		}
	}

	if jobs <= 0 {
		jobs = runtime.NumCPU()
		if jobs > 8 {
			jobs = 8
		}
	}

	// ── 双侧执行 ──
	// Clang 侧并发（worker 槽位隔离目录）；MoonBit 侧主线程串行（VM exe
	// 单实例保守口径与 vm_diff 同前提）。两结果数组分离，避免并发写竞争。
	clangRes := make([]*clangResult, len(cases))
	moonRes := make([]*moonResult, len(cases))
	var wg sync.WaitGroup
	sem := make(chan struct{}, jobs)
	for k := range cases {
		wg.Add(1)
		go func(k int) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			clangRes[k] = runClang(cases[k], k%jobs, clangVersion)
		}(k)
	}
	for k := range cases {
		moonRes[k] = runMoon(cases[k])
	}
	wg.Wait()

	same, knownN, diff := 0, 0, 0
	for k, c := range cases {
		base := filepath.Base(c.rel)
		o, m := clangRes[k], moonRes[k]
		if o.compileFail && m.compileFail {
			fmt.Printf("SAME  %s（双侧编译失败——等价）\n", c.rel)
			same++
			continue
		}
		issues := compareDirect(o, m)
		cleanupMoon(m)
		if len(issues) == 0 {
			fmt.Printf("SAME  %s\n", c.rel)
			same++
			continue
		}
		// P3-7（2026-09-26 审阅）：digest 混入 case 名——两条用例的差异
		// 文本完全相同时 digest 亦同（指针宽度两例撞车实锤），白名单豁免
		// 必须钉到「这一例的这种差异」而非「任何一例的这种差异」。
		digest := issueDigest(append([]string{base}, issues...))
		if e, ok := known.lookup(base); ok {
			if e.Digest == digest {
				fmt.Printf("DIFF-KNOWN %s（%s；digest=%s）\n", c.rel, e.Reason, digest)
				knownN++
				continue
			}
			fmt.Printf("DIFF  %s：已知差异形状已变（登记 %s 实测 %s）——重新归因更新 known_direct.json：%s\n",
				c.rel, e.Digest, digest, strings.Join(issues, "；"))
			diff++
			continue
		}
		fmt.Printf("DIFF  %s [%s]：%s\n", c.rel, digest, strings.Join(issues, "；"))
		diff++
	}
	fmt.Printf("\nclang_direct: SAME=%d DIFF-KNOWN=%d DIFF=%d（共 %d）\n",
		same, knownN, diff, same+knownN+diff)

	// 白名单防腐化（动态部分）：known 条目未命中即红（转绿逼移除）
	if fullCorpusRun(corpora, explicit, sample) {
		bad := false
		for _, e := range known.entries {
			if !known.hit[e.Case] {
				fmt.Fprintf(os.Stderr, "clang_direct: known 白名单空转条目 %s——本轮未产生差额（用例已转绿则删除，双向监控纪律）\n", e.Case)
				bad = true
			}
		}
		if bad {
			os.Exit(1)
		}
	}
	if diff > 0 {
		os.Exit(1)
	}
}

// fullCorpusRun：真·全量（默认四语料、无 --cases/--sample）——--corpus 单
// 语料是子集运行，白名单空转校验（静态与动态）只在此形态判，否则
// `--corpus gap` 会误报「engine_note_lookalike.c 不在本轮」（P3-6，
// 2026-09-26 审阅：usage 写着支持 --corpus 却恒误红）。
func fullCorpusRun(corpora []string, explicit []string, sample int) bool {
	if len(explicit) != 0 || sample != 0 {
		return false
	}
	if len(corpora) != len(corporaDefault) {
		return false
	}
	for i := range corpora {
		if corpora[i] != corporaDefault[i] {
			return false
		}
	}
	return true
}

// cleanupMoon：runMoon 映像文件清理（compare 消费后）。
func cleanupMoon(m *moonResult) {
	if m != nil && m.memoryPath != "" {
		os.Remove(m.memoryPath)
	}
}

func fileExists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}

func tailAll(b []byte) string {
	if len(b) > 2000 {
		return string(b[len(b)-2000:])
	}
	return string(b)
}

func collectCases(corpora []string, sample int, explicit []string) []caseRef {
	var out []caseRef
	if len(explicit) > 0 {
		for _, c := range explicit {
			p := ""
			for _, corpus := range corporaDefault {
				cand := filepath.Join("native", "tests", "cases", corpus, c)
				if fileExists(cand) {
					p = cand
					break
				}
			}
			if p == "" {
				// 允许全路径
				p = c
			}
			out = append(out, caseRef{rel: p, path: p})
		}
		return out
	}
	for _, c := range corpora {
		dir := filepath.Join("native", "tests", "cases", c)
		entries, err := os.ReadDir(dir)
		if err != nil {
			continue
		}
		for _, e := range entries {
			if e.IsDir() || !strings.HasSuffix(e.Name(), ".c") {
				continue
			}
			p := filepath.Join(dir, e.Name())
			out = append(out, caseRef{rel: filepath.ToSlash(p), path: p})
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].rel < out[j].rel })
	if sample > 0 && sample < len(out) {
		step := float64(len(out)) / float64(sample)
		sampled := make([]caseRef, 0, sample)
		for i := 0; i < sample; i++ {
			idx := int(float64(i) * step)
			if idx >= len(out) {
				idx = len(out) - 1
			}
			sampled = append(sampled, out[idx])
		}
		return sampled
	}
	return out
}

// ── Clang 侧（形态复刻 shadow_verify）──

func clangCompileArgs(cFile, exeFile string) []string {
	args := []string{cFile, "-o", exeFile, "-Wno-implicit-function-declaration"}
	if runtime.GOOS != "windows" {
		args = append(args, "-lm")
	}
	return args
}

func clangVersionString() string {
	out, err := exec.Command(clangPath, "--version").Output()
	if err != nil {
		return "unknown"
	}
	return strings.TrimSpace(string(out))
}

type cachePayload struct {
	Schema      string `json:"schema"`
	Stdout      string `json:"stdout"`
	ExitCode    int    `json:"exit_code"`
	CompileFail bool   `json:"compile_fail"`
}

func cacheKey(src []byte, clangVersion string) string {
	h := sha256.New()
	h.Write([]byte(cacheSchema))
	h.Write([]byte{0})
	h.Write(src)
	h.Write([]byte{0})
	h.Write([]byte(clangVersion))
	h.Write([]byte{0})
	args := clangCompileArgs("<src>", "<exe>")
	h.Write([]byte(strings.Join(args, " ")))
	return fmt.Sprintf("%x", h.Sum(nil))[:40]
}

func runClang(c caseRef, slot int, clangVersion string) *clangResult {
	src, err := os.ReadFile(c.path)
	if err != nil {
		return &clangResult{compileFail: true, abnormal: true}
	}
	key := cacheKey(src, clangVersion)
	if data, err := os.ReadFile(filepath.Join(clangCacheDir, key+".json")); err == nil {
		var p cachePayload
		if json.Unmarshal(data, &p) == nil && p.Schema == cacheSchema {
			return &clangResult{compileFail: p.CompileFail, stdout: p.Stdout, exitCode: p.ExitCode}
		}
	}
	// 重试判据（shadow_verify 同款）：「编译成功且非瞬态异常」才接受——
	// 编译失败也重试（Windows 并发下 Defender 实时扫描锁目标文件会让 clang
	// 以非零退出，首跑 127 例实锤；重试 3 次仍失败才接受为结果——真确定性
	// 失败重试只是浪费 1.5s，换来瞬态不误判）。
	var res *clangResult
	for attempt := 0; attempt < clangRetry; attempt++ {
		res = runClangOnce(c, slot)
		if !res.compileFail && !res.abnormal {
			break
		}
		// 指数退避 1s/2s/4s（P1-1 收敛批：全量并发下邻居编译窗口 >1.5s，
		// 线性 500ms 退避 3 次仍可能全程落在竞态窗内——实测同 4 例连续
		// 3 轮重试全失败、单独跑即绿）
		time.Sleep(time.Duration(1000<<attempt) * time.Millisecond)
	}
	// 编译失败结果**不落缓存**（2026-09-26 审阅 P1-1 连带修复）：Windows
	// 全量并发下调度竞态会让 clang 以 ExitError 伪装成确定性失败——三态
	// 实证：全量 601 两轮稳定同 4 例 / 同 4 例单独并发 3 轮全绿 / 串行
	// jobs=1 绿。缓存会把竞态快照固化成假确定性（key 不含运行环境状态）。
	// 代价 = 每轮重算 ~10 个真编译失败例（每例 <1s），换来毒化通道封死。
	if res != nil && !res.abnormal && !res.compileFail {
		storeCache(key, res)
	}
	return res
}

// runClangOnce：槽位隔离目录内编译 + 运行（stdin 空——与 MoonBit 侧同口径）。
func runClangOnce(c caseRef, slot int) *clangResult {
	runDir := filepath.Join(os.TempDir(), fmt.Sprintf("clang_direct_%d_%d", os.Getpid(), slot))
	if err := os.MkdirAll(runDir, 0o755); err != nil {
		return &clangResult{compileFail: true, abnormal: true}
	}
	defer os.RemoveAll(runDir)
	base := filepath.Base(c.path)
	ext := ".exe"
	if runtime.GOOS != "windows" {
		ext = ""
	}
	exeFile := filepath.Join(runDir, strings.TrimSuffix(base, ".c")+ext)
	compileCmd := exec.Command(clangPath, clangCompileArgs(c.path, exeFile)...)
	var cOut bytes.Buffer
	compileCmd.Stdout = &cOut
	compileCmd.Stderr = &cOut
	if err := compileCmd.Run(); err != nil {
		if _, ok := err.(*exec.ExitError); ok {
			// 编译失败：确定性行为（源码不支持），落缓存
			return &clangResult{compileFail: true, stdout: cOut.String()}
		}
		return &clangResult{compileFail: true, abnormal: true}
	}
	// 运行（超时 = 环境异常可重试；exit != 0 = 确定性结果）。
	// **cwd = 槽位隔离目录**（2026-09-26 审阅 P1-1 修复）：此前在仓库根跑，
	// fopen("test.txt") 族用例真读写仓库根的 gitignore 遗留文件，且 8 路并发
	// 互相覆盖同源竞态（连跑两轮 DIFF=2/4，用户实测）——隔离后这些用例回到
	// 确定性的 fopen 失败形态，known_direct 相应重新归因。
	runCmd := exec.Command(exeFile)
	runCmd.Dir = runDir
	var rOut bytes.Buffer
	runCmd.Stdout = &rOut
	runCmd.Stderr = &rOut
	timer := time.AfterFunc(clangRunTimeout, func() { runCmd.Process.Kill() })
	defer timer.Stop()
	err := runCmd.Run()
	code := 0
	if exitErr, ok := err.(*exec.ExitError); ok {
		code = exitErr.ExitCode()
	} else if err != nil {
		return &clangResult{compileFail: false, abnormal: true, stdout: rOut.String()}
	}
	return &clangResult{stdout: rOut.String(), exitCode: code}
}

func storeCache(key string, r *clangResult) {
	_ = os.MkdirAll(clangCacheDir, 0o755)
	p := cachePayload{Schema: cacheSchema, Stdout: r.stdout, ExitCode: r.exitCode, CompileFail: r.compileFail}
	data, err := json.Marshal(p)
	if err != nil {
		return
	}
	tmp := filepath.Join(clangCacheDir, key+".tmp")
	if os.WriteFile(tmp, data, 0o644) == nil {
		_ = os.Rename(tmp, filepath.Join(clangCacheDir, key+".json"))
	}
}

// ── MoonBit 侧（形态复刻 vm_diff）──

func runMoon(c caseRef) *moonResult {
	// P2-4（2026-09-26 审阅）：加 --dump-memory 正向证据通道——此前把
	// run.exe 换成 `int main(){return 0;}` 的静默 exe 仍报 SAME（空 stdout
	// + exit 0 全对上）。映像恰 1MB 是 runner 真跑了编译装载全链的充分
	// 证据（vm_diff 同款口径）；缺失/非 1MB 进 issues 红。
	tmp, err := os.CreateTemp("", "cdmem_*.bin")
	if err != nil {
		return &moonResult{compileFail: true, stdout: "// TMPFAIL"}
	}
	tmp.Close()
	// 注意：不 defer 删除——compareDirect 消费映像在 runMoon 返回之后
	//（vm_diff 曾同坑：defer 先删致校验永假）；清理由主循环 cleanup 承担。
	var out bytes.Buffer
	cmd := exec.Command(filepath.FromSlash(runnerExe), c.path, "--dump-memory", tmp.Name())
	cmd.Stdout = &out
	cmd.Stderr = &out
	_ = cmd.Run()
	s := out.String()
	r := &moonResult{stdout: s, memoryPath: tmp.Name()}
	if strings.Contains(s, "// COMPILE-ERROR") {
		r.compileFail = true
	}
	for _, line := range strings.Split(s, "\n") {
		if strings.HasPrefix(strings.TrimRight(line, "\r"), "// EXIT ") {
			fmt.Sscanf(strings.TrimRight(line, "\r"), "// EXIT %d", &r.exitCode)
		}
	}
	r.stdout = extractMoonStdout(s)
	return r
}

// extractMoonStdout：剥协议标记行（// EXIT / // TRAP / // COMPILE-ERROR 族）
// + Latin-1 归一（cmd/run 的 UTF-8 双字节形态折回单字节——U+0080–U+00FF
// 封闭域无损可逆）。
func extractMoonStdout(s string) string {
	// 协议形状提取（vm_diff extractMoonBitStdout 同款口径）：剥标记行 →
	// 尾部空行剥 → 末行 // EXIT 剥 → CRLF 归一 + 首尾空行剥。
	lines := strings.Split(s, "\n")
	var kept []string
	for _, l := range lines {
		t := strings.TrimRight(l, "\r")
		if strings.HasPrefix(t, "// TRAP ") || strings.HasPrefix(t, "// COMPILE-ERROR ") {
			continue
		}
		kept = append(kept, l)
	}
	for len(kept) > 0 && strings.TrimRight(kept[len(kept)-1], "\r") == "" {
		kept = kept[:len(kept)-1]
	}
	if n := len(kept); n > 0 {
		if strings.HasPrefix(strings.TrimRight(kept[n-1], "\r"), "// EXIT ") {
			kept = kept[:n-1]
		}
	}
	return latin1Fold(normalizeLines(kept))
}

// normalizeLines：CRLF 归一 + 首尾空行剥（vm_diff 同款；无尾换行 join）。
func normalizeLines(lines []string) string {
	out := make([]string, 0, len(lines))
	for _, l := range lines {
		out = append(out, strings.TrimRight(l, "\r"))
	}
	for len(out) > 0 && out[len(out)-1] == "" {
		out = out[:len(out)-1]
	}
	for len(out) > 0 && out[0] == "" {
		out = out[1:]
	}
	return strings.Join(out, "\n")
}

// normalizeClangStdout：clang golden 行级归一——Windows 下 Clang 编译的原生
// 程序 stdout 为文本模式（\n 伸缩为 \r\n），比对前剥 \r 对齐引擎侧字节口径；
// 不做其它清洗（比对读纯程序输出，驱动侧禁再动内容——E-P1-5）。
func normalizeClangStdout(s string) string {
	return normalizeLines(strings.Split(s, "\n"))
}

// latin1Fold：UTF-8 的 U+0080–U+00FF 双字节序折回 Latin-1 单字节。
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

// ── 比对 ──

func compareDirect(o *clangResult, m *moonResult) []string {
	var issues []string
	if o.compileFail != m.compileFail {
		who := "clang"
		if m.compileFail {
			who = "moonbit"
		}
		detail := ""
		if o.compileFail {
			// clang 错误首行入报文（诊断可达——并发一过性失败与真源码
			// 不支持靠它区分，P1-1 收敛批）
			for _, l := range strings.Split(o.stdout, "\n") {
				if t := strings.TrimSpace(l); t != "" {
					detail = "；" + clip(t)
					break
				}
			}
		}
		issues = append(issues, fmt.Sprintf("单侧编译失败（%s%s）", who, detail))
		return issues
	}
	if o.compileFail {
		return issues // 双侧失败等价（调用方判）
	}
	if normalizeClangStdout(o.stdout) != m.stdout {
		issues = append(issues, summarizeStdout(normalizeClangStdout(o.stdout), m.stdout))
	}
	if o.exitCode != m.exitCode {
		issues = append(issues, fmt.Sprintf("返回码 %d != %d", o.exitCode, m.exitCode))
	}
	// 正向证据（P2-4）：runner 真跑了全链 ⇒ 映像恰 1MB。静默 exe / 假 runner
	// 在此红（实测：cmd/run 换 return-0 stub 时本条必红）。
	if !m.compileFail {
		switch {
		case m.memoryPath == "":
			issues = append(issues, "映像缺失（runner 未产出 dump）")
		default:
			if md, err := os.ReadFile(m.memoryPath); err != nil {
				issues = append(issues, fmt.Sprintf("映像读取失败（%v）", err))
			} else if len(md) != 1024*1024 {
				issues = append(issues, fmt.Sprintf("映像非 1MB（%d）——runner 全链正向证据缺失", len(md)))
			}
		}
	}
	return issues
}

func summarizeStdout(o, m string) string {
	ol := strings.Split(o, "\n")
	ml := strings.Split(m, "\n")
	for i := 0; i < len(ol) && i < len(ml); i++ {
		if ol[i] != ml[i] {
			return fmt.Sprintf("stdout 第 %d 行不一致（clang %q vs moonbit %q）", i+1, clip(ol[i]), clip(ml[i]))
		}
	}
	if len(ol) != len(ml) {
		return fmt.Sprintf("stdout 行数不一致（clang %d vs moonbit %d）", len(ol), len(ml))
	}
	return fmt.Sprintf("stdout 不一致（%d/%d 字节）", len(o), len(m))
}

func clip(s string) string {
	if len(s) > 40 {
		return s[:40] + "…"
	}
	return s
}

func issueDigest(issues []string) string {
	h := sha256.Sum256([]byte(strings.Join(issues, "‖")))
	return fmt.Sprintf("%x", h)[:8]
}

// ── known 台账 ──

func loadKnown() *knownList {
	kl := &knownList{hit: map[string]bool{}}
	data, err := os.ReadFile(filepath.Join("scripts", "clang_direct", "known_direct.json"))
	if err != nil {
		return kl
	}
	_ = json.Unmarshal(data, &kl.entries)
	return kl
}

func (k *knownList) lookup(base string) (knownEntry, bool) {
	for _, e := range k.entries {
		if e.Case == base {
			k.hit[e.Case] = true
			return e, true
		}
	}
	return knownEntry{}, false
}

// findStaleSource：runner 旧于任一 moonbit 源即返回该源（vm_diff 同款）。
func findStaleSource(exe string) string {
	var stale string
	st, err := os.Stat(exe)
	if err != nil {
		return "（stat 失败）"
	}
	_ = filepath.WalkDir("moonbit", func(p string, d os.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			switch d.Name() {
			case "_build", ".mooncakes":
				return filepath.SkipDir
			}
			return nil
		}
		n := d.Name()
		if !strings.HasSuffix(n, ".mbt") && !strings.HasSuffix(n, ".mod") && !strings.HasSuffix(n, ".pkg") {
			return nil
		}
		if fi, err := d.Info(); err == nil && fi.ModTime().After(st.ModTime()) {
			stale = p
		}
		return nil
	})
	return stale
}
