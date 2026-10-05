// gen_diagnostics 生成 MoonBit vitro/engine/diagnostics 包的数据层四件
// （A3 fix 载荷 / A4+A5 概念图 / A6 误区模式 / A7 学习路径）。
//
// #39 真值源迁移（2026-10-05）：输入已从 Rust 冻结区 .rs 翻转为
// scripts/moonbit/diagnostics_data/ 四 JSON 单源（原为双产物输出面，
// 现为真源——退役后修复批改文案的落笔处）。.rs 解析层保留为
// **legacy 对账臂**（绞杀者纪律，gen_protocol_ts 先例）：
//   - 结构性对账（非值级）——「行为/引用参数 = 骨架，文案 = 值」：
//   - 骨架（比）：码位 / 条目 id / 边三元组 / 映射键+值列表 / 节点→卡片
//     引用映射（per-node）/ fix 的 fix_kind+anchor（应用行为）/ 模式
//     检测阈值 min_occurrences+time_window / step 的 step_type 序列 +
//     target_id+highlight_lines（教学路由引用）
//   - 值级（不比）：suggestion/title/detail/description/name 文案、
//     emoji、strength 权重（F6 f32 登记在案）、difficulty——修复批
//     （工序②后、工序④前的窗口）只改 JSON 值是合法演化，值级臂会
//     挡住修复批正道（结构即 oracle 对拍防线依赖的骨架，值是呈现面）；
//   - 冻结区四 .rs 全存在 → 对账；全不存在（工序④删区）→ 自动豁免；
//     部分存在 → 红（异常形态，删区是一次性整目录操作）。
//
// 契约（同 gen_diag，S8 diagnostics 批 2026-10-02；2026-10-05 翻转沿用）：
//   - fail loud：任何装载失配 / 基线计数漂移 / legacy 结构分叉立即 exit 1，
//     禁静默 default；
//   - 幂等：同源重复运行产物字节一致；四 JSON 文件（行尾归一）联合
//     sha256 前 8 位随产物落款——JSON 变则产物变，-check 漂移防线
//     语义不变；
//   - 数据/机制分列（勘察 §2.0 A3 拆分判据）：generate_fix 的**动态五码**
//     （1004/3035/3041/3050/3051——含坐标回搜 / 消息分支）不入表，
//     由机制层 fix_gen.mbt 手写照搬；表只装纯静态载荷。动态码集合
//     在 JSON 侧与白名单双向对账——增删动态码立即红。
//
// 用法：
//
//	cd 仓库根 && go run ./scripts/moonbit/gen_diagnostics          # 生成 / 覆盖产物
//	cd 仓库根 && go run ./scripts/moonbit/gen_diagnostics -check   # 校验产物未漂移
//
// 输入（真源，#39 迁出冻结区）：
//   - scripts/moonbit/diagnostics_data/{fix_payloads,concepts,patterns,paths}.json
//     （source_sha 字段为 2026-10-05 提取时的 .rs 指纹，冻结元数据不再更新）
//
// 过渡对账源（legacy 臂，Rust 冻结区只读，删区自动豁免）：
//   - native/src/diagnostics/{error_catalog,knowledge_graph,misconception_patterns,learning_path}.rs
//
// 输出：
//   - moonbit/diagnostics/{fix_payloads,concepts,patterns,paths}_gen.mbt
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
	"regexp"
	"sort"
	"strconv"
	"strings"
)

// ---- 基线（对源实测 2026-10-02；源冻结期漂移即红，人工核对后更新并登记） ----
const (
	expectedStaticCodes = 25 // 静态载荷码数（3060|3061 双码展开计 2）
	expectedNodes       = 25
	expectedEdges       = 25
	expectedMapEntries  = 28
	expectedPatterns    = 6
	expectedPaths       = 6
)

// 动态码白名单（机制层 fix_gen.mbt 手写照搬——集合漂移即红）。
var dynamicCodeWhitelist = map[int]bool{
	1004: true, 3035: true, 3041: true, 3050: true, 3051: true,
}

type fixEntry struct {
	Code       int    `json:"code"`
	Suggestion string `json:"suggestion"`
	FixKind    int    `json:"fix_kind"`
	Anchor     string `json:"anchor"` // "Manual" | "LineEnd"
	Text       string `json:"text"`
}

type nodeEntry struct {
	ID             string   `json:"id"`
	Domain         string   `json:"domain"`
	Title          string   `json:"title"`
	Description    string   `json:"description"`
	Difficulty     int      `json:"difficulty"`
	RelatedCardIDs []string `json:"related_card_ids"`
}

type edgeEntry struct {
	From     string  `json:"from"`
	To       string  `json:"to"`
	Relation string  `json:"relation"`
	Strength float64 `json:"strength"`
}

type mapEntry struct {
	Code    int      `json:"code"`
	Concept []string `json:"concepts"`
}

type patternEntry struct {
	ID             string `json:"id"`
	Name           string `json:"name"`
	Description    string `json:"description"`
	ErrorCodes     []int  `json:"error_codes"`
	MinOccurrences int    `json:"min_occurrences"`
	TimeWindow     int    `json:"time_window"`
}

type stepEntry struct {
	StepType   string `json:"step_type"`
	Title      string `json:"title"`
	Detail     string `json:"detail"`
	TargetID   string `json:"target_id"`
	Highlights []int  `json:"highlight_lines"`
}

type pathEntry struct {
	ID      string      `json:"id"`
	Minutes int         `json:"estimated_time_minutes"`
	Steps   []stepEntry `json:"steps"`
}

func fatalf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "gen_diagnostics: FAIL: "+format+"\n", args...)
	os.Exit(1)
}

// ============ 装载：diagnostics_data/ JSON 真源（#39 翻转后输入） ============

type fixDoc struct {
	SourceSHA    string     `json:"source_sha"` // 提取时 .rs 指纹（冻结元数据，不参与判定）
	Entries      []fixEntry `json:"entries"`
	DynamicCodes []int      `json:"dynamic_codes"`
}

type conceptsDoc struct {
	SourceSHA       string      `json:"source_sha"`
	Nodes           []nodeEntry `json:"nodes"`
	Edges           []edgeEntry `json:"edges"`
	ErrorConceptMap []mapEntry  `json:"error_concept_map"`
}

type patternsDoc struct {
	SourceSHA string         `json:"source_sha"`
	Patterns  []patternEntry `json:"patterns"`
}

