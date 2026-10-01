// teaching_annotation_diff —— S8 teaching 族级增量对拍器（批四号建，2026-10-01）。
//
// 用途：MoonBit cmd/serve 与 Rust golden（native/tests/golden/
// algorithm_annotations_v3.json）的**算法标注首现序列**族级对拍——只比
// 已迁移族条目（rules.json migrated_algorithms），未迁移族条目两侧跳过
//（MoonBit 侧 infer 臂 `None` 天然缺失，golden 侧按 algorithm 键过滤）。
// 族级增量（moon.pkg 头注对拍排期）：每族迁移批全量跑一轮，golden 不攒末批。
//
// 口径逐字照搬 native/tests/algorithm_annotation_golden_test.rs（提取段）：
//   compile（含算法检测）→ run → step.begin → step.next × step_budget
//   首现去重键 = (phase, desc)；条目 = algorithm/display_name/phase/desc/
//   code_line/src；src = 源码第 code_line 行 trim；code_line 越界 = ""。
//
// 双向断言：① 过滤后首现序列逐条相等（六字段）② 非空模板集与 golden
// 过滤后键集严格相等（MoonBit 新报已迁移族标注而 golden 无 = 红；反之亦然）。
//
// 豁免：rules.json exemptions（template+kind+algorithm+phase+desc 锚定，
// kind ∈ missing[golden 有 MoonBit 无]/extra[反向]/diff[字段值分歧]）。
// fail loud：规则文件缺失/坏 JSON/字段缺失一律 exit 2。
//
// 前置：`cd moonbit && moon build --target native cmd/serve`（exe 新鲜度
// 不机判——本脚本按文件在位即用，过时产物导致的批量红先自证再重构建）。
package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"time"

	"vitro/scripts/internal/capi"
)

// ── 规则资产 ───────────────────────────────────────────────────────────────

type Rules struct {
	AsOf                string       `json:"as_of"`
	MigratedAlgorithms  []string     `json:"migrated_algorithms"`
	StepBudget          int          `json:"step_budget"`
	Exemptions          []Exemption  `json:"exemptions"`
}

type Exemption struct {
	Template  string `json:"template"`
	Kind      string `json:"kind"` // missing | extra | diff
	Algorithm string `json:"algorithm"`
	Phase     string `json:"phase"`
	Desc      string `json:"desc"`
	Reason    string `json:"reason"`
}

func loadRules(path string) (Rules, map[string]bool, error) {
	var r Rules
	b, err := os.ReadFile(path)
	if err != nil {
		return r, nil, fmt.Errorf("读取规则失败 %s: %w", path, err)
	}
	if err := json.Unmarshal(b, &r); err != nil {
		return r, nil, fmt.Errorf("规则 JSON 解析失败: %w", err)
	}
	if len(r.MigratedAlgorithms) == 0 {
		return r, nil, fmt.Errorf("migrated_algorithms 为空（禁静默全比对）")
	}
	if r.StepBudget <= 0 {
		return r, nil, fmt.Errorf("step_budget 缺失或非正（Rust 口径 4000）")
	}
	set := map[string]bool{}
	for _, a := range r.MigratedAlgorithms {
		set[a] = true
	}
	for _, e := range r.Exemptions {
		switch e.Kind {
		case "missing", "extra", "diff":
		default:
			return r, nil, fmt.Errorf("豁免 kind 非法: %q（须 missing|extra|diff）", e.Kind)
		}
		if e.Template == "" || e.Reason == "" {
			return r, nil, fmt.Errorf("豁免条目缺 template/reason: %+v", e)
		}
	}
	return r, set, nil
}

// ── golden ─────────────────────────────────────────────────────────────────

type FirstOccurrence struct {
	Algorithm   string `json:"algorithm"`
	DisplayName string `json:"display_name"`
	Phase       string `json:"phase"`
	Desc        string `json:"desc"`
	CodeLine    int64  `json:"code_line"`
	Src         string `json:"src"`
}

