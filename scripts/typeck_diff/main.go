// typeck_diff：S4 类型检查层差分驱动（E1–E4）。
//
// 用法（仓库根）：
//
//	go run ./scripts/typeck_diff <corpus_dir>            # E1–E4 全量对拍
//	go run ./scripts/typeck_diff <corpus_dir> --selftest  # J9：注入差异先证红
//
// 对拍面（S4 版 E1–E4，语义与 parser 层同名锚不同层）：
//   - E1：typeck 诊断序列——type_errors/type_warnings/type_hints 三段
//     {code,line,column,message} push 序保序；与 parse_errors 一并含在
//     全响应逐字节比对内
//   - E4：类型化 AST（lowering 后 ProgramNode：插入的 Cast / dims 推断 /
//     ty 定型）——Rust serve `typeck.dump` vs MoonBit `cmd/dump_typeck`，
//     双侧经归一器（scripts/internal/canonicalize，进程内调用；2026-09-22
//     抽库前为逐样本起进程）归一后逐字节 diff
//   - E2：符号表投影——从 typed_ast 派生 funcs/structs/unions/globals 的
//     {name, 签名摘要} 排序数组（不独立出口：typeck 内部 Map 状态不外溢，
//     从产物反推是行为等价）
//   - E3：名集合投影——funcs+globals+structs+unions 名字全集排序数组
//     （S4 验收行"mangled 名集合相等"的 C only 语义：C 侧无模板/方法
//     mangling，名集合即符号名全集）
//
// E1/E4 为全响应逐字节比对（最强锚）；E2/E3 投影独立报告，用于 E4 分叉
// 时的定位（分叉是否触及名字/签名层）。投影是 typed_ast 的纯函数——
// E4 一致则 E2/E3 必然一致。
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
	"sort"

	canon "vitro/scripts/internal/canonicalize"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "用法: go run ./scripts/typeck_diff <corpus_dir> [--selftest]")
		os.Exit(2)
	}
	corpus, err := filepath.Abs(os.Args[1])
	if err != nil {
		fail("语料路径解析失败: %v", err)
	}
	selftest := len(os.Args) > 2 && os.Args[2] == "--selftest"
	os.Exit(runCorpus(corpus, selftest))
}

// ---------------------------------------------------------------------------
// 语料对拍（E1/E4 全响应 + E2/E3 投影）
// ---------------------------------------------------------------------------

// knownForkFiles：parser 层已知有意分叉（S3 F3-v2 累加器裁定 b 白名单，
// 见 scripts/parser_diff/main.go 同名表——根因在 parser：局部函数指针/
// 函数原型声明符 oracle 双层 Pointer(Pointer(Function)) 不符 C，MoonBit
// 按 C 语义单层）在 **typeck 消费面**的放大——类型定型分叉连带 E1 诊断
//（如 fp(42) 通用指针调用 W3055 只在 oracle 双层形态下触发）。与 parser
// 侧同规则：命中降级 FORK(known) 报告不计失败（白名单吞 DIFF 属危险面，
// 依赖 FORK 行诚实可见）；S8 差异台账收编时一并裁定。
var knownForkFiles = map[string]string{
	"function_pointer_return_ptr.c": "局部函数指针双层→C 单层（F3-v2）——typeck 消费面放大（W3055 分叉）",
	"kr_5_11.c":                     "局部函数原型双层→C 单层（F3-v2）——typeck 消费面放大",
}

