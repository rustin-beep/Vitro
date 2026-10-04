// Command perf_baseline 是**性能基线报告器**（报告型，无红绿判定）。
//
// 目的（2026-10-04 用户拍板入库）：把此前只存在于 `tmp/perf_probe/`（gitignore）
// 的性能探针收进仓库，使性能实录 §12/§13 的数字**可复跑、可审计**——不再"一人言"。
// 本仓《脚本总清单与必跑防线》§2.6 对 `scripts/unified_perf_baseline.py` 的处置行
// 早已预留「MoonBit 引擎性能走新基线工具」，本工具即该位置。
//
// 定位：
//   - **报告型**：只产 `reports/perf_baseline.md` + CI artifact，**不做红绿判定**
//     （照 `scripts/engineering_health` 先例；阈值门禁待基线固化后另议）。
//   - **语言 = Go**：遵本册 §三「判定型 / 会再跑的脚本语言 = Go」。
//   - **逐进程口径**：必须在**无 agent 注入层**的环境跑（CI runner / 计划任务 /
//     普通窗口）。本 agent 会话内进程创建 ~150ms（实录 §12.1/§13.1），会话内跑
//     量到的是"会话税"而非引擎性能。故工具**把启动定标打进报告并给有效性判词**，
//     读者据此判断本次采集是否可引用。
//
// 子模式（`-mode`）：
//
//	launch   启动定标：spawn 成本 + 「进 main 之前 / 退 main 之后」拆分（自 spawn 探针）
//	pipeline 四层 dump 工具 × 语料 × N 轮吞吐（端到端含写盘）
//	compare  MoonBit dump_compile vs Rust dump-compile 逐文件（比值跨时可对比）
//	ab       两版本树交替 A/B（需 -b-root；本地/按需跑，CI 不跑）
//	all      launch + pipeline + compare（默认）
//
// 规则外置 `rules.json`；缺产物 / 空语料即 **fail loud**（拒绝产假报告）；
// `-selftest` 为 J9 证红入口（子进程断言 fail-loud 路径真的会红）。
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"vitro/scripts/internal/capi"
)

const defaultRulesPath = "scripts/perf_baseline/rules.json"

// ─── 规则 ────────────────────────────────────────────────────────────────────

type rulesTool struct {
	ID        string   `json:"id"`
	ExtraArgs []string `json:"extra_args"`
}

type rulesCompare struct {
	Corpus   string `json:"corpus"`
	MoonTool string `json:"moon_tool"`
	RustVerb string `json:"rust_verb"`
}

type rulesAB struct {
	Corpus string   `json:"corpus"`
	Rounds int      `json:"rounds"`
	Tools  []string `json:"tools"`
}

type rulesDoc struct {
	Schema         int          `json:"schema"`
	CorpusRoot     string       `json:"corpus_root"`
	Corpora        []string     `json:"corpora"`
	Rounds         int          `json:"rounds"`
	TimeoutSec     int          `json:"timeout_sec"`
	MoonCmdRoot    string       `json:"moon_cmd_root"`
	MoonSourceRoot string       `json:"moon_source_root"`
	RustCLI        string       `json:"rust_cli"`
	DumpTools      []rulesTool  `json:"dump_tools"`
	OutRoot        string       `json:"out_root"`
	ReportPath     string       `json:"report_path"`
	LaunchReps     int          `json:"launch_reps"`
	Compare        rulesCompare `json:"compare"`
	AB             rulesAB      `json:"ab"`
}

func fatal(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "perf_baseline: FATAL: "+format+"\n", args...)
	os.Exit(2)
}

func loadRules(root, relPath string) rulesDoc {
	abs := filepath.Join(root, filepath.FromSlash(relPath))
	raw, err := os.ReadFile(abs)
	if err != nil {
		fatal("读规则失败(%s): %v", relPath, err)
	}
	var rd rulesDoc
	if err := json.Unmarshal(raw, &rd); err != nil {
		fatal("解析规则失败: %v", err)
	}
	if rd.CorpusRoot == "" || len(rd.Corpora) == 0 || len(rd.DumpTools) == 0 ||
		rd.MoonCmdRoot == "" || rd.RustCLI == "" || rd.OutRoot == "" || rd.ReportPath == "" {
		fatal("规则缺必需字段（corpus_root / corpora / dump_tools / moon_cmd_root / rust_cli / out_root / report_path）")
	}
	if rd.Rounds <= 0 {
		rd.Rounds = 5
	}
	if rd.TimeoutSec <= 0 {
		rd.TimeoutSec = 180
	}
	if rd.LaunchReps <= 0 {
		rd.LaunchReps = 12
	}
	if rd.Compare.MoonTool == "" {
		rd.Compare.MoonTool = "dump_compile"
	}
	if rd.Compare.RustVerb == "" {
		rd.Compare.RustVerb = "dump-compile"
	}
	if rd.Compare.Corpus == "" {
		rd.Compare.Corpus = rd.Corpora[0]
	}
	return rd
}

