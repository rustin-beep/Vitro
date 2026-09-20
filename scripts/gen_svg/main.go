package main

// 文档插图生成器 —— 探针转正 Go 重写（2026-09-20，原 tmp/gen_arch_svg.py +
// tmp/gen_three_svg.py 退役）。
//
// 四张 docs/current 入库插图的跑批快照数字**只在此处为模板**：生成时从
// reports/facts.json 读真值注入，并以 <tspan data-fact="key">n</tspan> 显式
// 锚定；scripts/facts check 逐锚机判漂移。漂移工作流：
//
//	跑防线（或 go run ./scripts/facts）→ facts check 红（SVG 数字过时）
//	→ go run ./scripts/gen_svg → facts check 绿
//
// 禁止手改入库 SVG 的 data-fact 锚定数字——下次生成即回退（facts 的
// interactiveSync 也刻意跳过 .svg 命中）。设计常量（2000 帧 / 50 检查点等）
// 不是快照、无锚，改动属代码常量变更，走评审。
//
// 用法：go run ./scripts/gen_svg [arch|cache|kg|shadow|all]（默认 all）
//
// 品牌纪律（照搬 assets/logo/vitro-logo.svg）：只用玻璃蓝 #155E86 /
// #4FB3E8(dark) + 基准灰 #94A3AD / #5A6B75(dark) + 墨 #0D1B24 / #E9F1F7(dark)
// + 白高光；无渐变堆叠、无投影、圆头端点；纯 CSS @media 深浅自适应，无脚本。

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// ─── facts 台账（只读；与 scripts/facts 同一份 reports/facts.json）──────────

type factEntry struct {
	Value  *int   `json:"value"`
	AsOf   string `json:"as_of"`
	Status string `json:"status"`
	Source string `json:"source"`
	HowTo  string `json:"how_to_get"`
}

type factsDoc struct {
	GeneratedAt string               `json:"generated_at"`
	Facts       map[string]factEntry `json:"facts"`
}

func loadFacts(root string) factsDoc {
	p := filepath.Join(root, "reports", "facts.json")
	b, err := os.ReadFile(p)
	if err != nil {
		fatal("读不到 reports/facts.json（先跑 go run ./scripts/facts facts 采集）: " + err.Error())
	}
	var d factsDoc
	if err := json.Unmarshal(b, &d); err != nil {
		fatal("reports/facts.json 解析失败: " + err.Error())
	}
	return d
}

// mustFact 取数值真值，fail loud：不猜默认值（缺 key / 待采集 / 超龄一律红）。
func mustFact(d factsDoc, key string) int {
	f, ok := d.Facts[key]
	if !ok || f.Value == nil || (f.Status != "ok" && f.Status != "stale") {
		how := ""
		if ok {
			how = f.HowTo
		}
		fatal(fmt.Sprintf("facts 键 %q 不可用（status=%s）——how_to_get: %s",
			key, f.Status, how))
	}
	return *f.Value
}

func asOfOf(d factsDoc, key string) string {
	if f, ok := d.Facts[key]; ok {
		return f.AsOf
	}
	return d.GeneratedAt
}

func fatal(msg string) {
	fmt.Fprintln(os.Stderr, "错误: "+msg)
	os.Exit(2)
}

// ─── SVG 拼装 helper ─────────────────────────────────────────────────────────

func esc(s string) string {
	r := strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;")
	return r.Replace(s)
}

func box(x, y, w, h int, cls string, rx int) string {
	return fmt.Sprintf(`<rect class="%s" x="%d" y="%d" width="%d" height="%d" rx="%d"/>`,
		cls, x, y, w, h, rx)
}

// textF：dataFact 非空时把整段文本包进 <tspan data-fact=…>——数字与锚一一
// 对应（facts 的 SVG 通道按锚后最近 tspan 文本取数，一行多锚零歧义）。
func textF(x, y int, cls, s, dataFact string) string {
	content := esc(s)
	if dataFact != "" {
		content = fmt.Sprintf(`<tspan data-fact="%s">%s</tspan>`, dataFact, content)
	}
	return fmt.Sprintf(`<text class="%s" x="%d" y="%d" text-anchor="middle">%s</text>`,
		cls, x, y, content)
}

