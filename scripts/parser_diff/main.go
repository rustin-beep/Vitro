// parser_diff：S3 解析层差分驱动（E1–E4 + 病态 12 样本 + 活性断言）。
//
// 用法（仓库根）：
//
//	go run ./scripts/parser_diff <corpus_dir>            # E1/E2 全量对拍
//	go run ./scripts/parser_diff --pathological           # E3 病态 12 样本（同等拒绝）
//	go run ./scripts/parser_diff --legal-deep             # E4 合法深嵌套反向锚
//	go run ./scripts/parser_diff --threshold              # E3+ 阈值样本（勘察 §8-E3）
//	go run ./scripts/parser_diff <corpus_dir> --selftest  # J9：注入差异先证红
//
// 对拍面：
//   - E1：AST dump JSON——Rust serve `ast.dump` 响应 vs MoonBit
//     `cmd/dump_ast` 输出，双侧经归一器（scripts/internal/canonicalize，
//     进程内调用；2026-09-22 抽库前为逐样本起进程）归一后逐字节 diff
//   - E2：parse_errors 序列（code/line/column 保序；message 在 JSON 内
//     一并逐字节比——文案两侧照搬自同一源，漂移即红）
//   - 活性：MoonBit 侧 stall_count 必须为 0（勘察 6-3 的 GC 语言观测义务；
//     Rust 侧恒 0）
//
// fail loud：自检（serve 可用 / 两侧文件数一致）不过直接拒绝给判定；归一器
// 已进程内链接（2026-09-22 抽库，scripts/internal/canonicalize），其可用性由
// 编译期保证，不再需要预构建自检；差异全量列出后 exit 1。
package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"

	canon "vitro/scripts/internal/canonicalize"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "用法: go run ./scripts/parser_diff <corpus_dir|--pathological|--legal-deep> [--selftest]")
		os.Exit(2)
	}
	mode := os.Args[1]
	selftest := len(os.Args) > 2 && os.Args[2] == "--selftest"
	switch {
	case mode == "--pathological":
		os.Exit(runPathological(selftest))
	case mode == "--legal-deep":
		os.Exit(runLegalDeep(selftest))
	case mode == "--threshold":
		os.Exit(runThreshold(selftest))
	default:
		corpus, err := filepath.Abs(mode)
		if err != nil {
			fail("语料路径解析失败: %v", err)
		}
		os.Exit(runCorpus(corpus, selftest))
	}
}

// ---------------------------------------------------------------------------
// 语料对拍（E1/E2/活性）
// ---------------------------------------------------------------------------

// knownForkFiles：E1/E2 已知有意分叉（2026-09-20 F3-v2 累加器裁定 b：
// 向 C 语义修正，oracle 侧自身不符 C 的形态族；逐条登记于 S3 执行
// 记录 §7-4/§8）。新增条目必须先登记后加名；J9：selftest 不覆盖此面
// （白名单吞 DIFF 属危险面，依赖 FORK(known) 行诚实可见）。
var knownForkFiles = map[string]string{
	// 局部函数指针声明 int*(*fp)(int)：oracle 产出双层
	// Pointer(Pointer(Function)) 不符 C（Clang 22.1.4 判据：单层
	// int*(*)(int)）；累加器统一 C 语义单层。全局同形态 oracle 本就
	// 单层（两处 oracle 实现互不一致），仅局部路径分叉。
	"function_pointer_return_ptr.c": "局部函数指针双层→C 单层（F3-v2）",
	// 局部函数原型声明 char*month_name(int n)（K&R 5-11）：oracle 局部
	// 路径对函数声明符双包 Pointer(Pointer(Function))，同上族——累加器
	// 按 C 语义单层（Clang：函数原型，Vitro 表示层 decay 单层）
	"kr_5_11.c": "局部函数原型双层→C 单层（F3-v2）",
}