// ─── 计时原语 ────────────────────────────────────────────────────────────────

func timeoutOf(rd rulesDoc) time.Duration {
	return time.Duration(rd.TimeoutSec) * time.Second
}

// runTimed 跑一个子进程，返回 wall 时长与退出码（-1 = 启动失败）。
func runTimed(exe string, args []string, timeout time.Duration) (time.Duration, int) {
	t0 := time.Now()
	cmd := exec.Command(exe, args...)
	if err := cmd.Start(); err != nil {
		return time.Since(t0), -1
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	select {
	case <-done:
	case <-time.After(timeout):
		_ = cmd.Process.Kill()
		<-done
	}
	return time.Since(t0), cmd.ProcessState.ExitCode()
}

// spawnSplit 把一次 spawn 拆成 CreateProcess 本身 / 运行+退出 两段。
func spawnSplit(exe string, args []string) (create, run time.Duration) {
	t0 := time.Now()
	cmd := exec.Command(exe, args...)
	if err := cmd.Start(); err != nil {
		return time.Since(t0), 0
	}
	t1 := time.Now()
	_ = cmd.Wait()
	return t1.Sub(t0), time.Since(t1)
}

// stampSplit 跑「自 spawn 时间戳探针」（`<self> __stamp`）：子进程在 main 入口打
// epoch ns，父进程据此拆出「进 main 之前」与「退 main 之后」。
func stampSplit(self string, reps int) (preMs, postMs float64) {
	var pre, post []float64
	for i := 0; i < reps; i++ {
		e0 := time.Now()
		out, err := exec.Command(self, "__stamp").Output()
		e1 := time.Now()
		if err != nil {
			continue
		}
		var ns int64
		if _, err := fmt.Sscanf(strings.TrimSpace(string(out)), "%d", &ns); err != nil {
			continue
		}
		child := time.Unix(0, ns)
		pre = append(pre, float64(child.Sub(e0).Microseconds())/1000.0)
		post = append(post, float64(e1.Sub(child).Microseconds())/1000.0)
	}
	return median(pre), median(post)
}

func median(xs []float64) float64 {
	if len(xs) == 0 {
		return 0
	}
	cp := append([]float64(nil), xs...)
	sort.Float64s(cp)
	return cp[len(cp)/2]
}

func percentile(xs []float64, p float64) float64 {
	if len(xs) == 0 {
		return 0
	}
	cp := append([]float64(nil), xs...)
	sort.Float64s(cp)
	i := int(float64(len(cp)) * p)
	if i >= len(cp) {
		i = len(cp) - 1
	}
	return cp[i]
}

// ─── 文件工具 ────────────────────────────────────────────────────────────────

func corpusDir(root string, rd rulesDoc, name string) string {
	return filepath.Join(root, filepath.FromSlash(rd.CorpusRoot), name)
}

// corpusFiles 返回排序后的 .c 绝对路径 + 名字列表；目录不可读或为空即 fail loud。
func corpusFiles(dir string) ([]string, []string) {
	ents, err := os.ReadDir(dir)
	if err != nil {
		fatal("语料目录不可读: %s (%v)", dir, err)
	}
	var paths, names []string
	for _, e := range ents {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".c") {
			continue
		}
		paths = append(paths, filepath.Join(dir, e.Name()))
		names = append(names, e.Name())
	}
	sort.Strings(paths)
	sort.Strings(names)
	if len(paths) == 0 {
		fatal("0 个 .c 语料文件: %s（拒绝空转产假报告）", dir)
	}
	return paths, names
}

// freshDir 建一个空目录：先尽力删，删不掉就改名让位（safe-delete 钩子下同样成立）。
func freshDir(dir string) {
	if err := os.RemoveAll(dir); err != nil {
		if _, statErr := os.Stat(dir); statErr == nil {
			_ = os.Rename(dir, fmt.Sprintf("%s_old_%d", dir, time.Now().UnixNano()))
		}
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		fatal("建输出目录失败: %s (%v)", dir, err)
	}
}

func countFiles(dir string) int {
	n := 0
	_ = filepath.WalkDir(dir, func(_ string, d os.DirEntry, err error) error {
		if err == nil && !d.IsDir() {
			n++
		}
		return nil
	})
	return n
}

func exeOf(cmdRoot, tool string) string {
	return filepath.Join(cmdRoot, filepath.FromSlash(tool), tool+".exe")
}

