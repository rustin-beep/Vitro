// gen_diag 生成 MoonBit vitro/engine/diag 包的机器单源部分。
//
// #39 真值源迁移（2026-10-05）：输入已从 Rust 冻结区 .rs 翻转为
// scripts/moonbit/diagnostics_data/{error_codes,catalog}.json 单源
// （E4xxx 309 码位按判定书保守全迁——C++ 死面摘除批再裁）。
// .rs 解析层保留为 **legacy 对账臂**（绞杀者纪律，gen_protocol_ts 先例）：
// 结构性对账（臂名码全等 + WARN/HINT 白名单 + 卡片码集合）；文案值
// （emoji/title/explanation/common_causes）不比——#27 与修复批的合法
// 演化面。`-export-json` 为 legacy → JSON 同步工具（删区后无源可导自然失效）。
//
// 纪律（第一阶段计划 T2）：
//   - ErrorCode 枚举禁手抄——本脚本是唯一产出口；
//   - fail loud：任何解析失配 / 白名单不对账 / 卡片数异常立即 exit 1，
//     禁静默 default；
//   - 幂等：同源重复运行产物字节一致（无时间戳；源 JSON sha256 前 8 位
//     随产物落款——源变则产物变，配合 -check 构成漂移防线）；
//   - -check：产物与现存文件逐字节比对，不一致 exit 1（CI 幂等锚）。
//
// 用法：
//
//	cd 仓库根 && go run ./scripts/moonbit/gen_diag                    # 生成 / 覆盖产物
//	cd 仓库根 && go run ./scripts/moonbit/gen_diag -check             # 校验产物未漂移
//	cd 仓库根 && go run ./scripts/moonbit/gen_diag -export-json       # legacy .rs → 两 JSON（同步工具）
//
// 输入（真源，#39 迁出冻结区）：
//   - scripts/moonbit/diagnostics_data/error_codes.json（137 臂 + source_sha 指纹）
//   - scripts/moonbit/diagnostics_data/catalog.json（77 卡片 + source_sha 指纹）
//
// legacy 对账源（Rust 冻结区只读，删区自动豁免）：
//   - ../native/crates/vitro_shared/src/error_codes.rs
//   - ../native/src/diagnostics/error_catalog/{lexer,parser,semantic,cpp}.rs
//
// 输出（MoonBit 活跃区）：
//   - diag/error_code_gen.mbt   （enum + code/severity/lang/name/display/all/from_code + 卡片码清单）
//   - diag/catalog_gen.mbt      （77 卡片 + catalog_of 穷尽 137 臂无兜底臂）
package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

const (
	expectedArms    = 137 // 计划 T2 基线：137 臂（2026-09-19 对源实测）
	expectedCatalog = 102 // 计划 T2 基线：catalog 77→102（#50 批③图标接线批 +25）
)

type arm struct {
	Name string `json:"name"` // Rust 变体名（如 E1001_UnknownChar）
	Code int    `json:"code"`
}

type entry struct {
	Code         int      `json:"code"`
	Icon         string   `json:"icon"`
	Title        string   `json:"title"`
	Explanation  string   `json:"explanation"`
	CommonCauses []string `json:"common_causes"`
}

// armNames 供 catalog 渲染按码取变体名（main 解析后填充）。
var armNames = map[int]string{}

func fatalf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "gen_diag: FAIL: "+format+"\n", args...)
	os.Exit(1)
}

