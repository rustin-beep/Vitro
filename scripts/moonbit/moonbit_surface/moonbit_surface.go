// moonbit_surface：MoonBit 对外面审计（S5 收尾批·收面前置；S6 批一段·口径修复 2026-09-23）。
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
// **口径（S6 批一段修复，2026-09-23）**：consumer 与 provider 一律**包全名**
// （moon.mod 模块名 + 包目录，如 `vitro/engine/lexer/internal/host`）。
// `@别名.` 依据**消费文件所属包的 moon.pkg import 块**解析（别名 = import
// 路径末段；全仓 moon.pkg 零显式别名，遇 `as` 等未知形态 fail loud）：
//   - 普通源码与 *_wbtest.mbt：main import 块（wbtest 不携带 for-test，陷阱 #26）；
//   - *_test.mbt 与包内 README*（doc 测试是黑盒）：main ∪ for "test" ∪ 自引用
//     （被测包按末段别名隐式 import——`host/host_test.mbt` 的 `@host.` 即此；
//     `@self.` 同义，当前语料未用但语义存在，一并映射）；
//   - 模块根 README*（无 moon.pkg；发布面 README.md 的 nocheck 示例是文档
//     承诺，计入消费）：别名按**全仓工作区包末段**解析，命中多个（如 `host`
//     同时是 L7 与 lexer/internal/host）或零个均 fail loud。
//
// 修复动机（旧口径三处不一致）：consumer 取目录末段、provider 取 `@别名`
// 末段——`lexer` 对 `lexer/internal/host` 的消费（别名 host）会假性救活 L7
// `host` 的同名符号（该收的收不掉，J9 注入实证）；边表同名条目只能靠注释
// 区分。验收锚：注入 `host::vfs_provider` 同名对，旧闸静默、新闸红。
//
// **判据盲区登记（文本 grep 的已知边界，变更形态时可静默漏检）**：
// ① 注释/字符串内的 @pkg.sym 计为消费（过宽方向，不漏收只可能挡收）；
// ② 点调用方法（obj.method()）不带前缀——类型经变量流动时方法消费不计
// （类型符号消费已按类型名覆盖大部分场景）。
// （原盲区③ import 别名已随本批修复：moon.pkg 零别名假设 + 未知形态红。）
//
// **provider 侧全递归（S6 批二段，2026-09-23 已落地）**：13 个一级包 + 4 个
// 子包（lexer/token、lexer/internal/{host,pp,scanner}）同入「无主判定」。
// 实测零暴露——批一段的 `used` 全名记账已覆盖子包消费（原本预期"会暴露
// 一批待收符号"未出现；新增仅 token::LineMap 一个签名闭包，自动免收）。
//
// 白名单 surface_allowlist.txt：一行一符号（格式 `包全名 sym`）= **允许保持
// pub 但当前无消费**的集合（如管线预留/发包面）。-check 双向对账：
// 实际可收集合多出白名单 → 漏收（红）；白名单条目不在实际集合 → 过期
// （红，须清理）。边清单 surface_edges.txt：一行一边（格式
// `consumer全名 provider全名 sym`；根 README 的 consumer 记 `.`；core 库
// provider 记完整路径如 `moonbitlang/core/string`）。新增边 = 对外面扩张，
// 必须人工审阅登记。
//
// **发布状态（2026-09-22 核实）**：0.4.0（2026-09-21）起 module 下全部对外
// 包已在架（moon publish 是 module 级）⇒ 收面 = 对已发布包的破坏性变更，
// 须走版本化弃期；本闸角色 = **防扩散闸**（新 pub + 新消费边一律拦下要人工
// 裁定）。脚本默认全包审计（信息面）。
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

// pkgInfo：工作区一个包的 moon.pkg 解析结果。
type pkgInfo struct {
	relDir      string            // 工作区相对目录，如 lexer/internal/host
	fullName    string            // 包全名，如 vitro/engine/lexer/internal/host
	mainAliases map[string]string // 别名 → provider 全名（main import 块）
	testAliases map[string]string // 别名 → provider 全名（for "test" 块）
}

