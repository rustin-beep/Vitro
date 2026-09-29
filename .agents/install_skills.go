// Vitro Agent Skills 安装器——把 .agents/skills/ 下的项目专属 skill 装进各 AI 工具的 skill 目录。
//
// 用法（cwd 任意；脚本按自身位置定位同级 skills/）：
//
//	go run .agents/install_skills.go --list                    # 列出可装 skill 并做 frontmatter 校验
//	go run .agents/install_skills.go --all                     # 装到检测到用户目录的工具（用户级）
//	go run .agents/install_skills.go --tool claude             # 装到 ~/.claude/skills
//	go run .agents/install_skills.go --tool claude --scope project   # 装到 <仓库根>/.claude/skills
//	go run .agents/install_skills.go --tool zcode              # 装到 ~/.zcode/skills
//	go run .agents/install_skills.go --dest <dir>              # 装到任意目录（其他工具通用）
//	--force 覆盖已存在目标；默认跳过并提示。
//	--diff 逐文件比对源与安装副本（配合 --tool/--dest/--all 选目标），报告差异清单供升级决策——
//	        默认安装行为是「跳过已存在」（副本停在旧版），--force 是「整目录删了重拷」（丢本地演化），
//	        升级前先 --diff 看清两边差什么，把盲跳过/盲覆盖变成显式决策。报告工具不设红绿（恒 exit 0）。
//
// 注意：
//   - ZCode 用户无需安装：ZCode 直接扫描工作区 .agents/skills/。
//   - skill 格式为通用 Agent Skills 格式（目录 + SKILL.md + YAML frontmatter），不绑定具体工具；
//     安装物是普通目录复制（含 references/ 子目录），删除即卸载。
//   - 零第三方依赖；fail loud：SKILL.md 缺失 / frontmatter 缺 name 或 description /
//     name 与目录名不一致即整体 exit 1。
//   - 维护义务：改动对应流程或文档时连坐更新 SKILL.md；新增 skill 后跑一次 --list 确认校验绿。
package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strings"
)

type skill struct {
	name string
	dir  string
	desc string
}

var tools = map[string]string{ // 工具名 -> 用户级 skills 目录
	"claude": filepath.Join(homeDir(), ".claude", "skills"),
	"zcode":  filepath.Join(homeDir(), ".zcode", "skills"),
}

func homeDir() string {
	h, err := os.UserHomeDir()
	if err != nil {
		fail("无法定位用户主目录: %v", err)
	}
	return h
}

func fail(format string, args ...interface{}) {
	fmt.Fprintf(os.Stderr, "[安装器] 错误: "+format+"\n", args...)
	os.Exit(1)
}

var metaLine = regexp.MustCompile(`(?m)^([A-Za-z][\w-]*):\s*(.+?)\s*$`)

func parseFrontmatter(path string) map[string]string {
	b, err := os.ReadFile(path)
	if err != nil {
		fail("%s: 读取失败: %v", path, err)
	}
	text := string(b)
	// CRLF 兼容（2026-09-29 J9 证红抓出）：core.autocrlf=true 的 Windows clone
	// 工作区里 SKILL.md 是 CRLF，"---\r\n" 不匹配 "---\n" 前缀会误报缺
	// frontmatter——归一后再解析（.gitattributes 锁 .agents/** 为 LF 是双保险）。
	text = strings.ReplaceAll(text, "\r\n", "\n")
	if !strings.HasPrefix(text, "---\n") {
		fail("%s: SKILL.md 缺少 YAML frontmatter（--- 包头的 name/description）", path)
	}
	end := strings.Index(text[4:], "\n---")
	if end < 0 {
		fail("%s: frontmatter 未闭合", path)
	}
	meta := map[string]string{}
	for _, m := range metaLine.FindAllStringSubmatch(text[4:end+4], -1) {
		meta[m[1]] = m[2]
	}
	return meta
}

func discover(skillsDir string) []skill {
	entries, err := os.ReadDir(skillsDir)
	if err != nil {
		fail("skill 源目录不存在: %s", skillsDir)
	}
	var out []skill
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		f := filepath.Join(skillsDir, e.Name(), "SKILL.md")
		if _, err := os.Stat(f); err != nil {
			fail("%s: 缺 SKILL.md", e.Name())
		}
		meta := parseFrontmatter(f)
		if meta["name"] == "" || meta["description"] == "" {
			fail("%s: frontmatter 缺 name 或 description", e.Name())
		}
		if meta["name"] != e.Name() {
			fail("%s: frontmatter name=%q 与目录名不一致", e.Name(), meta["name"])
		}
		out = append(out, skill{name: e.Name(), dir: filepath.Join(skillsDir, e.Name()), desc: meta["description"]})
	}
	if len(out) == 0 {
		fail("%s 下没有可安装的 skill", skillsDir)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].name < out[j].name })
	return out
}

func copyDir(src, dst string) error {
	return filepath.WalkDir(src, func(p string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(src, p)
		if err != nil {
			return err
		}
		target := filepath.Join(dst, rel)
		if d.IsDir() {
			return os.MkdirAll(target, 0o755)
		}
		in, err := os.Open(p)
		if err != nil {
			return err
		}
		defer in.Close()
		outFile, err := os.Create(target)
		if err != nil {
			return err
		}
		defer outFile.Close()
		_, err = io.Copy(outFile, in)
		return err
	})
}