func requireExe(p, hint string) {
	if _, err := os.Stat(p); err != nil {
		if hint != "" {
			fatal("缺产物: %s（%s）", p, hint)
		}
		fatal("缺产物: %s", p)
	}
}

// ─── launch ─────────────────────────────────────────────────────────────────

type launchRow struct {
	Name   string
	Min    float64
	Med    float64
	Max    float64
	Create float64
	Run    float64
}

type launchResult struct {
	Rows []launchRow
	Pre  float64
	Post float64
}

func runLaunch(root string, rd rulesDoc, self, outRoot string) (launchResult, error) {
	var res launchResult

	rust := filepath.Join(root, filepath.FromSlash(rd.RustCLI))
	if _, err := os.Stat(rust); err != nil {
		return res, fmt.Errorf("缺 Rust oracle: %s", rust)
	}

	// MoonBit 侧用最小语料走正常路径（缺参 fail 路径有 backtrace 假象）。
	paths, _ := corpusFiles(corpusDir(root, rd, rd.Compare.Corpus))
	small := paths[0]
	for _, p := range paths {
		fi, err := os.Stat(p)
		if err != nil {
			continue
		}
		if s, e := os.Stat(small); e != nil || fi.Size() < s.Size() {
			small = p
		}
	}
	moonExe := exeOf(filepath.Join(root, filepath.FromSlash(rd.MoonCmdRoot)), rd.Compare.MoonTool)
	if _, err := os.Stat(moonExe); err != nil {
		return res, fmt.Errorf("缺产物: %s（先 `cd moonbit && moon build --release --target native cmd/%s`）", moonExe, rd.Compare.MoonTool)
	}
	moonDir := filepath.Join(outRoot, "launch_moon")

	targets := []struct {
		name string
		exe  string
		args []string
	}{
		{"rust vitro_cli(usage)", rust, nil},
		{"moon " + rd.Compare.MoonTool + "(最小语料)", moonExe, []string{small, moonDir}},
	}
	for _, t := range targets {
		var ts []float64
		for i := 0; i < rd.LaunchReps; i++ {
			if t.args != nil {
				freshDir(moonDir)
			}
			d, _ := runTimed(t.exe, t.args, timeoutOf(rd))
			ts = append(ts, float64(d.Microseconds())/1000.0)
		}
		sorted := append([]float64(nil), ts...)
		sort.Float64s(sorted)
		res.Rows = append(res.Rows, launchRow{
			Name: t.name, Min: sorted[0], Med: median(ts), Max: sorted[len(sorted)-1],
		})
	}

	// 拆分段（取 min 以去掉尖峰）
	c, w := spawnSplit(rust, nil)
	for i := 1; i < rd.LaunchReps; i++ {
		c2, w2 := spawnSplit(rust, nil)
		if c2 < c {
			c = c2
		}
		if w2 < w {
			w = w2
		}
	}
	res.Rows[0].Create = float64(c.Microseconds()) / 1000.0
	res.Rows[0].Run = float64(w.Microseconds()) / 1000.0
	res.Pre, res.Post = stampSplit(self, rd.LaunchReps)
	return res, nil
}

// ─── pipeline ───────────────────────────────────────────────────────────────

type pipeRow struct {
	Tool     string
	Corpus   string
	RoundsMS []float64
	MedMS    float64
	MBPerSec float64
	Files    int
	MB       float64
}

func runPipeline(root string, rd rulesDoc, outRoot string) ([]pipeRow, error) {
	cmdRoot := filepath.Join(root, filepath.FromSlash(rd.MoonCmdRoot))
	var rows []pipeRow
	for _, tool := range rd.DumpTools {
		exe := exeOf(cmdRoot, tool.ID)
		if _, err := os.Stat(exe); err != nil {
			return nil, fmt.Errorf("缺产物: %s（先 `cd moonbit && moon build --release --target native cmd/%s`）", exe, tool.ID)
		}
		for _, corp := range rd.Corpora {
			dir := corpusDir(root, rd, corp)
			paths, _ := corpusFiles(dir)
			var bytes int64
			for _, p := range paths {
				if fi, err := os.Stat(p); err == nil {
					bytes += fi.Size()
				}
			}
			var ts []float64
			files := 0
			for r := 0; r < rd.Rounds; r++ {
				out := filepath.Join(outRoot, fmt.Sprintf("%s_%s_r%d", tool.ID, corp, r))
				freshDir(out)
				d, _ := runTimed(exe, append([]string{dir, out}, tool.ExtraArgs...), timeoutOf(rd))
				ts = append(ts, float64(d.Microseconds())/1000.0)
				files = countFiles(out)
			}
			mb := float64(bytes) / 1024.0 / 1024.0
			med := median(ts)
			row := pipeRow{Tool: tool.ID, Corpus: corp, RoundsMS: ts, MedMS: med, Files: files, MB: mb}
			if med > 0 {
				row.MBPerSec = mb / (med / 1000.0)
			}
			rows = append(rows, row)
		}
	}
	return rows, nil
}