func main() {
	// 迁址自 moonbit/scripts/（2026-09-21 审阅批四：包内容白名单清零——
	// Go 工具与内部清单不入 mooncakes 包）。脚本可从任意 cwd 调用，
	// 此处统一 chdir 到 moonbit/ 使既有相对路径（../native、moon fmt、
	// 产物目录）零改动。
	if err := os.Chdir("moonbit"); err != nil {
		fmt.Fprintf(os.Stderr, "须在仓库根运行（找不到 moonbit/）: %v\n", err)
		os.Exit(2)
	}
	check := flag.Bool("check", false, "只校验产物未漂移，不写入")
	exportJSON := flag.Bool("export-json", false, "从 legacy .rs 提取/同步两 JSON 真源（过渡期工具；删区后无源可导自然失效）")
	jsonDir := flag.String("json", "../scripts/moonbit/diagnostics_data", "JSON 真源目录（#39 迁出冻结区）")
	codesPath := flag.String("codes", "../native/crates/vitro_shared/src/error_codes.rs", "legacy 枚举源路径（对账臂/导出模式）")
	catalogDir := flag.String("catalog", "../native/src/diagnostics/error_catalog", "legacy 卡片源目录（对账臂/导出模式）")
	outDir := flag.String("out", "diag", "输出目录")
	flag.Parse()

	if *exportJSON {
		exportJSONFromLegacy(*codesPath, *catalogDir, *jsonDir)
		return
	}

	// ---- ① 装载 JSON 真源（#39 翻转，2026-10-05） ----
	// 行尾归一后取 sha：工作区 LF/CRLF 形态（git autocrlf、checkout 差异）
	// 不得影响产物落款——否则换行尾即 -check 假红。
	ecRaw, err := os.ReadFile(filepath.Join(*jsonDir, "error_codes.json"))
	if err != nil {
		fatalf("读 JSON 真源失败 error_codes.json: %v", err)
	}
	ecRaw = bytes.ReplaceAll(ecRaw, []byte("\r\n"), []byte("\n"))
	srcHash := fmt.Sprintf("%x", sha256.Sum256(ecRaw))[:8]

	catRaw, err := os.ReadFile(filepath.Join(*jsonDir, "catalog.json"))
	if err != nil {
		fatalf("读 JSON 真源失败 catalog.json: %v", err)
	}
	catRaw = bytes.ReplaceAll(catRaw, []byte("\r\n"), []byte("\n"))
	catalogHash := fmt.Sprintf("%x", sha256.Sum256(catRaw))[:8]

	arms := loadArms(ecRaw)
	if len(arms) != expectedArms {
		fatalf("枚举臂数 %d ≠ 基线 %d——JSON 真源已变更，请人工核对后更新 expectedArms 并登记差异", len(arms), expectedArms)
	}
	for _, a := range arms {
		armNames[a.Code] = a.Name
	}
	// 白名单不再独立入 JSON（纯派生数据——.rs 侧 WARN_CODES/HINT_CODES 与
	// 变体前缀集双向一致由 crossCheckWhitelists 实证）：按 W/H 前缀派生。
	wCodes, hCodes := deriveWhitelists(arms)

	entries := loadEntries(catRaw)
	if len(entries) != expectedCatalog {
		fatalf("卡片数 %d ≠ 基线 %d——JSON 真源已变更，请人工核对后更新 expectedCatalog 并登记差异", len(entries), expectedCatalog)
	}
	crossCheckCatalog(entries)

	genCode := renderErrorCode(arms, wCodes, hCodes, entries, srcHash)
	genCatalog := renderCatalog(entries, srcHash, catalogHash)

	writeProducts(*outDir, map[string]string{
		"error_code_gen.mbt": genCode,
		"catalog_gen.mbt":    genCatalog,
	}, *check)

	// ---- ② legacy 对账臂（结构性：臂名码全等 + 白名单 + 卡片码集合；值不比） ----
	legacyReconcileDiag(*codesPath, *catalogDir, arms, entries)

	if *check {
		fmt.Println("gen_diag: check OK（产物与 JSON 真源一致，2 文件未漂移）")
	} else {
		fmt.Println("gen_diag: 生成完成（2 文件）")
	}
}

// deriveWhitelists 按 W/H 变体名前缀派生白名单（Unknown 哨兵除外）。
func deriveWhitelists(arms []arm) (w, h []int) {
	for _, a := range arms {
		if a.Name == "Unknown" {
			continue
		}
		switch a.Name[0] {
		case 'W':
			w = append(w, a.Code)
		case 'H':
			h = append(h, a.Code)
		}
	}
	return w, h
}

// ---- 装载：diagnostics_data/ JSON 真源 ----

type armsDoc struct {
	SourceSHA string `json:"source_sha"` // 提取时 .rs 指纹（冻结元数据，不参与判定）
	Arms      []arm  `json:"arms"`
}

type catalogDoc struct {
	SourceSHA string  `json:"source_sha"`
	Entries   []entry `json:"entries"`
}

func loadArms(raw []byte) []arm {
	var d armsDoc
	if err := json.Unmarshal(raw, &d); err != nil {
		fatalf("error_codes.json 解析失败: %v", err)
	}
	seen := map[int]string{}
	for _, a := range d.Arms {
		if prev, dup := seen[a.Code]; dup {
			fatalf("编号 %d 重复：%s 与 %s", a.Code, prev, a.Name)
		}
		if !validVariantName(a.Name) {
			fatalf("臂名 %q 不符 E/W/H 前缀规范——JSON 真源形态可疑", a.Name)
		}
		seen[a.Code] = a.Name
	}
	return d.Arms
}

func loadEntries(raw []byte) []entry {
	var d catalogDoc
	if err := json.Unmarshal(raw, &d); err != nil {
		fatalf("catalog.json 解析失败: %v", err)
	}
	seen := map[int]bool{}
	for _, e := range d.Entries {
		if seen[e.Code] {
			fatalf("卡片码 %d 重复", e.Code)
		}
		seen[e.Code] = true
	}
	return d.Entries
}

// ---- 导出：legacy .rs → 两 JSON（初始提取 / 过渡期同步工具） ----

func exportJSONFromLegacy(codesPath, catalogDir, jsonDir string) {
	src, err := os.ReadFile(codesPath)
	if err != nil {
		fatalf("export: 读 legacy 枚举源失败 %s: %v", codesPath, err)
	}
	src = bytes.ReplaceAll(src, []byte("\r\n"), []byte("\n"))
	srcHash := fmt.Sprintf("%x", sha256.Sum256(src))[:8]

	arms := parseArms(string(src))
	wCodes, hCodes := parseWhitelists(string(src))
	crossCheckWhitelists(arms, wCodes, hCodes)
	entries := parseCatalog(catalogDir)

	if err := os.MkdirAll(jsonDir, 0o755); err != nil {
		fatalf("export: 建目录失败: %v", err)
	}
	writeJSONDoc(filepath.Join(jsonDir, "error_codes.json"), armsDoc{SourceSHA: srcHash, Arms: arms})
	writeJSONDoc(filepath.Join(jsonDir, "catalog.json"), catalogDoc{SourceSHA: catalogSourceHash(catalogDir), Entries: entries})
	fmt.Printf("gen_diag: export 完成（arms %d / entries %d → %s；重跑生成刷新产物落款）\n", len(arms), len(entries), jsonDir)
}

