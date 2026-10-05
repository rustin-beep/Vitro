// precompile_bytecode_libc —— Bytecode Libc 预编译产物的**冻结完整性闸**
// （工序④删区批 2026-10-05 重定位：原「活性生成器」靠 vitro_cli〔Rust oracle〕
// export 预编译 libc C 源——oracle 随 native/ 删除后无法再生成）。
//
// 现役形态（--check，CI）：源 digest 静态校验——
//
//	scripts/moonbit/libc_src/（C 源，2026-10-05 自 native/runtime_libc 迁出）
//	↔ scripts/moonbit/libc_data/bytecode_libc_data.json 内嵌 source_digest
//
//	一致即 PASS（产物 = 冻结终态；libc 源变更即红）。重生成须 checkout tag
//	rust-oracle-freeze 重建 oracle 后以 git 历史版生成模式执行（本版已收敛
//	为 check-only——生成段/RS/layout/双写随 Rust 区退役）。
//
// J9：篡改 libc 源一字节 → digest 失配红；产物缺 source_digest 字段红。
package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"sort"
)

var (
	root     = repoRoot()
	srcDirs  = []string{filepath.Join(root, "scripts", "moonbit", "libc_src", "src"), filepath.Join(root, "scripts", "moonbit", "libc_src", "vitro")}
	artifact = filepath.Join(root, "scripts", "moonbit", "libc_data", "bytecode_libc_data.json")
)

// digestSchema 摘要 schema 版本：源文件集合或摘要算法变化时递增。
const digestSchema = 1

func repoRoot() string {
	wd, err := os.Getwd()
	if err != nil {
		fmt.Fprintln(os.Stderr, "无法取工作目录:", err)
		os.Exit(2)
	}
	dir := wd
	for i := 0; i < 6; i++ {
		ok := true
		for _, m := range []string{"corpus", "scripts"} {
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
	fmt.Fprintln(os.Stderr, "请在仓库内运行：找不到包含 corpus/ 与 scripts/ 的项目根")
	os.Exit(2)
	return ""
}

// sourceFiles 返回 libc_src 下参与预编译的源文件（按路径排序——确定性）。
func sourceFiles(includeHeaders bool) []string {
	exts := map[string]bool{".c": true, ".cpp": true}
	if includeHeaders {
		exts[".h"] = true
	}
	var files []string
	for _, dir := range srcDirs {
		ents, err := os.ReadDir(dir)
		if err != nil {
			continue
		}
		for _, e := range ents {
			if e.IsDir() {
				continue
			}
			if exts[filepath.Ext(e.Name())] {
				files = append(files, filepath.Join(dir, e.Name()))
			}
		}
	}
	sort.Strings(files)
	return files
}

// computeSourceDigest：源内容（行尾归一）+ schema 联合摘要——算法与删区前
// 生成器逐位同源（git 历史版复刻），产物内 digest 可直接对账。
func computeSourceDigest() string {
	h := sha256.New()
	fmt.Fprintf(h, "schema=%d\n", digestSchema)
	for _, f := range sourceFiles(true) {
		rel, _ := filepath.Rel(root, f)
		h.Write([]byte(filepath.ToSlash(rel)))
		h.Write([]byte{0})
		b, err := os.ReadFile(f)
		if err != nil {
			fmt.Fprintln(os.Stderr, "读源文件失败:", f, err, "（digest 拒绝静默缺文件——2026-10-05 审阅 P3）")
			os.Exit(2)
		}
		h.Write(bytes.ReplaceAll(b, []byte("\r\n"), []byte("\n")))
		h.Write([]byte{0})
	}
	return "sha256:" + hex.EncodeToString(h.Sum(nil))
}

func main() {
	check := flag.Bool("check", false, "源↔产物 digest 完整性校验（CI 形态）")
	flag.Parse()
	if !*check {
		fmt.Fprintln(os.Stderr, "生成模式已随 Rust oracle 退役（工序④ 2026-10-05）——产物为冻结终态；重生成须 checkout tag rust-oracle-freeze 重建 oracle 后用 git 历史版生成模式。现役仅 --check。")
		os.Exit(2)
	}
	raw, err := os.ReadFile(artifact)
	if err != nil {
		fmt.Fprintf(os.Stderr, "  missing artifact: %s: %v\n", artifact, err)
		os.Exit(1)
	}
	var probe struct {
		SourceDigest string `json:"source_digest"`
	}
	if err := json.Unmarshal(raw, &probe); err != nil || probe.SourceDigest == "" {
		fmt.Fprintln(os.Stderr, "  artifact unreadable or no source_digest")
		os.Exit(1)
	}
	current := computeSourceDigest()
	if probe.SourceDigest != current {
		fmt.Fprintf(os.Stderr, "  recorded digest: %s\n  current  digest: %s\n  source files: %d under scripts/moonbit/libc_src\n", probe.SourceDigest, current, len(sourceFiles(true)))
		fmt.Fprintln(os.Stderr, "ERROR: libc 源已变更而冻结产物未更新（重生成走 rust-oracle-freeze 历史路径）")
		os.Exit(1)
	}
	fmt.Println("Precompiled artifact integrity OK（libc 源 ↔ 冻结产物 digest 一致）")
}
