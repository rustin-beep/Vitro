// Command gen_protocol_ts 从权威 Rust 源生成 `@vitro/protocol` 的 TS 类型定义
// 与字段集元数据（架构审阅 v2 A 组 #9 / §7.5）。
//
// 动机（E-08 的"结构性一半"）：L9 外置把教学正确性移到了防线之外。TS 侧的
// **字段级错误**（字段名写错 / 字段缺失 / 版本不匹配）本可在编译期即红——前提是
// TS 侧有**从权威源生成**的类型，而不是手抄。手抄就是又一处分叉温床。
//
// 权威源选谁（关键设计决定）：
//   `native/src/unified/{types,root_cause}.rs` + `native/src/session.rs` 的 Rust
//   结构体——它们是**编译期受字段冻结测试守护**的真实源
//   （`native/tests/step_payload_schema_v0_1_test.rs`）。
//   `docs/spec/STEP_PAYLOAD_SCHEMA_V0_1.md` 是**表述层**（人工维护的 markdown 表格）。
//   故取「**从实现生成 + 与文档双向对账**」：任一方向不同步都判红——这同时把
//   「文档与实现是否一致」这个此前无人守的问题变成了机器判据。
//
// 合规（E-06 / E-07）：生成器保持 Go，属**构建期多语言工具**，不进产物。
//
// 判据：
//   ① `-check` 幂等：磁盘产物 == 现场生成（否则红，提示重跑生成）；
//   ② 字段集双向对账：每个类型的 Rust 字段集 == schema 文档表格的字段集
//      （文档漏列字段 / 实现新增字段未入文档，两向都红）；
//   ③ 空集不得绿：解析出 0 字段、0 类型一律 fail loud。
// 规则外置 rules.json；`--selftest` 三路内存注入证红。
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

const rulesPath = "scripts/gen_protocol_ts/rules.json"

type typeSpec struct {
	Name string `json:"name"`
	Kind string `json:"kind"`
}

type rulesDoc struct {
	Schema       int        `json:"schema"`
	SchemaVer    string     `json:"schema_version"`
	FrozenAnchor string     `json:"frozen_anchor"`
	SchemaDoc    string     `json:"schema_doc"`
	TypeSources  []string   `json:"type_sources"`
	Types        []typeSpec `json:"types"`
	OutTS        string     `json:"out_ts"`
	OutMeta      string     `json:"out_meta"`
}

func fatal(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "FATAL: "+format+"\n", args...)
	os.Exit(2)
}

func repoRoot() string {
	wd, err := os.Getwd()
	if err != nil {
		fatal("无法取工作目录: %v", err)
	}
	dir := wd
	for i := 0; i < 6; i++ {
		ok := true
		for _, m := range []string{"native", "scripts"} {
			if fi, err := os.Stat(filepath.Join(dir, m)); err != nil || !fi.IsDir() {
				ok = false
				break
			}
		}
		if ok {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	fatal("请在仓库内运行：找不到包含 native/ 与 scripts/ 的项目根")
	return ""
}

func mustRead(root, rel string) string {
	b, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(rel)))
	if err != nil {
		fatal("读 %s 失败: %v", rel, err)
	}
	return string(b)
}

// ---------------------------------------------------------------- Rust 解析

type rustField struct {
	Name string
	Ty   string
}

type rustType struct {
	Name     string
	Kind     string // "struct" | "enum"
	Fields   []rustField
	Variants []string
	Source   string
}

var (
	reStructHead = regexp.MustCompile(`(?m)^\s*pub\s+struct\s+([A-Za-z_]\w*)`)
	reEnumHead   = regexp.MustCompile(`(?m)^\s*pub\s+enum\s+([A-Za-z_]\w*)`)
	// 行尾**允许注释**——否则 `pub access_type: String, // "Read" | "Write"`
	// 这类带尾注的字段会被整行漏掉（实测踩过：AccessedVar 少一个字段，
	// 闸门误报为「文档多列字段」——判据的假红／假绿都可能由此产生）。
	reField   = regexp.MustCompile(`(?m)^\s*pub\s+([A-Za-z_]\w*)\s*:\s*(.+?),\s*(?://[^\n]*)?$`)
	reVariant = regexp.MustCompile(`(?m)^\s*([A-Za-z_]\w*)\s*,?\s*$`)
)

