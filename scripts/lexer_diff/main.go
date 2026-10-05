// lexer_diff：S2 词法差分对拍驱动（Go，零第三方依赖，fail loud）。
//
// 管线：语料目录（.c 文件）→
//
//	① Rust oracle 批量 dump：native/target/release/vitro_cli dump-tokens <dir> --out A --raw --pp
//	② MoonBit 侧批量 dump：moon -C moonbit run --target native cmd/dump_tokens -- <dir> B both
//	③ 逐文件逐字节 diff（A/*.l1.tsv ↔ B/*.l1.tsv、A/*.l2.tsv ↔ B/*.l2.tsv）
//
// 任一文件缺失或内容差异即 exit 1 并打印首差异上下文——不静默跳过。
//
// 工序③固化基线模式（2026-10-05，digest 清单形态）：
//
//	go run ./scripts/lexer_diff <corpus_dir> --freeze  # oracle dump → 临时目录 → TSV hash 聚合 golden_digest.json
//	go run ./scripts/lexer_diff <corpus_dir> --golden  # mb TSV hash ↔ 清单比对
//
//	oracle exe 不存在时自动切 --golden（工序④删区后 CI 零改动存活）；
//	清单键 = "corpus/name.tsv"，语料 sha 漂移即红；全文兜底 = orphan 分支
//	frozen-oracle-snapshot；重刷 diff = 影响面清单。一致性锚非正确性锚。
//
// J9 埋雷（--selftest）：对一侧 TSV 注入单字节差异，驱动必须报红（护栏可触发性）。
//
// 用法（仓库根）：
//
//	go run ./scripts/lexer_diff <corpus_dir>            # 全量对拍
//	go run ./scripts/lexer_diff <corpus_dir> --selftest # 先证红再退出
package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

const rustCLI = "native/target/release/vitro_cli.exe"
const selftestMutate = "count=" // 注入点：篡改尾行计数（必然逐字节差异）
const goldenRoot = "scripts/lexer_diff/golden"

func main() {
	var corpusArg string
	freeze, againstGolden, selftest := false, false, false
	for _, a := range os.Args[1:] {
		switch a {
		case "--freeze":
			freeze = true
		case "--golden":
			againstGolden = true
		case "--selftest":
			selftest = true
		default:
			if strings.HasPrefix(a, "--") || corpusArg != "" {
				fmt.Fprintf(os.Stderr, "lexer_diff: 未知/重复参数 %q\n", a)
				os.Exit(2)
			}
			corpusArg = a
		}
	}
	if corpusArg == "" {
		fmt.Fprintln(os.Stderr, "用法: go run ./scripts/lexer_diff <corpus_dir> [--freeze|--golden|--selftest]")
		os.Exit(2)
	}
	corpus, err := filepath.Abs(corpusArg)
	must(err, "解析语料绝对路径")
	if _, err := os.Stat("go.mod"); err != nil {
		fmt.Fprintln(os.Stderr, "lexer_diff: 必须在仓库根目录运行")
		os.Exit(2)
	}
	if freeze && againstGolden {
		fmt.Fprintln(os.Stderr, "lexer_diff: --freeze 与 --golden 互斥")
		os.Exit(2)
	}
	digestFile := filepath.Join(goldenRoot, "golden_digest.json")
	oracleAlive := func() bool { _, err := os.Stat(rustCLI); return err == nil }
	if !oracleAlive() && !freeze {
		if !againstGolden {
			fmt.Println("lexer_diff: oracle exe 不存在（已删区？）——自动切 --golden 基线模式")
			againstGolden = true
		}
	}
	if freeze && !oracleAlive() {
		fmt.Fprintln(os.Stderr, "lexer_diff: --freeze 需要 oracle exe")
		os.Exit(1)
	}

	rustOut, err := os.MkdirTemp("", "lexdiff_rust_*")
	must(err, "创建 Rust 输出目录")
	defer os.RemoveAll(rustOut)
	mbOut, err := os.MkdirTemp("", "lexdiff_mb_*")
	must(err, "创建 MoonBit 输出目录")
	defer os.RemoveAll(mbOut)

	// ① Rust oracle（digest 清单形态：freeze 产 hash 清单；golden 走独立比对）
	if freeze {
		runOrFail(exec.Command(rustCLI, "dump-tokens", corpus, "--out", rustOut, "--raw", "--pp"), rustCLI)
		doc := loadLexDigest(digestFile)
		doc.Sources[filepath.Base(corpus)] = corpusSHAs(corpus)
		n := 0
		for _, f := range listTSV(rustOut) {
			doc.TSVs[filepath.Base(corpus)+"/"+f] = fileSHA16(filepath.Join(rustOut, f))
			n++
		}
		writeLexDigest(digestFile, doc)
		fmt.Printf("lexer_diff freeze: digest 清单更新 %d TSV（%s 段）→ %s"+string(rune(10)), n, filepath.Base(corpus), digestFile)
		return
	}
	if againstGolden {
		os.Exit(runLexGolden(corpus, mbOut, digestFile))
	}
	runOrFail(exec.Command(rustCLI, "dump-tokens", corpus, "--out", rustOut, "--raw", "--pp"), rustCLI)
	// ② MoonBit
	runOrFail(exec.Command("moon", "-C", "moonbit", "run", "--target", "native",
		"cmd/dump_tokens", "--", corpus, mbOut, "both"), "moon run cmd/dump_tokens")

	// J9：对 MoonBit 侧第一个 TSV 注入差异，证明驱动会红
	if selftest {
		mutated := mutateFirstTSV(mbOut)
		fmt.Printf("[selftest] 已注入差异: %s（随后对拍必须 FAIL）\n", mutated)
	}

	// ③ 逐文件比对（golden 模式下 rustOut = golden 目录；跳过 _manifest.json）
	files := listTSV(rustOut)
	var cmpFiles []string
	for _, f := range files {
		if f == "_manifest.json" {
			continue
		}
		cmpFiles = append(cmpFiles, f)
	}
	files = cmpFiles
	leftLabel := "rust"
	if againstGolden {
		leftLabel = "golden"
	}
	if len(files) == 0 {
		fmt.Fprintln(os.Stderr, "lexer_diff: Rust/golden 侧产物为空——语料目录无 .c 文件或 dump 失败")
		os.Exit(1)
	}
	sort.Strings(files)
	mbFiles := listTSV(mbOut)
	mbSet := map[string]bool{}
	for _, f := range mbFiles {
		mbSet[f] = true
	}
	failures := 0
	for _, name := range files {
		if !mbSet[name] {
			fmt.Printf("DIFF 缺失: MoonBit 侧无 %s\n", name)
			failures++
			continue
		}
		a, errA := os.ReadFile(filepath.Join(rustOut, name))
		b, errB := os.ReadFile(filepath.Join(mbOut, name))
		if errA != nil || errB != nil {
			fmt.Printf("DIFF 读取失败: %s (%v / %v)\n", name, errA, errB)
			failures++
			continue
		}
		if !bytes.Equal(a, b) {
			fmt.Printf("DIFF %s:\n", name)
			printFirstDiff(a, b, leftLabel)
			failures++
		}
	}
	// 反向缺失：MoonBit 有 Rust 无（语料外产物泄漏）
	rustSet := map[string]bool{}
	for _, f := range files {
		rustSet[f] = true
	}
	for _, f := range mbFiles {
		if !rustSet[f] {
			fmt.Printf("DIFF 多余: Rust 侧无 %s\n", f)
			failures++
		}
	}
	if failures > 0 {
		fmt.Printf("lexer_diff: FAIL——%d 处差异（语料 %s）\n", failures, corpus)
		os.Exit(1)
	}
	fmt.Printf("lexer_diff: PASS——%d 个 TSV 逐字节一致（语料 %s）\n", len(files), corpus)
}