func writeJSONDoc(path string, doc any) {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	enc.SetIndent("", "  ")
	if err := enc.Encode(doc); err != nil {
		fatalf("export: JSON 序列化失败 %s: %v", path, err)
	}
	if err := os.WriteFile(path, buf.Bytes(), 0o644); err != nil {
		fatalf("export: 写 %s 失败: %v", path, err)
	}
	fmt.Printf("gen_diag: export Written: %s\n", path)
}

// ---- legacy 对账臂（结构性，非值级——同 gen_diagnostics 语义） ----

// legacyReconcileDiag：枚举臂名码全等 + WARN/HINT 白名单（.rs 独立声明）
// == JSON 臂前缀派生集 + 卡片码集合相等。emoji/title/explanation/
// common_causes 值不比——#27 与修复批的合法演化面（icon 同域，2026-10-07 emoji→icon）。三态：全在→对账；
// 全不在（工序④删区）→豁免；部分在→红（异常形态）。
func legacyReconcileDiag(codesPath, catalogDir string, arms []arm, entries []entry) {
	catalogFiles := []string{"lexer.rs", "parser.rs", "semantic.rs", "cpp.rs"}
	_, codesErr := os.Stat(codesPath)
	catalogPresent := 0
	for _, f := range catalogFiles {
		if _, err := os.Stat(filepath.Join(catalogDir, f)); err == nil {
			catalogPresent++
		}
	}
	codesPresent := codesErr == nil
	allPresent := codesPresent && catalogPresent == len(catalogFiles)
	nonePresent := !codesPresent && catalogPresent == 0
	switch {
	case nonePresent:
		fmt.Println("gen_diag: legacy 源已删区（工序④），对账臂豁免")
		return
	case !allPresent:
		fatalf("legacy 源部分存在（codes=%v catalog=%d/%d）——异常形态（删区应为一次性整目录），先排查再继续", codesPresent, catalogPresent, len(catalogFiles))
	}

	src, err := os.ReadFile(codesPath)
	if err != nil {
		fatalf("读 legacy 枚举源失败: %v", err)
	}
	src = bytes.ReplaceAll(src, []byte("\r\n"), []byte("\n"))
	lArms := parseArms(string(src))
	lW, lH := parseWhitelists(string(src))
	crossCheckWhitelists(lArms, lW, lH)
	lEntries := parseCatalog(catalogDir)

	var diffs []string
	// 臂面：名码全等（声明序即源序，直接逐位比）
	if len(lArms) != len(arms) {
		diffs = append(diffs, fmt.Sprintf("枚举臂数：JSON %d ↔ legacy %d", len(arms), len(lArms)))
	} else {
		for i := range arms {
			if arms[i].Name != lArms[i].Name || arms[i].Code != lArms[i].Code {
				diffs = append(diffs, fmt.Sprintf("枚举臂[%d]：JSON %s/%d ↔ legacy %s/%d（首个分叉）", i, arms[i].Name, arms[i].Code, lArms[i].Name, lArms[i].Code))
				break
			}
		}
	}
	// 白名单面：.rs 独立声明的 WARN/HINT == JSON 前缀派生集
	jW, jH := deriveWhitelists(arms)
	if !equalInts(jW, lW) {
		diffs = append(diffs, "WARN 白名单：JSON 派生集 ↔ legacy 声明集不一致")
	}
	if !equalInts(jH, lH) {
		diffs = append(diffs, "HINT 白名单：JSON 派生集 ↔ legacy 声明集不一致")
	}
	// 卡片面：码集合（值不比）
	if d := cmpCodeSets(entryCodes(entries), entryCodes(lEntries)); d != "" {
		diffs = append(diffs, "卡片码集合："+d)
	}

	if len(diffs) > 0 {
		fmt.Fprintln(os.Stderr, "gen_diag: FAIL: legacy 结构对账红（JSON 真源与 Rust oracle 骨架分叉）：")
		for _, d := range diffs {
			fmt.Fprintln(os.Stderr, "  - "+d)
		}
		fmt.Fprintln(os.Stderr, "处置：结构性变更须两侧同改（.rs 属防线维护）或确认后移除 legacy 臂；纯文案改动不应触发本红")
		os.Exit(1)
	}
	fmt.Println("gen_diag: legacy 结构对账 OK（Rust oracle 枚举+卡片骨架一致，删区后自动豁免）")
}

func entryCodes(entries []entry) []string {
	out := make([]string, len(entries))
	for i, e := range entries {
		out[i] = strconv.Itoa(e.Code)
	}
	return out
}