type pathsDoc struct {
	SourceSHA string      `json:"source_sha"`
	Paths     []pathEntry `json:"paths"`
}

func unmarshalDoc[T any](raw []byte, what string) T {
	var d T
	if err := json.Unmarshal(raw, &d); err != nil {
		fatalf("%s 解析失败: %v", what, err)
	}
	return d
}

func loadFixDoc(raw []byte) ([]fixEntry, map[int]bool) {
	d := unmarshalDoc[fixDoc](raw, "fix_payloads.json")
	dynamic := make(map[int]bool, len(d.DynamicCodes))
	for _, c := range d.DynamicCodes {
		dynamic[c] = true
	}
	return d.Entries, dynamic
}

func loadConceptsDoc(raw []byte) ([]nodeEntry, []edgeEntry, []mapEntry) {
	d := unmarshalDoc[conceptsDoc](raw, "concepts.json")
	return d.Nodes, d.Edges, d.ErrorConceptMap
}

func loadPatternsDoc(raw []byte) []patternEntry {
	return unmarshalDoc[patternsDoc](raw, "patterns.json").Patterns
}

func loadPathsDoc(raw []byte) []pathEntry {
	return unmarshalDoc[pathsDoc](raw, "paths.json").Paths
}

// ============ legacy 对账臂（结构性，非值级——头注语义说明） ============

// legacyReconcile：Rust 冻结区四 .rs 存在期间，其解析结果的**结构签名**必须
// 与 JSON 真源一致。结构签名 = 码位/条目 id/边三元组/映射键值/引用面——
// oracle 对拍防线依赖的骨架；文案值（suggestion/title/detail/…）不比，
// 那是修复批在 JSON 侧的合法演化面。三态：全在→对账；全不在→豁免；
// 部分在→红（异常形态——删区是一次性整目录操作，半删态只可能是事故）。
func legacyReconcile(srcDir string, fixes []fixEntry, dynamic map[int]bool, nodes []nodeEntry, edges []edgeEntry, conceptMap []mapEntry, patterns []patternEntry, paths []pathEntry) {
	legacyFiles := []string{"error_catalog.rs", "knowledge_graph.rs", "misconception_patterns.rs", "learning_path.rs"}
	present := 0
	for _, f := range legacyFiles {
		if _, err := os.Stat(filepath.Join(srcDir, f)); err == nil {
			present++
		} else if !os.IsNotExist(err) {
			fatalf("stat legacy 源 %s: %v", f, err)
		}
	}
	switch present {
	case 0:
		fmt.Println("gen_diagnostics: legacy 源已删区（工序④），对账臂豁免")
		return
	case len(legacyFiles):
		// 全在，走对账
	default:
		fatalf("legacy 源部分存在（%d/%d）——异常形态（删区应为一次性整目录），先排查再继续", present, len(legacyFiles))
	}

	var raws [][]byte
	for _, f := range legacyFiles {
		b, err := os.ReadFile(filepath.Join(srcDir, f))
		if err != nil {
			fatalf("读 legacy 源失败 %s: %v", f, err)
		}
		raws = append(raws, bytes.ReplaceAll(b, []byte("\r\n"), []byte("\n")))
	}
	lFixes, lDynamic := parseGenerateFix(string(raws[0]))
	lNodes, lEdges, lMap := parseKnowledgeGraph(string(raws[1]))
	lPatterns := parseMisconception(string(raws[2]))
	lPaths := parseLearningPath(string(raws[3]))

	var diffs []string
	// fix 面：静态码位 + 应用行为参数（fix_kind/anchor——行为参数 = 骨架） + 动态码集合
	if d := cmpStrSets("静态码位+应用行为", fixSigs(fixes), fixSigs(lFixes)); d != nil {
		diffs = append(diffs, d...)
	}
	if d := cmpStrSets("动态码位", boolKeys(dynamic), boolKeys(lDynamic)); d != nil {
		diffs = append(diffs, d...)
	}
	// 概念图骨架：节点 id / 边三元组 / 映射键+值 / 节点→卡片引用（per-node）
	if d := cmpStrSets("概念节点 id", nodeIDs(nodes), nodeIDs(lNodes)); d != nil {
		diffs = append(diffs, d...)
	}
	if d := cmpStrSets("概念边三元组", edgeSigs(edges), edgeSigs(lEdges)); d != nil {
		diffs = append(diffs, d...)
	}
	if d := cmpStrSets("错误码→概念映射", mapSigs(conceptMap), mapSigs(lMap)); d != nil {
		diffs = append(diffs, d...)
	}
	if d := cmpStrSets("节点→卡片引用", nodeCardSigs(nodes), nodeCardSigs(lNodes)); d != nil {
		diffs = append(diffs, d...)
	}
	// 误区模式骨架：id + error_codes + 检测阈值（行为参数 = 骨架）
	if d := cmpStrSets("误区模式 id", patternIDs(patterns), patternIDs(lPatterns)); d != nil {
		diffs = append(diffs, d...)
	}
	if d := cmpStrSets("误区模式码位+检测阈值", patternCodes(patterns), patternCodes(lPatterns)); d != nil {
		diffs = append(diffs, d...)
	}
	// 学习路径骨架：id + step_type 序列 + 教学路由引用（target_id/highlight_lines）
	if d := cmpStrSets("路径 id", pathIDs(paths), pathIDs(lPaths)); d != nil {
		diffs = append(diffs, d...)
	}
	if d := cmpStrSets("路径步骤序列+路由引用", pathStepSigs(paths), pathStepSigs(lPaths)); d != nil {
		diffs = append(diffs, d...)
	}

	if len(diffs) > 0 {
		fmt.Fprintln(os.Stderr, "gen_diagnostics: FAIL: legacy 结构对账红（JSON 真源与 Rust oracle 骨架分叉）：")
		for _, d := range diffs {
			fmt.Fprintln(os.Stderr, "  - "+d)
		}
		fmt.Fprintln(os.Stderr, "处置：结构性变更须两侧同改（.rs 属防线维护）或确认后移除 legacy 臂；纯文案改动不应触发本红")
		os.Exit(1)
	}
	fmt.Printf("gen_diagnostics: legacy 结构对账 OK（Rust oracle %d 文件骨架一致，删区后自动豁免）\n", len(legacyFiles))
}

// ---- 结构签名提取（两侧同函数，输出可排序字符串集） ----

