package main

// CLI 壳的 J9 锚（2026-09-22 补）：--check 分支与退出码此前**无仓内锚**——
// 原 TestCheckBytes 名不副实（函数体只做幂等断言、与 TestIdempotent 重复，
// 从未调用 CLI、未断言退出码）。本文件直测 run()（显式出入参），逐条锚
// 2026-09-22 实测行为。
//
// 分工：归一**性质**锚在被测单源 scripts/internal/canonicalize/canonicalize_test.go；
// 本文件只锚 CLI **契约**（参数解析 / 退出码 / stdout 与 stderr 去向）。

import (
	"bytes"
	"strings"
	"testing"
)

func invoke(args []string, stdin string) (int, string, string) {
	var out, errb bytes.Buffer
	code := run(args, strings.NewReader(stdin), &out, &errb)
	return code, out.String(), errb.String()
}

const canonicalJSON = "{\n  \"a\": 2\n}\n"

// 归一路径（无 --check）：规范形写 stdout、退出 0、stderr 静默。
func TestRunNormalizeWritesCanonicalStdout(t *testing.T) {
	code, out, errOut := invoke(nil, `{"a":2}`)
	if code != 0 {
		t.Fatalf("归一路径应退出 0，得 %d", code)
	}
	if out != canonicalJSON {
		t.Fatalf("stdout 应为规范形\n得 %q\n期 %q", out, canonicalJSON)
	}
	if errOut != "" {
		t.Fatalf("归一路径 stderr 应静默，得 %q", errOut)
	}
}

// J9：--check 规范形 → exit 0（此前无锚的那条分支）。
func TestCheckCanonicalExitsZero(t *testing.T) {
	code, out, errOut := invoke([]string{"--check"}, canonicalJSON)
	if code != 0 {
		t.Fatalf("规范形 --check 应退出 0，得 %d（stderr=%q）", code, errOut)
	}
	if out != "" {
		t.Fatalf("--check 不应写 stdout，得 %q", out)
	}
}

// --check 的**首尾空白容忍**（2026-09-22 实测行为，非推测）：比较前双侧
// TrimSpace，故缺尾随换行 / 前导换行 / 前后空格均 exit 0——判定面只有
// 键序 / 缩进 / 转义三项。原文案宣称"尾随换行不匹配"，与实况不符，已随本批修正。
func TestCheckToleratesSurroundingWhitespace(t *testing.T) {
	for _, in := range []string{
		"{\n  \"a\": 2\n}",   // 缺尾随换行
		"\n{\n  \"a\": 2\n}\n", // 前导换行
		"  {\n  \"a\": 2\n}  ", // 前后空格
	} {
		if code, _, errOut := invoke([]string{"--check"}, in); code != 0 {
			t.Fatalf("首尾空白应容忍，输入 %q 得退出 %d（stderr=%q）", in, code, errOut)
		}
	}
}

// J9：--check 乱序键 → exit 1（键序面）。
func TestCheckUnorderedKeysExitsOne(t *testing.T) {
	if code, _, errOut := invoke([]string{"--check"}, `{"b":1,"a":2}`); code != 1 {
		t.Fatalf("乱序键应退出 1，得 %d（stderr=%q）", code, errOut)
	}
}

// J9：--check 缩进不符 → exit 1（缩进面）。
func TestCheckIndentMismatchExitsOne(t *testing.T) {
	if code, _, _ := invoke([]string{"--check"}, "{\n    \"a\": 2\n}\n"); code != 1 {
		t.Fatalf("4 空格缩进应退出 1，得 %d", code)
	}
}

// J9：--check 紧凑单行 → exit 1（缩进 + 换行面）。
func TestCheckCompactOneLineExitsOne(t *testing.T) {
	if code, _, _ := invoke([]string{"--check"}, `{"a":2}`); code != 1 {
		t.Fatalf("紧凑单行应退出 1，得 %d", code)
	}
}

// J9：--check 非法 JSON → exit 1 且 stdout 零字节（拒绝输出，不猜不兜底）。
func TestCheckInvalidJSONExitsOneEmptyStdout(t *testing.T) {
	for _, bad := range []string{`{"a":}`, `not json`} {
		code, out, errOut := invoke([]string{"--check"}, bad)
		if code != 1 {
			t.Fatalf("非法输入 %q 应退出 1，得 %d", bad, code)
		}
		if out != "" {
			t.Fatalf("非法输入 %q 不得写 stdout，得 %q", bad, out)
		}
		if errOut == "" {
			t.Fatalf("非法输入 %q 应给 stderr 说明", bad)
		}
	}
}

// J9：--check 双 JSON 值 → exit 1（锚数据必须单值）。
func TestCheckMultipleValuesExitsOne(t *testing.T) {
	if code, _, _ := invoke([]string{"--check"}, `{"a":1}{"b":2}`); code != 1 {
		t.Fatalf("双 JSON 值应退出 1，得 %d", code)
	}
}

// 归一失败（无 --check）：同样 exit 1 且零 stdout——拒绝路径与 --check 无关。
func TestRunInvalidJSONExitsOneEmptyStdout(t *testing.T) {
	code, out, _ := invoke(nil, `{"a":}`)
	if code != 1 || out != "" {
		t.Fatalf("非法 JSON 应 exit 1 且零输出，得 exit=%d out=%q", code, out)
	}
}

// 未知参数 → exit 2（与原全局 flag.ExitOnError 口径对齐）。
func TestUnknownFlagExitsTwo(t *testing.T) {
	if code, _, _ := invoke([]string{"--no-such-flag"}, canonicalJSON); code != 2 {
		t.Fatalf("未知参数应退出 2，得 %d", code)
	}
}
