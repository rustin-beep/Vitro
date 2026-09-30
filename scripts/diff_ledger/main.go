// diff_ledger —— 差异台账对账闸（S8 批零号二段，2026-09-30）。
//
// 单源：scripts/diff_ledger/ledger.json（24 条差异 + capability_flags 17 项；
// 初始 14 条源自 MoonBit迁移蓝图v1 §⑦，capability_flags 键集源自知识沉淀
// 勘察报告附录 A）。本闸把总计划 §8 的守门规则机判化：
//
//	「引擎行为与台账冲突时要么改行为要么改台账，禁止沉默漂移」
//
// 判定四路（任一红即 exit 1；输入读不到/解析失败 fail loud exit 2）：
//
//  1. schema：schema 版本串；capability_flags 恰 17 键（键集锁定——加键/
//     删键即红，改承诺面须连坐本闸）；differences 非空；ID 唯一且格式
//     ^DIFF-[A-Z0-9]+(-[A-Z0-9]+)*-[0-9]{2}$；class / carry_over / status /
//     evidence 枚举域；anchors 三键齐备且元素为非空字符串。
//  2. 正向对账：ledger anchors 引用的每条 case 必须真实存在于对应防线
//     的 known 白名单（台账不得虚报锚）。
//  3. 反向对账：三防线 known 白名单的每一条必须被 ledger 至少一条引用
//     （收编完整性——防线新豁免一条分叉而台账无条目 = 沉默漂移，即红）。
//  4. --selftest：注入五类违规证红（J9 埋雷义务；任一路不红 exit 2）。
//
// 三防线 known 真值源：
//   - clang_direct：scripts/clang_direct/known_direct.json（JSON 直读，case 字段）
//   - vm_diff：scripts/vm_diff/known_diffs.json（JSON 直读，case 字段）
//   - shadow：**闸内清单**（下方 shadowKnown）——权威源 = native/AGENTS.md
//     防线 1 记载的 known_issue 实跑清单 + scripts/shadow_verify/main.go
//     knownFailureCases；shadow 侧 known 增删须同步本清单（双向监控义务，
//     注释同 KNOWN_FAILURE_CASES 的 E2E 双向约定）。shadow 未把 known 外置
//     JSON 是历史形态——外置化与 G-7 存量三处同族，登记技术债随防线维护
//     窗口；届时本闸改为直读，清单删除。
//
// 边界（如实记录，2026-09-30 实测口径）：gap 目录 @category=*bug* 的 4 条
// 预注册豁免（string_len_manual / loop_var_shadow / function_pointer_sizeof /
// sizeof_array_param）是「豁免规则面」而非活差异清单，不入对账——其中
// string_len_manual 与 loop_var_shadow 当前两侧 match（空转豁免，spfa_default
// 同族），清理义务在 shadow 防线侧；活差异清单以实跑 known_issue 为准。
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"regexp"
	"strings"
)

// ---------------------------------------------------------------- ledger 模型

type anchors struct {
	ShadowKnown      []string `json:"shadow_known"`
	ClangDirectKnown []string `json:"clang_direct_known"`
	VMDiffKnown      []string `json:"vm_diff_known"`
}

type difference struct {
	ID                  string   `json:"id"`
	Title               string   `json:"title"`
	Class               string   `json:"class"`
	CarryOver           string   `json:"carry_over"`
	Status              string   `json:"status"`
	Evidence            string   `json:"evidence"`
	Anchors             anchors  `json:"anchors"`
	DetectableByDefense []string `json:"detectable_by_defense"`
}

type ledger struct {
	Schema          string         `json:"schema"`
	CapabilityFlags map[string]any `json:"capability_flags"`
	Differences     []difference   `json:"differences"`
}

// ---------------------------------------------------------------- 枚举与常量