func runCorpus(corpus string, selftest bool) int {
	files := listCFiles(corpus)
	if len(files) == 0 {
		fail("语料目录无 .c 文件: %s", corpus)
	}
	rustOuts := rustAstDumpBatch(files)
	if selftest {
		// J9 埋雷：篡改首个文件的 Rust 侧输出（ok 翻转），驱动必须红
		rustOuts[0] = []byte(`{"ok": false, "parse_error_count": 0, "ast": null, "parse_errors": [], "stall_count": 0}`)
		fmt.Println("parser_diff: selftest 已注入差异（Rust 侧样本 0 篡改）")
	}
	moonDir := moonDump(corpus)
	failures := 0
	for i, f := range files {
		stem := stemOf(f)
		moonRaw, err := os.ReadFile(filepath.Join(moonDir, stem+".c.ast.json"))
		if err != nil {
			// dump_ast 输出名 = <stem>.c.ast.json（basename 去 .ast 后缀前含 .c）
			moonRaw, err = os.ReadFile(filepath.Join(moonDir, stem+".ast.json"))
			if err != nil {
				fail("MoonBit 侧输出缺失: %s (%v)", stem, err)
			}
		}
		rustNorm := canonicalize(rustOuts[i])
		moonNorm := canonicalize(moonRaw)
		if !bytes.Equal(rustNorm, moonNorm) {
			// 已知有意分叉（裁定 b：向 C 语义修正；oracle 自身不符 C 的
			// 形态族）——登记于 S3 执行记录，命中白名单降级 FORK 报告，
			// 不计失败（诚实显示差异仍在，防静默吞）
			if reason, ok := knownForkFiles[filepath.Base(f)]; ok {
				fmt.Printf("FORK(known) %s——%s\n", filepath.Base(f), reason)
				continue
			}
			failures++
			fmt.Printf("DIFF %s\n  rust: %s\n  moon: %s\n", filepath.Base(f),
				preview(rustNorm), preview(moonNorm))
			continue
		}
		// 活性断言：stall_count 必须为 0（归一化文本内直接查）
		if bytes.Contains(moonNorm, []byte(`"stall_count": 0`)) == false {
			failures++
			fmt.Printf("STALL %s：MoonBit 侧解析器出现零推进迭代\n", filepath.Base(f))
		}
	}
	if failures > 0 {
		fmt.Printf("parser_diff: FAIL——%d/%d 处差异（语料 %s）\n", failures, len(files), corpus)
		return 1
	}
	fmt.Printf("parser_diff: PASS——%d 个样本 AST+诊断序列归一后逐字节一致（语料 %s）\n", len(files), corpus)
	return 0
}

// ---------------------------------------------------------------------------
// E3 病态 12 样本（勘察 6-4 / 6-11 全部通道；两侧"同等拒绝"）
// ---------------------------------------------------------------------------

// pathologicalSamples：12 条（6-4 通道 7 条 + 6-11 通道 5 条）。
// 每条：名字、生成器（规模参数展开）、预期（两侧都拒绝：ok=false 或
// parse_errors 非空；进程不崩）。
var pathologicalSamples = []struct {
	name string
	src  string
}{
	{"paren_63", "int main() { return " + rep("(", 63) + "1" + rep(")", 63) + "; }"},
	{"brace_300", "int main() {" + rep("{", 300) + rep("}", 300) + "return 0; }"},
	{"init_list_3000", "int a[" + strconv.Itoa(3000) + "] = " + rep("{", 3000) + "1" + rep("}", 3000) + "; int main() { return 0; }"},
	{"assign_chain_3000", "int main() { int a = 0; a" + rep(" = a", 3000) + "; return a; }"},
	{"unary_chain_5000", "int main() { return " + rep("!", 5000) + "1; }"},
	{"pointer_chain_100", "int " + rep("*", 100) + " p; int main() { return 0; }"},
	{"postfix_chain_5000", "int main() { int a[1]; return a" + rep("[0]", 5000) + "; }"},
	{"decl_suffix_1300", "int a" + rep("[1]", 1300) + ";"},
	{"typedef_suffix_1500", "typedef int T" + rep("[1]", 1500) + ";"},
	{"sizeof_abstract_1400", "int main() { return sizeof(int" + rep("[1]", 1400) + "); }"},
	{"param_suffix_1500", "int f(int a" + rep("[1]", 1500) + ") { return 0; }"},
	{"field_suffix_1500", "struct S { int a" + rep("[1]", 1500) + "; };"},
}

