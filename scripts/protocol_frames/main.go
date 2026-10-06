//go:build windows

// protocol_frames —— serve 协议帧字段级冻结测试（总计划 §3-B 结构化差分：
// 「serve 补字段级冻结测试（protocol_frames.jsonl 双宿主对拍）」——S7 批
// 四号交付物第三件，2026-10-04 兑现）。
//
// 形态：固定请求序列发往双宿主（Rust vitro_cli serve = oracle 臂；
// MoonBit cmd/serve = 迁移臂），每帧响应经 canonicalize（键排序归一——
// 已知限制条目 9 定案口径：Rust serde BTreeMap 字典序 vs MoonBit 插入序，
// 比较一律经 canonicalize）→ compact 单行 → 文本级 mask（已知永久分叉的
// 字段值替换，规则外置 rules.json）→ 与入库基线 baseline.jsonl 逐帧比对。
//
// 三重义务：
//   - 双宿主互比（--diff-hosts）：两侧帧逐字节一致（分叉即红）；
//   - 基线冻结（默认 --check）：两臂各自与基线比对——防两侧一起漂
//     （白名单只管键集，这里管到值——「字段级冻结」的增量面）；
//   - 退役形态预置：Rust 删除后 MoonBit 臂单跑仍与基线比（oracle 臂的
//     最后一次消费即 --update-baseline 那次，随 0.8.0 工序②终验走）。
//
// **覆盖面边界（审阅 P3-⑤ 登记，2026-10-04）**：非 ASCII 程序输出的
// delta 值域**不在本闸覆盖内**——MoonBit delta 为 Latin-1 逐字节折回
// （serve_io 头注在案的既有分叉、消费方字节域还原），ASCII delta 与泄漏
// 报告全文（帧组 30-32）正常冻结；非 ASCII delta 帧纳入待该分叉收敛后
// 启用（skip 为方法粒度，帧级拆分不为此预建）。
//
// 用法：
//
//	go run ./scripts/protocol_frames                  # 双臂 vs 基线（CI 形态）
//	go run ./scripts/protocol_frames --diff-hosts     # 双宿主互比（无基线依赖）
//	go run ./scripts/protocol_frames --update-baseline # 以 oracle 臂刷新基线（人工令）
//	go run ./scripts/protocol_frames --audit-skips    # skip 僵尸审计（不跳真跑）
//	go run ./scripts/protocol_frames --selftest       # J9 三锚（mask/非法 JSON/比对红）
package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"time"

	"vitro/scripts/internal/canonicalize"
)

// ---------------------------------------------------------------- 路径与请求表

var (
	rustCli     string
	mbServe     string
	backendWasm bool // #49 批三：--backend-wasm
	rulesPath   = filepath.Join("scripts", "protocol_frames", "rules.json")
	basePath    = filepath.Join("scripts", "protocol_frames", "baseline.jsonl")
)

func init() {
	root := projectRoot()
	rustCli = filepath.Join(root, "native", "target", "release", "vitro_cli.exe")
	name := "serve"
	if runtime.GOOS == "windows" {
		name = "serve.exe"
	}
	mbServe = filepath.Join(root, "moonbit", "_build", "native", "debug", "build", "cmd", "serve", name)
}

func projectRoot() string {
	if v := os.Getenv("VITRO_ROOT"); v != "" {
		return v
	}
	dir, err := os.Getwd()
	if err != nil {
		fmt.Fprintf(os.Stderr, "错误: 无法取 cwd: %v\n", err)
		os.Exit(2)
	}
	for {
		if _, err := os.Stat(filepath.Join(dir, "go.mod")); err == nil {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			fmt.Fprintln(os.Stderr, "错误: 未找到项目根（go.mod）——从仓库根运行或设 VITRO_ROOT")
			os.Exit(2)
		}
		dir = parent
	}
}

// req 固定请求序列——覆盖 serve 帧面方法族（帧结构冻结目标）。序列变更
// = 行为变更，显式改代码走评审，不入外置资产。
type req struct {
	id     int
	method string
	params string // JSON 文本（nil 参数留空）
}