// ─── compare ────────────────────────────────────────────────────────────────

type cmpResult struct {
	Corpus  string
	Names   []string
	MoonMS  []float64
	RustMS  []float64
	MoonTot float64
	RustTot float64
	MoonMed float64
	RustMed float64
	MoonP90 float64
	RustP90 float64
	MoonBad int
	RustBad int
	Tool    string
	Verb    string
}

// runCompare：逐文件交替测 MoonBit 与 Rust（同一循环内先后跑，抵消段内漂移）。
func runCompare(root string, rd rulesDoc, outRoot string) (cmpResult, error) {
	var res cmpResult
	res.Corpus = rd.Compare.Corpus
	res.Tool, res.Verb = rd.Compare.MoonTool, rd.Compare.RustVerb
	dir := corpusDir(root, rd, res.Corpus)
	paths, names := corpusFiles(dir)
	res.Names = names

	moonExe := exeOf(filepath.Join(root, filepath.FromSlash(rd.MoonCmdRoot)), rd.Compare.MoonTool)
	if _, err := os.Stat(moonExe); err != nil {
		return res, fmt.Errorf("缺产物: %s", moonExe)
	}
	rustExe := filepath.Join(root, filepath.FromSlash(rd.RustCLI))
	if _, err := os.Stat(rustExe); err != nil {
		return res, fmt.Errorf("缺 Rust oracle: %s", rustExe)
	}

	moonOut := filepath.Join(outRoot, "cmp_moon")
	rustOut := filepath.Join(outRoot, "cmp_rust.json")
	// 输出目录**每次运行清一次**（不逐文件清）——与实录 §12.4/§13 的既有口径一致，
	// 保证比值跨时可对比。逐文件重建目录会让本侧多付"新建文件"而非"覆写"的税（实测 ~7%）。
	freshDir(moonOut)
	for _, p := range paths {
		md, mrc := runTimed(moonExe, []string{p, moonOut}, timeoutOf(rd))
		rd2, rrc := runTimed(rustExe, []string{rd.Compare.RustVerb, p, "-o", rustOut}, timeoutOf(rd))
		res.MoonMS = append(res.MoonMS, float64(md.Microseconds())/1000.0)
		res.RustMS = append(res.RustMS, float64(rd2.Microseconds())/1000.0)
		if mrc != 0 {
			res.MoonBad++
		}
		if rrc != 0 {
			res.RustBad++
		}
	}
	res.MoonTot = sum(res.MoonMS)
	res.RustTot = sum(res.RustMS)
	res.MoonMed, res.RustMed = median(res.MoonMS), median(res.RustMS)
	res.MoonP90, res.RustP90 = percentile(res.MoonMS, 0.9), percentile(res.RustMS, 0.9)
	return res, nil
}

func sum(xs []float64) float64 {
	var s float64
	for _, x := range xs {
		s += x
	}
	return s
}

// ─── ab ─────────────────────────────────────────────────────────────────────

type abRow struct {
	Tool   string
	ARotMS []float64
	BRotMS []float64
	A      float64
	B      float64
}

