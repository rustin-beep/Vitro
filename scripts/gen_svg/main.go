package main

// 文档插图生成器 —— 探针转正 Go 重写（2026-09-20，原 tmp/gen_arch_svg.py +
// tmp/gen_three_svg.py 退役）；2026-09-24 扩为九张（新增包切分/统一模式架构/
// 状态机/内存布局/协议帧/wasm 并发五张，来源与对账见各 gen 函数头注）。
//
// 入库插图的跑批快照数字**只在此处为模板**：生成时从
// reports/facts.json 读真值注入，并以 <tspan data-fact="key">n</tspan> 显式
// 锚定；scripts/facts check 逐锚机判漂移。漂移工作流：
//
//	跑防线（或 go run ./scripts/facts）→ facts check 红（SVG 数字过时）
//	→ go run ./scripts/gen_svg → facts check 绿
//
// 禁止手改入库 SVG 的 data-fact 锚定数字——下次生成即回退（facts 的
// interactiveSync 也刻意跳过 .svg 命中）。设计常量（2000 帧 / 50 检查点 /
// 256KB 隔离预算等）与建包进度徽标不是跑批快照、无锚，改动属代码常量
// 变更，走评审。
//
// 用法：go run ./scripts/gen_svg [arch|cache|kg|shadow|packages|uarch|ustate|memory|protocol|wasm|all]
//（默认 all）
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

// arrow：带三角箭头的直线（marker orient=auto 按线方向旋转）。
func arrow(x1, y1, x2, y2 int, cls string) string {
	return fmt.Sprintf(`<line class="%s" x1="%d" y1="%d" x2="%d" y2="%d" marker-end="url(#ah)"/>`,
		cls, x1, y1, x2, y2)
}

// arrowPoly：正交折线箭头（末段出箭头）。pts 形如 "x1,y1 x2,y2 x3,y3"。
func arrowPoly(pts, cls string) string {
	return fmt.Sprintf(`<polyline class="%s" points="%s" marker-end="url(#ah)"/>`, cls, pts)
}

// textL：左对齐文本（表格式排版用）。
func textL(x, y int, cls, s string) string {
	return fmt.Sprintf(`<text class="%s" x="%d" y="%d" text-anchor="start">%s</text>`, cls, x, y, esc(s))
}

// markerDef：箭头头部（每图一次）。颜色走 class，随深浅模式联动。
const markerDef = `  <defs>
    <marker id="ah" viewBox="0 0 10 10" refX="8.5" refY="5" markerWidth="6.5" markerHeight="6.5" orient="auto-start-reverse">
      <path d="M0,0 L10,5 L0,10 z" class="ahf"/>
    </marker>
  </defs>`