func fixSigs(fixes []fixEntry) []string {
	out := make([]string, len(fixes))
	for i, e := range fixes {
		out[i] = fmt.Sprintf("%d:kind%d:%s", e.Code, e.FixKind, e.Anchor)
	}
	return out
}

func boolKeys(m map[int]bool) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, strconv.Itoa(k))
	}
	return out
}

func nodeIDs(nodes []nodeEntry) []string {
	out := make([]string, len(nodes))
	for i, n := range nodes {
		out[i] = n.ID
	}
	return out
}

func edgeSigs(edges []edgeEntry) []string {
	out := make([]string, len(edges))
	for i, e := range edges {
		out[i] = e.From + " ->" + e.To + " [" + e.Relation + "]"
	}
	return out
}

func mapSigs(m []mapEntry) []string {
	out := make([]string, len(m))
	for i, me := range m {
		cs := append([]string(nil), me.Concept...)
		sort.Strings(cs)
		out[i] = strconv.Itoa(me.Code) + ":" + strings.Join(cs, ",")
	}
	return out
}

// nodeCardSigs：节点→卡片引用映射（per-node 签名——比 bag 多重集强：
// 「A 节点丢了卡、B 节点补了同一张」的换位漂移 bag 抓不住）。
func nodeCardSigs(nodes []nodeEntry) []string {
	out := make([]string, len(nodes))
	for i, n := range nodes {
		cards := append([]string(nil), n.RelatedCardIDs...)
		sort.Strings(cards)
		out[i] = n.ID + "=" + strings.Join(cards, ",")
	}
	return out
}

func patternIDs(ps []patternEntry) []string {
	out := make([]string, len(ps))
	for i, p := range ps {
		out[i] = p.ID
	}
	return out
}

func patternCodes(ps []patternEntry) []string {
	var out []string
	for _, p := range ps {
		out = append(out, p.ID+"="+strconv.Itoa(len(p.ErrorCodes)))
		for _, c := range p.ErrorCodes {
			out = append(out, p.ID+":"+strconv.Itoa(c))
		}
		// 检测阈值（行为参数 = 骨架——变更即检测行为分叉）
		out = append(out, p.ID+fmt.Sprintf("@min%d:win%d", p.MinOccurrences, p.TimeWindow))
	}
	return out
}

func pathIDs(ps []pathEntry) []string {
	out := make([]string, len(ps))
	for i, p := range ps {
		out[i] = p.ID
	}
	return out
}

func pathStepSigs(ps []pathEntry) []string {
	var out []string
	for _, p := range ps {
		var steps []string
		for _, s := range p.Steps {
			hl := make([]string, len(s.Highlights))
			for i, v := range s.Highlights {
				hl[i] = strconv.Itoa(v)
			}
			steps = append(steps, s.StepType+"@"+s.TargetID+"["+strings.Join(hl, ",")+"]")
		}
		out = append(out, p.ID+"="+strings.Join(steps, ">"))
	}
	return out
}

// ---- 集合比对（双侧排序后逐位；返回 nil = 一致） ----

func cmpStrSets(what string, a, b []string) []string {
	as := append([]string(nil), a...)
	bs := append([]string(nil), b...)
	sort.Strings(as)
	sort.Strings(bs)
	if len(as) != len(bs) {
		return []string{fmt.Sprintf("%s：条数 %d ≠ %d", what, len(as), len(bs))}
	}
	for i := range as {
		if as[i] != bs[i] {
			return []string{fmt.Sprintf("%s：JSON[%q] ↔ legacy[%q]（首个分叉，后续省略）", what, as[i], bs[i])}
		}
	}
	return nil
}

func main() {
	if err := os.Chdir("moonbit"); err != nil {
		fmt.Fprintf(os.Stderr, "须在仓库根运行（找不到 moonbit/）: %v\n", err)
		os.Exit(2)
	}
	check := flag.Bool("check", false, "只校验产物未漂移，不写入")
	jsonDir := flag.String("json", "../scripts/moonbit/diagnostics_data", "JSON 真源目录（#39 迁出冻结区）")
	outDir := flag.String("out", "diagnostics", ".mbt 输出目录")
	legacyDir := flag.String("legacy-src", "../native/src/diagnostics", "legacy 对账源目录（Rust 冻结区，删区自动豁免）")
	flag.Parse()

	// ---- ① 装载 JSON 真源（固定顺序参与联合 sha——顺序变更即产物落款变更） ----
	jsonFiles := []string{"fix_payloads.json", "concepts.json", "patterns.json", "paths.json"}
	var jsonRaws [][]byte
	h := sha256.New()
	for _, f := range jsonFiles {
		b, err := os.ReadFile(filepath.Join(*jsonDir, f))
		if err != nil {
			fatalf("读 JSON 真源失败 %s: %v", f, err)
		}
		b = bytes.ReplaceAll(b, []byte("\r\n"), []byte("\n"))
		jsonRaws = append(jsonRaws, b)
		h.Write(b)
	}
	srcHash := fmt.Sprintf("%x", h.Sum(nil))[:8]

	fixes, dynamic := loadFixDoc(jsonRaws[0])
	nodes, edges, conceptMap := loadConceptsDoc(jsonRaws[1])
	patterns := loadPatternsDoc(jsonRaws[2])
	paths := loadPathsDoc(jsonRaws[3])

	// ---- ② 基线校验（数据面守恒——JSON 侧同受基线闸约束） ----
	if len(fixes) != expectedStaticCodes {
		fatalf("静态载荷码数 %d ≠ 基线 %d——JSON 真源已变更，请人工核对后更新 expectedStaticCodes 并登记差异", len(fixes), expectedStaticCodes)
	}
	if len(dynamic) != len(dynamicCodeWhitelist) {
		fatalf("动态码集合 %v 与白名单基数 %d 不符——JSON 真源新增/减少了机制码", dynamic, len(dynamicCodeWhitelist))
	}
	for c := range dynamic {
		if !dynamicCodeWhitelist[c] {
			fatalf("码 %d 不在动态白名单 {1004,3035,3041,3050,3051}——新形态臂出现，请先裁定其数据/机制归属", c)
		}
	}
	if len(nodes) != expectedNodes || len(edges) != expectedEdges || len(conceptMap) != expectedMapEntries {
		fatalf("概念图基线漂移：nodes %d/%d edges %d/%d map %d/%d", len(nodes), expectedNodes, len(edges), expectedEdges, len(conceptMap), expectedMapEntries)
	}
	if len(patterns) != expectedPatterns {
		fatalf("误区模式数 %d ≠ 基线 %d", len(patterns), expectedPatterns)
	}
	if len(paths) != expectedPaths {
		fatalf("学习路径数 %d ≠ 基线 %d", len(paths), expectedPaths)
	}

	// ---- ③ 渲染 .mbt 产物 ----
	writeProducts(*outDir, map[string]string{
		"fix_payloads_gen.mbt": renderFixPayloads(fixes, dynamic, srcHash),
		"concepts_gen.mbt":     renderConcepts(nodes, edges, conceptMap, srcHash),
		"patterns_gen.mbt":     renderPatterns(patterns, srcHash),
		"paths_gen.mbt":        renderPaths(paths, srcHash),
	}, *check)

	// ---- ④ legacy 对账臂（结构性；.rs 全在才对账，全不在豁免） ----
	legacyReconcile(*legacyDir, fixes, dynamic, nodes, edges, conceptMap, patterns, paths)

	if *check {
		fmt.Println("gen_diagnostics: check OK（.mbt 4 件未漂移）")
	} else {
		fmt.Println("gen_diagnostics: 生成完成（.mbt 4）")
	}
}

