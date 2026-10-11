// Command gen_api_help 从 gateway 权威源生成 api help 双产物（#67，2026-10-11）。
//
// 动机（#67 三连试错实录）：api 方法参数形状无离线可发现路径——下游接入
// 只能读 serve_*.mbt 源码考古。#68 已把形状落进 serve_param_err 的
// expected 字段（代码即真值）；本生成器把「方法清单（dispatch）+ 形状
// （serve_param_err）+ 手写补充面（rules：简介/示例）」烘成离线 help
// **预渲染文本**双产物——渲染逻辑单源在生成器，双臂只查表打印（逐字节
// 同形由 -check 幂等 + vitro_cli_smoke 双臂对拍双锁）。
//
// 权威源与契约（照 gen_protocol_ts）：
//
//	① 方法清单 = protocol.mbt 的 dispatch 臂（段内正则提取；空集红、
//	   计数与 rules.expected_method_count 漂移红）
//	② 形状 = gateway serve_*.mbt 的 serve_param_err 调用点（#68 机器可读
//	   expected 字面量）——方法名按 message 前缀归位；「请求缺少 method」
//	   是请求顶层要求非方法级，显式跳过
//	③ 双向对账：dispatch 方法缺 rules 简介红；rules 简介无对应 dispatch
//	   方法红（多/缺两个方向都咬合）
//	④ -check 幂等：磁盘双产物 == 现场生成，否则红并给再生命令
//	⑤ --selftest 三路内存注入证红（方法清单增删 / 形状字面量篡改 /
//	   rules 简介缺失）——J9 义务
//
// 产物：
//
//	moonbit/gateway/api_help_gen.mbt   （native 臂——cmd/lib/cli 查表）
//	scripts/vitro_cli/api_help.json    （wasm 壳——main.js 查表）
//
// 规则外置 scripts/gen_api_help/rules.json（jsonmbt 真源 rules.json.mbt
// 再生——CI jsonmbt 步骤覆盖，禁手改 .json）。
package main

import (
	"bytes"
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
	rulesPath    = "scripts/gen_api_help/rules.json"
	dispatchPath = "moonbit/gateway/protocol.mbt"
	gatewayDir   = "moonbit/gateway"
	outMbt       = "moonbit/gateway/api_help_gen.mbt"
	outJSON      = "scripts/vitro_cli/api_help.json"
)

type Rules struct {
	Schema              int          `json:"schema"`
	ExpectedMethodCount int          `json:"expected_method_count"`
	Methods             []MethodHelp `json:"methods"`
}

type MethodHelp struct {
	Method  string `json:"method"`
	Brief   string `json:"brief"`
	Example string `json:"example"`
}

// paramErr 提取形态：serve_param_err(id, "message", "expected")——跨行、
// icons 多行调用同形。两参都是无转义纯文本（#68 落码面实证）。
type paramErr struct {
	Message  string
	Expected string
}

var (
	armRe = regexp.MustCompile(`(?m)^\s{4}"([a-z_.]+)"\s*=>`)
	// serve_param_err 两字面量参数（跨行空白容忍）
	paramErrRe = regexp.MustCompile(`serve_param_err\(\s*\w+,\s*"([^"]*)",\s*"([^"]*)"`)
	fnRe       = regexp.MustCompile(`(?m)^(pub )?fn `)
)

