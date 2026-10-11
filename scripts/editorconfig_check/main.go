// editorconfig 机判闸（#61 零头，2026-10-11）：.editorconfig 声明的
// charset/end_of_line/insert_final_newline 三硬性项对全仓文本文件机判——
// 编辑器「建议」升格为 CI 红。规则面（与 .editorconfig 单源同步）：
//   - 通用（文本类）：UTF-8 可解码、LF 行尾、末行换行
//   - .json / .json.mbt：+ 缩进 2 空格（jsonmbt 合流批②扩面，#47 纪律 13 语境）
//
// 豁免：生成物（@generated 头标注）按「产物面漂移归生成器闸」原则排除
// （本闸只管手写面）；tmp/、_build/、.mooncakes/、node_modules/ 目录剪枝。
package main

import (
	"bufio"
	"bytes"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

var rootFlag = flag.String("root", ".", "仓库根")

func isText(raw []byte) bool {
	return bytes.IndexByte(raw, 0) < 0
}

func isGenerated(raw []byte) bool {
	n := len(raw)
	if n > 400 {
		n = 400
	}
	return bytes.Contains(raw[:n], []byte("@generated"))
}

func utf8Valid(raw []byte) bool {
	for i := 0; i < len(raw); {
		b := raw[i]
		if b < 0x80 {
			i++
			continue
		}
		var n int
		switch {
		case b&0xE0 == 0xC0:
			n = 2
		case b&0xF0 == 0xE0:
			n = 3
		case b&0xF8 == 0xF0:
			n = 4
		default:
			return false
		}
		if i+n > len(raw) {
			return false
		}
		for j := 1; j < n; j++ {
			if raw[i+j]&0xC0 != 0x80 {
				return false
			}
		}
		i += n
	}
	return true
}

// jsonIndentCheck：缩进 2 空格（逐行扫行首空白——缩进量非 2 的倍数即红）
func jsonIndentCheck(raw []byte) string {
	sc := bufio.NewScanner(bytes.NewReader(raw))
	ln := 0
	for sc.Scan() {
		ln++
		line := sc.Text()
		if strings.TrimSpace(line) == "" {
			continue
		}
		ind := len(line) - len(strings.TrimLeft(line, " "))
		if ind%2 != 0 {
			return fmt.Sprintf("第 %d 行缩进 %d（非 2 的倍数）", ln, ind)
		}
	}
	return ""
}

func main() {
	flag.Parse()
	var offenders []string
	base, _ := filepath.Abs(*rootFlag)
	_ = filepath.Walk(base, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		rel, _ := filepath.Rel(base, path)
		for _, seg := range strings.Split(rel, string(filepath.Separator)) {
			if seg == ".git" || seg == "_build" || seg == ".mooncakes" ||
				seg == "node_modules" || seg == "tmp" || seg == ".clang_cache_cd" ||
				seg == ".shadow_tmp" || seg == "tmp_vitro_fs_bb_roundtrip" || seg == ".vscode" || seg == "build" {
				return filepath.SkipDir
			}
		}
		if info.IsDir() {
			return nil
		}
		raw, err := os.ReadFile(path)
		if err != nil || !isText(raw) || isGenerated(raw) {
			return nil
		}
		name := filepath.Base(path)
		// 豁免面（手写面之外）：① jsonmbt 机器写回的 .json（emitter 缩进=1 是
		// 其输出契约——改缩进即破坏 round-trip；含 golden digest 族）
		// ② 实测样本库（用户采集样本保真优先——末行换行改写属内容改写）
		// ③ reports/（shadow 时代一次性产物，非活跃手写面）
		if strings.HasSuffix(name, ".json") || strings.HasSuffix(name, ".json.mbt") {
			// jsonmbt 真源族按前缀豁免缩进项（末行换行等通用项仍管）
			if strings.HasPrefix(rel, "scripts"+string(filepath.Separator)+"moonbit"+string(filepath.Separator)+"diagnostics_data") ||
				strings.HasPrefix(rel, "scripts"+string(filepath.Separator)+"teaching_annotation_diff") ||
				strings.HasPrefix(rel, "scripts"+string(filepath.Separator)+"vm_diff") ||
				strings.HasPrefix(rel, "scripts"+string(filepath.Separator)+"clang_direct") ||
				strings.HasPrefix(rel, "scripts"+string(filepath.Separator)+"lexer_diff") ||
				strings.HasPrefix(rel, "scripts"+string(filepath.Separator)+"typeck_diff") ||
				strings.HasPrefix(rel, "scripts"+string(filepath.Separator)+"codegen_diff") ||
				strings.HasPrefix(rel, "scripts"+string(filepath.Separator)+"protocol_frames") ||
				strings.HasPrefix(rel, "scripts"+string(filepath.Separator)+"parser_diff") {
				return nil // 机器写回面：整体豁免（生成器 -check 闸管漂移）
			}
		}
		if strings.HasPrefix(rel, "docs"+string(filepath.Separator)+"current"+string(filepath.Separator)+"07-质量与裁定"+string(filepath.Separator)+"demo实测样本库") ||
			strings.HasPrefix(rel, "reports"+string(filepath.Separator)) {
			return nil // 样本保真 / 一次性报告面
		}
		if !utf8Valid(raw) {
			offenders = append(offenders, rel+"（非 UTF-8 字节）")
			return nil
		}
		// CRLF 归一后判（core.autocrlf=true 的 Windows checkout 会把索引 LF
		// 展开为工作区 CRLF——git ls-files --eol 实测 i/lf w/crlf；仓库形态
		// 合规，工作区展开是环境产物。残留 lone-CR（无 LF 配对）仍红）
		if bytes.IndexByte(raw, 0x0d) >= 0 {
			norm := bytes.ReplaceAll(raw, []byte{0x0d, 0x0a}, []byte{0x0a})
			if bytes.IndexByte(norm, 0x0d) >= 0 {
				offenders = append(offenders, rel+"（lone CR——非 CRLF 对形态）")
			}
			raw = norm
		}
		if len(raw) > 0 && raw[len(raw)-1] != 0x0a {
			offenders = append(offenders, rel+"（缺末行换行）")
		}
		if strings.HasSuffix(name, ".json") || strings.HasSuffix(name, ".json.mbt") {
			if v := jsonIndentCheck(raw); v != "" {
				offenders = append(offenders, rel+"（"+v+"）")
			}
		}
		return nil
	})
	if len(offenders) > 0 {
		for _, o := range offenders {
			fmt.Println("editorconfig_check: " + o)
		}
		fmt.Printf("editorconfig_check: FAIL——%d 处违反（.editorconfig 硬性项）\n", len(offenders))
		os.Exit(1)
	}
	fmt.Println("editorconfig_check: PASS——.editorconfig 硬性项（UTF-8/LF/末行换行/JSON 缩进）全仓合规")
}