func requestTable() []req {
	return []req{
		// compile：成功形态 + 错误诊断形态 + 非 ASCII（§94 点名覆盖 0 → 中文注释/串）
		{1, "compile", `{"source":"int main() { int a = 1; a = a + 1; return a; }"}`},
		{2, "compile", `{"source":"int main() { int x = ; }"}`},
		{3, "compile", `{"source":"#include <stdio.h>\nint main() { printf(\"你好 vitr\\u006f\"); printf(\"\\\\x41\\\\x42\"); return 0; }"}`},
		// run：deterministic（时钟恒 0——两侧一致，免 time mask）+ trap 形态
		{4, "run", `{"deterministic":true}`},
		{5, "compile", `{"source":"int main() { int a = 0; int b = 1 / a; return b; }"}`},
		{6, "run", `{"deterministic":true}`},
		// IO 族
		{7, "output.delta", `{"cursor":0}`},
		// 静态三件 + capabilities（engine_version/abi 走 mask——永久形态差）
		{8, "capabilities", ``},
		{9, "error_catalog", ``},
		{10, "semantic_labels", ``},
		{11, "contracts", ``},
		// config 读写
		{12, "config.get", ``},
		{13, "config.set", `{"max_steps":5000}`},
		{14, "config.get", ``},
		// step 族全链（先编译回正常程序）
		{15, "compile", `{"source":"int fib(int n) { if (n < 2) return n; return fib(n-1) + fib(n-2); }\nint main() { return fib(4); }"}`},
		{16, "step.begin", ``},
		{17, "step.next", ``},
		{18, "step.next", ``},
		{19, "payload.get", `{"step":0}`},
		{20, "seek", `{"step":3}`},
		{21, "breakpoints.set", `{"lines":[2]}`},
		{22, "step.next", ``},
		// dump 族（只读通道）
		{23, "ast.dump", `{"source":"int main() { return 42; }"}`},
		// memory.regions（帧结构冻结——值确定性由引擎布局保证）
		{24, "memory.regions", ``},
		// 错误帧：未知方法 + 缺参
		{25, "no.such.method", ``},
		{26, "compile", ``},
		// reset 链
		{27, "session.reset", ``},
		{28, "compile", `{"source":"int main() { return 7; }"}`},
		{29, "run", `{"deterministic":true}`},
		// leak 报告帧组（审阅 P1③ 补——首版序列 run 帧无 malloc，泄漏报告
		// 从不产生 = hex 位宽分叉的闸盲区）：双 malloc 不 free → run → delta
		// 全文（报告文本含 addr 形态——oracle {:04X} 最少 4 位——进冻结）。
		{30, "compile", `{"source":"#include <stdlib.h>\n#include <stdio.h>\nint main() { printf(\"leak test\"); int* a = malloc(4); int* b = malloc(8); return 0; }"}`},
		{31, "run", `{"deterministic":true}`},
		{32, "output.delta", `{"cursor":0}`},
	}
}

// ---------------------------------------------------------------- mask 规则

type rules struct {
	SkipMethods map[string]string `json:"skip_methods"`
	Masks       []struct {
		Name    string `json:"name"`
		Pattern string `json:"pattern"`
		Replace string `json:"replace"`
		Reason  string `json:"reason"`
	} `json:"masks"`
}

var (
	compiled []struct {
		re      *regexp.Regexp
		replace string
		name    string
	}
	skipMethods map[string]string
)

func loadRules() {
	raw, err := os.ReadFile(rulesPath)
	if err != nil {
		fatal("读 mask 规则失败（%s）: %v", rulesPath, err)
	}
	var r rules
	if err := json.Unmarshal(raw, &r); err != nil {
		fatal("mask 规则非法 JSON: %v", err)
	}
	if len(r.SkipMethods) == 0 && len(r.Masks) == 0 {
		fatal("规则为空集（空集不得绿——已知分叉面须显式登记）")
	}
	skipMethods = r.SkipMethods
	for _, m := range r.Masks {
		re, err := regexp.Compile(m.Pattern)
		if err != nil {
			fatal("mask 规则 %s 正则非法: %v", m.Name, err)
		}
		compiled = append(compiled, struct {
			re      *regexp.Regexp
			replace string
			name    string
		}{re, m.Replace, m.Name})
	}
}

// ---------------------------------------------------------------- serve 会话

