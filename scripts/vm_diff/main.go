// vm_diff：D 级三联 diff 驱动（批五号——总计划 §6 D 级锚：stdout + 返回码
// + 1MB 最终内存映像）。
//
// 两侧：
//
//	Rust oracle：native/target/release/vitro_cli.exe run <file.c>
//	MoonBit：    moonbit/_build/native/release/build/cmd/run/run.exe（**预编译
//	            直跑**——moon run 包装层在 Go exec 下 0xffffffff 崩溃，
//	            实测 bash/python 正常、Go 不稳；故 vm_diff 前置要求先
//	            `moon build --target native cmd/run`）
//
// 三通道：
//  1. stdout：双侧归一（滤 oracle 前后缀噪音行 + 恰一个尾换行）后逐字节
//  2. 返回码：oracle process exit code vs MoonBit `// EXIT N` 标记
//  3. 1MB 映像：MoonBit 侧 --dump-memory（oracle 侧待 Rust 出口——本版
//     先验「自包含性」：文件恰 1MB）
//
// 用法：go run ./scripts/vm_diff [--corpus dir] [--cases f1.c,f2.c,...]
//
//	（默认 corpus = native/tests/cases/baseline，均匀抽 30 例）
package main

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

const runnerExe = "moonbit/_build/native/release/build/cmd/run/run.exe"

type result struct {
	stdout      string
	exitCode    int
	memoryPath  string
	compileFail bool
}

