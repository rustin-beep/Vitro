// moonbit_surface：MoonBit 对外面审计（S5 收尾批·收面前置）。
//
// 用法（cd moonbit）：
//
//	go run ./scripts/moonbit_surface            # 列出各包"无跨包消费"的 pub 符号
//	go run ./scripts/moonbit_surface -check     # 对账白名单：可收集合 ≠ 白名单即红
//
// 判定：一个 pub 符号是**对外面**当且仅当它在本包之外被消费——MoonBit
// 包内不自引用 `@pkg.` 前缀，故 `@pkg.sym` 形态的 grep 天然等于跨包消费。
// 类型符号有消费则其方法/字段面跟随保留（类型可见即可调用其 pub 成员）；
// 类型无消费 → 类型本身进可收清单（成员随之隐没）。
//
// 消费扫描范围：moonbit/**/*.mbt + README*.md（doc 测试是已发布包的
// 文档承诺，计入消费）。排除各包自身源码（`@pkg.` 在包内不出现，无需
// 排除；mbti 文件本身排除）。
//
// **判据盲区登记（2026-09-21 审阅，三条——文本 grep 的已知边界，变更
// 形态时可静默漏检；收面以此闸为主、mbti diff（moon info）为辅）**：
// ① import 别名（as y）——按路径末段猜包名，别名导入的 @y.sym 会算错
//
//	provider；② 注释/字符串内的 @pkg.sym 计为消费（过宽方向，不漏收
//	只可能挡收）；③ 点调用方法（obj.method()）不带前缀——类型经变量
//	流动时方法消费不计（类型符号消费已按类型名覆盖大部分场景）。
//
// 白名单 surface_allowlist.txt：一行一符号（格式 `pkg sym`）= **允许保持
// pub 但当前无消费**的集合（如管线预留/发包面）。-check 双向对账：
// 实际可收集合多出白名单 → 漏收（红）；白名单条目不在实际集合 → 过期
// （红，须清理）。
//
// **发布状态（2026-09-22 核实，原注释已过时）**：`vitro/engine` 已发布
// 0.1.0–0.4.0（本机 registry 实测）。因 MoonBit 的 `moon publish` 是
// **module 级**发布，**0.4.0（2026-09-21 15:49）起 module 下全部对外包
// （16 个）已在架**——"未发布包零成本收面"的窗口正是赶在该发布之前用掉的
// （S5 收尾批收面 27 符号 + 本闸 + `surface_edges.txt` 边清单，2026-09-21）。
// 此后任何收面都是**对已发布包的破坏性变更**，须走版本化弃期；本闸的角色
// 从"收面工具"转为"**防扩散闸**"——新 pub + 新消费边一律拦下要人工裁定。
// 脚本默认全包审计（信息面）。
package main

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

var (
	// mbti 行形态 → 符号
	reFn     = regexp.MustCompile(`^pub fn ([A-Za-z_][A-Za-z0-9_]*)`)
	reMethod = regexp.MustCompile(`^pub fn ([A-Za-z_][A-Za-z0-9_]*)::([A-Za-z_][A-Za-z0-9_]*)`)
	reType   = regexp.MustCompile(`^pub(?:\(all\))? (?:struct|enum) ([A-Za-z_][A-Za-z0-9_]*)`)
	reConst  = regexp.MustCompile(`^pub (?:const|let) ([A-Za-z_][A-Za-z0-9_]*)`)
	// 消费形态：@pkg.sym / @pkg.Type::m / @pkg.Type::Ctor
	reUse = regexp.MustCompile(`@[a-z][a-z0-9_]*\.([A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)?)`)
)

type symbol struct {
	pkg  string
	name string // 函数/常量名 或 类型名（方法归属类型，不单列）
	kind string // fn / const / type / method(归属)
}