type host struct {
	name string
	cmd  *exec.Cmd
	in   io.WriteCloser
	out  *bufio.Scanner
}

func startHost(name, exe string) *host {
	var cmd *exec.Cmd
	if name == "moonbit" && backendWasm {
		// #49 批三：wasm 臂 = node 壳 serve（moonbit 产物位；协议同构）
		cmd = exec.Command("node", exe, "serve")
	} else if name == "moonbit" {
		cmd = exec.Command(exe) // cmd/serve 无子命令形态
	} else {
		cmd = exec.Command(exe, "serve")
	}
	stdin, err := cmd.StdinPipe()
	if err != nil {
		fatal("%s stdin pipe: %v", name, err)
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		fatal("%s stdout pipe: %v", name, err)
	}
	cmd.Stderr = io.Discard
	if err := cmd.Start(); err != nil {
		fatal("启动 %s 失败（%s）: %v", name, exe, err)
	}
	return &host{name: name, cmd: cmd, in: stdin, out: bufio.NewScanner(stdout)}
}

func (h *host) request(r req) string {
	var line []byte
	if r.params == "" {
		line = []byte(fmt.Sprintf(`{"id":%d,"method":"%s"}`, r.id, r.method))
	} else {
		line = []byte(fmt.Sprintf(`{"id":%d,"method":"%s","params":%s}`, r.id, r.method, r.params))
	}
	if _, err := h.in.Write(append(line, '\n')); err != nil {
		fatal("%s 写 stdin 失败（进程退出？）: %v", h.name, err)
	}
	if !h.out.Scan() {
		fatal("%s 响应流中断（id=%d %s）", h.name, r.id, r.method)
	}
	return h.out.Text()
}

func (h *host) stop() {
	h.in.Close()
	done := make(chan error, 1)
	go func() { done <- h.cmd.Wait() }()
	select {
	case <-done:
	case <-time.After(10 * time.Second):
		_ = h.cmd.Process.Kill()
	}
}

// frameLine 帧处理管线：raw → canonicalize（键排序/转义归一）→ compact
// 单行 → mask（文本级替换——规则外置）。
func frameLine(raw string) (string, error) {
	canon, err := canonicalize.Bytes([]byte(raw))
	if err != nil {
		return "", fmt.Errorf("canonicalize: %w", err)
	}
	var buf bytes.Buffer
	if err := json.Compact(&buf, canon); err != nil {
		return "", fmt.Errorf("compact: %w", err)
	}
	s := buf.String()
	for _, m := range compiled {
		s = m.re.ReplaceAllString(s, m.replace)
	}
	return s, nil
}

// ---------------------------------------------------------------- 主流程

func fatal(f string, a ...any) {
	fmt.Fprintf(os.Stderr, "错误: "+f+"\n", a...)
	os.Exit(2)
}

