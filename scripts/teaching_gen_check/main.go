// teaching_gen_check —— 教学资产生成闸（#125 批 A，2026-10-15）。
//
// 驱动 moonbit/teaching/tools/content_parser.c（**vitro 编译运行——C 解析器
// 自举**，三 schema 经 `--` argv 选模式），产物经 moon fmt 后与入库
// `moonbit/teaching/assets/*_gen.mbt` 逐字节比对（生成器契约：产物形态以
// fmt 为准；builtin_notes 实测 fmt 改写数组换行 58B，故 fmt 必须在环内）。
//
// 用法（仓库根）：
//
//	go run ./scripts/teaching_gen_check                 # -check 语义（CI 闸）
//	go run ./scripts/teaching_gen_check -write          # 再生（真源变更后）
//	go run ./scripts/teaching_gen_check -backend native # 换臂（缺省 js；
//	                                                    # 四臂对拍由批 A 验收
//	                                                    # driver 离线覆盖）
//
// 语义要点（实测记档 2026-10-15）：
//   - 程序返回值在 **note 帧**（"程序运行完成，返回值：N"），CLI 自身恒
//     rc=0——必须解析 note 帧，否则失败静默假绿（#129 裸跑 stdout 污染另案）。
//   - --json stdout 帧的 delta 是 **Latin-1 折叠字节**（1 字符=1 字节），
//     重建 = 逐码点折回字节；>0xFF 码点按 UTF-8 编码（demo run.ts 同款）。
//   - fmt 走包内临时件：写 assets/_gencheck_tmp.mbt → moon fmt → 比对 →
//     删除（check 不留副作用；-write 直接落正式路径后再 fmt）。
package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
)

var backend = flag.String("backend", "js", "vitro 臂：js（缺省）| native | wasm")
var writeMode = flag.Bool("write", false, "再生模式：产物落正式路径（真源变更后用）")

type spec struct {
	mode     string // parser argv[1]
	src      string // 真源（content/ 下）
	product  string // 产物（assets/ 下）
	expected int    // 基线条数（解析器自校，此处仅报告）
}

var specs = []spec{
	{"trap", "trap_messages.md", "trap_messages_gen.mbt", 45},
	{"suggestions", "suggestions.md", "suggestions_gen.mbt", 43},
	{"builtin_notes", "builtin_notes.md", "builtin_notes_gen.mbt", 12},
}

var reNoteRC = regexp.MustCompile(`程序运行完成，返回值：(\d+)`)

func die(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "[teaching_gen_check] FAIL: "+format+"\n", args...)
	os.Exit(1)
}

// runParser 跑 vitro（--json）→ 帧重建出程序 stdout 字节。
func runParser(s spec) []byte {
	cmd := exec.Command("bash", "scripts/bin/vitro")
	if *backend != "js" {
		cmd.Args = append(cmd.Args, "--backend", *backend)
	}
	cmd.Args = append(cmd.Args, "run", "--json", "moonbit/teaching/tools/content_parser.c",
		"-i", "moonbit/teaching/content/"+s.src, "--", s.mode)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		die("vitro 启动失败（%s 臂）: %v\n%s", *backend, err, stderr.String())
	}
	progRC := 0
	if m := reNoteRC.FindSubmatch(stdout.Bytes()); m != nil {
		fmt.Sscanf(string(m[1]), "%d", &progRC)
	}
	if progRC != 0 {
		die("解析器程序返回值 %d（%s）\nstderr: %s", progRC, s.mode, stderr.String())
	}
	// 帧重建：stdout 型 delta 按 Latin-1 折叠折回字节；>0xFF 码点按 UTF-8。
	var out bytes.Buffer
	for _, line := range bytes.Split(stdout.Bytes(), []byte("\n")) {
		if !bytes.Contains(line, []byte(`"delta"`)) {
			continue
		}
		var frame struct {
			Type  string `json:"type"`
			Frame struct {
				Result struct {
					Delta string `json:"delta"`
				} `json:"result"`
			} `json:"frame"`
		}
		if json.Unmarshal(line, &frame) != nil || frame.Type != "stdout" {
			continue
		}
		for _, ch := range frame.Frame.Result.Delta {
			if ch <= 0xFF {
				out.WriteByte(byte(ch))
			} else {
				out.WriteString(string(ch))
			}
		}
	}
	return out.Bytes()
}

// runMoonFmt 包内 fmt（cwd=moonbit/，workspace 命令）。
func runMoonFmt(rel string) {
	cmd := exec.Command("moon", "fmt", rel)
	cmd.Dir = "moonbit"
	var out bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &out
	if err := cmd.Run(); err != nil {
		die("moon fmt 失败（moon 须在 PATH）: %v\n%s", err, out.String())
	}
}

func main() {
	flag.Parse()
	tmpRel := "teaching/assets/_gencheck_tmp.mbt"
	tmpAbs := filepath.Join("moonbit", filepath.FromSlash(tmpRel))

	var drifted []string
	for _, s := range specs {
		out := runParser(s)
		if *writeMode {
			real := filepath.Join("moonbit", "teaching", "assets", s.product)
			if err := os.WriteFile(real, out, 0o644); err != nil {
				die("写产物失败 %s: %v", real, err)
			}
			runMoonFmt("teaching/assets/" + s.product)
			fmt.Printf("[teaching_gen_check] 再生 %s（fmt 后 %d B）\n", s.product, len(out))
			continue
		}
		// check：包内临时件 → fmt → 与入库产物比对 → 删临时件
		if err := os.WriteFile(tmpAbs, out, 0o644); err != nil {
			die("写临时件失败: %v", err)
		}
		runMoonFmt(tmpRel)
		after, err := os.ReadFile(tmpAbs)
		if err != nil {
			die("回读临时件失败: %v", err)
		}
		os.Remove(tmpAbs)
		committed, err := os.ReadFile(filepath.Join("moonbit", "teaching", "assets", s.product))
		if err != nil {
			die("读入库产物失败 %s: %v（先 -write 再生）", s.product, err)
		}
		norm := func(b []byte) []byte { return bytes.ReplaceAll(b, []byte("\r\n"), []byte("\n")) }
		if !bytes.Equal(norm(after), norm(committed)) {
			drifted = append(drifted, s.product)
			fmt.Fprintf(os.Stderr, "[teaching_gen_check] ✗ %s 漂移（raw %d B / fmt 后 %d B / 入库 %d B）\n",
				s.product, len(out), len(after), len(committed))
		} else {
			fmt.Printf("[teaching_gen_check] ✓ %s 与解析器输出一致（fmt 后 %d B）\n", s.product, len(after))
		}
	}
	if len(drifted) > 0 {
		die("产物漂移 %s——真源已改未再生（go run ./scripts/teaching_gen_check -write）",
			strings.Join(drifted, ", "))
	}
	fmt.Println("[teaching_gen_check] 全部通过：三 schema 产物 ≡ 解析器输出（fmt 后）")
}