func cmpCodeSets(a, b []string) string {
	as := append([]string(nil), a...)
	bs := append([]string(nil), b...)
	sort.Strings(as)
	sort.Strings(bs)
	if len(as) != len(bs) {
		return fmt.Sprintf("条数 %d ≠ %d", len(as), len(bs))
	}
	for i := range as {
		if as[i] != bs[i] {
			return fmt.Sprintf("JSON[%s] ↔ legacy[%s]（首个分叉）", as[i], bs[i])
		}
	}
	return ""
}

// ---- 解析：error_codes.rs ----

func parseArms(src string) []arm {
	start := strings.Index(src, "pub enum ErrorCode {")
	if start < 0 {
		fatalf("未找到 pub enum ErrorCode 块")
	}
	end := strings.Index(src[start:], "\n}")
	if end < 0 {
		fatalf("enum 块未闭合")
	}
	body := src[start : start+end]
	var arms []arm
	seen := map[int]string{}
	for _, line := range strings.Split(body, "\n") {
		t := strings.TrimSpace(line)
		if t == "" || strings.HasPrefix(t, "//") {
			continue
		}
		eq := strings.Index(t, " = ")
		if eq < 0 || !strings.HasSuffix(t, ",") {
			continue
		}
		name := t[:eq]
		if !validVariantName(name) {
			continue
		}
		numStr := strings.TrimSuffix(t[eq+3:], ",")
		code, err := strconv.Atoi(numStr)
		if err != nil {
			fatalf("臂 %q 编号解析失败: %v", name, err)
		}
		if prev, dup := seen[code]; dup {
			fatalf("编号 %d 重复：%s 与 %s", code, prev, name)
		}
		seen[code] = name
		arms = append(arms, arm{Name: name, Code: code})
	}
	return arms
}

// validVariantName：E/W/H 前缀 + 4 位编号 + '_' + 名（如 E1001_UnknownChar），或 Unknown。
func validVariantName(name string) bool {
	if name == "Unknown" {
		return true
	}
	if len(name) < 7 || name[5] != '_' {
		return false
	}
	switch name[0] {
	case 'E', 'W', 'H':
	default:
		return false
	}
	for i := 1; i <= 4; i++ {
		if name[i] < '0' || name[i] > '9' {
			return false
		}
	}
	return name[6] != '_'
}

func parseWhitelists(src string) (w, h []int) {
	w, h = extractList(src, "WARN_CODES"), extractList(src, "HINT_CODES")
	if len(w) == 0 || len(h) == 0 {
		fatalf("WARN_CODES/HINT_CODES 白名单解析为空——源形态变更？")
	}
	return w, h
}

func extractList(src, name string) []int {
	marker := name + ": &[i32] = &["
	i := strings.Index(src, marker)
	if i < 0 {
		fatalf("未找到 %s 声明", name)
	}
	rest := src[i+len(marker):]
	end := strings.Index(rest, "]")
	if end < 0 {
		fatalf("%s 未闭合", name)
	}
	var out []int
	for _, part := range strings.Split(rest[:end], ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		v, err := strconv.Atoi(part)
		if err != nil {
			fatalf("%s 成员 %q 解析失败: %v", name, part, err)
		}
		out = append(out, v)
	}
	return out
}

// crossCheckWhitelists 复刻 Rust 侧 test_whitelist_matches_source_variants 语义：
// 白名单与变体名前缀双向一致——新增 W/H 码漏登记、或白名单腐化，立即红。
func crossCheckWhitelists(arms []arm, w, h []int) {
	var wVar, hVar []int
	for _, a := range arms {
		if a.Name == "Unknown" {
			continue
		}
		switch a.Name[0] {
		case 'W':
			wVar = append(wVar, a.Code)
		case 'H':
			hVar = append(hVar, a.Code)
		}
	}
	if !equalInts(w, wVar) {
		fatalf("W 白名单 %v 与 W 变体集 %v 不一致——漏登记的 W 码会静默显示 E 前缀（P3 伪造复发）", w, wVar)
	}
	if !equalInts(h, hVar) {
		fatalf("H 白名单 %v 与 H 变体集 %v 不一致", h, hVar)
	}
}

func equalInts(a, b []int) bool {
	sa, sb := append([]int{}, a...), append([]int{}, b...)
	sort.Ints(sa)
	sort.Ints(sb)
	if len(sa) != len(sb) {
		return false
	}
	for i := range sa {
		if sa[i] != sb[i] {
			return false
		}
	}
	return true
}

// ---- 解析：error_catalog/*.rs ----

func parseCatalog(dir string) []entry {
	files := []string{"lexer.rs", "parser.rs", "semantic.rs", "cpp.rs"}
	var entries []entry
	seen := map[int]bool{}
	for _, f := range files {
		path := filepath.Join(dir, f)
		src, err := os.ReadFile(path)
		if err != nil {
			fatalf("读卡片源失败 %s: %v", path, err)
		}
		src = bytes.ReplaceAll(src, []byte("\r\n"), []byte("\n")) // 解析层同归一（见 codesPath 处注释）
		for _, e := range parseEntryBlocks(string(src), f) {
			if seen[e.Code] {
				fatalf("卡片码 %d 重复（%s）", e.Code, f)
			}
			seen[e.Code] = true
			entries = append(entries, e)
		}
	}
	sort.Slice(entries, func(i, j int) bool { return entries[i].Code < entries[j].Code })
	return entries
}

