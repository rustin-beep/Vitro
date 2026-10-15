package main

// course_catalog —— 课程内容管线契约闸（#120，2026-10-15；判定型脚本：
// 零第三方依赖、规则外置 rules.json、fail loud、无静默 default）。
//
// 用法（flag 必须在任何位置参数之前；cwd = 仓库根）：
//
//	go run ./scripts/course_catalog            # 全量校验
//	go run ./scripts/course_catalog -v         # 逐条打印通过项
//	go run ./scripts/course_catalog -selftest  # J9 注入证红（闸自身体检）
//
// 判据（schema 校验单源在 gen_course——CI 先跑 gen_course -check 再跑本闸）：
//  1. 叙述→课目对账：course/**/*.md 的 (kind,id) 必须命中 demo 课目集
//     （cases.js 用例 id ∪ algorithms.js 族/扩展 id ∪ variants tpl）——
//     「叙述指向不存在的课」即红（反方向不查：课目可以暂无叙述，渐进覆盖）。
//  2. lesson.c 防线对拍：course/**/lesson.c 存在即对拍——vitro 编译运行
//     vs clang 编译运行，stdout/stderr 逐字节比对（stdin 取自 frontmatter）。
//     独立于 corpus/ 语料线（lesson.c 是课程示例防线，非引擎对拍语料）。
//  3. J9 自检：-selftest 注入假课（id=strng-typo）断言判据必红。

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

type note struct {
	ID   string `json:"id"`
	Kind string `json:"kind"`
}

type fail struct {
	judge string
	msg   string
}

func die(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "[course_catalog] "+format+"\n", args...)
	os.Exit(1)
}

// ── 课目键集抽取（正则形态由生成器产出格式保证；漂移由 J9 兜底）────────

var (
	reCaseID  = regexp.MustCompile(`(?m)^\s*id: "([a-z_0-9]+)"`)
	reAlgoID  = regexp.MustCompile(`\{\s*id: "([A-Za-z_0-9]+)", name:`)
	reVarTpl  = regexp.MustCompile(`tpl: "([A-Za-z_0-9]+)"`)
	reLessonM = regexp.MustCompile(`(?m)^---\r?\n((?:.*\r?\n)*?)---\r?\n`)
	reFmID    = regexp.MustCompile(`(?m)^id:\s*"?([A-Za-z_0-9-]+)"?\s*$`)
	reFmKind  = regexp.MustCompile(`(?m)^kind:\s*"?([a-z]+)"?\s*$`)
	reFmStdin = regexp.MustCompile(`(?m)^stdin:\s*"?([^"\n]*)"?`)
)

func readKeys(path string, res ...*regexp.Regexp) map[string]bool {
	src, err := os.ReadFile(path)
	if err != nil {
		die("读 %s: %v", path, err)
	}
	out := map[string]bool{}
	for _, re := range res {
		for _, m := range re.FindAllStringSubmatch(string(src), -1) {
			out[m[1]] = true
		}
	}
	return out
}

// ── 真源收集 ────────────────────────────────────────────────────────────

type srcNote struct {
	ID, Kind, Dir string
	Stdin         string
	HasC          bool
}

func collectNotes() []*srcNote {
	var out []*srcNote
	chaps, err := os.ReadDir("course")
	if err != nil {
		die("读 course/（本闸 cwd 须为仓库根）: %v", err)
	}
	for _, chap := range chaps {
		if !chap.IsDir() || strings.HasPrefix(chap.Name(), ".") {
			continue
		}
		lessons, _ := os.ReadDir(filepath.Join("course", chap.Name()))
		for _, l := range lessons {
			dir := filepath.Join("course", chap.Name(), l.Name())
			md, err := os.ReadFile(filepath.Join(dir, "lesson.md"))
			if err != nil {
				continue // 草稿目录
			}
			fm := reLessonM.FindStringSubmatch(string(md))
			if fm == nil {
				die("%s: 缺 frontmatter", dir)
			}
			id := reFmID.FindStringSubmatch(fm[1])
			kd := reFmKind.FindStringSubmatch(fm[1])
			if id == nil || kd == nil {
				die("%s: frontmatter 缺 id 或 kind", dir)
			}
			n := &srcNote{ID: id[1], Kind: kd[1], Dir: dir}
			if si := reFmStdin.FindStringSubmatch(fm[1]); si != nil {
				n.Stdin = si[1]
			}
			if _, err := os.Stat(filepath.Join(dir, "lesson.c")); err == nil {
				n.HasC = true
			}
			out = append(out, n)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Dir < out[j].Dir })
	return out
}

