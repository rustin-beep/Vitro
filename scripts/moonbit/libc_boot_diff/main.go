// libc_boot_diff：libc 自举对拍闸（S5 尾项『libc 自举』）。
//
// 命题：**MoonBit 引擎能否编译自己的标准库 C 源，且产物与 Rust oracle 一致**。
// 这是"自举"的机器判据——不是"能跑通"，是"逐字节一致"。
//
// 用法（**仓库根**）：
//
//	go run ./scripts/moonbit/libc_boot_diff            # 对拍 native/runtime_libc/src
//	go run ./scripts/moonbit/libc_boot_diff --selftest # J9：注入差异必红
//
// 为什么两侧形态不同、却仍能逐字节比：
//   - Rust 侧 `vitro_cli export <src> -o <out> --builtin-libc`（vitro_cli.rs:275）
//     的口径是「注入 stub main → 编译 → 过滤」三段式：
//     ① 追加 stub unit `int main() { return 0; }`（BytecodeGen 要求 main）
//     ② code[0] 若为 Jump（入口 wrapper）→ 记 operand 为 wrapper_ip，截断 code
//     ③ code[0] 置 Nop
//     ④ func_table / func_index 删 "main"
//     ⑤ --builtin-libc：删 func_index 中「在 BYTECODE_LIBC_ALL_FUNCS 但不在
//        func_table」的预注册项
//   - MoonBit 侧以 `dump_compile --library` 编译同样的 <源 + stub>：
//     library mode 不预注册固定索引段、全局偏移自 0 起 —— 这正是 ⑤ 在
//     Rust 侧靠"删预注册项"达成的同一语义（两侧 `with_mode` 都只改这两个初值）。
//     本驱动再对 MoonBit 产物做 ②③④ 同等过滤，然后投影到**交集字段**比对。
//
// 已知唯一的注入口径坑：stub 必须**直接接在主源末尾换行之后**（不前插空行）
// ——Rust 的多 unit 拼接等价于 `src1 + src2`，前插空行会让 stub 区指令的
// loc.line 差 1（实测踩过，非引擎差异）。
//
// 判定：交集字段（rules.json 的 compare_fields）经键排序 + 归一器归一后
// 逐字节相等 → SAME；任一字段不同 → DIFF（真红）；任一侧编译失败 → FAIL。
// 空集不得绿：源目录无 .c、或某侧零产物 → 直接红。
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	canon "vitro/scripts/internal/canonicalize"
)

const rulesPath = "scripts/moonbit/libc_boot_diff/rules.json"

type rulesDoc struct {
	Schema        int      `json:"schema"`
	SrcDir        string   `json:"src_dir"`
	StubSource    string   `json:"stub_source"`
	CompareFields []string `json:"compare_fields"`
}

// pair：单个源文件的两侧产物（MoonBit 侧已按 export 口径过滤）。
type pair struct {
	name      string
	moonOK    bool
	moonRaw   json.RawMessage
	rustRaw   json.RawMessage
	rustOK    bool
	wrapperIP int
}