func main() {
	if err := os.Chdir("moonbit"); err != nil {
		fmt.Fprintf(os.Stderr, "chdir moonbit failed: %v\n", err)
		os.Exit(2)
	}

	check := false
	for _, a := range os.Args[1:] {
		if a == "-check" {
			check = true
		}
	}
	moduleName := readModuleName()
	pkgs := discoverPackages(moduleName)

	// provider 侧**全递归**（S6 批二段，2026-09-23）：13 个一级包 +
	// 4 个子包（lexer/token、lexer/internal/{host,pp,scanner}）——子包 pub 面
	// 首次进「无主须收面或入白名单」判定。**实测零暴露**：批一段的全名记账
	// （`used` 以 Provider 全名为键）早已覆盖子包消费，本段只是把提供侧接上
	// （新增仅 1 个签名闭包 lexer/token::LineMap，自动免收）。
	pkgsMbti, err := filepath.Glob("*/pkg.generated.mbti")
	if deep, err2 := filepath.Glob("*/*/pkg.generated.mbti"); err2 == nil {
		pkgsMbti = append(pkgsMbti, deep...)
	}
	if err != nil || len(pkgsMbti) == 0 {
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
				corpus = append(corpus, filepath.ToSlash(path))
			}
		}
		return nil
	})
	if len(corpus) == 0 {
		fatal("消费语料为空")
	}
	// 消费索引：provider 全名 → set(sym-path)；边集 consumer provider sym（第二面闸）
	used := map[string]map[string]bool{}
	usedEdges := map[string]bool{}
	for _, f := range corpus {
		data, err := os.ReadFile(f)
		if err != nil {
			fatal("读 %s: %v", f, err)
		}
		vis, ambiguous, consumer := visibilityFor(f, pkgs)
		for _, m := range reUse.FindAllStringSubmatch(string(data), -1) {
			// m[1] 形如 sym 或 Type::member——类型消费记 `T`，成员消费记 `T::m`
			parts := strings.SplitN(m[1], "::", 2)
			alias := m[0][1:strings.Index(m[0], ".")]
			if ambiguous != nil && ambiguous[alias] {
				fatal("歧义别名 @%s.（%s）——末段撞车的工作区包不止一个（如 L7 host 与 lexer/internal/host）；根 README 引用须消歧后过闸", alias, f)
			}
			provider, ok := vis[alias]
			if !ok {
				fatal("未知别名 @%s.（%s，consumer=%s）——不在所属包 moon.pkg 的可见 import 集；若属新形态（显式别名/新 scope）须先扩本闸", alias, f, consumer)
			}
			if used[provider] == nil {
				used[provider] = map[string]bool{}
			}
			used[provider][parts[0]] = true
			used[provider][m[1]] = true
			if consumer != provider {
				usedEdges[consumer+" "+provider+" "+parts[0]] = true
			}
		}
	}
	// 各包符号 → 可收判定；closureSig = 因 pub 签名引用而必须保持 pub 的类型
	collectable := map[string][]string{} // pkg 全名 → []sym
	closureSig := map[string][]string{}  // pkg 全名 → []type（签名闭包，非收面对象）
	for _, mbti := range pkgsMbti {
		pkg := moduleName + "/" + filepath.ToSlash(filepath.Dir(mbti))
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

// readModuleName：moon.mod 的 name 字段（包全名前缀的唯一真相源）。
func readModuleName() string {
	data, err := os.ReadFile("moon.mod")
	if err != nil {
		fatal("读 moon.mod 失败：%v", err)
	}
	for _, line := range strings.Split(string(data), "\n") {
		t := strings.TrimSpace(line)
		if strings.HasPrefix(t, "name") {
			q0 := strings.Index(t, `"`)
			q1 := strings.LastIndex(t, `"`)
			if q0 < 0 || q1 <= q0 {
				fatal("moon.mod name 行形态未知：%s", t)
			}
			return t[q0+1 : q1]
		}
	}
	fatal("moon.mod 无 name 字段")
	return ""
}

// discoverPackages：全仓 moon.pkg → 包全名 + 两级 import 别名表。
// moon.pkg 语法面（本仓实测形态，超出即红——fail loud 未知形态）：
//
//	import {
//	  "vitro/engine/lexer/token",
//	}
//	import {
//	  "vitro/engine/diag",
//	} for "test"
//
// 别名 = import 路径末段（全仓零显式别名）；块内重名、main/for-test 同别名
// 不同 provider、非 "test" scope、as 显式别名 → 一律红。
func discoverPackages(moduleName string) map[string]*pkgInfo {
	pkgs := map[string]*pkgInfo{}
	var mp []string
	_ = filepath.Walk(".", func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() && (info.Name() == "_build" || info.Name() == ".mooncakes" || info.Name() == "scripts") {
			return filepath.SkipDir
		}
		if !info.IsDir() && info.Name() == "moon.pkg" {
			mp = append(mp, filepath.ToSlash(path))
		}
		return nil
	})
	if len(mp) == 0 {
		fatal("未发现任何 moon.pkg（须在 moonbit/ 下运行）")
	}
	for _, p := range mp {
		relDir := filepath.ToSlash(filepath.Dir(p))
		pi := &pkgInfo{
			relDir:      relDir,
			fullName:    moduleName + "/" + relDir,
			mainAliases: map[string]string{},
			testAliases: map[string]string{},
		}
		data, err := os.ReadFile(p)
		if err != nil {
			fatal("读 %s: %v", p, err)
		}
		scope := ""
		inImport := false
		for _, raw := range strings.Split(string(data), "\n") {
			line := strings.TrimSpace(raw)
			if i := strings.Index(line, "//"); i >= 0 {
				line = strings.TrimSpace(line[:i])
			}
			if line == "" {
				continue
			}
			if !inImport {
				if line == "import {" {
					inImport = true
					scope = ""
					continue
				}
				// 非 import 行（supported_targets / pkgtype / warnings 等）忽略
				if strings.HasPrefix(line, "import") {
					fatal("%s: 未知 import 形态（本闸只认 `import {` 块）：%s", p, line)
				}
				continue
			}
			// import 块内
			if strings.HasPrefix(line, "}") {
				inImport = false
				if rest := strings.TrimSpace(line[1:]); rest != "" {
					if !strings.HasPrefix(rest, `for "test"`) {
						fatal("%s: 未知 import scope（本闸只认 for \"test\"）：%s", p, rest)
					}
					scope = "test"
				}
				continue
			}
			entry := strings.TrimSuffix(line, ",")
			entry = strings.TrimSpace(entry)
			if len(entry) < 2 || entry[0] != '"' || entry[len(entry)-1] != '"' {
				fatal("%s: import 条目形态未知（显式别名 as / 多行等须先扩闸）：%s", p, entry)
			}
			path := entry[1 : len(entry)-1]
			alias := path[strings.LastIndex(path, "/")+1:]
			target := pi.mainAliases
			if scope == "test" {
				target = pi.testAliases
			}
			if prev, dup := target[alias]; dup && prev != path {
				fatal("%s: 块内别名冲突 @%s. → %s 与 %s", p, alias, prev, path)
			}
			target[alias] = path
		}
		if inImport {
			fatal("%s: import 块未闭合", p)
		}
		// main 与 for-test 同别名不同 provider：黑盒/doc 测试可见集是两者并集，
		// 冲突即歧义（MoonBit 编译亦不允许，此处前置红）。
		for a, tp := range pi.testAliases {
			if mp2, ok := pi.mainAliases[a]; ok && mp2 != tp {
				fatal("%s: main 与 for \"test\" 别名冲突 @%s. → %s 与 %s", p, a, mp2, tp)
			}
		}
		if _, dup := pkgs[relDir]; dup {
			fatal("包目录重复登记：%s", relDir)
		}
		pkgs[relDir] = pi
	}
	return pkgs
}

