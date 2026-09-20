package main

// HTML 嵌入标签行豁免（2026-09-21 图览批）的证红锚测试（J9：判定面变更
// 上线前先证红）。
//
// 背景：README「项目图览」以 logo 式内联挂图（<img ... width="900">）后，
// img 行的 alt="影子验证门禁流水线" 提供 shadow_c_cases 规则语境（影子|shadow）、
// width="900" 落在其 [400,900] 区间——布局参数被判成"C 影子用例总数 900≠680
// 漂移"（实测红：README.md:44 / 影子验证框架.md:13 两处，width=880 同撞）。
// 修复：reHTMLTagLine（<img / width="）行整体跳过数字对账——嵌入图内的真
// 快照数字由 SVG data-fact 通道（tspan 锚）承担，标签行数字只是布局参数。
//
//   - img 行带区间内数字 → 豁免，不判漂移（TestHTMLImgLineWidthExempt）
//   - 豁免不外溢：同文件真文本行数字漂移仍红（TestTextLineNearImgStillAudited）
//
// 若这两条判定翻转（img 行复活误报 / 文本行被顺带豁免），先修豁免边界再动文档。

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeImgFixture(t *testing.T, lines ...string) AuditResult {
	t.Helper()
	root := t.TempDir()
	rel := filepath.Join(root, "README.md")
	if err := os.WriteFile(rel, []byte(strings.Join(lines, "\n")+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	doc := FactsDoc{Facts: map[string]Fact{
		"shadow_c_cases": {Value: intPtr(676), Status: "ok"},
	}}
	return auditDocs(root, doc)
}

// img 行 width=900（恰在 [400,900] 区间）：修复前判漂移，修复后豁免。
func TestHTMLImgLineWidthExempt(t *testing.T) {
	res := writeImgFixture(t,
		`<img src="docs/current/04-标准库与防线/shadow-verification-flow.svg" alt="影子验证门禁流水线" width="900">`,
	)
	a := findAudit(res, "shadow_c_cases")
	if a == nil {
		t.Fatal("shadow_c_cases audit 缺失")
	}
	if len(a.Drift) != 0 {
		t.Fatalf("img 布局行不应判漂移，实判 %d 处（豁免失效）: %+v", len(a.Drift), a.Drift)
	}
	if a.Matched != 0 {
		t.Fatalf("img 布局行应整体跳过而非计一致命中，Matched=%d", a.Matched)
	}
}

// 豁免边界：同文件普通文本行的漂移数字必须仍红（豁免不得外溢到正文）。
func TestTextLineNearImgStillAudited(t *testing.T) {
	res := writeImgFixture(t,
		`<img src="shadow-verification-flow.svg" alt="影子验证门禁流水线" width="900">`,
		``,
		`当前规模：C 侧 **700 个用例**（Clang 影子对照真值 676，此行必须红）`,
	)
	a := findAudit(res, "shadow_c_cases")
	if a == nil {
		t.Fatal("shadow_c_cases audit 缺失")
	}
	if len(a.Drift) != 1 {
		t.Fatalf("真文本行漂移必须仍红，实判 Drift=%d", len(a.Drift))
	}
}