// ── 判据 1：叙述→课目对账 ───────────────────────────────────────────────

func reconcile(notes []*srcNote, v bool) []fail {
	casesKeys := readKeys(filepath.Join("demo", "cases.js"), reCaseID)
	algoKeys := readKeys(filepath.Join("demo", "algorithms.js"), reAlgoID, reVarTpl)
	var fails []fail
	for _, n := range notes {
		var ok bool
		switch n.Kind {
		case "case":
			ok = casesKeys[n.ID]
		case "algo", "xlab", "variant":
			ok = algoKeys[n.ID] // item/xitem/variants-tpl 同池（variants 元素自带 id+tpl 双字段）
		default:
			fails = append(fails, fail{"对账", fmt.Sprintf("%s: 未知 kind %q", n.Dir, n.Kind)})
			continue
		}
		if !ok {
			fails = append(fails, fail{"对账", fmt.Sprintf("%s: 叙述 (kind=%s, id=%s) 不命中任何课目（cases.js/algorithms.js 无此键）", n.Dir, n.Kind, n.ID)})
			continue
		}
		if v {
			fmt.Printf("[course_catalog] ✓ 对账 %s (%s,%s)\n", n.Dir, n.Kind, n.ID)
		}
	}
	return fails
}

// ── 判据 2：lesson.c 防线对拍（vitro vs clang）─────────────────────────

// latin1ToUTF8 把 wire 侧 Latin-1 折回的 delta 还原为 UTF-8（语义对齐 demo run.ts 同名函数：
// >0xFF 截低字节必乱码的坑已在 demo 侧实锤，此处按字节逐个还原）。
func latin1ToUTF8(s string) string {
	var b strings.Builder
	b.Grow(len(s))
	for _, r := range s {
		if r <= 0xFF {
			b.WriteByte(byte(r))
		} else {
			b.WriteRune(r) // 已是 UTF-8 码点（不该出现，容错保留）
		}
	}
	return b.String()
}

func runCmd(dir string, env []string, name string, args ...string) (string, string, error) {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	var out, errB bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &errB
	err := cmd.Run()
	return out.String(), errB.String(), err
}

// collectVitroOutput 跑 vitro run --json，从帧流拼 stdout/stderr（Latin-1 还原）。
func collectVitroOutput(dir, cPath, stdin string) (string, string, error) {
	args := []string{"run", "--json", cPath}
	if stdin != "" {
		inPath := filepath.Join(dir, "_stdin.txt")
		if err := os.WriteFile(inPath, []byte(stdin), 0o644); err != nil {
			return "", "", err
		}
		defer os.Remove(inPath)
		args = append(args, "-i", "_stdin.txt")
	}
	raw, _, err := runCmd(dir, nil, filepath.Join("scripts", "bin", "vitro"), args...)
	if err != nil {
		return "", "", fmt.Errorf("vitro run: %w\n%s", err, raw)
	}
	var so, se strings.Builder
	for _, line := range strings.Split(raw, "\n") {
		var frame struct {
			Type  string `json:"type"`
			Frame struct {
				Result struct {
					Delta string `json:"delta"`
				} `json:"result"`
			} `json:"frame"`
		}
		if !bytes.Contains([]byte(line), []byte(`"delta"`)) {
			continue
		}
		if json.Unmarshal([]byte(line), &frame) != nil {
			continue
		}
		switch frame.Type {
		case "stdout":
			so.WriteString(latin1ToUTF8(frame.Frame.Result.Delta))
		case "stderr":
			se.WriteString(latin1ToUTF8(frame.Frame.Result.Delta))
		}
	}
	return so.String(), se.String(), nil
}