func runPathological(selftest bool) int {
	tmp, err := os.MkdirTemp("", "parser_patho_*")
	if err != nil {
		fail("临时目录失败: %v", err)
	}
	defer os.RemoveAll(tmp)
	for _, s := range pathologicalSamples {
		if err := os.WriteFile(filepath.Join(tmp, s.name+".c"), []byte(s.src), 0644); err != nil {
			fail("病态样本写入失败: %v", err)
		}
	}
	files := listCFiles(tmp)
	if len(files) != len(pathologicalSamples) {
		fail("病态样本数不符: %d != %d", len(files), len(pathologicalSamples))
	}
	rustOuts := rustAstDumpBatch(files)
	if selftest {
		// J9 埋雷：把"decl_suffix_1300"的 Rust 侧结果改成 ok=true——
		// "同等拒绝"断言必须红
		for i, f := range files {
			if filepath.Base(f) == "decl_suffix_1300.c" {
				rustOuts[i] = []byte(`{"ok": true, "parse_error_count": 0, "ast": {}, "parse_errors": [], "stall_count": 0}`)
			}
		}
		fmt.Println("parser_diff: selftest 已注入差异（decl_suffix_1300 篡改为 ok=true）")
	}
	moonDir := moonDump(tmp)
	failures := 0
	for i, f := range files {
		name := filepath.Base(f)
		rustNorm := canonicalize(rustOuts[i])
		stem := stemOf(f)
		moonRaw, err := os.ReadFile(filepath.Join(moonDir, stem+".c.ast.json"))
		if err != nil {
			fail("MoonBit 侧输出缺失: %s (%v)", name, err)
		}
		moonNorm := canonicalize(moonRaw)
		// E3 断言 1：两侧同等拒绝（Rust P1 修复后同样诊断拒绝——若
		// 某侧 ok=true 且 parse_errors 空，即"同等拒绝"被破坏）
		for _, side := range []struct {
			tag  string
			norm []byte
		}{{"rust", rustNorm}, {"moon", moonNorm}} {
			if bytes.Contains(side.norm, []byte(`"ok": true`)) &&
				bytes.Contains(side.norm, []byte(`"parse_error_count": 0`)) {
				failures++
				fmt.Printf("E3-REJECT-MISS %s（%s 侧意外接受）\n", name, side.tag)
			}
		}
		// E3 断言 2：错误码序列 + 首错位置 + 完整诊断面一致
		if !bytes.Equal(rustNorm, moonNorm) {
			failures++
			fmt.Printf("E3-DIFF %s\n  rust: %s\n  moon: %s\n", name,
				preview(rustNorm), preview(moonNorm))
			continue
		}
	}
	if failures > 0 {
		fmt.Printf("parser_diff --pathological: FAIL——%d 处（12 样本同等拒绝锚）\n", failures)
		return 1
	}
	fmt.Printf("parser_diff --pathological: PASS——12 病态样本同等拒绝（错误码序列+位置一致，两侧无崩溃）\n")
	return 0
}

// ---------------------------------------------------------------------------
// E4 合法深嵌套反向锚（crash_regression_tests.rs:776 形状）
// ---------------------------------------------------------------------------

func runLegalDeep(selftest bool) int {
	samples := []struct {
		name string
		src  string
	}{
		{"paren_30_add_100", "int main() { return " + rep("(", 30) + "1" +
			rep(" + 1", 100) + rep(")", 30) + "; }"},
		{"decl_suffix_1200", "int a" + rep("[1]", 1200) + "; int main() { return 0; }"},
	}
	tmp, err := os.MkdirTemp("", "parser_legal_*")
	if err != nil {
		fail("临时目录失败: %v", err)
	}
	defer os.RemoveAll(tmp)
	for _, s := range samples {
		if err := os.WriteFile(filepath.Join(tmp, s.name+".c"), []byte(s.src), 0644); err != nil {
			fail("E4 样本写入失败: %v", err)
		}
	}
	files := listCFiles(tmp)
	rustOuts := rustAstDumpBatch(files)
	if selftest {
		rustOuts[0] = []byte(`{"ok": false, "parse_error_count": 1, "ast": null, "parse_errors": [{"code":1006,"line":1,"column":1,"message":"x"}], "stall_count": 0}`)
		fmt.Println("parser_diff: selftest 已注入差异（E4 样本 0 篡改为拒绝）")
	}
	moonDir := moonDump(tmp)
	failures := 0
	for i, f := range files {
		name := filepath.Base(f)
		rustNorm := canonicalize(rustOuts[i])
		stem := stemOf(f)
		moonRaw, err := os.ReadFile(filepath.Join(moonDir, stem+".c.ast.json"))
		if err != nil {
			fail("MoonBit 侧输出缺失: %s (%v)", name, err)
		}
		moonNorm := canonicalize(moonRaw)
		for _, side := range []struct {
			tag  string
			norm []byte
		}{{"rust", rustNorm}, {"moon", moonNorm}} {
			if !bytes.Contains(side.norm, []byte(`"ok": true`)) {
				failures++
				fmt.Printf("E4-MUST-SUCCEED %s（%s 侧意外拒绝）: %s\n", name, side.tag, preview(side.norm))
			}
		}
		if !bytes.Equal(rustNorm, moonNorm) {
			failures++
			fmt.Printf("E4-DIFF %s\n  rust: %s\n  moon: %s\n", name, preview(rustNorm), preview(moonNorm))
		}
	}
	if failures > 0 {
		fmt.Printf("parser_diff --legal-deep: FAIL——%d 处（E4 反向锚）\n", failures)
		return 1
	}
	fmt.Printf("parser_diff --legal-deep: PASS——合法深嵌套样本两侧成功且 AST 一致\n")
	return 0
}

