// teaching_annotation_diff·--catalog-check（#36，2026-10-16）：引擎
// algorithms.catalog 导出的三方对账闸——
//
//	A. 判据源码提取物：detect_*.mbt 的 build_match 调用（括号平衡扫描，
//	   family/display_name/第 5 参是否恒空 []）
//	B. 引擎导出：`vitro api algorithms.catalog` 双臂（native exe + js 直编
//	   壳）——两臂先互拍一致（纪律 14 最小面：两臂都是单源壳直连引擎）
//	C. rules.json migrated_algorithms（43 族全集）
//	D. gen_demo_algorithms 呈现层分组表（id/label/组内族集——demo 消费
//	   切换前的双源过渡锁）
//
// 断言：A↔B 逐条（display_name + vis_events 位——A 的第 5 参恒空 ↔
// vis_events=false）；B.family 集 == C 集；B.groups == D 的 id/label 且
// B 条目 group 归属 == D 组内成员。
//
// J9 义务：--catalog-selftest 内存注入两路证红（提取物 display_name
// 篡改 / rules 集合缺键）——不落盘。
//
// 前置：EnsureFresh 自建（native release cmd/vitro + js release
// cmd/vitro_js）；node 在 PATH（js 臂宿主）。
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"vitro/scripts/internal/freshness"
)

type catalogEntry struct {
	Family      string `json:"family"`
	DisplayName string `json:"display_name"`
	Group       string `json:"group"`
	VisEvents   bool   `json:"vis_events"`
}

type catalogExport struct {
	Schema     string         `json:"schema"`
	Total      int            `json:"total"`
	Groups     []catalogGroup `json:"groups"`
	Algorithms []catalogEntry `json:"algorithms"`
}

type catalogGroup struct {
	ID    string `json:"id"`
	Label string `json:"label"`
}

// build_matchSource：判据源码提取物（A）。
type buildMatchSource struct {
	Family      string
	DisplayName string
	VisEvents   bool // 第 5 参非恒空 []
}

var detectFiles = []string{
	"detect.mbt", "detect_search.mbt", "detect_graph.mbt",
	"detect_tree.mbt", "detect_structures.mbt", "detect_math.mbt",
}

// extractBuildMatches：括号平衡扫描 build_match 调用块，取前两个字符串
// 参数与最后一个参数（第 5 参）。
func extractBuildMatches(stepsDir string) ([]buildMatchSource, error) {
	var out []buildMatchSource
	for _, f := range detectFiles {
		src, err := os.ReadFile(filepath.Join(stepsDir, f))
		if err != nil {
			return nil, fmt.Errorf("读取判据源码失败 %s: %w", f, err)
		}
		text := string(src)
		idx := 0
		for {
			pos := strings.Index(text[idx:], "build_match(")
			if pos < 0 {
				break
			}
			pos += idx
			j := pos + len("build_match(")
			depth := 1
			for depth > 0 && j < len(text) {
				switch text[j] {
				case '(':
					depth++
				case ')':
					depth--
				}
				j++
			}
			if depth != 0 {
				return nil, fmt.Errorf("build_match 调用块未闭合：%s", f)
			}
			block := text[pos:j]
			inner := block[strings.IndexByte(block, '(')+1 : strings.LastIndexByte(block, ')')]
			// 逐参切分（顶层逗号——字符串字面量内逗号不算）
			var params []string
			var cur strings.Builder
			inStr := false
			for i := 0; i < len(inner); i++ {
				c := inner[i]
				if c == '"' {
					inStr = !inStr
					cur.WriteByte(c)
					continue
				}
				if c == ',' && !inStr {
					params = append(params, strings.TrimSpace(cur.String()))
					cur.Reset()
					continue
				}
				cur.WriteByte(c)
			}
			params = append(params, strings.TrimSpace(cur.String()))
			// 尾逗号后的空白残参丢弃（moon fmt 多行形态）
			filtered := params[:0]
			for _, p := range params {
				if p != "" {
					filtered = append(filtered, p)
				}
			}
			params = filtered
			if len(params) != 5 {
				return nil, fmt.Errorf("build_match 参数数 %d ≠ 5：%s 内 %q", len(params), f, firstN(inner, 60))
			}
			fam := strings.Trim(params[0], `"`)
			disp := strings.Trim(params[1], `"`)
			vis := strings.TrimSpace(params[4]) != "[]"
			out = append(out, buildMatchSource{Family: fam, DisplayName: disp, VisEvents: vis})
			idx = j
		}
	}
	return out, nil
}

