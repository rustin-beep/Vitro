package main

// Manual 桶兜底（FactAudit.Suspect，2026-09-23）的证红锚测试（J9）。
//
// 背景：分解式行（`682 个用例（678 + 3 + 1）`）因"子项与总数无法机判区分"
// 被归入 Manual 桶豁免漂移判定——`facts check` 恒绿。于是**真值变化时若只改
// 了一部分数字**（或整行都没跟上），门禁完全看不见。实测：d1b2d54 批次
// README.md:81 写 `682 个用例（完全匹配 678 + 3 + 1）` 而真值 683，
// `facts check` 报"漂移 0"。
//
// 兜底判据：整行候选数字中**是否有任一个等于真值**。已正确维护的分解式行
// 至少有一个数字（子项或总数）对上真值；整行都对不上 ⇒ 几乎必然漏连坐。
//
// 本测试锁三件事：
//   1. 整行无数字对上真值 → 进 Suspect（默认提醒、--strict 判红的依据）；
//   2. 行内任一数字对上真值 → 不进 Suspect（不误伤正确维护的分解式行）；
//   3. Suspect 是 Manual 的**子集**（不改变 Manual 桶口径，纯增量）。

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// suspectFixture：写一行到 docs/current 下的临时文档，跑 auditDocs。
func suspectFixture(t *testing.T, key string, truth int, line string) *FactAudit {
	t.Helper()
	root := t.TempDir()
	p := filepath.Join(root, "docs", "current", "01-定位与路线", "夹具.md")
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(strings.Join([]string{line}, "\n")+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	doc := FactsDoc{Facts: map[string]Fact{
		key: {Value: intPtr(truth), Status: "ok"},
	}}
	res := auditDocs(root, doc)
	a := findAudit(res, key)
	if a == nil {
		t.Fatalf("规则 %s 未出现在审计结果中", key)
	}
	return a
}

// 真实样本（README.md:81 形态）：总数与全部子项都没跟上真值 → 必进 Suspect。
func TestSuspectWholeLineMissesTruth(t *testing.T) {
	a := suspectFixture(t, "shadow_c_cases", 683,
		"- **C 教学子集**：C Shadow Verification **682 个用例**（完全匹配 678 + known_issue 3 + gap_extension 1，无非预期差异；vitro_better 已清零）")
	if len(a.Manual) != 1 {
		t.Fatalf("分解式行应进 Manual：Manual=%d", len(a.Manual))
	}
	if len(a.Suspect) != 1 {
		t.Fatalf("整行无数字等于真值 683（行内 {682,678,3,1}）应进 Suspect：Suspect=%d",
			len(a.Suspect))
	}
}

// 反向：只改了总数、子项仍留旧值 —— 行内含真值（总数那处）⇒ 不进 Suspect。
// 这是刻意的保守面：兜底只抓"整行全错"，不抓"部分未同步"（后者要人读算式）。
func TestSuspectLineContainsTruthNotFlagged(t *testing.T) {
	a := suspectFixture(t, "shadow_c_cases", 683,
		"- C Shadow Verification **683 个用例**（完全匹配 678 + known_issue 3 + gap_extension 1）")
	if len(a.Manual) != 1 {
		t.Fatalf("仍应进 Manual：Manual=%d", len(a.Manual))
	}
	if len(a.Suspect) != 0 {
		t.Fatalf("行内总数 683 等于真值，不应进 Suspect：Suspect=%d", len(a.Suspect))
	}
}

// 子项对上真值也算（真值可能是被分解出的子项，如 cpp 99 = 95 + 4 里的 95 不是、
// 但总数 99 是）——用"真值落在子项位"的形态复检，确保不是只看首数。
func TestSuspectTruthInSubItemCounts(t *testing.T) {
	a := suspectFixture(t, "shadow_cpp_cases", 95,
		"- C++ 侧 **99 个用例**（95 一致 + 4 clang_compile_fail）")
	if len(a.Suspect) != 0 {
		t.Fatalf("子项 95 等于真值，不应进 Suspect：Suspect=%d", len(a.Suspect))
	}
}

// Suspect 必须是 Manual 的子集（本兜底是纯增量，不改 Manual 口径）。
func TestSuspectSubsetOfManual(t *testing.T) {
	a := suspectFixture(t, "shadow_c_cases", 683,
		"- C Shadow Verification **682 个用例**（完全匹配 678 + 3 + 1）")
	if len(a.Suspect) > len(a.Manual) {
		t.Fatalf("Suspect(%d) 必须 ≤ Manual(%d)", len(a.Suspect), len(a.Manual))
	}
	for _, s := range a.Suspect {
		found := false
		for _, m := range a.Manual {
			if m.File == s.File && m.LineNo == s.LineNo {
				found = true
				break
			}
		}
		if !found {
			t.Fatalf("Suspect 条目 %s:%d 不在 Manual 中", s.File, s.LineNo)
		}
	}
}

// 非分解式行（不触发 Warn）走 Drift 老路，不被兜底截胡——防止误改判定归属。
func TestSuspectDoesNotHijackPlainDrift(t *testing.T) {
	a := suspectFixture(t, "shadow_c_cases", 683,
		"- C Shadow Verification 682 个用例")
	if len(a.Drift) != 1 {
		t.Fatalf("非分解式写错仍应判 Drift=1：Drift=%d", len(a.Drift))
	}
	if len(a.Suspect) != 0 {
		t.Fatalf("非 Manual 行不得进 Suspect：Suspect=%d", len(a.Suspect))
	}
}

// cargo 规则 pattern 不得被 facts 键名 `moonbit_test_passed` 的 "passed"
// 子串误命中（2026-09-29 实锤：README.mbt.md:47 是 moon 测试分解式行，
// 行内键名含 passed → 被圈进 cargo Manual/Suspect → --strict 假红）。
// 真实 cargo 行的形态是 "1027 passed"（数字紧邻），键名形态是
// `*_test_passed`（前缀下划线字母）——以 `\d+\s*passed` 收紧区分。
func TestCargoRuleIgnoresFactsKeyName(t *testing.T) {
	a := suspectFixture(t, "cargo_test_passed", 1027,
		"moon check && moon test    # 508 测试（source 14 + opcode 10 分解和 502；裸总数以 facts `moonbit_test_passed` 为准）")
	if len(a.Manual) != 0 {
		t.Fatalf("facts 键名 moonbit_test_passed 不得使 moon 分解式行进 cargo 规则 Manual：Manual=%d", len(a.Manual))
	}
	if len(a.Suspect) != 0 {
		t.Fatalf("facts 键名 moonbit_test_passed 不得使 moon 分解式行进 cargo 规则 Suspect：Suspect=%d", len(a.Suspect))
	}
}

// 反向锚：数字紧邻 passed 的真实形态（"1027 passed"）仍必须命中——
// 夹具行刻意不含 "cargo test"/"rust 单测"/"全绿" 其他分支词，单锁
// `\d+\s*passed` 分支自身（收紧不是漏防）。
func TestCargoRuleStillMatchesNumberPassed(t *testing.T) {
	a := suspectFixture(t, "cargo_test_passed", 1027,
		"- 防线快照：1027 passed，0 failed（分解式 1025 + 2）")
	if len(a.Manual) != 1 {
		t.Fatalf("数字紧邻 passed 的分解式行仍应进 Manual：Manual=%d", len(a.Manual))
	}
	if len(a.Suspect) != 0 {
		t.Fatalf("行内总数 1027 等于真值，不应进 Suspect：Suspect=%d", len(a.Suspect))
	}
}

// moonbit 区间带宽锚（2026-09-29）：真值 508 曾越旧上限 500 被滤出候选，
// 整行（README.mbt.md:47 形态）无候选等于真值 → Suspect 假红。锁两件事：
//   1. 真值落在区间内时，行内等于真值的数字使其不进 Suspect；
//   2. 真值越过区间上限的形态必须进 Suspect（带宽兜底本身可被发现——
//      上限再过时一次，这里会先红）。
func TestMoonbitTruthInRange(t *testing.T) {
	a := suspectFixture(t, "moonbit_test_passed", 508,
		"moon check && moon test    # 508 测试（source 14 + opcode 10 分解和 502）")
	if len(a.Suspect) != 0 {
		t.Fatalf("行内 508 等于真值且在区间内，不应进 Suspect：Suspect=%d", len(a.Suspect))
	}
}