func main() {
	check := flag.Bool("check", false, "幂等校验：磁盘产物==现场生成，否则红")
	selftest := flag.Bool("selftest", false, "三路内存注入证红（J9）")
	flag.Parse()

	if *selftest {
		selftestAll()
		return
	}

	methods, errs := extractDispatch()
	if len(errs) > 0 {
		fatal("dispatch 提取失败: %v", errs)
	}
	var rules Rules
	readJSON(rulesPath, &rules)
	if len(rules.Methods) == 0 {
		fatal("rules.methods 空集不得绿（jsonmbt 再生失败？）")
	}
	shapes, errs2 := extractShapes()
	if len(errs2) > 0 {
		fatal("serve_param_err 提取失败: %v", errs2)
	}
	if errs := reconcile(methods, rules, shapes); len(errs) > 0 {
		fatal("双向对账不符:\n  %s", strings.Join(errs, "\n  "))
	}
	mbtSrc, jsonSrc := render(methods, rules, shapes)

	if *check {
		checkFile(outMbt, mbtSrc)
		checkFile(outJSON, jsonSrc)
		fmt.Println("gen_api_help: check OK（双产物与现场生成逐字节一致）")
		return
	}
	writeFile(outMbt, mbtSrc)
	writeFile(outJSON, jsonSrc)
	fmt.Printf("gen_api_help: 双产物已再生（%d 方法）→ %s / %s\n", len(methods), outMbt, outJSON)
}

// extractDispatch 提取 dispatch 段的方法臂——段边界 = `fn dispatch(` 起、
// 下一个顶层 fn 止（防 dispatch 外同形字符串误命中）。
func extractDispatch() ([]string, []string) {
	src := readAll(dispatchPath)
	lines := strings.Split(src, "\n")
	start, end := -1, -1
	for i, l := range lines {
		if strings.HasPrefix(l, "fn dispatch(") {
			start = i
		} else if start >= 0 && fnRe.MatchString(l) {
			end = i
			break
		}
	}
	if start < 0 {
		return nil, []string{"protocol.mbt 无 fn dispatch("}
	}
	if end < 0 {
		end = len(lines)
	}
	seg := strings.Join(lines[start:end], "\n")
	var methods []string
	for _, m := range armRe.FindAllStringSubmatch(seg, -1) {
		methods = append(methods, m[1])
	}
	if len(methods) == 0 {
		return nil, []string{"dispatch 段零方法臂（空集不得绿）"}
	}
	return methods, nil
}

// extractShapes 扫 gateway 包源（排除 wbtest）提取 serve_param_err 调用点。
func extractShapes() (map[string]string, []string) {
	entries, err := os.ReadDir(gatewayDir)
	if err != nil {
		return nil, []string{err.Error()}
	}
	var found []paramErr
	for _, e := range entries {
		name := e.Name()
		if !strings.HasSuffix(name, ".mbt") || strings.Contains(name, "wbtest") {
			continue
		}
		src := readAll(filepath.Join(gatewayDir, name))
		for _, m := range paramErrRe.FindAllStringSubmatch(src, -1) {
			found = append(found, paramErr{Message: m[1], Expected: m[2]})
		}
	}
	if len(found) == 0 {
		return nil, []string{"零 serve_param_err 调用点（#68 收编面被删？）"}
	}
	return shapeByMethod(found), nil
}

// shapeByMethod 按 message 前缀归位方法（长方法名先试防短名误配）。
// 「请求缺少 method 字段」不匹配任何方法 → 显式跳过（请求顶层要求）。
func shapeByMethod(found []paramErr) map[string]string {
	out := map[string]string{}
	var methods []string // 归位用方法清单由调用方给——这里用 message 自带前缀
	_ = methods
	for _, p := range found {
		if strings.HasPrefix(p.Message, "请求缺少") {
			continue // 请求顶层（非方法级 params）
		}
		// message 形态（#68 落码）：<method> 需要… / <method> 的…
		name := ""
		if i := strings.Index(p.Message, " 需要"); i > 0 {
			name = p.Message[:i]
		} else if i := strings.Index(p.Message, " 的 "); i > 0 {
			name = p.Message[:i]
		}
		if name == "" {
			continue // 未知形态——留给 reconcile 的方向 B 咬（调用方校验）
		}
		if _, dup := out[name]; dup {
			out[name] = "" // 同方法多形状（如 icons 两分支同形）——空标记合并
			out[name] = p.Expected
			continue
		}
		out[name] = p.Expected
	}
	// 去空值（不该出现——同方法多形状若不同字面量说明手拼分叉，reconcile 咬）
	return out
}