// ============ 解析：error_catalog.rs generate_fix ============

// parseGenerateFix 提取静态载荷码与动态码集合。
func parseGenerateFix(src string) ([]fixEntry, map[int]bool) {
	fnAt := strings.Index(src, "pub fn generate_fix(")
	if fnAt < 0 {
		fatalf("未找到 pub fn generate_fix")
	}
	mAt := strings.Index(src[fnAt:], "match code {")
	if mAt < 0 {
		fatalf("generate_fix 内未找到 match code")
	}
	bodyStart := fnAt + mAt + len("match code ")
	body := balancedBlock(src, bodyStart, '{', '}', "generate_fix match")
	if body == "" {
		fatalf("generate_fix match 体未闭合")
	}
	arms := splitArms(body)
	var fixes []fixEntry
	dynamic := map[int]bool{}
	for _, a := range arms {
		if a.pattern == "_" {
			continue
		}
		codes := parseArmCodes(a.pattern)
		if len(codes) == 0 {
			fatalf("臂模式 %q 解析失败", a.pattern)
		}
		entry, isStatic, err := parseFixTuple(a.body)
		if err != nil {
			fatalf("码 %v 元组解析失败: %v", codes, err)
		}
		if !isStatic {
			for _, c := range codes {
				dynamic[c] = true
			}
			continue
		}
		for _, c := range codes {
			e := entry
			e.Code = c
			fixes = append(fixes, e)
		}
	}
	sort.Slice(fixes, func(i, j int) bool { return fixes[i].Code < fixes[j].Code })
	return fixes, dynamic
}

// balancedBlock 从 src[start]（须指向开括号）取平衡块体（不含两端括号）。
// 字符串 / 行注释感知。未闭合返回空串。
func balancedBlock(src string, start int, open, close byte, what string) string {
	if start >= len(src) || src[start] != open {
		fatalf("%s：起点不是开括号 @%d", what, start)
	}
	depth := 0
	for j := start; j < len(src); j++ {
		c := src[j]
		if c == '"' {
			_, next := scanRustString(src, j)
			j = next - 1
			continue
		}
		if c == '/' && j+1 < len(src) && src[j+1] == '/' {
			for j < len(src) && src[j] != '\n' {
				j++
			}
			continue
		}
		if c == open {
			depth++
		} else if c == close {
			depth--
			if depth == 0 {
				return src[start+1 : j]
			}
		}
	}
	return ""
}

type arm struct {
	pattern string
	body    string
}

// splitArms 在 match 体内按顶层 `pattern =>` 切臂（字符串 / 括号 / 注释感知）。
func splitArms(body string) []arm {
	type cand struct {
		at  int
		end int // => 后位置
		pat string
	}
	var cands []cand
	depth := 0
	i := 0
	for i < len(body) {
		c := body[i]
		if c == '"' {
			_, next := scanRustString(body, i)
			i = next
			continue
		}
		if c == '/' && i+1 < len(body) && body[i+1] == '/' {
			for i < len(body) && body[i] != '\n' {
				i++
			}
			continue
		}
		if c == '(' || c == '{' || c == '[' {
			depth++
			i++
			continue
		}
		if c == ')' || c == '}' || c == ']' {
			depth--
			i++
			continue
		}
		if depth == 0 {
			// 臂模式候选：数字 / `N | M` / `_`，其后紧跟 ` =>`
			rest := body[i:]
			if m := regexp.MustCompile(`^(?:_|\d+(?:\s*\|\s*\d+)*)\s*=>`).FindString(rest); m != "" {
				pat := strings.TrimSpace(strings.TrimSuffix(strings.TrimSpace(m), "=>"))
				cands = append(cands, cand{at: i, end: i + len(m), pat: pat})
				i += len(m)
				continue
			}
		}
		i++
	}
	var arms []arm
	for k, cd := range cands {
		var end int
		if k+1 < len(cands) {
			end = cands[k+1].at
		} else {
			end = len(body)
		}
		seg := body[cd.end:end]
		// 先剥注释再 trim 尾逗号——注释行在臂尾时先 trim 会漏掉逗号
		seg = strings.TrimSuffix(strings.TrimSpace(stripLineComments(seg)), ",")
		arms = append(arms, arm{pattern: cd.pat, body: strings.TrimSpace(seg)})
	}
	return arms
}

// stripLineComments 删除 // 行注释（字符串感知）。
func stripLineComments(s string) string {
	var b strings.Builder
	i := 0
	for i < len(s) {
		c := s[i]
		if c == '"' {
			v, next := scanRustString(s, i)
			b.WriteString(s[i:next])
			_ = v
			i = next
			continue
		}
		if c == '/' && i+1 < len(s) && s[i+1] == '/' {
			for i < len(s) && s[i] != '\n' {
				i++
			}
			continue
		}
		b.WriteByte(c)
		i++
	}
	return b.String()
}

func parseArmCodes(pattern string) []int {
	var out []int
	for _, part := range strings.Split(pattern, "|") {
		v, err := strconv.Atoi(strings.TrimSpace(part))
		if err != nil {
			return nil
		}
		out = append(out, v)
	}
	return out
}