func runAB(root string, rd rulesDoc, outRoot, bRoot string, roundsOverride int, corpusOverride string) ([]abRow, error) {
	if bRoot == "" {
		return nil, fmt.Errorf("-mode ab 需要 -b-root <对照版本树的 cmd 根目录>")
	}
	aRoot := filepath.Join(root, filepath.FromSlash(rd.MoonCmdRoot))
	corpus := rd.AB.Corpus
	if corpusOverride != "" {
		corpus = corpusOverride
	}
	if corpus == "" {
		corpus = rd.Compare.Corpus
	}
	rounds := rd.AB.Rounds
	if rounds <= 0 {
		rounds = rd.Rounds
	}
	if roundsOverride > 0 {
		rounds = roundsOverride
	}
	tools := rd.AB.Tools
	if len(tools) == 0 {
		for _, t := range rd.DumpTools {
			tools = append(tools, t.ID)
		}
	}
	dir := corpusDir(root, rd, corpus)
	corpusFiles(dir) // fail loud if 空
	extraOf := map[string][]string{}
	for _, t := range rd.DumpTools {
		extraOf[t.ID] = t.ExtraArgs
	}

	var rows []abRow
	for _, tool := range tools {
		ae, be := exeOf(aRoot, tool), exeOf(filepath.FromSlash(bRoot), tool)
		if _, err := os.Stat(ae); err != nil {
			return nil, fmt.Errorf("缺本地产物: %s", ae)
		}
		if _, err := os.Stat(be); err != nil {
			return nil, fmt.Errorf("-b-root 下缺产物: %s", be)
		}
		var ta, tb []float64
		for r := 0; r < rounds; r++ {
			oa := filepath.Join(outRoot, fmt.Sprintf("ab_A_%s_r%d", tool, r))
			ob := filepath.Join(outRoot, fmt.Sprintf("ab_B_%s_r%d", tool, r))
			freshDir(oa)
			da, _ := runTimed(ae, append([]string{dir, oa}, extraOf[tool]...), timeoutOf(rd))
			freshDir(ob)
			db, _ := runTimed(be, append([]string{dir, ob}, extraOf[tool]...), timeoutOf(rd))
			ta = append(ta, float64(da.Microseconds())/1000.0)
			tb = append(tb, float64(db.Microseconds())/1000.0)
		}
		rows = append(rows, abRow{Tool: tool, A: median(ta), B: median(tb), ARotMS: ta, BRotMS: tb})
	}
	return rows, nil
}

// ─── 新鲜度 ─────────────────────────────────────────────────────────────────

// staleness：dump 产物是否旧于 moonbit 源码（防测「陈旧/注入态 exe」——skill 04 A21）。
func staleness(root string, rd rulesDoc) (stale []string, newestSrc time.Time) {
	srcRoot := filepath.Join(root, filepath.FromSlash(rd.MoonSourceRoot))
	_ = filepath.WalkDir(srcRoot, func(p string, d os.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			switch d.Name() {
			case "_build", ".mooncakes", "target", ".git":
				return filepath.SkipDir
			}
			return nil
		}
		n := d.Name()
		if !strings.HasSuffix(n, ".mbt") && n != "moon.mod" && n != "moon.pkg" {
			return nil
		}
		if fi, err := d.Info(); err == nil && fi.ModTime().After(newestSrc) {
			newestSrc = fi.ModTime()
		}
		return nil
	})
	cmdRoot := filepath.Join(root, filepath.FromSlash(rd.MoonCmdRoot))
	for _, t := range rd.DumpTools {
		p := exeOf(cmdRoot, t.ID)
		if fi, err := os.Stat(p); err != nil {
			stale = append(stale, t.ID+"(缺失)")
		} else if fi.ModTime().Before(newestSrc) {
			stale = append(stale, t.ID)
		}
	}
	return stale, newestSrc
}

// ─── 报告 ───────────────────────────────────────────────────────────────────

type reportInput struct {
	Root      string
	RulesPath string
	Modes     []string
	Rounds    int
	Corpora   []string
	StartT    time.Time
	Launch    *launchResult
	Pipe      []pipeRow
	Compare   *cmpResult
	AB        []abRow
	ABRoot    string
	Stale     []string
	Newest    time.Time
	ModeErrs  []string
}

