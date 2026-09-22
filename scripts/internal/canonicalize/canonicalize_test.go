package canonicalize

// 归一器的 J9 证红锚（判定面上线前先证明它会红）与归一性质测试。
//
// J9 义务：归一性质（键排序 / 数字保形 / 转义统一 / 幂等 / 非法与双值拒绝）
// 是 E1 锚逐字节比对的可信前提——判定函数坏了的"全绿"比没有门禁更坏。
//
// 位置说明（2026-09-22）：本文件随归一器抽库自 scripts/canonicalize 迁入**被测
// 单源所在包**（此前的形态是"测试在 CLI 包、被测包零测试文件、go test 显示
// no test files"）。CLI 壳自身的 --check 分支与退出码锚见
// scripts/canonicalize/main_test.go；归一性质与 CLI 参数解析分离，两边互不代偿。

import (
	"strings"
	"testing"
)

func canon(t *testing.T, in string) string {
	t.Helper()
	out, err := Bytes([]byte(in))
	if err != nil {
		t.Fatalf("归一失败: %v", err)
	}
	return string(out)
}

// J9：乱序键必须被重排（--check 对乱序输入必红的前提）。
func TestKeySort(t *testing.T) {
	got := canon(t, `{"b":1,"a":2,"c":{"z":true,"y":false}}`)
	want := "{\n  \"a\": 2,\n  \"b\": 1,\n  \"c\": {\n    \"y\": false,\n    \"z\": true\n  }\n}\n"
	if got != want {
		t.Fatalf("键排序：\n得 %q\n期 %q", got, want)
	}
}

// J9：数字形态必须保形（1.0 不得变 1；1e2 不得变 100）。
func TestNumberFormPreserved(t *testing.T) {
	got := canon(t, `{"a":1,"b":1.0,"c":1e2,"d":-0,"big":9007199254740993}`)
	// 键字典序：a, b, big, c, d——d 为末键无尾逗号
	for _, want := range []string{`"a": 1,`, `"b": 1.0,`, `"c": 1e2,`, `"d": -0` + "\n", `"big": 9007199254740993,`} {
		if !strings.Contains(got, want) {
			t.Fatalf("数字保形失败：输出缺 %q\n得 %s", want, got)
		}
	}
}

// J9：字符串转义归一（\u0041 与 A 等价；HTML 字符不被转义）。
func TestEscapeNormalized(t *testing.T) {
	got := canon(t, `{"s":"A","h":"<a&b>"}`)
	if !strings.Contains(got, `"s": "A"`) {
		t.Fatalf("\\u0041 应归一为 A：%s", got)
	}
	if !strings.Contains(got, `"h": "<a&b>"`) {
		t.Fatalf("HTML 转义应关闭（&<> 原样）：%s", got)
	}
}

// 幂等：规范形再归一不变（E1 锚逐字节比对的可信前提）。
func TestIdempotent(t *testing.T) {
	in := `{"z":[3,1,{"k":null}],"a":"中","n":1.50}`
	once := canon(t, in)
	twice := canon(t, once)
	if once != twice {
		t.Fatalf("幂等破坏：\n一 %q\n二 %q", once, twice)
	}
}

// J9：非法 JSON 必须拒绝（fail loud，禁止静默输出空/原样）。
func TestInvalidRejected(t *testing.T) {
	for _, bad := range []string{`{`, `{"a":}`, `not json`, ``, `[1,2,`} {
		if out, err := Bytes([]byte(bad)); err == nil {
			t.Fatalf("非法输入 %q 必须报错，却产出 %q", bad, out)
		}
	}
}

// J9：多 JSON 值拼接必须拒绝（锚数据错误不猜）。
func TestMultipleValuesRejected(t *testing.T) {
	if _, err := Bytes([]byte(`{"a":1}{"b":2}`)); err == nil {
		t.Fatal("双 JSON 值必须拒绝")
	}
}

// 数组顺序保持（排序数组 = 销毁信息）。
func TestArrayOrderPreserved(t *testing.T) {
	got := canon(t, `[3,1,2]`)
	if got != "[\n  3,\n  1,\n  2\n]\n" {
		t.Fatalf("数组顺序必须保持：得 %q", got)
	}
}
