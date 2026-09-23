// libc_single_source：libc 三名单单源对账闸（S5 收尾批 · S6 前置）。
//
// 背景：Rust 侧「这个名字是不是 builtin」的判据是两张表的并集——
// `host_func_id::by_user_name`（路由名）∪ `BYTECODE_LIBC_ALL_FUNCS`
// （固定索引名，88 条）。MoonBit 侧照搬时把并集**手抄**成 libc 包的
// `builtin_all`（175 名）——于是同一事实有第四份副本，且三份之间零对账：
// libc 包注释里那句「`print_int` 不在此集（Rust host_func_id 无此名）」
// 实测即为**错误陈述**（Rust 侧 `by_user_name` 明确有
// `"print_int" | "__vitro_output" => Some(OUTPUT)` 别名臂）。本闸把
// 「三表一致」从注释里的承诺变成机判红线。
//
// 用法（**仓库根**）：
//
//	go run ./scripts/moonbit/libc_single_source            # 三表关系报告 + 判定
//	go run ./scripts/moonbit/libc_single_source -check     # 判定（CI 门禁用）
//	go run ./scripts/moonbit/libc_single_source --selftest # J9：注入差异必红
//
// 判据（规则见 rules.json，改名/搬锚点只改 JSON）：
//
//	① 四表各自无重复，且均非空（防「解析失败→空集→全绿」的假绿，
//	   空集不得绿是本仓防伪绿三条之一）
//	② builtin_all == (host_names ∪ bytecode_names) - excluded_from_union
//	③ |host_names ∩ bytecode_names| == expect.host_intersect_bytecode
//	④ pure_names ⊆ host_names ∩ bytecode_names
//
// fail loud：任一源文件缺失或锚点找不到 → exit 2（拒绝给判定，禁静默
// default）；断言不过 → exit 1。判定型脚本的自身证红（J9）由 --selftest
// 承担：先确认基线绿，再从 builtin_all 抽掉一个名，必须变红。
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

const rulesPath = "scripts/moonbit/libc_single_source/rules.json"

type sourceSpec struct {
	File        string `json:"file"`
	AnchorStart string `json:"anchor_start"`
	AnchorEnd   string `json:"anchor_end"`
	Kind        string `json:"kind"`
}

type rulesDoc struct {
	Schema   int                   `json:"schema"`
	Sources  map[string]sourceSpec `json:"sources"`
	Excluded []string              `json:"excluded_from_union"`
	Expect   struct {
		HostIntersectBytecode int `json:"host_intersect_bytecode"`
	} `json:"expect"`
}

var (
	reStringLit = regexp.MustCompile(`"([^"]+)"`)
	// match_arms：`"name" => Some(HOST_X)`（Rust 侧的 `"a" | "b" =>` 别名
	// 臂在生成物中已展开为多臂，故此处即名字集口径）
	reMatchArm = regexp.MustCompile(`(?m)^[ \t]*"([^"]+)"[ \t]*=>[ \t]*Some\(`)
	// match_arms 的函数体结束启发式：下一个顶层 `fn `/`pub fn `
	reNextTopFn = regexp.MustCompile(`(?m)^(pub )?fn `)
)

type table struct {
	name    string
	names   []string
	set     map[string]bool
	dupes   []string
	srcPath string
}

func main() {
	selftest := false
	check := false
	for _, a := range os.Args[1:] {
		switch a {
		case "--selftest":
			selftest = true
		case "-check":
			check = true
		default:
			fatal("未知参数: %s（可用：-check / --selftest）", a)
		}
	}

	raw, err := os.ReadFile(rulesPath)
	if err != nil {
		fatal("读规则失败（须在仓库根运行）: %v", err)
	}
	var rd rulesDoc
	if err := json.Unmarshal(raw, &rd); err != nil {
		fatal("规则解析失败: %v", err)
	}
	if rd.Schema != 1 {
		fatal("规则 schema 不支持: %d（期望 1）", rd.Schema)
	}

	builtin := mustTable(rd, "builtin_all")
	host := mustTable(rd, "host_names")
	bytecode := mustTable(rd, "bytecode_names")
	pure := mustTable(rd, "pure_names")

	if !check {
		report(builtin, host, bytecode, pure, rd)
	}

	if selftest {
		os.Exit(selftestRun(builtin, host, bytecode, pure, rd))
	}
	if verdict(builtin, host, bytecode, pure, rd) {
		fmt.Println("libc_single_source: PASS（三表一致：builtin_all == (host ∪ bytecode) - excluded，交集与 PURE 子集均符合）")
		return
	}
	fmt.Println("libc_single_source: FAIL——三名单已分叉（详见上方差异）")
	os.Exit(1)
}

