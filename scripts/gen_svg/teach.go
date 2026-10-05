package main

// ─── 图 M：教学智能 43 算法族流水线（detect + infer 双机制）──────────────────
// 2026-10-04 新增（S8 收官文档配套）：teaching/steps 域此前零图——S8 总览 §二
// 的核心叙事（编译期 detect + 执行期 infer + algorithm_matches wire 出口）只有
// 文字，demo 侧栏的活值源头在图上不可见。
//
// 输入源 = 盘上真值文件活值直读（不经 facts 中转，skills 图同款模式；数字源
// 不在 facts.json 责任面内，全图无 data-fact 锚）：
//   ① scripts/teaching_annotation_diff/rules.json   → migrated_algorithms 族全集
//   ② scripts/teaching_annotation_diff/golden/algorithm_annotations_v3.json → golden 总条数（工序③固化迁出冻结区 2026-10-05）
//   ③ templates/*/source.c                          → 机判模板数（teaching_annotation_diff 同口径）
//
// 七组分组表与 gen_demo_algorithms 同源复制，完备性断言同款（组表并集 ==
// 迁移族全集、组表不含非迁移族，违者 fatal）——两处表一处变，另一处
// gen_svg -check（CI hygiene）即红顶人审。漂移防线 = -check：真值源变 →
// 落盘 SVG 失步 → 闸红。

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
)

type teachRules struct {
	Migrated []string `json:"migrated_algorithms"`
}

// 七组呈现层分组（与 scripts/gen_demo_algorithms/main.go 的 groups 表同源——
// 组概念属 UI 非引擎语义；完备性由 genTeach 内机判断言保证）
var teachGroups = []struct {
	id    string
	label string
	algos []string
}{
	{"sorting", "排序", []string{"bubble_sort", "insertion_sort", "merge_sort", "quick_sort", "selection_sort", "heap_sort", "counting_sort", "shell_sort", "radix_sort"}},
	{"search", "查找", []string{"binary_search", "is_prime"}},
	{"graph", "图", []string{"bfs", "dfs", "dijkstra", "floyd", "kruskal_mst", "prim_mst", "topological_sort"}},
	{"tree", "树", []string{"bst_insert", "bst_search", "bst_delete", "bst_validate", "avl_tree", "huffman_tree", "level_order", "threaded_binary_tree"}},
	{"structures", "结构", []string{"linked_list_append", "linked_list_delete", "static_linked_list", "circular_linked_list", "linked_stack", "linked_queue", "circular_queue", "hash_table", "seq_list", "union_find", "josephus"}},
	{"string", "字符串", []string{"string_match_bf", "string_match_kmp", "string_reverse"}},
	{"mathdp", "数学·DP", []string{"gcd", "hanoi", "dp"}},
}

