// wasmopt —— wasm-gc 产物构建后置优化驱动（#120 批①，2026-10-17）。
//
// 形态：Go 驱动（供给管理/校验/确定性自检/fail loud）+ node 执行器
// （wasmopt.mjs——binaryen JS API；供给 = npm tarball 钉版本下载到
// tools/cache，sha256 校验，Go 标准库解包零三方依赖）。
// 特征位组合与等价性背书见 wasmopt.mjs 头注；体积收益 = lean 产物
// 实测 -19.3% raw / -20.4% gzip（1872 帧逐字节一致在案）。
//
// 用法（仓库根）：
//
//	go run ./scripts/wasmopt <file.wasm>        # 原地优化（两次运行 digest 一致才落盘）
//	go run ./scripts/wasmopt -check <file.wasm> # 幂等校验：产物已优化（再优化不变）
//
// fail loud：下载失败 / sha256 不符 / 解包缺件 / 优化产物非法（wasm
// magic 头）/ 二次运行不确定（binaryen 确定性破坏）/ -check 非 fixpoint。
// 缓存：tools/cache/binaryen-<ver>/（gitignore——本地与 CI 同版本钉死，
// 冷缓存自动下载 ~23MB 一次）。
package main

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

const (
	binaryenVersion = "132.0.0"
	binaryenURL     = "https://registry.npmjs.org/binaryen/-/binaryen-" + binaryenVersion + ".tgz"
	// 钉死校验（2026-10-17 实下载取得；npm dist shasum1 =
	// 7d8e2d3a501bfc2d93e6e906c2460e551a84d927 互证）
	binaryenSHA256 = "6543555fb29bb92548f325c7dc18e9ab7dbb1215edda25993d1e3f71d85b8618"
	cacheRoot      = "tools/cache"
)

func die(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "[wasmopt] FAIL: "+format+"\n", args...)
	os.Exit(1)
}

// ensureSupply 本地缓存就位（缺则下载 + sha256 + 解包）。
func ensureSupply() string {
	dir := filepath.Join(cacheRoot, "binaryen-"+binaryenVersion, "package")
	entry := filepath.Join(dir, "index.js")
	if _, err := os.Stat(entry); err == nil {
		return dir
	}
	fmt.Printf("[wasmopt] 冷缓存：下载 %s（钉版本 + sha256 校验）…\n", binaryenURL)
	resp, err := http.Get(binaryenURL)
	if err != nil {
		die("下载失败: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		die("下载失败: HTTP %d", resp.StatusCode)
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		die("读响应失败: %v", err)
	}
	sum := sha256.Sum256(body)
	got := hex.EncodeToString(sum[:])
	if got != binaryenSHA256 {
		die("sha256 不符：期望 %s 实得 %s（供给被篡改或 registry 漂移——更新须人工改钉值）", binaryenSHA256, got)
	}
	if err := os.MkdirAll(filepath.Dir(entry), 0o755); err != nil {
		die("建缓存目录失败: %v", err)
	}
	if err := extractTarGz(body, filepath.Dir(dir)); err != nil {
		die("解包失败: %v", err)
	}
	if _, err := os.Stat(entry); err != nil {
		die("解包后缺 %s（包形态漂移）", entry)
	}
	return dir
}

func extractTarGz(data []byte, dest string) error {
	gz, err := gzip.NewReader(bytes.NewReader(data))
	if err != nil {
		return err
	}
	defer gz.Close()
	tr := tar.NewReader(gz)
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}
		switch hdr.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(filepath.Join(dest, filepath.FromSlash(hdr.Name)), 0o755); err != nil {
				return err
			}
		case tar.TypeReg:
			p := filepath.Join(dest, filepath.FromSlash(hdr.Name))
			if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
				return err
			}
			f, err := os.Create(p)
			if err != nil {
				return err
			}
			if _, err := io.Copy(f, tr); err != nil {
				f.Close()
				return err
			}
			f.Close()
		case tar.TypeSymlink:
			// npm 包内符号链接（bin/ 脚本族）——执行器只用 index.js，跳过
		}
	}
}