func runCorpus(corpus string, selftest bool) int {
	files := listCFiles(corpus)
	if len(files) == 0 {
		fail("语料目录无 .c 文件: %s", corpus)
	}
	rustOuts := rustTypeckDumpBatch(files)
	moonDir := moonDump(corpus)
	// 归一化缓存：注入判据需要先知道"哪些样本当前 PASS"（由绿转红才是
	// 干净证红——注入本就 DIFF 的样本无法归因，F3 复盘）
	rustNorms := make([][]byte, len(files))
	moonNorms := make([][]byte, len(files))
	for i, f := range files {
		stem := stemOf(f)
		moonRaw, err := os.ReadFile(filepath.Join(moonDir, stem+".c.typeck.json"))
		if err != nil {
			moonRaw, err = os.ReadFile(filepath.Join(moonDir, stem+".typeck.json"))
			if err != nil {
				fail("MoonBit 侧输出缺失: %s (%v)", stem, err)
			}
		}
		rustNorms[i] = canonicalize(rustOuts[i])
		moonNorms[i] = canonicalize(moonRaw)
	}
	injectIdx := -1
	if selftest {
		// J9 埋雷（双注入，一面一个；样本须为 ok=true——解析失败样本只能
		// 走翻 ok 分支，证不到 E2/E3/E4 面，F3 复盘）：
		// ① type_errors 追加假诊断 → E1 诊断序列面必须红；
		// ② typed_ast 首个函数改名 → E2 符号表/E3 名集合/E4 全树面必须红。
		for i := range files {
			if !bytes.Equal(rustNorms[i], moonNorms[i]) {
				continue // 本就 DIFF：注入无法归因，跳过
			}
			if !isOKDoc(rustOuts[i]) {
				continue // ok=false：改名分支不可达
			}
			rustOuts[i] = selftestInject(rustOuts[i])
			rustNorms[i] = canonicalize(rustOuts[i])
			injectIdx = i
			fmt.Printf("typeck_diff: selftest 已注入差异（样本 %s 当前 PASS 且 ok=true，Rust 侧：type_errors 假诊断 + typed_ast 首函数改名——E1 与 E2/E3/E4 双面）\n",
				filepath.Base(files[i]))
			break
		}
		if injectIdx < 0 {
			fail("selftest 语料无『当前 PASS 且 ok=true』样本——由绿转红的干净证红无从建立")
		}
	}
	failures := 0
	diffMarked := make([]bool, len(files))
	for i, f := range files {
		if !bytes.Equal(rustNorms[i], moonNorms[i]) {
			// parser 层已知分叉在 typeck 消费面的放大（白名单条目与
			// parser_diff 同源）——降级 FORK 报告不计失败，防静默吞
			if reason, ok := knownForkFiles[filepath.Base(f)]; ok {
				fmt.Printf("FORK(known) %s——%s\n", filepath.Base(f), reason)
				continue
			}
			failures++
			diffMarked[i] = true
			fmt.Printf("DIFF %s（E1/E4 全响应）\n  rust: %s\n  moon: %s\n", filepath.Base(f),
				preview(rustNorms[i]), preview(moonNorms[i]))
			continue
		}
		// E2/E3 投影（E4 已一致时的独立面——投影是 typed_ast 的纯函数，
		// E4 一致而投影不一致即投影器自身缺陷，fail loud 不算样本失败）
		rustProj := project(rustOuts[i])
		moonProj := project(moonRawOf(moonDir, files[i]))
		if rustProj.Symbols != moonProj.Symbols || rustProj.Names != moonProj.Names {
			fail("投影器自相矛盾（E4 一致但投影不一致）: %s", filepath.Base(f))
		}
	}
	if selftest && !diffMarked[injectIdx] {
		// 逐样本断言（F3 复盘：整体计数 +1 可被既有红面掩盖，证据强度
		// 按"注入样本自身的判定"计）
		fail("selftest 未证红——注入样本 %s 未判 DIFF，锚失效", filepath.Base(files[injectIdx]))
	}
	if failures > 0 {
		fmt.Printf("typeck_diff: FAIL——%d/%d 处差异（语料 %s）\n", failures, len(files), corpus)
		return 1
	}
	fmt.Printf("typeck_diff: PASS——%d 个样本 E1 诊断序列+E4 类型化 AST 归一逐字节一致 + E2/E3 投影一致（语料 %s）\n", len(files), corpus)
	return 0
}

// isOKDoc：响应是否 ok=true（selftest 注入样本筛选用——ok=false 时
// selftestInject 的改名分支不可达）。
func isOKDoc(raw []byte) bool {
	var doc struct {
		OK bool `json:"ok"`
	}
	if err := json.Unmarshal(raw, &doc); err != nil {
		fail("isOKDoc 解析失败: %v (%s)", err, preview(raw))
	}
	return doc.OK
}

// moonRawOf：读 MoonBit 侧原始输出（投影用——投影取原始 JSON 而非归一
// 形态，canonicalize 不改语义只改排版）。
func moonRawOf(moonDir string, f string) []byte {
	stem := stemOf(f)
	raw, err := os.ReadFile(filepath.Join(moonDir, stem+".c.typeck.json"))
	if err != nil {
		raw, err = os.ReadFile(filepath.Join(moonDir, stem+".typeck.json"))
		if err != nil {
			fail("MoonBit 侧输出缺失: %s (%v)", stem, err)
		}
	}
	return raw
}

