// Command mbti_sync 是 MoonBit 接口面同步闸：断言「跑 moon info 前后
// moonbit/**/pkg.generated.mbti 的内容集合逐字节不变」。
//
// 背景（2026-09-22 实测）：.mbt（实现）与 pkg.generated.mbti（接口面）的
// 一致性此前纯靠人工跑 moon info。本仓已因此漏过一次——libc/pkg.generated.mbti
// 与该包不同步（.mbti 少了 `type LibcSig`），直到下一轮有人顺手跑 moon info
// 才补登。这类"静默漂移"与 B#12 空表哨兵同族：**机制写在纪律里，判定不在
// 机器里**——纪律靠人记，就会漏。
//
// 判据（取「仓库现状 ≠ 源码真相」形态）：moon info 无 `--check` 子命令
// （实测 moon 0.1.20260920），故本闸只能取快照不变量——
//
//	snapshot(moon info 前) == snapshot(moon info 后)
//
// 不等即有 .mbti 与源码脱节（pub 面改了没同步 / 新增包未生成 / 手工改坏），
// 列出全部变化文件后 exit 1。0 个 .mbti 亦红（拒绝空转判绿）。
//
// 与同族的边界：本闸判「接口面是否跟上实现」，**不判**「接口面是否该收窄」
// （那是 moonbit_surface 的职责）。两者互补，不可互替。
//
// 自愈特性（使用须知）：闸自己会跑 moon info ⇒ 判红的同时**把 .mbti 同步到
// 当前实现状态**。第一次跑红（仓库里的 .mbti 落后于实现）、紧接着再跑即绿——
// 这是刻意的红→绿形态，不是漏判。CI 侧语义不变（checkout 后跑一次，红 =
// 提交时未同步；CI 环境丢弃修复无副作用）；本地侧则省掉"手动跑 moon info"
// 这一步：红完 .mbti 已是新版，直接一起提交即可。
package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

const rulesPath = "scripts/moonbit/mbti_sync/rules.json"

type rulesDoc struct {
	Schema       int      `json:"schema"`
	ModuleDir    string   `json:"module_dir"`
	MbtiFilename string   `json:"mbti_filename"`
	MoonInfoArgs []string `json:"moon_info_args"`
	SkipDirs     []string `json:"skip_dirs"`
}

// fatal：fail loud 的统一出口（exit 2，区别于门禁失败的 exit 1）。
func fatal(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "FATAL: "+format+"\n", args...)
	os.Exit(2)
}

// repoRoot：向上探测含 native/ 与 scripts/ 的目录（go run 的可执行在
// GOCACHE 临时目录，无 __file__ 锚点——与 scripts/internal/capi 同款）。
func repoRoot() string {
	wd, err := os.Getwd()
	if err != nil {
		fatal("无法取工作目录: %v", err)
	}
	dir := wd
	for i := 0; i < 6; i++ {
		ok := true
		for _, m := range []string{"native", "scripts"} {
			if fi, err := os.Stat(filepath.Join(dir, m)); err != nil || !fi.IsDir() {
				ok = false
				break
			}
		}
		if ok {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	fatal("请在仓库内运行：找不到包含 native/ 与 scripts/ 的项目根")
	return ""
}

// snapshot：module 下全部 .mbti 的「仓库根相对路径（正斜杠）→ sha256」。
func snapshot(root string, rd rulesDoc) map[string]string {
	base := filepath.Join(root, filepath.FromSlash(rd.ModuleDir))
	if fi, err := os.Stat(base); err != nil || !fi.IsDir() {
		fatal("module_dir 不存在: %s (%v)", base, err)
	}
	skip := map[string]bool{}
	for _, d := range rd.SkipDirs {
		skip[d] = true
	}
	out := map[string]string{}
	err := filepath.WalkDir(base, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			if skip[d.Name()] {
				return filepath.SkipDir
			}
			return nil
		}
		if d.Name() != rd.MbtiFilename {
			return nil
		}
		b, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		sum := sha256.Sum256(b)
		rel, err := filepath.Rel(root, path)
		if err != nil {
			rel = path
		}
		out[filepath.ToSlash(rel)] = hex.EncodeToString(sum[:])
		return nil
	})
	if err != nil {
		fatal("扫描 %s 失败: %v", base, err)
	}
	if len(out) == 0 {
		fatal("0 个 %s——闸门空转（module_dir / mbti_filename 配置有误），拒绝判绿", rd.MbtiFilename)
	}
	return out
}

type diffResult struct {
	added   []string
	removed []string
	changed []string
}

func (d diffResult) isEmpty() bool {
	return len(d.added) == 0 && len(d.removed) == 0 && len(d.changed) == 0
}

func (d diffResult) total() int {
	return len(d.added) + len(d.removed) + len(d.changed)
}

func diff(before, after map[string]string) diffResult {
	var r diffResult
	for k, v := range after {
		old, ok := before[k]
		if !ok {
			r.added = append(r.added, k)
			continue
		}
		if old != v {
			r.changed = append(r.changed, k)
		}
	}
	for k := range before {
		if _, ok := after[k]; !ok {
			r.removed = append(r.removed, k)
		}
	}
	sort.Strings(r.added)
	sort.Strings(r.removed)
	sort.Strings(r.changed)
	return r
}