// parseEntryBlocks 逐块提取 (code, ErrorInfo { ... })——大括号配对扫描
// （字符串字面量感知，块尾形态有 "}),", "},\\n)", "})\\n]" 三种，无法单点 Index）。
func parseEntryBlocks(src, from string) []entry {
	var out []entry
	for {
		i := strings.Index(src, "ErrorInfo {")
		if i < 0 {
			break
		}
		depth := 0
		end := -1
		for j := i + len("ErrorInfo "); j < len(src); j++ {
			c := src[j]
			if c == '"' {
				_, next := scanRustString(src, j)
				j = next - 1
				continue
			}
			if c == '{' {
				depth++
			} else if c == '}' {
				depth--
				if depth == 0 {
					end = j
					break
				}
			}
		}
		if end < 0 {
			fatalf("%s: ErrorInfo 块大括号未配对", from)
		}
		block := src[i : end+1]
		src = src[end+1:]
		out = append(out, entry{
			Code:         mustIntField(block, "code", from),
			Icon:         mustStrField(block, "icon", from),
			Title:        mustStrField(block, "title", from),
			Explanation:  mustStrField(block, "explanation", from),
			CommonCauses: mustStrArrayField(block, "common_causes", from),
		})
	}
	return out
}

func mustIntField(block, field, from string) int {
	i := strings.Index(block, field+":")
	if i < 0 {
		fatalf("%s: 块内缺字段 %s", from, field)
	}
	rest := strings.TrimSpace(block[i+len(field)+1:])
	end := strings.IndexAny(rest, ",}")
	if end < 0 {
		fatalf("%s: 字段 %s 无结束符", from, field)
	}
	v, err := strconv.Atoi(strings.TrimSpace(rest[:end]))
	if err != nil {
		fatalf("%s: 字段 %s 数值解析失败: %v", from, field, err)
	}
	return v
}

// scanRustString 从 s[pos]（须指向开引号）扫描一个 Rust 字符串字面量，
// 返回解码值与收尾下一位。
func scanRustString(s string, pos int) (string, int) {
	if pos >= len(s) || s[pos] != '"' {
		fatalf("扫描起点不是引号: %q", safeHead(s, pos))
	}
	var b strings.Builder
	for i := pos + 1; i < len(s); i++ {
		c := s[i]
		if c == '\\' && i+1 < len(s) {
			switch s[i+1] {
			case 'n':
				b.WriteByte('\n')
				i++ // 与 post 的 i++ 合计跳过转义对的 2 字节
			case 't':
				b.WriteByte('\t')
				i++
			case 'r':
				b.WriteByte('\r')
				i++
			case '"', '\\':
				b.WriteByte(s[i+1])
				i++
			case '\n':
				// Rust 续行转义：跳过换行与后续空白（semantic.rs 实存）。
				// 只推进到 j-1，post 的 i++ 恰落在续行后首字节——此前
				// 此 case 后又有统一 i++，双跳吞掉首字节（"向"丢 E5 实证，
				// E4 对拍 77 条唯一差异即此）。
				j := i + 2
				for j < len(s) && (s[j] == ' ' || s[j] == '	' || s[j] == '\r') {
					j++
				}
				i = j - 1
			default:
				fatalf("未处理的 Rust 转义 0x%02x @ %q", s[i+1], safeHead(s, pos))
			}
			continue
		}
		if c == '"' {
			return b.String(), i + 1
		}
		b.WriteByte(c)
	}
	fatalf("字符串未闭合")
	return "", 0
}

func safeHead(s string, pos int) string {
	head := s[pos:]
	if len(head) > 16 {
		head = head[:16]
	}
	return head
}

func mustStrField(block, field, from string) string {
	i := strings.Index(block, field+":")
	if i < 0 {
		fatalf("%s: 块内缺字段 %s", from, field)
	}
	pos := strings.IndexByte(block[i:], '"')
	if pos < 0 {
		fatalf("%s: 字段 %s 无字符串字面量", from, field)
	}
	v, _ := scanRustString(block, i+pos)
	return v
}

func mustStrArrayField(block, field, from string) []string {
	i := strings.Index(block, field+": &[")
	if i < 0 {
		fatalf("%s: 块内缺字段 %s", from, field)
	}
	rest := block[i+len(field)+3:]
	var out []string
	for {
		pos := strings.IndexByte(rest, '"')
		if pos < 0 {
			return out
		}
		v, next := scanRustString(rest, pos)
		out = append(out, v)
		rest = rest[next:]
		t := strings.TrimLeft(rest, " \t\n\r")
		if strings.HasPrefix(t, "]") {
			return out
		}
	}
}

func crossCheckCatalog(entries []entry) {
	for _, e := range entries {
		if _, ok := armNames[e.Code]; !ok {
			fatalf("卡片码 %d 不在 ErrorCode 枚举内——卡片源与枚举源失配", e.Code)
		}
	}
}