func genTeach(root string, _ factsDoc) {
	// ── 数据采集（fail loud）──
	raw, err := os.ReadFile(filepath.Join(root, "scripts", "teaching_annotation_diff", "rules.json"))
	if err != nil {
		fatal("读 rules.json 失败: " + err.Error())
	}
	var rules teachRules
	if err := json.Unmarshal(raw, &rules); err != nil {
		fatal("解析 rules.json 失败: " + err.Error())
	}
	if len(rules.Migrated) == 0 {
		fatal("rules.json migrated_algorithms 为空")
	}
	family := map[string]bool{}
	for _, a := range rules.Migrated {
		family[a] = true
	}
	nFamilies := len(rules.Migrated)

	goldRaw, err := os.ReadFile(filepath.Join(root, "scripts", "teaching_annotation_diff", "golden", "algorithm_annotations_v3.json"))
	if err != nil {
		fatal("读 algorithm_annotations_v3.json 失败: " + err.Error())
	}
	var golden map[string][]json.RawMessage
	if err := json.Unmarshal(goldRaw, &golden); err != nil {
		fatal("解析 algorithm_annotations_v3.json 失败: " + err.Error())
	}
	nGolden := 0
	for _, v := range golden {
		nGolden += len(v)
	}

	tplDir := filepath.Join(root, "templates")
	entries, err := os.ReadDir(tplDir)
	if err != nil {
		fatal("读 templates/ 失败: " + err.Error())
	}
	nTemplates := 0
	for _, e := range entries {
		if e.IsDir() {
			if _, err := os.Stat(filepath.Join(tplDir, e.Name(), "source.c")); err == nil {
				nTemplates++
			}
		}
	}

	// 七组交集计数 + 完备性断言（与 gen_demo_algorithms 断言同款，fail loud）
	counts := make([]int, len(teachGroups))
	covered := map[string]bool{}
	for gi, g := range teachGroups {
		for _, a := range g.algos {
			if !family[a] {
				fatal("分组表含非迁移族 " + a + "（组 " + g.id + "）——与 gen_demo_algorithms 表失去同步，两侧同改")
			}
			counts[gi]++
			covered[a] = true
		}
	}
	for a := range family {
		if !covered[a] {
			fatal("迁移族 " + a + " 未入任何分组——分组表缺族，与 gen_demo_algorithms 两侧同改")
		}
	}

	// ── 绘制 ──
	P := svgOpen(1200, 890, "vitro 教学智能算法族流水线",
		"教学智能 · detect 编译期识别 + infer 执行期推断",
		fmt.Sprintf("对账 S8时间旅行与教学智能总览.md §二；数字=盘上真值活值直读（rules.json %d 族 / golden %d 条 / templates %d 模板），重生成 go run ./scripts/gen_svg teach",
			nFamilies, nGolden, nTemplates))
	P = append(P, markerDef,
		textF(600, 56, "tt", fmt.Sprintf("教学智能 · %d 算法族识别与逐帧推断", nFamilies), ""),
		textF(600, 92, "tm", "detect 编译期识别 + infer 执行期推断 · 教学中文文案由引擎生成（非前端拼装）", ""),
	)

	// 输入条：双通道源头
	P = append(P, box(40, 118, 1120, 64, "core", 12))
	P = append(P,
		textF(320, 148, "ts", "C 源码", ""),
		textF(320, 172, "tc", fmt.Sprintf("templates/ · %d 模板（含变体）", nTemplates), ""),
		textF(880, 148, "ts", "VM 逐帧执行现场", ""),
		textF(880, 172, "tc", "调用栈 / 局部变量 / 内存快照 / 输出游标", ""),
	)
	P = append(P,
		arrow(320, 182, 320, 230, "edge"),
		arrow(880, 182, 880, 230, "edge"),
	)

	// 左 zone：编译期识别 detect
	P = append(P, box(40, 236, 545, 356, "zone", 14),
		textF(312, 272, "t", "编译期识别 detect", ""),
		textF(312, 300, "tm", "vitro/engine/teaching/steps · detect*.mbt 按域拆分", ""),
	)
	P = append(P, box(64, 320, 497, 92, "card", 10),
		textF(312, 348, "ts", "U1#1 收紧版判据", ""),
		textL(88, 376, "tc", "函数命名主导（sort / search / tree …）"),
		textL(88, 400, "tc", "结构特征辅助 · 编译期一次判定"),
	)
	P = append(P, box(64, 432, 497, 144, "card", 10),
		textF(312, 460, "ts", "compile 帧 · algorithm_matches 字段", ""),
		textL(88, 488, "tc", "族名 / 中文名 / 函数 / 置信度 / 行号 / vis_events"),
		textL(88, 512, "tc", "协议「只增不改」纪律内 · 自诞生即可选"),
		textL(88, 536, "tc", "消费方：demo 侧栏 · agent（CLI --json 同源）"),
	)

	// 右 zone：执行期推断 infer
	P = append(P, box(615, 236, 545, 356, "zone", 14),
		textF(888, 272, "t", "执行期推断 infer", ""),
		textF(888, 300, "tm", "vitro/engine/teaching/steps · infer*.mbt 逐帧驱动", ""),
	)
	P = append(P, box(639, 320, 497, 92, "card", 10),
		textF(888, 348, "ts", "逐帧推断 · 教学文案模板", ""),
		textL(663, 376, "tc", "「第 1 趟：将第 1 大的元素放到正确位置」"),
		textL(663, 400, "tc", "级说明由引擎生成 · 前端只渲染不拼装"),
	)
	P = append(P, box(639, 432, 497, 144, "card", 10),
		textF(888, 460, "ts", "StepPayload 教学字段（每帧）", ""),
		textL(663, 488, "tc", "semantic_label（受控词表 · schema 附录 B 单源）"),
		textL(663, 512, "tc", "algorithm_step（教学文案）+ vis_events（事件行）"),
		textL(663, 536, "tc", "local_vars / call_stack 快照"),
		textL(663, 560, "tc", "array_snapshots / pointer_snapshots"),
	)

	// 七组分布：活值机判
	P = append(P, box(40, 616, 1120, 108, "zone", 14),
		textF(600, 646, "t", "七组分布（rules.json 迁移族全集机判）", ""),
	)
	for i, g := range teachGroups {
		x := 46 + i*160
		P = append(P, box(x, 660, 148, 48, "card", 10),
			textF(x+74, 682, "tc", g.label, ""),
			textF(x+74, 702, "ts", strconv.Itoa(counts[i]), ""),
		)
	}

	// 对拍纪律
	P = append(P, box(40, 748, 1120, 76, "warn", 12),
		textF(600, 778, "t", "对拍纪律", ""),
		textF(600, 806, "tc", fmt.Sprintf("%d 条 golden 首现序列 ↔ Rust oracle 逐条一致 · teaching_annotation_diff 机判 · %d 模板全绿（豁免显式过闸）", nGolden, nTemplates), ""),
	)

	P = append(P,
		textF(600, 858, "tc", "对账 S8时间旅行与教学智能总览.md §二 · 漂移重生成：go run ./scripts/gen_svg teach", ""),
	)
	writeSVG(root, "docs/current/05-教学体验/teaching-detect-infer-pipeline.svg", P)
}