// selftestInject：双注入——ok:true 响应给 type_errors 追加假诊断 + 首个
// 函数改名（E1 与 E2/E3/E4 双面证红）；ok:false 响应翻转 ok（保证对任何
// 样本必红）。
func selftestInject(raw []byte) []byte {
	var doc map[string]any
	if err := json.Unmarshal(raw, &doc); err != nil {
		fail("selftest 样本解析失败: %v", err)
	}
	if ok, _ := doc["ok"].(bool); ok {
		te, _ := doc["type_errors"].([]any)
		doc["type_errors"] = append(te, map[string]any{
			"code": 9999, "line": 1, "column": 1, "message": "selftest 注入",
		})
		if ta, _ := doc["typed_ast"].(map[string]any); ta != nil {
			if funcs, _ := ta["funcs"].([]any); len(funcs) > 0 {
				if f0, _ := funcs[0].(map[string]any); f0 != nil {
					if name, _ := f0["name"].(string); name != "" {
						f0["name"] = name + "__selftest"
					}
				}
			}
		}
	} else {
		doc["ok"] = true
	}
	out, err := json.Marshal(doc)
	if err != nil {
		fail("selftest 样本重序列化失败: %v", err)
	}
	return out
}

// ---------------------------------------------------------------------------
// E2/E3 投影（typed_ast 的纯函数）
// ---------------------------------------------------------------------------

type projection struct {
	Symbols string // E2：funcs/structs/unions/globals 签名摘要（排序后序列化）
	Names   string // E3：名字全集排序数组序列化
}

// project：从 typeck.dump 响应提取 E2/E3 投影。typed_ast 为 null（词法/
// 解析失败路径）时投影为空集常量。
func project(raw []byte) projection {
	var doc struct {
		OK       bool `json:"ok"`
		TypedAST *struct {
			Funcs []struct {
				Name       string `json:"name"`
				ReturnType mtype  `json:"return_type"`
				Params     []struct {
					Name string `json:"name"`
					Ty   mtype  `json:"ty"`
				} `json:"params"`
				IsVariadic bool `json:"is_variadic"`
				IsStatic   bool `json:"is_static"`
			} `json:"funcs"`
			Structs []struct {
				Name   string `json:"name"`
				Fields []struct {
					Name string `json:"name"`
					Ty   mtype  `json:"ty"`
				} `json:"fields"`
			} `json:"structs"`
			Unions []struct {
				Name   string `json:"name"`
				Fields []struct {
					Name string `json:"name"`
					Ty   mtype  `json:"ty"`
				} `json:"fields"`
			} `json:"unions"`
			Globals []struct {
				Name     string `json:"name"`
				Ty       mtype  `json:"ty"`
				IsStatic bool   `json:"is_static"`
			} `json:"globals"`
		} `json:"typed_ast"`
	}
	if err := json.Unmarshal(raw, &doc); err != nil {
		fail("投影解析失败: %v (%s)", err, preview(raw))
	}
	if doc.TypedAST == nil {
		return projection{Symbols: "<no-ast>", Names: "<no-ast>"}
	}
	var names []string
	type fsig struct {
		Name    string   `json:"name"`
		Ret     string   `json:"ret"`
		Params  []string `json:"params"`
		Vari    bool     `json:"variadic"`
		Static  bool     `json:"static"`
	}
	type sagg struct {
		Name   string     `json:"name"`
		Fields [][2]string `json:"fields"`
	}
	var funcs []fsig
	for _, f := range doc.TypedAST.Funcs {
		p := make([]string, len(f.Params))
		for i, q := range f.Params {
			p[i] = skeleton(&q.Ty)
		}
		funcs = append(funcs, fsig{f.Name, skeleton(&f.ReturnType), p, f.IsVariadic, f.IsStatic})
		names = append(names, f.Name)
	}
	agg := func(list []struct {
		Name   string `json:"name"`
		Fields []struct {
			Name string `json:"name"`
			Ty   mtype  `json:"ty"`
		} `json:"fields"`
	}) []sagg {
		out := make([]sagg, 0, len(list))
		for _, s := range list {
			fields := make([][2]string, len(s.Fields))
			for i, fl := range s.Fields {
				fields[i] = [2]string{fl.Name, skeleton(&fl.Ty)}
			}
			out = append(out, sagg{s.Name, fields})
			names = append(names, s.Name)
		}
		return out
	}
	structs := agg(doc.TypedAST.Structs)
	unions := agg(doc.TypedAST.Unions)
	type gsig struct {
		Name   string `json:"name"`
		Ty     string `json:"ty"`
		Static bool   `json:"static"`
	}
	var globals []gsig
	for _, g := range doc.TypedAST.Globals {
		globals = append(globals, gsig{g.Name, skeleton(&g.Ty), g.IsStatic})
		names = append(names, g.Name)
	}
	// 排序义务（F6）：投影面全排序——不依赖任何 Map/键序
	sort.Slice(funcs, func(i, j int) bool { return funcs[i].Name < funcs[j].Name })
	sort.Slice(structs, func(i, j int) bool { return structs[i].Name < structs[j].Name })
	sort.Slice(unions, func(i, j int) bool { return unions[i].Name < unions[j].Name })
	sort.Slice(globals, func(i, j int) bool { return globals[i].Name < globals[j].Name })
	sort.Strings(names)
	sym := map[string]any{
		"funcs": funcs, "structs": structs, "unions": unions, "globals": globals,
	}
	symJSON, err := json.Marshal(sym)
	if err != nil {
		fail("E2 投影序列化失败: %v", err)
	}
	namesJSON, err := json.Marshal(names)
	if err != nil {
		fail("E3 投影序列化失败: %v", err)
	}
	return projection{Symbols: string(symJSON), Names: string(namesJSON)}
}

