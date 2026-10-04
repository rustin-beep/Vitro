// gen_demo_algorithms：demo「算法可视化」侧栏数据生成器（2026-10-04，refs #28）。
//
// 输入（全部机判真值源，禁手画——侧栏列表 = 渲染产物）：
//
//	① scripts/teaching_annotation_diff/rules.json   → migrated_algorithms 43 族全集
//	② native/tests/golden/algorithm_annotations_v3.json → 模板→族映射 + display_name 中文名
//	③ templates/<tpl>/source.c                      → 每族代表示例源码
//
// 输出：demo/algorithms.js（浏览器脚本形态，同 cases.js：全局 const 无导出）——
//
//	DEMO_ALGORITHMS = { groups: [{ id, label, items: [{ id, name, source }] }] }
//
// 完备性断言（漂移即红）：
//   - 分组固定表（七组）的并集 == rules.json 43 族集合（漏族/多族/改名即红）
//   - 每族必须有代表模板（golden 首现）与非空 source.c
//
// 产物不入库（2026-10-04 发射化：与 demo/js/*.js、wasm.wasm 同形态）——
// ci.yml 与 pages.yml 消费前现场发射，发射即检查闸（断言失败即红，
// 陈旧产物无法存在）；.gitignore 有 demo/algorithms.js。
//
// 用法：go run ./scripts/gen_demo_algorithms
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// 七组呈现层分组（组概念属 UI 非引擎语义；完备性由下方断言机判保证——
// 族名从 rules.json 来，本表漏/多/错名即红）
var groups = []struct {
	id, label string
	algos     []string
}{
	{"sorting", "排序", []string{"bubble_sort", "insertion_sort", "merge_sort", "quick_sort", "selection_sort", "heap_sort", "counting_sort", "shell_sort", "radix_sort"}},
	{"search", "查找", []string{"binary_search", "is_prime"}},
	{"graph", "图", []string{"bfs", "dfs", "dijkstra", "floyd", "kruskal_mst", "prim_mst", "topological_sort"}},
	{"tree", "树", []string{"bst_insert", "bst_search", "bst_delete", "bst_validate", "avl_tree", "huffman_tree", "level_order", "threaded_binary_tree"}},
	{"structures", "结构", []string{"linked_list_append", "linked_list_delete", "static_linked_list", "circular_linked_list", "linked_stack", "linked_queue", "circular_queue", "hash_table", "seq_list", "union_find", "josephus"}},
	{"string", "字符串", []string{"string_match_bf", "string_match_kmp", "string_reverse"}},
	{"mathdp", "数学与动态规划", []string{"gcd", "hanoi", "dp"}},
}

type goldenEntry struct {
	Algorithm   string `json:"algorithm"`
	DisplayName string `json:"display_name"`
}

type rulesFile struct {
	Migrated []string `json:"migrated_algorithms"`
}

func die(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "gen_demo_algorithms: "+format+"\n", args...)
	os.Exit(1)
}

// jsBacktick 把源码文本产出为 JS 反引号字面量，附带两件机械清洗：
//
//	① CRLF 归一（模板源 LF；防 Windows checkout 翻转产物字节）；
//	② 剥对拍模板的参数化注释标记 /*__PARAM_x__*/（2026-10-04 视觉审阅：
//	  该标记是对拍 harness 的注入锚语法，直接展示教学观感差；剥除是纯
//	  注释删除不改语义，可编译性由 demo_smoke「43 源 compile 全 ok」兜底）。
func jsBacktick(s string) string {
	s = reParamMark.ReplaceAllString(s, "")
	s = strings.ReplaceAll(s, "\\", "\\\\")
	s = strings.ReplaceAll(s, "`", "\\`")
	s = strings.ReplaceAll(s, "${", "\\${")
	// CRLF 归一（模板源 LF；防 Windows checkout 翻转产物字节）
	s = strings.ReplaceAll(s, "\r\n", "\n")
	return s
}

var reParamMark = regexp.MustCompile(`/\*__PARAM_[a-z_0-9]+__\*/`)

// ── 小工具 ──────────────────────────────────────────────

func fileExists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}

func containsStr(list []string, v string) bool {
	for _, x := range list {
		if x == v {
			return true
		}
	}
	return false
}

func appendUnique(list []string, v string) []string {
	for _, x := range list {
		if x == v {
			return list
		}
	}
	return append(list, v)
}

func camel(snake string) string {
	parts := strings.Split(snake, "_")
	out := parts[0]
	for _, w := range parts[1:] {
		if w == "" {
			continue
		}
		out += strings.ToUpper(w[:1]) + w[1:]
	}
	return out
}