var (
	classSet     = set("architectural", "implementable", "pedagogical")
	carryOverSet = set("inherit", "fix", "drop", "retest")
	statusSet    = set("verified-run", "verified-code", "verified-anchor",
		"verified-doc", "resolved-verified", "open", "open-unverified")
	evidenceSet = set("run", "code", "anchor", "doc")

	// detectableSet —— detectable_by_defense 值域（D18 修复 2026-09-30：
	// 原域开放且与 anchors 无一致性断言 ⇒ 旁证字段笔误静默——P3-1 实锤
	// 形态。三防线名 + 两个非 anchors 的防线侧观测值；加值须连坐本枚举）。
	detectableSet = map[string]bool{
		"shadow":               true,
		"clang_direct":         true,
		"vm_diff":              true,
		"libc_single_source":   true,
		"memory-verify-wbtest": true,
	}

	idPattern = regexp.MustCompile(`^DIFF-[A-Z0-9]+(-[A-Z0-9]+)*-[0-9]{2}$`)

	// capabilityFlagsKeys —— 17 键锁定（知识沉淀附录 A 原数；值随引擎演化
	// 更新，键集变更即红——改承诺面须连坐本闸与 §8）。
	capabilityFlagsKeys = []string{
		"pointer_width_bytes", "struct_layout", "float_literal_default",
		"float_compare", "allocator", "quarantine_budget_kb", "heap_size_bytes",
		"realloc_always_moves", "printf_dynamic_width", "fprintf_custom_stream",
		"generic_match", "compound_literal_lifetime", "wasm_catch_unwind",
		"time_source", "include_once_implicit", "max_include_depth",
		"include_cycle_detect",
	}

	// shadowKnown —— shadow 防线实跑 known_issue 清单（真值源见包注释；
	// .c 后缀与 ledger anchors 口径一致）。
	shadowKnown = []string{
		"function_pointer_sizeof.c",
		"sizeof_array_param.c",
		"bTree_default.c",
	}
)

func set(xs ...string) map[string]bool {
	m := make(map[string]bool, len(xs))
	for _, x := range xs {
		m[x] = true
	}
	return m
}

// ---------------------------------------------------------------- 判定核心

