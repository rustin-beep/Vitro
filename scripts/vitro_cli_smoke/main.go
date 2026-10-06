// vitro_cli_smoke：统一 CLI 入口（wasm 壳 + launcher）的判定型闸（#49 批一）。
//
// 断言三组：
//
//	A. 壳四子命令 rc 契约（CLI_PROTOCOL_V1 五值表的壳侧覆盖面）；
//	B. **双臂同形对拍**——launcher 默认臂（wasm 壳）vs native exe 跑同一
//	   用例，stdout 归一（CRLF→LF）后逐行一致。这是「差异消灭在源头」的
//	   机判锚：两臂消费同一 gateway/引擎语义（note 通道 UTF-8、trap 文本
//	   同源、标记行协议同构），任何一臂漂移即红——零 canonicalize 特例。
//	C. launcher 语义：backend 标注行（stderr）+ --backend 覆盖转发。
//
// 前置：moonbit/_build 两产物在位（wasm-gc release gateway + native release
// cmd/vitro）——CI 步骤先建；本闸零参数（fail loud 缺产物即红）。
package main

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

var (
	repoRoot string
	failures int
)

func fatalf(format string, args ...any) {
	fmt.Printf("FAIL: "+format+"\n", args...)
	failures++
}

func normalize(s string) string {
	return strings.ReplaceAll(s, "\r\n", "\n")
}

// stripBackendLine：剥 `[vitro] backend=…` 标注行——B 组对拍的**唯一**允许
// 差异（backend 标注是设计差异非协议面：wasm 臂恒报 wasm、launcher 降级臂
// 报 native；其余任何行差异都红——零 canonicalize 特例）。
func stripBackendLine(s string) string {
	var kept []string
	for _, ln := range strings.Split(s, "\n") {
		if strings.HasPrefix(ln, "[vitro] backend=") {
			continue
		}
		kept = append(kept, ln)
	}
	return strings.Join(kept, "\n")
}

// runOut 执行并返回 (stdout+stderr 归一, rc)。缺产物/启动失败 = fail loud。
func runOut(name string, argv ...string) (string, int) {
	cmd := exec.Command(name, argv...)
	cmd.Dir = repoRoot
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	rc := 0
	if exit, ok := err.(*exec.ExitError); ok {
		rc = exit.ExitCode()
	} else if err != nil {
		fatalf("启动失败 %v %v: %v", name, argv, err)
		return "", -1
	}
	return normalize(stdout.String() + "\n--stderr--\n" + stderr.String()), rc
}

