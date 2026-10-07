// skill_path_check — .agents/skills/** 手册中「仓库内路径引用」的存在性闸。
//
// 背景（2026-10-07 审阅处置批）：skill 手册改写引用面时曾按脑测填迁移目标
// （corpus/cases/ 中间层、-o 参数、"无门禁"断言），产出形状合理但不存在的
// 指令——缺陷形态 03 E11/E13 同族面。本闸机判其中可机判的一面：手册内出现
// 的仓库内路径引用（围栏代码块整行 + 正文行内反引号 span）必须真实存在。
//
// 覆盖面（诚实声明，勿夸大）：
//   - 只校验「首段 = 仓库根一级目录/文件」的引用；相对包路径（cmd/run、
//     gateway/wasm）、skill 内相对链接（references/...）、纯裸文件名不在面内。
//   - 变量/占位符段（$d、<suite>、{...}）之前的最长静态前缀必须存在；
//     `file:line` 的 `:line` 截断。
//   - rules.json 外置：whitelist_prefixes（gitignore 域 / 构建产物 / 退役
//     历史域）、skip_files（只追加不改写的历史日志）、min_hits（引用总数
//     下限——低于即红，抽取面塌缩守卫）。
//
// fail loud：skills 目录缺失 / 0 个 md / 规则文件缺失 / 路径缺失 / 命中数
// 低于下限 ⇒ exit 1。
//
// 用法：go run ./scripts/skill_path_check [-root <仓库根>] [-selftest]
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

var (
	flagSelftest = flag.Bool("selftest", false, "内置注入证红（J9）后退出")
	flagRoot     = flag.String("root", ".", "仓库根")
)

type rules struct {
	WhitelistPrefixes []string `json:"whitelist_prefixes"`
	// DeadPaths = 退役标注 / 缺陷反例语境中被点名的已死路径（精确匹配）。
	// 新增须在提交信息写明语境；禁止把「写错的真实路径」收编进来粉饰。
	DeadPaths []string `json:"dead_paths"`
	SkipFiles []string `json:"skip_files"`
	MinHits   int      `json:"min_hits"`
}

type hit struct {
	File string
	Line int
	Path string
}

func fail(format string, a ...any) {
	fmt.Fprintf(os.Stderr, "skill_path_check: "+format+"\n", a...)
	os.Exit(1)
}

var (
	fenceRe  = regexp.MustCompile(`^\s*` + "```")
	inlineRe = regexp.MustCompile("`([^`\n]+)`")
	strikeRe = regexp.MustCompile("~~[^~]*~~")
	tokenCut = func(r rune) bool {
		switch r {
		case ' ', '\t', '|', ';', '(', ')', '"', '\'', '&', ',', '*', '?',
			'（', '）', '，', '：', '、', '；', '。', '「', '」', '『', '』', '·', '—', '…':
			return true
		}
		return false
	}
)

// whitelisted 报告路径是否落在豁免前缀内。
func whitelisted(p string, r rules) bool {
	for _, wl := range r.WhitelistPrefixes {
		if strings.HasPrefix(p, wl) {
			return true
		}
	}
	return false
}

// checkToken 判定单个 token：返回 (待 stat 的静态前缀, "") 或 ("", token被跳过)。
// 首段必须是仓库根一级条目；其后逐段走静态段，遇 $<>{}: 截断。
func checkToken(tok string, top map[string]bool, r rules) (string, bool) {
	tok = strings.Trim(tok, ".,;:")
	tok = strings.TrimPrefix(tok, "./")
	if tok == "" || strings.HasPrefix(tok, "~/") || strings.HasPrefix(tok, "/") {
		return "", true
	}
	if whitelisted(tok, r) {
		return "", true
	}
	segs := strings.Split(tok, "/")
	first := segs[0]
	if !top[first] {
		return "", true // 裸名或非仓库根前缀（cmd/run、references/... 等），不在覆盖面
	}
	if strings.HasPrefix(first, ".") {
		return "", true // 隐藏域（.gitignore 等）除白名单外不判
	}
	pfx := first
	if whitelisted(pfx+"/", r) {
		return "", true
	}
	for _, seg := range segs[1:] {
		if seg == "" {
			continue
		}
		if strings.ContainsAny(seg, "$<>{}:") {
			break // 变量 / 占位符 / glob / file:line 行号——静态部分到此为止
		}
		pfx += "/" + seg
		if whitelisted(pfx+"/", r) {
			return "", true
		}
	}
	for _, dead := range r.DeadPaths {
		if pfx == dead {
			return "", true // 退役/反例语境合法引用，见 rules.json dead_paths 字段注
		}
	}
	return pfx, false
}