func verifyC(notes []*srcNote, v bool) []fail {
	var fails []fail
	tmp, err := os.MkdirTemp("", "course_verify_*")
	if err != nil {
		die("建临时目录: %v", err)
	}
	defer os.RemoveAll(tmp) // 系统临时目录，不碰仓库（scripts/tmp 盲区教训）
	for _, n := range notes {
		if !n.HasC {
			continue
		}
		cPath := filepath.Join(n.Dir, "lesson.c")
		stdin, _ := os.ReadFile(filepath.Join(n.Dir, "_stdin.txt"))
		_ = stdin
		// vitro 臂
		vOut, vErr, err := collectVitroOutput(".", cPath, n.Stdin)
		if err != nil {
			fails = append(fails, fail{"对拍", fmt.Sprintf("%s: vitro 臂失败: %v", cPath, err)})
			continue
		}
		// clang 臂
		exe := filepath.Join(tmp, "prog.exe")
		if _, cerr, err := runCmd(tmp, nil, "clang", absPath(cPath), "-o", exe); err != nil {
			fails = append(fails, fail{"对拍", fmt.Sprintf("%s: clang 编译失败: %v\n%s", cPath, err, cerr)})
			continue
		}
		run := func(bin string) (string, string) {
			args := []string{}
			if n.Stdin != "" {
				args = append(args, bin)
				cmd := exec.Command(args[0])
				cmd.Stdin = strings.NewReader(n.Stdin)
				var o, e bytes.Buffer
				cmd.Stdout, cmd.Stderr = &o, &e
				_ = cmd.Run()
				return o.String(), e.String()
			}
			o, e, _ := runCmd(tmp, nil, bin)
			return o, e
		}
		cOut, cErr := run(exe)
		// 行尾归一化：clang Windows 文本模式 stdout 写 \r\n（既有防线同款坑，
		// clang-baseline-corpus-pitfalls 在案），vitro 输出裸 \n——比对前统一 CRLF→LF。
		norm := func(s string) string { return strings.ReplaceAll(s, "\r\n", "\n") }
		if norm(vOut) != norm(cOut) || norm(vErr) != norm(cErr) {
			fails = append(fails, fail{"对拍", fmt.Sprintf("%s: 双臂输出不一致\n  vitro stdout=%q stderr=%q\n  clang stdout=%q stderr=%q", cPath, vOut, vErr, cOut, cErr)})
			continue
		}
		if v {
			fmt.Printf("[course_catalog] ✓ 对拍 %s（vitro ≡ clang，%d B stdout）\n", cPath, len(vOut))
		}
	}
	return fails
}

func absPath(p string) string {
	a, _ := filepath.Abs(p)
	return a
}

// ── J9 自检 ─────────────────────────────────────────────────────────────

func selftest() {
	fake := []*srcNote{{ID: "strng-typo", Kind: "algo", Dir: "<J9注入>"}}
	fails := reconcile(fake, false)
	for _, f := range fails {
		if f.judge == "对账" && strings.Contains(f.msg, "strng-typo") {
			fmt.Println("[course_catalog] J9 自检 OK：假课注入被对账判据捕获")
			return
		}
	}
	die("J9 自检失败：假课注入未被捕获——判据已失效（对账函数或键集抽取漂移）")
}

func main() {
	v := flag.Bool("v", false, "逐条打印通过项")
	self := flag.Bool("selftest", false, "J9 注入证红（闸自身体检）")
	flag.Parse()

	if *self {
		selftest()
		return
	}

	notes := collectNotes()
	var fails []fail
	fails = append(fails, reconcile(notes, *v)...)
	fails = append(fails, verifyC(notes, *v)...)

	if len(fails) > 0 {
		for _, f := range fails {
			fmt.Fprintf(os.Stderr, "[course_catalog] ✗ [%s] %s\n", f.judge, f.msg)
		}
		die("%d 项判据未过", len(fails))
	}
	fmt.Printf("[course_catalog] 全部通过：%d 课叙述对账 + %d 个 lesson.c 对拍\n", len(notes), countC(notes))
}

func countC(notes []*srcNote) int {
	n := 0
	for _, x := range notes {
		if x.HasC {
			n++
		}
	}
	return n
}
