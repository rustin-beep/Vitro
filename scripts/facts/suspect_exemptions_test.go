package main

// suspect_exemptions 白名单机制锚（2026-10-01 --strict 接线批，模块审阅
// 09 P2-1 处方①）。三路 J9：
//   1. 未登记的 Suspect 行 → 仍计数（--strict 判红依据不变）；
//   2. 登记（path+contains 命中）→ 豁免并留痕（SuspectExemptedN）；
//   3. 登记但本轮零命中 → StaleSuspectExempts（僵尸豁免面，check 无条件红）；
//   4. 坏条目（缺字段/文件不存在/坏 JSON）→ loadSuspectExemptions 拒绝。

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// suspectExemptFixture：suspectFixture 扩展——在 TempDir 下同时铺
// suspect_exemptions.json（可为空表）与夹具文档，跑 auditDocs 返回结果。
func suspectExemptFixture(t *testing.T, line string, exempts string) AuditResult {
	t.Helper()
	root := t.TempDir()
	p := filepath.Join(root, "docs", "current", "01-定位与路线", "夹具.md")
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(strings.Join([]string{line}, "\n")+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(root, "scripts", "facts"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "scripts", "facts", "suspect_exemptions.json"),
		[]byte(exempts), 0o644); err != nil {
		t.Fatal(err)
	}
	doc := FactsDoc{Facts: map[string]Fact{
		"shadow_c_cases": {Value: intPtr(683), Status: "ok"},
	}}
	return auditDocs(root, doc)
}

const suspectLine = "- **C 教学子集**：C Shadow Verification **682 个用例**（完全匹配 678 + known_issue 3 + gap_extension 1，无非预期差异）"

// 1：未登记 → Suspect 计数不变（--strict 判红依据）。空白名单 = 全计数。
func TestSuspectExemptUnregisteredStillCounts(t *testing.T) {
	res := suspectExemptFixture(t, suspectLine, "[]\n")
	a := findAudit(res, "shadow_c_cases")
	if a == nil {
		t.Fatal("规则未出现在审计结果中")
	}
	if len(a.Suspect) != 1 || len(a.SuspectExempted) != 0 {
		t.Fatalf("未登记的 Suspect 行应原样计数：Suspect=%d Exempted=%d",
			len(a.Suspect), len(a.SuspectExempted))
	}
	if res.SuspectN != 1 || res.SuspectExemptedN != 0 || len(res.StaleSuspectExempts) != 0 {
		t.Fatalf("空白名单下计数应全落 Suspect：SuspectN=%d ExemptedN=%d Stale=%d",
			res.SuspectN, res.SuspectExemptedN, len(res.StaleSuspectExempts))
	}
}

// 2：登记（path 对 + contains 命中行文本）→ 豁免留痕、SuspectN 归零。
func TestSuspectExemptRegisteredExempts(t *testing.T) {
	res := suspectExemptFixture(t, suspectLine, `[{
		"path": "docs/current/01-定位与路线/夹具.md",
		"contains": "682 个用例",
		"reason": "测试锚：合法未来值行"
	}]`)
	a := findAudit(res, "shadow_c_cases")
	if len(a.Suspect) != 0 || len(a.SuspectExempted) != 1 {
		t.Fatalf("登记命中的行应豁免：Suspect=%d Exempted=%d",
			len(a.Suspect), len(a.SuspectExempted))
	}
	if res.SuspectN != 0 || res.SuspectExemptedN != 1 || len(res.StaleSuspectExempts) != 0 {
		t.Fatalf("豁免后 SuspectN 应为 0 且无僵尸条目：SuspectN=%d ExemptedN=%d Stale=%d",
			res.SuspectN, res.SuspectExemptedN, len(res.StaleSuspectExempts))
	}
}

// 3：登记但 contains 零命中 → 行仍计数 + 僵尸条目标红（check 无条件红依据）。
func TestSuspectExemptStaleEntryFlagsRed(t *testing.T) {
	res := suspectExemptFixture(t, suspectLine, `[{
		"path": "docs/current/01-定位与路线/夹具.md",
		"contains": "不存在的内容锚",
		"reason": "测试锚：应判僵尸"
	}]`)
	a := findAudit(res, "shadow_c_cases")
	if len(a.Suspect) != 1 || len(a.SuspectExempted) != 0 {
		t.Fatalf("零命中的条目不得豁免任何行：Suspect=%d Exempted=%d",
			len(a.Suspect), len(a.SuspectExempted))
	}
	if len(res.StaleSuspectExempts) != 1 {
		t.Fatalf("零命中条目应进 StaleSuspectExempts（无条件红）：got %d",
			len(res.StaleSuspectExempts))
	}
}

// 4：坏条目三形态 → loadSuspectExemptions 拒绝（fail loud，不走 auditDocs
// 以免 os.Exit 杀测试进程）。
func TestSuspectExemptLoadRejects(t *testing.T) {
	root := t.TempDir()
	dir := filepath.Join(root, "scripts", "facts")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	p := filepath.Join(dir, "suspect_exemptions.json")

	for name, body := range map[string]string{
		"坏 JSON":     `[{`,
		"缺字段":        `[{"path": "docs/current/x.md", "contains": "x"}]`,
		"文件不存在": `[{"path": "docs/current/无此文件.md", "contains": "x", "reason": "r"}]`,
	} {
		if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
		if _, err := loadSuspectExemptions(root); err == nil {
			t.Fatalf("%s 应被拒绝（fail loud）", name)
		}
	}

	// 合法空表 + 缺文件（向后兼容）均通过。
	if err := os.WriteFile(p, []byte("[]"), 0o644); err != nil {
		t.Fatal(err)
	}
	if es, err := loadSuspectExemptions(root); err != nil || len(es) != 0 {
		t.Fatalf("空表应通过：es=%d err=%v", len(es), err)
	}
	if err := os.Remove(p); err != nil {
		t.Fatal(err)
	}
	if es, err := loadSuspectExemptions(root); err != nil || len(es) != 0 {
		t.Fatalf("缺文件应视为空表（向后兼容）：es=%d err=%v", len(es), err)
	}
}

// 回归锚：豁免不改变 Suspect 语义本身——同一行在无白名单时必先进 Suspect
// （防止"为过闸改判定"的回归形态）。
func TestSuspectExemptDoesNotWeakenDetection(t *testing.T) {
	res := suspectExemptFixture(t, suspectLine, "[]\n")
	a := findAudit(res, "shadow_c_cases")
	if len(a.Suspect) != 1 {
		t.Fatalf("基准：该行必进 Suspect（当前=%d），豁免机制不得改变判定本身", len(a.Suspect))
	}
}
