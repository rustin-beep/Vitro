// teaching_phase_vocab：#51 批① phase 受控词表冻结闸（2026-10-17，
// refs #122 F3——前端 F4 批的 CI 接线交付物，本仓补齐落地）。
//
// teaching/steps/infer_*.mbt 的 `build_step(algorithm, "phase", "文案")`
// 第二参 phase 是算法过程语义的受控词表（#51：70+ 自由串无契约——
// 「该契约化的没契约」）。本闸对齐 semantic_label 纪律：词表只增不改、
// 漂移即红。四路判红：
//
//	①未登记扩张：代码出现 rules.json 未登记的 phase；
//	②僵尸条目：rules.json 条目代码零命中；
//	③family 漂移：phase 的使用函数集（infer_* 家族）与登记集双向不等；
//	④非字面量调用：`build_step(` 出现次数 > 字面量命中数（插值/变量
//	 作 phase —— 词表闸的抽取面直接失明）。
//
// 另有抽取面下限（total < min_call_sites 红——正则失能防护：规则改坏时
// 命中塌缩不会静默绿）。`-selftest` 内存注入四路证红（J9），不落盘。
//
//	go run ./scripts/teaching_phase_vocab           # 对账（CI 形态）
//	go run ./scripts/teaching_phase_vocab -selftest # 四路注入证红
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

const (
	stepsDir  = "moonbit/teaching/steps"
	rulesPath = "scripts/teaching_phase_vocab/rules.json"
)

type Rules struct {
	Schema       int     `json:"schema"`
	MinCallSites int     `json:"min_call_sites"`
	Phases       []Entry `json:"phases"`
}

type Entry struct {
	Phase    string   `json:"phase"`
	Families []string `json:"families"`
}

// call：一次 build_step 调用的抽取产物（字面量形态）。
type call struct {
	Phase  string
	Family string
	File   string
}

var (
	callRe = regexp.MustCompile(`(?s)build_step\(\s*[A-Za-z_][\w.]*\s*,\s*"([a-z_0-9]+)"\s*,`)
	fnRe   = regexp.MustCompile(`(?m)^fn (infer_\w+)\(`)
)

// extract：扫 infer_*.mbt。返回字面量命中与 `build_step(` 总出现数
// （两者差 = 非字面量调用数）。family = 调用点所在的最近 infer_* 函数
// （词表漂移按函数粒度归因——函数即判据族）。
func extract(dir string) ([]call, int, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, 0, fmt.Errorf("读 %s: %w", dir, err)
	}
	var calls []call
	occurrences := 0
	for _, e := range entries {
		name := e.Name()
		if !strings.HasPrefix(name, "infer_") || !strings.HasSuffix(name, ".mbt") {
			continue
		}
		src, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			return nil, 0, fmt.Errorf("读 %s: %w", name, err)
		}
		occurrences += strings.Count(string(src), "build_step(")
		fns := fnRe.FindAllStringSubmatchIndex(string(src), -1)
		for _, m := range callRe.FindAllStringSubmatchIndex(string(src), -1) {
			phase := string(src)[m[2]:m[3]]
			fam := ""
			for _, f := range fns {
				if f[0] < m[0] {
					fam = string(src)[f[2]:f[3]]
				} else {
					break
				}
			}
			calls = append(calls, call{Phase: phase, Family: fam, File: name})
		}
	}
	return calls, occurrences, nil
}

// checkSet：四路 + 下限。输入抽取产物与登记表，返回红清单（空 = 绿）。
func checkSet(rules Rules, calls []call, occurrences int) []string {
	var errs []string
	// 抽取面下限（正则失能防护）
	if len(calls) < rules.MinCallSites {
		errs = append(errs, fmt.Sprintf(
			"抽取面塌缩：字面量命中 %d < min_call_sites %d（正则失能或大批删除——人工核对后更新 rules.json）",
			len(calls), rules.MinCallSites))
	}
	// ④非字面量调用
	if occurrences > len(calls) {
		errs = append(errs, fmt.Sprintf(
			"非字面量 phase 调用 %d 处（build_step( 出现 %d vs 字面量命中 %d）——phase 须为字符串字面量（词表闸抽取面要求）",
			occurrences-len(calls), occurrences, len(calls)))
	}
	// 代码侧 phase → families
	codeMap := map[string]map[string]bool{}
	for _, c := range calls {
		if codeMap[c.Phase] == nil {
			codeMap[c.Phase] = map[string]bool{}
		}
		codeMap[c.Phase][c.Family] = true
	}
	// ①未登记扩张
	for ph := range codeMap {
		if !hasEntry(rules, ph) {
			errs = append(errs, fmt.Sprintf("未登记扩张：phase %q（infer_* 新串须先入 rules.json 受控词表——只增不改纪律）", ph))
		}
	}
	// ②僵尸条目 + ③family 漂移
	for _, e := range rules.Phases {
		got, ok := codeMap[e.Phase]
		if !ok {
			errs = append(errs, fmt.Sprintf("僵尸条目：rules.json phase %q 代码零命中（删或回填使用点）", e.Phase))
			continue
		}
		want := map[string]bool{}
		for _, f := range e.Families {
			want[f] = true
		}
		var onlyCode, onlyRules []string
		for f := range got {
			if !want[f] {
				onlyCode = append(onlyCode, f)
			}
		}
		for f := range want {
			if !got[f] {
				onlyRules = append(onlyRules, f)
			}
		}
		if len(onlyCode) > 0 || len(onlyRules) > 0 {
			sort.Strings(onlyCode)
			sort.Strings(onlyRules)
			errs = append(errs, fmt.Sprintf(
				"family 漂移：phase %q 代码新增 %v / 登记-renamed或删除 %v（连坐 rules.json families）",
				e.Phase, onlyCode, onlyRules))
		}
	}
	return errs
}