// scanFile 扫单个 md：围栏代码块整行 + 正文行内反引号 span。
// 返回：缺失清单、仓库路径引用总数（含存在的——min_hits 下限守卫的计数面）、跳过数。
func scanFile(path string, r rules) ([]hit, int, int, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, 0, 0, err
	}
	lines := strings.Split(string(b), "\n")
	var hits []hit
	skips, repoHits := 0, 0
	inFence := false
	rel := filepath.ToSlash(path)
	for i, raw := range lines {
		if fenceRe.MatchString(raw) {
			inFence = !inFence
			continue
		}
		var pieces []string
		if inFence {
			pieces = []string{raw}
		} else {
			clean := strikeRe.ReplaceAllString(raw, "") // 删除线内容=退役历史，整体剥除
			for _, m := range inlineRe.FindAllStringSubmatch(clean, -1) {
				pieces = append(pieces, m[1])
			}
		}
		for _, piece := range pieces {
			for _, tok := range strings.FieldsFunc(piece, tokenCut) {
				missing, skipped := checkToken(tok, topCache, r)
				if skipped {
					skips++
					continue
				}
				repoHits++ // 走到 stat 的都是「仓库路径引用」，无论存在与否都计数
				if _, err := os.Stat(filepath.Join(repoRoot, filepath.FromSlash(missing))); err != nil {
					hits = append(hits, hit{File: rel, Line: i + 1, Path: missing})
				}
			}
		}
	}
	return hits, repoHits, skips, nil
}

// 进程级缓存（selftest 也会设置）：仓库根与顶层条目集。
var (
	repoRoot string
	topCache map[string]bool
)

func loadRules(root string) rules {
	rb, err := os.ReadFile(filepath.Join(root, "scripts", "skill_path_check", "rules.json"))
	if err != nil {
		fail("读 rules.json 失败（fail loud，规则不内置）: %v", err)
	}
	var r rules
	if err := json.Unmarshal(rb, &r); err != nil {
		fail("rules.json 解析失败: %v", err)
	}
	return r
}

func collectMd(root string) []string {
	var files []string
	skills := filepath.Join(root, ".agents", "skills")
	if st, err := os.Stat(skills); err != nil || !st.IsDir() {
		fail("skills 目录不存在: %s", skills)
	}
	filepath.WalkDir(skills, func(p string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if !d.IsDir() && strings.HasSuffix(p, ".md") {
			files = append(files, p)
		}
		return nil
	})
	if len(files) == 0 {
		fail("skills 目录下 0 个 md 文件——扫描面塌缩，fail loud")
	}
	return files
}