// blockBody：从 head（形如 `pub struct X`）之后的首个 `{` 起，返回配对 `}` 前的体。
func blockBody(src string, headEnd int) (string, bool) {
	i := strings.Index(src[headEnd:], "{")
	if i < 0 {
		return "", false
	}
	start := headEnd + i
	depth := 0
	for j := start; j < len(src); j++ {
		switch src[j] {
		case '{':
			depth++
		case '}':
			depth--
			if depth == 0 {
				return src[start+1 : j], true
			}
		}
	}
	return "", false
}

func parseRustTypes(root string, files []string, want map[string]typeSpec) map[string]*rustType {
	out := map[string]*rustType{}
	for _, rel := range files {
		src := mustRead(root, rel)
		for name := range want {
			if _, done := out[name]; done {
				continue
			}
			var head *regexp.Regexp
			kind := want[name].Kind
			if kind == "struct" {
				head = reStructHead
			} else {
				head = reEnumHead
			}
			loc := head.FindStringSubmatchIndex(src)
			// 找的是**名为 name 的那个**定义，不是首个
			for _, m := range head.FindAllStringSubmatchIndex(src, -1) {
				if src[m[2]:m[3]] == name {
					loc = m
					break
				} else {
					loc = nil
				}
			}
			if loc == nil {
				continue
			}
			body, ok := blockBody(src, loc[1])
			if !ok {
				fatal("%s 的 %s 体定位失败（花括号不配对？）", rel, name)
			}
			rt := &rustType{Name: name, Kind: kind, Source: rel}
			if kind == "struct" {
				for _, f := range reField.FindAllStringSubmatch(body, -1) {
					rt.Fields = append(rt.Fields, rustField{Name: f[1], Ty: strings.TrimSpace(f[2])})
				}
				if len(rt.Fields) == 0 {
					fatal("%s 的 struct %s 解析出 0 字段——拒绝空转", rel, name)
				}
			} else {
				for _, line := range strings.Split(body, "\n") {
					t := strings.TrimSpace(line)
					if t == "" || strings.HasPrefix(t, "//") || strings.HasPrefix(t, "#") {
						continue
					}
					if m := reVariant.FindStringSubmatch(t); m != nil {
						rt.Variants = append(rt.Variants, m[1])
					}
				}
				if len(rt.Variants) == 0 {
					fatal("%s 的 enum %s 解析出 0 变体——拒绝空转", rel, name)
				}
			}
			out[name] = rt
		}
	}
	for name := range want {
		if _, ok := out[name]; !ok {
			fatal("类型 %s 在 type_sources（%s）里找不到 pub 定义", name, strings.Join(files, ", "))
		}
	}
	return out
}

// ---------------------------------------------------------------- 文档解析

// parseDocFields：schema 文档里「### N.M `TypeName`」/「## N. ... `TypeName`」
// 标题后**首个 markdown 表格**的第一列字段名集合。
func parseDocFields(doc string, known map[string]bool) map[string]map[string]bool {
	out := map[string]map[string]bool{}
	lines := strings.Split(doc, "\n")
	cur := ""
	inTable := false
	for _, l := range lines {
		t := strings.TrimSpace(l)
		if strings.HasPrefix(t, "#") {
			// 标题里出现的已知类型名即绑定目标（取首个匹配）
			cur = ""
			for _, m := range regexp.MustCompile("`([A-Za-z_][A-Za-z0-9_]*)`").FindAllStringSubmatch(t, -1) {
				if known[m[1]] {
					cur = m[1]
					break
				}
			}
			inTable = false
			continue
		}
		if cur == "" {
			continue
		}
		if !strings.HasPrefix(t, "|") {
			// 表格结束（首个表格之后的内容忽略——同小节后续表格不混入）
			if inTable {
				cur = ""
				inTable = false
			}
			continue
		}
		cells := strings.Split(t, "|")
		if len(cells) < 2 {
			continue
		}
		first := cells[1]
		if strings.Contains(first, "---") { // 分隔行
			inTable = true
			continue
		}
		if !inTable {
			continue
		}
		if out[cur] == nil {
			out[cur] = map[string]bool{}
		}
		// 第一列形如 `name` 或 `extra0` / `extra1` / `extra2`
		for _, m := range regexp.MustCompile("`([A-Za-z_][A-Za-z0-9_]*)`").FindAllStringSubmatch(first, -1) {
			out[cur][m[1]] = true
		}
	}
	return out
}

// ---------------------------------------------------------------- TS 生成