func runMoonInfo(root string, rd rulesDoc) {
	if len(rd.MoonInfoArgs) == 0 {
		fatal("moon_info_args 为空——拒绝空转")
	}
	cmd := exec.Command(rd.MoonInfoArgs[0], rd.MoonInfoArgs[1:]...)
	cmd.Dir = filepath.Join(root, filepath.FromSlash(rd.ModuleDir))
	out, err := cmd.CombinedOutput()
	if err != nil {
		fatal("moon info 失败（%v）：\n%s", err, tail(string(out), 30))
	}
}

// check：跑一次「快照 → moon info → 再快照 → 比对」。
func check(root string, rd rulesDoc) (diffResult, int) {
	before := snapshot(root, rd)
	runMoonInfo(root, rd)
	after := snapshot(root, rd)
	return diff(before, after), len(before)
}

func report(r diffResult) {
	if len(r.added) > 0 {
		fmt.Printf("mbti_sync: 新增 %d 个接口面文件（只有跑 moon info 才生成 ⇒ 仓库里漏提交）：\n", len(r.added))
		for _, f := range r.added {
			fmt.Printf("  + %s\n", f)
		}
	}
	if len(r.removed) > 0 {
		fmt.Printf("mbti_sync: 消失 %d 个接口面文件（包被删而 .mbti 未清，或 moon info 不再产出）：\n", len(r.removed))
		for _, f := range r.removed {
			fmt.Printf("  - %s\n", f)
		}
	}
	if len(r.changed) > 0 {
		fmt.Printf("mbti_sync: %d 个接口面与实现脱节（.mbt 改了 pub 面但没跑 moon info）：\n", len(r.changed))
		for _, f := range r.changed {
			fmt.Printf("  ~ %s\n", f)
		}
	}
}

// selftest（J9 埋雷义务）：向一个真实 .mbti 注入"脱节内容"（模拟手工改坏 /
// 未同步），断言闸门必红。恢复走 defer，避免中途失败留下脏工作区。
//
// 为何注入 .mbti 而不是改 .mbt 源：本闸会自己跑 moon info ⇒ 改源会被 moon info
// 正常修复而不可归因（同 codegen_diff F3 复盘的教训：注入本就合法的形态无法证红）。
// 注入到生成物上，moon info 的重写本身就是"检测到脱节"的充分条件。
func selftest(root string, rd rulesDoc) int {
	st := snapshot(root, rd)
	target := ""
	for k := range st {
		if target == "" || k < target {
			target = k
		}
	}
	if target == "" {
		fmt.Println("mbti_sync: selftest ABORT——无可注入的 .mbti")
		return 2
	}
	abs := filepath.Join(root, filepath.FromSlash(target))
	orig, err := os.ReadFile(abs)
	if err != nil {
		fmt.Printf("mbti_sync: selftest ABORT——读 %s 失败: %v\n", target, err)
		return 2
	}
	restored := false
	restore := func() {
		if restored {
			return
		}
		if err := os.WriteFile(abs, orig, 0o644); err != nil {
			fmt.Printf("mbti_sync: selftest 严重——恢复 %s 失败: %v（工作区可能已脏）\n", target, err)
		}
		restored = true
	}
	defer restore()

	injected := append(append([]byte{}, orig...), []byte("\n// mbti_sync selftest probe\n")...)
	if err := os.WriteFile(abs, injected, 0o644); err != nil {
		fmt.Printf("mbti_sync: selftest ABORT——注入 %s 失败: %v\n", target, err)
		return 2
	}
	fmt.Printf("mbti_sync: selftest 已向 %s 注入脱节内容（模拟手工改坏 / 未同步）\n", target)

	r, _ := check(root, rd)
	restore() // 立即恢复（moon info 重写该文件后，恢复原内容即回到同步态）

	if r.isEmpty() {
		fmt.Println("mbti_sync: selftest FAIL——注入脱节内容后仍判绿，闸门失效")
		return 1
	}
	fmt.Printf("mbti_sync: selftest PASS——注入的脱节被捕获（判红 %d 个文件），J9 证红成立\n", r.total())
	return 0
}

func tail(s string, n int) string {
	lines := strings.Split(strings.TrimRight(s, "\n"), "\n")
	if len(lines) <= n {
		return s
	}
	return strings.Join(lines[len(lines)-n:], "\n")
}

func main() {
	checkFlag := flag.Bool("check", false, "判定模式（CI 入口；默认亦为判定，此参数保持与兄弟闸门调用形态一致）")
	selftestFlag := flag.Bool("selftest", false, "J9 证红：注入脱节内容，断言闸门必红")
	flag.Parse()

	root := repoRoot()
	raw, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(rulesPath)))
	if err != nil {
		fatal("读规则失败: %v", err)
	}
	var rd rulesDoc
	if err := json.Unmarshal(raw, &rd); err != nil {
		fatal("解析规则失败: %v", err)
	}
	if rd.ModuleDir == "" || rd.MbtiFilename == "" {
		fatal("规则缺 module_dir / mbti_filename")
	}
	_ = checkFlag

	if *selftestFlag {
		os.Exit(selftest(root, rd))
	}

	r, n := check(root, rd)
	if r.isEmpty() {
		fmt.Printf("mbti_sync: PASS——%d 个接口面文件与实现同步（moon info 零变化）\n", n)
		return
	}
	report(r)
	fmt.Println("mbti_sync: FAIL——接口面与实现脱节；请跑 `cd moonbit && moon info` 并提交 .mbti 变更")
	os.Exit(1)
}