// visibilityFor：语料文件 → (别名→provider 全名 可见集, 歧义别名集, consumer 全名)。
// 模块根 README* 的 consumer 记 "."（无包上下文；发布面文档承诺按全仓
// 工作区包末段解析）——末段撞车的别名（当前 @host.：L7 与 lexer/internal/host）
// 入歧义集，引用即红，不静默择一。
func visibilityFor(f string, pkgs map[string]*pkgInfo) (map[string]string, map[string]bool, string) {
	// 就近向上找所属包
	d := filepath.ToSlash(filepath.Dir(f))
	for {
		if pi, ok := pkgs[d]; ok {
			base := filepath.Base(f)
			if strings.HasSuffix(base, "_test.mbt") || strings.HasPrefix(base, "README") {
				// 黑盒测试 / doc 测试：main ∪ for-test ∪ 自引用
				vis := map[string]string{}
				for a, p := range pi.mainAliases {
					vis[a] = p
				}
				for a, p := range pi.testAliases {
					vis[a] = p
				}
				self := pi.fullName[strings.LastIndex(pi.fullName, "/")+1:]
				vis[self] = pi.fullName
				vis["self"] = pi.fullName
				return vis, nil, pi.fullName
			}
			// 普通源码 / wbtest：main import 块 + 自引用（MoonBit 包不自 import，
			// 正常代码不可能出现 @自身末段.——出现即注释/字符串（既知盲区①，
			// 过宽方向），按自消费归账保持旧口径；与 main import 撞名则红）
			vis := map[string]string{}
			for a, p := range pi.mainAliases {
				vis[a] = p
			}
			self := pi.fullName[strings.LastIndex(pi.fullName, "/")+1:]
			if prev, dup := vis[self]; dup && prev != pi.fullName {
				fatal("包 %s 的 main import 含与自身末段撞名的别名 @%s. → %s（MoonBit 亦不允许）", pi.fullName, self, prev)
			}
			vis[self] = pi.fullName
			vis["self"] = pi.fullName
			return vis, nil, pi.fullName
		}
		if d == "." || d == "/" {
			break
		}
		d = filepath.ToSlash(filepath.Dir(d))
	}
	// 模块根（无 moon.pkg）：只允许 README*（doc/发布面）；散置 .mbt 须先入包
	base := filepath.Base(f)
	if !strings.HasPrefix(base, "README") {
		fatal("语料文件 %s 不属于任何包（模块根只认 README*）——散置 .mbt 须入包后过闸", f)
	}
	// 根 README 的别名空间 = 全仓工作区包末段；撞车的入歧义集
	vis := map[string]string{}
	ambiguous := map[string]bool{}
	byAlias := map[string][]string{}
	for _, pi := range pkgs {
		last := pi.fullName[strings.LastIndex(pi.fullName, "/")+1:]
		byAlias[last] = append(byAlias[last], pi.fullName)
	}
	for a, cands := range byAlias {
		if len(cands) == 1 {
			vis[a] = cands[0]
		} else {
			ambiguous[a] = true
		}
	}
	return vis, ambiguous, "."
}

// checkEdges：实际边集 ↔ ../scripts/moonbit/surface_edges.txt 双向对账。
// 实际边集以 "consumer provider sym" 记（两侧均包全名；根 README 的
// consumer 为 "."；core 库 provider 为完整路径）。
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
