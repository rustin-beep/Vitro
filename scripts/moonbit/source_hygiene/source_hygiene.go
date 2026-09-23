// source_hygiene：源码卫生扫描（NUL 字节 / i/-text 事故族）。
//
// 用法（仓库根）：
//
//	go run ./scripts/moonbit/source_hygiene          # 扫描并列出命中
//	go run ./scripts/moonbit/source_hygiene -check   # 同（-check 为与兄弟闸调用形态一致）
//
// **事故族**（两次实锤）：含真 NUL 的文件被 git 判二进制（`git ls-files --eol`
// 显示 `w/-text`，`git diff` 只显示 `Bin N -> M bytes`）⇒
//
//	① .gitattributes 的 `text eol=lf` 全部失效（git 跳过文本转换）；
//	② diff/PR 审阅完全不可见（先例：docs/** 148 行行尾事故族；
//	   2026-09-23 host/host_test.mbt 15KB 黑盒测试整文件不可见）。
//
// 根因是"源码字面量里落了真字节而非转义写法"（`b"x" + NUL` vs `b"x\x00"`）——
// 多字节转义经 shell/python 管道写入时最易发生，故以闸兜底。
//
// 扫描集 = **git 跟踪的全部文件**（`git ls-files`，仓库根）：
// fail-safe（新文件类型自动进闸，不存在扩展名白名单的静默跳过）；当前
// tracked 集合零二进制文件 → 零假阳性。若将来确需入库含 NUL 的产物，
// 在 source_hygiene_allowlist.txt 显式登记（一行一路径，附理由），
// 未登记即红——禁止用扩展名白名单静默放行。
package main

import (
	"bufio"
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

func main() {
	root := repoRoot()
	_ = os.Chdir(root)

	allow := map[string]bool{}
	if f, err := os.Open("scripts/moonbit/source_hygiene_allowlist.txt"); err == nil {
		sc := bufio.NewScanner(f)
		for sc.Scan() {
			line := strings.TrimSpace(sc.Text())
			if line != "" && !strings.HasPrefix(line, "#") {
				allow[line] = true
			}
		}
		f.Close()
	}

	out, err := exec.Command("git", "ls-files", "-z").Output()
	if err != nil {
		fatal("git ls-files 失败（须在 git 仓库内运行）：%v", err)
	}
	files := strings.Split(strings.TrimRight(string(out), "\x00"), "\x00")
	if len(files) == 0 {
		fatal("git ls-files 为空——fail loud（空集不得绿）")
	}

	hit := 0
	for _, p := range files {
		if allow[p] {
			continue
		}
		data, err := os.ReadFile(p)
		if err != nil {
			// 工作区缺文件（如子模块/稀疏检出）不在此闸职责内，跳过但计数
			continue
		}
		if i := bytes.IndexByte(data, 0); i >= 0 {
			n := bytes.Count(data, []byte{0})
			fmt.Printf("含真 NUL: %s（首个偏移 %d，共 %d 个）——改转义写法（如 \\x00）或登记 allowlist\n", p, i, n)
			hit++
		}
	}
	if hit > 0 {
		fatal("source_hygiene: %d 个被跟踪文件含真 NUL（git 将判二进制，diff 不可见）", hit)
	}
	fmt.Printf("source_hygiene: OK（%d 个被跟踪文件零真 NUL）\n", len(files))
}

// repoRoot：向上找 go.mod 定位仓库根（CI 与本地 cwd 差异兼容）。
func repoRoot() string {
	d, err := os.Getwd()
	if err != nil {
		fatal("getwd: %v", err)
	}
	for {
		if _, err := os.Stat(filepath.Join(d, "go.mod")); err == nil {
			return d
		}
		parent := filepath.Dir(d)
		if parent == d {
			fatal("未找到仓库根（go.mod）")
		}
		d = parent
	}
}

func fatal(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "source_hygiene: "+format+"\n", args...)
	os.Exit(2)
}