func firstN(s string, n int) string {
	if len(s) > n {
		return s[:n]
	}
	return s
}

// exeName：Windows 下可执行后缀（与 resolveServeExe 同口径）。
func exeName() string {
	if os.PathSeparator == '\\' {
		return "vitro.exe"
	}
	return "vitro"
}

// fetchCatalog：跑 `api algorithms.catalog {}` 并解析响应帧 result
// （argv 直传：native=[exe,"api",...]；js=["node",entry,"api",...]）。
func fetchCatalog(name string, argv []string) (catalogExport, error) {
	var out catalogExport
	cmd := exec.Command(name, append(argv, "api", "algorithms.catalog", "{}")...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return out, fmt.Errorf("%s 执行失败: %w\nstderr: %s", name, err, firstN(stderr.String(), 200))
	}
	var frame struct {
		OK     bool          `json:"ok"`
		Result catalogExport `json:"result"`
	}
	if err := json.Unmarshal(stdout.Bytes(), &frame); err != nil {
		return out, fmt.Errorf("响应帧解析失败（%s）: %w\nstdout: %s", name, err, firstN(stdout.String(), 200))
	}
	if !frame.OK {
		return out, fmt.Errorf("响应帧 ok=false（%s）", name)
	}
	out = frame.Result
	return out, nil
}

// bytes_Buf：避免与 main.go 的 bytes import 形态冲突的本文件局部别名。
// （Go 不允许类型别名指向另一个包的类型再当 Buf 用——直接用标准库。）

// compareCatalogs：三方对账（返回全部红项——fail loud 但一次性报全）。
func compareCatalogs(a []buildMatchSource, b catalogExport, migrated map[string]bool, demoGroups []demoGroup) []string {
	var errs []string
	if len(a) != len(b.Algorithms) {
		errs = append(errs, fmt.Sprintf("条数：判据提取物 %d ≠ 引擎导出 %d", len(a), len(b.Algorithms)))
	}
	byFamily := map[string]catalogEntry{}
	for _, e := range b.Algorithms {
		byFamily[e.Family] = e
	}
	for _, s := range a {
		e, ok := byFamily[s.Family]
		if !ok {
			errs = append(errs, fmt.Sprintf("判据族 %q 不在引擎导出", s.Family))
			continue
		}
		if e.DisplayName != s.DisplayName {
			errs = append(errs, fmt.Sprintf("%s display_name：判据 %q ≠ 引擎 %q", s.Family, s.DisplayName, e.DisplayName))
		}
		if e.VisEvents != s.VisEvents {
			errs = append(errs, fmt.Sprintf("%s vis_events：判据第 5 参恒空=%v ≠ 引擎 %v", s.Family, !s.VisEvents, e.VisEvents))
		}
	}
	// C：rules.json migrated_algorithms 集
	if len(migrated) != len(b.Algorithms) {
		errs = append(errs, fmt.Sprintf("族数：rules.json %d ≠ 引擎导出 %d", len(migrated), len(b.Algorithms)))
	}
	for fam := range migrated {
		if _, ok := byFamily[fam]; !ok {
			errs = append(errs, fmt.Sprintf("rules.json 族 %q 不在引擎导出", fam))
		}
	}
	// D：gen_demo_algorithms 分组表
	if len(demoGroups) != len(b.Groups) {
		errs = append(errs, fmt.Sprintf("分组数：demo 生成器 %d ≠ 引擎导出 %d", len(demoGroups), len(b.Groups)))
	}
	demoByID := map[string]demoGroup{}
	for _, g := range demoGroups {
		demoByID[g.ID] = g
	}
	for _, g := range b.Groups {
		d, ok := demoByID[g.ID]
		if !ok {
			errs = append(errs, fmt.Sprintf("引擎分组 %q 不在 demo 生成器表", g.ID))
			continue
		}
		if d.Label != g.Label {
			errs = append(errs, fmt.Sprintf("分组 %q label：demo %q ≠ 引擎 %q", g.ID, d.Label, g.Label))
		}
		want := map[string]bool{}
		for _, f := range d.Algos {
			want[f] = true
		}
		for _, e := range b.Algorithms {
			if e.Group == g.ID && !want[e.Family] {
				errs = append(errs, fmt.Sprintf("族 %q 引擎归组 %q ≠ demo 生成器归属", e.Family, g.ID))
			}
		}
	}
	// D 反向（2026-10-17 审阅 P3-⑧）：demo 生成器表多列的族不捕——幽灵条目
	// （不在引擎导出）与归属分叉（demo 列在 A 组、引擎归 B 组）原先双向
	// 只查了引擎→demo 一边。
	engineGroupByFamily := map[string]string{}
	for _, e := range b.Algorithms {
		engineGroupByFamily[e.Family] = e.Group
	}
	for _, g := range demoGroups {
		for _, f := range g.Algos {
			eg, ok := engineGroupByFamily[f]
			if !ok {
				errs = append(errs, fmt.Sprintf("demo 生成器组 %q 列族 %q 不在引擎导出（僵尸/拼写）", g.ID, f))
				continue
			}
			if eg != g.ID {
				errs = append(errs, fmt.Sprintf("demo 生成器组 %q 列族 %q 引擎归组为 %q（归属分叉）", g.ID, f, eg))
			}
		}
	}
	return errs
}

