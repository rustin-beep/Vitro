package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// T6（2026-09-19）：MoonBit 测试真值解析器——绿路径 + J9 埋雷（假输出 /
// 无 Total 行 / 失败计数非零时的字段语义），红证随 go test 留痕。

func TestMoonbitParseGreen(t *testing.T) {
	facts := map[string]Fact{}
	collectMoonbitFromOutput("Total tests: 58, passed: 58, failed: 0", 0, facts)
	f, ok := facts["moonbit_test_passed"]
	if !ok || f.Status != "ok" || f.Value == nil || *f.Value != 58 {
		t.Fatalf("绿路径解析失败: %+v", f)
	}
}

func TestMoonbitParseFailureRunStillCounts(t *testing.T) {
	// 失败计数非零：passed 是真值（诚实记录失败量，不粉饰为 ok 之外的状态）
	facts := map[string]Fact{}
	collectMoonbitFromOutput("Total tests: 10, passed: 8, failed: 2", 1, facts)
	f := facts["moonbit_test_passed"]
	if f.Status != "ok" || *f.Value != 8 {
		t.Fatalf("失败形态应记 passed=8: %+v", f)
	}
}

func TestMoonbitParseNoTotalLine(t *testing.T) {
	// J9 埋雷：编译失败输出（无 Total 行）必须 unavailable，禁止兜底 0
	facts := map[string]Fact{}
	collectMoonbitFromOutput("Error: [3002] parse error ...", 1, facts)
	f, ok := facts["moonbit_test_passed"]
	if !ok || f.Status != "unavailable" {
		t.Fatalf("无 Total 行应 unavailable: %+v", f)
	}
}

func TestMoonbitParseEmptyOutput(t *testing.T) {
	// J9 埋雷：空输出 unavailable
	facts := map[string]Fact{}
	collectMoonbitFromOutput("", 0, facts)
	if f := facts["moonbit_test_passed"]; f.Status != "unavailable" {
		t.Fatalf("空输出应 unavailable: %+v", f)
	}
}

// S2（2026-09-19）：词法差分真值解析——绿路径 + J9 埋雷（FAIL 输出禁兜底）。

func TestLexerDiffParseGreen(t *testing.T) {
	n, ok := parseLexerDiffPass("lexer_diff: PASS——4800 个 TSV 逐字节一致（语料 x）")
	if !ok || n != 4800 {
		t.Fatalf("绿路径解析失败: n=%d ok=%v", n, ok)
	}
}

func TestLexerDiffParseFailLoud(t *testing.T) {
	// J9 埋雷：FAIL 输出（无 PASS 行）必须判 false，禁止把失败当 0 个采集
	if n, ok := parseLexerDiffPass("lexer_diff: FAIL——3 处差异（语料 x）"); ok || n != 0 {
		t.Fatalf("FAIL 输出必须不可采：n=%d ok=%v", n, ok)
	}
}

// S3 审阅补线（2026-09-20，F7）：解析差分真值解析器——绿路径 + J9 埋雷。
// 此前 facts.go:548 注释声称"（J9 埋雷覆盖假输出）"但无任何测试。

func TestParserDiffParseGreen(t *testing.T) {
	n, ok := parseParserDiffPass("parser_diff: PASS——597 个样本 AST+诊断序列归一后逐字节一致（语料 x）")
	if !ok || n != 597 {
		t.Fatalf("绿路径解析失败: n=%d ok=%v", n, ok)
	}
}

func TestParserDiffParseFailLoud(t *testing.T) {
	// J9 埋雷：FAIL 输出（无 PASS 行）必须判 false，禁止把失败当 0 个采集；
	// 崩溃输出（moon run 失败信息）同样不可采
	for _, out := range []string{
		"parser_diff: FAIL——3 处差异（语料 x）",
		"parser_diff: moon run cmd/dump_ast 失败: exit status 0xc00000fd",
	} {
		if n, ok := parseParserDiffPass(out); ok || n != 0 {
			t.Fatalf("假输出必须不可采（%q）: n=%d ok=%v", out, n, ok)
		}
	}
}

// ── 建包状态采集（2026-09-28 包图防漂移批）────────────────────────────────

func TestMoonbitPackagesGreen(t *testing.T) {
	root := t.TempDir()
	for _, d := range []string{
		"moonbit/ast", "moonbit/vm", "moonbit/protocol",
		"moonbit/cmd/run", "moonbit/lexer/internal/scanner",
		"moonbit/_build/pkg", "moonbit/.mooncakes/moonbitlang/x/fs", // 必须排除
	} {
		if err := os.MkdirAll(filepath.Join(root, filepath.FromSlash(d)), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(root, filepath.FromSlash(d), "moon.pkg"), []byte("{}"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(root, "moonbit", "moon.mod"),
		[]byte("name = \"vitro/engine\"\n\nversion = \"0.6.0\"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	facts := map[string]Fact{}
	collectMoonbitPackages(root, facts)

	f, ok := facts["moonbit_built_packages"]
	if !ok || f.Status != "ok" || f.SValue == "" {
		t.Fatalf("built_packages 绿路径失败: %+v", f)
	}
	got := map[string]bool{}
	for _, p := range strings.Fields(f.SValue) {
		got[p] = true
	}
	for _, want := range []string{"moonbit/ast", "moonbit/vm", "moonbit/protocol", "moonbit/cmd/run", "moonbit/lexer/internal/scanner"} {
		if !got[want] {
			t.Fatalf("缺包 %s: %q", want, f.SValue)
		}
	}
	for _, banned := range []string{"moonbit/_build/pkg", "moonbit/.mooncakes/moonbitlang/x/fs"} {
		if got[banned] {
			t.Fatalf("排除目录漏网: %q", f.SValue)
		}
	}

	v, ok := facts["moonbit_engine_version"]
	if !ok || v.Status != "ok" || v.SValue != "0.6.0" {
		t.Fatalf("engine_version 绿路径失败: %+v", v)
	}
}

func TestMoonbitPackagesNoVersionField(t *testing.T) {
	// J9 埋雷：moon.mod 缺 version 字段（形态变更）必须 unavailable，禁止兜底
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, "moonbit", "ast"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "moonbit", "ast", "moon.pkg"), []byte("{}"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "moonbit", "moon.mod"), []byte("name = \"vitro/engine\"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	facts := map[string]Fact{}
	collectMoonbitPackages(root, facts)
	if f := facts["moonbit_engine_version"]; f.Status != "unavailable" {
		t.Fatalf("缺 version 字段必须 unavailable: %+v", f)
	}
	if f := facts["moonbit_built_packages"]; f.Status != "ok" || !strings.Contains(f.SValue, "moonbit/ast") {
		t.Fatalf("包扫描不受 moon.mod 影响: %+v", f)
	}
}

func TestMoonbitPackagesEmptyTree(t *testing.T) {
	// J9 埋雷：零包目录（moonbit/ 整体缺失或空）必须 unavailable，禁止空串冒充真值
	root := t.TempDir()
	facts := map[string]Fact{}
	collectMoonbitPackages(root, facts)
	if f := facts["moonbit_built_packages"]; f.Status != "unavailable" {
		t.Fatalf("空树必须 unavailable: %+v", f)
	}
}