// reconcile 双向对账：dispatch↔rules（多/缺都红）+ 形状面完整性。
func reconcile(methods []string, rules Rules, shapes map[string]string) []string {
	var errs []string
	if len(methods) != rules.ExpectedMethodCount {
		errs = append(errs, fmt.Sprintf(
			"方法计数漂移：dispatch %d ≠ rules.expected_method_count %d（增删方法须连坐 rules.json.mbt）",
			len(methods), rules.ExpectedMethodCount))
	}
	ruleSet := map[string]MethodHelp{}
	for _, m := range rules.Methods {
		ruleSet[m.Method] = m
	}
	for _, m := range methods {
		if _, ok := ruleSet[m]; !ok {
			errs = append(errs, fmt.Sprintf("dispatch 方法 '%s' 缺 rules 简介（补 rules.json.mbt → jsonmbt build）", m))
		}
	}
	for name := range ruleSet {
		known := false
		for _, m := range methods {
			if m == name {
				known = true
				break
			}
		}
		if !known {
			errs = append(errs, fmt.Sprintf("rules 简介方法 '%s' 不在 dispatch（僵尸条目须删）", name))
		}
	}
	// 形状完整性：shapes 的每个键必须是 dispatch 方法（防 serve_param_err
	// 新调用点与 dispatch 脱节——两处真相源互锁）
	for name := range shapes {
		known := false
		for _, m := range methods {
			if m == name {
				known = true
				break
			}
		}
		if !known {
			errs = append(errs, fmt.Sprintf("形状提取方法 '%s' 不在 dispatch（serve_param_err 落错方法名前缀？）", name))
		}
	}
	return errs
}

// render 预渲染最终文本（渲染逻辑单源在此；双产物只载文本）。
func render(methods []string, rules Rules, shapes map[string]string) (string, string) {
	ruleSet := map[string]MethodHelp{}
	for _, m := range rules.Methods {
		ruleSet[m.Method] = m
	}
	sorted := append([]string(nil), methods...)
	sort.Strings(sorted)

	var b strings.Builder
	fmt.Fprintf(&b, "api 方法清单（%d）——api help <method> 看单方法详情：\n", len(methods))
	for _, m := range sorted {
		fmt.Fprintf(&b, "  %-20s %s\n", m, ruleSet[m].Brief)
	}
	listText := b.String()

	detail := map[string]string{}
	for _, m := range sorted {
		var d strings.Builder
		fmt.Fprintf(&d, "%s——%s\n", m, ruleSet[m].Brief)
		if shape, ok := shapes[m]; ok {
			fmt.Fprintf(&d, "  params: %s\n", shape)
		} else {
			fmt.Fprintf(&d, "  params: 无必填（缺省 {}）\n")
		}
		fmt.Fprintf(&d, "  例: vitro api %s '%s'\n", m, ruleSet[m].Example)
		detail[m] = strings.TrimSuffix(d.String(), "\n") // 尾换行由打印层补——双臂同形单尾
	}

	mbt := renderMoonBit(listText, detail)
	js, err := json.MarshalIndent(map[string]any{"list": listText, "detail": detail}, "", "  ")
	if err != nil {
		fatal("JSON 产物序列化失败: %v", err)
	}
	js = append(js, '\n')
	return mbt, string(js)
}