// ---------------------------------------------------------------------------
// E3+ 阈值样本（勘察 §8-E3"新语言重标定后的阈值样本"——S3 审阅补齐）
//
// 三族：
//   A. offsetof 嵌套深链（F1）：跨临界 k=16/64/128，两侧一致断言
//      （修复前 MoonBit 静默接受/栈溢出 vs Rust 优雅拒绝——必红）
//   B. enum/_Static_assert 常量链（F2）：600（对照）/1200/1200，两侧一致
//      断言（修复前 MoonBit parse 期常量折叠栈溢出——必红）
//   C. 指针括号+多维数组（F3）：MoonBit 侧 C 语义结构断言——裁定 (b)
//      有意与 Rust oracle 分叉（撕裂折叠已入差异台账），故此族不做两侧
//      对拍，断言修复后的正确折叠形状 + 两条防回归对照
// ---------------------------------------------------------------------------

// offsetofChain：k 层嵌套 offsetof——每层 struct 数组维度再放 offsetof，
// 深度计数每层归零的通道（F1 病灶形状）。
func offsetofChain(k int) string {
	s := "offsetof(struct{int a[0];},a)"
	for i := 0; i < k; i++ {
		s = "offsetof(struct{int a[" + s + "];},a)"
	}
	return s
}

func enumChain(n int) string {
	return "enum E { A = " + rep("1+", n-1) + "1 };\nint main() { return 0; }\n"
}

func sassertChain(n int) string {
	return "_Static_assert(" + rep("1+", n-1) + "1, \"x\");\nint main() { return 0; }\n"
}

var thresholdAgreeSamples = []struct {
	name string
	src  string
}{
	{"offsetof_16", "int main() { return " + offsetofChain(16) + "; }\n"},
	{"offsetof_64", "int main() { return " + offsetofChain(64) + "; }\n"},
	{"offsetof_128", "int main() { return " + offsetofChain(128) + "; }\n"},
	// 复审补：崩溃悬崖侧（修复前 k≥86 起栈溢出）——固定"不再崩溃"下界
	{"offsetof_140", "int main() { return " + offsetofChain(140) + "; }\n"},
	{"enum_add_600", enumChain(600)},
	{"enum_add_1200", enumChain(1200)},
	{"sassert_add_1200", sassertChain(1200)},
}

// C 族：指针括号 + 数组维度的 C 语义折叠断言（裁定 b）。
// want 为类型骨架（skeleton 产出）；pick 从 dump 文档提取被断言的类型。
type shapeSample struct {
	name string
	src  string
	want string
	pick func(*dumpDoc) *mtype
}