func tsType(rt string) string {
	s := strings.TrimSpace(rt)
	switch s {
	case "i32", "i64", "u32", "u64", "f32", "f64", "usize", "isize", "i8", "u8", "i16", "u16":
		return "number"
	case "String", "&str":
		return "string"
	case "bool":
		return "boolean"
	}
	if strings.HasPrefix(s, "Vec<") && strings.HasSuffix(s, ">") {
		inner := tsType(s[4 : len(s)-1])
		if strings.Contains(inner, " | ") {
			return "(" + inner + ")[]"
		}
		return inner + "[]"
	}
	if strings.HasPrefix(s, "Option<") && strings.HasSuffix(s, ">") {
		return tsType(s[7:len(s)-1]) + " | null"
	}
	if i := strings.LastIndex(s, "::"); i >= 0 {
		s = s[i+2:]
	}
	return s
}

func genTS(rd rulesDoc, types map[string]*rustType) string {
	var b strings.Builder
	b.WriteString("// 本文件由 `scripts/gen_protocol_ts` 生成，**请勿手改**。\n")
	b.WriteString("//\n")
	b.WriteString("// 权威源（Rust 结构体，受 native/tests/step_payload_schema_v0_1_test.rs 字段冻结测试守护）：\n")
	for _, s := range rd.TypeSources {
		b.WriteString("//   - " + s + "\n")
	}
	b.WriteString("// schema：" + rd.SchemaDoc + "（v" + rd.SchemaVer + "，冻结锚 `" + rd.FrozenAnchor + "`）\n")
	b.WriteString("// 再生成：`go run ./scripts/gen_protocol_ts`；幂等校验：`-check`\n")
	b.WriteString("\n")
	b.WriteString("/// StepPayload schema 版本（与 docs/spec 冻结版本一致）。\n")
	b.WriteString("export const SCHEMA_VERSION = \"" + rd.SchemaVer + "\";\n")

	// 先枚举，再 struct（消费顺序友好）
	var enums, structs []string
	for _, t := range rd.Types {
		if t.Kind == "enum" {
			enums = append(enums, t.Name)
		} else {
			structs = append(structs, t.Name)
		}
	}
	sort.Strings(enums)
	// struct 按 rules 里的声明顺序（StepPayload 在最后，先出子结构）
	for _, n := range structs {
		rt := types[n]
		b.WriteString("\n/// `" + n + "`（源：" + rt.Source + "）\n")
		b.WriteString("export interface " + n + " {\n")
		for _, f := range rt.Fields {
			b.WriteString("  " + f.Name + ": " + tsType(f.Ty) + ";\n")
		}
		b.WriteString("}\n")
	}
	for _, n := range enums {
		rt := types[n]
		b.WriteString("\n/// `" + n + "`（源：" + rt.Source + "）——字符串字面量联合（与 Rust serde 序列化一致）\n")
		b.WriteString("export const " + n + " = {\n")
		for _, v := range rt.Variants {
			b.WriteString("  " + v + ": \"" + v + "\",\n")
		}
		b.WriteString("} as const;\n")
		b.WriteString("export type " + n + " = (typeof " + n + ")[keyof typeof " + n + "];\n")
	}
	return b.String()
}

// genMeta：字段集元数据（供**无 tsc 环境**下的运行时校验 / 消费者自查用）。
func genMeta(rd rulesDoc, types map[string]*rustType) string {
	var b strings.Builder
	b.WriteString("// 本文件由 `scripts/gen_protocol_ts` 生成，**请勿手改**。\n")
	b.WriteString("// 字段集元数据：无 TypeScript 工具链的消费方（或运行时自检）可据此校验字段名。\n\n")
	b.WriteString("export const SCHEMA_VERSION = \"" + rd.SchemaVer + "\";\n\n")
	b.WriteString("export const ENUMS = {\n")
	for _, t := range rd.Types {
		if t.Kind != "enum" {
			continue
		}
		vs := types[t.Name].Variants
		q := make([]string, len(vs))
		for i, v := range vs {
			q[i] = "\"" + v + "\""
		}
		b.WriteString("  " + t.Name + ": [" + strings.Join(q, ", ") + "],\n")
	}
	b.WriteString("};\n\n")
	b.WriteString("export const FIELDS = {\n")
	for _, t := range rd.Types {
		if t.Kind != "struct" {
			continue
		}
		fs := types[t.Name].Fields
		names := make([]string, len(fs))
		for i, f := range fs {
			names[i] = "\"" + f.Name + "\""
		}
		b.WriteString("  " + t.Name + ": [" + strings.Join(names, ", ") + "],\n")
	}
	b.WriteString("};\n")
	return b.String()
}