func runOrFail(cmd *exec.Cmd, label string) {
	out, err := cmd.CombinedOutput()
	if err != nil {
		fmt.Fprintf(os.Stderr, "lexer_diff: %s 执行失败: %v\n%s\n", label, err, out)
		os.Exit(1)
	}
}

func listTSV(dir string) []string {
	entries, err := os.ReadDir(dir)
	if err != nil {
		must(err, "读取输出目录")
	}
	var out []string
	for _, e := range entries {
		if filepath.Ext(e.Name()) == ".tsv" {
			out = append(out, e.Name())
		}
	}
	return out
}

func mutateFirstTSV(dir string) string {
	files := listTSV(dir)
	if len(files) == 0 {
		fmt.Fprintln(os.Stderr, "selftest: 无 TSV 可注入——前置步骤已失败")
		os.Exit(1)
	}
	sort.Strings(files)
	p := filepath.Join(dir, files[0])
	b, err := os.ReadFile(p)
	must(err, "selftest 读取")
	i := bytes.Index(b, []byte(selftestMutate))
	if i < 0 {
		fmt.Fprintln(os.Stderr, "selftest: 未找到注入点")
		os.Exit(1)
	}
	b[i+len(selftestMutate)] = '9' // count=N -> count=9（除非恰为 9，再兜底改下一字节）
	if b[i+len(selftestMutate)] == '9' && bytes.Contains(b[i:i+len(selftestMutate)+2], []byte("=9")) {
		b[i+len(selftestMutate)] = '7'
	}
	must(os.WriteFile(p, b, 0o644), "selftest 写回")
	return p
}

func printFirstDiff(a, b []byte, leftLabel string) {
	la := bytes.Split(a, []byte("\n"))
	lb := bytes.Split(b, []byte("\n"))
	n := len(la)
	if len(lb) > n {
		n = len(lb)
	}
	for i := 0; i < n; i++ {
		var x, y []byte
		if i < len(la) {
			x = la[i]
		}
		if i < len(lb) {
			y = lb[i]
		}
		if !bytes.Equal(x, y) {
			fmt.Printf("  行 %d:\n    rust:    %s\n    moonbit: %s\n", i+1, x, y)
			return
		}
	}
}