func buildReport(in reportInput) string {
	var b strings.Builder
	fmt.Fprintf(&b, "# Vitro 性能基线报告\n\n")
	fmt.Fprintf(&b, "> 仓库根：`%s`\n", in.Root)
	fmt.Fprintf(&b, "> 生成时刻：%s（采集耗时 %.1fs）\n", in.StartT.Format("2006-01-02 15:04:05"), time.Since(in.StartT).Seconds())
	fmt.Fprintf(&b, "> 生成者：`go run ./scripts/perf_baseline`（模式 %s）\n", strings.Join(in.Modes, "+"))
	fmt.Fprintf(&b, "> 规则：`%s`（轮数 %d，语料 %s）\n\n", in.RulesPath, in.Rounds, strings.Join(in.Corpora, "/"))
	fmt.Fprintf(&b, "**口径**：逐进程端到端（含进程创建与写盘）。本报告是**报告型**（无红绿判定）——\n")
	fmt.Fprintf(&b, "数字随机器/时段漂移，**判据优先看比值与跨次趋势**，勿把单次绝对值当契约。\n\n")

	fmt.Fprintf(&b, "## 0. 本次采集有效性\n\n")
	if in.Launch != nil && len(in.Launch.Rows) > 0 {
		floor := in.Launch.Rows[0].Med
		if floor > 20 {
			fmt.Fprintf(&b, "- 🔴 **启动开销偏高**（最小目标中位 %.1fms > 20ms）⇒ 疑似在 agent 会话内采集，\n", floor)
			fmt.Fprintf(&b, "  **逐进程绝对值不可引用**；请在 CI runner / 计划任务 / 普通窗口重采。\n")
		} else {
			fmt.Fprintf(&b, "- ✅ 启动开销正常（最小目标中位 %.1fms ≤ 20ms）⇒ 逐进程口径有效。\n", floor)
		}
	} else {
		fmt.Fprintf(&b, "- ⚠️ 未采 launch 定标，**无法判定逐进程口径是否有效**。\n")
	}
	if len(in.Stale) > 0 {
		fmt.Fprintf(&b, "- ⚠️ **产物新鲜度**：以下 dump 产物旧于 `%s/` 下最新源（%s）⇒ 可能测到陈旧/注入态 exe（skill 04 A21）：**%s**\n",
			"moonbit", in.Newest.Format("2006-01-02 15:04:05"), strings.Join(in.Stale, ", "))
	} else if !in.Newest.IsZero() {
		fmt.Fprintf(&b, "- ✅ 产物新鲜度：全部 dump 产物新于 `moonbit/` 最新源。\n")
	}
	for _, e := range in.ModeErrs {
		fmt.Fprintf(&b, "- ❌ %s\n", e)
	}
	fmt.Fprintf(&b, "\n")

	if in.Launch != nil && len(in.Launch.Rows) > 0 {
		fmt.Fprintf(&b, "## 1. 启动定标（ms）\n\n")
		fmt.Fprintf(&b, "| 目标 | min | 中位 | max |\n|---|---|---|---|\n")
		for _, r := range in.Launch.Rows {
			fmt.Fprintf(&b, "| %s | %.1f | %.1f | %.1f |\n", r.Name, r.Min, r.Med, r.Max)
		}
		if in.Launch.Rows[0].Create > 0 {
			fmt.Fprintf(&b, "\n- 拆分（rust oracle，取 min）：CreateProcess 本身 %.1fms / 运行+退出 %.1fms\n",
				in.Launch.Rows[0].Create, in.Launch.Rows[0].Run)
		}
		fmt.Fprintf(&b, "- 分段（自 spawn 时间戳探针）：**进 main 之前 %.1fms** / 退 main 之后 %.1fms\n", in.Launch.Pre, in.Launch.Post)
		fmt.Fprintf(&b, "\n> 参照：实录 §12.9 平面窗口 4.6-6.0ms；§12.1 会话内 ~148ms。\n\n")
	}

	if len(in.Pipe) > 0 {
		fmt.Fprintf(&b, "## 2. 四层管线吞吐（%d 轮，端到端含写盘）\n\n", in.Rounds)
		fmt.Fprintf(&b, "| 工具 | 语料 | min(s) | 中位(s) | 吞吐(MB/s) | 产物文件 | rounds |\n|---|---|---|---|---|---|---|\n")
		for _, r := range in.Pipe {
			rs := make([]string, 0, len(r.RoundsMS))
			minT := r.RoundsMS[0]
			for _, t := range r.RoundsMS {
				rs = append(rs, fmt.Sprintf("%.3f", t/1000.0))
				if t < minT {
					minT = t
				}
			}
			fmt.Fprintf(&b, "| %s | %s | %.3f | %.3f | %.2f | %d | [%s] |\n",
				r.Tool, r.Corpus, minT/1000.0, r.MedMS/1000.0, r.MBPerSec, r.Files, strings.Join(rs, ", "))
		}
		fmt.Fprintf(&b, "\n> **首轮冷启动**常 ~5x（实测），中位偶被尖峰抬高 ⇒ **min 是能力下界、中位是常态**，\n")
		fmt.Fprintf(&b, "> 两者并看；rounds 列保留原始值供判尖峰。轮数一律 ≥5。\n\n")
	}

	if in.Compare != nil && len(in.Compare.MoonMS) > 0 {
		c := in.Compare
		fmt.Fprintf(&b, "## 3. 逐文件对比：MoonBit %s vs Rust %s（语料 %s，n=%d）\n\n",
			c.Tool, c.Verb, c.Corpus, len(c.MoonMS))
		fmt.Fprintf(&b, "| 侧 | 总(s) | 中位(ms) | p90(ms) | 非 0 退出 |\n|---|---|---|---|---|\n")
		fmt.Fprintf(&b, "| MoonBit | %.3f | %.1f | %.1f | %d |\n", c.MoonTot/1000.0, c.MoonMed, c.MoonP90, c.MoonBad)
		fmt.Fprintf(&b, "| Rust oracle | %.3f | %.1f | %.1f | %d |\n", c.RustTot/1000.0, c.RustMed, c.RustP90, c.RustBad)
		if c.RustTot > 0 {
			fmt.Fprintf(&b, "\n- **比值 moon/rust（总耗时）= %.2f×**（对冻结 oracle 而言该比值**跨时可对比**，是回归主判据）\n", c.MoonTot/c.RustTot)
		}
		if c.RustMed > 0 {
			fmt.Fprintf(&b, "- 比值（中位）= %.2f×\n", c.MoonMed/c.RustMed)
		}
		fmt.Fprintf(&b, "\n> 参照：实录 §12.4 该比值 1.49×（2026-09-29）；§13 本轮 1.50-1.51×（2026-10-04）。\n\n")
	}

	if len(in.AB) > 0 {
		fmt.Fprintf(&b, "## 4. A/B：本地工作区(A) vs 对照树(B)\n\n")
		fmt.Fprintf(&b, "- A = `moonbit/_build/native/release/build/cmd`\n- B = `%s`\n\n", in.ABRoot)
		fmt.Fprintf(&b, "| 工具 | A 中位(s) | B 中位(s) | A/B |\n|---|---|---|---|\n")
		for _, r := range in.AB {
			ratio := 0.0
			if r.B > 0 {
				ratio = r.A / r.B
			}
			fmt.Fprintf(&b, "| %s | %.3f | %.3f | %.2f× |\n", r.Tool, r.A/1000.0, r.B/1000.0, ratio)
		}
		fmt.Fprintf(&b, "\n> 判读：<1 = A 更快。性能等价时应在 1.0 附近；**交替逐轮**采样已抵消漂移。\n\n")
	}

	fmt.Fprintf(&b, "## 附：复跑\n\n")
	fmt.Fprintf(&b, "```bash\n")
	fmt.Fprintf(&b, "# 必须在无 agent 注入层的环境（CI runner / 计划任务 / 普通窗口）\n")
	fmt.Fprintf(&b, "cd moonbit && moon build --release --target native \\\n  cmd/dump_tokens cmd/dump_ast cmd/dump_typeck cmd/dump_compile\n")
	fmt.Fprintf(&b, "cd .. && go run ./scripts/perf_baseline                       # 默认 all\n")
	fmt.Fprintf(&b, "go run ./scripts/perf_baseline -mode ab -b-root <对照 cmd 根>  # 版本 A/B\n")
	fmt.Fprintf(&b, "```\n")
	return b.String()
}