func main() {
	selftest := false
	for _, a := range os.Args[1:] {
		switch a {
		case "--selftest":
			selftest = true
		default:
			fatal("未知参数: %s（可用：--selftest）", a)
		}
	}
	rd := loadRules()

	if !fileExists(filepath.FromSlash(rd.SrcDir)) {
		fatal("源目录不存在（须在仓库根运行）: %s", rd.SrcDir)
	}
	files := listC(rd.SrcDir)
	if len(files) == 0 {
		fatal("源目录无 .c 文件: %s", rd.SrcDir)
	}
	fmt.Printf("libc_boot_diff: 对拍 %s（%d 个 C 源）\n", rd.SrcDir, len(files))

	work, err := os.MkdirTemp("", "libc_boot_*")
	if err != nil {
		fatal("临时目录失败: %v", err)
	}
	defer os.RemoveAll(work)

	stubDir := filepath.Join(work, "src")
	if err := os.MkdirAll(stubDir, 0o755); err != nil {
		fatal("建目录失败: %v", err)
	}
	for _, f := range files {
		body, err := os.ReadFile(f)
		if err != nil {
			fatal("读源失败 %s: %v", f, err)
		}
		// 关键：直接拼接（不插入额外分隔），与 Rust 多 unit 拼接口径一致
		out := append(append([]byte(nil), body...), []byte(rd.StubSource)...)
		if err := os.WriteFile(filepath.Join(stubDir, filepath.Base(f)), out, 0o644); err != nil {
			fatal("写 stub 源失败: %v", err)
		}
	}

	moonDir := filepath.Join(work, "moon")
	runMoon(stubDir, moonDir)

	// 装载两侧产物（先全部读入，selftest 需要基线判定后再注入）
	pairs := make([]pair, 0, len(files))
	ok := true
	for _, f := range files {
		base := filepath.Base(f)
		p := pair{name: base}

		raw, err := os.ReadFile(filepath.Join(moonDir, base+".compile.json"))
		if err != nil {
			fmt.Printf("  FAIL %s: MoonBit 侧无产物（%v）\n", base, err)
			ok = false
			pairs = append(pairs, p)
			continue
		}
		var md struct {
			OK   bool            `json:"ok"`
			Dump json.RawMessage `json:"dump"`
			Err  json.RawMessage `json:"errors"`
		}
		if err := json.Unmarshal(raw, &md); err != nil {
			fmt.Printf("  FAIL %s: MoonBit 输出解析失败（%v）\n", base, err)
			ok = false
			pairs = append(pairs, p)
			continue
		}
		if !md.OK {
			fmt.Printf("  FAIL %s: MoonBit 编译失败 %s\n", base, preview(md.Err))
			ok = false
			pairs = append(pairs, p)
			continue
		}
		filtered, wrap, err := filterExport(md.Dump)
		if err != nil {
			fmt.Printf("  FAIL %s: MoonBit 产物过滤失败（%v）\n", base, err)
			ok = false
			pairs = append(pairs, p)
			continue
		}
		p.moonOK, p.moonRaw, p.wrapperIP = true, filtered, wrap

		rustPath := filepath.Join(work, strings.TrimSuffix(base, ".c")+".rust.json")
		runRustExport(f, rustPath)
		rb, err := os.ReadFile(rustPath)
		if err != nil || len(rb) == 0 {
			fmt.Printf("  FAIL %s: Rust export 无产物\n", base)
			ok = false
			pairs = append(pairs, p)
			continue
		}
		p.rustOK, p.rustRaw = true, rb
		pairs = append(pairs, p)
	}

	if !ok {
		fmt.Println("libc_boot_diff: FAIL——任一侧缺产物（见上）")
		os.Exit(1)
	}

	// 基线判定
	nSame, nDiff := 0, 0
	var firstDiff string
	for i := range pairs {
		p := &pairs[i]
		same, detail, err := comparePair(*p, rd.CompareFields)
		if err != nil {
			fatal("比对 %s 失败: %v", p.name, err)
		}
		if same {
			nSame++
			fmt.Printf("  SAME %s（code=%d 条；wrapper_ip=%d）\n", p.name, countCode(p.moonRaw), p.wrapperIP)
		} else {
			nDiff++
			if firstDiff == "" {
				firstDiff = p.name
			}
			fmt.Printf("  DIFF %s\n%s\n", p.name, detail)
		}
	}
	fmt.Printf("libc_boot_diff: SAME=%d DIFF=%d（%d 源）\n", nSame, nDiff, len(pairs))

	if selftest {
		os.Exit(selftestRun(pairs, rd.CompareFields, nDiff == 0))
	}
	if nDiff > 0 {
		fmt.Println("libc_boot_diff: FAIL——自举产物与 oracle 不一致（真红）")
		os.Exit(1)
	}
	fmt.Println("libc_boot_diff: PASS——MoonBit library mode 产物与 Rust export 交集字段逐字节一致")
}

// selftestRun：J9 埋雷。先确认基线全绿（否则注入后的红无法归因），再对
// 首个样本注入「code[1].operand +1」，必须由绿转红。
func selftestRun(pairs []pair, fields []string, baselineGreen bool) int {
	if !baselineGreen {
		fmt.Println("libc_boot_diff: selftest ABORT——基线不绿，注入后的红无法归因")
		return 2
	}
	if len(pairs) == 0 {
		fmt.Println("libc_boot_diff: selftest ABORT——无样本")
		return 2
	}
	p := pairs[0]
	injected, ok := injectOperand(p.moonRaw)
	if !ok {
		fmt.Println("libc_boot_diff: selftest ABORT——注入失败（样本 code 段不足 2 条或 operand 非数值）")
		return 2
	}
	p.moonRaw = injected
	same, _, err := comparePair(p, fields)
	if err != nil {
		fatal("selftest 比对失败: %v", err)
	}
	fmt.Printf("libc_boot_diff: selftest 已注入——%s 的 code[1].operand +1\n", p.name)
	if same {
		fmt.Println("libc_boot_diff: selftest FAIL——注入后仍判绿，闸门失效")
		return 1
	}
	fmt.Println("libc_boot_diff: selftest PASS——注入差异被捕获（红），J9 证红成立")
	return 0
}