var thresholdShapeSamples = []shapeSample{
	{"shape_ptrarr_guard", "int *p0[2];\nint main() { return 0; }\n",
		"Array(dims=2,elem=Pointer(Int))",
		func(d *dumpDoc) *mtype { return globalTy(d, "p0") }},
	{"shape_arrptr_dim1_guard", "int (*p3)[5];\nint main() { return 0; }\n",
		"Pointer(Array(dims=5,elem=Int))",
		func(d *dumpDoc) *mtype { return globalTy(d, "p3") }},
	{"shape_arrptr_dim2", "int (*p1)[2][3];\nint main() { return 0; }\n",
		"Pointer(Array(dims=2,3,elem=Int))",
		func(d *dumpDoc) *mtype { return globalTy(d, "p1") }},
	{"shape_arrptr_dim3", "int (*p2)[2][3][4];\nint main() { return 0; }\n",
		"Pointer(Array(dims=2,3,4,elem=Int))",
		func(d *dumpDoc) *mtype { return globalTy(d, "p2") }},
	{"shape_arrptr_field", "struct S1 { int (*f)[2][3]; };\nint main() { return 0; }\n",
		"Pointer(Array(dims=2,3,elem=Int))",
		func(d *dumpDoc) *mtype { return structFieldTy(d, "S1", "f") }},
	{"shape_arrptr_param", "int g1(int (*p)[2][3]) { return 0; }\nint main() { return 0; }\n",
		"Pointer(Array(dims=2,3,elem=Int))",
		func(d *dumpDoc) *mtype { return paramTy(d, "g1", "p") }},
	{"shape_arrptr_abstract", "int m1 = sizeof(int (*)[2][3]);\nint main() { return m1; }\n",
		"Pointer(Array(dims=2,3,elem=Int))",
		func(d *dumpDoc) *mtype { return globalInitSizeofTy(d, "m1") }},
	{"shape_arrptr_typedef", "typedef int (*Q1)[2][3];\nQ1 x;\nint main() { return 0; }\n",
		"Pointer(Array(dims=2,3,elem=Int))",
		func(d *dumpDoc) *mtype { return globalTy(d, "x") }},
	// F3-v2 复审扩族（期望值按 Clang -Xclang -ast-dump 拼写派生，22.1.4
	// 实测互证；f01/f02 的最外 Pointer 为 Vitro 函数 decay 约定）
	{"shape_arrptr_inner_dim", "int (*q1[2])[3][4];\nint main() { return 0; }\n",
		"Array(dims=2,elem=Pointer(Array(dims=3,4,elem=Int)))",
		func(d *dumpDoc) *mtype { return globalTy(d, "q1") }},
	{"shape_arrptr_inner_dim23", "int (*q2[2][3])[4][5];\nint main() { return 0; }\n",
		"Array(dims=2,3,elem=Pointer(Array(dims=4,5,elem=Int)))",
		func(d *dumpDoc) *mtype { return globalTy(d, "q2") }},
	{"shape_dblptr_arrptr", "int (*(*q3)[2][3])[4][5];\nint main() { return 0; }\n",
		"Pointer(Array(dims=2,3,elem=Pointer(Array(dims=4,5,elem=Int))))",
		func(d *dumpDoc) *mtype { return globalTy(d, "q3") }},
	{"shape_ptrarr_dim23", "int *q4[2][3];\nint main() { return 0; }\n",
		"Array(dims=2,3,elem=Pointer(Int))",
		func(d *dumpDoc) *mtype { return globalTy(d, "q4") }},
	{"shape_fnret_arrptr", "int (*h1(void))[2][3];\nint main() { return 0; }\n",
		"Pointer(Function(ret=Pointer(Array(dims=2,3,elem=Int))))",
		func(d *dumpDoc) *mtype { return globalTy(d, "h1") }},
	{"shape_fnptr_ret_arrptr", "int (*(*h2)(void))[2][3];\nint main() { return 0; }\n",
		"Pointer(Function(ret=Pointer(Array(dims=2,3,elem=Int))))",
		func(d *dumpDoc) *mtype { return globalTy(d, "h2") }},
	{"shape_fnptr_guard", "int (*fp9)(void);\nint main() { return 0; }\n",
		"Pointer(Function(ret=Int))",
		func(d *dumpDoc) *mtype { return globalTy(d, "fp9") }},
	{"shape_fnptr_arr_guard", "int (*fp8[2])(void);\nint main() { return 0; }\n",
		"Array(dims=2,elem=Pointer(Function(ret=Int)))",
		func(d *dumpDoc) *mtype { return globalTy(d, "fp8") }},
}

