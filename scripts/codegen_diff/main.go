// codegen_diff：S5 字节码生成层差分驱动（A 级产物对拍）。
//
// 用法（仓库根）：
//
//	go run ./scripts/codegen_diff <corpus_dir>              # A 级全量对拍
//	go run ./scripts/codegen_diff <corpus_dir> --baseline   # 基线期：one-sided 不计红（显式标志）
//	go run ./scripts/codegen_diff <corpus_dir> --selftest   # J9：注入差异先证红
//
// 对拍面（S5 版 A 级，勘察 §8.2 L1–L4 全量）：
//   - Rust `vitro_cli dump-compile`（CompileDump 14 键：version + CompileOutput
//     13 字段，含 export 不导出的 source_map/symbols/struct_defs/union_defs/
//     global_data_end 五项）vs MoonBit `cmd/dump_compile`（{"ok":true,"dump":
//     <同 14 键>}），双侧经 scripts/canonicalize 归一后逐字节 diff。
//   - 三条冻结（勘察 §8.2）：槽位策略 v1 逐位兼容 / 绝对 IP 跳转编码 /
//     libc 固定索引（1000/1024/1089 按名→索引比对）——本管道对 code 段
//     逐指令 diff 即三者共同的行为锚。
//
// 判定四类：
//
//	SAME          双 ok 且归一产物逐字节一致（锚绿）
//	AGREE-ERROR   双 fail 且失败层一致（lex/parse/type/gen 四层映射——
//	              Rust 按 dump-compile stderr 前缀归类，MoonBit 按 stage）
//	DIFF-ONE-SIDED 一 ok 一 fail（能力缺口——扩展批逐族收敛的目标面）
//	DIFF-CONTENT  双 ok 但产物不同（真红）
//
// exit 策略（fail loud，禁静默 default）：
//
//	DIFF-CONTENT > 0                 → exit 1（任何时候都是真红）
//	DIFF-ONE-SIDED > 0 且无 --baseline → exit 1（骨架/扩展期用 --baseline
//	                                    显式豁免 one-sided，content 红不豁免）
//	AGREE-ERROR 不计红（双侧同层拒绝是行为一致，但报告可见）
//
// selftest（J9 埋雷）：选一条"当前 SAME 且 Rust ok"的样本，Rust 侧
// code[1].operand 注入 +1 → 必须 DIFF-CONTENT 红（由绿转红的干净证红，
// 注入本就 DIFF 的样本无法归因——F3 复盘）。
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "用法: go run ./scripts/codegen_diff <corpus_dir> [--baseline|--selftest]")
		os.Exit(2)
	}
	corpus, err := filepath.Abs(os.Args[1])
	if err != nil {
		fail("语料路径解析失败: %v", err)
	}
	baseline := false
	selftest := false
	for _, a := range os.Args[2:] {
		switch a {
		case "--baseline":
			baseline = true
		case "--selftest":
			selftest = true
		default:
			fail("未知参数: %s", a)
		}
	}
	os.Exit(runCorpus(corpus, baseline, selftest))
}

// knownForkFiles：parser 层已知有意分叉（S3 F3-v2 累加器裁定 b 白名单，
// 见 scripts/parser_diff / scripts/typeck_diff 同名表——根因在 parser：
// 局部函数指针/函数原型声明符 oracle 双层 Pointer(Pointer(Function)) 不符
// C 语义，MoonBit 按 C 单层）在 **codegen 消费面**的放大（symbols 的 ty
// 定型分叉连带 dump 产物）。与 typeck 侧同规则：命中降级 FORK(known)
// 报告不计失败；S8 差异台账收编时一并裁定。2026-09-21 扩展批三号首条
// CONTENT-DIFF 即此根因（code 段两侧一致，纯类型定型面分叉）。
var knownForkFiles = map[string]string{
	"function_pointer_return_ptr.c": "局部函数指针双层→C 单层（F3-v2）——codegen 消费面放大（symbols.ty）",
	"kr_5_11.c":                     "局部函数原型双层→C 单层（F3-v2）——codegen 消费面放大",
}