// isExtraRepresented：extra 族的代表源已脱离 templates 目录——golden 桶里
// 若同时挂有该族模板，它们已进 variants（consumedTpls 已含），此处只对
// 「名字恰与 extra 族 camel 同名」的兜底场景判重（现无此形态，防御性）。
func isExtraRepresented(tpl string, tplByAlgo map[string]string, root string) bool {
	entries, err := os.ReadDir(filepath.Join(root, "scripts", "gen_demo_algorithms", "extra"))
	if err != nil {
		return false
	}
	for _, e := range entries {
		n := strings.TrimSuffix(e.Name(), ".c")
		if camel(n) == tpl {
			return true
		}
	}
	return false
}

func tplTagFor(root, algo string, tplByAlgo map[string]string) string {
	if s, ok := extraSrcFor(root, algo); ok && s != "" {
		return "extra"
	}
	return tplByAlgo[algo]
}

func loadAlgoSource(root, algo string, tplByAlgo map[string]string) string {
	if s, ok := extraSrcFor(root, algo); ok && s != "" {
		return s
	}
	tpl := tplByAlgo[algo]
	if tpl == "" {
		die("族 %s 在 golden 无代表模板（对拍面缺口——rules.json 与 golden 漂移？）", algo)
	}
	return loadTplSource(root, tpl)
}

func loadTplSource(root, tpl string) string {
	sb, err := os.ReadFile(filepath.Join(root, "templates", tpl, "source.c"))
	if err != nil {
		die("模板 %s source.c: %v", tpl, err)
	}
	if len(bytes.TrimSpace(sb)) == 0 {
		die("模板 %s source.c 为空", tpl)
	}
	return string(sb)
}

// extraSrcFor：scripts/gen_demo_algorithms/extra/<族>.c 覆盖源（存在即优
// 先于 golden/模板代表）
func extraSrcFor(root, algo string) (string, bool) {
	b, err := os.ReadFile(filepath.Join(root, "scripts", "gen_demo_algorithms", "extra", algo+".c"))
	if err != nil {
		return "", false
	}
	return string(b), true
}