func main() {
	// cwd = 仓库根（防线惯例——vm_diff 等同款相对路径约定）
	repoRoot = "."

	shell := filepath.Join(repoRoot, "scripts", "vitro_cli", "main.js")
	nativeExe := filepath.Join(repoRoot, "moonbit", "_build", "native", "release", "build", "cmd", "vitro", "vitro.exe")
	wasmMod := filepath.Join(repoRoot, "moonbit", "_build", "wasm-gc", "release", "build", "gateway", "wasm", "wasm.wasm")
	for _, p := range []string{shell, nativeExe, wasmMod} {
		if _, err := os.Stat(p); err != nil {
			fmt.Printf("vitro_cli_smoke: 前置产物缺失 %s（先构建：moon build --release --target wasm-gc gateway/wasm 与 MOON_CC=clang moon build --release --target native cmd/vitro）\n", p)
			os.Exit(1)
		}
	}
	nodeBin, err := exec.LookPath("node")
	if err != nil {
		fmt.Println("vitro_cli_smoke: node 不在 PATH（wasm 臂宿主）")
		os.Exit(1)
	}

	// fixture：trap 用例 + quote-include 双文件（B 组对拍用）
	tmpDir := filepath.Join(repoRoot, "tmp", "cli_smoke_fixtures")
	os.MkdirAll(tmpDir, 0o755)
	trapC := filepath.Join(tmpDir, "trap_case.c")
	os.WriteFile(trapC, []byte("#include <stdio.h>\n#include <string.h>\nint main(){ char buf[4]; strcpy(buf, \"hello\"); printf(\"x\\n\"); return 0; }\n"), 0o644)
	incC := filepath.Join(tmpDir, "inc_case.c")
	incH := filepath.Join(tmpDir, "util.h")
	os.WriteFile(incH, []byte("#define MAGIC 42\n"), 0o644)
	os.WriteFile(incC, []byte("#include <stdio.h>\n#include \"util.h\"\nint main(){ printf(\"MAGIC=%d\\n\", MAGIC); return 0; }\n"), 0o644)
	plainC := filepath.Join(repoRoot, "corpus", "baseline", "array_sum_loop.c")

	// ── A 组：壳 rc 契约 ─────────────────────────────────────────
	type rcCase struct {
		name string
		argv []string
		want int
	}
	for _, c := range []rcCase{
		{"run 正常", []string{"run", plainC}, 0},
		{"run trap", []string{"run", trapC}, 2},
		{"run 编译错", []string{"run", "tmp/cli_smoke_fixtures/none.c"}, 4},
		{"compile 正常", []string{"compile", plainC}, 0},
		{"compile trap 源（编译面=0）", []string{"compile", trapC}, 0},
		{"step 正常", []string{"step", plainC}, 0},
		{"api 单帧 ok", []string{"api", "capabilities"}, 0},
		{"api 单帧 ok:false", []string{"api", "bogus.method"}, 1},
	} {
		_, rc := runOut(nodeBin, append([]string{shell}, c.argv...)...)
		if rc != c.want {
			fatalf("A[壳 rc] %s: rc=%d want %d", c.name, rc, c.want)
		} else {
			fmt.Printf("ok  A[壳 rc] %s rc=%d\n", c.name, rc)
		}
	}
	// api --batch（stdin 帧序列——状态跨帧：compile→run 连续）
	batch := `{"id":1,"method":"ping","params":{}}
{"id":2,"method":"compile","params":{"source":"int main(){return 0;}"}}
{"id":3,"method":"run","params":{}}
`
	cmd := exec.Command(nodeBin, shell, "api", "--batch")
	cmd.Dir = repoRoot
	cmd.Stdin = strings.NewReader(batch)
	var ob bytes.Buffer
	cmd.Stdout = &ob
	if err := cmd.Run(); err != nil {
		if exit, ok := err.(*exec.ExitError); !ok || exit.ExitCode() != 0 {
			fatalf("A[api --batch] 启动/rc 异常: %v（输出 %s）", err, ob.String())
		}
	}
	if !strings.Contains(ob.String(), `"pong":true`) || !strings.Contains(ob.String(), `"status":"finished"`) {
		fatalf("A[api --batch] 帧序列断言失败：%s", ob.String())
	} else {
		fmt.Println("ok  A[api --batch] ping+compile+run 状态跨帧")
	}

	// ── B 组：双臂同形对拍（核心锚——差异消灭的机判）────────────
	for _, c := range []struct {
		name string
		file string
	}{
		{"普通用例", plainC},
		{"trap 用例", trapC},
		{"quote-include 双文件", incC},
	} {
		relPath, _ := filepath.Rel(repoRoot, c.file)
		relPath = filepath.ToSlash(relPath)
		wasmOut, wasmRc := runOut(nodeBin, shell, "run", relPath)
		natOut, natRc := runOut(nativeExe, "run", relPath)
		if wasmRc != natRc {
			fatalf("B[双臂对拍] %s: rc 不一致 wasm=%d native=%d", c.name, wasmRc, natRc)
		}
		wasmOut, natOut = stripBackendLine(wasmOut), stripBackendLine(natOut)
		if wasmOut != natOut {
			fatalf("B[双臂对拍] %s: stdout/stderr 不一致\n--- wasm ---\n%s\n--- native ---\n%s", c.name, wasmOut, natOut)
		}
		fmt.Printf("ok  B[双臂对拍] %s（rc=%d 同形）\n", c.name, wasmRc)
	}

	// ── C 组：launcher 语义 ─────────────────────────────────────
	shLauncher := filepath.Join(repoRoot, "scripts", "bin", "vitro")
	outL, rcL := runOut("sh", shLauncher, "run", "corpus/baseline/array_sum_loop.c")
	if rcL != 0 {
		fatalf("C[launcher sh] 默认臂 rc=%d", rcL)
	}
	if !strings.Contains(outL, "backend=wasm") {
		fatalf("C[launcher sh] 默认臂缺 backend=wasm 标注：%s", outL)
	}
	fmt.Println("ok  C[launcher sh] 默认臂 backend 标注")

	outN, rcN := runOut("sh", shLauncher, "--backend", "native", "run", "corpus/baseline/array_sum_loop.c")
	if rcN != 0 {
		fatalf("C[launcher sh] --backend native rc=%d", rcN)
	}
	if !strings.Contains(outN, "backend=native") || !strings.Contains(outN, "程序运行完成") {
		fatalf("C[launcher sh] --backend native 输出异常：%s", outN)
	}
	fmt.Println("ok  C[launcher sh] --backend native 转发")

	// cmd 形态仅 Windows 断言（CI 双 runner 覆盖；sh 版全平台）
	if runtime.GOOS == "windows" {
		outC, rcC := runOut("cmd.exe", "/c", filepath.Join(repoRoot, "scripts", "bin", "vitro.cmd"), "run", "corpus/baseline/array_sum_loop.c")
		if rcC != 0 {
			fatalf("C[launcher cmd] 默认臂 rc=%d：%s", rcC, outC)
		}
		if !strings.Contains(outC, "backend=wasm") {
			fatalf("C[launcher cmd] 默认臂缺 backend 标注：%s", outC)
		}
		fmt.Println("ok  C[launcher cmd] 默认臂（Windows）")
	}

	if failures > 0 {
		fmt.Printf("vitro_cli_smoke: %d 失败\n", failures)
		os.Exit(1)
	}
	fmt.Println("vitro_cli_smoke: 全绿（rc 契约 + 双臂同形对拍 + launcher）")
}
