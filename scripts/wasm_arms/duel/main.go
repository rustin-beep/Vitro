// duel——wasmoon × wasmtime 双 wasm 宿主对拍驱动（#199 独立版，2026-10-20）。
//
// 独立脚本，不接入 corpus_fuzz 体系； verdict 口径与 corpus_fuzz 对齐：
//
//	AGREE           两引擎逐帧 JSON 语义一致（含错误帧）
//	HOST_DIVERGENCE 同一请求两引擎结果不同（宿主 bug，最高优先）
//	WASMOON_CRASH   wasmoon 臂 crash/超时（wasmtime 正常）
//	WASMTIME_CRASH  wasmtime 臂 crash/超时（wasmoon 正常）
//	BOTH_CRASH      双臂都失败
//
// 请求序列来自命令行或 -cases JSON 文件（每行一个 NDJSON 请求，按序发给
// 同一实例——会话状态跨请求保持，与 gateway 单活跃会话语义一致）。
//
// 用法：
//
//	go run . -wasm <gateway_nojs.wasm> -cases cases.txt
//	go run . -wasm <wasm> '{"method":"engine_version"}' ...
package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"
)

const armTimeout = 600 * time.Second

type verdict struct {
	Verdict  string `json:"verdict"`
	Index    int    `json:"index"`
	Detail   string `json:"detail,omitempty"`
	Wasmoon  string `json:"wasmoon,omitempty"`
	Wasmtime string `json:"wasmtime,omitempty"`
}

func runArm(exe, wasm, casesPath string) (frames []string, err error) {
	args := []string{wasm, "--cases", casesPath}
	cmd := exec.Command(exe, args...)
	out, err := cmd.Output()
	if err != nil {
		return nil, err
	}
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		line = strings.TrimSpace(line)
		if line != "" {
			frames = append(frames, line)
		}
	}
	return frames, nil
}

func canonical(frames []string) []interface{} {
	var parsed []interface{}
	for _, f := range frames {
		var v interface{}
		if err := json.Unmarshal([]byte(f), &v); err != nil {
			parsed = append(parsed, f) // 非 JSON 帧按原文比对
			continue
		}
		parsed = append(parsed, v)
	}
	return parsed
}

func main() {
	wasm := flag.String("wasm", "", "gateway 零导入风味 wasm 路径")
	cases := flag.String("cases", "", "NDJSON 请求文件（每行一条；空则用命令行余参）")
	indexFile := flag.String("index", "", "请求→用例名映射文件（tab 分隔：帧序号\t用例名）")
	wasmoonExe := flag.String("wasmoon", `D:\code\Vitro\scripts\wasm_arms\_build\native\debug\build\wasm_arms\wasmoon_arm\wasmoon_arm.exe`, "wasmoon 臂宿主")
	wasmtimeExe := flag.String("wasmtime", `D:\code\Vitro\scripts\wasm_arms\wasmtime_arm\wasmtime_arm.exe`, "wasmtime 臂宿主")
	flag.Parse()

	if *wasm == "" {
		fmt.Fprintln(os.Stderr, "usage: duel -wasm <wasm> [-cases file] [request...]")
		os.Exit(2)
	}
	caseNames := map[int]string{}
	if *indexFile != "" {
		f, err := os.Open(*indexFile)
		if err != nil {
			fatalf("open index: %v", err)
		}
		sc := bufio.NewScanner(f)
		for sc.Scan() {
			parts := strings.SplitN(sc.Text(), "	", 2)
			if len(parts) == 2 {
				var idx int
				fmt.Sscanf(parts[0], "%d", &idx)
				caseNames[idx] = parts[1]
			}
		}
		f.Close()
	}
	var requests []string
	if *cases != "" {
		f, err := os.Open(*cases)
		if err != nil {
			fatalf("open cases: %v", err)
		}
		defer f.Close()
		sc := bufio.NewScanner(f)
		sc.Buffer(make([]byte, 1024*1024), 8*1024*1024)
		for sc.Scan() {
			l := strings.TrimSpace(sc.Text())
			if l != "" && !strings.HasPrefix(l, "//") {
				requests = append(requests, l)
			}
		}
	} else {
		requests = flag.Args()
	}
	if len(requests) == 0 {
		fatalf("no requests")
	}

	type armResult struct {
		frames []string
		err    error
	}
	wasmoonCh := make(chan armResult, 1)
	wasmtimeCh := make(chan armResult, 1)
	go func() {
		f, e := runArm(*wasmoonExe, *wasm, *cases)
		wasmoonCh <- armResult{f, e}
	}()
	go func() {
		f, e := runArm(*wasmtimeExe, *wasm, *cases)
		wasmtimeCh <- armResult{f, e}
	}()

	var wm, wt armResult
	// 两臂并发跑；先收快的，另一臂限时等待
	wt = <-wasmtimeCh
	select {
	case wm = <-wasmoonCh:
	case <-time.After(armTimeout):
		fatalf("wasmoon arm timed out after %s", armTimeout)
	}

	if wm.err != nil && wt.err != nil {
		emit(verdict{Verdict: "BOTH_CRASH", Detail: wm.err.Error() + " / " + wt.err.Error()})
		return
	}
	if wm.err != nil {
		emit(verdict{Verdict: "WASMOON_CRASH", Detail: wm.err.Error()})
		return
	}
	if wt.err != nil {
		emit(verdict{Verdict: "WASMTIME_CRASH", Detail: wt.err.Error()})
		return
	}

	// 帧数一致性前置检查（响应帧数不同本身就是分叉）
	if len(wm.frames) != len(wt.frames) {
		emit(verdict{Verdict: "HOST_DIVERGENCE", Detail: fmt.Sprintf("frame count %d vs %d", len(wm.frames), len(wt.frames))})
		return
	}
	// 会话型协议：instance 是单例，双臂各自独立实例，逐帧比对 JSON 语义
	for i := range requests {
		name := caseNames[i]
		// run 帧依赖同用例的 compile 帧；compile 分叉时 run 的分叉是派生，
		// 只对 compile 帧报 HOST_DIVERGENCE（run 帧标 DERIVED_SKIP）。
		wmCanon := canonical(wm.frames[i : i+1])
		wtCanon := canonical(wt.frames[i : i+1])
		if equalJSON(wmCanon, wtCanon) {
			emit(verdict{Verdict: "AGREE", Index: i, Detail: name})
		} else {
			emit(verdict{Verdict: "HOST_DIVERGENCE", Index: i,
				Detail:   name + " | wasmoon=" + trunc(wm.frames[i], 400) + " wasmtime=" + trunc(wt.frames[i], 400),
				Wasmoon:  trunc(wm.frames[i], 2000),
				Wasmtime: trunc(wt.frames[i], 2000)})
		}
	}
}

func trunc(s string, n int) string {
	if len(s) > n {
		return s[:n] + "...(truncated)"
	}
	return s
}

func equalJSON(a, b []interface{}) bool {
	ab, _ := json.Marshal(a)
	bb, _ := json.Marshal(b)
	return string(ab) == string(bb)
}

func emit(v verdict) {
	b, _ := json.MarshalIndent(v, "", "  ")
	fmt.Println(string(b))
}

func fatalf(format string, args ...interface{}) {
	fmt.Fprintf(os.Stderr, "duel: "+format+"\n", args...)
	os.Exit(2)
}