// ---------------------------------------------------------------------------
// MoonBit dump JSON 的最小类型面（skeleton 渲染用——与 parser_diff 同源）
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
		ReturnType *mtype           `json:"return_type"`
		ParamTypes []json.RawMessage `json:"param_types"`
	} `json:"Function"`
	Int    json.RawMessage `json:"Int"`
	Char   json.RawMessage `json:"Char"`
	Struct json.RawMessage `json:"Struct"`
}

func skeleton(t *mtype) string {
	if t == nil {
		return "<null>"
	}
	switch {
	case t.Int != nil:
		return "Int"
	case t.Char != nil:
		return "Char"
	case t.Array != nil:
		dims := make([]string, len(t.Array.Dims))
		for i, d := range t.Array.Dims {
			dims[i] = fmt.Sprintf("%d", d)
		}
		return "Array(dims=" + join(dims) + ",elem=" + skeleton(t.Array.Element) + ")"
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

func join(parts []string) string {
	out := ""
	for i, p := range parts {
		if i > 0 {
			out += ","
		}
		out += p
	}
	return out
}

// ---------------------------------------------------------------------------
// 两侧出口
// ---------------------------------------------------------------------------

// rustTypeckDumpBatch：单 serve 进程批量发 typeck.dump 请求（JSONL 流式），
// 返回与 files 同序的 result JSON。
func rustTypeckDumpBatch(files []string) [][]byte {
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
				"method": "typeck.dump",
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

// moonDump：跑 MoonBit 侧 cmd/dump_typeck，返回输出目录。
func moonDump(corpus string) string {
	out, err := os.MkdirTemp("", "typeck_moon_*")
	if err != nil {
		fail("临时目录失败: %v", err)
	}
	cmd := exec.Command("moon", "run", "--target", "native", "cmd/dump_typeck", "--", corpus, out)
	cmd.Dir = "moonbit"
	var buf bytes.Buffer
	cmd.Stdout = &buf
	cmd.Stderr = &buf
	if err := cmd.Run(); err != nil {
		fail("moon run cmd/dump_typeck 失败: %v\n%s", err, buf.String())
	}
	return out
}

// ---------------------------------------------------------------------------
// 工具
// ---------------------------------------------------------------------------

// canonicalize：本地包装（fail loud 口径与抽库前一致——归一失败即拒绝给
// 判定）。归一逻辑单源在 scripts/internal/canonicalize。
//
// 2026-09-22 抽库改造：原实现每次调用都 exec.Command 起一个新进程，旧 CLI
// 单次实测 **224.6ms**（那基本就是进程创建成本）；进程内单次实测
// **4.6ms / 225KB 载荷**。本驱动的调用点在**逐文件循环内、每文件 2 次**——
// 四语料 600 文件（baseline 365 + knr 81 + leetcode 138 + gap 16）即 1200 次
// 进程创建，按单次 224.6ms 自洽 ≈ 270s。且该循环**串行单线程**，32 线程机上
// 只占 1 核（"CPU 几乎没占用"的成因）。
//
// 口径：改造省下的是这 1200 次**进程创建**，不是"归零"——进程内仍有
// ~4.6ms/次。判定语义不变（锚逐字节，PASS 计数与 FORK(known) 条目均未变）。
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

func preview(b []byte) string {
	if len(b) > 220 {
		return string(b[:220]) + "..."
	}
	return string(b)
}

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "typeck_diff: "+format+"\n", args...)
	os.Exit(2)
}