func installOne(s skill, dest string, force bool) {
	if _, err := os.Stat(dest); err == nil {
		if !force {
			fmt.Printf("  跳过 %s（已存在: %s；--force 可覆盖）\n", s.name, dest)
			return
		}
		if err := os.RemoveAll(dest); err != nil {
			fail("覆盖 %s 失败: %v", dest, err)
		}
	}
	if err := copyDir(s.dir, dest); err != nil {
		fail("安装 %s 失败: %v", s.name, err)
	}
	fmt.Printf("  已装 %s → %s\n", s.name, dest)
}

// diffOne：逐文件比对源 skill 目录与安装副本，打印差异清单。
// 返回是否存在差异（报告工具，不设红绿——升级决策由人做）。
func diffOne(s skill, dest string) bool {
	if _, err := os.Stat(dest); err != nil {
		fmt.Printf("  %s: 未安装 → %s\n", s.name, dest)
		return true
	}
	list := func(root string) map[string]string {
		m := map[string]string{}
		filepath.WalkDir(root, func(p string, d os.DirEntry, err error) error {
			if err != nil || d.IsDir() {
				return err
			}
			rel, err := filepath.Rel(root, p)
			if err != nil {
				return err
			}
			m[filepath.ToSlash(rel)] = p
			return nil
		})
		return m
	}
	src, dst := list(s.dir), list(dest)
	var keys []string
	for k := range src {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var dstOnly []string
	for k := range dst {
		if _, ok := src[k]; !ok {
			dstOnly = append(dstOnly, k)
		}
	}
	sort.Strings(dstOnly)
	diff := false
	for _, k := range keys {
		sp := src[k]
		dp, ok := dst[k]
		if !ok {
			fmt.Printf("  %s: +%s（源新增，重装可得）\n", s.name, k)
			diff = true
			continue
		}
		sb, err1 := os.ReadFile(sp)
		db, err2 := os.ReadFile(dp)
		if err1 != nil || err2 != nil || string(sb) != string(db) {
			fmt.Printf("  %s: ~%s（内容不同，源 %d 字节 / 副本 %d 字节）\n", s.name, k, len(sb), len(db))
			diff = true
		}
	}
	for _, k := range dstOnly {
		fmt.Printf("  %s: *%s（仅副本所有——本地演化，--force 重装会丢失）\n", s.name, k)
		diff = true
	}
	if !diff {
		fmt.Printf("  %s: 一致\n", s.name)
	}
	return diff
}

func selfDir() string {
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		fail("无法定位脚本自身路径")
	}
	return filepath.Dir(file)
}

func main() {
	self := selfDir()
	repoRoot := filepath.Dir(self)
	skillsDir := filepath.Join(self, "skills")

	list := flag.Bool("list", false, "只列出 skill，不安装")
	all := flag.Bool("all", false, "装到检测到用户目录的全部工具（用户级）")
	tool := flag.String("tool", "", "目标工具: claude | zcode")
	scope := flag.String("scope", "user", "安装范围: user | project")
	dest := flag.String("dest", "", "安装到任意目录（其他工具通用）")
	force := flag.Bool("force", false, "覆盖已存在的同名 skill")
	diff := flag.Bool("diff", false, "逐文件比对源与安装副本（升级决策用），不安装")
	flag.Parse()

	skills := discover(skillsDir)

	fmt.Printf("Vitro 项目 skills（%d 个，frontmatter 校验通过）:\n", len(skills))
	for _, s := range skills {
		fmt.Printf("  - %s: %s\n", s.name, s.desc)
	}
	if *list {
		return
	}
	if !*all && *tool == "" && *dest == "" {
		if *diff {
			fail("--diff 需要目标：--all（自动检测）/ --tool claude|zcode / --dest <dir>")
		}
		fmt.Println("\n未指定目标: 用 --all（自动检测）/ --tool claude|zcode / --dest <dir>。ZCode 用户无需安装（工作区自动扫描）。")
		return
	}

	type target struct{ label, dir string }
	var targets []target
	if *dest != "" {
		targets = append(targets, target{"dest", *dest})
	} else {
		if *tool != "" {
			userDir, ok := tools[*tool]
			if !ok {
				fail("未知工具 %q（可选: claude, zcode）", *tool)
			}
			if *scope == "user" {
				targets = append(targets, target{*tool + "(user)", userDir})
			} else {
				targets = append(targets, target{*tool + "(project)", filepath.Join(repoRoot, "."+*tool, "skills")})
			}
		}
		if *all {
			for name, userDir := range tools {
				if fi, err := os.Stat(filepath.Dir(userDir)); err == nil && fi.IsDir() {
					targets = append(targets, target{name + "(user)", userDir})
				}
			}
		}
		if len(targets) == 0 {
			fail("--all 未检测到任何工具用户目录；请显式 --tool 或 --dest")
		}
	}

	action := "比对"
	if !*diff {
		action = "安装到"
	}
	for _, t := range targets {
		fmt.Printf("\n%s %s（%s）:\n", action, t.label, t.dir)
		anyDiff := false
		for _, s := range skills {
			d := filepath.Join(t.dir, s.name)
			if *diff {
				if diffOne(s, d) {
					anyDiff = true
				}
				continue
			}
			installOne(s, d, *force)
		}
		if *diff && anyDiff {
			fmt.Println("  → 更新 = --force 重装（丢失「*」标记的本地演化）；保留 = 不动")
		}
	}
	if *all {
		fmt.Println("\n提示: ZCode 本身直接扫描工作区 .agents/skills/，无需安装到 ~/.zcode 即可生效。")
	}
}