// validate 对 ledger 副本跑 schema + 双向对账；返回全部违规（空 = 绿）。
// known 三参为防线真值清单，由调用方注入（正常跑 = 读盘/selftest = 构造）。
func validate(l *ledger, shadow, clangDirect, vmDiff []string) []string {
	var bad []string

	// —— schema ——
	if l.Schema != "vitro-diff-ledger-v1" {
		bad = append(bad, "schema 字符串 ≠ vitro-diff-ledger-v1: "+l.Schema)
	}
	if len(l.CapabilityFlags) != len(capabilityFlagsKeys) {
		bad = append(bad, fmt.Sprintf("capability_flags 键数 %d ≠ %d（键集锁定）",
			len(l.CapabilityFlags), len(capabilityFlagsKeys)))
	}
	for _, k := range capabilityFlagsKeys {
		if _, ok := l.CapabilityFlags[k]; !ok {
			bad = append(bad, "capability_flags 缺锁定键: "+k)
		}
	}
	if len(l.Differences) == 0 {
		bad = append(bad, "differences 为空")
	}
	seen := map[string]bool{}
	for _, d := range l.Differences {
		if !idPattern.MatchString(d.ID) {
			bad = append(bad, "ID 格式非法: "+d.ID)
		}
		if seen[d.ID] {
			bad = append(bad, "ID 重复: "+d.ID)
		}
		seen[d.ID] = true
		if !classSet[d.Class] {
			bad = append(bad, d.ID+": class 越界: "+d.Class)
		}
		if !carryOverSet[d.CarryOver] {
			bad = append(bad, d.ID+": carry_over 越界: "+d.CarryOver)
		}
		if !statusSet[d.Status] {
			bad = append(bad, d.ID+": status 越界: "+d.Status)
		}
		if !evidenceSet[d.Evidence] {
			bad = append(bad, d.ID+": evidence 越界: "+d.Evidence)
		}
		for _, c := range d.Anchors.ShadowKnown {
			if strings.TrimSpace(c) == "" {
				bad = append(bad, d.ID+": shadow_known 含空串")
			}
		}
		for _, c := range d.Anchors.ClangDirectKnown {
			if strings.TrimSpace(c) == "" {
				bad = append(bad, d.ID+": clang_direct_known 含空串")
			}
		}
		for _, c := range d.Anchors.VMDiffKnown {
			if strings.TrimSpace(c) == "" {
				bad = append(bad, d.ID+": vm_diff_known 含空串")
			}
		}
		// —— D18 断言（P3-2，2026-09-30）：detectable_by_defense 域枚举 +
		// 与 anchors 的一致性（⊇ 有锚防线名——旁证字段不得与锚矛盾；
		// 单向：防线"可检测"不要求"已豁免在册"〔语料未覆盖时合法〕）
		for _, v := range d.DetectableByDefense {
			if !detectableSet[v] {
				bad = append(bad, d.ID+": detectable_by_defense 越界: "+v)
			}
		}
		anchored := map[string][]string{
			"shadow":       d.Anchors.ShadowKnown,
			"clang_direct": d.Anchors.ClangDirectKnown,
			"vm_diff":      d.Anchors.VMDiffKnown,
		}
		for defense, cases := range anchored {
			if len(cases) > 0 && !contains(d.DetectableByDefense, defense) {
				bad = append(bad, d.ID+": detectable_by_defense 缺有锚防线 "+defense+
					"（anchors 与旁证字段矛盾——D18）")
			}
		}
	}

	// —— 正向：anchors 引用 ⊆ 防线真值 ——
	for _, d := range l.Differences {
		for _, c := range d.Anchors.ShadowKnown {
			if !contains(shadow, c) {
				bad = append(bad, d.ID+": shadow_known 引用不存在的豁免条目: "+c)
			}
		}
		for _, c := range d.Anchors.ClangDirectKnown {
			if !contains(clangDirect, c) {
				bad = append(bad, d.ID+": clang_direct_known 引用不存在的豁免条目: "+c)
			}
		}
		for _, c := range d.Anchors.VMDiffKnown {
			if !contains(vmDiff, c) {
				bad = append(bad, d.ID+": vm_diff_known 引用不存在的豁免条目: "+c)
			}
		}
	}

	// —— 反向：防线真值每条必须被至少一条差异收编 ——
	for _, c := range shadow {
		if !referenced(l, "shadow", c) {
			bad = append(bad, "shadow known 条目未被台账收编（沉默漂移）: "+c)
		}
	}
	for _, c := range clangDirect {
		if !referenced(l, "cd", c) {
			bad = append(bad, "clang_direct known 条目未被台账收编（沉默漂移）: "+c)
		}
	}
	for _, c := range vmDiff {
		if !referenced(l, "vd", c) {
			bad = append(bad, "vm_diff known 条目未被台账收编（沉默漂移）: "+c)
		}
	}
	return bad
}

func contains(xs []string, v string) bool {
	for _, x := range xs {
		if x == v {
			return true
		}
	}
	return false
}

func referenced(l *ledger, which, c string) bool {
	for _, d := range l.Differences {
		var list []string
		switch which {
		case "shadow":
			list = d.Anchors.ShadowKnown
		case "cd":
			list = d.Anchors.ClangDirectKnown
		case "vd":
			list = d.Anchors.VMDiffKnown
		}
		if contains(list, c) {
			return true
		}
	}
	return false
}

// ---------------------------------------------------------------- known 加载

type knownEntry struct {
	Case string `json:"case"`
}

func loadKnownCases(path string) []string {
	raw, err := os.ReadFile(path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "[diff_ledger] fail loud：读不到 %s：%v\n", path, err)
		os.Exit(2)
	}
	var entries []knownEntry
	if err := json.Unmarshal(raw, &entries); err != nil {
		fmt.Fprintf(os.Stderr, "[diff_ledger] fail loud：%s 解析失败：%v\n", path, err)
		os.Exit(2)
	}
	out := make([]string, 0, len(entries))
	for _, e := range entries {
		out = append(out, e.Case)
	}
	return out
}

// ---------------------------------------------------------------- selftest（J9）