// selftestRun：J9 埋雷。先确认基线绿（否则注入后的红无法归因），再模拟
// 「builtin_all 漏抄一名」，必须判红。
func selftestRun(b, h, bc, p table, rd rulesDoc) int {
	if !verdict(b, h, bc, p, rd) {
		fmt.Println("libc_single_source: selftest ABORT——基线不绿，注入后的红无法归因")
		return 2
	}
	// 取一个确在并集里的名做移除目标（确定性：并集字典序首个）
	u := unionOf(h, bc)
	if len(u) == 0 {
		fmt.Println("libc_single_source: selftest ABORT——并集为空，无法构造注入")
		return 2
	}
	victim := u[0]
	var reduced []string
	for _, n := range b.names {
		if n != victim {
			reduced = append(reduced, n)
		}
	}
	if len(reduced) == len(b.names) {
		fmt.Println("libc_single_source: selftest ABORT——移除目标不在 builtin_all 中")
		return 2
	}
	injected := table{name: b.name + "(injected: 抽掉 " + victim + ")", names: reduced,
		set: toSet(reduced), srcPath: b.srcPath}
	fmt.Printf("libc_single_source: selftest 已注入——builtin_all 抽掉 %q（模拟漏抄）\n", victim)
	if verdict(injected, h, bc, p, rd) {
		fmt.Println("libc_single_source: selftest FAIL——注入后仍判绿，闸门失效")
		return 1
	}
	fmt.Println("libc_single_source: selftest PASS——注入差异被捕获（红），J9 证红成立")
	return 0
}

// verdict：四项判据全过才是绿。返回 false 时打印全部差异（不早退，
// 一次暴露所有分叉方向）。
func verdict(b, h, bc, p table, rd rulesDoc) bool {
	ok := true
	for _, t := range []table{b, h, bc, p} {
		if len(t.dupes) > 0 {
			ok = false
			fmt.Printf("  [重复] %s 内有重复名 %d 个: %s\n", t.name, len(t.dupes), strings.Join(t.dupes, ", "))
		}
	}
	// ① 非空（空集不得绿）
	for _, t := range []table{b, h, bc, p} {
		if len(t.names) == 0 {
			ok = false
			fmt.Printf("  [空集] %s 解析出 0 个名——锚点或源文件已变，拒绝判定\n", t.name)
		}
	}
	if !ok {
		return false
	}

	// ② builtin_all == (host ∪ bytecode) - excluded
	u := unionOf(h, bc)
	excl := toSet(rd.Excluded)
	var want []string
	for _, n := range u {
		if !excl[n] {
			want = append(want, n)
		}
	}
	missing := diff(want, b.set)                  // 应在 builtin_all 却缺失
	extra := diff(sortedKeys(b.set), toSet(want)) // builtin_all 多出的
	if len(missing) > 0 || len(extra) > 0 {
		ok = false
		fmt.Printf("  [等式] builtin_all(%d) != (host ∪ bytecode)(%d) - excluded(%d)\n",
			len(b.names), len(u), len(rd.Excluded))
		if len(missing) > 0 {
			fmt.Printf("    builtin_all 缺少（并集有而 libc 无）: %s\n", strings.Join(missing, ", "))
		}
		if len(extra) > 0 {
			fmt.Printf("    builtin_all 多出（libc 有而并集无）: %s\n", strings.Join(extra, ", "))
		}
	}

	// ③ 交集计数
	inter := intersectOf(h, bc)
	if len(inter) != rd.Expect.HostIntersectBytecode {
		ok = false
		fmt.Printf("  [交集] |host ∩ bytecode| = %d，期望 %d（差集详情见下）\n",
			len(inter), rd.Expect.HostIntersectBytecode)
	}
	// ④ PURE ⊆ 交集
	var pureOut []string
	for _, n := range p.names {
		if !toSet(inter)[n] {
			pureOut = append(pureOut, n)
		}
	}
	if len(pureOut) > 0 {
		ok = false
		fmt.Printf("  [PURE] 下列 PURE 名不在 host ∩ bytecode 内: %s\n", strings.Join(pureOut, ", "))
	}
	return ok
}