func main() {
	diffHosts := flag.Bool("diff-hosts", false, "双宿主互比（两侧帧逐字节一致；不依赖基线）")
	backendWasmFlag := flag.Bool("backend-wasm", false, "#49 批三：moonbit 臂被测物换统一入口壳 serve（node 消费 gateway wasm.wasm）——基线/断言零改动")
	update := flag.Bool("update-baseline", false, "以 oracle（Rust）臂刷新入库基线（人工令——随 0.8.0 工序②终验走最后一次）")
	auditSkips := flag.Bool("audit-skips", false, "skip 僵尸审计（审阅 P3-④ 补）：临时不 skip 真跑一轮——原 skip 帧两侧一致即僵尸红（键集分叉已收敛应删条目），DIFF=合法 skip")
	selftest := flag.Bool("selftest", false, "J9：mask 生效 + 非法 JSON 拒绝 + 基线比对红三锚")
	flag.Parse()
	if *backendWasmFlag {
		backendWasm = true
		shell := filepath.Join(projectRoot(), "scripts", "vitro_cli", "main.js")
		wasmMod := filepath.Join(projectRoot(), "moonbit", "_build", "wasm-gc", "release", "build", "gateway", "wasm", "wasm.wasm")
		for _, f := range []string{shell, wasmMod} {
			if _, err := os.Stat(f); err != nil {
				fatal("wasm 臂产物缺失 %s（先构建：moon build --release --target wasm-gc gateway/wasm）", f)
			}
		}
		if _, err := exec.LookPath("node"); err != nil {
			fatal("wasm 臂需要 node（统一入口壳宿主）")
		}
		mbServe = shell
	}

	loadRules()

	if *selftest {
		selfTest()
		return
	}

	// audit-skips 强制互比模式（审阅 P3-④ 语义修正）：基线生成时 skip 帧
	// 已被剔除——僵尸审计必须走双宿主互比才能暴露 skip 帧的两侧实态。
	if *auditSkips {
		*diffHosts = true
	}

	table := requestTable()
	// 整帧豁免（键集结构性分叉——skip_methods）双臂同跳，打印留痕。
	// --audit-skips 时不跳（僵尸审计：skip 帧两侧一致 = 键集分叉已收敛
	// 应删条目——skip 面每轮可被人工审计，与 replay 的 ZOMBIE 内联同义）。
	effective := table[:0]
	for _, r := range table {
		if reason, hit := skipMethods[r.method]; hit && !*auditSkips {
			fmt.Printf("[SKIP] %s（%s）\n", r.method, reason)
			continue
		}
		effective = append(effective, r)
	}
	table = effective

	// rust 臂（退役形态预置兑现，2026-10-05 删区批）：rustCli 不存在 =
	// oracle 已删区退役 → MoonBit 单臂基线比；--diff-hosts（含 --audit-skips
	// 强制互比）与 --update-baseline 依赖双臂/rust 侧真值，明示 fatal。
	useRust := true
	if _, err := os.Stat(rustCli); err != nil {
		useRust = false
		fmt.Fprintln(os.Stderr, "[retired] rust 臂不可用（oracle 已删区退役）——MoonBit 单臂基线比")
	}
	var rustFrames []string
	if useRust {
		rust := startHost("rust", rustCli)
		for _, r := range table {
			line, err := frameLine(rust.request(r))
			if err != nil {
				fatal("rust 臂帧处理失败（id=%d %s）: %v", r.id, r.method, err)
			}
			rustFrames = append(rustFrames, line)
		}
		rust.stop()
	}

	if *update {
		if !useRust {
			fatal("--update-baseline 需 rust 侧真值；oracle 已删区退役、基线已冻结——如需重建基线须人工裁定以哪臂为准")
		}
		if err := writeBaseline(rustFrames); err != nil {
			fatal("写基线失败: %v", err)
		}
		fmt.Printf("基线已刷新（%d 帧）→ %s\n", len(rustFrames), basePath)
		return
	}

	mb := startHost("moonbit", mbServe)
	var mbFrames []string
	for _, r := range table {
		line, err := frameLine(mb.request(r))
		if err != nil {
			fatal("moonbit 臂帧处理失败（id=%d %s）: %v", r.id, r.method, err)
		}
		mbFrames = append(mbFrames, line)
	}
	mb.stop()

	exit := 0

	if *diffHosts {
		if !useRust {
			fatal("--diff-hosts（含 --audit-skips 强制互比）需双宿主；rust 臂已随删区退役——skip 帧审计改走 MoonBit 单臂基线比 + skip_methods 清单人工复核")
		}
		if len(rustFrames) != len(mbFrames) {
			fatal("两臂帧数不等：rust=%d moonbit=%d", len(rustFrames), len(mbFrames))
		}
		for i, rf := range rustFrames {
			if rf != mbFrames[i] {
				exit = 1
				fmt.Printf("[DIFF] 帧 %d（%s）\n  rust:   %s\n  moonbit: %s\n", table[i].id, table[i].method, rf, mbFrames[i])
			}
		}
		if exit == 0 {
			fmt.Printf("双宿主互比：%d 帧全部一致\n", len(rustFrames))
		}
		os.Exit(exit)
	}

	// 默认：基线冻结比对（moonbit 臂必在；rust 臂按退役形态可选）
	base, err := readBaseline()
	if err != nil {
		fatal("读基线失败: %v", err)
	}
	if len(base) != len(mbFrames) {
		fatal("基线帧数 %d ≠ 序列帧数 %d——序列已变更，须 --update-baseline 重建（人工评审令）", len(base), len(mbFrames))
	}
	arms := []struct {
		name   string
		frames []string
	}{{"moonbit", mbFrames}}
	if useRust {
		arms = append([]struct {
			name   string
			frames []string
		}{{"rust", rustFrames}}, arms...)
	}
	for _, arm := range arms {
		if drifts := diffAgainstBase(arm.name, base, arm.frames, table); len(drifts) > 0 {
			exit = 1
			for _, d := range drifts {
				fmt.Println(d)
			}
		}
	}
	if exit == 0 {
		fmt.Printf("基线冻结比对：%d 臂 × %d 帧全部一致\n", len(arms), len(mbFrames))
	}
	os.Exit(exit)
}