// textRow：一行内多段（文本片段 | 锚+数字）交替拼接。
type seg struct {
	text string // 纯文本段（已按原样，内部 esc）
	num  string // 非空 = 数字段，num 为 data-fact 键
	val  int    // 数字段的值
}

func textSegs(x, y int, cls string, segs []seg) string {
	var b strings.Builder
	fmt.Fprintf(&b, `<text class="%s" x="%d" y="%d" text-anchor="middle">`, cls, x, y)
	for _, s := range segs {
		if s.num != "" {
			fmt.Fprintf(&b, `<tspan data-fact="%s">%d</tspan>`, s.num, s.val)
		} else {
			b.WriteString(esc(s.text))
		}
	}
	b.WriteString("</text>")
	return b.String()
}

func line(x1, y1, x2, y2 int, cls string) string {
	return fmt.Sprintf(`<line class="%s" x1="%d" y1="%d" x2="%d" y2="%d"/>`,
		cls, x1, y1, x2, y2)
}

const css = `  <style>
    .bg     { fill: transparent; }
    .core   { fill: #155E86; fill-opacity: .07; stroke: #155E86; stroke-width: 3; }
    .card   { fill: #155E86; fill-opacity: .05; stroke: #155E86; stroke-width: 2.5; }
    .cons   { fill: none; stroke: #94A3AD; stroke-width: 2; }
    .warn   { fill: #155E86; fill-opacity: .04; stroke: #94A3AD; stroke-width: 2; stroke-dasharray: 7 5; }
    .line   { stroke: #94A3AD; stroke-width: 3; fill: none; }
    .edge   { stroke: #94A3AD; stroke-width: 2.5; fill: none; }
    .tt     { font-family: "Segoe UI","Microsoft YaHei",sans-serif; font-size: 30px; font-weight: 600; fill: #0D1B24; stroke: none; }
    .t      { font-family: "Segoe UI","Microsoft YaHei",sans-serif; font-size: 20px; fill: #0D1B24; stroke: none; }
    .ts     { font-family: "Consolas","Cascadia Mono",monospace; font-size: 19px; fill: #155E86; stroke: none; }
    .tm     { font-family: "Segoe UI","Microsoft YaHei",sans-serif; font-size: 18px; fill: #5A6B75; stroke: none; }
    .tc     { font-family: "Segoe UI","Microsoft YaHei",sans-serif; font-size: 16px; fill: #5A6B75; stroke: none; }
    @media (prefers-color-scheme: dark) {
      .core { stroke: #4FB3E8; fill: #4FB3E8; fill-opacity: .1; }
      .card { stroke: #4FB3E8; fill: #4FB3E8; fill-opacity: .07; }
      .cons, .warn { stroke: #5A6B75; }
      .line, .edge { stroke: #5A6B75; }
      .tt, .t { fill: #E9F1F7; }
      .ts     { fill: #4FB3E8; }
      .tm, .tc { fill: #94A3AD; }
    }
  </style>`

func svgOpen(w, h int, label, title, note string) []string {
	return []string{
		fmt.Sprintf(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" role="img" aria-label="%s">`, w, h, esc(label)),
		"  <title>" + esc(title) + "</title>",
		"  <!-- 由 scripts/gen_svg 生成（勿手改）：" + note + " -->",
		css,
		fmt.Sprintf(`  <rect class="bg" width="%d" height="%d"/>`, w, h),
	}
}

func writeSVG(root, rel string, parts []string) {
	p := filepath.Join(root, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		fatal(err.Error())
	}
	body := strings.Join(parts, "\n") + "\n</svg>\n"
	if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
		fatal("写 " + rel + " 失败: " + err.Error())
	}
	fmt.Printf("written: %s (%d bytes)\n", rel, len(body))
}

