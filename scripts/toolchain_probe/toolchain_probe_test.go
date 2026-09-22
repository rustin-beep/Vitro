package main

import (
	"strings"
	"testing"
)

// 基线解析/比较的 J9 锚。
//
// 背景（2026-09-22 CI 假红实测）：windows runner 的 git autocrlf 在
// checkout 时把 LF 基线检出为 CRLF，探针 Split("\n") 后每行尾部残留
// \r，与运行时实测串比较恒不等——版本一致也判"版本漂移"（CI 输出里
// \r 回车符还会把终端光标打回行首，基线/实测显示错乱成两行）。
// 修复 = baselineLines 对 CRLF 规范化；本文件锚定该判定面。

const lfBaseline = "# toolchain_probe 版本基线\nmoon 0.1.20260920 (914d7da 2026-09-20)\nmoonc v0.10.14+7d59c7ec9\n"
const crlfBaseline = "# toolchain_probe 版本基线\r\nmoon 0.1.20260920 (914d7da 2026-09-20)\r\nmoonc v0.10.14+7d59c7ec9\r\n"

func TestBaselineMatchesCRLFvsLF(t *testing.T) {
	// J9 埋雷①（本次 CI 假红形态）：CRLF 基线 vs LF 实测——同版本必须判相等。
	if !baselineMatches(crlfBaseline, lfBaseline) {
		t.Fatalf("CRLF 基线与 LF 实测同版本应相等（\\r 残留致假红）")
	}
}

func TestBaselineLinesNoCarriageReturn(t *testing.T) {
	for _, l := range baselineLines(crlfBaseline) {
		if strings.Contains(l, "\r") {
			t.Fatalf("规范化后行内不得残留 \\r: %q", l)
		}
	}
}

func TestBaselineDriftStillRed(t *testing.T) {
	// 反向锚：真版本漂移（实测 moonc 升级）必须仍判不等——规范化不得放松判定。
	actual := "# toolchain_probe 版本基线\nmoon 0.1.20260920 (914d7da 2026-09-20)\nmoonc v0.10.15+abcd\n"
	if baselineMatches(crlfBaseline, actual) {
		t.Fatalf("真版本漂移（moonc 0.10.14 vs 0.10.15）应判不等")
	}
}

func TestBaselineCommentAndBlankSkipped(t *testing.T) {
	// 注释行剔除 + 空行跳过（原逻辑空行会以空串参与比较——顺带收紧）。
	got := baselineLines("# 注释\n\nmoon 1 (a b)\nmoonc v2\n")
	if len(got) != 2 || got[0] != "moon 1 (a b)" || got[1] != "moonc v2" {
		t.Fatalf("注释/空行应剔除: %#v", got)
	}
}