// ---------------------------------------------------------------- 主流程

func loadAll(root string, rd rulesDoc) (map[string]*rustType, map[string]map[string]bool) {
	want := map[string]typeSpec{}
	for _, t := range rd.Types {
		want[t.Name] = t
	}
	types := parseRustTypes(root, rd.TypeSources, want)
	known := map[string]bool{}
	for n := range want {
		known[n] = true
	}
	doc := mustRead(root, rd.SchemaDoc)
	if !strings.Contains(doc, "v"+rd.SchemaVer) {
		fatal("%s 里找不到版本串 v%s——schema 版本与规则不符", rd.SchemaDoc, rd.SchemaVer)
	}
	docFields := parseDocFields(doc, known)
	if len(docFields) == 0 {
		fatal("%s 解析出 0 个类型字段表——文档形态变化或解析失配，拒绝判绿", rd.SchemaDoc)
	}
	return types, docFields
}

// fieldSetMismatch：Rust 字段集 ↔ 文档字段集 双向对账。
func fieldSetMismatch(rd rulesDoc, types map[string]*rustType, docFields map[string]map[string]bool) []string {
	var out []string
	for _, t := range rd.Types {
		if t.Kind != "struct" {
			continue
		}
		doc, ok := docFields[t.Name]
		if !ok {
			out = append(out, fmt.Sprintf("%s：文档里找不到该类型的字段表（文档未收录？）", t.Name))
			continue
		}
		rust := map[string]bool{}
		var order []string
		for _, f := range types[t.Name].Fields {
			rust[f.Name] = true
			order = append(order, f.Name)
		}
		for _, n := range order {
			if !doc[n] {
				out = append(out, fmt.Sprintf("%s：Rust 有字段 %s 而文档未列", t.Name, n))
			}
		}
		var dnames []string
		for n := range doc {
			dnames = append(dnames, n)
		}
		sort.Strings(dnames)
		for _, n := range dnames {
			if !rust[n] {
				out = append(out, fmt.Sprintf("%s：文档列了 %s 而 Rust 无此字段", t.Name, n))
			}
		}
	}
	return out
}

func writeOrCheck(root string, rd rulesDoc, rel, content string, checkOnly bool) bool {
	abs := filepath.Join(root, filepath.FromSlash(rel))
	if checkOnly {
		old, err := os.ReadFile(abs)
		if err != nil {
			fmt.Printf("  !! %s 不存在或不可读（%v）——请跑 `go run ./scripts/gen_protocol_ts`\n", rel, err)
			return false
		}
		if string(old) != content {
			fmt.Printf("  !! %s 与现场生成不一致（产物陈旧 / 手工改过）——请跑 `go run ./scripts/gen_protocol_ts`\n", rel)
			return false
		}
		return true
	}
	if err := os.MkdirAll(filepath.Dir(abs), 0o755); err != nil {
		fatal("建目录失败: %v", err)
	}
	if err := os.WriteFile(abs, []byte(content), 0o644); err != nil {
		fatal("写 %s 失败: %v", rel, err)
	}
	return true
}