func must(err error, what string) {
	if err != nil {
		fmt.Fprintf(os.Stderr, "lexer_diff: %s 失败: %v\n", what, err)
		os.Exit(1)
	}
}

// ---- 工序③固化：digest 清单（聚合单文件；重刷 diff = 影响面清单） ----

type lexDigestDoc struct {
	Version int                          `json:"version"`
	Sources map[string]map[string]string `json:"sources"` // corpus → {name.c: sha8}
	TSVs    map[string]string            `json:"tsvs"`    // "corpus/name.tsv" → sha16
}

func loadLexDigest(p string) lexDigestDoc {
	d := lexDigestDoc{Version: 1, Sources: map[string]map[string]string{}, TSVs: map[string]string{}}
	if b, err := os.ReadFile(p); err == nil {
		if err := json.Unmarshal(b, &d); err != nil || d.Version != 1 {
			fmt.Fprintln(os.Stderr, "lexer_diff: digest 清单坏或版本不识", p)
			os.Exit(2)
		}
	}
	return d
}

func writeLexDigest(p string, d lexDigestDoc) {
	must(os.MkdirAll(filepath.Dir(p), 0o755), "建 golden 目录")
	data, _ := json.MarshalIndent(d, "", "  ")
	must(os.WriteFile(p, append(data, 10), 0o644), "写 digest 清单")
}

func fileSHA16(p string) string {
	b, err := os.ReadFile(p)
	if err != nil {
		return ""
	}
	return fmt.Sprintf("%x", sha256.Sum256(b))[:16]
}

// runLexGolden：mb TSV hash ↔ 清单比对（字段级 DIFF；全文兜底走 orphan 分支）。
func runLexGolden(corpus, mbOut, digestFile string) int {
	doc := loadLexDigest(digestFile)
	corpusName := filepath.Base(corpus)
	src, ok := doc.Sources[corpusName]
	if !ok {
		fmt.Fprintf(os.Stderr, "lexer_diff[golden]: 清单缺语料段 %s（先 --freeze）\n", corpusName)
		return 1
	}
	cur := corpusSHAs(corpus)
	if len(cur) != len(src) {
		fmt.Fprintf(os.Stderr, "lexer_diff[golden]: 语料 %s 文件数已变（现 %d ≠ 落盘 %d）——重跑 --freeze\n", corpusName, len(cur), len(src))
		return 1
	}
	for name, sha := range src {
		if cur[name] != sha {
			fmt.Fprintf(os.Stderr, "lexer_diff[golden]: 语料 %s 已变更而清单未重刷——重跑 --freeze\n", name)
			return 1
		}
	}
	runOrFail(exec.Command("moon", "-C", "moonbit", "run", "--target", "native",
		"cmd/dump_tokens", "--", corpus, mbOut, "both"), "moon run cmd/dump_tokens")
	failures := 0
	mbFiles := listTSV(mbOut)
	mbSet := map[string]bool{}
	for _, f := range mbFiles {
		mbSet[f] = true
	}
	matched := 0
	for name, want := range doc.TSVs {
		base := filepath.Base(name)
		if name[:len(name)-len(base)-1] != corpusName {
			continue
		}
		if !mbSet[base] {
			fmt.Printf("DIFF 缺失: MoonBit 侧无 %s\n", base)
			failures++
			continue
		}
		if got := fileSHA16(filepath.Join(mbOut, base)); got != want {
			fmt.Printf("DIFF %s: hash %s ≠ 清单 %s（全文对照见 frozen-oracle-snapshot 分支）\n", base, got, want)
			failures++
		} else {
			matched++
		}
	}
	for _, f := range mbFiles {
		if _, ok := doc.TSVs[corpusName+"/"+f]; !ok {
			fmt.Printf("DIFF 多余: 清单无 %s\n", corpusName+"/"+f)
			failures++
		}
	}
	if failures > 0 {
		fmt.Printf("lexer_diff[golden]: FAIL——%d 处差异（语料 %s）\n", failures, corpusName)
		return 1
	}
	fmt.Printf("lexer_diff[golden]: PASS——%d 个 TSV hash 与冻结基线一致（语料 %s）\n", matched, corpusName)
	return 0
}

func corpusSHAs(corpus string) map[string]string {
	out := map[string]string{}
	entries, err := os.ReadDir(corpus)
	must(err, "读语料目录")
	for _, e := range entries {
		if !strings.HasSuffix(e.Name(), ".c") {
			continue
		}
		b, err := os.ReadFile(filepath.Join(corpus, e.Name()))
		must(err, "读语料 "+e.Name())
		crlf := []byte{13, 10}
		lf := []byte{10}
		h := sha256.Sum256(bytes.ReplaceAll(b, crlf, lf))
		out[e.Name()] = fmt.Sprintf("%x", h)[:8]
	}
	return out
}