func runThreshold(selftest bool) int {
	tmp, err := os.MkdirTemp("", "parser_thresh_*")
	if err != nil {
		fail("临时目录失败: %v", err)
	}
	defer os.RemoveAll(tmp)
	all := 0
	for _, s := range thresholdAgreeSamples {
		if err := os.WriteFile(filepath.Join(tmp, s.name+".c"), []byte(s.src), 0644); err != nil {
			fail("阈值样本写入失败: %v", err)
		}
		all++
	}
	for _, s := range thresholdShapeSamples {
		if err := os.WriteFile(filepath.Join(tmp, s.name+".c"), []byte(s.src), 0644); err != nil {
			fail("阈值样本写入失败: %v", err)
		}
		all++
	}
	files := listCFiles(tmp)
	if len(files) != all {
		fail("阈值样本数不符: %d != %d", len(files), all)
	}
	rustOuts := rustAstDumpBatch(files)
	if selftest {
		// J9 埋雷 1：offsetof_64 的 Rust 侧翻转 ok——两侧一致断言必须红
		for i, f := range files {
			if filepath.Base(f) == "offsetof_64.c" {
				rustOuts[i] = []byte(`{"ok": true, "parse_error_count": 0, "ast": {}, "parse_errors": [], "stall_count": 0}`)
			}
		}
		fmt.Println("parser_diff: selftest 已注入差异（offsetof_64 Rust 侧篡改为 ok=true）")
	}
	moonDir := moonDump(tmp)
	failures := 0
	// 断言 1：A/B 族两侧一致（canonicalize 逐字节；崩溃在 moonDump 即 fail）
	for i, f := range files {
		name := filepath.Base(f)
		if !isAgreeSample(name) {
			continue
		}
		rustNorm := canonicalize(rustOuts[i])
		moonRaw, err := os.ReadFile(filepath.Join(moonDir, stemOf(f)+".c.ast.json"))
		if err != nil {
			fail("MoonBit 侧输出缺失: %s (%v)", name, err)
		}
		moonNorm := canonicalize(moonRaw)
		if !bytes.Equal(rustNorm, moonNorm) {
			failures++
			fmt.Printf("TH-AGREE-DIFF %s\n  rust: %s\n  moon: %s\n", name,
				preview(rustNorm), preview(moonNorm))
		}
	}
	// 断言 2：C 族 MoonBit 侧 C 语义折叠形状（不与 oracle 对拍——有意分叉）
	for _, f := range files {
		s := thresholdShapeSampleOf(filepath.Base(f))
		if s == nil {
			continue
		}
		moonRaw, err := os.ReadFile(filepath.Join(moonDir, stemOf(f)+".c.ast.json"))
		if err != nil {
			fail("MoonBit 侧输出缺失: %s (%v)", f, err)
		}
		var doc dumpDoc
		if err := json.Unmarshal(moonRaw, &doc); err != nil {
			fail("阈值样本 %s JSON 解析失败: %v", s.name, err)
		}
		if !doc.OK {
			failures++
			fmt.Printf("TH-SHAPE-REJECTED %s（MoonBit 侧意外拒绝：%s）\n", s.name, preview(moonRaw))
			continue
		}
		got := skeleton(s.pick(&doc))
		want := s.want
		if selftest {
			// J9 埋雷 2：篡改期望骨架——形状断言必须红
			want = "Int（selftest 注入的假期望）"
			fmt.Println("parser_diff: selftest 已注入差异（C 族期望骨架篡改）")
		}
		if got != want {
			failures++
			fmt.Printf("TH-SHAPE-DIFF %s\n  want: %s\n  got:  %s\n", s.name, want, got)
		}
	}
	if failures > 0 {
		fmt.Printf("parser_diff --threshold: FAIL——%d 处（阈值样本 %d 条）\n", failures, all)
		return 1
	}
	fmt.Printf("parser_diff --threshold: PASS——A/B 族 %d 条两侧一致 + C 族 %d 条 C 语义折叠正确\n",
		len(thresholdAgreeSamples), len(thresholdShapeSamples))
	return 0
}

func isAgreeSample(name string) bool {
	for _, s := range thresholdAgreeSamples {
		if s.name+".c" == name {
			return true
		}
	}
	return false
}

