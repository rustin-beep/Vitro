// vm_diff：D 级 diff 驱动（批五号——总计划 §6 D 级锚：stdout + 返回码
// + 1MB 最终内存映像；§7.1 层 1 全量化，2026-09-26 六轮审阅销项批）。
//
// 两侧：
//
//	Rust oracle：native/target/release/vitro_cli.exe run <file.c>
//	MoonBit：    moonbit/_build/native/release/build/cmd/run/run.exe（**预编译
//	            直跑**——moon run 包装层在 Go exec 下 0xffffffff 崩溃，
//	            实测 bash/python 正常、Go 不稳；故 vm_diff 前置要求先
//	            `cd moonbit && moon build --release --target native cmd/run`——
//	            ① **--release 必须带**：默认 debug，脚本读的 release 路径
//	            不会更新（2026-09-26 实测坑）；② moon build 必须在
//	            moonbit/ 下跑，仓库根会 exit 127 "not in a Moon project"）
//
// 新鲜度门禁（2026-09-26 审阅 P1-2 接线；同批批改：mtime 触发 + 构建
// 复核）：启动时校验 runner exe 不旧于 moonbit/ 下任一 .mbt/.mod/.pkg
// 源；落后则**跑一次规范化构建复核**——退出码 0 ⇒ moon 按内容 hash 已
// 保证 exe 内容最新（重链或 no-work），放行；构建失败 ⇒ 红并拒绝给判定。
// 设计动因：moon 的增量按内容 hash（touch/git 换行归一/等价内容再生成
// 都会让 mtime 落后而内容其实最新——mtime 硬红会反复假阳性，实测于本批
// 提交时的 git add 换行归一），而真死角是「构建失败照跑旧 exe 报假绿」
// ——构建复核恰好只在该死角红。CI 全新 checkout + 首建路径不受影响。
//
// 三通道（诚实口径，2026-09-26 审阅 P2-2 修正：第三通道未做 diff）：
//  1. stdout：双侧提取纯程序输出（oracle 取「=== 运行输出 ===」分隔
//     段 + 剥末行尾注；MoonBit 剥标记行）后逐字节比对
//  2. 返回码：oracle 末行尾注 vs MoonBit `// EXIT N` 标记
//  3. 1MB 映像：MoonBit 侧 --dump-memory——**本版仅自包含性校验（恰
//     1MB），不做 diff**（oracle 侧 1MB 映像出口待建，出口就绪后补）
//
// stdout 提取（2026-09-26 审阅 P2-3 收紧）：此前按前缀整行滤噪
// （"// "、两空格缩进、Warning/Error/Finished.）会吃掉程序合法输出
// （如 printf("// hi")——同包探针实证归一后真差异被抹平）；现改为
// 按两侧各自的已知协议形状提取，不再碰程序输出内容行。
//
// verdict 三级（§7.1 层 1，2026-09-26）：
//
//	SAME             无差异
//	DIFF-known       case 在 known_diffs.json 且差异 digest 与登记一致
//	                 （已归因差异——D 级台账登记的 @math 值级偏离等；
//	                 digest 漂移即降级 DIFF，防白名单腐化为万能豁免）
//	DIFF(unexpected) 其余一切差异——红
//
// 白名单防腐化：skip/known 条目全量跑后未命中任何用例即红（空转条目
// = 腐化温床）。
//
// 用法：go run ./scripts/vm_diff [--sample N] [--corpus dir] [--cases f1.c,...]
//
//	（默认四语料全量 baseline+knr+leetcode+gap = 601 例；
//	--sample N 均匀抽样 = 快速本地模式；--corpus 单目录覆盖默认四语料）
package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

const runnerExe = "moonbit/_build/native/release/build/cmd/run/run.exe"

var corporaDefault = []string{"baseline", "knr", "leetcode", "gap"}

// skipEntry：SKIP 白名单（cmd 工具层豁免等非 VM 面用例）。
type skipEntry struct {
	Case   string `json:"case"`
	Reason string `json:"reason"`
}