func main() {
	corpus := filepath.Join("native", "tests", "cases", "baseline")
	var explicit []string
	for i := 1; i < len(os.Args); i++ {
		arg := os.Args[i]
		if arg == "--corpus" && i+1 < len(os.Args) {
			i++
			corpus = os.Args[i]
		} else if arg == "--cases" && i+1 < len(os.Args) {
			i++
			explicit = strings.Split(os.Args[i], ",")
		}
	}
	if !fileExists(runnerExe) {
		fmt.Fprintf(os.Stderr, "vm_diff: %s 不存在——先跑 moon build --target native cmd/run\n", runnerExe)
		os.Exit(1)
	}

	var files []string
	if len(explicit) > 0 {
		files = explicit
	} else {
		files = pick30(corpus)
	}
	if len(files) == 0 {
		fmt.Fprintln(os.Stderr, "vm_diff: 无用例")
		os.Exit(1)
	}

	same, diff := 0, 0
	for _, f := range files {
		path := f
		hasSep := strings.ContainsAny(f, `/\`)
		if !filepath.IsAbs(f) && !hasSep {
			path = filepath.Join(corpus, f)
		}
		if !fileExists(path) {
			fmt.Printf("SKIP  %s（不存在）\n", f)
			continue
		}
		if strings.Contains(f, "e2_") {
			fmt.Printf("SKIP  %s（e2 include 搜索面——cmd/run 无本地 .h 注入，非 VM 面）\n", f)
			continue
		}
		o := runOracle(path)
		m := runMoonBit(path)
		if o.compileFail && m.compileFail {
			fmt.Printf("SAME  %s（双侧编译失败——等价）\n", f)
			same++
			continue
		}
		issues := compare(f, o, m)
		if len(issues) == 0 {
			fmt.Printf("SAME  %s\n", f)
			same++
		} else {
			fmt.Printf("DIFF  %s：%s\n", f, strings.Join(issues, "；"))
			diff++
		}
	}
	fmt.Printf("\nvm_diff: SAME=%d DIFF=%d（共 %d）\n", same, diff, same+diff)
	if diff > 0 {
		os.Exit(1)
	}
}

// pick30：从语料均匀抽 30 例（覆盖整个字母序范围）。
func pick30(corpus string) []string {
	entries, err := os.ReadDir(corpus)
	if err != nil {
		return nil
	}
	var all []string
	for _, e := range entries {
		if strings.HasSuffix(e.Name(), ".c") {
			all = append(all, e.Name())
		}
	}
	sort.Strings(all)
	if len(all) <= 30 {
		return all
	}
	out := make([]string, 0, 30)
	step := float64(len(all)) / 30
	for i := 0; i < 30; i++ {
		idx := int(float64(i) * step)
		if idx >= len(all) {
			idx = len(all) - 1
		}
		out = append(out, all[idx])
	}
	return out
}

func fileExists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}

func runOracle(path string) *result {
	bin := filepath.Join("native", "target", "release", "vitro_cli.exe")
	if !fileExists(bin) {
		return &result{compileFail: true, stdout: "// ORACLE-MISSING"}
	}
	var out bytes.Buffer
	cmd := exec.Command(bin, "run", path)
	cmd.Stdout = &out
	cmd.Stderr = &out
	err := cmd.Run()
	code := 0
	if exitErr, ok := err.(*exec.ExitError); ok {
		code = exitErr.ExitCode()
	}
	r := &result{stdout: out.String(), exitCode: code}
	if strings.Contains(r.stdout, "=== 诊断信息 ===") {
		r.compileFail = true
	}
	// oracle 的返回码在「程序运行完成，返回值：N」行（进程 exit 恒 0）
	for _, line := range strings.Split(r.stdout, "\n") {
		if strings.HasPrefix(line, "程序运行完成，返回值：") {
			fmt.Sscanf(line, "程序运行完成，返回值：%d", &r.exitCode)
		}
	}
	return r
}

func runMoonBit(path string) *result {
	tmp, err := os.CreateTemp("", "vmem_*.bin")
	if err != nil {
		return &result{stdout: "// TMPFAIL"}
	}
	tmp.Close()
	defer os.Remove(tmp.Name())

	var out bytes.Buffer
	cmd := exec.Command(filepath.FromSlash(runnerExe), path, "--dump-memory", tmp.Name())
	cmd.Stdout = &out
	cmd.Stderr = &out
	_ = cmd.Run()
	r := &result{stdout: out.String(), memoryPath: tmp.Name()}
	if strings.Contains(r.stdout, "// COMPILE-ERROR") {
		r.compileFail = true
	}
	for _, line := range strings.Split(strings.TrimSpace(r.stdout), "\n") {
		if strings.HasPrefix(line, "// EXIT ") {
			fmt.Sscanf(line, "// EXIT %d", &r.exitCode)
		}
	}
	return r
}

// compare：三通道比对。
func compare(name string, o, m *result) []string {
	var issues []string
	os_ := normalizeStdout(o.stdout)
	ms := normalizeStdout(m.stdout)
	if os_ != ms {
		issues = append(issues, summarizeStdout(os_, ms))
	}
	if o.exitCode != m.exitCode {
		issues = append(issues, fmt.Sprintf("返回码 %d != %d", o.exitCode, m.exitCode))
	}
	if m.memoryPath != "" {
		if data, err := os.ReadFile(m.memoryPath); err == nil {
			if len(data) != 1024*1024 {
				issues = append(issues, fmt.Sprintf("映像非 1MB（%d）", len(data)))
			}
		}
	}
	return issues
}

// normalizeStdout：滤噪音行 + 恰一个尾换行。
func normalizeStdout(s string) string {
	var lines []string
	for _, l := range strings.Split(s, "\n") {
		t := strings.TrimRight(l, "\r")
		if strings.HasPrefix(t, "// ") || strings.HasPrefix(t, "=== ") ||
			strings.HasPrefix(t, "编译失败") || strings.HasPrefix(t, "编译成功") ||
			strings.HasPrefix(t, "[提示]") || strings.HasPrefix(t, "[警告]") ||
			strings.HasPrefix(t, "    建议:") || strings.HasPrefix(t, "检测到算法") ||
			strings.HasPrefix(t, "  ") ||
			strings.HasPrefix(t, "    警告") || strings.HasPrefix(t, "  - ") ||
			strings.HasPrefix(t, "Warning") || strings.HasPrefix(t, "Error") ||
			strings.HasPrefix(t, "Finished.") {
			continue
		}
		// oracle 尾注可能紧贴程序输出（无换行分隔）——行内剥离
		if idx := strings.Index(t, "程序运行完成，返回值："); idx >= 0 {
			t = t[:idx]
		}
		lines = append(lines, t)
	}
	for len(lines) > 0 && lines[len(lines)-1] == "" {
		lines = lines[:len(lines)-1]
	}
	for len(lines) > 0 && lines[0] == "" {
		lines = lines[1:]
	}
	return strings.Join(lines, "\n")
}

// summarizeStdout：stdout 差异摘要（首个差异行 + 两侧长度）。
func summarizeStdout(o, m string) string {
	ol := strings.Split(o, "\n")
	ml := strings.Split(m, "\n")
	for i := 0; i < len(ol) && i < len(ml); i++ {
		if ol[i] != ml[i] {
			return fmt.Sprintf("stdout 第 %d 行不一致（oracle %q vs moonbit %q；总 %d/%d 字节）", i+1, clip(ol[i]), clip(ml[i]), len(o), len(m))
		}
	}
	if len(ol) != len(ml) {
		return fmt.Sprintf("stdout 行数不一致（oracle %d vs moonbit %d；总 %d/%d 字节）", len(ol), len(ml), len(o), len(m))
	}
	return fmt.Sprintf("stdout 不一致（%d/%d 字节）", len(o), len(m))
}

func clip(s string) string {
	if len(s) > 40 {
		return s[:40] + "…"
	}
	return s
}
