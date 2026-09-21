package main

import "testing"

// cargo test 真值解析器（collectCargoTestFromOutput）的绿路径 + J9 埋雷。
//
// 背景（2026-09-22 修复）：suites 解析失败时曾**不写任何键**——沿用逻辑
// （collectAll 只对"键存在且 unavailable"的条目生效）因此跳过，CI 形态
// （--cargo-log）采到的套件数真值会在下一次日常运行落盘时被无声丢弃，
// 本地永远"待采集"、无法预演 CI 的漂移判定。修复 = 与 passed 对称地写
// unavailable。本文件的埋雷测试在修复前会红（键缺失 ≠ unavailable）。

const cargoLogSample = `     Running tests\vitro_e2e.rs (target\debug\deps\vitro_e2e-a1.exe)

running 3 tests
test a ... ok
test result: ok. 3 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out

     Running tests\typeck_unit_test.rs (target\debug\deps\typeck_unit_test-b2.exe)

running 5 tests
test result: ok. 5 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out
`

func TestCargoParseGreen(t *testing.T) {
	facts := map[string]Fact{}
	collectCargoTestFromOutput(cargoLogSample, 0, "native/cargo_test_ci.log", "parse_ci_log", facts)
	p := facts["cargo_test_passed"]
	if p.Status != "ok" || p.Value == nil || *p.Value != 8 {
		t.Fatalf("passed 绿路径（3+5=8）解析失败: %+v", p)
	}
	s := facts["cargo_test_suites"]
	if s.Status != "ok" || s.Value == nil || *s.Value != 2 {
		t.Fatalf("suites 绿路径（2 个 Running 行）解析失败: %+v", s)
	}
}

func TestCargoParseNoRunningLine(t *testing.T) {
	// J9 埋雷①：有 test result 行但无 Running 行的畸形日志——suites 必须
	// 显式 unavailable（修复前：键整个缺失，绕过沿用逻辑，真值无声丢失）。
	facts := map[string]Fact{}
	collectCargoTestFromOutput("test result: ok. 3 passed; 0 failed", 0, "log", "parse_ci_log", facts)
	s, ok := facts["cargo_test_suites"]
	if !ok || s.Status != "unavailable" {
		t.Fatalf("无 Running 行应显式 unavailable（键缺失会绕过沿用）: %+v", s)
	}
}

func TestCargoParseEmptyOutput(t *testing.T) {
	// J9 埋雷②：空/损坏日志——两个键都必须 unavailable，禁止兜底 0。
	facts := map[string]Fact{}
	collectCargoTestFromOutput("", 0, "log", "parse_ci_log", facts)
	for _, k := range []string{"cargo_test_passed", "cargo_test_suites"} {
		f, ok := facts[k]
		if !ok || f.Status != "unavailable" {
			t.Fatalf("%s 空输出应显式 unavailable: %+v", k, f)
		}
	}
}

func TestCargoParseZeroSuitesStillUnavailable(t *testing.T) {
	// J9 埋雷③：n==0（一个 Running 行都没有）与解析失败同语义——unavailable，
	// 不写 0（0 套件是假绿形态：cargo 根本没跑起来）。
	facts := map[string]Fact{}
	collectCargoTestFromOutput("Compiling vitro_native v0.1.0\nerror: build failed", 101, "log", "parse_ci_log", facts)
	if s := facts["cargo_test_suites"]; s.Status != "unavailable" {
		t.Fatalf("构建失败（0 套件）应 unavailable 而非 0: %+v", s)
	}
	if p := facts["cargo_test_passed"]; p.Status != "unavailable" {
		t.Fatalf("构建失败（0 passed）应 unavailable: %+v", p)
	}
}