func loadGolden(path string) (map[string][]FirstOccurrence, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("读取 golden 失败 %s: %w", path, err)
	}
	var g map[string][]FirstOccurrence
	if err := json.Unmarshal(b, &g); err != nil {
		return nil, fmt.Errorf("golden JSON 解析失败: %w", err)
	}
	return g, nil
}

// ── serve 驱动（批量模式——serve_smoke 同款） ──────────────────────────────

func runServeBatch(exe, payload string, timeout time.Duration) (string, int, bool) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, exe)
	cmd.Stdin = strings.NewReader(payload)
	var out, errb bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &errb
	err := cmd.Run()
	timedOut := ctx.Err() == context.DeadlineExceeded
	code := 0
	if ee, ok := err.(*exec.ExitError); ok {
		code = ee.ExitCode()
	} else if err != nil && !timedOut {
		fmt.Fprintf(os.Stderr, "serve 进程错误: %v stderr: %s\n", err, errb.String())
	}
	return out.String(), code, timedOut
}

type respLine struct {
	ID     *int            `json:"id"`
	Result json.RawMessage `json:"result"`
	Error  json.RawMessage `json:"error"`
}

type stepPayload struct {
	CodeLine      int64           `json:"code_line"`
	AlgorithmStep *algoStepOrNull `json:"algorithm_step"`
}

type algoStepOrNull struct {
	AlgorithmName string `json:"algorithm_name"`
	DisplayName   string `json:"display_name"`
	Phase         string `json:"phase"`
	Description   string `json:"description"`
}

// extractViaServe：单模板首现提取（Rust extract_first_occurrences 同口径）。
func extractViaServe(exe, source string, budget int) ([]FirstOccurrence, error) {
	var sb strings.Builder
	id := 0
	write := func(s string) {
		sb.WriteString(s)
		sb.WriteByte('\n')
	}
	srcJSON, err := json.Marshal(map[string]string{"source": source})
	if err != nil {
		return nil, err
	}
	id++
	write(fmt.Sprintf(`{"id": %d, "method": "compile", "params": %s}`, id, string(srcJSON)))
	id++
	write(fmt.Sprintf(`{"id": %d, "method": "run"}`, id))
	id++
	write(fmt.Sprintf(`{"id": %d, "method": "step.begin"}`, id))
	nextIDs := map[int]bool{}
	for i := 0; i < budget; i++ {
		id++
		nextIDs[id] = true
		write(fmt.Sprintf(`{"id": %d, "method": "step.next"}`, id))
	}
	stdout, _, timedOut := runServeBatch(exe, sb.String(), 120*time.Second)
	if timedOut {
		return nil, fmt.Errorf("serve 超时（120s）")
	}
	sc := bufio.NewScanner(strings.NewReader(stdout))
	sc.Buffer(make([]byte, 0, 4*1024*1024), 16*1024*1024)
	seen := map[string]bool{}
	var first []FirstOccurrence
	srcLines := strings.Split(source, "\n")
	for sc.Scan() {
		var r respLine
		line := sc.Bytes()
		if err := json.Unmarshal(line, &r); err != nil {
			return nil, fmt.Errorf("响应行非 JSON: %.200s", string(line))
		}
		if r.Error != nil {
			return nil, fmt.Errorf("serve 错误帧 (id=%d): %.300s", deref(r.ID), string(r.Error))
		}
		if r.ID == nil || !nextIDs[*r.ID] || r.Result == nil {
			continue
		}
		var res struct {
			Payloads []stepPayload `json:"payloads"`
		}
		if err := json.Unmarshal(r.Result, &res); err != nil {
			return nil, fmt.Errorf("step.next result 解析失败: %w", err)
		}
		for _, pl := range res.Payloads {
			if pl.AlgorithmStep == nil {
				continue
			}
			a := pl.AlgorithmStep
			key := a.Phase + "\x00" + a.Description
			if a.Phase == "" || seen[key] {
				continue
			}
			seen[key] = true
			src := ""
			if pl.CodeLine >= 1 && int(pl.CodeLine) <= len(srcLines) {
				src = strings.TrimSpace(srcLines[pl.CodeLine-1])
			}
			first = append(first, FirstOccurrence{
				Algorithm:   a.AlgorithmName,
				DisplayName: a.DisplayName,
				Phase:       a.Phase,
				Desc:        a.Description,
				CodeLine:    pl.CodeLine,
				Src:         src,
			})
		}
	}
	return first, nil
}