func main() {
	if err := os.Chdir("moonbit"); err != nil {
		fmt.Fprintf(os.Stderr, "chdir moonbit failed: %v", err)
		os.Exit(2)
	}

	check := false
	for _, a := range os.Args[1:] {
		if a == "-check" {
			check = true
		}
	}
	pkgs, err := filepath.Glob("*/pkg.generated.mbti")
	if err != nil || len(pkgs) == 0 {
		fatal("未找到包接口面（须在 moonbit/ 下运行）")
	}
	// 消费语料：所有 .mbt + README*.md（含 cmd/ 工具与 doc 测试）
	var corpus []string
	_ = filepath.Walk(".", func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() && (info.Name() == "_build" || info.Name() == ".mooncakes" || info.Name() == "scripts") {
			return filepath.SkipDir
		}
		if !info.IsDir() {
			base := info.Name()
			if strings.HasSuffix(base, ".mbt") || strings.HasPrefix(base, "README") {
				corpus = append(corpus, path)
			}
		}
		return nil
	})
	if len(corpus) == 0 {
		fatal("消费语料为空")
	}
	// 消费索引：pkg → set(sym-path)；边集 consumer provider sym（第二面闸）
	used := map[string]map[string]bool{}
	usedEdges := map[string]bool{}
	for _, f := range corpus {
		data, err := os.ReadFile(f)
		if err != nil {
			fatal("读 %s: %v", f, err)
		}
		for _, m := range reUse.FindAllStringSubmatch(string(data), -1) {
			// m[1] 形如 sym 或 Type::member——类型消费记 `T`，成员消费记 `T::m`
			parts := strings.SplitN(m[1], "::", 2)
			// pkg 名从匹配原文取（@xxx. 的 xxx）
			pkgAlias := pkgOf(string(data), m[0], f)
			consumerPkg := filepath.Base(filepath.Dir(f))
			if used[pkgAlias] == nil {
				used[pkgAlias] = map[string]bool{}
			}
			used[pkgAlias][parts[0]] = true
			used[pkgAlias][m[1]] = true
			if consumerPkg != pkgAlias {
				usedEdges[consumerPkg+" "+pkgAlias+" "+parts[0]] = true
			}
		}
	}
	// 各包符号 → 可收判定；closureSig = 因 pub 签名引用而必须保持 pub 的类型
	collectable := map[string][]string{} // pkg → []sym
	closureSig := map[string][]string{}  // pkg → []type（签名闭包，非收面对象）
	for _, mbti := range pkgs {
		pkg := strings.Split(filepath.Dir(mbti), string(filepath.Separator))[0]
		data, err := os.ReadFile(mbti)
		if err != nil {
			fatal("读 %s: %v", mbti, err)
		}
		lines := strings.Split(string(data), "\n")

		// 第一遍：本包 pub 类型名。
		pubTypes := map[string]bool{}
		for _, line := range lines {
			if m := reType.FindStringSubmatch(line); m != nil {
				pubTypes[m[1]] = true
			}
		}
		// 第二遍：**引用计数**——一个 pub 类型若在本包 mbti 里除自身定义行
		// 之外还有出现（被 pub fn/const 签名、pub(all) struct 字段、enum
		// 变体载荷引用），则它是**闭包**：私有化会让那处引用非法。
		//
		// 这是本闸的判定补全（2026-09-22）：原实现只覆盖"字段类型"闭包且
		// 靠人工白名单登记（ParseError / LocalBuffer），**漏了函数签名与
		// 枚举变体两类**——实测导致 `diag.CatalogEntry`/`Severity`/
		// `SourceLang` 与 `source.Pos` 被误报成"可收"（照清单去收会直接
		// 编译错：pub 函数不能返回私有类型）。
		occur := map[string]int{}
		for _, line := range lines {
			for t := range pubTypes {
				if hasWord(line, t) {
					occur[t]++
				}
			}
		}
		// 第三遍：逐符号判定
		for _, line := range lines {
			var name, kind string
			if m := reMethod.FindStringSubmatch(line); m != nil {
				name, kind = m[1], "type" // 方法归属类型判定
			} else if m := reFn.FindStringSubmatch(line); m != nil {
				name, kind = m[1], "fn"
			} else if m := reType.FindStringSubmatch(line); m != nil {
				name, kind = m[1], "type"
			} else if m := reConst.FindStringSubmatch(line); m != nil {
				name, kind = m[1], "const"
			} else {
				continue
			}
			if used[pkg] != nil && used[pkg][name] {
				continue
			}
			if kind == "type" && occur[name] > 1 {
				closureSig[pkg] = append(closureSig[pkg], name)
				continue
			}
			collectable[pkg] = append(collectable[pkg], name)
		}
		// 去重排序（同类型多方法只记一次）
		sort.Strings(collectable[pkg])
		dedup := collectable[pkg][:0]
		prev := ""
		for _, s := range collectable[pkg] {
			if s != prev {
				dedup = append(dedup, s)
				prev = s
			}
		}
		collectable[pkg] = dedup
		sort.Strings(closureSig[pkg])
		csDedup := closureSig[pkg][:0]
		prev = ""
		for _, s := range closureSig[pkg] {
			if s != prev {
				csDedup = append(csDedup, s)
				prev = s
			}
		}
		closureSig[pkg] = csDedup
	}
	if !check {
		total := 0
		for _, pkg := range sortedKeys(collectable) {
			if len(collectable[pkg]) == 0 {
				continue
			}
			fmt.Printf("%s: %s\n", pkg, strings.Join(collectable[pkg], ", "))
			total += len(collectable[pkg])
		}
		fmt.Printf("moonbit_surface: %d 个无跨包消费 pub 符号（收面对象；-check 对账 surface_allowlist.txt）\n", total)
		// 签名闭包（自动识别）——**不是收面对象**：私有化会让引用它的
		// pub 函数/常量签名非法。列出供人工核对（此前靠白名单手工登记，
		// 易漏且曾误报 4 个符号为"可收"）。
		var csTotal int
		for _, pkg := range sortedKeys(closureSig) {
			if len(closureSig[pkg]) == 0 {
				continue
			}
			fmt.Printf("[签名闭包·非收面] %s: %s\n", pkg, strings.Join(closureSig[pkg], ", "))
			csTotal += len(closureSig[pkg])
		}
		fmt.Printf("moonbit_surface: 另 %d 个 pub 类型为签名闭包（保持 pub，不计入收面）\n", csTotal)
		return
	}
	// -check：与白名单双向对账
	allow := map[string]bool{}
	if af, err := os.Open("../scripts/moonbit/surface_allowlist.txt"); err == nil {
		sc := bufio.NewScanner(af)
		for sc.Scan() {
			line := strings.TrimSpace(sc.Text())
			if line != "" && !strings.HasPrefix(line, "#") {
				allow[line] = true
			}
		}
		af.Close()
	} else {
		fatal("白名单缺失（../scripts/moonbit/surface_allowlist.txt）——先建白名单再 -check")
	}
	bad := 0
	for _, pkg := range sortedKeys(collectable) {
		for _, sym := range collectable[pkg] {
			key := pkg + " " + sym
			if !allow[key] {
				fmt.Printf("漏收: %s\n", key)
				bad++
			}
		}
	}
	for _, k := range sortedSetKeys(allow) {
		parts := strings.SplitN(k, " ", 2)
		if len(parts) == 2 {
			if syms, ok := collectable[parts[0]]; !ok || !contains(syms, parts[1]) {
				fmt.Printf("过期白名单: %s（已消费或已收，须清理）\n", k)
				bad++
			}
		}
	}
	// —— 第二面闸：跨包消费边对账（防"新 pub + 新消费"绕过无主对账的
	// 扩张通道——新增边必须人工审阅登记 surface_edges.txt）。两面证据
	// 全收集后统一红（首面 fatal 早退会吞掉边级证据——注入实测发现）——
	edgeBad := checkEdges(usedEdges)
	if bad > 0 || edgeBad > 0 {
		fatal("moonbit_surface: 对账不符（无主 %d + 边 %d）", bad, edgeBad)
	}
	fmt.Println("moonbit_surface: check OK（可收清单与白名单一致 + 消费边与边清单一致）")
}