func report(b, h, bc, p table, rd rulesDoc) {
	inter := intersectOf(h, bc)
	u := unionOf(h, bc)
	fmt.Println("libc 三名单单源对账（S5 收尾批 · S6 前置）")
	for _, t := range []table{b, h, bc, p} {
		fmt.Printf("  %-16s %4d 名  ← %s\n", t.name, len(t.names), t.srcPath)
	}
	fmt.Printf("  %-16s %4d 名（|host ∩ bytecode|=%d，并集 - excluded(%d) = %d）\n",
		"host ∪ bytecode", len(u), len(inter), len(rd.Excluded), len(u)-len(exclIn(u, rd.Excluded)))
}

func exclIn(u []string, excl []string) []string {
	var out []string
	e := toSet(excl)
	for _, n := range u {
		if e[n] {
			out = append(out, n)
		}
	}
	return out
}

// ---------------------------------------------------------------------------
// 提取
// ---------------------------------------------------------------------------

func mustTable(rd rulesDoc, key string) table {
	spec, ok := rd.Sources[key]
	if !ok {
		fatal("规则缺 source 定义: %s", key)
	}
	data, err := os.ReadFile(filepath.FromSlash(spec.File))
	if err != nil {
		fatal("读源失败 %s（须在仓库根运行）: %v", spec.File, err)
	}
	text := string(data)
	body, err := sliceByAnchors(text, spec)
	if err != nil {
		fatal("源 %s 的锚点定位失败: %v", spec.File, err)
	}
	var names []string
	switch spec.Kind {
	case "string_list":
		for _, m := range reStringLit.FindAllStringSubmatch(body, -1) {
			names = append(names, m[1])
		}
	case "match_arms":
		for _, m := range reMatchArm.FindAllStringSubmatch(body, -1) {
			names = append(names, m[1])
		}
	default:
		fatal("未知 kind: %s（source %s）", spec.Kind, key)
	}
	set := toSet(names)
	var dupes []string
	seen := map[string]int{}
	for _, n := range names {
		seen[n]++
	}
	for n, c := range seen {
		if c > 1 {
			dupes = append(dupes, fmt.Sprintf("%s×%d", n, c))
		}
	}
	sort.Strings(dupes)
	return table{name: key, names: names, set: set, dupes: dupes, srcPath: spec.File}
}

// sliceByAnchors：按 anchor_start 定位，anchor_end 为空时用「下一个顶层
// fn」启发式收尾（match_arms 形态）。
func sliceByAnchors(text string, spec sourceSpec) (string, error) {
	i := strings.Index(text, spec.AnchorStart)
	if i < 0 {
		return "", fmt.Errorf("anchor_start 未命中: %q", spec.AnchorStart)
	}
	rest := text[i+len(spec.AnchorStart):]
	if spec.AnchorEnd != "" {
		j := strings.Index(rest, spec.AnchorEnd)
		if j < 0 {
			return "", fmt.Errorf("anchor_end 未命中: %q", spec.AnchorEnd)
		}
		return rest[:j], nil
	}
	if loc := reNextTopFn.FindStringIndex(rest); loc != nil && loc[0] > 0 {
		return rest[:loc[0]], nil
	}
	return rest, nil
}

// ---------------------------------------------------------------------------
// 集合工具
// ---------------------------------------------------------------------------

func toSet(xs []string) map[string]bool {
	m := make(map[string]bool, len(xs))
	for _, x := range xs {
		m[x] = true
	}
	return m
}

func unionOf(a, b table) []string {
	m := map[string]bool{}
	for n := range a.set {
		m[n] = true
	}
	for n := range b.set {
		m[n] = true
	}
	return sortedKeys(m)
}

func intersectOf(a, b table) []string {
	var out []string
	for n := range a.set {
		if b.set[n] {
			out = append(out, n)
		}
	}
	sort.Strings(out)
	return out
}

func diff(xs []string, exclude map[string]bool) []string {
	var out []string
	for _, x := range xs {
		if !exclude[x] {
			out = append(out, x)
		}
	}
	sort.Strings(out)
	return out
}

func sortedKeys(m map[string]bool) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

func fatal(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "libc_single_source: "+format+"\n", args...)
	os.Exit(2)
}