func runCorpus(corpus string, baseline bool, selftest bool) int {
	files := listCFiles(corpus)
	if len(files) == 0 {
		fail("语料目录无 .c 文件: %s", corpus)
	}
	rustOuts, rustStderrs := rustDumpBatch(files)
	moonDir := moonDump(corpus)
	// 归一化：Rust 全文件；MoonBit 抽 .dump（ok=false 保留原文件形态参与
	// stage 判定）
	type side struct {
		ok   bool
		dump []byte // ok=true 时为 14 键 dump 的归一形态
		aggr string // ok=false 时的失败层（lex/parse/type/gen）
	}
	sides := make([][2]side, len(files))
	for i, f := range files {
		stem := stemOf(f)
		moonRaw, err := os.ReadFile(filepath.Join(moonDir, stem+".c.compile.json"))
		if err != nil {
			moonRaw, err = os.ReadFile(filepath.Join(moonDir, stem+".compile.json"))
			if err != nil {
				fail("MoonBit 侧输出缺失: %s (%v)", stem, err)
			}
		}
		rustOK := len(rustOuts[i]) > 0
		moonOK, moonDumpRaw, moonStage := parseMoonDoc(moonRaw)
		sides[i][0] = side{rustOK, nil, ""}
		if rustOK {
			sides[i][0].dump = canonicalize(rustOuts[i])
		}
		sides[i][1] = side{moonOK, nil, moonStage}
		if moonOK {
			sides[i][1].dump = canonicalize(moonDumpRaw)
		}
	}
	injectIdx := -1
	if selftest {
		for i := range files {
			if sides[i][0].ok && sides[i][1].ok && bytes.Equal(sides[i][0].dump, sides[i][1].dump) {
				rustOuts[i] = selftestInject(rustOuts[i])
				sides[i][0].dump = canonicalize(rustOuts[i])
				injectIdx = i
				fmt.Printf("codegen_diff: selftest 已注入差异（样本 %s 当前 SAME，Rust 侧 code[1].operand +1）\n",
					filepath.Base(files[i]))
				break
			}
		}
		if injectIdx < 0 {
			fail("selftest 语料无『当前 SAME 且双 ok』样本——由绿转红的干净证红无从建立")
		}
	}
	nSame, nAgree, nOneSided, nContent := 0, 0, 0, 0
	injectRed := false
	for i, f := range files {
		r, m := sides[i][0], sides[i][1]
		switch {
		case r.ok && m.ok:
			if bytes.Equal(r.dump, m.dump) {
				nSame++
			} else {
				// parser 层已知分叉在 codegen 消费面的放大（白名单与
				// typeck_diff 同源）——降级 FORK 报告不计失败
				if reason, ok := knownForkFiles[filepath.Base(f)]; ok {
					fmt.Printf("FORK(known) %s——%s\n", filepath.Base(f), reason)
					continue
				}
				nContent++
				fmt.Printf("DIFF-CONTENT %s\n  rust: %s\n  moon: %s\n", filepath.Base(f),
					preview(r.dump), preview(m.dump))
				if i == injectIdx {
					injectRed = true
				}
			}
		case !r.ok && !m.ok:
			// 双 fail：MoonBit stage vs Rust stderr 归类（dump 不可得，层一致
			// 即行为一致——诊断文本不同源不比）
			rStage := rustFailStage(rustStderrs[i], files[i])
			if rStage == m.aggr {
				nAgree++
			} else {
				// 层不同：一侧在更早层失败——按 content 级红处理（行为分叉）
				nContent++
				fmt.Printf("DIFF-STAGE %s：rust=%s moon=%s\n", filepath.Base(f), rStage, m.aggr)
			}
		default:
			nOneSided++
			which := "rust-ok/moon-fail"
			if !r.ok {
				which = "rust-fail/moon-ok"
			}
			fmt.Printf("DIFF-ONE-SIDED %s（%s）\n", filepath.Base(f), which)
		}
	}
	if selftest && !injectRed {
		fail("selftest 未证红——注入样本 %s 未判 DIFF-CONTENT，锚失效", filepath.Base(files[injectIdx]))
	}
	fmt.Printf("codegen_diff: SAME=%d AGREE-ERROR=%d ONE-SIDED=%d CONTENT-DIFF=%d（语料 %s, %d 文件）\n",
		nSame, nAgree, nOneSided, nContent, corpus, len(files))
	if nContent > 0 {
		fmt.Println("codegen_diff: FAIL——产物层差异（真红）")
		return 1
	}
	if nOneSided > 0 && !baseline {
		fmt.Println("codegen_diff: FAIL——能力缺口（one-sided）未豁免；基线期可显式 --baseline")
		return 1
	}
	fmt.Println("codegen_diff: PASS")
	return 0
}