// ─── 图 A：三出口一核心架构（源：README.md:15-30 + 架构设计.md §2）────────────

func genArch(root string, _ factsDoc) {
	P := svgOpen(1200, 720, "vitro 三出口一核心架构图", "vitro — 三出口一核心架构",
		"内容对账 README.md:15-30 与 架构设计.md §2；配色沿用 assets/logo/ 品牌三色")
	P = append(P,
		box(220, 40, 760, 168, "core", 14),
		textF(600, 86, "tt", "vitro 引擎核心（Rust workspace）", ""),
		textF(600, 126, "t", "编译器管线 Lexer → Parser → TypeChecker → BytecodeGen", ""),
		textF(600, 162, "t", "VitroVM · 统一模式 · 诊断系统 · 禁止平台 API 耦合", ""),
		textF(600, 192, "tm", "session_api 会话语义中立层：三出口共用同一套入口语义", ""),
		line(600, 208, 600, 260, "line"),
		line(195, 260, 995, 260, "line"),
		line(195, 260, 195, 330, "line"),
		line(595, 260, 595, 330, "line"),
		line(995, 260, 995, 330, "line"),
	)
	exitTitles := [][3]string{
		{"出口 1：native cdylib / C ABI", "ABI 版本化", "vitro_abi_version()"},
		{"出口 2：wasm32-unknown-unknown", ".wasm + 薄 JS/TS 绑定", "3.75MB 冒烟实证"},
		{"出口 3：vitro_cli serve", "JSON-lines 会话模式", "headless 交互"},
	}
	// 消费者文案逐条对账 README.md:17-30（不增减事实）。用例规模数字留在
	// README（facts md 通道对账）——架构图口径化"全量 C 语料"，消掉随跑批
	// 漂移的第二份拷贝。
	consLines := [][]string{
		{"第一消费者：vitro_cli", "scripts/shadow_verify.go（capi 直调）",
			"全量 C 语料的生产验证", "第三方教学 IDE（P/Invoke）· 任意语言 FFI"},
		{"浏览器前端（社区）· 在线教学演示", "移动浏览器“看”场景",
			"已冒烟实证：零修改构建 3.75MB", "C API 全链路 + E3070 安全检测在 wasm 下工作"},
		{"编译 / 运行 / 单步", "时间旅行 / 断点", "脚本化消费", ""},
	}
	exitX := [3]int{15, 415, 815}
	for i, x := range exitX {
		cx := x + 180
		P = append(P,
			box(x, 330, 360, 128, "card", 14),
			textF(cx, 372, "t", exitTitles[i][0], ""),
			textF(cx, 406, "tm", exitTitles[i][1], ""),
			textF(cx, 436, "ts", exitTitles[i][2], ""),
			line(cx, 458, cx, 520, "line"),
			box(x, 520, 360, 116, "cons", 12),
		)
		for j, l := range consLines[i] {
			if l == "" {
				continue
			}
			P = append(P, textF(cx, 550+j*25, "tc", l, ""))
		}
	}
	writeSVG(root, "docs/current/01-定位与路线/vitro-architecture-three-exits.svg", P)
}

// ─── 图 B：统一模式·三态缓存（源：统一模式设计.md §2.1 表格 + §5.2）──────────