// ---- 渲染 ----

// escapeMbt 按 MoonBit 字符串字面量规则转义。
func escapeMbt(s string) string {
	var b strings.Builder
	for _, r := range s {
		switch r {
		case '\\':
			b.WriteString(`\\`)
		case '"':
			b.WriteString(`\"`)
		case '\n':
			b.WriteString(`\n`)
		case '\t':
			b.WriteString(`\t`)
		case '\r':
			b.WriteString(`\r`)
		default:
			b.WriteRune(r)
		}
	}
	return b.String()
}

func severityOf(a arm, wSet, hSet map[int]bool) string {
	switch {
	case wSet[a.Code]:
		return "Warning"
	case hSet[a.Code]:
		return "Hint"
	default:
		return "Error"
	}
}

func langOf(a arm) string {
	// 5xxx（C# 预留段）→ CSharp 先行落位；现库 137 码无 5xxx（审阅 P2-3）
	if a.Code >= 5000 {
		return "CSharp"
	}
	if a.Code >= 4000 {
		return "Cpp"
	}
	return "C"
}

func prefixOf(a arm, wSet, hSet map[int]bool) string {
	switch {
	case wSet[a.Code]:
		return "W"
	case hSet[a.Code]:
		return "H"
	default:
		return "E"
	}
}

func renderErrorCode(arms []arm, w, h []int, entries []entry, srcHash string) string {
	wSet, hSet := map[int]bool{}, map[int]bool{}
	for _, c := range w {
		wSet[c] = true
	}
	for _, c := range h {
		hSet[c] = true
	}
	entrySet := map[int]bool{}
	for _, e := range entries {
		entrySet[e.Code] = true
	}

	sorted := append([]arm{}, arms...)
	sort.Slice(sorted, func(i, j int) bool { return sorted[i].Code < sorted[j].Code })

	var b strings.Builder
	fmt.Fprintf(&b, "// @generated by scripts/moonbit/gen_diag —— 禁手改（git/diff 工具链按 @generated 识别；再生成：cd 仓库根 && go run ./scripts/moonbit/gen_diag）。\n"+
		"// 源：scripts/moonbit/diagnostics_data/error_codes.json（#39 迁出冻结区；sha256/%s）\n"+
		"// 基线：137 臂 / catalog 102 条（漂移时本脚本 fail loud）。\n\n"+
		"///|\n"+
		"/// 诊断错误码（137 臂，生成自 Rust oracle——禁手抄，T2 纪律）。\n"+
		"/// 段位：1xxx 词法 / 2xxx 语法 / 3xxx 语义 / 4xxx C++ 专属。\n"+
		"/// severity 由 W/H 白名单（与变体前缀双向对账）决定；lang 按 4xxx 段位。\n"+
		"pub(all) enum ErrorCode {\n", srcHash)
	for _, a := range sorted {
		fmt.Fprintf(&b, "  %s\n", a.Name)
	}
	b.WriteString("} derive(Debug, Eq, Hash, Compare)\n")

	// #54 A2：0079 显式提升声明（implicit_impl_as_method 将被工具链移除——
	// 短名形态零 moon.pkg 连坐；生成物侧由本模板单源）
	b.WriteString("\npub extend ErrorCode with Debug::{to_repr}\n" +
		"\npub extend ErrorCode with Eq::{not_equal, equal}\n" +
		"\npub extend ErrorCode with Hash::{hash, hash_combine}\n" +
		"\npub extend ErrorCode with Compare::{op_lt, op_le, op_ge, compare, op_gt}\n")

	b.WriteString("\n///|\n" +
		"/// 编号（穷尽 match，无下划线兜底——增删臂即编译红）。\n" +
		"pub fn ErrorCode::code(self : ErrorCode) -> Int {\n  match self {\n")
	for _, a := range sorted {
		fmt.Fprintf(&b, "    %s => %d\n", a.Name, a.Code)
	}
	b.WriteString("  }\n}\n")

	b.WriteString("\n///|\n" +
		"/// 严重级（穷尽；W 白名单 11 码 / H 白名单 1 码，生成时与变体前缀双向对账——\n" +
		"/// P3 语义单源：W/H 数值区间与 E 交织，不可按数值段判定）。\n" +
		"pub fn ErrorCode::severity(self : ErrorCode) -> Severity {\n  match self {\n")
	for _, a := range sorted {
		fmt.Fprintf(&b, "    %s => %s\n", a.Name, severityOf(a, wSet, hSet))
	}
	b.WriteString("  }\n}\n")

	b.WriteString("\n///|\n" +
		"/// 语言域（穷尽）：Cpp = 仅 C++ 形态触发（4xxx 段）；C = C 共通域\n" +
		"/// （C++ 中的 C 子集同样触发）。\n" +
		"pub fn ErrorCode::lang(self : ErrorCode) -> SourceLang {\n  match self {\n")
	for _, a := range sorted {
		fmt.Fprintf(&b, "    %s => %s\n", a.Name, langOf(a))
	}
	b.WriteString("  }\n}\n")

	b.WriteString("\n///|\n" +
		"/// 变体名（与 Rust 逐字一致——稳定标识，诊断序列差分锚的 key）。\n" +
		"pub fn ErrorCode::name(self : ErrorCode) -> String {\n  match self {\n")
	for _, a := range sorted {
		line := fmt.Sprintf("    %s => \"%s\"", a.Name, a.Name)
		if len(line) > 80 {
			// 与 moon fmt 折行规范一致（>80 列折值到下一行），避免 fmt 与 gen 互踩
			fmt.Fprintf(&b, "    %s =>\n      \"%s\"\n", a.Name, a.Name)
		} else {
			fmt.Fprintf(&b, "%s\n", line)
		}
	}
	b.WriteString("  }\n}\n")

	b.WriteString("\n///|\n" +
		"/// 显示码串（P3 段位前缀单源：E1001 / W3053 / H3057——与 Rust\n" +
		"/// code_prefix + 码值拼接同形）。\n" +
		"pub fn ErrorCode::display_code(self : ErrorCode) -> String {\n  match self {\n")
	for _, a := range sorted {
		fmt.Fprintf(&b, "    %s => \"%s%d\"\n", a.Name, prefixOf(a, wSet, hSet), a.Code)
	}
	b.WriteString("  }\n}\n")

	b.WriteString("\n///|\n" +
		"/// 全量清单（137，编号升序）——覆盖率断言与差分遍历的载体。\n" +
		"pub fn ErrorCode::all() -> Array[ErrorCode] {\n  [\n")
	for _, a := range sorted {
		fmt.Fprintf(&b, "    %s,\n", a.Name)
	}
	b.WriteString("  ]\n}\n")

	b.WriteString("\n///|\n" +
		"/// 编号 → 码；未知编号返回 None。\n" +
		"pub fn ErrorCode::from_code(value : Int) -> ErrorCode? {\n  match value {\n")
	for _, a := range sorted {
		fmt.Fprintf(&b, "    %d => Some(%s)\n", a.Code, a.Name)
	}
	b.WriteString("    _ => None\n  }\n}\n")

	var withC, withoutC []int
	for _, a := range sorted {
		if entrySet[a.Code] {
			withC = append(withC, a.Code)
		} else {
			withoutC = append(withoutC, a.Code)
		}
	}
	b.WriteString("\n///|\n" +
		"/// 有教学卡片的码清单（升序）。\n" +
		"pub fn catalog_codes() -> Array[Int] {\n  [\n" +
		wrapInts(withC) + "\n  ]\n}\n")
	b.WriteString("\n///|\n" +
		"/// 无卡片码清单（升序；含 Unknown=0）——「码无卡片」可断言清单（T2）。\n" +
		"pub fn codes_without_catalog() -> Array[Int] {\n  [\n" +
		wrapInts(withoutC) + "\n  ]\n}\n")
	return b.String()
}