// rustDumpBatch：逐文件 `vitro_cli dump-compile`（并行，每文件一进程）。
// 失败返回 nil（层归类走 stderr，由 rustFailStage 读取）。
//
// P1-1（审阅修复）：此前 os.CreateTemp 预创建 + 子进程覆写的握手在
// Windows 偶发 os error 5（拒绝访问——句柄关闭竞态/杀毒瞬时锁），导致
// 同语料同二进制判定不确定（批跑 rust-fail、单跑 rust-ok）。改为：
// 输出路径不预创建（子进程独占创建）+ error 5 重试一次；失败判定以
// **产物文件是否存在**为准（exit 0 必有文件、exit≠0 无文件）。
// 返回 (产物, stderr)：失败样本的 stderr 随序返回供 rustFailStage 查表
// 归类（2026-09-21 审阅修复：此前批量已捕获却丢弃、逐例重跑 CLI）。
func rustDumpBatch(files []string) ([][]byte, [][]byte) {
	cli := rustCli()
	outs := make([][]byte, len(files))
	stderrs := make([][]byte, len(files))
	outDir, err := os.MkdirTemp("", "codegen_rust_out_*")
	if err != nil {
		fail("临时目录失败: %v", err)
	}
	defer os.RemoveAll(outDir)
	var wg sync.WaitGroup
	sem := make(chan struct{}, 8)
	for i, f := range files {
		wg.Add(1)
		go func(i int, f string) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			outPath := filepath.Join(outDir, fmt.Sprintf("%d.json", i))
			var lastStderr []byte
			for attempt := 0; attempt < 2; attempt++ {
				cmd := exec.Command(cli, "dump-compile", f, "-o", outPath)
				var stderr bytes.Buffer
				cmd.Stderr = &stderr
				err := cmd.Run()
				lastStderr = stderr.Bytes()
				if err == nil {
					break
				}
				if attempt == 0 && bytes.Contains(lastStderr, []byte("拒绝访问")) {
					continue // error 5 瞬态：重试一次
				}
				break
			}
			data, readErr := os.ReadFile(outPath)
			if readErr != nil || len(data) == 0 {
				outs[i] = nil // 编译失败（无产物）；层归类走查表
				stderrs[i] = lastStderr
				return
			}
			outs[i] = data
		}(i, f)
	}
	wg.Wait()
	return outs, stderrs
}

// rustFailStage：Rust 侧失败层归类（dump-compile stderr 前缀——与
// cmd_dump_compile 的 eprintln 文本耦合，文本变更须同步此处）。
// stderr 由 rustDumpBatch 随序伴生返回，查表不重跑（2026-09-21 审阅
// 修复：.err 伴生文件方案已废弃——死码且泄漏 %TEMP）。
func rustFailStage(stderrRaw []byte, f string) string {
	s := string(stderrRaw)
	for _, p := range [][2]string{
		{"词法错误", "lex"},
		{"语法错误", "parse"},
		{"类型错误", "type"},
		{"生成错误", "gen"},
	} {
		if strings.Contains(s, p[0]) {
			return p[1]
		}
	}
	// P1-1：基础设施错误（拒绝访问/找不到二进制等）不是语料属性。
	// 〔2026-09-21 审阅降级〕fail 会把单文件异常升级成整轮 abort——批量
	// 判定可用性缺陷。改返回哨兵 stage "infra"：该文件计 DIFF-STAGE 红
	// （与 MoonBit stage 永不相等）、其余文件继续判定，不再吞整轮证据；
	// 真基础设施故障由多数文件齐红 + 人工看 stderr 暴露。
	return "infra"
}

// parseMoonDoc：解析 MoonBit 侧输出——ok 与 .dump 原始字节与失败 stage。
// **必须走 json.RawMessage**：map[string]any 往返会把 u64 位模式
// （globals_init_64 第二元，> 2^53）重编为 float64 最短十进制（末位漂移，
// 实测 4609434218613702656 → 4609434218613702700）——产物字节失真。
func parseMoonDoc(raw []byte) (bool, []byte, string) {
	var doc struct {
		OK    bool            `json:"ok"`
		Stage string          `json:"stage"`
		Dump  json.RawMessage `json:"dump"`
	}
	if err := json.Unmarshal(raw, &doc); err != nil {
		fail("MoonBit 输出解析失败: %v (%s)", err, preview(raw))
	}
	if !doc.OK {
		return false, nil, doc.Stage
	}
	return true, doc.Dump, ""
}