// ─── selftest（J9 证红） ─────────────────────────────────────────────────────

// selftestRun：用子进程断言 fail-loud 真的会红。两路注入：
//  1. moon_cmd_root 指向不存在目录 ⇒ pipeline 必非 0 退出；
//  2. corpus_root 指向空目录 ⇒ 必非 0 退出（拒绝空转产假报告）。
//
// 通过条件 = 两路都红；任一路不红即 selftest FAIL（说明存在假绿风险）。
func selftestRun(root string, rd rulesDoc) int {
	self, err := os.Executable()
	if err != nil {
		fmt.Printf("perf_baseline: selftest ABORT——取自身路径失败: %v\n", err)
		return 2
	}
	tmpDir := filepath.Join(root, "tmp", "perf_baseline", "__selftest")
	if err := os.RemoveAll(tmpDir); err != nil {
		fmt.Printf("perf_baseline: selftest ABORT——清理临时目录失败: %v\n", err)
		return 2
	}
	if err := os.MkdirAll(tmpDir, 0o755); err != nil {
		fmt.Printf("perf_baseline: selftest ABORT——建临时目录失败: %v\n", err)
		return 2
	}

	run := func(tag string, mutate func(*rulesDoc)) bool {
		inj := rd
		mutate(&inj)
		p := filepath.Join(tmpDir, tag+".json")
		body, mErr := json.MarshalIndent(inj, "", "  ")
		if mErr != nil {
			fmt.Printf("perf_baseline: selftest ABORT——序列化注入规则失败: %v\n", mErr)
			os.Exit(2)
		}
		if wErr := os.WriteFile(p, body, 0o644); wErr != nil {
			fmt.Printf("perf_baseline: selftest ABORT——写注入规则失败: %v\n", wErr)
			os.Exit(2)
		}
		rel, rErr := filepath.Rel(root, p)
		if rErr != nil {
			rel = p
		}
		cmd := exec.Command(self, "-rules", filepath.ToSlash(rel), "-mode", "pipeline")
		cmd.Dir = root
		out, _ := cmd.CombinedOutput()
		red := cmd.ProcessState != nil && cmd.ProcessState.ExitCode() != 0
		first := strings.TrimSpace(string(out))
		if i := strings.IndexByte(first, '\n'); i >= 0 {
			first = first[:i]
		}
		fmt.Printf("  [%s] 退出=%d %s | %s\n", tag, cmd.ProcessState.ExitCode(), map[bool]string{true: "🔴 红(预期)", false: "⚪ 绿(非预期)"}[red], first)
		return red
	}

	ok1 := run("bad_cmdroot", func(r *rulesDoc) {
		r.MoonCmdRoot = "tmp/perf_baseline/__no_such_dir__"
	})
	emptyCorpus := filepath.Join(tmpDir, "empty_corpus")
	_ = os.MkdirAll(filepath.Join(emptyCorpus, "baseline"), 0o755)
	ok2 := run("empty_corpus", func(r *rulesDoc) {
		r.CorpusRoot = filepath.ToSlash(filepath.Join("tmp", "perf_baseline", "__selftest", "empty_corpus"))
		r.Corpora = []string{"baseline"}
	})

	if ok1 && ok2 {
		fmt.Println("perf_baseline: selftest PASS——两路注入（缺产物 / 空语料）均被判红，fail-loud 成立")
		return 0
	}
	fmt.Println("perf_baseline: selftest FAIL——存在未判红的注入路（假绿风险）")
	return 1
}