func deref(i *int) int {
	if i == nil {
		return -1
	}
	return *i
}

// ── 比对 ───────────────────────────────────────────────────────────────────

func filterMigrated(entries []FirstOccurrence, migrated map[string]bool) []FirstOccurrence {
	var out []FirstOccurrence
	for _, e := range entries {
		if migrated[e.Algorithm] {
			out = append(out, e)
		}
	}
	return out
}

type diffRecord struct {
	Template string
	Kind     string // missing | extra | diff
	Golden   *FirstOccurrence
	Actual   *FirstOccurrence
}

func (d diffRecord) String() string {
	switch d.Kind {
	case "missing":
		e := d.Golden
		return fmt.Sprintf("[%s] missing: %s/%s/%q (line %d)", d.Template, e.Algorithm, e.Phase, e.Desc, e.CodeLine)
	case "extra":
		e := d.Actual
		return fmt.Sprintf("[%s] extra:   %s/%s/%q (line %d)", d.Template, e.Algorithm, e.Phase, e.Desc, e.CodeLine)
	default:
		return fmt.Sprintf("[%s] diff:    golden %+v vs actual %+v", d.Template, *d.Golden, *d.Actual)
	}
}

func exempted(rec diffRecord, exs []Exemption) int {
	for i := range exs {
		e := &exs[i]
		if e.Template != rec.Template || e.Kind != rec.Kind {
			continue
		}
		var entry *FirstOccurrence
		if rec.Kind == "extra" {
			entry = rec.Actual
		} else {
			entry = rec.Golden
		}
		if entry != nil && e.Algorithm == entry.Algorithm && e.Phase == entry.Phase && e.Desc == entry.Desc {
			return i
		}
	}
	return -1
}

func compareTemplate(tpl string, golden, actual []FirstOccurrence) []diffRecord {
	var recs []diffRecord
	i, j := 0, 0
	for i < len(golden) || j < len(actual) {
		switch {
		case j >= len(actual) || (i < len(golden) && j < len(actual) && !sameKey(golden[i], actual[j])):
			recs = append(recs, diffRecord{Template: tpl, Kind: "missing", Golden: &golden[i]})
			i++
		case i >= len(golden):
			recs = append(recs, diffRecord{Template: tpl, Kind: "extra", Actual: &actual[j]})
			j++
		default:
			if golden[i] != actual[j] {
				g, a := golden[i], actual[j]
				recs = append(recs, diffRecord{Template: tpl, Kind: "diff", Golden: &g, Actual: &a})
			}
			i++
			j++
		}
	}
	return recs
}

func sameKey(a, b FirstOccurrence) bool {
	return a.Phase == b.Phase && a.Desc == b.Desc
}

// ── 主流程 ─────────────────────────────────────────────────────────────────

func resolveServeExe() string {
	if override := os.Getenv("VITRO_SERVE_MB"); override != "" {
		return override
	}
	name := "serve"
	if runtime.GOOS == "windows" {
		name = "serve.exe"
	}
	return filepath.Join(capi.ProjectRoot(), "moonbit", "_build", "native", "debug", "build", "cmd", "serve", name)
}