// selftestInject：Rust 侧产物 code[1].operand +1。RawMessage 分段重组——
// 只有 code[1] 一条经解码重编（operand 是跳转 IP/立即数，值域远小于
// 2^53，float64 安全），其余字段保留原始字节（大整数文本不失真——
// 见 parseMoonDoc 的 RawMessage 理由）。
func selftestInject(raw []byte) []byte {
	var doc map[string]json.RawMessage
	if err := json.Unmarshal(raw, &doc); err != nil {
		fail("selftest 注入解析失败: %v", err)
	}
	var code []json.RawMessage
	if err := json.Unmarshal(doc["code"], &code); err != nil {
		fail("selftest 注入失败：code 段解析失败: %v", err)
	}
	if len(code) < 2 {
		fail("selftest 注入失败：code 段不足 2 条")
	}
	var ins map[string]any
	if err := json.Unmarshal(code[1], &ins); err != nil {
		fail("selftest 注入失败：code[1] 解析失败: %v", err)
	}
	operand, ok := ins["operand"].(float64)
	if !ok {
		fail("selftest 注入失败：code[1].operand 非数值")
	}
	ins["operand"] = operand + 1
	reIns, err := json.Marshal(ins)
	if err != nil {
		fail("selftest 注入重序列化失败: %v", err)
	}
	code[1] = reIns
	reCode, err := json.Marshal(code)
	if err != nil {
		fail("selftest 注入 code 重序列化失败: %v", err)
	}
	doc["code"] = reCode
	re, err := json.Marshal(doc)
	if err != nil {
		fail("selftest 注入顶层重序列化失败: %v", err)
	}
	return re
}

// ---------------------------------------------------------------------------
// 基础设施（与 typeck_diff 同款，独立复制避免跨脚本依赖）
// ---------------------------------------------------------------------------

var (
	canonicalizeOnce sync.Once
	canonicalizePath string
	rustCliOnce      sync.Once
	rustCliPath      string
)

func canonicalizeBinary() string {
	canonicalizeOnce.Do(func() {
		exe := filepath.Join(os.TempDir(), "codegen_diff_canonicalize")
		if runtime.GOOS == "windows" {
			exe += ".exe"
		}
		cmd := exec.Command("go", "build", "-o", exe, "./scripts/canonicalize")
		var buf bytes.Buffer
		cmd.Stderr = &buf
		if err := cmd.Run(); err != nil {
			fail("canonicalize 预构建失败: %v\n%s", err, buf.String())
		}
		canonicalizePath = exe
	})
	return canonicalizePath
}

func canonicalize(raw []byte) []byte {
	cmd := exec.Command(canonicalizeBinary())
	cmd.Stdin = bytes.NewReader(raw)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		fail("canonicalize 失败: %v\nstderr: %s\ninput: %s", err, stderr.String(), preview(raw))
	}
	return out
}

func rustCli() string {
	rustCliOnce.Do(func() {
		for _, p := range []string{
			"native/target/release/vitro_cli.exe",
			"native/target/release/vitro_cli",
		} {
			if _, err := os.Stat(p); err == nil {
				rustCliPath = p
				return
			}
		}
		fail("未找到 vitro_cli release 二进制（native/target/release/）——先 cargo build --release --bin vitro_cli")
	})
	return rustCliPath
}

func moonDump(corpus string) string {
	out, err := os.MkdirTemp("", "codegen_moon_*")
	if err != nil {
		fail("临时目录失败: %v", err)
	}
	cmd := exec.Command("moon", "run", "--target", "native", "cmd/dump_compile", "--", corpus, out)
	cmd.Dir = "moonbit"
	var buf bytes.Buffer
	cmd.Stdout = &buf
	cmd.Stderr = &buf
	if err := cmd.Run(); err != nil {
		fail("moon run cmd/dump_compile 失败: %v\n%s", err, buf.String())
	}
	return out
}

func listCFiles(dir string) []string {
	entries, err := os.ReadDir(dir)
	if err != nil {
		fail("读语料目录失败: %v (%s)", err, dir)
	}
	var files []string
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), ".c") {
			files = append(files, filepath.Join(dir, e.Name()))
		}
	}
	sort.Strings(files)
	return files
}

func stemOf(path string) string {
	base := filepath.Base(path)
	return strings.TrimSuffix(base, ".c")
}

func preview(b []byte) string {
	s := string(b)
	if len(s) > 120 {
		return s[:120] + "…"
	}
	return s
}

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "codegen_diff: "+format+"\n", args...)
	os.Exit(2)
}