// wrapInts 与 moon fmt 一致的 80 列贪心装行（前缀 4 空格，元素 "N," 逗号+空格分隔）。
func wrapInts(nums []int) string {
	var lines []string
	cur := "    "
	for _, n := range nums {
		tok := strconv.Itoa(n) + ","
		if cur != "    " && len(cur)+1+len(tok) > 84 {
			lines = append(lines, cur)
			cur = "    "
		}
		if cur == "    " {
			cur += tok
		} else {
			cur += " " + tok
		}
	}
	if cur != "    " {
		lines = append(lines, cur)
	}
	return strings.Join(lines, "\n")
}

// catalogSourceHash 四份卡片源（行尾归一后）的联合 sha256 前 8 位。
func catalogSourceHash(dir string) string {
	h := sha256.New()
	for _, f := range []string{"lexer.rs", "parser.rs", "semantic.rs", "cpp.rs"} {
		b, err := os.ReadFile(filepath.Join(dir, f))
		if err != nil {
			fatalf("读卡片源失败 %s: %v", f, err)
		}
		h.Write(bytes.ReplaceAll(b, []byte{13, 10}, []byte{10}))
	}
	return fmt.Sprintf("%x", h.Sum(nil))[:8]
}

func renderCatalog(entries []entry, srcHash string, catalogHash string) string {
	var b strings.Builder
	fmt.Fprintf(&b, "// @generated by scripts/moonbit/gen_diag —— 禁手改（git/diff 工具链按 @generated 识别；再生成：cd 仓库根 && go run ./scripts/moonbit/gen_diag）。\n"+
		"// 源：scripts/moonbit/diagnostics_data/{error_codes,catalog}.json（#39 迁出冻结区；枚举源 sha256/%s；卡片源 sha256/%s，行尾归一）\n"+
		"// 基线：77 条（漂移时本脚本 fail loud）。\n\n"+
		"///|\n"+
		"/// 教学卡片查询（穷尽 match 137 臂无下划线兜底；77 臂 Some、60 臂 None）。\n"+
		"/// 无卡片码是登记在案的缺口（codes_without_catalog），不是异常。\n"+
		"pub fn ErrorCode::catalog(self : ErrorCode) -> CatalogEntry? {\n  match self {\n", srcHash, catalogHash)
	entrySet := map[int]bool{}
	for _, e := range entries {
		entrySet[e.Code] = true
		// 爆开形态与 moon fmt 输出逐字节一致：fmt 宽度按 UTF-8 字节计
		// （中文 3 字节），causes 整行 >84 字节即爆开（元素并排不再折，
		// 字符串字面量不可折）；Some(CatalogEntry::of(...)) 全参数逐行。
		causes := causesLit(e.CommonCauses)
		causesLine := "          [" + causes + "],"
		var causesForm string
		if len(causesLine) <= 84 {
			causesForm = causesLine
		} else {
			causesForm = "          [\n            " + causes + ",\n          ],"
		}
		fmt.Fprintf(&b, "    %s =>\n      Some(\n        CatalogEntry::of(\n          %d,\n          \"%s\",\n          \"%s\",\n          \"%s\",\n%s\n        ),\n      )\n",
			armNames[e.Code], e.Code, escapeMbt(e.Icon), escapeMbt(e.Title), escapeMbt(e.Explanation), causesForm)
	}
	// 无卡片臂显式列 None（无兜底臂纪律：增删枚举臂即编译红）
	var noneCodes []int
	for code := range armNames {
		if !entrySet[code] {
			noneCodes = append(noneCodes, code)
		}
	}
	sort.Ints(noneCodes)
	for _, code := range noneCodes {
		fmt.Fprintf(&b, "    %s => None\n", armNames[code])
	}
	b.WriteString("  }\n}\n")
	return b.String()
}