// hasWord：词边界匹配（避免 `Severity` 命中 `SeverityX`）。
func hasWord(s, w string) bool {
	for idx := 0; ; {
		i := strings.Index(s[idx:], w)
		if i < 0 {
			return false
		}
		pos := idx + i
		beforeOK := pos == 0 || !isIdentByte(s[pos-1])
		afterOK := pos+len(w) >= len(s) || !isIdentByte(s[pos+len(w)])
		if beforeOK && afterOK {
			return true
		}
		idx = pos + 1
	}
}

func isIdentByte(c byte) bool {
	return c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
}

// checkEdges：实际边集 ↔ ../scripts/moonbit/surface_edges.txt 双向对账。
// 实际边集以 "consumer provider sym" 记（consumer 取文件所在包目录名；
// cmd/ 工具按其子包名计——dump_ast 等）。
func checkEdges(actual map[string]bool) int {
	ef, err := os.Open("../scripts/moonbit/surface_edges.txt")
	if err != nil {
		fatal("边清单缺失（../scripts/moonbit/surface_edges.txt）——先生成基准")
	}
	defer ef.Close()
	allowed := map[string]bool{}
	sc := bufio.NewScanner(ef)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line != "" && !strings.HasPrefix(line, "#") {
			allowed[line] = true
		}
	}
	bad := 0
	for _, e := range sortedSetKeys(actual) {
		if !allowed[e] {
			fmt.Printf("新消费边（对外面扩张，须人工登记）: %s"+string(rune(10)), e)
			bad++
		}
	}
	for _, e := range sortedSetKeys(allowed) {
		if !actual[e] {
			fmt.Printf("过期边（已无此消费，须清理）: %s"+string(rune(10)), e)
			bad++
		}
	}
	return bad
}

// pkgOf：从匹配串 @pkg.sym 反查 pkg 别名（m[0] 的 @ 后段）。
func pkgOf(_, match, _ string) string {
	i := strings.Index(match, ".")
	return match[1:i]
}

func contains(arr []string, s string) bool {
	for _, a := range arr {
		if a == s {
			return true
		}
	}
	return false
}

func sortedKeys(m map[string][]string) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

func sortedSetKeys(m map[string]bool) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

func fatal(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "moonbit_surface: "+format+"\n", args...)
	os.Exit(2)
}