// parseFixTuple 解析七元组 (suggestion, kind, c1, c2, c3, c4, text)。
// isStatic=false 表示该臂含机制（坐标计算 / 消息分支），不入表。
func parseFixTuple(body string) (fixEntry, bool, error) {
	var e fixEntry
	// 块形态 { ( ... ) } 或裸 ( ... )
	t := strings.TrimSpace(body)
	t = strings.TrimPrefix(t, "{")
	t = strings.TrimSuffix(t, "}")
	t = strings.TrimSpace(t)
	// 动态信号：控制流 / 查找 / 帮助函数调用（剥注释后仍存在即机制）
	for _, sig := range []string{"if ", "let ", "format!", ".find", "contains", "Some(", "found_pos", "as i32"} {
		if strings.Contains(t, sig) {
			return e, false, nil
		}
	}
	if !strings.HasPrefix(t, "(") {
		return e, false, fmt.Errorf("臂体非元组形态：%q", safeHead(t, 0))
	}
	parts := splitTuple(t)
	if len(parts) != 7 {
		return e, false, fmt.Errorf("元组分段 %d ≠ 7：%q", len(parts), parts)
	}
	var err error
	e.Suggestion, err = litString(parts[0])
	if err != nil {
		return e, false, fmt.Errorf("suggestion: %w", err)
	}
	e.FixKind, err = strconv.Atoi(strings.TrimSpace(parts[1]))
	if err != nil {
		return e, false, fmt.Errorf("fix_kind: %w", err)
	}
	coords := make([]string, 4)
	for k := 0; k < 4; k++ {
		coords[k] = strings.TrimSpace(parts[2+k])
	}
	text := strings.TrimSpace(parts[6])
	allZero := coords[0] == "0" && coords[1] == "0" && coords[2] == "0" && coords[3] == "0"
	switch {
	case allZero:
		e.Anchor = "Manual"
		if text != "String::new()" {
			return e, false, fmt.Errorf("Manual 形态 text 非 String::new()：%q", text)
		}
	case coords[0] == "line" && coords[1] == "trimmed_len" && coords[2] == "line" && coords[3] == "trimmed_len":
		e.Anchor = "LineEnd"
		e.Text, err = litString(text)
		if err != nil {
			return e, false, fmt.Errorf("text: %w", err)
		}
	default:
		return e, false, fmt.Errorf("未知坐标组合 %v——新锚定形态须先裁定", coords)
	}
	return e, true, nil
}

// splitTuple 把 "( a, b, ... )" 顶层逗号分段（字符串 / 嵌套括号感知）。
func splitTuple(t string) []string {
	inner := strings.TrimSpace(t)
	inner = strings.TrimPrefix(inner, "(")
	inner = strings.TrimSuffix(inner, ")")
	var parts []string
	depth := 0
	start := 0
	i := 0
	for i < len(inner) {
		c := inner[i]
		if c == '"' {
			_, next := scanRustString(inner, i)
			i = next
			continue
		}
		switch c {
		case '(', '{', '[':
			depth++
		case ')', '}', ']':
			depth--
		case ',':
			if depth == 0 {
				parts = append(parts, inner[start:i])
				start = i + 1
			}
		}
		i++
	}
	last := strings.TrimSpace(inner[start:])
	if last != "" {
		parts = append(parts, last) // 尾逗号不产生空段
	}
	return parts
}

// litString 解析 `"..."` + 可选 `.to_string()` / `String::new()`（后者返回空串）。
func litString(s string) (string, error) {
	t := strings.TrimSpace(s)
	if t == "String::new()" {
		return "", nil
	}
	q := strings.IndexByte(t, '"')
	if q < 0 {
		return "", fmt.Errorf("无字符串字面量：%q", safeHead(t, 0))
	}
	v, _ := scanRustString(t, q)
	return v, nil
}

// scanRustString 从 s[pos]（须指向开引号）扫描 Rust 字符串字面量，
// 返回解码值与收尾下一位（转义处理与 gen_diag 同款）。
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
				i++
			case 't':
				b.WriteByte('\t')
				i++
			case 'r':
				b.WriteByte('\r')
				i++
			case '"', '\\':
				b.WriteByte(s[i+1])
				i++
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
	if len(head) > 24 {
		head = head[:24]
	}
	return head
}

// ============ 解析：knowledge_graph.rs ============

func parseKnowledgeGraph(src string) ([]nodeEntry, []edgeEntry, []mapEntry) {
	nodesBody := lazyVecBody(src, "static NODES: LazyLock<Vec<ConceptNode>>", "NODES")
	var nodes []nodeEntry
	for _, blk := range splitStructBlocks(nodesBody, "ConceptNode {") {
		nodes = append(nodes, nodeEntry{
			ID:             rustFromField(blk, "id"),
			Domain:         rustFromField(blk, "domain"),
			Title:          rustFromField(blk, "title"),
			Description:    rustFromField(blk, "description"),
			Difficulty:     mustIntField(blk, "difficulty", "ConceptNode"),
			RelatedCardIDs: rustFromVecField(blk, "related_card_ids"),
		})
	}
	edgesBody := lazyVecBody(src, "static EDGES: LazyLock<Vec<ConceptEdge>>", "EDGES")
	var edges []edgeEntry
	for _, blk := range splitStructBlocks(edgesBody, "ConceptEdge {") {
		st, err := strconv.ParseFloat(rustRawField(blk, "strength"), 64)
		if err != nil {
			fatalf("strength 解析失败: %v", err)
		}
		edges = append(edges, edgeEntry{
			From:     rustFromField(blk, "from"),
			To:       rustFromField(blk, "to"),
			Relation: rustFromField(blk, "relation"),
			Strength: st,
		})
	}
	var conceptMap []mapEntry
	re := regexp.MustCompile(`m\.insert\((\d+),\s*vec!\[([^\]]*)\]\);`)
	for _, m := range re.FindAllStringSubmatch(src, -1) {
		code, _ := strconv.Atoi(m[1])
		var concepts []string
		for _, sm := range regexp.MustCompile(`String::from\("((?:[^"\\]|\\.)*)"\)`).FindAllStringSubmatch(m[2], -1) {
			v, _ := litString(`"` + sm[1] + `"`)
			concepts = append(concepts, v)
		}
		if len(concepts) == 0 {
			fatalf("ERROR_CONCEPT_MAP 码 %d 概念列表为空", code)
		}
		conceptMap = append(conceptMap, mapEntry{Code: code, Concept: concepts})
	}
	return nodes, edges, conceptMap
}