func fileSHA256(p string) (string, []byte) {
	b, err := os.ReadFile(p)
	if err != nil {
		die("读文件失败 %s: %v", p, err)
	}
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:]), b
}

// runOnce 跑一次优化到临时产物，返回其 sha256。
func runOnce(mjs, supply, inPath, outPath string) string {
	cmd := exec.Command("node", mjs, inPath, outPath, supply)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		die("优化执行失败: %v", err)
	}
	digest, data := fileSHA256(outPath)
	// 产物 sanity：wasm magic（\0asm）——非法产物禁回写
	if len(data) < 4 || data[0] != 0x00 || data[1] != 'a' || data[2] != 's' || data[3] != 'm' {
		die("优化产物非法（非 wasm magic）：%s", outPath)
	}
	return digest
}

func main() {
	check := flag.Bool("check", false, "幂等校验：产物已优化（再优化逐字节不变）")
	flag.Parse()
	if flag.NArg() != 1 {
		die("用法: go run ./scripts/wasmopt [-check] <file.wasm>")
	}
	target, err := filepath.Abs(flag.Arg(0))
	if err != nil {
		die("路径解析失败: %v", err)
	}
	supply := ensureSupply()
	mjs, err := filepath.Abs("scripts/wasmopt/wasmopt.mjs")
	if err != nil {
		die("路径解析失败: %v", err)
	}
	tmp1 := target + ".opt1.tmp"
	tmp2 := target + ".opt2.tmp"
	defer os.Remove(tmp1)
	defer os.Remove(tmp2)

	sidecar := target + ".wasmopt.sha256"
	if *check {
		want, err := os.ReadFile(sidecar)
		if err != nil {
			die("-check 无 sidecar（%s）——产物从未经本驱动优化", sidecar)
		}
		got, _ := fileSHA256(target)
		wantS := strings.TrimRight(string(want), "\n")
		if wantS != got {
			die("-check digest 失配：现产物 %s ≠ 标记 %s——moon 重建已覆盖优化产物，重跑 go run ./scripts/wasmopt", got[:12], wantS[:12])
		}
		fmt.Printf("[wasmopt] check OK：产物为优化终态（%s）\n", got[:12])
		return
	}
	origDigest, origData := fileSHA256(target)
	if want, err := os.ReadFile(sidecar); err == nil && strings.TrimRight(string(want), "\n") == origDigest {
		fmt.Printf("[wasmopt] 产物已是优化终态（%s），跳过\n", origDigest[:12])
		return
	}
	start := time.Now()
	d1 := runOnce(mjs, supply, target, tmp1)
	d2 := runOnce(mjs, supply, target, tmp2)
	if d1 != d2 {
		die("确定性破坏：两次优化 digest 不一致（%s ≠ %s）——binaryen 非确定或环境异常，拒落盘", d1[:12], d2[:12])
	}
	if err := os.Rename(tmp1, target); err != nil {
		die("落盘失败: %v", err)
	}
	if err := os.WriteFile(sidecar, []byte(d1+"\n"), 0o644); err != nil {
		die("写 sidecar 失败: %v", err)
	}
	_, newData := fileSHA256(target)
	fmt.Printf("[wasmopt] %s: %d -> %d B（gzip %d -> %d B，-%.1f%%）耗时 %s\n",
		filepath.Base(target), len(origData), len(newData),
		gzipSize(origData), gzipSize(newData),
		100*(1-float64(len(newData))/float64(len(origData))),
		time.Since(start).Round(time.Millisecond))
}

func gzipSize(b []byte) int {
	var buf bytes.Buffer
	gz, _ := gzip.NewWriterLevel(&buf, 9)
	gz.Write(b)
	gz.Close()
	return buf.Len()
}
