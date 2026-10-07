//go:build windows

// Package capi 是防线脚本共享的基础工具单源：仓库根定位（ProjectRoot）、
// fail loud 退出（Fatal）、字符截断（TruncateRunes）。
//
// 历史：本包曾是引擎 DLL（vitro_native.dll）C ABI 绑定与字符串读取的单源
// 封装（D5 重构，2026-09-13）——随 Rust 对照区退役（2026-10-05 删区），DLL
// 绑定族（Load/EnsureFreshArtifacts/EngineVersionString/ReadChannel/
// CompileErrorsExact/RunProgramStdout/RuntimeErr 等）零调用者成为死代码，
// 2026-10-07 批五审阅 P3-3 清理删除（其「产物新鲜度」语义已由
// scripts/internal/freshness 以 moon 产物为对象重建——同名概念双源就此
// 收口；CBytes/Normalize/MsSince/GitShortHead 同批随删）。
package capi

import (
	"fmt"
	"os"
	"path/filepath"
	"sync"
)

// ---------------------------------------------------------------- 路径

var (
	projectRootOnce sync.Once
	projectRoot     string
)

// ProjectRoot 返回仓库根（含 corpus/ 与 scripts/ 的目录——2026-10-05 删区后 native/ 不再作标记），找不到时 exit 2。
// Go 没有 Python 的 __file__ 锚点（go run 的可执行文件在 GOCACHE 临时目录），
// 按"包含 corpus/ 与 scripts/ 的目录"向上探测，允许从仓库根、scripts/ 或更深
// 子目录运行。
func ProjectRoot() string {
	projectRootOnce.Do(func() { projectRoot = findProjectRoot() })
	return projectRoot
}

func findProjectRoot() string {
	wd, err := os.Getwd()
	if err != nil {
		fmt.Fprintln(os.Stderr, "无法确定工作目录:", err)
		os.Exit(2)
	}
	dir := wd
	for i := 0; i < 5; i++ {
		if isProjectRoot(dir) {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	fmt.Fprintln(os.Stderr, "请在仓库内运行：找不到包含 native/ 与 scripts/ 的项目根")
	os.Exit(2)
	return ""
}

func isProjectRoot(dir string) bool {
	for _, marker := range []string{"corpus", "scripts"} { // 工序④删区（2026-10-05）：native/ 已删，根标记换 corpus/
		if fi, err := os.Stat(filepath.Join(dir, marker)); err != nil || !fi.IsDir() {
			return false
		}
	}
	return true
}

// ---------------------------------------------------------------- 工具函数

// Fatal 格式化错误到 stderr 并 exit 2（防线脚本 fail loud 统一口径）。
func Fatal(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "FATAL: "+format+"\n", args...)
	os.Exit(2)
}

// TruncateRunes 按字符数截断（Python 的 s[:n] 是字符截断，Go 切片是字节）。
func TruncateRunes(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n])
}