const css = `  <style>
    .bg     { fill: #FFFFFF; }
    .core   { fill: #155E86; fill-opacity: .07; stroke: #155E86; stroke-width: 3; }
    .card   { fill: #155E86; fill-opacity: .05; stroke: #155E86; stroke-width: 2.5; }
    .cons   { fill: none; stroke: #94A3AD; stroke-width: 2; }
    .warn   { fill: #155E86; fill-opacity: .04; stroke: #94A3AD; stroke-width: 2; stroke-dasharray: 7 5; }
    .plan   { fill: none; stroke: #94A3AD; stroke-width: 1.8; stroke-dasharray: 5 4; }
    .line   { stroke: #94A3AD; stroke-width: 3; fill: none; }
    .edge   { stroke: #94A3AD; stroke-width: 2.5; fill: none; }
    .ahf    { fill: #94A3AD; stroke: none; }
    .tn     { font-family: "Consolas","Cascadia Mono",monospace; font-size: 17px; fill: #155E86; stroke: none; }
    .zone   { fill: #155E86; fill-opacity: .028; stroke: #155E86; stroke-width: 1.6; }
    .tt     { font-family: "Segoe UI","Microsoft YaHei",sans-serif; font-size: 34px; font-weight: 600; fill: #0D1B24; stroke: none; }
    .t      { font-family: "Segoe UI","Microsoft YaHei",sans-serif; font-size: 23px; fill: #0D1B24; stroke: none; }
    .ts     { font-family: "Consolas","Cascadia Mono",monospace; font-size: 21px; fill: #155E86; stroke: none; }
    .tm     { font-family: "Segoe UI","Microsoft YaHei",sans-serif; font-size: 20px; fill: #5A6B75; stroke: none; }
    .tc     { font-family: "Segoe UI","Microsoft YaHei",sans-serif; font-size: 18px; fill: #5A6B75; stroke: none; }
    @media (prefers-color-scheme: dark) {
      .bg   { fill: #0D1B24; }
      .core { stroke: #4FB3E8; fill: #4FB3E8; fill-opacity: .1; }
      .card { stroke: #4FB3E8; fill: #4FB3E8; fill-opacity: .07; }
      .zone { stroke: #4FB3E8; fill: #4FB3E8; fill-opacity: .05; }
      .cons, .warn, .plan { stroke: #5A6B75; }
      .line, .edge { stroke: #5A6B75; }
      .ahf  { fill: #5A6B75; }
      .tt, .t { fill: #E9F1F7; }
      .ts, .tn { fill: #4FB3E8; }
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
		{"出口 2：wasm32", ".wasm + 薄 JS/TS 绑定", "3.75MB 冒烟实证"},
		{"出口 3：vitro_cli serve", "JSON-lines 会话模式", "headless 交互"},
	}
	// 消费者文案逐条对账 README.md:17-30（不增减事实）。用例规模数字留在
	// README（facts md 通道对账）——架构图口径化"全量 C 语料"，消掉随跑批
	// 漂移的第二份拷贝。
	// 2026-09-24 观感批允许缩略（事实不增减）：wasm32-unknown-unknown→wasm32、
	// 省略 E3070 字样——字号上调后卡宽所限，详名见 README 正文。
	consLines := [][]string{
		{"第一消费者：vitro_cli", "scripts/shadow_verify.go（capi 直调）",
			"全量 C 语料的生产验证", "第三方教学 IDE（P/Invoke）· 任意语言 FFI"},
		{"浏览器前端（社区）· 在线教学演示", "移动浏览器“看”场景",
			"已冒烟实证：零修改构建 3.75MB", "C API 全链路 + 安全检测可用"},
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
			box(x, 520, 360, 124, "cons", 12),
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
	P := svgOpen(1200, 716, "vitro 统一模式三态缓存", "统一模式 · 三态缓存（Triple-Cache）",
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
			{156, "tm", "VM 状态恢复·继续执行"},
			{184, "tm", "大小：全量 50MB → 增量 5~10MB"},
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
		box(120, 470, 960, 146, "warn", 12),
		textF(600, 508, "t", "CheckpointManager 落地机制（§5.2，2026-09-11 核对）", ""),
		textF(600, 540, "tc", "每 full_every 个检查点存完整 1MB 全量，其余仅存被修改的 4KB 脏页", ""),
		textF(600, 566, "tc", "上限 max_checkpoints = 50 · smart_mode 语义关键点强制保存", ""),
		textF(600, 592, "tc", "隔离区 quarantine 必须随快照往返，否则时间旅行回退后 UAF 检测出现假阴性", ""),
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
			"指针 Pointer", "· 取址 / 解引用 / 指针算术", "数组 Array（· 数组退化）", "结构体布局 StructLayout"}},
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
		box(160, 660, 880, 100, "warn", 12),
		textF(600, 696, "t", "学生遇错 / 浏览代码 → 动态激活相关概念子图，展示知识间关联", ""),
		textF(600, 722, "tc", "现有基础：error_catalog 中文解释 · 7 种 AST 模式识别 ·", ""),
		textF(600, 748, "tc", "模板 meta.yaml 的 knowledge_nodes 标注", ""),
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

	P := svgOpen(1200, 836, "vitro 影子验证门禁流水线", "影子验证框架 · Clang 影子对照与 CI 硬门禁",
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

// ─── 图 E：MoonBit 包切分分层 L0–L9（源：总计划 §4 包切分总图 + §10 里程碑）──
// 对账总计划 §4 逐层文字；虚线框 = 规划未建包；进度徽标为截至生成批次的状态
// 快照（无 data-fact 锚，权威 = 总计划 §10）。

type pkgCell struct {
	name, desc string
	plan       bool // 规划未建包（虚线框）
}

type layerRow struct {
	tag, name, badge string
	rows             [][]pkgCell
	note             string // 层内底部补充行（可空）
}

func genPackages(root string, _ factsDoc) {
	// 2026-09-24 观感批（用户反馈"挤、字小"）：拆为编译侧（L0–L6）与执行与
	// 智能侧（L7–L9+仓库外）两张；字号随共享 CSS 上调，行距 82 / 卡高 60。
	type lyr struct {
		tag, name, badge string
		rows             [][]pkgCell
		note             string
	}
	compile := []lyr{
		{"L0", "零依赖", "0.5.0 在架", [][]pkgCell{
			{{"vitro/engine/source", "SourceLoc + 坐标契约（字节偏移 +1 · 双坐标）", false},
				{"vitro/engine/opcode", "132 opcodes 稳定编号 + operand 校验", false}}},
			""},
		{"L1", "诊断契约", "0.5.0 在架", [][]pkgCell{
			{{"vitro/engine/diag", "ErrorCode 137 臂 + Severity + SourceLang + catalog JSON + 覆盖率断言", false}}},
			""},
		{"L2", "抽象语法", "0.5.0 在架", [][]pkgCell{
			{{"vitro/engine/ast", "Type 17 / Expr 26 / Stmt 16 + depth + 判等渲染单源", false}}},
			""},
		{"L3", "名字单源", "0.4.0 在架", [][]pkgCell{
			{{"vitro/engine/names", "InstKey→InstId→mangled Name 唯一产出口（parser / typeck 共依赖）", false}}},
			""},
		{"L4", "前端", "0.5.0 在架", [][]pkgCell{
			{{"vitro/engine/lexer", "独立预处理 pass + LineMap + 宿主 IO", false},
				{"vitro/engine/parser", "token→AST · 瀑布 + 声明符螺旋 · depth 守卫", false}},
			{{"csharp/lexer + csharp/parser", "〔CS 批·S6 后〕C# 前端；插值字符串 hole 级 span", true}}},
			""},
		{"L5", "语义", "0.4.0 在架", [][]pkgCell{
			{{"vitro/engine/typeck", "定型 + lowering（4 Pass）", false},
				{"vitro/engine/containers", "JSON 数据驱动 · S9 裁定", false},
				{"vitro/engine/libc", "单表签名 57 + 放行 175", false}},
			{{"csharp/typeck", "〔CS 批〕引用语义 / 类系统 / 异常类型链 / ARC 插桩点判定（共享切线=表达式/语句层）", true}}},
			""},
		{"L6", "发射", "0.4.0 在架", [][]pkgCell{
			{{"vitro/engine/codegen", "compile/compile_library 双入口 · 槽位 v1", false},
				{"vitro/engine/bytecode", "产物 schema + libc 固定索引 + 路由表单源", false}},
			{{"csharp/codegen", "〔CS 批〕ARC 插桩 / 异常映射 trap→Throw / 顶层语句入口合成", true}}},
			""},
	}
	runtime := []lyr{
		{"L7", "执行", "S6 进行中", [][]pkgCell{
			{{"vitro/engine/memory", "MemoryMap + checked_access 单入口", false},
				{"vitro/engine/host", "路由表消费侧 · Bytes 输出通道 · 100+ handlers", false}},
			{{"vitro/engine/vm", "executor 穷尽 match + snapshot 派生 · 未开工", true},
				{"vitro/engine/jit", "〔S9 裁定批〕必须可整体移除", true}}},
			""},
		{"L8", "会话/协议", "S7 未开工", [][]pkgCell{
			{{"vitro/engine/session", "SessionConfig 值对象", false},
				{"vitro/engine/protocol", "帧 + schema + 词汇表", false},
				{"vitro/engine/gateway", "wasm-gc 4 函数导出 + NDJSON", false}}},
			""},
		{"L9", "教学智能", "S8 未开工", [][]pkgCell{
			{{"time_travel", "seek / 检查点重放", false},
				{"teaching/steps", "算法步骤语义", false},
				{"analysis", "cfg / algorithms", false},
				{"diagnostics", "根因 / 误区", false}}},
			"── 经 VmObserver / SourceProvider / AlgorithmContext 三接口依赖反转，不依赖 session"},
	}
	drawLayers := func(title, sub string, layers []lyr, canvasH int, out string, withOutside bool) {
		P := svgOpen(1200, canvasH, "vitro MoonBit 包切分分层图", title,
			"对账 MoonBit迁移总计划.md §4 包切分总图逐层文字；虚线框=规划未建包；进度徽标截至生成批次（权威=总计划 §10）")
		P = append(P, markerDef,
			textF(600, 56, "tt", title, ""),
			textF(600, 94, "tm", sub, ""),
		)
		y := 118
		for _, lr := range layers {
			h := 12 + len(lr.rows)*72 + 12
			if len(lr.rows) > 1 {
				h += 10
			}
			if lr.note != "" {
				h += 26
			}
			P = append(P, box(20, y, 1160, h, "card", 12),
				textL(40, y+34, "t", lr.tag),
				textL(40, y+62, "tc", lr.name))
			if lr.badge != "" {
				P = append(P, textL(1065, y+34, "tc", lr.badge))
			}
			for j, row := range lr.rows {
				fy := y + 12 + j*82
				var ws []int
				switch len(row) {
				case 1:
					ws = []int{880}
				case 2:
					ws = []int{433, 433}
				case 3:
					ws = []int{280, 280, 280}
				default:
					ws = []int{210, 210, 210, 210}
				}
				gap := 0
				if len(ws) > 1 {
					gap = (880 - sum(ws)) / (len(ws) - 1)
				}
				x := 175
				for k, pc := range row {
					pcls := "card"
					if pc.plan {
						pcls = "plan"
					}
					nameCls := "ts"
					if len(row) > 2 {
						nameCls = "tn"
					}
					P = append(P, box(x, fy, ws[k], 60, pcls, 10),
						textL(x+16, fy+26, nameCls, pc.name),
						textL(x+16, fy+50, "tc", pc.desc))
					x += ws[k] + gap
				}
			}
			if lr.note != "" {
				P = append(P, textL(175, y+h-16, "tc", lr.note))
			}
			y += h + 18
		}
		if withOutside { // 执行与智能侧附仓库外横条
			P = append(P, box(20, y, 1160, 60, "warn", 12),
				textL(40, y+36, "t", "仓库外"),
				textL(175, y+36, "tm", "Go 驱动层（保留·司法/驱动语言）· Node engine-host（新增薄层·golden 生成宿主）· spike 目录"))
			y += 78
		}
		P = append(P,
			textF(600, y+24, "tc", "硬约束：依赖严格单向无环 · .mbti 只暴露 protocol / lexer.tokenize / typeck.check 三面 · 版本锚 protocol_version 编译期常量", ""),
			textF(600, y+50, "tc", "虚线框 = 规划未建包 · 进度徽标截至 2026-09-24（权威：总计划 §10）· 漂移重生成：go run ./scripts/gen_svg packages", ""),
		)
		writeSVG(root, out, P)
	}
	sub := "module vitro/engine · 依赖严格单向无环 · .mbti 取代 ABI 版本化成为对外义务载体"
	drawLayers("MoonBit 迁移 · 包切分分层（L0–L6 编译侧）", sub, compile, 1230,
		"docs/current/01-定位与路线/moonbit-package-layers-compile.svg", false)
	drawLayers("MoonBit 迁移 · 包切分分层（L7–L9 执行与智能侧）", sub, runtime, 720,
		"docs/current/01-定位与路线/moonbit-package-layers-runtime.svg", true)
}

func sum(ws []int) int {
	t := 0
	for _, w := range ws {
		t += w
	}
	return t
}

// ─── 图 F：统一模式架构总览（源：统一模式设计.md §3 ASCII 架构图）────────────

func genUnifiedArch(root string, _ factsDoc) {
	P := svgOpen(1200, 902, "vitro 统一模式架构总览", "统一模式 · 架构总览",
		"对账 统一模式设计.md §3 架构总览图（消费方前端 → 三出口 → session_api → UnifiedEngine → VitroVM）")
	P = append(P, markerDef,
		textF(600, 56, "tt", "统一模式 · 架构总览", ""),
		textF(600, 94, "tm", "消费方前端（社区实现）经三出口触及 session_api 与 UnifiedEngine；seek 越窗 = 最近 Checkpoint 恢复 + 正向重放", ""),
	)
	// 消费方前端
	P = append(P, box(40, 112, 1120, 240, "core", 14),
		textL(64, 146, "t", "消费方前端（社区实现；本仓库不含前端）"))
	comps := []struct {
		x          int
		name, desc string
	}{
		{64, "CodeEditor + Heatmap", "代码编辑 + 执行热力条带"},
		{424, "ExecControlPanel", "Play / Pause / Step / Slider"},
		{784, "AlgoCanvas / VisPanel", "算法可视化 · 变量 · 内存面板"},
	}
	for _, c := range comps {
		cx := c.x + 168
		P = append(P, box(c.x, 162, 336, 76, "card", 12),
			textF(cx, 192, "t", c.name, ""),
			textF(cx, 220, "tc", c.desc, ""))
	}
	P = append(P, box(64, 254, 1056, 94, "card", 12),
		textF(592, 282, "t", "消费方执行控制器（阶段机 + 本地视图缓存）", ""),
		textF(592, 310, "tc", "FrameCache（窗口内 payload 的本地副本，可选）· StateMachine: Idle / Collecting / Paused / Playback / Seeking", ""),
		textF(592, 334, "tc", "CurrentStep: int", ""))
	// 出口带（加高：文字与后端框缘脱开）
	P = append(P, arrow(600, 352, 600, 414, "line"),
		textL(620, 378, "tm", "出口：capi JSON / serve JSON-lines / wasm 绑定"),
		textL(620, 404, "tc", "出口只做薄包装，语义一律取自 session_api"))
	// Rust 后端
	P = append(P, box(40, 421, 1120, 405, "core", 14),
		textL(64, 455, "t", "Rust 后端"))
	P = append(P, box(200, 462, 800, 50, "card", 10),
		textF(600, 492, "t", "session_api —— 语言中立会话语义层（三出口共用同一套入口语义）", ""))
	P = append(P, arrow(600, 512, 600, 536, "line"),
		box(100, 536, 1000, 200, "card", 12),
		textF(600, 568, "ts", "UnifiedEngine（native/src/unified/engine.rs）", ""))
	ue := []struct {
		x          int
		name, desc string
	}{
		{130, "run_batch", "step_loop 推进 · collect 收集"},
		{450, "CheckpointMgr", "checkpoints · seek()"},
		{770, "VM (Active)", "memory 1MB · value_stack"},
	}
	for _, u := range ue {
		cx := u.x + 150
		P = append(P, box(u.x, 584, 300, 80, "zone", 10),
			textF(cx, 614, "t", u.name, ""),
			textF(cx, 636, "tc", u.desc, ""))
	}
	// 三小卡汇流到 VitroVM
	P = append(P,
		line(280, 664, 280, 706, "line"),
		line(600, 664, 600, 706, "line"),
		line(920, 664, 920, 706, "line"),
		line(280, 706, 920, 706, "line"),
		arrow(600, 706, 600, 746, "line"),
		box(100, 746, 1000, 76, "card", 12),
		textF(600, 774, "t", "VitroVM：step_next() · snapshot() / restore() · read_memory(addr)", ""),
		textF(600, 800, "tc", "快照/恢复实现 crates/vitro_vm/src/snapshot.rs（CheckpointManager）· 隔离区 quarantine 必须随快照往返", ""),
	)
	P = append(P,
		textF(600, 854, "tc", "一致性契约：seek 到第 N 步后 local_vars / call_stack / array_snapshots / pointer_snapshots / heatmap_count 以第 N 步快照为准（spec §4.3）", ""),
		textF(600, 880, "tc", "对账 统一模式设计.md §3 · 漂移重生成：go run ./scripts/gen_svg uarch", ""),
	)
	writeSVG(root, "docs/current/05-教学体验/unified-architecture.svg", P)
}

// ─── 图 G：统一模式六状态机（源：统一模式设计.md §4 状态图 + §4.1/§4.2）──────

func genStateMachine(root string, _ factsDoc) {
	P := svgOpen(1200, 920, "vitro 统一模式六状态机", "统一模式 · 六状态有限状态机",
		"对账 统一模式设计.md §4 状态图与 §4.2 关键状态转换（边文字逐条取原文）")
	P = append(P, markerDef,
		textF(600, 56, "tt", "统一模式 · 六状态有限状态机", ""),
		textF(600, 94, "tm", "所有用户操作都触发状态转换（§4）· 边标注 = 用户操作原文", ""),
	)
	states := []struct {
		x, y       int
		name, hint string
	}{
		{70, 150, "Idle", "编辑器可编辑"},
		{500, 150, "Collecting", "自动前进·动画跟随"},
		{930, 150, "Playback", "执行结束·可自由拖动"},
		{500, 430, "Paused", "进度暂停·动画定格"},
		{930, 430, "Seeking", "拖动中·动画跟随"},
		{500, 690, "StepMode", "单步·类似传统调试器"},
	}
	for _, s := range states {
		cx := s.x + 100
		P = append(P, box(s.x, s.y, 200, 78, "card", 12),
			textF(cx, s.y+34, "t", s.name, ""),
			textF(cx, s.y+64, "tc", s.hint, ""))
	}
	P = append(P,
		arrow(270, 189, 500, 189, "edge"), textF(385, 174, "tc", "编译运行", ""),
		arrow(700, 172, 930, 172, "edge"), textF(815, 158, "tc", "执行结束", ""),
		arrow(930, 206, 700, 206, "edge"), textF(815, 232, "tc", "继续执行", ""),
		arrow(570, 228, 570, 430, "edge"), textF(516, 330, "tc", "暂停", ""),
		arrowPoly("500,728 440,728 440,210 500,210", "edge"),
		textF(360, 560, "tc", "自动播放", ""),
		arrow(600, 508, 600, 690, "edge"), textF(654, 600, "tc", "继续", ""),
		arrow(1030, 228, 1030, 430, "edge"), textF(1100, 330, "tc", "拖动进度条", ""),
		arrow(985, 430, 985, 228, "edge"), textF(922, 330, "tc", "恢复完成", ""),
		arrow(930, 469, 700, 469, "edge"), textF(815, 456, "tc", "用户暂停/拖动", ""),
		arrowPoly("500,748 150,748 150,228", "cons"),
		textF(310, 700, "tc", "任何状态：修改代码", ""),
		textF(310, 726, "tc", "→ 提示重新编译、重置缓存", ""),
		textF(205, 258, "tc", "点击“重跑”", ""),
		box(60, 800, 1080, 84, "card", 12),
		textF(600, 832, "t", "seek 一致性契约（spec/STEP_PAYLOAD_SCHEMA_V0_1.md §4.3）", ""),
		textF(600, 862, "tc", "seek 到第 N 步：local_vars / call_stack / array_snapshots / pointer_snapshots / heatmap_count 以第 N 步快照为准（消费方整体重绘）", ""),
	)
	writeSVG(root, "docs/current/05-教学体验/unified-state-machine.svg", P)
}

// ─── 图 H：1MB 线性内存布局与有界隔离（源：内存安全规范 §3.4 + 堆有界隔离决议）─

func genMemory(root string, _ factsDoc) {
	P := svgOpen(1200, 900, "vitro 线性内存布局与有界隔离", "VitroVM · 1MB 线性内存布局 + 堆有界隔离（Bounded Quarantine）",
		"对账 内存安全规范.md §3.4 + 堆有界隔离决议.md §1–§5；地址段为设计常量（非快照，无 data-fact 锚）")
	P = append(P, markerDef,
		textF(600, 56, "tt", "VitroVM · 1MB 线性内存布局 + 堆有界隔离", ""),
		textF(600, 94, "tm", "VM 的堆不是宿主 allocator，而是 1MB 线性内存中的一段；释放不立即归还，先进有界隔离区（FIFO 驱逐复用）", ""),
	)
	type segRow struct {
		dy int
		cl string
		s  string
	}
	segs := []struct {
		y0, y1 int
		cls    string
		rows   []segRow
	}{
		{122, 242, "zone", []segRow{{36, "t", "栈 Stack（顶 = 1MB）"}, {66, "tc", "自高地址向下 ↓"}, {92, "tc", "局部变量 / 调用帧"}}},
		{242, 322, "zone", []segRow{{34, "t", "argv"}, {64, "tc", "自 0x10000（64KB）向下分配"}}},
		{322, 402, "bg", []segRow{{50, "tc", "（未用地址空间）"}}},
		{402, 522, "warn", []segRow{{34, "t", "隔离区 quarantine"}, {64, "tc", "FIFO · 预算 = 堆上限 1/4 = 256KB"}, {90, "tc", "超预算驱逐最老已释放块"}}},
		{522, 582, "zone", []segRow{{40, "tc", "bump 已分配 ↑（顶指针 O(1)）"}}},
		{582, 642, "zone", []segRow{{40, "tc", "first-fit 复用（驱逐后归还）"}}},
		{642, 722, "zone", []segRow{{32, "t", "全局区（0x1000 起）"}, {60, "tc", "全局变量·extern·vtable·字符串字面量·静态局部"}}},
		{722, 776, "bg", []segRow{{32, "tc", "0x0–0x1000 保留"}}},
	}
	for _, sg := range segs {
		if sg.cls != "bg" {
			P = append(P, box(150, sg.y0, 410, sg.y1-sg.y0, sg.cls, 0))
		}
		for _, r := range sg.rows {
			P = append(P, textF(355, sg.y0+r.dy, r.cl, r.s, ""))
		}
	}
	for _, tk := range []struct {
		y int
		a string
	}{{122, "0x100000"}, {322, "0x10000"}, {642, "0x5000"}, {722, "0x1000"}, {776, "0x0"}} {
		P = append(P, line(116, tk.y, 150, tk.y, "cons"), textL(20, tk.y+7, "ts", tk.a))
	}
	P = append(P, box(610, 122, 560, 192, "card", 12),
		textF(890, 154, "t", "bump 分配 + 有界隔离（决议 2026-09-11）", ""),
		textL(630, 188, "tc", "malloc：顶指针 O(1) 推进；隔离超预算 → 先 FIFO 驱逐"),
		textL(630, 214, "tc", "free：标记 + 进 FIFO 隔离区，不立即归还"),
		textL(630, 240, "tc", "realloc：恒为新块拷贝（与 glibc 常见路径一致）"),
		textL(630, 266, "tc", "heap_base = max(0x5000, align4(global_data_end))（R1）"),
		textL(630, 292, "tc", "预算会话可调：vitro_set_quarantine_budget（默认 256KB）"),
	)
	P = append(P, box(610, 334, 560, 208, "card", 12),
		textF(890, 366, "t", "教学四场景（churn / leak 正确分离）", ""),
		textL(630, 400, "tc", "churn：隔离稳态 ≤ 预算，驱逐复用 → 无限可跑（不误伤）"),
		textL(630, 426, "tc", "leak：不进隔离区，bump 推进 → 撞 1MB 墙 → 教学 trap"),
		textL(630, 452, "tc", "UAF：检测窗口 = 最近 256KB free 历史，覆盖率极高"),
		textL(630, 478, "tc", "Double-Free：隔离窗口内地址不复用 → 必检出"),
		textL(630, 504, "tc", "时间旅行：隔离窗口内内存单调（CoW 与确定性受益）"),
	)
	P = append(P, box(610, 562, 560, 140, "card", 12),
		textF(890, 594, "t", "三道墙（决议 §6，全部已实施）", ""),
		textL(630, 628, "tc", "① 1MB 堆墙：malloc 耗尽 → 返 NULL + 教学 trap"),
		textL(630, 654, "tc", "② 步数保险丝 max_steps（会话配置，reset 保留）"),
		textL(630, 680, "tc", "③ region 表封顶（记账侧有界）"),
	)
	P = append(P, box(610, 722, 560, 92, "zone", 12),
		textL(630, 750, "tc", "MoonBit vitro/engine/memory 已建包（S6）"),
		textL(630, 774, "tc", "MemoryMap + check_access 单入口 + FreedLogs 二分"),
		textL(630, 798, "tc", "地址布局常量定义点仍在 L6 bytecode"),
	)
	P = append(P,
		textF(600, 848, "tc", "诚实记录：隔离窗口外 UAF 可能漏检——free 与误用之间 churn 超过 256KB 后，*p 落在已复用块（同 ASAN quarantine 行为）", ""),
		textF(600, 874, "tc", "布局示意不按比例 · 对账 内存安全规范 §3.4 + 堆有界隔离决议 · 漂移重生成：go run ./scripts/gen_svg memory", ""),
	)
	writeSVG(root, "docs/current/01-定位与路线/memory-layout-quarantine.svg", P)
}

// ─── 图 I：StepPayload v0.1 帧结构（源：docs/spec/STEP_PAYLOAD_SCHEMA_V0_1.md §0–§5）──

func genProtocol(root string, _ factsDoc) {
	P := svgOpen(1200, 940, "vitro StepPayload v0.1 帧结构", "StepPayload Schema v0.1 · 单步快照帧（已冻结）",
		"对账 docs/spec/STEP_PAYLOAD_SCHEMA_V0_1.md §0–§5；字段清单为 schema 冻结内容（非快照，无 data-fact 锚）")
	P = append(P,
		textF(600, 56, "tt", "StepPayload Schema v0.1 · 单步快照帧", ""),
		textF(600, 94, "tm", "已冻结（2026-09-12 · S1–S5 签字回放 61/61）· 语言中立，任何语言按此解析步数据，无需了解 Rust 内部表示", ""),
		textF(600, 138, "tc", "（同一语义）出口：capi vitro_step_next_json · vitro_get_step_payloads_json(session, start, end) · serve NDJSON · wasm 绑定", ""),
		box(40, 174, 720, 638, "core", 14),
		textL(64, 204, "ts", "StepPayload（单步快照 · 14 顶层字段）"),
		textL(64, 234, "tc", "── 步定位 ──"),
		textL(64, 258, "ts", "step_index"), textL(280, 258, "tc", "int32 · 步号 0 起；一步 = 一条字节码指令"),
		textL(64, 282, "ts", "code_line"), textL(280, 282, "tc", "int32 · 源码行 1 起（0 = 无源码行）"),
		textL(64, 306, "ts", "func_name"), textL(280, 306, "tc", "string · 教学可读名（main / bubble_sort）"),
		textL(64, 330, "ts", "semantic_label"), textL(280, 330, "tc", "string · 行 + 值推断的教学语义标签"),
		textL(64, 362, "tc", "── 教学快照 ──"),
		textL(64, 386, "ts", "local_vars"), textL(280, 386, "tc", "ApiVariableSnapshot[] · 当前作用域变量"),
		textL(64, 410, "ts", "call_stack"), textL(280, 410, "tc", "ApiFrameInfo[] · 自底向上，末元素 = 当前帧"),
		textL(64, 434, "ts", "array_snapshots"), textL(280, 434, "tc", "ArraySnapshot[] · 元素上限 256，超出 truncated"),
		textL(64, 458, "ts", "pointer_snapshots"), textL(280, 458, "tc", "PointerSnapshot[] · 四状态见右侧"),
		textL(64, 490, "tc", "── 行为与事件 ──"),
		textL(64, 514, "ts", "vis_events"), textL(280, 514, "tc", "VisEvent[] · 取走式：同一步不重复投递"),
		textL(64, 538, "ts", "heatmap_*"), textL(280, 538, "tc", "heatmap_line + heatmap_count · 该行累计执行次数"),
		textL(64, 562, "ts", "accessed_vars"), textL(280, 562, "tc", "AccessedVar[] · 本步读写的变量"),
		textL(64, 594, "tc", "── 可空（JSON null）──"),
		textL(64, 618, "ts", "algorithm_step"), textL(280, 618, "tc", "AlgorithmStepSnapshot? · 未命中算法模板 = null"),
		textL(64, 642, "ts", "root_cause_hint"), textL(280, 642, "tc", "RootCauseHint? · 无运行时陷阱 = null"),
		textL(64, 690, "tc", "多文件会话：code_line / heatmap_line 为合并源码全局行号（§8 #9）"),
		textL(64, 716, "tc", "地址：1MB 线性内存内 u32（0x1000 全局区起 · 0x5000 堆起 · 栈自高向下）"),
		textL(64, 742, "tc", "可空 = null；消费方须同时容忍字段缺省（新字段可不出现在旧数据）"),
		textL(64, 768, "tc", "枚举取值为字符串字面量，大小写敏感（\"Valid\" / \"Read\"）"),
	)
	P = append(P, box(800, 174, 370, 156, "card", 12),
		textF(985, 204, "t", "pointer 四状态（§3.1）", ""),
		textL(820, 234, "tc", "Valid 有效"),
		textL(820, 260, "tc", "Freed 已释放（判定依赖隔离区）"),
		textL(820, 286, "tc", "Null 空指针"),
		textL(820, 312, "tc", "Dangling 悬垂"),
	)
	P = append(P, box(800, 350, 370, 170, "card", 12),
		textF(985, 382, "t", "frameCache 窗口语义（§4）", ""),
		textL(820, 412, "tc", "payload.get(start, end)：窗口内 O(1)"),
		textL(820, 438, "tc", "越窗 seek：Checkpoint 恢复 + 正向重放"),
		textL(820, 464, "tc", "seek 第 N 步 → 五视图以第 N 步快照为准"),
		textL(820, 490, "tc", "（消费方整体重绘，无需自行回退状态）"),
	)
	P = append(P, box(800, 540, 370, 170, "card", 12),
		textF(985, 572, "t", "差分编码与版本纪律（§5 / §9）", ""),
		textL(820, 602, "tc", "StepStreamBatch / Delta 字段级差分"),
		textL(820, 628, "tc", "解码不变量：delta 后与全量逐字段相等"),
		textL(820, 654, "tc", "字段只增不改语义；新增字段可空 / 有默认"),
		textL(820, 680, "tc", "废弃走双写过渡期；版本 abi + engine"),
	)
	P = append(P, box(800, 730, 370, 104, "zone", 12),
		textF(985, 760, "t", "消费方", ""),
		textL(820, 788, "tc", "capi 第一批 · vitro_cli serve · wasm 绑定"),
		textL(820, 812, "tc", "任何第三方语言按本 schema 自行解析"),
	)
	P = append(P,
		textF(600, 852, "tc", "实现锚：unified/{types,collector,engine,stream,contracts,vocabulary}.rs · capi/first_batch.rs（出口序列化）", ""),
		textF(600, 878, "tc", "对账 docs/spec/STEP_PAYLOAD_SCHEMA_V0_1.md §0–§5 · 漂移重生成：go run ./scripts/gen_svg protocol", ""),
		textF(600, 904, "tc", "步号约定：step_index 从 0 起；一步 = VM 执行一条字节码指令（含透明 StepEvent 调试指令）", ""),
	)
	writeSVG(root, "docs/spec/step-payload-frame.svg", P)
}

// ─── 图 J：wasm 多实例并发隔离（源：wasm多实例并发模型与U2拍板.md §1–§2）──────

func genWasm(root string, _ factsDoc) {
	P := svgOpen(1200, 880, "vitro wasm 多实例并发隔离", "wasm 多实例并发模型 · 1 实例 = 1 线程 = 1 会话",
		"对账 wasm多实例并发模型与U2拍板.md §1 裁定结论 + §2 依据；三宿主形态表逐列对账")
	P = append(P,
		textF(600, 56, "tt", "wasm 多实例并发隔离", ""),
		textF(600, 94, "tm", "裁定（2026-09-19）：每线程一个完全独立的引擎实例——隔离是 wasm 实例模型的构造性质，不依赖引擎侧线程安全改造", ""),
		box(40, 116, 390, 240, "warn", 14),
		textF(235, 150, "t", "反例：capi 单实例形态", ""),
		textF(235, 178, "tc", "（形态本身的构造缺陷，非可修 bug）", ""),
		textF(235, 210, "tc", "单进程单实例全局状态", ""),
		textF(235, 238, "tc", "DLL 并发调用 → 堆损坏（引擎非线程安全）", ""),
		textF(235, 266, "tc", "Vitro 侧调用必须互斥", ""),
		textF(235, 302, "tc", "wasm 多实例是其正解：同进程 N 实例", ""),
		textF(235, 330, "tc", "替代「N 进程 DLL 池」或「单实例互斥」", ""),
		box(470, 116, 700, 248, "core", 14),
		textL(494, 150, "t", "正解：同进程 N 个完全独立的引擎实例"),
	)
	for i := 0; i < 3; i++ {
		x := 494 + i*222
		cx := x + 100
		P = append(P, box(x, 168, 200, 188, "card", 12),
			textF(cx, 198, "ts", fmt.Sprintf("Instance %d", i+1), ""),
			textF(cx, 228, "tc", "1MB 线性内存 ✓", ""),
			textF(cx, 256, "tc", "全局状态 ✓", ""),
			textF(cx, 284, "tc", "VFS + rand MT19937 ✓", ""),
			textF(cx, 312, "tc", "GC 堆（wasm-gc）", ""),
			textF(cx, 338, "tc", "绑定 1 线程 · 1 会话", ""))
	}
	P = append(P,
		box(40, 384, 1130, 68, "core", 12),
		textF(605, 414, "t", "铁律：1 实例 = 1 线程 = 1 会话——同一实例不得跨线程并发调用", ""),
		textF(605, 440, "tc", "实例内部保持单线程不是缺陷：判分确定性与 seek 回放可重放的来源", ""),
	)
	hosts := []struct {
		x    int
		name string
		rows []string
	}{
		{40, "浏览器（IBrowserHost · 终局）", []string{
			"N × Web Worker",
			"Module 结构化克隆进各 worker",
			"各自 instantiate",
			"（编译一次 · 实例化 N 次）",
			"铁律硬度：结构性（worker 各持）"}},
		{425, "Node", []string{
			"worker_threads",
			"structuredClone 支持",
			"WebAssembly.Module 转移",
			"铁律硬度：结构性"}},
		{810, ".NET 内嵌（Wasmtime）", []string{
			"每线程独立 Store + Instance",
			"Module 编译一次（Send+Sync）",
			"每线程 Store::new + instantiate",
			"铁律硬度：类型系统强制",
			"Store 非 Sync：跨线程共享编译失败"}},
	}
	for _, h := range hosts {
		cx := h.x + 180
		P = append(P, box(h.x, 480, 360, 214, "card", 12), textF(cx, 514, "t", h.name, ""))
		for j, r := range h.rows {
			cl := "tc"
			if j == 0 {
				cl = "ts"
			}
			P = append(P, textF(cx, 548+j*28, cl, r, ""))
		}
	}
	P = append(P,
		textL(60, 740, "tc", "边界（诚实记录）：宿主 import 面不在构造性隔离内——输出/输入通道由宿主提供，输出挂宿主全局（console / 单管道）会交错；"),
		textL(60, 766, "tc", "宿主须按实例绑定输出回调；serve 的 session id 概念平移，宿主只做帧路由。"),
		textL(60, 798, "tc", "容量参考：serve RSS 预算 64MB、实测峰值 ~24MB/会话——N 的上限由内存决定，不是并发正确性。"),
		textL(60, 830, "tc", "实证缺口：同进程 N 实例并发互不干扰尚无实测记录（拍板生效前补锚）· wasm32 现产冒烟 3.75MB 即具备全部并发性质。"),
		textF(600, 862, "tc", "对账 wasm多实例并发模型与U2拍板.md §1–§2 · 漂移重生成：go run ./scripts/gen_svg wasm", ""),
	)
	writeSVG(root, "docs/current/06-出口与协议/wasm-multi-instance-isolation.svg", P)
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
	case "packages":
		genPackages(root, fd)
	case "uarch":
		genUnifiedArch(root, fd)
	case "ustate":
		genStateMachine(root, fd)
	case "memory":
		genMemory(root, fd)
	case "protocol":
		genProtocol(root, fd)
	case "wasm":
		genWasm(root, fd)
	case "all":
		genArch(root, fd)
		genCache(root, fd)
		genKG(root, fd)
		genShadow(root, fd)
		genPackages(root, fd)
		genUnifiedArch(root, fd)
		genStateMachine(root, fd)
		genMemory(root, fd)
		genProtocol(root, fd)
		genWasm(root, fd)
	default:
		fatal("未知目标: " + which + "（可用: arch / cache / kg / shadow / packages / uarch / ustate / memory / protocol / wasm / all）")
	}
}