// lazyVecBody 取 `static NAME: LazyLock<Vec<T>> = LazyLock::new(|| { vec![...] });`
// 的 vec![ ] 内体。
func lazyVecBody(src, decl, name string) string {
	i := strings.Index(src, decl)
	if i < 0 {
		fatalf("未找到 %s 声明", name)
	}
	v := strings.Index(src[i:], "vec![")
	if v < 0 {
		fatalf("%s 内未找到 vec![", name)
	}
	start := i + v + len("vec![")
	depth := 1
	for j := start; j < len(src); j++ {
		c := src[j]
		if c == '"' {
			_, next := scanRustString(src, j)
			j = next - 1
			continue
		}
		if c == '[' {
			depth++
		} else if c == ']' {
			depth--
			if depth == 0 {
				return src[start:j]
			}
		}
	}
	fatalf("%s vec! 未闭合", name)
	return ""
}

// splitStructBlocks 按 `Marker {` 分块（大括号配对 + 字符串感知）。
func splitStructBlocks(body, marker string) []string {
	var out []string
	for {
		i := strings.Index(body, marker)
		if i < 0 {
			return out
		}
		open := i + len(marker) - 1
		blk := balancedBlock(body, open, '{', '}', marker)
		if blk == "" {
			fatalf("%s 块未闭合", marker)
		}
		out = append(out, blk)
		body = body[open+len(blk)+2:]
	}
}

// rustFromField 解析 `field: String::from("...")`。
func rustFromField(block, field string) string {
	return rustStrField(block, field, "String::from(")
}

func rustStrField(block, field, ctor string) string {
	i := strings.Index(block, field+":")
	if i < 0 {
		fatalf("块内缺字段 %s", field)
	}
	rest := block[i+len(field)+1:]
	q := strings.Index(rest, `"`)
	if q < 0 {
		fatalf("字段 %s 无字符串字面量", field)
	}
	v, _ := scanRustString(rest, q)
	return v
}

func rustRawField(block, field string) string {
	i := strings.Index(block, field+":")
	if i < 0 {
		fatalf("块内缺字段 %s", field)
	}
	rest := strings.TrimSpace(block[i+len(field)+1:])
	end := strings.IndexAny(rest, ",}")
	if end < 0 {
		fatalf("字段 %s 无结束符", field)
	}
	return strings.TrimSpace(rest[:end])
}

func mustIntField(block, field, what string) int {
	v, err := strconv.Atoi(rustRawField(block, field))
	if err != nil {
		fatalf("%s 字段 %s 数值解析失败: %v", what, field, err)
	}
	return v
}

// rustFromVecField 解析 `field: vec![String::from("a"), String::from("b")]` 或 `vec![]`。
func rustFromVecField(block, field string) []string {
	i := strings.Index(block, field+":")
	if i < 0 {
		fatalf("块内缺字段 %s", field)
	}
	v := strings.Index(block[i:], "vec![")
	if v < 0 {
		fatalf("字段 %s 无 vec![", field)
	}
	start := i + v + len("vec![")
	depth := 1
	for j := start; j < len(block); j++ {
		c := block[j]
		if c == '[' {
			depth++
		} else if c == ']' {
			depth--
			if depth == 0 {
				out := []string{}
				for _, sm := range regexp.MustCompile(`String::from\("((?:[^"\\]|\\.)*)"\)`).FindAllStringSubmatch(block[start:j], -1) {
					s, _ := litString(`"` + sm[1] + `"`)
					out = append(out, s)
				}
				return out
			}
		}
	}
	fatalf("字段 %s vec! 未闭合", field)
	return nil
}

// ============ 解析：misconception_patterns.rs ============

func parseMisconception(src string) []patternEntry {
	body := lazyVecBody(src, "pub fn default_patterns() -> Vec<MisconceptionPattern> {", "default_patterns")
	var out []patternEntry
	for _, blk := range splitStructBlocks(body, "MisconceptionPattern {") {
		p := patternEntry{
			ID:             rustFromField(blk, "id"),
			Name:           rustFromField(blk, "name"),
			Description:    rustFromField(blk, "description"),
			MinOccurrences: mustIntField(blk, "min_occurrences", "MisconceptionPattern"),
			TimeWindow:     mustIntField(blk, "time_window", "MisconceptionPattern"),
			ErrorCodes:     []int{}, // 空 = 仅 trap 关键词匹配（M05），JSON 面 null/[] 语义不分叉
		}
		i := strings.Index(blk, "error_codes:")
		if i < 0 {
			fatalf("MisconceptionPattern %s 缺 error_codes", p.ID)
		}
		rest := blk[i+len("error_codes:"):]
		end := strings.Index(rest, "]")
		if end < 0 {
			fatalf("error_codes 未闭合")
		}
		for _, part := range strings.Split(rest[:end], ",") {
			part = strings.TrimSpace(part)
			if part == "" || part == "vec![" {
				continue
			}
			part = strings.TrimPrefix(part, "vec![")
			if part == "" {
				continue
			}
			v, err := strconv.Atoi(strings.TrimSpace(part))
			if err != nil {
				// 行内注释（如 "3021, // Bounds"）——剥注释后重试
				if c := strings.Index(part, "//"); c >= 0 {
					part = strings.TrimSpace(part[:c])
					v, err = strconv.Atoi(part)
				}
				if err != nil {
					fatalf("error_codes 成员 %q 解析失败: %v", part, err)
				}
			}
			p.ErrorCodes = append(p.ErrorCodes, v)
		}
		out = append(out, p)
	}
	return out
}

// ============ 解析：learning_path.rs ============

