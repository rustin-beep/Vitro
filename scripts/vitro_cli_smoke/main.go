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
// --corpus N：B 组语料级扩面（#49 批二）——corpus/baseline 按稳定序取前 N
// 例三臂对拍（wasm+js+native 同判定口径；js 臂连坐 2026-10-15）。缺省
// 0 = 只跑内置三 fixture；CI 接 30 例。
//
// 前置：moonbit/_build 两产物在位（wasm-gc release gateway + native release
// cmd/vitro）——CI 步骤先建；缺产物即红（fail loud）。
package main

import (
	"bytes"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
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

// firstDiff：两 buffer 首个差异偏移（等长前提；映像对拍诊断用）。
func firstDiff(a, b []byte) int {
	n := len(a)
	if len(b) < n {
		n = len(b)
	}
	for i := 0; i < n; i++ {
		if a[i] != b[i] {
			return i
		}
	}
	return n
}

func main() {
	corpusN := flag.Int("corpus", 0, "B 组语料级扩面：corpus/baseline 取前 N 例三臂对拍 wasm+js+native（CI=30）")
	flag.Parse()
	// cwd = 仓库根（防线惯例——vm_diff 等同款相对路径约定）
	repoRoot = "."

	// main.js 退役批（2026-10-16）：wasm 臂被测物 = cmd/vitro_wasm js 产物
	// （MoonBit 胶水——gateway wasm 产物的宿主壳；main.js 已删）
	shell := filepath.Join(repoRoot, "moonbit", "_build", "js", "release", "build", "cmd", "vitro_wasm", "vitro_wasm.js")
	nativeExe := filepath.Join(repoRoot, "moonbit", "_build", "native", "release", "build", "cmd", "vitro", "vitro.exe")
	wasmMod := filepath.Join(repoRoot, "moonbit", "_build", "wasm-gc", "release", "build", "gateway", "wasm", "wasm.wasm")
	jsEntry := filepath.Join(repoRoot, "moonbit", "_build", "js", "release", "build", "cmd", "vitro_js", "vitro_js.js")
	wasmGlue := shell
	for _, p := range []string{wasmGlue, nativeExe, wasmMod, jsEntry} {
		if _, err := os.Stat(p); err != nil {
			fmt.Printf("vitro_cli_smoke: 前置产物缺失 %s（先构建：moon build --release --target wasm-gc gateway/wasm + MOON_CC=clang moon build --release --target native cmd/vitro + moon build --release --target js cmd/vitro_js + moon build --release --target js cmd/vitro_wasm）\n", p)
			os.Exit(1)
		}
	}
	nodeBin, err := exec.LookPath("node")
	if err != nil {
		fmt.Println("vitro_cli_smoke: node 不在 PATH（wasm 臂宿主）")
		os.Exit(1)
	}
	// node 版本前置闸（P2，2026-10-15 用户审阅提醒）：vitro_wasm 的 MIN_NODE=25
	// 以下 wasm 壳恒退 rc=5 哨兵（#106）——不前置拦截会把宿主版本不足
	// 误报成整片「输出不一致」（node 22 下 92 条误导红的实录），真因被
	// 埋。版本不足即红，不静默跳过（fail loud）。门槛数字与 main.js
	// MIN_NODE 同步维护。
	if vout, verr := exec.Command(nodeBin, "--version").Output(); verr == nil {
		v := strings.TrimPrefix(strings.TrimSpace(string(vout)), "v")
		if major, aerr := strconv.Atoi(strings.SplitN(v, ".", 2)[0]); aerr == nil && major < 22 {
			fmt.Printf("vitro_cli_smoke: 宿主 node %s < 22（wasm 臂 js-string builtins 需要——vitro_wasm MIN_NODE=22 同源门槛，f49794f6 降 LTS 批同步）。\n"+
				"wasm 臂将恒退 rc=5 降级哨兵，后续对拍会整片误报「输出不一致」。先升级 node ≥ 25 再跑本闸。\n", v)
			os.Exit(1)
		}
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
		// DX P2（2026-10-11）：未知方法 cli 预检 rc=4（用法错）——旧锚 1
		// 是 gateway 帧协议内失败码位（shell 会误读编译错同码），翻锚
		{"api 单帧 ok:false", []string{"api", "bogus.method"}, 4},
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
	//（编译错+warning 用例：审阅 P2 补——失败路径 type_warnings 透出〔gateway
	// serve_compile typeck-error 分支〕；scanf 用例：审阅 P3 补——--corpus 30
	// 字典序不含 scanf，批一段一修的 headless 分叉族无 CI 回归锚）
	warnC := filepath.Join(tmpDir, "warn_case.c")
	// 病 85 修（2026-10-16）：旧 fixture 实产出 2E+0W（用例名「类型警告」名实
	// 不符）——补 double→int 窄化（W3053）成真 E+W 混合，失败路径的 warning
	// 行渲染自此有双臂对拍锚（#129 分立后诊断走 stderr——runOut 合并口径）
	os.WriteFile(warnC, []byte("int main(){ int *p; char *c = p; int y = c; double d = 3.14; int z = d; return y + z; }\n"), 0o644)
	for _, c := range []struct {
		name string
		file string
	}{
		{"普通用例", plainC},
		{"trap 用例", trapC},
		{"quote-include 双文件", incC},
		{"编译错+类型警告（失败路径诊断）", warnC},
		{"scanf EOF（headless 语义）", filepath.Join(repoRoot, "corpus", "baseline", "scanf_return_value.c")},
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
		// 审阅 P1-②（2026-10-15）：js 臂进语义对拍面——此前只在前置产物
		// 检查出现（grep 7 处无一对拍），分派表缺 7 子命令零防线
		jsOut, jsRc := runOut(nodeBin, jsEntry, "run", relPath)
		if jsRc != natRc {
			fatalf("B[三臂对拍] %s: rc 不一致 js=%d native=%d", c.name, jsRc, natRc)
		}
		jsOut = stripBackendLine(jsOut)
		if jsOut != natOut {
			fatalf("B[三臂对拍] %s: js 与 native 不同形\n--- js ---\n%s\n--- native ---\n%s", c.name, jsOut, natOut)
		}
		fmt.Printf("ok  B[三臂对拍] %s（rc=%d 同形）\n", c.name, wasmRc)
	}

	// B 组附 2：api help 三态双臂对拍（#67，2026-10-11）——离线可发现性
	// 出口的双形锁：数据 = 生成器双产物（native api_help_gen.mbt / wasm
	// api_help.json，gen_api_help -check 幂等），此处锁「双臂查表打印
	// 逐字节同形」+ 三态 rc（0 清单 / 0 详情 / 4 未知）+ 内容锚（清单含
	// 方法计数行、详情含 #68 expected 形状——形状漂移双闸之一）。
	{
		for _, c := range []struct {
			name   string
			args   []string
			wantRc int
			needle string
		}{
			{"api help 清单", []string{"api", "help"}, 0, "api 方法清单（28）"},
			{"api help compile 详情", []string{"api", "help", "compile"}, 0, "params: files:[{filename?,source}] | source:string[,filename:string]"},
			{"api help 未知方法", []string{"api", "help", "no.such"}, 4, "用法错: 未知方法 'no.such'"},
		} {
			wOut, wRc := runOut(nodeBin, append([]string{shell}, c.args...)...)
			nOut, nRc := runOut(nativeExe, c.args...)
			if wRc != c.wantRc || nRc != c.wantRc {
				fatalf("B[api help] %s: rc 期望 %d，实得 wasm=%d native=%d", c.name, c.wantRc, wRc, nRc)
			}
			wOut, nOut = stripBackendLine(wOut), stripBackendLine(nOut)
			if wOut != nOut {
				fatalf("B[api help] %s: 双臂不同形\n--- wasm ---\n%s\n--- native ---\n%s", c.name, wOut, nOut)
			}
			if !strings.Contains(wOut, c.needle) {
				fatalf("B[api help] %s: 内容锚缺失（期望含 %q）\n%s", c.name, c.needle, wOut)
			}
			fmt.Printf("ok  B[api help] %s（rc=%d 同形+内容锚）\n", c.name, c.wantRc)
		}
	}

	// B 组附 1：note 去重语义锚（审阅 P3-1，2026-10-07）——note 通道语义
	// 不在 vm_diff/clang_direct 比对面（vm_diff 只比 stdout/rc/映像，壳把
	// note 写成 // NOTE 行被提取器剥掉），apply_reply 全量同文本去重此前
	// 零闸。malloc(0) 连续三次调用只产一条教学附注（批五第一片）；
	// 双臂同形 + 期望计数双锚。
	dupC := filepath.Join(tmpDir, "malloc0_dup.c")
	os.WriteFile(dupC, []byte("#include <stdlib.h>\nint main(){ void*p; p=malloc(0); p=malloc(0); p=malloc(0); return p==0; }\n"), 0o644)
	relDup, _ := filepath.Rel(repoRoot, dupC)
	relDup = filepath.ToSlash(relDup)
	wDup, rcDup := runOut(nodeBin, shell, "run", relDup)
	nDup, rcNat := runOut(nativeExe, "run", relDup)
	if rcDup != rcNat || stripBackendLine(wDup) != stripBackendLine(nDup) {
		fatalf("B[双臂对拍] malloc(0)×3: 双臂不同形\n--- wasm ---\n%s\n--- native ---\n%s", wDup, nDup)
	}
	if c := strings.Count(stripBackendLine(wDup), "[warning] malloc(0)"); c != 1 {
		fatalf("B[note 去重语义] malloc(0)×3 期望恰 1 条教学附注，实得 %d 条——apply_reply 全量同文本去重回归（批五第一片）", c)
	}
	fmt.Println("ok  B[note 去重语义] malloc(0)×3 恰 1 条附注（双臂同形）")

	// B 组附：1MB 映像双臂对拍（--dump-memory——memory.dump 帧链路，
	// #49 批二段二）：双臂各落盘一份逐字节比（cmp 语义；与 vm_diff 第三联
	// 同口径——同字节则 wasm 臂映像联齐备）
	{
		wasmDump := filepath.Join(tmpDir, "dump_wasm.bin")
		natDump := filepath.Join(tmpDir, "dump_native.bin")
		os.Remove(wasmDump)
		os.Remove(natDump)
		_, wrc := runOut(nodeBin, shell, "run", "corpus/baseline/bubble_sort.c", "--dump-memory", filepath.ToSlash(wasmDump))
		_, nrc := runOut(nativeExe, "run", "corpus/baseline/bubble_sort.c", "--dump-memory", filepath.ToSlash(natDump))
		if wrc != 0 || nrc != 0 {
			fatalf("B[映像对拍] rc 异常 wasm=%d native=%d", wrc, nrc)
		} else if wb, err1 := os.ReadFile(wasmDump); err1 != nil {
			fatalf("B[映像对拍] dump 文件读取失败 wasm=%v", err1)
		} else if nb, err2 := os.ReadFile(natDump); err2 != nil {
			fatalf("B[映像对拍] dump 文件读取失败 native=%v", err2)
		} else if len(wb) != 1024*1024 {
			fatalf("B[映像对拍] wasm dump 尺寸 %d ≠ 1MB", len(wb))
		} else if !bytes.Equal(wb, nb) {
			fatalf("B[映像对拍] 1MB 映像逐字节不一致（首差 offset=%d）", firstDiff(wb, nb))
		} else {
			fmt.Println("ok  B[映像对拍] 1MB dump 双臂逐字节一致（memory.dump 帧）")
		}
	}

	// B 组扩面：语料级双臂对拍（--corpus N；#49 批二）——同判定口径
	//（rc + 剥 backend 行后逐字节）。稳定序 = 文件名字典序取前 N。
	if *corpusN > 0 {
		entries, err := os.ReadDir(filepath.Join(repoRoot, "corpus", "baseline"))
		if err != nil {
			fatalf("B[语料对拍] corpus/baseline 不可读: %v", err)
		}
		var names []string
		for _, e := range entries {
			if !e.IsDir() && strings.HasSuffix(e.Name(), ".c") {
				names = append(names, e.Name())
			}
		}
		sort.Strings(names)
		if len(names) == 0 {
			fatalf("B[语料对拍] corpus/baseline 零 .c 用例——目录形态异常")
		}
		if *corpusN > len(names) {
			*corpusN = len(names)
		}
		pass := 0
		for _, name := range names[:*corpusN] {
			rel := "corpus/baseline/" + name
			wasmOut, wasmRc := runOut(nodeBin, shell, "run", rel)
			natOut, natRc := runOut(nativeExe, "run", rel)
			if wasmRc != natRc {
				fatalf("B[语料对拍] %s: rc 不一致 wasm=%d native=%d", name, wasmRc, natRc)
			}
			wasmOut, natOut = stripBackendLine(wasmOut), stripBackendLine(natOut)
			if wasmOut != natOut {
				fatalf("B[语料对拍] %s: 输出不一致\n--- wasm ---\n%s\n--- native ---\n%s", name, wasmOut, natOut)
			}
			// js 臂语料级连坐（P2，2026-10-15 用户审阅提醒）：原 --corpus N
			// 只比 wasm↔native，js 臂仅内置 fixture 三例——缺省臂反而语料
			// 零覆盖（曾致 js 臂分派表缺 7 子命令的盲区靠内置例侥幸不红）。
			// 判定口径同上：rc 等值 + stripBackendLine 后同形。
			jsOut, jsRc := runOut(nodeBin, jsEntry, "run", rel)
			if jsRc != natRc {
				fatalf("B[语料对拍] %s: rc 不一致 js=%d native=%d", name, jsRc, natRc)
			}
			jsOut = stripBackendLine(jsOut)
			if jsOut != natOut {
				fatalf("B[语料对拍] %s: js 与 native 不同形\n--- js ---\n%s\n--- native ---\n%s", name, jsOut, natOut)
			}
			pass++
		}
		if failures == 0 {
			fmt.Printf("ok  B[语料对拍] 前 %d 例（字典序）三臂同形（wasm+js+native）\n", pass)
		}
	}

	// ── C 组：launcher 语义（fatalf 不终止——ok 行须 else 门控，失败时
	// 不打印自相矛盾的「ok」）─────────────────────────────────────
	shLauncher := filepath.Join(repoRoot, "scripts", "bin", "vitro")
	outL, rcL := runOut("sh", shLauncher, "run", "corpus/baseline/array_sum_loop.c")
	if rcL != 0 {
		fatalf("C[launcher sh] 默认臂 rc=%d", rcL)
	} else if !strings.Contains(outL, "backend=js") {
		fatalf("C[launcher sh] 默认臂缺 backend=js 标注（三后端批 2026-10-15 缺省臂=js）：%s", outL)
	} else {
		fmt.Println("ok  C[launcher sh] 默认臂 backend 标注")
	}

	outN, rcN := runOut("sh", shLauncher, "--backend", "native", "run", "corpus/baseline/array_sum_loop.c")
	if rcN != 0 {
		fatalf("C[launcher sh] --backend native rc=%d", rcN)
	} else if !strings.Contains(outN, "backend=native") || !strings.Contains(outN, "程序运行完成") {
		fatalf("C[launcher sh] --backend native 输出异常：%s", outN)
	} else {
		fmt.Println("ok  C[launcher sh] --backend native 转发")
	}

	outW, rcW := runOut("sh", shLauncher, "--backend", "wasm", "run", "corpus/baseline/array_sum_loop.c")
	if rcW != 0 {
		fatalf("C[launcher sh] --backend wasm rc=%d", rcW)
	} else if !strings.Contains(outW, "backend=wasm") {
		fatalf("C[launcher sh] --backend wasm 标注缺失：%s", outW)
	} else {
		fmt.Println("ok  C[launcher sh] --backend wasm 转发")
	}

	// cmd 形态仅 Windows 断言（CI 双 runner 覆盖；sh 版全平台）
	if runtime.GOOS == "windows" {
		outC, rcC := runOut("cmd.exe", "/c", filepath.Join(repoRoot, "scripts", "bin", "vitro.cmd"), "run", "corpus/baseline/array_sum_loop.c")
		if rcC != 0 {
			fatalf("C[launcher cmd] 默认臂 rc=%d：%s", rcC, outC)
		} else if !strings.Contains(outC, "backend=js") {
			fatalf("C[launcher cmd] 默认臂缺 backend=js 标注：%s", outC)
		} else {
			fmt.Println("ok  C[launcher cmd] 默认臂（Windows）")
		}
	}

	if failures > 0 {
		fmt.Printf("vitro_cli_smoke: %d 失败\n", failures)
		os.Exit(1)
	}
	// ── G 组：#129 通道分立（2026-10-16 用户拍板，推翻 #69 混流裁定）──
	// 文本模式 stdout 只承载被测程序输出（无 // 标记行——字节精确）；
	// 诊断行/note/EXIT 标记行/用法错走 stderr（gcc/clang 先例）。
	// J9：本断言先于实现存在——改前三臂 stdout 含标记行即红（证红留痕）。
	{
		hintC := filepath.Join(repoRoot, "corpus", "baseline", "bsearch_basic.c")
		type gArm struct {
			name string
			argv []string
		}
		for _, g := range []gArm{
			{"wasm", []string{nodeBin, wasmGlue}},
			{"js", []string{nodeBin, jsEntry}},
			{"native", nil},
		} {
			argv := append([]string{}, g.argv...)
			if g.name == "native" {
				argv = []string{nativeExe}
			}
			argv = append(argv, "run", hintC)
			cmd := exec.Command(argv[0], argv[1:]...)
			cmd.Dir = repoRoot
			var so, se bytes.Buffer
			cmd.Stdout = &so
			cmd.Stderr = &se
			if err := cmd.Run(); err == nil {
				// stdout：不得有任何 "// " 前缀行
				for _, line := range strings.Split(so.String(), "\n") {
					if strings.HasPrefix(line, "// ") {
						fatalf("G[#129 通道分立] %s: stdout 含标记行 %q（#69 翻案后 stdout 只承载程序输出）", g.name, line)
					}
				}
				// stderr：必含 hint 诊断行与 note 行（bsearch_basic 带 H3057 + 完成附注）
				if !strings.Contains(se.String(), "// COMPILE-HINT") || !strings.Contains(se.String(), "// NOTE ") {
					seHead := se.String()
					if len(seHead) > 200 {
						seHead = seHead[:200]
					}
					fatalf("G[#129 通道分立] %s: stderr 缺诊断/note 标记行（应走 stderr）——stderr=%q", g.name, seHead)
				}
				fmt.Printf("ok  G[#129 通道分立] %s 臂：stdout 纯程序输出 + stderr 标记行\n", g.name)
			} else {
				fatalf("G[#129 通道分立] %s: 执行失败 %v", g.name, err)
			}
		}
	}

	// ── D 组：薄壳 include 接线（病 43，#71 第二梯队 2026-10-11）────
	// compile/step 薄壳不経 cmd/vitro——注册下沉 cmd/lib/cli 后，薄壳
	// quote-include 必须过（修复前恒 E1021；防线此前三层全漏——薄壳不在
	// 任何对拍面，round6 教训）。exe 来自全量 release 构建（CI 140 行）。
	thinCompile := filepath.Join(repoRoot, "moonbit", "_build", "native", "release", "build", "cmd", "compile", "compile.exe")
	thinStep := filepath.Join(repoRoot, "moonbit", "_build", "native", "release", "build", "cmd", "step", "step.exe")
	if _, err := os.Stat(thinCompile); err == nil {
		outTC, rcTC := runOut(thinCompile, incC)
		if rcTC != 0 || strings.Contains(outTC, "E1021") {
			fatalf("D[薄壳 compile] quote-include 断链 rc=%d：%s", rcTC, outTC)
		} else {
			fmt.Println("ok  D[薄壳 compile] quote-include 接线")
		}
	} else {
		fmt.Println("skip D[薄壳 compile]（release exe 未构建——本地非全量态）")
	}
	if _, err := os.Stat(thinStep); err == nil {
		outTS, rcTS := runOut(thinStep, incC)
		if rcTS != 0 || strings.Contains(outTS, "E1021") {
			fatalf("D[薄壳 step] quote-include 断链 rc=%d：%s", rcTS, outTS)
		} else {
			fmt.Println("ok  D[薄壳 step] quote-include 接线")
		}
	} else {
		fmt.Println("skip D[薄壳 step]（release exe 未构建——本地非全量态）")
	}

	fmt.Println("vitro_cli_smoke: 全绿（rc 契约 + 双臂同形对拍 + launcher + 薄壳 include）")
}
