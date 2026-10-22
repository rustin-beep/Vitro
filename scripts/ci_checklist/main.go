// ci_checklist —— 「存在即接入」注册表闸（msime scripts/run-checks.sh 形态
// 的 Vitro 化，2026-10-11 #71 防线续批）。
//
// 单一真源 = 文件系统：scripts/** 下每个含 `package main` 的 .go 文件即一个
// 可 go run 的判定型驱动；对账目标 = ci.yml 里全部 `go run ./scripts/...`
// 活行。**双向红**：
//
//	① 漏登记：驱动存在但 ci.yml 零活行引用（libc_boot 断供类红的事前形态
//	  ——闸落地了却没人跑）——例外表可豁免（reason 必填，僵尸例外无条件红）；
//	② 悬空：ci.yml 活行引用的驱动文件不存在（步骤写错路径/驱动被删）。
//
// 例外表 exceptions.json（本目录）：{"driver": "<scripts 相对路径>", "reason":
// "..."}。豁免面三类合法形态：库目录（canonicalize/internal/jmemit——被进程
// 内 import 消费，非独立 go run 闸）、本地工具（perf_baseline——CI 无消费面；
// docs_preview / gen_icon_preview 已于 #273 迁 .mts 出 Go 驱动面）、CLI 资产（vitro_cli——scripts/bin/vitro 是
// sh/js launcher 资产非 go run 目标）。例外条目若同时被 ci.yml 活行引用 =
// 僵尸（红——双向监控，known_direct 同哲学）。
//
// ④ moon test 目标面（2026-10-15 补向，js 后端漏接实锤）：ci.yml 全部
// moon test 活行的目标并集必须覆盖 moon 四目标 {js, native, wasm,
// wasm-gc}——后端集加员连坐测试面（AGENTS §14）。前三向防「Go 驱动
// 接线」，本向防「裸 moon 命令的目标面随架构演进滞后」。
//
// 判定型 fail loud（全域纪律 8/12）：不做环境探测、不静默跳过；rc 0=对账
// 一致，rc 1=任一向红。
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

type exception struct {
	Driver string `json:"driver"`
	Reason string `json:"reason"`
}