// diffAgainstBase 单臂帧 vs 基线逐帧比（selftest 可注入的判定单点——
// 审阅 P2：比对逻辑必须被 --selftest 验过，不能只验 mask）。
func diffAgainstBase(arm string, base, actual []string, table []req) []string {
	if len(base) != len(actual) {
		return []string{fmt.Sprintf("[DRIFT] %s 帧数不等：基线 %d ≠ 实际 %d", arm, len(base), len(actual))}
	}
	var out []string
	for i, f := range actual {
		if f != base[i] {
			out = append(out, fmt.Sprintf("[DRIFT] %s 帧 %d（%s）\n  基线: %s\n  实际: %s", arm, table[i].id, table[i].method, base[i], f))
		}
	}
	return out
}

func writeBaseline(frames []string) error {
	var b strings.Builder
	for _, f := range frames {
		b.WriteString(f)
		b.WriteByte('\n')
	}
	return os.WriteFile(basePath, []byte(b.String()), 0o644)
}

func readBaseline() ([]string, error) {
	raw, err := os.ReadFile(basePath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, fmt.Errorf("基线不存在（%s）——先 --update-baseline 生成并入库", basePath)
		}
		return nil, err
	}
	var lines []string
	for _, l := range strings.Split(strings.TrimRight(string(raw), "\n"), "\n") {
		if l != "" {
			lines = append(lines, l)
		}
	}
	return lines, nil
}

// selfTest J9 埋雷（审阅 P2 补全——头注承诺「篡改/删基线必红」必须被验）：
// ① mask 必须真吃掉内容（防规则悄悄失配假绿）；② 帧管线对非法 JSON
// fail loud 透传；③ 基线比对判定注入不等帧必须产出 DRIFT（比对逻辑
// 自证——不能只验 mask 不验比对）。
func selfTest() {
	raw := `{"result":{"engine_version":"0.1.0 (abc1234)","note":"x"},"id":1}`
	line, err := frameLine(raw)
	if err != nil {
		fmt.Println("selftest: FAIL——合法帧处理失败:", err)
		os.Exit(2)
	}
	if strings.Contains(line, "abc1234") {
		fmt.Println("selftest: FAIL——engine_version mask 未生效（假绿面）")
		fmt.Println("  管线输出:", line)
		os.Exit(2)
	}
	if _, err := frameLine(`{"broken":`); err == nil {
		fmt.Println("selftest: FAIL——非法 JSON 未被拒绝（fail loud 透传断裂）")
		os.Exit(2)
	}
	// ③ 比对判定：篡改一帧（模拟基线漂移）必须产出 DRIFT
	tbl := requestTable()[:3]
	base := []string{`{"a":1}`, `{"b":2}`, `{"c":3}`}
	tampered := []string{`{"a":1}`, `{"b":99}`, `{"c":3}`}
	drifts := diffAgainstBase("selftest", base, tampered, tbl)
	if len(drifts) != 1 || !strings.Contains(drifts[0], "[DRIFT]") {
		fmt.Println("selftest: FAIL——基线比对判定对篡改帧不红（比对逻辑未被验证）")
		fmt.Println("  产出:", drifts)
		os.Exit(2)
	}
	if d := diffAgainstBase("selftest", base, base, tbl); len(d) != 0 {
		fmt.Println("selftest: FAIL——一致帧产出伪 DRIFT", d)
		os.Exit(2)
	}
	fmt.Println("selftest：mask 生效锚 + 非法 JSON 拒绝锚 + 基线比对红锚 通过")
}
