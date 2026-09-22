// canonicalize：差分锚的 JSON 归一器 CLI（P7，2026-09-19）。
//
// 归一规则与实现**单源**在 scripts/internal/canonicalize——本文件只是 CLI
// 壳：stdin 进 stdout 出，--check 为锚定模式（输入已是规范形则 exit 0）。
//
// ⚠️ **本壳不可删**——它不是"驱动都进程内化了、没人用"的遗留物，存在一条硬
// 约束：冻结区 `native/tests/ast_dump_test.rs` 的 `canonicalize()` 以
// `go run ../scripts/canonicalize` 子进程调用本 CLI（stdin→stdout 契约：写
// stdin、读满 stdout、**非 0 退出即 panic**）。删壳或改 CLI 契约会直接打断
// 冻结区测试。其余用途：管道、人工核对、--check 锚定模式。
// 归一器进程内化的动因与代价见 scripts/internal/canonicalize 包注释。
//
// 用法：
//
//	go run ./scripts/canonicalize < in.json              # 输出规范形
//	go run ./scripts/canonicalize --check < in.json      # 已规范 exit 0，否则 exit 1（锚定模式）
//	echo '{"b":1,"a":2}' | go run ./scripts/canonicalize # 管道
package main

import (
	"bytes"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"

	"vitro/scripts/internal/canonicalize"
)

// run：CLI 主体。显式出入参、不碰 os.Stdin / os.Exit——使 --check 分支与退出码
// 可在包内直测（2026-09-22 补锚：此前该分支无仓内锚，TestCheckBytes 名不副实，
// 只做幂等断言，从未调 CLI、未断言退出码）。返回进程退出码。
func run(args []string, stdin io.Reader, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("canonicalize", flag.ContinueOnError)
	fs.SetOutput(stderr)
	check := fs.Bool("check", false, "锚定模式：输入已是规范形则 exit 0，否则 exit 1")
	if err := fs.Parse(args); err != nil {
		// 与原全局 flag.ExitOnError 口径对齐：-h/--help 退出 0，其余解析错退出 2。
		if errors.Is(err, flag.ErrHelp) {
			return 0
		}
		return 2
	}

	raw, err := io.ReadAll(stdin)
	if err != nil {
		fmt.Fprintf(stderr, "canonicalize: 读 stdin 失败: %v\n", err)
		return 1
	}

	canonical, err := canonicalize.Bytes(raw)
	if err != nil {
		fmt.Fprintf(stderr, "canonicalize: JSON 归一失败（拒绝输出，不猜不兜底）: %v\n", err)
		return 1
	}

	if *check {
		// 口径按实况写：比较前双侧 TrimSpace——**首尾空白（含尾随换行）容忍**，
		// 判定面只有键序 / 缩进 / 转义三项（2026-09-22 实测：缺尾随换行、前导
		// 换行、前后空格均 exit 0；原文案宣称"尾随换行不匹配"与实况不符，已改）。
		// 容忍是既定语义，锚在 main_test.go。
		if !bytes.Equal(bytes.TrimSpace(raw), bytes.TrimSpace(canonical)) {
			fmt.Fprintln(stderr, "输入不是规范形（键序/缩进/转义之一不匹配；首尾空白容忍）")
			return 1
		}
		return 0
	}
	// 与原实现同：写出错不判定（契约由消费方读齐 stdout 保证——冻结区
	// ast_dump_test.rs 读满 stdout 后才校验退出码）。保持逐字节行为对齐，
	// 不在抽库批里改 CLI 契约。
	_, _ = stdout.Write(canonical)
	return 0
}

func main() {
	os.Exit(run(os.Args[1:], os.Stdin, os.Stdout, os.Stderr))
}