func genCache(root string, _ factsDoc) {
	P := svgOpen(1200, 760, "vitro 统一模式三态缓存", "统一模式 · 三态缓存（Triple-Cache）",
		"对账 统一模式设计.md §2.1 表格三行 + §5.2 CheckpointManager 落地更新；数字为设计常量（非快照，无 data-fact 锚）")
	P = append(P,
		textF(600, 56, "tt", "统一模式 · 三态缓存（Triple-Cache）", ""),
		textF(600, 92, "tm", "90% 操作只访问 Frame Cache（零延迟）· 10% 操作恢复 Active VM（从 Checkpoint 懒加载）· 只有一个“当前 VM”", ""),
	)
	// 每列行布局独立：Checkpoint 列的 <(i32, VMSnapshot)> 行曾与"全量+增量
	// 混合"同段溢出框边（视觉验收 2026-09-20 fail），拆为两行。
	type row struct {
		dy  int
		cls string
		s   string
	}
	cols := []struct {
		x    int
		rows []row
	}{
		{30, []row{
			{42, "t", "Frame Cache"},
			{76, "tc", "UnifiedEngine 滑动窗口（2000 帧）"},
			{112, "ts", "Vec<StepPayload>"},
			{148, "tm", "动画渲染 / 变量面板 / 进度条拖动"},
			{182, "tm", "大小：2~5MB（1000 步）"},
		}},
		{430, []row{
			{42, "t", "Checkpoint"},
			{72, "tc", "vitro_vm::snapshot::CheckpointManager"},
			{102, "ts", "Vec<(i32, VMSnapshot)>"},
			{128, "tm", "全量 + 增量混合"},
			{156, "tm", "VM 状态恢复（继续执行 / 查看内存）"},
			{184, "tm", "大小：全量 50MB → 增量后 5~10MB"},
		}},
		{830, []row{
			{42, "t", "Active VM"},
			{76, "tc", "Rust 后端"},
			{112, "ts", "VitroVM 实例"},
			{148, "tm", "当前可执行的 VM 状态"},
			{182, "tm", "大小：1MB"},
		}},
	}
	for _, c := range cols {
		cx := c.x + 170
		P = append(P, box(c.x, 130, 340, 210, "card", 14))
		for _, r := range c.rows {
			P = append(P, textF(cx, 130+r.dy, r.cls, r.s, ""))
		}
	}
	P = append(P,
		line(200, 340, 200, 430, "line"),
		line(600, 340, 600, 430, "line"),
		line(1000, 340, 1000, 430, "line"),
		line(200, 430, 1000, 430, "line"),
		line(600, 430, 600, 470, "line"),
		box(120, 470, 960, 118, "warn", 12),
		textF(600, 508, "t", "CheckpointManager 落地机制（§5.2，2026-09-11 核对）", ""),
		textF(600, 540, "tc", "每 full_every 个检查点存完整 1MB 全量，其余仅存被修改的 4KB 脏页 · 上限 max_checkpoints = 50 · smart_mode 语义关键点强制保存", ""),
		textF(600, 568, "tc", "隔离区 quarantine 必须随快照往返，否则时间旅行回退后 UAF 检测出现假阴性", ""),
		textF(600, 640, "tc", "Frame Cache 权威副本在引擎内；消费方经 vitro_get_step_payloads_json / serve payload.get 取用，不得假设窗口外历史仍可查询", ""),
	)
	writeSVG(root, "docs/current/05-教学体验/unified-triple-cache.svg", P)
}

// ─── 图 C：认知推理·概念图谱（源：认知推理系统设计.md §3.1 三域树）────────────

