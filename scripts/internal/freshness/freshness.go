// Package freshness —— MoonBit 产物（native exe / wasm-gc 模块）的新鲜度
// 门禁单源（批五 P2-5 落地，2026-10-07；语义照搬 vm_diff 2026-09-26 批改版，
// 自 vm_diff 上提五家共用）。
//
// 背景：replay / serve_smoke / protocol_frames / teaching_annotation_diff
// 此前对被测 serve exe「按文件在位即用」——陈旧产物（源码已改、exe 未重建）
// 产生批量假红（2026-10-07 实锤：teaching 145 处红全部源于陈旧 debug serve
// exe，重建后 82/82 绿）。同时 mtime 硬红不可取：moon 增量按**内容 hash**
// 判定——touch、git 换行归一重写、等价内容再生成都会让 mtime 落后而产物
// 内容其实最新（vm_diff 实测：提交批的 git add 换行归一即触发假阳性）。
// 故门禁形态 = **mtime 触发 + 构建复核**：
//
//  1. 产物缺失 → fail loud（提示构建命令，exit 1）；
//  2. moonbit/ 任一源文件（.mbt/.mod/.pkg，跳过 _build 与 .mooncakes）新于
//     产物 → 跑一次规范化构建复核：退出码 0 ⇒ moon 已保证内容最新（重链了
//     或 hash 判定 no-work），放行；失败 ⇒ 红并拒绝继续（陈旧产物假红/假绿
//     由此封死）；复核成功但产物仍缺失（moon 缓存与磁盘不一致）⇒ 红。
package freshness

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"vitro/scripts/internal/capi"
)

// EnsureFresh 断言产物新鲜（不新鲜则构建复核，复核失败 exit 1）。
// prefix 是调用方名（错误消息前缀，如 "vm_diff"）；exePath 是被测产物路径；
// buildArgs 是复核构建命令（cwd=moonbit/，如 "build", "--release",
// "--target", "native", "cmd/run"）。
func EnsureFresh(prefix, exePath string, buildArgs ...string) {
	if _, err := os.Stat(exePath); err != nil {
		fmt.Fprintf(os.Stderr, "%s: %s 不存在——先跑 cd moonbit && moon %s\n",
			prefix, exePath, strings.Join(buildArgs, " "))
		os.Exit(1)
	}
	if stale := findStaleSource(exePath); stale != "" {
		fmt.Fprintf(os.Stderr, "%s: %s 旧于源 %s——跑构建复核（moon 内容 hash 增量）...\n",
			prefix, exePath, stale)
		if !rebuild(buildArgs) {
			fmt.Fprintf(os.Stderr, "%s: 构建失败——修好构建前不给判定（陈旧产物假红/假绿由此封死）\n", prefix)
			os.Exit(1)
		}
		if _, err := os.Stat(exePath); err != nil {
			fmt.Fprintf(os.Stderr, "%s: 构建成功但 %s 仍缺失（moon 缓存与磁盘不一致）——删对应 _build 目标目录后重建\n",
				prefix, exePath)
			os.Exit(1)
		}
	}
}

// rebuild 跑规范化构建（cwd=仓库根/moonbit）——退出码 0 即 moon 已保证产物
// 内容最新；供 mtime 落后时复核。
//
// **MOON_CC=clang 显式注入（审阅 P2-1，2026-10-07）**：CI 的 MOON_CC 全是
// 行内前缀（ci.yml 无 workflow env: 级声明），进程继承不到——复核构建若落
// Windows 默认 cl 会撞 moon#2254 构建悬崖（分钟级）且失败文案误导为「代码
// 构建坏了」。此处与 ci.yml 各步同款显式注入（AGENTS 纪律 11 连坐）。
func rebuild(buildArgs []string) bool {
	cmd := exec.Command("moon", buildArgs...)
	cmd.Env = append(os.Environ(), "MOON_CC=clang")
	cmd.Dir = filepath.Join(capi.ProjectRoot(), "moonbit")
	out, err := cmd.CombinedOutput()
	if err != nil {
		fmt.Fprintln(os.Stderr, string(out))
		return false
	}
	return true
}

// findStaleSource 返回任一比产物新的 moonbit 源文件（.mbt/.mod/.pkg；跳过
// _build 产物目录与 .mooncakes），全新鲜则返回空串。
//
// **测试文件排除（审阅 P3-4，2026-10-07）**：*_test.mbt / *_wbtest.mbt 不
// 参与 `moon build` 产物——纳入扫描面会把「改一个测试锚」误判为产物陈旧
// 并触发构建复核（叠加 P2-1 的 MSVC 悬崖曾是分钟级浪费）。判据=后缀排除。
func findStaleSource(artifact string) string {
	st, err := os.Stat(artifact)
	if err != nil {
		return artifact
	}
	artMtime := st.ModTime()
	var stale string
	root := filepath.Join(capi.ProjectRoot(), "moonbit")
	_ = filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			if d.Name() == "_build" || d.Name() == ".mooncakes" {
				return filepath.SkipDir
			}
			return nil
		}
		name := d.Name()
		if strings.HasSuffix(name, "_test.mbt") || strings.HasSuffix(name, "_wbtest.mbt") {
			return nil
		}
		if strings.HasSuffix(name, ".mbt") || strings.HasSuffix(name, ".mod") ||
			strings.HasSuffix(name, ".pkg") {
			if info, err := d.Info(); err == nil && info.ModTime().After(artMtime) {
				if stale == "" {
					stale = path
				}
			}
		}
		return nil
	})
	return stale
}