type demoGroup struct {
	ID, Label string
	Algos     []string
}

// extractDemoGroups：正则提取 gen_demo_algorithms main.go 的 groups var。
func extractDemoGroups(path string) ([]demoGroup, error) {
	src, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	text := string(src)
	start := strings.Index(text, "var groups = ")
	if start < 0 {
		return nil, fmt.Errorf("gen_demo_algorithms 未找到 groups var")
	}
	// []struct { 类型声明 }{ 字面量起始——从字面量段起扫描，避免类型声明
	// 结尾的 \n}{ 提前截断
	body := text[start:]
	braceOpen := strings.Index(body, "}{")
	if braceOpen < 0 {
		return nil, fmt.Errorf("groups 字面量起始 }{ 未找到")
	}
	body = body[braceOpen+1:]
	end := strings.Index(body, "\n}")
	if end < 0 {
		return nil, fmt.Errorf("groups 字面量未闭合")
	}
	block := body[:end]
	re := regexp.MustCompile(`\{"([a-z]+)", "([^"]+)", \[\]string\{([^}]*)\}\}`)
	var out []demoGroup
	for _, m := range re.FindAllStringSubmatch(block, -1) {
		var algos []string
		for _, a := range strings.Split(m[3], ",") {
			// 先 TrimSpace 再剥引号——顺序反了前导空格会挡住引号剥除
			a = strings.Trim(strings.TrimSpace(a), `"`)
			if a != "" {
				algos = append(algos, a)
			}
		}
		out = append(out, demoGroup{ID: m[1], Label: m[2], Algos: algos})
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("groups 提取零条（正则失配？）")
	}
	return out, nil
}

