package jmemit

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// KeyOrderOf：通用容器键序抽取（栈式深度计数——vm_diff 版的库化）。
func KeyOrderOf(raw []byte, container string) []string {
	s := string(raw)
	marker := `"` + container + `": {`
	i := strings.Index(s, marker)
	if i < 0 {
		return nil
	}
	rest := s[i+len(marker):]
	ord := []string{}
	depth := 1
	inStr := false
	esc := false
	for j := 0; j < len(rest); j++ {
		c := rest[j]
		if inStr {
			if esc {
				esc = false
			} else if c == '\\' {
				esc = true
			} else if c == '"' {
				inStr = false
			}
			continue
		}
		switch c {
		case '"':
			inStr = true
		case '{':
			if depth == 1 {
				lineStart := strings.LastIndexByte(rest[:j], '\n') + 1
				head := strings.TrimSpace(rest[lineStart:j])
				if strings.HasPrefix(head, "\"") && strings.HasSuffix(head, ":") {
					ord = append(ord, strings.Trim(head[:len(head)-1], "\""))
				}
			}
			depth++
		case '}':
			depth--
			if depth == 0 {
				return ord
			}
		}
	}
	return ord
}

// Exe：jsonmbt CLI 路径（jsonmbt 仓 debug 构建——试毒模式滚动消费）。
const Exe = "../jsonmbt/_build/native/release/build/cmd/jsonmbt/jsonmbt.exe"

// EmitAndVerify：平面节形态的通用「emit + build round-trip 对拍」。
// docJSON：刚写回的 .json 字节；mbtPath：.mbt 真源落点；buildFn：把
// 再生 .json 解回调用方结构后做语义对拍（返回差异条数）。
// exe 缺失时告警跳过 round-trip（CI static gate 兜底），emit 本身不跳。
func EmitAndVerify(mbtPath string, docJSON []byte, emit func(ordOf map[string][]string) string, compare func(regen []byte) int) {
	// 各容器键序
	ordOf := map[string][]string{}
	for _, c := range containersOf(docJSON) {
		ordOf[c] = KeyOrderOf(docJSON, c)
	}
	if err := WriteFile(mbtPath, emit(ordOf)); err != nil {
		fmt.Fprintf(os.Stderr, "emit: 写 %s 失败: %v\n", mbtPath, err)
		os.Exit(1)
	}
	// fmt-stable（jsonmbt#10 同款 stub：spawn `moon fmt <单文件>`——单文件
	// 调用无 workspace 副作用面，emitter 紧凑形态归一为 fmt-clean 入仓形态，
	// 下轮 emit 重产仍会被本步归一——循环闭合）。moon 缺位时静默跳过
	//（fmt 失败不挡 round-trip——它不是语义闸）。
	if out, err := exec.Command("moon", "fmt", mbtPath).CombinedOutput(); err != nil {
		fmt.Fprintf(os.Stderr, "emit: 警告——moon fmt 单文件失败（产物保持 emitter 原形态）: %v\n%s\n", err, out)
	}
	if _, err := os.Stat(Exe); err != nil {
		fmt.Fprintf(os.Stderr, "emit: 警告——jsonmbt exe 缺失，round-trip 跳过（CI static gate 兜底）\n")
		return
	}
	regenPath := mbtPath + ".regen.tmp"
	out, err := exec.Command(Exe, "build", mbtPath, "-o", regenPath).CombinedOutput()
	if err != nil {
		fmt.Fprintf(os.Stderr, "emit: jsonmbt build 失败: %v\n%s\n", err, out)
		os.Exit(1)
	}
	regen, err := os.ReadFile(regenPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "emit: 读再生件失败: %v\n", err)
		os.Exit(1)
	}
	if bad := compare(regen); bad > 0 {
		fmt.Fprintf(os.Stderr, "emit: round-trip 语义漂移 %d 处——真源与 .json 不同步，拒绝入账\n", bad)
		os.Exit(1)
	}
	os.Remove(regenPath)
	fmt.Printf("emit: %s 真源 → round-trip 对拍绿\n", mbtPath)
}

// containersOf：抽 JSON 顶层里所有「map 容器」的键名（round-trip 对拍用
// 的序抽取目标——flat digest 的容器通常是 modes/corpora + 各节）。
func containersOf(raw []byte) []string {
	var probe map[string]json.RawMessage
	if err := json.Unmarshal(raw, &probe); err != nil {
		return nil
	}
	names := []string{}
	for k, v := range probe {
		var m map[string]json.RawMessage
		if json.Unmarshal(v, &m) == nil && len(m) > 0 {
			// 再看一层：值是对象且对象里还有对象容器的，把子容器也收
			names = append(names, k)
			for k2, v2 := range m {
				var m2 map[string]json.RawMessage
				if json.Unmarshal(v2, &m2) == nil && len(m2) > 0 {
					names = append(names, k2)
				}
			}
		}
	}
	return names
}

var _ = json.Marshal // 保持 import

// KeyOrderOfScalars：KeyOrderOf 的标量值限定版——只收「"key": "string"」
// 形态的直接键（digest 的 sources/hashes 层；嵌套对象键被跳过）。
// 动机：节名与内层 Map 名撞形态时（legal_deep 节 sources 恰 2 键 = 节键数），
// 长度校验不可分——直接限定值形态才算命中。
func KeyOrderOfScalars(raw []byte, container string) []string {
	s := string(raw)
	marker := `"` + container + `": {`
	i := strings.Index(s, marker)
	if i < 0 {
		return nil
	}
	rest := s[i+len(marker):]
	ord := []string{}
	depth := 1
	inStr := false
	esc := false
	for j := 0; j < len(rest); j++ {
		c := rest[j]
		if inStr {
			if esc {
				esc = false
			} else if c == 92 { // 92 = '\'（byte 字面量避开转义坑）
				esc = true
			} else if c == '"' {
				inStr = false
			}
			continue
		}
		switch c {
		case '"':
			inStr = true
		case '{':
			depth++
		case '}':
			depth--
			if depth == 0 {
				return ord
			}
		case ':':
			// depth==1 的冒号后看值首字符：`"` = 标量字符串 → 回收键名
			if depth == 1 {
				k := j + 1
				for k < len(rest) && (rest[k] == ' ') {
					k++
				}
				if k < len(rest) && rest[k] == '"' {
					lineStart := strings.LastIndexByte(rest[:j], '\n') + 1
					head := strings.TrimSpace(rest[lineStart:j])
					head = strings.TrimSuffix(head, ":")
					ord = append(ord, strings.Trim(head, "\""))
				}
			}
		}
	}
	return ord
}