func main() {
	repo := "."
	if len(os.Args) > 2 && os.Args[1] == "-repo" {
		repo = os.Args[2]
	}
	ciPath := filepath.Join(repo, ".github", "workflows", "ci.yml")
	ciBytes, err := os.ReadFile(ciPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "ci_checklist: 读 ci.yml 失败: %v\n", err)
		os.Exit(2)
	}

	// ── 驱动集：scripts/** 含 package main 的 .go（剪枝生成物/非源码）──
	prune := map[string]bool{
		"_build": true, "__pycache__": true, "node_modules": true,
		"bin": true, // sh/js launcher 资产目录（vitro/vitro.cmd——非 go run 面）
	}
	// go run 的单位是**目录**（包）——同目录多个 package main 文件计一次。
	driverSet := map[string]bool{}
	var drivers []string
	scriptsRoot := filepath.Join(repo, "scripts")
	err = filepath.Walk(scriptsRoot, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			if prune[info.Name()] {
				return filepath.SkipDir
			}
			return nil
		}
		if strings.HasSuffix(path, "_test.go") {
			return nil
		}
		body, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		if regexp.MustCompile(`(?m)^package main\b`).Match(body) {
			// 目录=包=go run 单位（入口文件名不限：toolchain_probe.go/
			// replay_s1_s5.go 等本仓实存形态）；同包多文件按目录去重。
			rel, _ := filepath.Rel(repo, filepath.Dir(path))
			rel = filepath.ToSlash(rel) // Windows 反斜杠归一
			if !driverSet[rel] {
				driverSet[rel] = true
				drivers = append(drivers, rel)
			}
		}
		return nil
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "ci_checklist: 扫描 scripts 失败: %v\n", err)
		os.Exit(2)
	}

	// ── 活行集：ci.yml 全部 go run ./scripts/... ──
	liveRe := regexp.MustCompile("go run (\\./)?scripts/[a-zA-Z0-9_/${}.-]+")
	liveSet := map[string]bool{}
	for _, m := range liveRe.FindAllString(string(ciBytes), -1) {
		p := strings.TrimPrefix(strings.TrimPrefix(m, "go run "), "./")
		if strings.Contains(p, "${{") {
			// matrix 模板行（gates-diff）：driver 枚举在 matrix.include 段
			//——静态展开（缺一即不入活行=matrix 删驱动后本闸连带红）
			for _, d := range []string{"parser_diff", "lexer_diff", "typeck_diff", "codegen_diff", "vm_diff", "clang_direct"} {
				if strings.Contains(string(ciBytes), "- driver: "+d) {
					liveSet["scripts/"+d] = true
				}
			}
			continue
		}
		if strings.HasSuffix(p, ".go") {
			// 单文件 go run 形态（realcode_diff/vitro_clang_diff.go -check）：
			// 归一到所在目录对账（目录=驱动单位）
			p = strings.TrimSuffix(p, filepath.ToSlash(filepath.Base(p)))
			p = strings.TrimSuffix(p, "/")
		}
		liveSet[p] = true
	}

	// ── 例外表 ──
	exPath := filepath.Join(scriptsRoot, "ci_checklist", "exceptions.json")
	exBytes, err := os.ReadFile(exPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "ci_checklist: 读例外表失败: %v\n", err)
		os.Exit(2)
	}
	var exceptions []exception
	if err := json.Unmarshal(exBytes, &exceptions); err != nil {
		fmt.Fprintf(os.Stderr, "ci_checklist: 例外表 JSON 坏: %v\n", err)
		os.Exit(2)
	}
	exSet := map[string]string{}
	for _, e := range exceptions {
		if e.Reason == "" {
			fmt.Fprintf(os.Stderr, "ci_checklist: 例外 %s 缺 reason（例外必须自证）\n", e.Driver)
			os.Exit(1)
		}
		exSet[e.Driver] = e.Reason
	}

	failed := false
	// ① 漏登记（例外豁免）
	for _, d := range drivers {
		if liveSet[d] {
			continue
		}
		if _, ok := exSet[d]; ok {
			continue
		}
		fmt.Printf("漏登记: %s（scripts 下存在 main 驱动，ci.yml 零活行——要么接线要么进例外表自证）\n", d)
		failed = true
	}
	// ② 悬空
	for p := range liveSet {
		found := false
		for _, d := range drivers {
			if d == p || strings.HasPrefix(d, p+"/") {
				found = true
				break
			}
		}
		if !found {
			fmt.Printf("悬空: ci.yml 活行 go run ./%s 但该驱动不存在\n", p)
			failed = true
		}
	}
	// ③ 僵尸例外（例外驱动同时被 ci 引用）
	for _, e := range exceptions {
		if liveSet[e.Driver] {
			fmt.Printf("僵尸例外: %s 已被 ci.yml 活行引用，例外条目应删\n", e.Driver)
			failed = true
		}
	}
	// ④ moon test 目标面（2026-10-15 实锤补向：三后端批落地 js 后端但
	// 测试目标漏接，hygiene 裸奔一个 CI 周期无人红——本闸 ①②③ 防「Go
	// 驱动接线」，不防「裸 moon 命令的目标面随架构演进」。后端集加员
	// 必须连坐测试面（AGENTS §14 三臂强制），机判化于此。
	// 目标全集 = moon 工具链四目标 {js, native, wasm, wasm-gc}（低频演进；
	// 工具链加目标时本清单随 toolchain_probe 基线同步）。对账语义 =
	// ci.yml 全部 moon test 活行的目标**并集**覆盖全集（单步骤故意单
	// 目标合法——如 build-and-unit 的 --target native 只纳 native-only 包）。
	moonTestRe := regexp.MustCompile(`(?m)^\s*moon test\b[^\n]*`)
	targetUnion := map[string]bool{}
	for _, line := range moonTestRe.FindAllString(string(ciBytes), -1) {
		if strings.Contains(line, "--target ") {
			for _, t := range regexp.MustCompile(`--target (\S+)`).FindAllStringSubmatch(line, -1) {
				targetUnion[t[1]] = true
			}
		} else {
			targetUnion["wasm"] = true // 裸 moon test 默认目标 = wasm
		}
	}
	for _, want := range []string{"js", "native", "wasm", "wasm-gc"} {
		if !targetUnion[want] {
			fmt.Printf("目标面缺口: ci.yml 全部 moon test 活行的目标并集缺 --target %s（后端集加员须连坐测试面——AGENTS §14 三臂强制）\n", want)
			failed = true
		}
	}

	if failed {
		fmt.Println("ci_checklist: FAIL——存在即接入对账不符")
		os.Exit(1)
	}
	fmt.Printf("ci_checklist: PASS——驱动 %d / 活行 %d / 例外 %d 三向对账 + moon test 目标面（%d 目标齐）一致\n",
		len(drivers), len(liveSet), len(exceptions), len(targetUnion))
}
