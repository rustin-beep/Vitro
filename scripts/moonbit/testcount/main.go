// testcount：MoonBit 测试数三向对账闸（v2，五轮审阅修正）。
//
// v1 缺陷（用户注入 400/400/400 复现）：真值读 reports/facts.json——该制品
// 默认 status=cached，与声明比对只是**复述**（文档与 facts 一起错的场景不红，
// 恰是四轮连坐失败的现场形态）；且 reports/ 不入 git，干净 clone 直接读失败。
//
// v2 真值 = **本闸自跑 `moon test` 解析 Total tests**（每跑一次全量测试，
// 成本与 mbti_sync 自跑 moon info 同量级）。facts 制品降为参考信息打印。
//
// 对账三方：moonbit/README.md ↔ moonbit/README.mbt.md ↔ moon test 实跑值。
// J9 三层（用户流程建议 #2）：①篡改声明 ±1 红；②原缺陷场景（三方一起旧值，
// 如 facts cached 400 + 文档 400）——v2 下真值来自实跑 406，文档 400 必红；
// ③已接 CI（.github/workflows/ci.yml core job）。
//
//	go run ./scripts/moonbit/testcount
package main

import (
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
)

var testCountRe = regexp.MustCompile(`#\s*(\d+)\s*测试（`)

func readDeclared(path string) (int, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return 0, fmt.Errorf("读 %s: %w", path, err)
	}
	matches := testCountRe.FindAllStringSubmatch(string(data), -1)
	if len(matches) == 0 {
		return 0, fmt.Errorf("%s 未找到「# N 测试（」声明行", path)
	}
	if len(matches) > 1 {
		return 0, fmt.Errorf("%s 声明行不唯一（%d 处）", path, len(matches))
	}
	n, err := strconv.Atoi(matches[0][1])
	if err != nil {
		return 0, fmt.Errorf("%s 声明数字解析失败: %w", path, err)
	}
	return n, nil
}

// runMoonTest：实跑 moon test 取真值（cwd=moonbit；解析最后一行 Total tests）。
func runMoonTest() (int, error) {
	cmd := exec.Command("moon", "test")
	cmd.Dir = "moonbit"
	out, err := cmd.CombinedOutput()
	if err != nil {
		return 0, fmt.Errorf("moon test 失败: %w\n%s", err, tailN(string(out), 20))
	}
	re := regexp.MustCompile(`Total tests:\s*(\d+),\s*passed:\s*(\d+),\s*failed:\s*(\d+)`)
	ms := re.FindAllStringSubmatch(string(out), -1)
	if len(ms) == 0 {
		return 0, fmt.Errorf("moon test 输出未找到 Total tests 行\n%s", tailN(string(out), 10))
	}
	m := ms[len(ms)-1]
	total, _ := strconv.Atoi(m[1])
	failed, _ := strconv.Atoi(m[3])
	if failed != 0 {
		return 0, fmt.Errorf("moon test 本身有失败（%d failed）——先修测试再对账", failed)
	}
	return total, nil
}

func tailN(s string, n int) string {
	lines := strings.Split(strings.TrimRight(s, "\n"), "\n")
	if len(lines) > n {
		lines = lines[len(lines)-n:]
	}
	return strings.Join(lines, "\n")
}

func main() {
	truth, err := runMoonTest()
	if err != nil {
		fmt.Fprintln(os.Stderr, "testcount:", err)
		os.Exit(1)
	}
	fail := false
	for _, p := range []string{"moonbit/README.md", "moonbit/README.mbt.md"} {
		n, err := readDeclared(p)
		if err != nil {
			fmt.Fprintln(os.Stderr, "testcount:", err)
			os.Exit(1)
		}
		if n != truth {
			fmt.Fprintf(os.Stderr, "testcount: %s 声明 %d != moon test 实跑 %d\n", p, n, truth)
			fail = true
		}
	}
	// 参考信息：facts 制品的 as_of（不参与判定——v1 的复述缺陷来源）
	if data, err := os.ReadFile("reports/facts.json"); err == nil {
		if i := strings.Index(string(data), "\"moonbit_test_passed\""); i >= 0 {
			seg := string(data[i : i+300])
			if j := strings.Index(seg, "\"as_of\""); j >= 0 {
				fmt.Printf("testcount: 参考 facts.as_of %s（制品不参与判定）\n", strings.TrimSpace(strings.SplitN(seg[j:], "\n", 2)[0]))
			}
		}
	}
	if fail {
		fmt.Fprintln(os.Stderr, "testcount: 对账不符——文档声明须等于 moon test 实跑真值（同步后提交）")
		os.Exit(1)
	}
	fmt.Printf("testcount: PASS——两文档声明与 moon test 实跑真值一致（%d）\n", truth)
}