func hasEntry(rules Rules, phase string) bool {
	for _, e := range rules.Phases {
		if e.Phase == phase {
			return true
		}
	}
	return false
}

func main() {
	selftest := flag.Bool("selftest", false, "内存注入四路证红（J9，不落盘）")
	flag.Parse()

	var rules Rules
	rb, err := os.ReadFile(rulesPath)
	if err != nil {
		fatal("读 %s: %v", rulesPath, err)
	}
	if err := json.Unmarshal(rb, &rules); err != nil {
		fatal("解析 %s: %v", rulesPath, err)
	}
	if len(rules.Phases) == 0 || rules.MinCallSites <= 0 {
		fatal("rules.json 空词表或 min_call_sites 非法——不得绿")
	}

	calls, occurrences, err := extract(stepsDir)
	if err != nil {
		fatal("提取失败: %v", err)
	}

	if *selftest {
		selftestAll(rules, calls, occurrences)
		return
	}

	if errs := checkSet(rules, calls, occurrences); len(errs) > 0 {
		fmt.Fprintln(os.Stderr, "teaching_phase_vocab 红（phase 受控词表对账不符）：")
		for _, e := range errs {
			fmt.Fprintln(os.Stderr, "  -", e)
		}
		os.Exit(1)
	}
	fmt.Printf("teaching_phase_vocab 绿（phase %d 条 ↔ infer_* 调用 %d 处字面量全等，四路判红在岗）\n",
		len(rules.Phases), len(calls))
}

// selftestAll：四路内存注入证红（真数据基线上各注入一路）。
func selftestAll(rules Rules, calls []call, occurrences int) {
	fail := 0
	// 路 1：未登记扩张
	spoiled := append([]call(nil), calls...)
	spoiled = append(spoiled, call{Phase: "zz_unregistered", Family: "infer_bubble_sort", File: "zz.mbt"})
	if errs := checkSet(rules, spoiled, occurrences+1); !anyStartsWith(errs, "未登记扩张") {
		fmt.Println("selftest 路 1 FAIL：未登记扩张未红")
		fail++
	} else {
		fmt.Println("selftest 路 1 OK（未登记扩张红）")
	}
	// 路 2：僵尸条目
	r2 := deepCopyRules(rules)
	r2.Phases = append(r2.Phases, Entry{Phase: "zz_zombie", Families: []string{"infer_bubble_sort"}})
	if errs := checkSet(r2, calls, occurrences); !anyStartsWith(errs, "僵尸条目") {
		fmt.Println("selftest 路 2 FAIL：僵尸条目未红")
		fail++
	} else {
		fmt.Println("selftest 路 2 OK（僵尸条目红）")
	}
	// 路 3：family 漂移（把一个登记族的 family 集改掉一格）
	r3 := deepCopyRules(rules)
	for i := range r3.Phases {
		if len(r3.Phases[i].Families) > 0 {
			r3.Phases[i].Families[0] = "infer_zz_renamed"
			break
		}
	}
	if errs := checkSet(r3, calls, occurrences); !anyStartsWith(errs, "family 漂移") {
		fmt.Println("selftest 路 3 FAIL：family 漂移未红")
		fail++
	} else {
		fmt.Println("selftest 路 3 OK（family 漂移红）")
	}
	// 路 4：非字面量调用（出现数 > 命中数）
	if errs := checkSet(rules, calls, len(calls)+3); !anyStartsWith(errs, "非字面量") {
		fmt.Println("selftest 路 4 FAIL：非字面量调用未红")
		fail++
	} else {
		fmt.Println("selftest 路 4 OK（非字面量调用红）")
	}
	if fail > 0 {
		os.Exit(2)
	}
	fmt.Println("teaching_phase_vocab selftest 全过（四路注入均红）")
}

func anyStartsWith(errs []string, prefix string) bool {
	for _, e := range errs {
		if strings.HasPrefix(e, prefix) {
			return true
		}
	}
	return false
}

func deepCopyRules(r Rules) Rules {
	out := Rules{Schema: r.Schema, MinCallSites: r.MinCallSites}
	out.Phases = make([]Entry, len(r.Phases))
	for i, e := range r.Phases {
		out.Phases[i] = Entry{Phase: e.Phase, Families: append([]string(nil), e.Families...)}
	}
	return out
}

func fatal(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "teaching_phase_vocab: "+format+"\n", args...)
	os.Exit(1)
}