// knownEntry：已归因差异白名单——digest = 差异内容（issues 拼接）sha256
// 前 8 位。case 命中但 digest 不匹配 = 差异形状已变，降级 DIFF 逼重新归因。
type knownEntry struct {
	Case   string `json:"case"`
	Digest string `json:"digest"`
	Reason string `json:"reason"`
}

type result struct {
	stdout      string
	exitCode    int
	memoryPath  string
	compileFail bool
}

// hit 防腐化标记：白名单条目须至少命中一次。
type skipList struct {
	entries []skipEntry
	hit     map[string]bool
}

type knownList struct {
	entries []knownEntry
	hit     map[string]bool
}

func main() {
	corpora := corporaDefault
	sample := 0
	var explicit []string
	args := os.Args[1:]
	for i := 0; i < len(args); i++ {
		switch {
		case args[i] == "--corpus" && i+1 < len(args):
			i++
			corpora = []string{args[i]}
		case args[i] == "--sample" && i+1 < len(args):
			i++
			fmt.Sscanf(args[i], "%d", &sample)
		case args[i] == "--cases" && i+1 < len(args):
			i++
			explicit = strings.Split(args[i], ",")
		default:
			fmt.Fprintf(os.Stderr, "vm_diff: 未知参数 %q\n", args[i])
			os.Exit(2)
		}
	}
	if !fileExists(runnerExe) {
		fmt.Fprintf(os.Stderr, "vm_diff: %s 不存在——先跑 cd moonbit && moon build --release --target native cmd/run\n", runnerExe)
		os.Exit(1)
	}
	// 新鲜度门禁（2026-09-26 批改：mtime 触发 + 构建复核）：moon 增量按
	// **内容 hash** 判定——touch、git 换行归一重写、等价内容再生成都会
	// 让 mtime 落后而 exe 内容其实最新（mtime 硬红 = 反复假阳性，实测：
	// 提交批的 git add 换行归一即触发）；反之构建失败照跑旧 exe 报假绿
	// 才是要封的死角。故落后时**跑一次规范化构建复核**：退出码 0 ⇒
	// moon 已保证 exe 内容最新（重链了或判定 no-work），放行；失败 ⇒
	// 红并拒绝给判定。
	if stale := findStaleSource(runnerExe); stale != "" {
		fmt.Fprintf(os.Stderr, "vm_diff: %s 旧于源 %s——跑构建复核（moon 内容 hash 增量）...\n", runnerExe, stale)
		if !rebuildRunner() {
			fmt.Fprintln(os.Stderr, "vm_diff: 构建失败——修好构建前不给判定（陈旧 exe 假绿由此封死）")
			os.Exit(1)
		}
		if !fileExists(runnerExe) {
			fmt.Fprintf(os.Stderr, "vm_diff: 构建成功但 %s 仍缺失（moon 缓存与磁盘不一致）——删 moonbit/_build/native/release/build/cmd/run 后重建\n", runnerExe)
			os.Exit(1)
		}
	}

	skips := loadSkipList()
	known := loadKnownDiffs()

	// 用例收集：--cases 精确指定（相对 corpus 根）或四语料全量/抽样。
	type Case struct {
		rel  string // 语料内相对名（display 用）
		path string
	}
	var cases []Case
	if len(explicit) > 0 {
		for _, f := range explicit {
			path := f
			if !filepath.IsAbs(f) && !strings.ContainsAny(f, `/\`) {
				// 裸名在四语料里找第一个命中
				found := false
				for _, c := range corpora {
					p := filepath.Join("native", "tests", "cases", c, f)
					if fileExists(p) {
						path = p
						found = true
						break
					}
				}
				if !found {
					fmt.Printf("SKIP  %s（四语料均不存在）\n", f)
					continue
				}
			}
			cases = append(cases, Case{rel: filepath.Base(f), path: path})
		}
	} else {
		for _, c := range corpora {
			dir := filepath.Join("native", "tests", "cases", c)
			entries, err := os.ReadDir(dir)
			if err != nil {
				fmt.Fprintf(os.Stderr, "vm_diff: 读语料目录失败 %s: %v\n", dir, err)
				os.Exit(1)
			}
			var names []string
			for _, e := range entries {
				if strings.HasSuffix(e.Name(), ".c") {
					names = append(names, e.Name())
				}
			}
			sort.Strings(names)
			if sample > 0 && len(names) > sample {
				names = sampleN(names, sample)
			}
			for _, n := range names {
				cases = append(cases, Case{rel: c + "/" + n, path: filepath.Join(dir, n)})
			}
		}
	}
	if len(cases) == 0 {
		fmt.Fprintln(os.Stderr, "vm_diff: 无用例")
		os.Exit(1)
	}

	// 白名单防腐化（静态部分）：skip/known 条目名不在本轮用例集合即红
	// ——只在全量模式（语料全集）判：抽样式可能天然不含白名单用例，静态
	// 判会误报（J9 注入实测实锤）。放在跑例之前，「语料中不存在」秒判
	// 不必等全量跑完；命中性防腐化（条目存在但从未触发）由全量跑后的
	// 动态检查承担（下方 known/skip 的 hit 表）。
	if len(explicit) == 0 && sample == 0 {
		names := map[string]bool{}
		for _, c := range cases {
			names[filepath.Base(c.rel)] = true
		}
		for _, e := range skips.entries {
			if !names[e.Case] {
				fmt.Fprintf(os.Stderr, "vm_diff: skip 白名单空转条目 %s——语料中不存在（删除或修正）\n", e.Case)
				os.Exit(1)
			}
		}
		for _, e := range known.entries {
			if !names[e.Case] {
				fmt.Fprintf(os.Stderr, "vm_diff: known 白名单空转条目 %s——语料中不存在（删除或修正）\n", e.Case)
				os.Exit(1)
			}
		}
	}

	same, knownN, diff, skipN := 0, 0, 0, 0
	for _, c := range cases {
		base := filepath.Base(c.rel)
		if r, ok := skips.lookup(base); ok {
			fmt.Printf("SKIP  %s（%s）\n", c.rel, r)
			skipN++
			continue
		}
		o := runOracle(c.path)
		m := runMoonBit(c.path)
		if o.compileFail && m.compileFail {
			fmt.Printf("SAME  %s（双侧编译失败——等价）\n", c.rel)
			same++
			continue
		}
		issues := compare(c.rel, o, m)
		if len(issues) == 0 {
			fmt.Printf("SAME  %s\n", c.rel)
			same++
			continue
		}
		digest := issueDigest(issues)
		if e, ok := known.lookup(base); ok {
			if e.Digest == digest {
				fmt.Printf("DIFF-KNOWN %s（%s；digest=%s）\n", c.rel, e.Reason, digest)
				knownN++
				continue
			}
			fmt.Printf("DIFF  %s：已知用例差异形状已变（登记 digest=%s 实测=%s）——重新归因更新 known_diffs.json：%s\n",
				c.rel, e.Digest, digest, strings.Join(issues, "；"))
			diff++
			continue
		}
		fmt.Printf("DIFF  %s [%s]：%s\n", c.rel, digest, strings.Join(issues, "；"))
		diff++
	}
	fmt.Printf("\nvm_diff: SAME=%d DIFF-KNOWN=%d DIFF=%d SKIP=%d（共 %d）\n",
		same, knownN, diff, skipN, same+knownN+diff+skipN)

	// 白名单防腐化：全量模式（非 --cases/--sample）下空转条目即红。
	if len(explicit) == 0 && sample == 0 {
		bad := false
		for _, e := range skips.entries {
			if !skips.hit[e.Case] {
				fmt.Fprintf(os.Stderr, "vm_diff: skip 白名单空转条目 %s——本轮未命中（已无需豁免则删除）\n", e.Case)
				bad = true
			}
		}
		for _, e := range known.entries {
			if !known.hit[e.Case] {
				fmt.Fprintf(os.Stderr, "vm_diff: known 白名单空转条目 %s——本轮未产生差额（用例已转绿则删除本条目，双向监控纪律）\n", e.Case)
				bad = true
			}
		}
		if bad {
			os.Exit(1)
		}
	}
	if diff > 0 {
		os.Exit(1)
	}
}

// sampleN：均匀抽 N（覆盖字母序范围；pick30 同源算法）。
func sampleN(all []string, n int) []string {
	out := make([]string, 0, n)
	step := float64(len(all)) / float64(n)
	for i := 0; i < n; i++ {
		idx := int(float64(i) * step)
		if idx >= len(all) {
			idx = len(all) - 1
		}
		out = append(out, all[idx])
	}
	return out
}

// issueDigest：差异内容指纹（sha256 前 8 位）——known 白名单的精确豁免键。
func issueDigest(issues []string) string {
	h := sha256.Sum256([]byte(strings.Join(issues, "\x00")))
	return fmt.Sprintf("%x", h)[:8]
}

// ---- 白名单装载（规则外置 JSON：人审数据不审代码）----

func loadSkipList() *skipList {
	s := &skipList{hit: map[string]bool{}}
	raw, err := os.ReadFile(filepath.Join("scripts", "vm_diff", "skip_list.json"))
	if err != nil {
		fmt.Fprintf(os.Stderr, "vm_diff: 读 skip_list.json 失败: %v\n", err)
		os.Exit(1)
	}
	if err := json.Unmarshal(raw, &s.entries); err != nil {
		fmt.Fprintf(os.Stderr, "vm_diff: skip_list.json 解析失败: %v\n", err)
		os.Exit(1)
	}
	return s
}

func (s *skipList) lookup(caseName string) (string, bool) {
	for _, e := range s.entries {
		if e.Case == caseName {
			s.hit[e.Case] = true
			return e.Reason, true
		}
	}
	return "", false
}

func loadKnownDiffs() *knownList {
	k := &knownList{hit: map[string]bool{}}
	raw, err := os.ReadFile(filepath.Join("scripts", "vm_diff", "known_diffs.json"))
	if err != nil {
		fmt.Fprintf(os.Stderr, "vm_diff: 读 known_diffs.json 失败: %v\n", err)
		os.Exit(1)
	}
	if err := json.Unmarshal(raw, &k.entries); err != nil {
		fmt.Fprintf(os.Stderr, "vm_diff: known_diffs.json 解析失败: %v\n", err)
		os.Exit(1)
	}
	return k
}

func (k *knownList) lookup(caseName string) (knownEntry, bool) {
	for _, e := range k.entries {
		if e.Case == caseName {
			k.hit[e.Case] = true
			return e, true
		}
	}
	return knownEntry{}, false
}

func fileExists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}

// compare：三通道比对（第三通道为自包含性校验，非 diff——见头注）。
func compare(name string, o, m *result) []string {
	var issues []string
	// 单侧编译失败先行报明（否则降格成「stdout/返回码不一致」难归因——
	// include_quote_sentinel 实锤：oracle vfs 磁盘/预设注入 vs cmd/run 无）
	if o.compileFail != m.compileFail {
		who := "oracle"
		if m.compileFail {
			who = "moonbit"
		}
		issues = append(issues, fmt.Sprintf("单侧编译失败（%s）", who))
	}
	os_ := extractOracleStdout(o.stdout)
	ms := extractMoonBitStdout(m.stdout)
	if os_ != ms {
		issues = append(issues, summarizeStdout(os_, ms))
	}
	if o.exitCode != m.exitCode {
		issues = append(issues, fmt.Sprintf("返回码 %d != %d", o.exitCode, m.exitCode))
	}
	if m.memoryPath != "" {
		if data, err := os.ReadFile(m.memoryPath); err == nil {
			if len(data) != 1024*1024 {
				issues = append(issues, fmt.Sprintf("映像非 1MB（%d）", len(data)))
			}
		}
	}
	return issues
}

// extractOracleStdout：从 vitro_cli run 的 stdout 提取纯程序输出——
// 取第一个「=== 运行输出 ===」分隔行（vitro_cli 分隔行族：编译警告/
// 诊断信息/运行输出）之后的内容，末行若为尾注形态（「程序运行完成，
// 返回值：N」）则剥。找不到分隔行（编译失败）返回空。
// 只剥末行尾注：程序自己打印 lookalike 文本（engine_note_lookalike 形状）
// 位于中间行不受影响。
func extractOracleStdout(s string) string {
	lines := strings.Split(s, "\n")
	start := -1
	for i, l := range lines {
		if strings.TrimRight(l, "\r") == "=== 运行输出 ===" {
			start = i + 1
			break
		}
	}
	if start < 0 {
		return ""
	}
	rest := lines[start:]
	// 尾注即运行输出段的**结束标志**（首个含该子串的行处截断，行内
	// 前缀保留——紧贴形态 "N程序运行完成，返回值：0" 同行）。尾注之后
	// 还有正文段（内存泄漏检测报告 ===== 段等——kr_6_6/lc_124 实锤），
	// 不截断会把报告正文当程序输出。已知限制：程序自己打印 lookalike
	// 文本会提前截断（engine_note_lookalike 形状）——精确口径由 shadow
	// 防线的结构化输出通道承担，登记不修。
	for i, l := range rest {
		if idx := strings.Index(l, "程序运行完成，返回值："); idx >= 0 {
			rest = rest[:i+1]
			rest[i] = l[:idx]
			break
		}
	}
	return normalizeLines(rest)
}

// extractMoonBitStdout：从 cmd/run 的 stdout 提取纯程序输出——剥引擎
// 标记行（`// TRAP`、`// COMPILE-ERROR` 前缀；末行 `// EXIT N`）。
// 标记是 vm_diff 与 cmd/run 的私有协议（头注「输出协议」），按精确形状
// 剥而非 `// ` 前缀整行剥——程序 printf("// hi") 是合法输出不得误伤。
func extractMoonBitStdout(s string) string {
	lines := strings.Split(s, "\n")
	var kept []string
	for _, l := range lines {
		t := strings.TrimRight(l, "\r")
		if strings.HasPrefix(t, "// TRAP ") || strings.HasPrefix(t, "// COMPILE-ERROR ") {
			continue
		}
		kept = append(kept, l)
	}
	// 先剥尾部空行再判末行：Split("\n") 在尾 \n 后产生空串元素，
	// 直接看 kept[n-1] 会撞空串而漏剥 EXIT 标记（探针实锤：EXIT 行
	// 残留进比对报 8 行假 DIFF）。
	for len(kept) > 0 && strings.TrimRight(kept[len(kept)-1], "\r") == "" {
		kept = kept[:len(kept)-1]
	}
	if n := len(kept); n > 0 {
		if strings.HasPrefix(strings.TrimRight(kept[n-1], "\r"), "// EXIT ") {
			kept = kept[:n-1]
		}
	}
	return normalizeLines(kept)
}

// normalizeLines：CRLF 归一 + 首尾空行剥 + 恰一个尾换行。
func normalizeLines(lines []string) string {
	out := make([]string, 0, len(lines))
	for _, l := range lines {
		out = append(out, strings.TrimRight(l, "\r"))
	}
	for len(out) > 0 && out[len(out)-1] == "" {
		out = out[:len(out)-1]
	}
	for len(out) > 0 && out[0] == "" {
		out = out[1:]
	}
	return strings.Join(out, "\n")
}

// rebuildRunner：跑规范化构建（cwd=moonbit）——退出码 0 即 moon 已保证
// exe 内容最新（重链了或内容 hash 判定 no-work）；供 mtime 落后时复核。
func rebuildRunner() bool {
	cmd := exec.Command("moon", "build", "--release", "--target", "native", "cmd/run")
	cmd.Dir = "moonbit"
	out, err := cmd.CombinedOutput()
	if err != nil {
		fmt.Fprintln(os.Stderr, string(out))
		return false
	}
	return true
}

// findStaleSource：返回任一比 runner exe 新的 moonbit 源文件（.mbt/
// .mod/.pkg；跳过 _build 产物目录），全新鲜则返回空串。
func findStaleSource(runner string) string {
	st, err := os.Stat(runner)
	if err != nil {
		return runner
	}
	exeMtime := st.ModTime()
	var stale string
	_ = filepath.WalkDir("moonbit", func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			if d.Name() == "_build" || d.Name() == ".mooncakes" {
				return filepath.SkipDir
			}
			return nil
		}
		name := d.Name()
		if strings.HasSuffix(name, ".mbt") || strings.HasSuffix(name, ".mod") ||
			strings.HasSuffix(name, ".pkg") {
			if info, err := d.Info(); err == nil && info.ModTime().After(exeMtime) {
				if stale == "" {
					stale = path
				}
			}
		}
		return nil
	})
	return stale
}

func runOracle(path string) *result {
	bin := filepath.Join("native", "target", "release", "vitro_cli.exe")
	if !fileExists(bin) {
		return &result{compileFail: true, stdout: "// ORACLE-MISSING"}
	}
	var out bytes.Buffer
	cmd := exec.Command(bin, "run", path)
	cmd.Stdout = &out
	cmd.Stderr = &out
	err := cmd.Run()
	code := 0
	if exitErr, ok := err.(*exec.ExitError); ok {
		code = exitErr.ExitCode()
	}
	r := &result{stdout: out.String(), exitCode: code}
	// 编译失败判定：以「无运行输出段」为准——诊断段（=== 诊断信息 ===）
	// 在编译**成功**但有警告/提示时也出现（file_fopen 实测：[提示] H3057 +
	// 「编译成功。」+ 运行输出段），拿诊断段判失败会把 39 个正常用例误判
	// 单侧失败（抽样回归实锤）。
	r.compileFail = !strings.Contains(r.stdout, "=== 运行输出 ===")
	// oracle 的返回码在「程序运行完成，返回值：N」尾注（进程 exit 恒 0）；
	// 尾注紧贴程序输出是常态——按子串定位再扫尾部，行首匹配会漏
	for _, line := range strings.Split(r.stdout, "\n") {
		if idx := strings.Index(line, "程序运行完成，返回值："); idx >= 0 {
			fmt.Sscanf(strings.TrimRight(line[idx:], "\r"), "程序运行完成，返回值：%d", &r.exitCode)
		}
	}
	return r
}

func runMoonBit(path string) *result {
	tmp, err := os.CreateTemp("", "vmem_*.bin")
	if err != nil {
		return &result{stdout: "// TMPFAIL"}
	}
	tmp.Close()
	defer os.Remove(tmp.Name())

	var out bytes.Buffer
	cmd := exec.Command(filepath.FromSlash(runnerExe), path, "--dump-memory", tmp.Name())
	cmd.Stdout = &out
	cmd.Stderr = &out
	_ = cmd.Run()
	r := &result{stdout: out.String(), memoryPath: tmp.Name()}
	if strings.Contains(r.stdout, "// COMPILE-ERROR") {
		r.compileFail = true
	}
	for _, line := range strings.Split(strings.TrimSpace(r.stdout), "\n") {
		if strings.HasPrefix(line, "// EXIT ") {
			fmt.Sscanf(line, "// EXIT %d", &r.exitCode)
		}
	}
	return r
}

// summarizeStdout：stdout 差异摘要（首个差异行 + 两侧长度）。
func summarizeStdout(o, m string) string {
	ol := strings.Split(o, "\n")
	ml := strings.Split(m, "\n")
	for i := 0; i < len(ol) && i < len(ml); i++ {
		if ol[i] != ml[i] {
			return fmt.Sprintf("stdout 第 %d 行不一致（oracle %q vs moonbit %q；总 %d/%d 字节）", i+1, clip(ol[i]), clip(ml[i]), len(o), len(m))
		}
	}
	if len(ol) != len(ml) {
		return fmt.Sprintf("stdout 行数不一致（oracle %d vs moonbit %d；总 %d/%d 字节）", len(ol), len(ml), len(o), len(m))
	}
	return fmt.Sprintf("stdout 不一致（%d/%d 字节）", len(o), len(m))
}

func clip(s string) string {
	if len(s) > 40 {
		return s[:40] + "…"
	}
	return s
}