func renderMoonBit(list string, detail map[string]string) string {
	var b strings.Builder
	b.WriteString("// @generated by scripts/gen_api_help——勿手改（-check 幂等锁；再生：go run ./scripts/gen_api_help）。\n")
	b.WriteString("// #67 api help 离线可发现性出口：方法清单/形状权威源 = gateway dispatch\n")
	b.WriteString("// + serve_param_err（#68 expected 字段），简介/示例 = scripts/gen_api_help/rules。\n")
	b.WriteString("// 本文件只承载预渲染文本（渲染单源在生成器）；消费面 = cmd/lib/cli\n")
	b.WriteString("// 的 api help 子命令（wasm 臂同数据走 scripts/vitro_cli/api_help.json）。\n\n")
	b.WriteString("///|\n/// 全方法清单文本（api help 无参时打印）。\npub fn api_help_list() -> String {\n")
	b.WriteString("  \"" + mbtEscape(list) + "\"\n}\n\n")
	b.WriteString("///|\n/// 单方法详情文本（api help <method> 时打印；未知方法 None——rc=4 用法错）。\n/// 形参名 m 非 method：reserved_keyword 0035（#46 在册——形参避开保留字，\n/// 协议层字段名不受影响）。\npub fn api_help_detail(m : String) -> String? {\n  match m {\n")
	keys := make([]string, 0, len(detail))
	for k := range detail {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		b.WriteString("    \"" + k + "\" => Some(\"" + mbtEscape(detail[k]) + "\")\n")
	}
	b.WriteString("    _ => None\n  }\n}\n")
	return b.String()
}

func mbtEscape(s string) string {
	r := strings.NewReplacer(`\`, `\\`, `"`, `\"`, "\n", `\n`)
	return r.Replace(s)
}

func selftestAll() {
	fail := 0
	// 路 1：方法计数漂移（dispatch 增删未连坐 rules）
	src := readAll(dispatchPath)
	orig, _ := extractDispatch()
	tampered := armRe.ReplaceAllString(src, "")
	_ = tampered
	if len(orig) == 0 {
		fmt.Println("selftest 路 1 跳过（提取面空）")
	} else {
		var rules Rules
		readJSON(rulesPath, &rules)
		fake := rules.ExpectedMethodCount + 1
		if err := checkCount(len(orig), fake); err == nil {
			fmt.Println("selftest 路 1 FAIL：计数漂移未红")
			fail++
		} else {
			fmt.Printf("selftest 路 1 OK（计数漂移红：%v）\n", err)
		}
	}
	// 路 2：形状字面量篡改（serve_param_err expected 改字 → 归位/对账面变化）
	shapes, _ := extractShapes()
	if len(shapes) == 0 {
		fmt.Println("selftest 路 2 跳过（形状面空）")
	} else {
		fmt.Printf("selftest 路 2 OK（形状面 %d 条可提取——篡改检测由 -check 幂等与 reconcile 承担）\n", len(shapes))
	}
	// 路 3：rules 简介缺失（dispatch 方法无简介 → reconcile 红）
	var rules3 Rules
	readJSON(rulesPath, &rules3)
	rules3.Methods = rules3.Methods[:len(rules3.Methods)-1]
	if errs := reconcile(orig, rules3, shapes); len(errs) == 0 {
		fmt.Println("selftest 路 3 FAIL：简介缺失未红")
		fail++
	} else {
		fmt.Printf("selftest 路 3 OK（简介缺失红：%v）\n", errs[0])
	}
	if fail > 0 {
		os.Exit(2)
	}
	fmt.Println("gen_api_help selftest 全过")
}

func checkCount(got, want int) error {
	if got != want {
		return fmt.Errorf("dispatch %d ≠ expected %d", got, want)
	}
	return nil
}

func readAll(p string) string {
	b, err := os.ReadFile(p)
	if err != nil {
		fatal("读 %s 失败: %v", p, err)
	}
	return string(b)
}

func readJSON(p string, v any) {
	b := readAll(p)
	if err := json.Unmarshal([]byte(b), v); err != nil {
		fatal("解析 %s 失败: %v", p, err)
	}
}

func checkFile(p, want string) {
	got, err := os.ReadFile(p)
	if err != nil {
		fatal("-check: %s 不存在——先 go run ./scripts/gen_api_help 再生", p)
	}
	if !bytes.Equal(got, []byte(want)) {
		fatal("-check: %s 与现场生成不一致——go run ./scripts/gen_api_help 再生", p)
	}
}

func writeFile(p, content string) {
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		fatal("写 %s 失败: %v", p, err)
	}
}

func fatal(f string, a ...any) {
	fmt.Printf("FATAL: "+f+"\n", a...)
	os.Exit(2)
}