// comparePair：投影到交集字段 → 键排序 → 归一器归一 → 逐字节比较。
func comparePair(p pair, fields []string) (bool, string, error) {
	moonProj, err := project(p.moonRaw, fields)
	if err != nil {
		return false, "", fmt.Errorf("moon 投影: %w", err)
	}
	rustProj, err := project(p.rustRaw, fields)
	if err != nil {
		return false, "", fmt.Errorf("rust 投影: %w", err)
	}
	a, err := canon.Bytes(rustProj)
	if err != nil {
		return false, "", fmt.Errorf("rust 归一: %w", err)
	}
	b, err := canon.Bytes(moonProj)
	if err != nil {
		return false, "", fmt.Errorf("moon 归一: %w", err)
	}
	if bytes.Equal(a, b) {
		return true, "", nil
	}
	// 逐字段定位差异（报告可读性）
	var detail strings.Builder
	var ra, rb map[string]json.RawMessage
	_ = json.Unmarshal(a, &ra)
	_ = json.Unmarshal(b, &rb)
	var keys []string
	for k := range ra {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		x, err1 := canon.Bytes(ra[k])
		y, err2 := canon.Bytes(rb[k])
		if err1 != nil || err2 != nil {
			continue
		}
		if !bytes.Equal(x, y) {
			fmt.Fprintf(&detail, "    [%s] 两侧不同（rust %d 字节 / moon %d 字节）\n", k, len(x), len(y))
			fmt.Fprintf(&detail, "        rust: %s\n", preview(x))
			fmt.Fprintf(&detail, "        moon: %s\n", preview(y))
		}
	}
	return false, detail.String(), nil
}

// project：只保留 fields 里的键（两侧产物形态不同，交集才是可比面）。
func project(raw json.RawMessage, fields []string) ([]byte, error) {
	var m map[string]json.RawMessage
	if err := json.Unmarshal(raw, &m); err != nil {
		return nil, err
	}
	out := map[string]json.RawMessage{}
	for _, f := range fields {
		if v, has := m[f]; has {
			out[f] = v
		}
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("投影后无字段（compare_fields 与产物键全不匹配）")
	}
	return json.Marshal(out)
}

// filterExport：按 Rust export 口径过滤 MoonBit dump——
//
//	① code[0] 为 Jump → 记 wrapper_ip，截断 code 到 wrapper_ip
//	② code[0] 置 Nop
//	③ func_table / func_index 删 main
//
// 全部在 RawMessage 层操作（大整数位模式不失真）。
func filterExport(dump json.RawMessage) (json.RawMessage, int, error) {
	var m map[string]json.RawMessage
	if err := json.Unmarshal(dump, &m); err != nil {
		return nil, -1, err
	}
	codeRaw, hasCode := m["code"]
	if !hasCode {
		return nil, -1, fmt.Errorf("产物无 code 字段")
	}
	var code []json.RawMessage
	if err := json.Unmarshal(codeRaw, &code); err != nil {
		return nil, -1, fmt.Errorf("code 解析失败: %w", err)
	}
	wrapperIP := -1
	if len(code) > 0 {
		var ins map[string]json.RawMessage
		if err := json.Unmarshal(code[0], &ins); err == nil {
			var op string
			if err := json.Unmarshal(ins["op"], &op); err == nil && strings.Contains(op, "Jump") {
				var operand float64
				if err := json.Unmarshal(ins["operand"], &operand); err == nil {
					wrapperIP = int(operand)
				}
			}
		}
	}
	if wrapperIP >= 0 && wrapperIP <= len(code) {
		code = code[:wrapperIP]
	}
	if len(code) > 0 {
		var ins map[string]json.RawMessage
		if err := json.Unmarshal(code[0], &ins); err != nil {
			return nil, -1, fmt.Errorf("code[0] 解析失败: %w", err)
		}
		ins["op"] = json.RawMessage(`"Nop"`)
		ins["operand"] = json.RawMessage(`0`)
		b, err := json.Marshal(ins)
		if err != nil {
			return nil, -1, err
		}
		code[0] = b
	}
	cb, err := json.Marshal(code)
	if err != nil {
		return nil, -1, err
	}
	m["code"] = cb

	for _, k := range []string{"func_table", "func_index"} {
		var mp map[string]json.RawMessage
		if err := json.Unmarshal(m[k], &mp); err != nil {
			continue
		}
		delete(mp, "main")
		b, err := json.Marshal(mp)
		if err != nil {
			return nil, -1, err
		}
		m[k] = b
	}
	out, err := json.Marshal(m)
	if err != nil {
		return nil, -1, err
	}
	return out, wrapperIP, nil
}