func parseLearningPath(src string) []pathEntry {
	re := regexp.MustCompile(`"(M\d+)"\s*=>\s*Some\(LearningPath\s*\{`)
	locs := re.FindAllStringSubmatchIndex(src, -1)
	if len(locs) != expectedPaths {
		fatalf("LearningPath 分派臂数 %d ≠ 基线 %d", len(locs), expectedPaths)
	}
	var out []pathEntry
	for k, loc := range locs {
		id := src[loc[2]:loc[3]]
		open := strings.LastIndex(src[loc[1]-1:loc[1]], "{") + loc[1] - 1
		blk := balancedBlock(src, open, '{', '}', "LearningPath")
		if blk == "" {
			fatalf("LearningPath %s 块未闭合", id)
		}
		var end int
		if k+1 < len(locs) {
			end = locs[k+1][0]
		} else {
			end = len(src)
		}
		// 步骤数组须在同一臂体内（防御：截取到下一臂前再找）
		scope := src[open : open+len(blk)+2]
		if open+len(blk)+2 > end {
			scope = scope[:end-open]
		}
		si := strings.Index(scope, "steps: vec![")
		if si < 0 {
			fatalf("LearningPath %s 缺 steps", id)
		}
		sv := scope[si+len("steps: vec!["):]
		depth := 1
		var sbody string
		for j := 0; j < len(sv); j++ {
			switch sv[j] {
			case '[':
				depth++
			case ']':
				depth--
				if depth == 0 {
					sbody = sv[:j]
					j = len(sv)
				}
			}
		}
		if sbody == "" {
			fatalf("LearningPath %s steps 未闭合", id)
		}
		p := pathEntry{ID: id, Minutes: mustIntField(blk, "estimated_time_minutes", "LearningPath")}
		for _, sb := range splitStructBlocks(sbody, "PathStep {") {
			p.Steps = append(p.Steps, stepEntry{
				StepType:   rustFromField(sb, "step_type"),
				Title:      rustFromField(sb, "title"),
				Detail:     rustFromField(sb, "detail"),
				TargetID:   rustFromField(sb, "target_id"),
				Highlights: intVecField(sb, "highlight_lines"),
			})
		}
		if len(p.Steps) == 0 {
			fatalf("LearningPath %s steps 为空", id)
		}
		out = append(out, p)
	}
	return out
}

// intVecField 解析 `field: vec![4]` / `vec![]`。
func intVecField(block, field string) []int {
	i := strings.Index(block, field+":")
	if i < 0 {
		fatalf("块内缺字段 %s", field)
	}
	rest := block[i+len(field)+1:]
	v := strings.Index(rest, "vec![")
	if v < 0 {
		fatalf("字段 %s 无 vec![", field)
	}
	start := v + len("vec![")
	end := strings.Index(rest[start:], "]")
	if end < 0 {
		fatalf("字段 %s vec! 未闭合", field)
	}
	out := []int{}
	for _, part := range strings.Split(rest[start:start+end], ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		n, err := strconv.Atoi(part)
		if err != nil {
			if c := strings.Index(part, "//"); c >= 0 {
				n, err = strconv.Atoi(strings.TrimSpace(part[:c]))
			}
			if err != nil {
				fatalf("字段 %s 成员 %q 解析失败: %v", field, part, err)
			}
		}
		out = append(out, n)
	}
	return out
}

// ============ 渲染：.mbt ============

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

const genBanner = "// @generated by scripts/moonbit/gen_diagnostics —— 禁手改（git/diff 工具链按 @generated 识别；再生成：cd 仓库根 && go run ./scripts/moonbit/gen_diagnostics）。\n" +
	"// 源：scripts/moonbit/diagnostics_data/ 四 JSON 真源（#39 迁出冻结区 2026-10-05；联合 sha256/%s，行尾归一）。\n" +
	"// legacy：Rust oracle 四 .rs 结构对账至工序④删区（值级文案为修复批合法演化面，不比）。\n"

func renderFixPayloads(fixes []fixEntry, dynamic map[int]bool, srcHash string) string {
	var b strings.Builder
	fmt.Fprintf(&b, genBanner, srcHash)
	dyn := make([]int, 0, len(dynamic))
	for c := range dynamic {
		dyn = append(dyn, c)
	}
	sort.Ints(dyn)
	fmt.Fprintf(&b, "// 基线：静态载荷 %d 码（漂移时本脚本 fail loud）；动态码 %v 不入表（机制层 fix_gen.mbt 照搬——勘察 A3 拆分）。\n\n", len(fixes), dyn)
	fmt.Fprintf(&b, "///|\n/// 静态修复载荷表查询（generate_fix 的纯静态码子集；无下划线外的\n/// 兜底——未知码 None，机制层随后查动态五码）。\npub fn fix_payload(code : Int) -> FixPayload? {\n  match code {\n")
	for _, e := range fixes {
		anchor := "Manual"
		if e.Anchor == "LineEnd" {
			anchor = "LineEnd"
		}
		fmt.Fprintf(&b, "    %d =>\n      Some(\n        FixPayload::{\n          suggestion: \"%s\",\n          fix_kind: %d,\n          anchor: %s,\n          text: \"%s\",\n        },\n      )\n",
			e.Code, escapeMbt(e.Suggestion), e.FixKind, anchor, escapeMbt(e.Text))
	}
	b.WriteString("    _ => None\n  }\n}\n")
	return b.String()
}

func renderConcepts(nodes []nodeEntry, edges []edgeEntry, conceptMap []mapEntry, srcHash string) string {
	var b strings.Builder
	fmt.Fprintf(&b, genBanner, srcHash)
	fmt.Fprintf(&b, "// 基线：节点 %d / 边 %d / 错误码映射 %d（漂移时本脚本 fail loud）。\n", len(nodes), len(edges), len(conceptMap))
	b.WriteString("// 分叉登记：3020→Recursion 系 oracle 存量语义错（勘察 ⑥-5），照搬不修——\n// 修复走差异台账两侧同修批。\n\n")

	fmt.Fprintf(&b, "///|\n/// 概念节点全集（源声明序）。\npub fn concept_nodes() -> Array[ConceptNode] {\n  [\n")
	for _, n := range nodes {
		cards := make([]string, len(n.RelatedCardIDs))
		for i, c := range n.RelatedCardIDs {
			cards[i] = "\"" + escapeMbt(c) + "\""
		}
		fmt.Fprintf(&b, "    ConceptNode::{\n      id: \"%s\",\n      domain: \"%s\",\n      title: \"%s\",\n      description: \"%s\",\n      difficulty: %d,\n      related_card_ids: [%s],\n    },\n",
			escapeMbt(n.ID), escapeMbt(n.Domain), escapeMbt(n.Title), escapeMbt(n.Description), n.Difficulty, strings.Join(cards, ", "))
	}
	b.WriteString("  ]\n}\n\n")

	fmt.Fprintf(&b, "///|\n/// 概念边全集（源声明序——DFS 前置路径的遍历序依赖此序）。\npub fn concept_edges() -> Array[ConceptEdge] {\n  [\n")
	for _, e := range edges {
		fmt.Fprintf(&b, "    ConceptEdge::{\n      from_id: \"%s\",\n      to_id: \"%s\",\n      relation: \"%s\",\n      strength: %s,\n    },\n",
			escapeMbt(e.From), escapeMbt(e.To), escapeMbt(e.Relation), strconv.FormatFloat(e.Strength, 'g', -1, 64))
	}
	b.WriteString("  ]\n}\n\n")

	fmt.Fprintf(&b, "///|\n/// 错误码 → 概念 id 列表（源 insert 序；LinkedHashMap 语义同源）。\npub fn error_concept_map() -> Map[Int, Array[String]] {\n  let m : Map[Int, Array[String]] = Map([])\n")
	for _, me := range conceptMap {
		cs := make([]string, len(me.Concept))
		for i, c := range me.Concept {
			cs[i] = "\"" + escapeMbt(c) + "\""
		}
		fmt.Fprintf(&b, "  m.set(%d, [%s])\n", me.Code, strings.Join(cs, ", "))
	}
	b.WriteString("  m\n}\n")
	return b.String()
}