func genKG(root string, _ factsDoc) {
	P := svgOpen(1200, 780, "vitro 认知推理概念图谱", "P2 知识图谱 · C 语言概念三域（已实现 Phase 22）",
		"对账 认知推理系统设计.md §3.1 节点分类树；P2 状态=已实现（24 节点 + 30+ 边）")
	P = append(P,
		textF(600, 54, "tt", "P2 知识图谱 · C 语言概念三域", ""),
		textF(600, 88, "tm", "已实现（Phase 22）：KnowledgeGraph 24 概念节点 + 30+ 关系边 · native/src/diagnostics/knowledge_graph.rs", ""),
	)
	domains := []struct {
		name  string
		x     int
		nodes []string
	}{
		{"编译概念域", 60, []string{"变量声明 VarDecl", "类型系统 TypeSystem",
			"· 隐式转换 / 指针类型", "运算符 Operators", "· 算术 / 逻辑 / 位运算", "作用域 Scope"}},
		{"内存概念域", 460, []string{"栈内存 StackMemory", "堆内存 HeapMemory",
			"指针 Pointer", "· 取址 / 解引用 / 指针算术", "数组 Array（· 数组退化）", "结构体内存布局 StructLayout"}},
		{"控制流概念域", 860, []string{"条件分支 IfSwitch", "循环 Loop",
			"· for / while / 边界条件", "函数调用 FunctionCall", "· 参数传递 / 返回值", "递归 Recursion"}},
	}
	for _, d := range domains {
		cx := d.x + 150
		P = append(P, box(d.x, 150, 300, 64, "core", 14),
			textF(cx, 191, "t", d.name, ""),
			line(cx, 214, cx, 246, "line"),
			box(d.x, 246, 300, 364, "card", 12))
		for i, n := range d.nodes {
			cls := "t"
			if strings.HasPrefix(n, "·") {
				cls = "tm"
			}
			P = append(P, textF(cx, 286+i*52, cls, n, ""))
		}
	}
	P = append(P,
		box(160, 660, 880, 88, "warn", 12),
		textF(600, 696, "t", "学生遇错 / 浏览代码 → 动态激活相关概念子图，展示知识间关联", ""),
		textF(600, 726, "tc", "现有基础：error_catalog 错误码中文解释 · 算法检测器 7 种 AST 模式识别 · 模板 meta.yaml 的 knowledge_nodes 标注", ""),
	)
	writeSVG(root, "docs/current/05-教学体验/cognitive-knowledge-graph.svg", P)
}

// ─── 图 D：影子验证·门禁流水线（源：影子验证框架.md §一/§三/§2.3）────────────
// 本图的跑批快照数字全部 data-fact 锚定 facts 台账。