// ─── main ───────────────────────────────────────────────────────────────────

func main() {
	self, _ := os.Executable()
	if len(os.Args) > 1 && os.Args[1] == "__stamp" {
		fmt.Printf("%d\n", time.Now().UnixNano())
		return
	}

	mode := flag.String("mode", "all", "all|launch|pipeline|compare|ab")
	rounds := flag.Int("rounds", 0, "覆盖轮数（0 = 用 rules.json）")
	corpus := flag.String("corpus", "", "只跑该语料（空 = 全部）")
	bRoot := flag.String("b-root", "", "A/B 对照版本树的 cmd 根目录")
	rulesRel := flag.String("rules", defaultRulesPath, "规则文件（仓库根相对路径）")
	reportOverride := flag.String("report", "", "报告输出路径覆盖")
	selftest := flag.Bool("selftest", false, "J9 证红：断言 fail-loud 路径真的会红")
	flag.Parse()

	root := capi.ProjectRoot()
	rd := loadRules(root, *rulesRel)
	if *rounds > 0 {
		rd.Rounds = *rounds
	}
	if *corpus != "" {
		rd.Corpora = []string{*corpus}
	}

	if *selftest {
		os.Exit(selftestRun(root, rd))
	}

	outRoot := filepath.Join(root, filepath.FromSlash(rd.OutRoot), time.Now().Format("20060102_150405"))
	if err := os.MkdirAll(outRoot, 0o755); err != nil {
		fatal("建输出根失败: %v", err)
	}

	in := reportInput{
		Root: root, RulesPath: *rulesRel, Rounds: rd.Rounds, Corpora: rd.Corpora,
		StartT: time.Now(), ABRoot: *bRoot,
	}

	switch *mode {
	case "ab":
		in.Modes = []string{"ab"}
		rows, err := runAB(root, rd, outRoot, *bRoot, *rounds, *corpus)
		if err != nil {
			fatal("%v", err)
		}
		in.AB = rows
	case "launch", "pipeline", "compare", "all":
		if *mode == "all" || *mode == "launch" {
			in.Modes = append(in.Modes, "launch")
			lr, err := runLaunch(root, rd, self, outRoot)
			if err != nil {
				fatal("%v", err)
			}
			in.Launch = &lr
		}
		if *mode == "all" || *mode == "pipeline" {
			in.Modes = append(in.Modes, "pipeline")
			rows, err := runPipeline(root, rd, outRoot)
			if err != nil {
				fatal("%v", err)
			}
			in.Pipe = rows
		}
		if *mode == "all" || *mode == "compare" {
			in.Modes = append(in.Modes, "compare")
			cr, err := runCompare(root, rd, outRoot)
			if err != nil {
				fatal("%v", err)
			}
			in.Compare = &cr
		}
	default:
		fatal("未知 -mode %q（可选 all|launch|pipeline|compare|ab）", *mode)
	}

	in.Stale, in.Newest = staleness(root, rd)

	reportPath := filepath.Join(root, filepath.FromSlash(rd.ReportPath))
	if *reportOverride != "" {
		reportPath = *reportOverride
	}
	if err := os.MkdirAll(filepath.Dir(reportPath), 0o755); err != nil {
		fatal("建报告目录失败: %v", err)
	}
	if err := os.WriteFile(reportPath, []byte(buildReport(in)), 0o644); err != nil {
		fatal("写报告失败: %v", err)
	}
	fmt.Printf("perf_baseline: 报告已写 %s（模式 %s）\n", reportPath, strings.Join(in.Modes, "+"))
	fmt.Printf("perf_baseline: 采集产物 %s（可删）\n", outRoot)
}