func thresholdShapeSampleOf(name string) *shapeSample {
	for i := range thresholdShapeSamples {
		if thresholdShapeSamples[i].name+".c" == name {
			return &thresholdShapeSamples[i]
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// MoonBit dump JSON 的最小类型面（C 族形状断言用）
// ---------------------------------------------------------------------------

type mtype struct {
	Array *struct {
		ArraySize int    `json:"array_size"`
		Dims      []int  `json:"dims"`
		Element   *mtype `json:"element"`
		IsVLA     bool   `json:"is_vla"`
	} `json:"Array"`
	Pointer *struct {
		Pointee *mtype `json:"pointee"`
	} `json:"Pointer"`
	Function *struct {
		ReturnType *mtype `json:"return_type"`
	} `json:"Function"`
	Int    json.RawMessage `json:"Int"`
	Struct json.RawMessage `json:"Struct"`
	Name   string          `json:"Named"`
}

// skeleton：类型骨架文本（Array 维度序 + 构造器嵌套——C 语义断言的比对面）。
func skeleton(t *mtype) string {
	if t == nil {
		return "<null>"
	}
	switch {
	case t.Int != nil:
		return "Int"
	case t.Array != nil:
		dims := make([]string, len(t.Array.Dims))
		for i, d := range t.Array.Dims {
			dims[i] = strconv.Itoa(d)
		}
		return "Array(dims=" + strings.Join(dims, ",") + ",elem=" + skeleton(t.Array.Element) + ")"
	case t.Pointer != nil:
		return "Pointer(" + skeleton(t.Pointer.Pointee) + ")"
	case t.Function != nil:
		return "Function(ret=" + skeleton(t.Function.ReturnType) + ")"
	case t.Struct != nil:
		return "Struct"
	default:
		return "<other>"
	}
}

type dumpDoc struct {
	OK              bool `json:"ok"`
	ParseErrorCount int  `json:"parse_error_count"`
	AST             *struct {
		Structs []struct {
			Name   string `json:"name"`
			Fields []struct {
				Name string `json:"name"`
				Ty   *mtype `json:"ty"`
			} `json:"fields"`
		} `json:"structs"`
		Globals []struct {
			Name string `json:"name"`
			Ty   *mtype `json:"ty"`
			Init *struct {
				Sizeof *struct {
					TargetType *mtype `json:"target_type"`
				} `json:"Sizeof"`
			} `json:"init"`
		} `json:"globals"`
		Funcs []struct {
			Name   string `json:"name"`
			Params []struct {
				Name string `json:"name"`
				Ty   *mtype `json:"ty"`
			} `json:"params"`
		} `json:"funcs"`
	} `json:"ast"`
}

func globalTy(d *dumpDoc, name string) *mtype {
	if d.AST == nil {
		return nil
	}
	for _, g := range d.AST.Globals {
		if g.Name == name {
			return g.Ty
		}
	}
	return nil
}

func globalInitSizeofTy(d *dumpDoc, name string) *mtype {
	if d.AST == nil {
		return nil
	}
	for _, g := range d.AST.Globals {
		if g.Name == name && g.Init != nil && g.Init.Sizeof != nil {
			return g.Init.Sizeof.TargetType
		}
	}
	return nil
}

func structFieldTy(d *dumpDoc, structName, field string) *mtype {
	if d.AST == nil {
		return nil
	}
	for _, s := range d.AST.Structs {
		if s.Name != structName {
			continue
		}
		for _, f := range s.Fields {
			if f.Name == field {
				return f.Ty
			}
		}
	}
	return nil
}

func paramTy(d *dumpDoc, funcName, param string) *mtype {
	if d.AST == nil {
		return nil
	}
	for _, f := range d.AST.Funcs {
		if f.Name != funcName {
			continue
		}
		for _, p := range f.Params {
			if p.Name == param {
				return p.Ty
			}
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// 两侧出口
// ---------------------------------------------------------------------------

// rustAstDumpBatch：单 serve 进程批量发 ast.dump 请求（JSONL 流式），
// 返回与 files 同序的 result JSON。
func rustAstDumpBatch(files []string) [][]byte {
	cli := filepath.Join("native", "target", "release", "vitro_cli.exe")
	if _, err := os.Stat(cli); err != nil {
		cli = filepath.Join("native", "target", "release", "vitro_cli")
		if _, err := os.Stat(cli); err != nil {
			fail("Rust CLI 不存在（先 cargo build --release --bin vitro_cli）: %v", err)
		}
	}
	cmd := exec.Command(cli, "serve")
	stdin, err := cmd.StdinPipe()
	if err != nil {
		fail("serve stdin 管道失败: %v", err)
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		fail("serve stdout 管道失败: %v", err)
	}
	cmd.Stderr = os.Stderr
	if err := cmd.Start(); err != nil {
		fail("serve 启动失败: %v", err)
	}
	go func() {
		w := bufio.NewWriter(stdin)
		enc := json.NewEncoder(w)
		for i, f := range files {
			src, err := os.ReadFile(f)
			if err != nil {
				fail("读样本失败 %s: %v", f, err)
			}
			_ = enc.Encode(map[string]any{
				"id":     i + 1,
				"method": "ast.dump",
				"params": map[string]any{"source": string(src), "filename": filepath.Base(f)},
			})
		}
		w.Flush()
		stdin.Close()
	}()
	outBy := make([][]byte, len(files))
	sc := bufio.NewScanner(stdout)
	sc.Buffer(make([]byte, 64*1024*1024), 64*1024*1024)
	seen := 0
	for sc.Scan() {
		line := sc.Bytes()
		if len(line) == 0 {
			continue
		}
		var resp struct {
			ID     int             `json:"id"`
			OK     bool            `json:"ok"`
			Result json.RawMessage `json:"result"`
			Error  json.RawMessage `json:"error"`
		}
		if err := json.Unmarshal(line, &resp); err != nil {
			fail("serve 响应解析失败: %v (%s)", err, preview(line))
		}
		if resp.ID < 1 || resp.ID > len(files) {
			fail("serve 响应 id 越界: %d", resp.ID)
		}
		if !resp.OK || len(resp.Result) == 0 {
			fail("serve 请求失败（id=%d）: %s", resp.ID, preview(resp.Error))
		}
		outBy[resp.ID-1] = append([]byte(nil), resp.Result...)
		seen++
		if seen == len(files) {
			break
		}
	}
	if err := cmd.Wait(); err != nil {
		// serve 在 stdin 关闭后退出；非零退出码在此容忍（响应已收齐）
		_ = err
	}
	if seen != len(files) {
		fail("serve 响应不齐: %d/%d", seen, len(files))
	}
	return outBy
}

// moonDump：跑 MoonBit 侧 dump_ast，返回输出目录。
func moonDump(corpus string) string {
	out, err := os.MkdirTemp("", "parser_moon_*")
	if err != nil {
		fail("临时目录失败: %v", err)
	}
	// 注：调用方负责 defer 清理不适用于返回目录——泄漏一个临时目录由
	// 系统清理（差分工具的常规代价）；如需回收可用 moonOutDir 全局化
	cmd := exec.Command("moon", "run", "--target", "native", "cmd/dump_ast", "--", corpus, out)
	cmd.Dir = "moonbit"
	var buf bytes.Buffer
	cmd.Stdout = &buf
	cmd.Stderr = &buf
	if err := cmd.Run(); err != nil {
		fail("moon run cmd/dump_ast 失败: %v\n%s", err, buf.String())
	}
	return out
}

// ---------------------------------------------------------------------------
// 工具
// ---------------------------------------------------------------------------

// canonicalize：本地包装（fail loud 口径与抽库前一致——归一器不可用则拒绝
// 给判定）。归一逻辑单源在 scripts/internal/canonicalize。
//
// 2026-09-22 抽库改造：此前为 `go run` 冷启动（F5 实测 ~1.9s/次），F5 已优化为
// 预构建二进制（~0.3s/次），但**逐样本起进程**本身仍在——本驱动四处对拍循环
// （runCorpus / runPathological / runLegalDeep / runThreshold）均每样本调 2 次。
// 单位成本：旧 CLI 单次实测 **224.6ms**（基本即进程创建成本），进程内单次实测
// **4.6ms / 225KB 载荷**。
//
// 口径：改造省下的是逐样本的**进程创建**，不是"归零"——进程内仍有 ~4.6ms/次。
// 判定语义不变（锚逐字节，四模式 PASS 结论均未变）。
func canonicalize(raw []byte) []byte {
	out, err := canon.Bytes(raw)
	if err != nil {
		fail("canonicalize 失败: %v\ninput: %s", err, preview(raw))
	}
	return out
}

func listCFiles(dir string) []string {
	entries, err := os.ReadDir(dir)
	if err != nil {
		fail("读目录失败 %s: %v", dir, err)
	}
	var files []string
	for _, e := range entries {
		if !e.IsDir() && filepath.Ext(e.Name()) == ".c" {
			files = append(files, filepath.Join(dir, e.Name()))
		}
	}
	return files
}

func stemOf(path string) string {
	base := filepath.Base(path)
	ext := filepath.Ext(base)
	return base[:len(base)-len(ext)]
}

func rep(s string, n int) string {
	b := bytes.Repeat([]byte(s), n)
	return string(b)
}

func preview(b []byte) string {
	if len(b) > 220 {
		return string(b[:220]) + "..."
	}
	return string(b)
}

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "parser_diff: "+format+"\n", args...)
	os.Exit(2)
}

var _ = regexp.MustCompile // 保留 regexp 引用（未来按行 diff 用）