// selftest 注入五类违规，每类必须红；任一不红 = exit 2（闸自身不可信）。
func selftest(good *ledger, shadow, clangDirect, vmDiff []string) {
	type probe struct {
		name  string
		mutaf func(*ledger)
	}
	probes := []probe{
		{"假 anchor（shadow 引用不存在条目）", func(l *ledger) {
			for i := range l.Differences {
				if l.Differences[i].ID == "DIFF-PTR-4BYTE-01" {
					l.Differences[i].Anchors.ShadowKnown = append(
						l.Differences[i].Anchors.ShadowKnown, "ghost_case.c")
				}
			}
		}},
		{"反向失覆盖（摘掉 bTree 收编）", func(l *ledger) {
			for i := range l.Differences {
				for j, c := range l.Differences[i].Anchors.ShadowKnown {
					if c == "bTree_default.c" {
						l.Differences[i].Anchors.ShadowKnown = append(
							l.Differences[i].Anchors.ShadowKnown[:j],
							l.Differences[i].Anchors.ShadowKnown[j+1:]...)
					}
				}
			}
		}},
		{"class 枚举越界", func(l *ledger) {
			l.Differences[0].Class = "cosmetic"
		}},
		{"ID 重复", func(l *ledger) {
			l.Differences[1].ID = l.Differences[0].ID
		}},
		{"capability_flags 删键", func(l *ledger) {
			delete(l.CapabilityFlags, "time_source")
		}},
		{"detectable 与 anchors 矛盾（D18：摘掉有锚防线）", func(l *ledger) {
			for i := range l.Differences {
				if l.Differences[i].ID == "DIFF-PTR-4BYTE-01" {
					l.Differences[i].DetectableByDefense = nil
				}
			}
		}},
	}
	ok := true
	for _, p := range probes {
		// 深拷贝差异切片与 map（probe 不得污染 good）
		cp := *good
		cp.Differences = append([]difference(nil), good.Differences...)
		cp.CapabilityFlags = map[string]any{}
		for k, v := range good.CapabilityFlags {
			cp.CapabilityFlags[k] = v
		}
		p.mutaf(&cp)
		violations := validate(&cp, shadow, clangDirect, vmDiff)
		if len(violations) == 0 {
			fmt.Printf("[selftest] ✗ 不红（缺陷）： %s\n", p.name)
			ok = false
		} else {
			fmt.Printf("[selftest] ✓ 红（%d 条违规）：%s\n", len(violations), p.name)
		}
	}
	if !ok {
		fmt.Fprintln(os.Stderr, "[diff_ledger] selftest 存在不红路径，拒绝运行")
		os.Exit(2)
	}
}

// ---------------------------------------------------------------- main

func main() {
	ledgerPath := "scripts/diff_ledger/ledger.json"
	if len(os.Args) > 1 && !strings.HasPrefix(os.Args[1], "-") {
		ledgerPath = os.Args[1]
	}

	raw, err := os.ReadFile(ledgerPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "[diff_ledger] fail loud：读不到 %s：%v\n", ledgerPath, err)
		os.Exit(2)
	}
	var l ledger
	if err := json.Unmarshal(raw, &l); err != nil {
		fmt.Fprintf(os.Stderr, "[diff_ledger] fail loud：%s 解析失败：%v\n", ledgerPath, err)
		os.Exit(2)
	}

	clangDirect := loadKnownCases("scripts/clang_direct/known_direct.json")
	vmDiff := loadKnownCases("scripts/vm_diff/known_diffs.json")
	shadow := append([]string(nil), shadowKnown...)

	if selftestMode := len(os.Args) > 1 && (os.Args[1] == "--selftest" || os.Args[1] == "-selftest"); selftestMode {
		selftest(&l, shadow, clangDirect, vmDiff)
		fmt.Println("[selftest] 六路全红，闸可信")
		return
	}

	violations := validate(&l, shadow, clangDirect, vmDiff)
	fmt.Printf("[diff_ledger] 条目 %d | capability_flags %d | shadow %d + clang_direct %d + vm_diff %d 条 known 对账\n",
		len(l.Differences), len(l.CapabilityFlags), len(shadow), len(clangDirect), len(vmDiff))
	if len(violations) > 0 {
		fmt.Fprintf(os.Stderr, "[diff_ledger] ✗ %d 条违规：\n", len(violations))
		for _, v := range violations {
			fmt.Fprintf(os.Stderr, "  - %s\n", v)
		}
		os.Exit(1)
	}
	fmt.Println("[diff_ledger] PASS：schema + 双向对账全绿（守门规则机判化就位）")
}