func causesLit(causes []string) string {
	var parts []string
	for _, c := range causes {
		parts = append(parts, "\""+escapeMbt(c)+"\"")
	}
	return strings.Join(parts, ", ")
}

// ---- 写出 / 校验 ----

// writeProducts 写出全部产物并经 moon fmt 规范化（gen 与 fmt 不得互踩：
// 最终形态一律以 moon fmt 输出为准——gen 原始输出仅是中间态）。
// check 模式：写盘 → fmt → 与先前内容逐字节比对，不一致则还原并红。
// productItem：产物路径与其 check 模式开场保存的原内容。
type productItem struct {
	path string
	cur  []byte
}

func writeProducts(dir string, products map[string]string, check bool) {
	var items []productItem
	for name, content := range products {
		path := filepath.Join(dir, name)
		var cur []byte
		if check {
			var err error
			cur, err = os.ReadFile(path)
			if err != nil {
				fatalf("-check: 读产物失败 %s: %v", path, err)
			}
		}
		if err := os.MkdirAll(dir, 0o755); err != nil {
			fatalf("建目录失败 %s: %v", dir, err)
		}
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			fatalf("写产物失败 %s: %v", path, err)
		}
		items = append(items, productItem{path, cur})
	}
	// 统一 fmt（一次调用，路径按字典序稳定）
	sort.Slice(items, func(i, j int) bool { return items[i].path < items[j].path })
	args := []string{"fmt"}
	for _, it := range items {
		args = append(args, it.path)
	}
	if out, err := runMoon(args...); err != nil {
		restoreItems(items)
		fatalf("moon fmt 失败（moon 须在 PATH）: %v\n%s", err, out)
	}
	if !check {
		return
	}
	// 全部比对完再统一还原+报红：逐个还原遇红即停会让后续产物停留在
	// fmt 形态未还原（部分还原副作用，违反「check 不留副作用」契约——
	// 2026-09-26 审阅批随 gen_host_route P1-1 同步修复）。
	var drifted []string
	for _, it := range items {
		now, err := os.ReadFile(it.path)
		if err != nil {
			restoreItems(items)
			fatalf("-check: 回读产物失败 %s: %v", it.path, err)
		}
		// 行尾归一后比对：core.autocrlf=true 的 checkout 会给产物 CRLF，
		// 而 gen 写 LF——不归一则假红且文案误报"源已变更"（审阅 P2-1，
		// 与源侧 srcHash 归一同理；.gitattributes 另行锁 moonbit/** 为 LF）。
		nowLF := bytes.ReplaceAll(now, []byte{13, 10}, []byte{10})
		curLF := bytes.ReplaceAll(it.cur, []byte{13, 10}, []byte{10})
		if !bytes.Equal(nowLF, curLF) {
			drifted = append(drifted, it.path)
		}
	}
	if len(drifted) > 0 {
		restoreItems(items)
		fatalf("-check: 产物漂移 %s——源已变更未再生成（cd 仓库根 && go run ./scripts/moonbit/gen_diag）", strings.Join(drifted, ", "))
	}
}

// restoreItems 还原 check 模式开场保存的原产物内容（失败路径不留覆盖副作用）。
func restoreItems(items []productItem) {
	for _, it := range items {
		if len(it.cur) > 0 {
			_ = os.WriteFile(it.path, it.cur, 0o644)
		}
	}
}

func runMoon(args ...string) (string, error) {
	cmd := exec.Command("moon", args...)
	var buf bytes.Buffer
	cmd.Stdout = &buf
	cmd.Stderr = &buf
	err := cmd.Run()
	return buf.String(), err
}