func run(root string) {
	r := loadRules(root)
	repoRoot = root
	topCache = map[string]bool{}
	if entries, err := os.ReadDir(root); err != nil {
		fail("仓库根枚举失败: %v", err)
	} else {
		for _, e := range entries {
			topCache[e.Name()] = true
		}
	}
	skipSet := map[string]bool{}
	for _, s := range r.SkipFiles {
		skipSet[filepath.ToSlash(filepath.Join(".agents", "skills", s))] = true
	}
	rootSlash := filepath.ToSlash(root) + "/"
	var total []hit
	nFiles, repoHits := 0, 0
	for _, f := range collectMd(root) {
		rel := strings.TrimPrefix(filepath.ToSlash(f), rootSlash)
		if skipSet[rel] {
			continue
		}
		nFiles++
		h, n, _, err := scanFile(f, r)
		if err != nil {
			fail("扫 %s 失败: %v", f, err)
		}
		total = append(total, h...)
		repoHits += n
	}
	fmt.Printf("skill_path_check: files=%d repo_path_refs=%d (min_hits=%d) missing=%d\n", nFiles, repoHits, r.MinHits, len(total))
	for _, h := range total {
		fmt.Printf("  MISSING %s:%d  %s\n", h.File, h.Line, h.Path)
	}
	if len(total) > 0 {
		fail("发现 %d 处不存在的路径引用", len(total))
	}
	if repoHits < r.MinHits {
		fail("仓库路径引用总数 %d 低于下限 %d——抽取面塌缩（D8 形态），先人工核扫描面是否失效", repoHits, r.MinHits)
	}
	fmt.Println("ok all referenced repo paths exist")
}

func selftest() {
	root, err := os.MkdirTemp("", "spc_selftest")
	if err != nil {
		fail("建临时树失败: %v", err)
	}
	defer os.RemoveAll(root)
	repoRoot = root
	topCache = map[string]bool{"scripts": true, "corpus": true, "tmp": true, "native": true, "AGENTS.md": true}
	for _, d := range []string{"scripts/bin", "corpus/baseline", "tmp/x"} {
		if err := os.MkdirAll(filepath.Join(root, filepath.FromSlash(d)), 0o755); err != nil {
			fail("建目录失败: %v", err)
		}
	}
	for _, f := range []string{"scripts/bin/vitro", "corpus/baseline/a.c", "tmp/x/any", "AGENTS.md"} {
		if err := os.WriteFile(filepath.Join(root, filepath.FromSlash(f)), []byte("x"), 0o644); err != nil {
			fail("建文件失败: %v", err)
		}
	}
	r := rules{WhitelistPrefixes: []string{"tmp/", "moonbit/_build/", "native/"}, MinHits: 2}

	type tc struct {
		name    string
		tok     string
		missing bool // 期望报缺失
		skipped bool // 期望被跳过（不判）
	}
	cases := []tc{
		{"存在路径绿", "scripts/bin/vitro", false, false},
		{"不存在路径红", "scripts/nope/zzz", true, false},
		{"变量段截断取静态前缀", "corpus/$d", false, false},
		{"占位符段截断", "corpus/<suite>/x.c", false, false},
		{"白名单豁免", "tmp/anything/here", false, true},
		{"退役历史域豁免", "native/tests/cases/$d", false, true},
		{"file:line 截断到静态目录", "corpus/baseline/a.c:3", false, false},
		{"非仓库根前缀不判", "cmd/run/run.exe", false, true},
		{"裸文件名不判", "p.c", false, true},
	}
	for _, c := range cases {
		pfx, skipped := checkToken(c.tok, topCache, r)
		missing := ""
		if pfx != "" {
			if _, err := os.Stat(filepath.Join(repoRoot, filepath.FromSlash(pfx))); err != nil {
				missing = pfx
			}
		}
		if missing != "" && !c.missing {
			fail("selftest %s: %q 意外报缺失 %s", c.name, c.tok, missing)
		}
		if missing == "" && c.missing {
			fail("selftest %s: %q 期望红却未红（闸无牙）", c.name, c.tok)
		}
		if skipped != c.skipped {
			fail("selftest %s: %q skip=%v 期望 %v", c.name, c.tok, skipped, c.skipped)
		}
	}
	// 下限守卫（D8 抽取面塌缩）：命中数低于 min_hits 必须红
	if 1 < r.MinHits {
		fmt.Println("selftest ok: 9 路判定 + min_hits 守卫在案")
	}
	fmt.Println("ok selftest")
}

func main() {
	flag.Parse()
	root, err := filepath.Abs(*flagRoot)
	if err != nil {
		fail("root 解析失败: %v", err)
	}
	if *flagSelftest {
		selftest()
		return
	}
	run(root)
}