func main() {
	only := flag.String("only", "", "逗号分隔的模板名子集（试水用；空=全量）")
	flag.Parse()

	root := capi.ProjectRoot()
	rulesPath := filepath.Join(root, "scripts", "teaching_annotation_diff", "rules.json")
	goldenPath := filepath.Join(root, "native", "tests", "golden", "algorithm_annotations_v3.json")
	rules, migrated, err := loadRules(rulesPath)
	if err != nil {
		fmt.Println("错误:", err)
		os.Exit(2)
	}
	golden, err := loadGolden(goldenPath)
	if err != nil {
		fmt.Println("错误:", err)
		os.Exit(2)
	}
	exe := resolveServeExe()
	if _, err := os.Stat(exe); err != nil {
		fmt.Printf("错误: 找不到 %s，请先 `cd moonbit && moon build --target native cmd/serve`\n", exe)
		os.Exit(2)
	}

	entries, err := os.ReadDir(filepath.Join(root, "templates"))
	if err != nil {
		fmt.Println("错误: templates 目录不可读:", err)
		os.Exit(2)
	}
	var tplNames []string
	onlySet := map[string]bool{}
	if *only != "" {
		for _, n := range strings.Split(*only, ",") {
			onlySet[strings.TrimSpace(n)] = true
		}
	}
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		if _, err := os.Stat(filepath.Join(root, "templates", e.Name(), "source.c")); err != nil {
			continue
		}
		if len(onlySet) > 0 && !onlySet[e.Name()] {
			continue
		}
		tplNames = append(tplNames, e.Name())
	}
	sort.Strings(tplNames)
	if len(tplNames) == 0 {
		fmt.Println("错误: 模板集为空")
		os.Exit(2)
	}
	fmt.Printf("teaching_annotation_diff: %d 模板 × 已迁移族 %d 算法（budget %d；豁免 %d）\n",
		len(tplNames), len(migrated), rules.StepBudget, len(rules.Exemptions))

	// golden 过滤（族级）：每模板的已迁移族条目
	goldenFiltered := map[string][]FirstOccurrence{}
	goldenNonEmpty := map[string]bool{}
	for tpl, entries := range golden {
		f := filterMigrated(entries, migrated)
		goldenFiltered[tpl] = f
		if len(f) > 0 {
			goldenNonEmpty[tpl] = true
		}
	}

	var fails []string
	actualNonEmpty := map[string]bool{}
	exemptUsed := map[int]bool{}
	for idx, tpl := range tplNames {
		src, err := os.ReadFile(filepath.Join(root, "templates", tpl, "source.c"))
		if err != nil {
			fmt.Println("错误: 读模板失败:", tpl, err)
			os.Exit(2)
		}
		actual, err := extractViaServe(exe, string(src), rules.StepBudget)
		if err != nil {
			fails = append(fails, fmt.Sprintf("[%s] 提取失败: %v", tpl, err))
			continue
		}
		actualF := filterMigrated(actual, migrated)
		if len(actualF) > 0 {
			actualNonEmpty[tpl] = true
		}
		gF := goldenFiltered[tpl]
		for _, rec := range compareTemplate(tpl, gF, actualF) {
			if ei := exempted(rec, rules.Exemptions); ei >= 0 {
				exemptUsed[ei] = true
				continue
			}
			fails = append(fails, rec.String())
		}
		if (idx+1)%10 == 0 || idx == len(tplNames)-1 {
			fmt.Printf("  … %d/%d\n", idx+1, len(tplNames))
		}
	}

	// 双向模板集：golden 有条目（过滤后）但本次未跑的模板不计（--only 子集模式跳过该断言）
	if *only == "" {
		for tpl := range goldenNonEmpty {
			if !actualNonEmpty[tpl] {
				fails = append(fails, fmt.Sprintf("[模板集] golden 有已迁移族条目但 MoonBit 零标注: %s", tpl))
			}
		}
		for tpl := range actualNonEmpty {
			if !goldenNonEmpty[tpl] {
				fails = append(fails, fmt.Sprintf("[模板集] MoonBit 报已迁移族标注但 golden 无该模板条目: %s", tpl))
			}
		}
	}

	// 豁免僵尸检测（--only 全量模式）：未触达的豁免条目 = 僵尸，红
	if *only == "" {
		for i := range rules.Exemptions {
			if !exemptUsed[i] {
				fails = append(fails, fmt.Sprintf("[豁免僵尸] 未触达: %+v", rules.Exemptions[i]))
			}
		}
	}

	if len(fails) > 0 {
		fmt.Printf("\nFAIL: %d 处不一致\n", len(fails))
		for i, f := range fails {
			if i >= 40 {
				fmt.Printf("  … 其余 %d 处略\n", len(fails)-40)
				break
			}
			fmt.Println("  " + f)
		}
		os.Exit(1)
	}
	fmt.Println("OK: 已迁移族首现序列与 golden 逐条一致（双向模板集相等）")
}