func renderPatterns(patterns []patternEntry, srcHash string) string {
	var b strings.Builder
	fmt.Fprintf(&b, genBanner, srcHash)
	fmt.Fprintf(&b, "// 基线：误区模式 %d 条（漂移时本脚本 fail loud）。M05 的 trap 关键词\n// 匹配是机制（misconception.mbt），表内 error_codes 为空即其标记。\n\n", len(patterns))
	fmt.Fprintf(&b, "///|\n/// 预置误区模式全集（源声明序）。\npub fn default_patterns() -> Array[MisconceptionPattern] {\n  [\n")
	for _, p := range patterns {
		codes := make([]string, len(p.ErrorCodes))
		for i, c := range p.ErrorCodes {
			codes[i] = strconv.Itoa(c)
		}
		fmt.Fprintf(&b, "    MisconceptionPattern::{\n      id: \"%s\",\n      name: \"%s\",\n      description: \"%s\",\n      error_codes: [%s],\n      min_occurrences: %d,\n      time_window: %d,\n    },\n",
			escapeMbt(p.ID), escapeMbt(p.Name), escapeMbt(p.Description), strings.Join(codes, ", "), p.MinOccurrences, p.TimeWindow)
	}
	b.WriteString("  ]\n}\n")
	return b.String()
}

func renderPaths(paths []pathEntry, srcHash string) string {
	var b strings.Builder
	fmt.Fprintf(&b, genBanner, srcHash)
	fmt.Fprintf(&b, "// 基线：学习路径 %d 条（漂移时本脚本 fail loud）。target_misconception_\n// id/name 运行时由检出误区带过（Rust d.pattern_id.clone() 同义），不冗余入表。\n// 分叉登记：target_id 悬空引用（勘察 ③-D5）照搬不修。\n\n", len(paths))
	fmt.Fprintf(&b, "///|\n/// 预置学习路径表（key = 误区模式 id，M01..M06）。\npub fn default_paths() -> Map[String, LearningPath] {\n  let m : Map[String, LearningPath] = Map([])\n")
	for _, p := range paths {
		fmt.Fprintf(&b, "  m.set(\n    \"%s\",\n    LearningPath::{\n      target_misconception_id: \"%s\",\n      target_misconception_name: \"\",\n      estimated_time_minutes: %d,\n      steps: [\n", escapeMbt(p.ID), escapeMbt(p.ID), p.Minutes)
		for _, s := range p.Steps {
			hl := make([]string, len(s.Highlights))
			for i, v := range s.Highlights {
				hl[i] = strconv.Itoa(v)
			}
			fmt.Fprintf(&b, "        PathStep::{\n          step_type: \"%s\",\n          title: \"%s\",\n          detail: \"%s\",\n          target_id: \"%s\",\n          highlight_lines: [%s],\n        },\n",
				escapeMbt(s.StepType), escapeMbt(s.Title), escapeMbt(s.Detail), escapeMbt(s.TargetID), strings.Join(hl, ", "))
		}
		b.WriteString("      ],\n    },\n  )\n")
	}
	b.WriteString("  m\n}\n")
	return b.String()
}

// ============ 写出 / 校验 ============

type productItem struct {
	path string
	cur  []byte
}

// writeProducts 写 .mbt 产物并经 moon fmt 规范化（gen 与 fmt 不得互踩：
// 最终形态以 fmt 输出为准）；check 模式逐字节（行尾归一）比对，
// 全部比对完再统一还原，失败路径不留覆盖副作用（契约同 gen_diag）。
// **读旧/写新两阶段分离**（审阅 F5 修复 2026-10-02）：map 迭代无序，
// 交错形态下「产物缺失→读旧失败 fatalf」时已写入的其它产物不还原，
// 工作区被污染成未 fmt 原文（CI 只读退出码看不见）；先读完全部旧产物
// （此阶段失败零写入，天然安全）再统一写。
func writeProducts(dir string, products map[string]string, check bool) {
	names := make([]string, 0, len(products))
	for name := range products {
		names = append(names, name)
	}
	sort.Strings(names)
	var items []productItem
	for _, name := range names {
		path := filepath.Join(dir, name)
		var cur []byte
		if check {
			var err error
			cur, err = os.ReadFile(path)
			if err != nil {
				fatalf("-check: 读产物失败 %s: %v", path, err)
			}
		}
		items = append(items, productItem{path, cur})
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		fatalf("建目录失败 %s: %v", dir, err)
	}
	for k, it := range items {
		if err := os.WriteFile(it.path, []byte(products[names[k]]), 0o644); err != nil {
			restoreItems(items)
			fatalf("写产物失败 %s: %v", it.path, err)
		}
	}
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
	var drifted []string
	for _, it := range items {
		now, err := os.ReadFile(it.path)
		if err != nil {
			restoreItems(items)
			fatalf("-check: 回读产物失败 %s: %v", it.path, err)
		}
		nowLF := bytes.ReplaceAll(now, []byte{13, 10}, []byte{10})
		curLF := bytes.ReplaceAll(it.cur, []byte{13, 10}, []byte{10})
		if !bytes.Equal(nowLF, curLF) {
			drifted = append(drifted, it.path)
		}
	}
	if len(drifted) > 0 {
		restoreItems(items)
		fatalf("-check: 产物漂移 %s——源已变更未再生成（cd 仓库根 && go run ./scripts/moonbit/gen_diagnostics）", strings.Join(drifted, ", "))
	}
}

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