func selftest(root string, rd rulesDoc) int {
	types, docFields := loadAll(root, rd)

	// 基线
	ts := genTS(rd, types)
	meta := genMeta(rd, types)
	baseOK := true
	if old, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(rd.OutTS))); err != nil || string(old) != ts {
		fmt.Println("gen_protocol_ts: selftest ABORT——基线产物与现场生成不一致，先跑生成再自证")
		baseOK = false
	}
	if old, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(rd.OutMeta))); err != nil || string(old) != meta {
		fmt.Println("gen_protocol_ts: selftest ABORT——基线 meta 产物不一致，先跑生成再自证")
		baseOK = false
	}
	if m := fieldSetMismatch(rd, types, docFields); len(m) > 0 {
		fmt.Printf("gen_protocol_ts: selftest ABORT——基线字段对账就红（%d 处），无法归因\n", len(m))
		baseOK = false
	}
	if !baseOK {
		return 2
	}

	// 选一个 struct 作注入目标
	target := ""
	for _, t := range rd.Types {
		if t.Kind == "struct" {
			target = t.Name
			break
		}
	}

	failed := 0
	// ① 生成物注入：给 Rust 侧某类型多一个字段 → 生成文本必不同
	cp := map[string]*rustType{}
	for k, v := range types {
		nv := *v
		nv.Fields = append([]rustField(nil), v.Fields...)
		cp[k] = &nv
	}
	cp[target].Fields = append(cp[target].Fields, rustField{Name: "__selftest_probe", Ty: "i32"})
	if genTS(rd, cp) == ts {
		fmt.Println("gen_protocol_ts: selftest FAIL——注入新字段后生成文本不变，生成器漏字段")
		failed++
	} else {
		fmt.Println("gen_protocol_ts: selftest ok——注入 Rust 新字段被判红（生成文本变化）")
	}
	// ② 文档对账注入：文档少一个字段
	dcp := map[string]map[string]bool{}
	for k, v := range docFields {
		m := map[string]bool{}
		for n := range v {
			m[n] = true
		}
		dcp[k] = m
	}
	if len(dcp[target]) > 0 {
		for n := range dcp[target] {
			delete(dcp[target], n)
			break
		}
		if len(fieldSetMismatch(rd, types, dcp)) == 0 {
			fmt.Println("gen_protocol_ts: selftest FAIL——文档删字段后仍判绿，对账失效")
			failed++
		} else {
			fmt.Println("gen_protocol_ts: selftest ok——文档缺字段被判红（双向对账生效）")
		}
	}
	// ③ 反向：文档多出一个 Rust 没有的字段
	dcp2 := map[string]map[string]bool{}
	for k, v := range docFields {
		m := map[string]bool{}
		for n := range v {
			m[n] = true
		}
		dcp2[k] = m
	}
	dcp2[target]["__selftest_fabricated"] = true
	if len(fieldSetMismatch(rd, types, dcp2)) == 0 {
		fmt.Println("gen_protocol_ts: selftest FAIL——文档多字段后仍判绿，反向对账失效")
		failed++
	} else {
		fmt.Println("gen_protocol_ts: selftest ok——文档多出字段被判红（反向对账生效）")
	}

	if failed > 0 {
		return 1
	}
	fmt.Printf("gen_protocol_ts: selftest PASS——3 路注入全部判红（注入目标 %s）\n", target)
	return 0
}

func main() {
	checkFlag := flag.Bool("check", false, "判定模式：磁盘产物 == 现场生成 + 字段集双向对账（CI 入口）")
	selftestFlag := flag.Bool("selftest", false, "J9 证红：三路内存注入")
	flag.Parse()

	root := repoRoot()
	var rd rulesDoc
	if err := json.Unmarshal([]byte(mustRead(root, rulesPath)), &rd); err != nil {
		fatal("解析规则失败: %v", err)
	}
	if len(rd.Types) == 0 || rd.OutTS == "" || rd.SchemaDoc == "" {
		fatal("规则缺 types / out_ts / schema_doc")
	}

	if *selftestFlag {
		os.Exit(selftest(root, rd))
	}

	types, docFields := loadAll(root, rd)
	ts := genTS(rd, types)
	meta := genMeta(rd, types)

	nFields := 0
	for _, t := range rd.Types {
		if t.Kind == "struct" {
			nFields += len(types[t.Name].Fields)
		}
	}
	fmt.Printf("gen_protocol_ts: 解析 %d 类型 / %d 字段（源 %d 文件）\n",
		len(rd.Types), nFields, len(rd.TypeSources))

	mis := fieldSetMismatch(rd, types, docFields)
	if len(mis) == 0 {
		fmt.Printf("  ok Rust ↔ schema 文档（%s）字段集双向一致\n", rd.SchemaDoc)
	} else {
		for _, m := range mis {
			fmt.Printf("  !! %s\n", m)
		}
	}

	okTS := writeOrCheck(root, rd, rd.OutTS, ts, *checkFlag)
	okMeta := writeOrCheck(root, rd, rd.OutMeta, meta, *checkFlag)
	if !*checkFlag {
		fmt.Printf("  ✓ 已写入 %s（%d 字节）与 %s（%d 字节）\n", rd.OutTS, len(ts), rd.OutMeta, len(meta))
	}

	if len(mis) > 0 || !okTS || !okMeta {
		fmt.Println("gen_protocol_ts: FAIL——生成物或字段对账不一致")
		os.Exit(1)
	}
	if *checkFlag {
		fmt.Println("gen_protocol_ts: PASS——产物新鲜且字段集与文档双向一致")
	} else {
		fmt.Println("gen_protocol_ts: 生成完成")
	}
}