// runCatalogCheck：--catalog-check 主流程（双臂 + 三方）。
func runCatalogCheck(root string, selftest bool) error {
	stepsDir := filepath.Join(root, "moonbit", "teaching", "steps")
	a, err := extractBuildMatches(stepsDir)
	if err != nil {
		return err
	}

	// B：双臂拉取（native release vitro.exe + js release vitro_js.js）
	vitroExe := filepath.Join(root, "moonbit", "_build", "native", "release", "build", "cmd", "vitro", exeName())
	freshness.EnsureFresh("catalog_check_native", vitroExe,
		"build", "--release", "--target", "native", "cmd/vitro")
	jsEntry := filepath.Join(root, "moonbit", "_build", "js", "release", "build", "cmd", "vitro_js", "vitro_js.js")
	freshness.EnsureFresh("catalog_check_js", jsEntry,
		"build", "--release", "--target", "js", "cmd/vitro_js")

	bNative, err := fetchCatalog(vitroExe, nil)
	if err != nil {
		return err
	}
	bJs, err := fetchCatalog("node", []string{jsEntry})
	if err != nil {
		return err
	}
	// 双臂互拍
	if n, j := fmt.Sprint(bNative), fmt.Sprint(bJs); n != j {
		return fmt.Errorf("双臂导出不一致：\nnative: %s\njs:     %s", firstN(n, 300), firstN(j, 300))
	}

	// C：rules.json migrated 集
	rulesPath := filepath.Join(root, "scripts", "teaching_annotation_diff", "rules.json")
	rules, _, err := loadRules(rulesPath)
	if err != nil {
		return err
	}
	migrated := map[string]bool{}
	for _, m := range rules.MigratedAlgorithms {
		migrated[m] = true
	}

	// D：gen_demo_algorithms 分组表
	demoGroups, err := extractDemoGroups(filepath.Join(root, "scripts", "gen_demo_algorithms", "main.go"))
	if err != nil {
		return err
	}

	errs := compareCatalogs(a, bNative, migrated, demoGroups)
	if selftest {
		// J9 四路内存注入证红（路 3/4 = 2026-10-17 审阅 P3-⑧ 补：D 反向
		// 双形态；双臂不一致为主路径硬等值比对——selftest 每跑即真比一次，
		// 不做套套式注入）
		spoiled := append([]buildMatchSource(nil), a...)
		spoiled[0].DisplayName = "篡改名"
		if e := compareCatalogs(spoiled, bNative, migrated, demoGroups); len(e) == 0 {
			return fmt.Errorf("selftest：display_name 篡改未红（锚无牙）")
		}
		dropOne := map[string]bool{}
		for k := range migrated {
			dropOne[k] = true
		}
		for k := range dropOne {
			delete(dropOne, k)
			break
		}
		if e := compareCatalogs(a, bNative, dropOne, demoGroups); len(e) == 0 {
			return fmt.Errorf("selftest：rules 缺键未红（锚无牙）")
		}
		ghost := append([]demoGroup(nil), demoGroups...)
		ghost[0].Algos = append([]string(nil), ghost[0].Algos...)
		ghost[0].Algos = append(ghost[0].Algos, "phantom_family_zz")
		if e := compareCatalogs(a, bNative, migrated, ghost); len(e) == 0 {
			return fmt.Errorf("selftest：demo 幽灵族未红（D 反向无牙）")
		}
		misfile := append([]demoGroup(nil), demoGroups...)
		misfile[0].Algos = append([]string(nil), misfile[0].Algos...)
		if len(misfile) < 2 || len(misfile[0].Algos) == 0 {
			return fmt.Errorf("selftest：分组表形态不足（<2 组或空组）——注入前提缺失")
		}
		misfile[1].Algos = append(misfile[1].Algos, misfile[0].Algos[0])
		if e := compareCatalogs(a, bNative, migrated, misfile); len(e) == 0 {
			return fmt.Errorf("selftest：demo 归属分叉未红（D 反向无牙）")
		}
		fmt.Println("teaching_annotation_diff --catalog-check selftest: 四路注入均红（锚有牙）")
		return nil
	}
	if len(errs) > 0 {
		fmt.Println("teaching_annotation_diff --catalog-check 红：")
		sort.Strings(errs)
		for _, e := range errs {
			fmt.Println("  -", e)
		}
		os.Exit(1)
	}
	fmt.Printf("teaching_annotation_diff --catalog-check 绿（判据 %d 条 ↔ 双臂导出一致 ↔ rules 43 ↔ demo 分组表）\n", len(a))
	return nil
}