func genShadow(root string, fd factsDoc) {
	cases := mustFact(fd, "shadow_c_cases")
	match := mustFact(fd, "shadow_c_match")
	knownN := mustFact(fd, "shadow_c_known_issue")
	gapExtN := mustFact(fd, "shadow_c_gap_extension")
	gaps := mustFact(fd, "shadow_c_gaps")
	cppCases := mustFact(fd, "shadow_cpp_cases")
	cppMatch := mustFact(fd, "shadow_cpp_match")
	cppFail := mustFact(fd, "shadow_cpp_clang_fail")

	P := svgOpen(1200, 820, "vitro 影子验证门禁流水线", "影子验证框架 · Clang 影子对照与 CI 硬门禁",
		"对账 影子验证框架.md §一思想 + §三流程 + §2.3 五分类门禁判定表；快照数字 data-fact 锚定 reports/facts.json")
	P = append(P,
		textF(600, 54, "tt", "影子验证 · Clang 影子对照与 CI 硬门禁", ""),
		textF(600, 88, "tm", "「下一步该实现什么特性？」—— 收集缺失特性数据，驱动 ROADMAP 优先级（区别于双轨验证的“已实现的特性对不对”）", ""),
	)
	steps := []struct {
		t, d string
		dy   int
		fact string
		val  int
	}{
		{"收集标准 C 测试用例", "baseline / gap / template_generated 目录热加载 · 空集 fail loud(exit 2)", 0, "", 0},
		{"跑影子验证 Clang vs Vitro", "用例冷启动 ~26s（16 并发）/ 缓存热跑 ~5s · stdin 同字节注入", 130, "shadow_c_cases", 0},
		{"五分类判定（逐字节比对 stdout）", "match ≡ · vitro_better 更完整 · known_issue 在案 · compile/runtime/output_gap", 260, "", 0},
	}
	SY, SH, SW := 130, 96, 720
	for i, st := range steps {
		y := SY + i*(SH+34)
		P = append(P, box(240, y, SW, SH, "card", 14))
		P = append(P, textF(600, y+40, "t", st.t, ""))
		if st.fact != "" {
			// "Go 驱动 · 680 用例冷启动…"——数字 tspan 锚定
			P = append(P, textSegs(600, y+72, "tc", []seg{
				{text: "Go 驱动 · "},
				{num: st.fact, val: cases},
				{text: st.d},
			}))
		} else {
			P = append(P, textF(600, y+72, "tc", st.d, ""))
		}
		if i < len(steps)-1 {
			P = append(P, line(600, y+SH, 600, y+SH+34, "line"))
		}
	}
	forkY := SY + 3*(SH+34) + 10
	P = append(P,
		line(600, SY+3*SH+2*34, 600, forkY, "line"),
		line(300, forkY, 900, forkY, "line"),
		line(300, forkY, 300, forkY+36, "line"),
		line(900, forkY, 900, forkY+36, "line"),
		box(110, forkY+36, 380, 150, "core", 14),
		textF(300, forkY+76, "t", "通过（视为绿）", ""),
		textF(300, forkY+108, "tm", "match · vitro_better · known_issue", ""),
		textF(300, forkY+140, "tc", "KNOWN_FAILURE_CASES 与 E2E 防线", ""),
		textF(300, forkY+164, "tc", "双向对齐，转绿未更新文档即 CI 失败", ""),
		box(710, forkY+36, 380, 150, "warn", 14),
		textF(900, forkY+76, "t", "非预期差异（exit 1）", ""),
		textF(900, forkY+108, "tm", "compile_gap / runtime_gap / output_gap", ""),
		textF(900, forkY+140, "tc", "缺失特性频率排序 → 确定 Top 3", ""),
		textF(900, forkY+164, "tc", "→ 驱动扩展优先级，进入开发实现", ""),
	)
	// 规模脚注拆两行（原单行贴边），每个数字独立 tspan 锚。
	P = append(P,
		textSegs(600, 756, "tc", []seg{
			{text: "当前规模：C "},
			{num: "shadow_c_cases", val: cases},
			{text: "（"},
			{num: "shadow_c_match", val: match},
			{text: " match + "},
			{num: "shadow_c_known_issue", val: knownN},
			{text: " known_issue + "},
			{num: "shadow_c_gap_extension", val: gapExtN},
			{text: " gap_extension，"},
			{num: "shadow_c_gaps", val: gaps},
			{text: " 非预期差异）"},
		}),
		textSegs(600, 784, "tc", []seg{
			{text: "C++ "},
			{num: "shadow_cpp_cases", val: cppCases},
			{text: "（"},
			{num: "shadow_cpp_match", val: cppMatch},
			{text: " 一致 + "},
			{num: "shadow_cpp_clang_fail", val: cppFail},
			{text: " 已记录 clang_compile_fail）· Clang 预检缺失即 fail fast(exit 2)"},
		}),
		textF(600, 810, "tc", "数据 as_of "+asOfOf(fd, "shadow_c_cases")+" · reports/facts.json（漂移重生成：go run ./scripts/gen_svg）", ""),
	)
	writeSVG(root, "docs/current/04-标准库与防线/shadow-verification-flow.svg", P)
}

// ─── 入口 ────────────────────────────────────────────────────────────────────

func main() {
	which := "all"
	if len(os.Args) > 1 {
		which = os.Args[1]
	}
	root, err := os.Getwd()
	if err != nil {
		fatal(err.Error())
	}
	if _, err := os.Stat(filepath.Join(root, "go.mod")); err != nil {
		fatal("请在项目根目录运行（找不到 go.mod）")
	}
	fd := loadFacts(root)
	switch which {
	case "arch":
		genArch(root, fd)
	case "cache":
		genCache(root, fd)
	case "kg":
		genKG(root, fd)
	case "shadow":
		genShadow(root, fd)
	case "all":
		genArch(root, fd)
		genCache(root, fd)
		genKG(root, fd)
		genShadow(root, fd)
	default:
		fatal("未知目标: " + which + "（可用: arch / cache / kg / shadow / all）")
	}
}