// injectOperand：code[1].operand +1（selftest 用；code[0] 已是 Nop，取 [1]
// 避开 wrapper 位置语义）。
func injectOperand(dump json.RawMessage) (json.RawMessage, bool) {
	var m map[string]json.RawMessage
	if err := json.Unmarshal(dump, &m); err != nil {
		return dump, false
	}
	var code []json.RawMessage
	if err := json.Unmarshal(m["code"], &code); err != nil || len(code) < 2 {
		return dump, false
	}
	var ins map[string]json.RawMessage
	if err := json.Unmarshal(code[1], &ins); err != nil {
		return dump, false
	}
	var op float64
	if err := json.Unmarshal(ins["operand"], &op); err != nil {
		return dump, false
	}
	ins["operand"] = json.RawMessage(strconv.Itoa(int(op) + 1))
	b, err := json.Marshal(ins)
	if err != nil {
		return dump, false
	}
	code[1] = b
	cb, err := json.Marshal(code)
	if err != nil {
		return dump, false
	}
	m["code"] = cb
	out, err := json.Marshal(m)
	if err != nil {
		return dump, false
	}
	return out, true
}

// ---------------------------------------------------------------------------
// 外部调用
// ---------------------------------------------------------------------------

func runMoon(stubDir, outDir string) {
	cmd := exec.Command("moon", "run", "--target", "native", "cmd/dump_compile",
		"--", stubDir, outDir, "--library")
	cmd.Dir = "moonbit"
	var buf bytes.Buffer
	cmd.Stdout = &buf
	cmd.Stderr = &buf
	if err := cmd.Run(); err != nil {
		fatal("moon dump_compile --library 失败: %v\n%s", err, buf.String())
	}
}

var rustCLIOnce string

func rustCLI() string {
	if rustCLIOnce != "" {
		return rustCLIOnce
	}
	for _, p := range []string{
		filepath.Join("native", "target", "release", "vitro_cli.exe"),
		filepath.Join("native", "target", "release", "vitro_cli"),
	} {
		if fileExists(p) {
			rustCLIOnce = p
			return p
		}
	}
	fatal("未找到 vitro_cli release 二进制（先 cargo build --release --bin vitro_cli）")
	return ""
}

func runRustExport(src, out string) {
	cmd := exec.Command(rustCLI(), "export", src, "-o", out, "--builtin-libc")
	var buf bytes.Buffer
	cmd.Stdout = &buf
	cmd.Stderr = &buf
	if err := cmd.Run(); err != nil {
		fatal("vitro_cli export 失败 %s: %v\n%s", src, err, buf.String())
	}
}

// ---------------------------------------------------------------------------
// 基础设施
// ---------------------------------------------------------------------------

func loadRules() rulesDoc {
	raw, err := os.ReadFile(rulesPath)
	if err != nil {
		fatal("读规则失败（须在仓库根运行）: %v", err)
	}
	var rd rulesDoc
	if err := json.Unmarshal(raw, &rd); err != nil {
		fatal("规则解析失败: %v", err)
	}
	if rd.Schema != 1 {
		fatal("规则 schema 不支持: %d（期望 1）", rd.Schema)
	}
	if len(rd.CompareFields) == 0 {
		fatal("规则缺 compare_fields")
	}
	return rd
}

func listC(dir string) []string {
	ents, err := os.ReadDir(filepath.FromSlash(dir))
	if err != nil {
		fatal("读源目录失败 %s: %v", dir, err)
	}
	var out []string
	for _, e := range ents {
		if !e.IsDir() && strings.HasSuffix(e.Name(), ".c") {
			out = append(out, filepath.Join(filepath.FromSlash(dir), e.Name()))
		}
	}
	sort.Strings(out)
	return out
}

func countCode(raw json.RawMessage) int {
	var m map[string]json.RawMessage
	if err := json.Unmarshal(raw, &m); err != nil {
		return -1
	}
	var code []json.RawMessage
	if err := json.Unmarshal(m["code"], &code); err != nil {
		return -1
	}
	return len(code)
}

func fileExists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}

func preview(b []byte) string {
	s := string(b)
	if len(s) > 160 {
		return s[:160] + "…"
	}
	return s
}

func fatal(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "libc_boot_diff: "+format+"\n", args...)
	os.Exit(2)
}