func main() {
	root, err := os.Getwd()
	if err != nil {
		die("cwd: %v", err)
	}
	// 从 scripts/gen_demo_algorithms 到仓库根（支持任意 cwd：向上找 moon.mod+templates）
	for {
		if _, err := os.Stat(filepath.Join(root, "templates")); err == nil {
			if _, err2 := os.Stat(filepath.Join(root, "moonbit", "moon.mod")); err2 == nil {
				break
			}
		}
		parent := filepath.Dir(root)
		if parent == root {
			die("找不到仓库根（templates/ + moonbit/moon.mod）")
		}
		root = parent
	}

	// ① rules.json 43 族全集
	rb, err := os.ReadFile(filepath.Join(root, "scripts", "teaching_annotation_diff", "rules.json"))
	if err != nil {
		die("rules.json: %v", err)
	}
	var rl rulesFile
	if err := json.Unmarshal(rb, &rl); err != nil {
		die("rules.json 坏 JSON: %v", err)
	}
	if len(rl.Migrated) == 0 {
		die("rules.json migrated_algorithms 为空")
	}
	migrated := map[string]bool{}
	for _, a := range rl.Migrated {
		migrated[a] = true
	}

	// ② golden：模板→族 + display_name
	gb, err := os.ReadFile(filepath.Join(root, "native", "tests", "golden", "algorithm_annotations_v3.json"))
	if err != nil {
		die("golden: %v", err)
	}
	golden := map[string][]goldenEntry{}
	if err := json.Unmarshal(gb, &golden); err != nil {
		die("golden 坏 JSON: %v", err)
	}
	// 族 → 代表模板（golden 序内首现）+ 中文名
	tplByAlgo := map[string]string{}
	nameByAlgo := map[string]string{}
	tpls := make([]string, 0, len(golden))
	for tpl := range golden {
		tpls = append(tpls, tpl)
	}
	sort.Strings(tpls) // 稳定序：同族多模板取字典序首（golden 数组序同模板内固定）
	for _, tpl := range tpls {
		for _, e := range golden[tpl] {
			if e.Algorithm == "" {
				continue
			}
			if _, dup := tplByAlgo[e.Algorithm]; !dup {
				tplByAlgo[e.Algorithm] = tpl
			}
			if _, has := nameByAlgo[e.Algorithm]; !has && e.DisplayName != "" {
				nameByAlgo[e.Algorithm] = e.DisplayName
			}
		}
	}

	// ③ extra 覆盖源（scripts/gen_demo_algorithms/extra/<族>.c）——
	// golden 31 族外的 12 族（camelCase 模板判据不命中或行级特征不满足）
	// 与命中形态更好的族由此提供；优先级最高
	// 已知豁免（引擎侧行号基准致 infer 拿错行文本，修复挂 Rust 退役后，
	// 两侧同病形态——见 demo_smoke 豁免表同源注释）：is_prime、
	// threaded_binary_tree 两族 step 标注不可得，侧栏条件渲染不显示。

	// ④ 中文名兜底：引擎判据源 detect_*.mbt 的 build_match("<族>", "<中文名>")
	// （golden 31 族外的 extra 族中文名唯一真源——从引擎代码机判提取，禁手画）
	detectFiles, err := filepath.Glob(filepath.Join(root, "moonbit", "teaching", "steps", "detect*.mbt"))
	if err != nil || len(detectFiles) == 0 {
		die("detect_*.mbt 不可读: %v", err)
	}
	reBuildMatch := regexp.MustCompile(`build_match\(\s*"([a-z_0-9]+)",\s*"([^"]+)"`)
	for _, df := range detectFiles {
		db, err := os.ReadFile(df)
		if err != nil {
			die("读 %s: %v", df, err)
		}
		for _, m := range reBuildMatch.FindAllStringSubmatch(string(db), -1) {
			if _, has := nameByAlgo[m[1]]; !has {
				nameByAlgo[m[1]] = m[2]
			}
		}
	}

	// 完备性断言一：分组并集 == 43 族集合
	union := map[string]string{} // algo -> group id
	for _, g := range groups {
		for _, a := range g.algos {
			if prev, dup := union[a]; dup {
				die("算法 %s 同时出现在组 %s 与 %s", a, prev, g.id)
			}
			union[a] = g.id
		}
	}
	var missing, extra []string
	for a := range migrated {
		if _, ok := union[a]; !ok {
			missing = append(missing, a)
		}
	}
	for a := range union {
		if !migrated[a] {
			extra = append(extra, a)
		}
	}
	if len(missing) > 0 || len(extra) > 0 {
		sort.Strings(missing)
		sort.Strings(extra)
		die("分组表漂移：rules.json 有而分组缺 %v；分组有而 rules.json 无 %v", missing, extra)
	}

	// ── 模板全量纳入（2026-10-04 用户拍板「资源放着浪费」：82 个 .c 模板
	// 全进侧栏——仿 heron 课程式三级组织 组→族→变体；cpp_ 前缀 6 个不进
	// 〔source.cpp 无 source.c 自然出局 + F-2 已裁砍 C++：class/template
	// 编译必败，负资产〕）。三桶归类（机判）：
	//   ① golden 有条目 → 按条目族归（代表 = 字典序首，其余为变体）；
	//   ② camel 名与族名精确匹配（无 golden 条目）→ 归该族变体；
	//   ③ 其余 → 「扩展练习」组平铺（未迁移族真值资源——能跑回放但
	//      无算法标注，UI 诚实标注状态）。
	templates := map[string][]string{} // 族 → 模板列表（golden 条目序）
	for _, tpl := range tpls {
		for _, e := range golden[tpl] {
			if e.Algorithm != "" && migrated[e.Algorithm] {
				templates[e.Algorithm] = appendUnique(templates[e.Algorithm], tpl)
			}
		}
	}
	// camel 桶（去重：已入 golden 桶的模板不重复归）
	var consumedTpls = map[string]bool{}
	for a := range templates {
		for _, t := range templates[a] {
			consumedTpls[t] = true
		}
	}
	// 全集与三桶对账（漂移即红）：代表+变体+扩展 == templates/*.c 全集
	var allTpls []string
	entries, err := os.ReadDir(filepath.Join(root, "templates"))
	if err != nil {
		die("templates/ 不可读: %v", err)
	}
	for _, e := range entries {
		if e.IsDir() && fileExists(filepath.Join(root, "templates", e.Name(), "source.c")) {
			allTpls = append(allTpls, e.Name())
		}
	}
	sort.Strings(allTpls)
	for _, a := range rl.Migrated {
		c := camel(a)
		// Windows 文件系统大小写不敏感——camel 名须经 allTpls 精确匹配取
		// 目录真名（kruskalMst 幽灵命中 kruskalMST 实锤），否则 Set 对账多算
		real := ""
		for _, t := range allTpls {
			if strings.EqualFold(t, c) {
				real = t
				break
			}
		}
		if real != "" && !consumedTpls[real] {
			templates[a] = appendUnique(templates[a], real)
			consumedTpls[real] = true
		}
	}
	var xlab []string
	for _, t := range allTpls {
		if !consumedTpls[t] && !isExtraRepresented(t, tplByAlgo, root) {
			xlab = append(xlab, t)
		}
	}

	// 全集对账（Set 语义——跨族归属的模板在 Set 层只算一次）：消耗集 ∪
	// 扩展集 == templates/*.c 全集，漂移即红
	setUnion := map[string]bool{}
	for t := range consumedTpls {
		setUnion[t] = true
	}
	for _, t := range xlab {
		setUnion[t] = true
	}
	if len(setUnion) != len(allTpls) {
		var ghost, missed []string
		for t := range setUnion {
			if !containsStr(allTpls, t) {
				ghost = append(ghost, t)
			}
		}
		for _, t := range allTpls {
			if !setUnion[t] {
				missed = append(missed, t)
			}
		}
		sort.Strings(ghost)
		sort.Strings(missed)
		die("模板全集对账失败：消耗+扩展=%d != templates/*.c=%d（幽灵=%v / 漏归=%v）", len(setUnion), len(allTpls), ghost, missed)
	}

	// 生成
	var b bytes.Buffer
	b.WriteString("// @generated by scripts/gen_demo_algorithms — 勿手改（产物不入库：CI/pages 现场发射）\n")
	b.WriteString("// 43 算法族 = teaching/steps 全集（rules.json 机判）；中文名 = golden display_name\n")
	b.WriteString("// + detect_*.mbt build_match 提取；示例源码 = templates/ 代表（golden 首现）\n")
	b.WriteString("// + extra/ 覆盖源；同族其余模板 = variants；未归类模板 = 扩展练习组\n")
	b.WriteString("//（2026-10-04，refs #28 + 用户拍板全量纳入：82 个 .c 模板全覆盖——\n")
	b.WriteString("// cpp_ 前缀不进，F-2 已裁砍 C++，class/template 编译必败）。\n")
	b.WriteString("\"use strict\";\n\n")
	b.WriteString("// 分组 × 族清单；source = 可直接载入编辑器的判据命中示例；\n")
	b.WriteString("// variants = 同族其它模板（点击切换示例形态）；xlab = 扩展练习。\n")
	b.WriteString("const DEMO_ALGORITHMS = {\n  groups: [\n")
	for _, g := range groups {
		fmt.Fprintf(&b, "    { id: %q, label: %q, items: [\n", g.id, g.label)
		// 组内按 golden 中文名稳定序输出无必要——保持分组表声明的教学序
		for _, a := range g.algos {
			name := nameByAlgo[a]
			if name == "" {
				die("族 %s 无 display_name（golden 首现条目缺中文名）", a)
			}
			// 变体 = 该族模板列表 - 代表（extra 族代表为 extra 源，golden
			// 模板若同时存在则全部作为变体展示）
			var variants []string
			if _, hasExtra := extraSrcFor(root, a); hasExtra {
				variants = templates[a]
			} else if tlist := templates[a]; len(tlist) > 1 {
				variants = tlist[1:]
			}
			fmt.Fprintf(&b, "      { id: %q, name: %q, template: %q, source: `%s`, variants: [",
				a, name, tplTagFor(root, a, tplByAlgo), jsBacktick(loadAlgoSource(root, a, tplByAlgo)))
			for i, v := range variants {
				if i > 0 {
					b.WriteString(", ")
				}
				fmt.Fprintf(&b, "\n        { tpl: %q, source: `%s` }", v, jsBacktick(loadTplSource(root, v)))
			}
			if len(variants) > 0 {
				b.WriteString("\n      ] },\n")
			} else {
				b.WriteString("] },\n")
			}
		}
		b.WriteString("    ] },\n")
	}
	// 扩展练习组（未归类模板——能跑回放但无算法标注，UI 诚实标注）
	b.WriteString("    { id: \"xlab\", label: \"扩展练习\", xitems: [\n")
	for _, t := range xlab {
		fmt.Fprintf(&b, "      { id: %q, name: %q, source: `%s` },\n", t, t, jsBacktick(loadTplSource(root, t)))
	}
	b.WriteString("    ] },\n")
	b.WriteString("  ],\n};\n")

	out := b.Bytes()
	outPath := filepath.Join(root, "demo", "algorithms.js")
	if err := os.WriteFile(outPath, out, 0o644); err != nil {
		die("写 %s: %v", outPath, err)
	}
	fmt.Printf("gen_demo_algorithms: 生成 %s（%d 族 × %d 组）\n", outPath, len(migrated), len(groups))
}
