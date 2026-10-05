// vm_diff：D 级 diff 驱动（批五号——总计划 §6 D 级锚：stdout + 返回码
// + 1MB 最终内存映像；§7.1 层 1 全量化，2026-09-26 六轮审阅销项批）。
//
// 工序③固化基线模式（2026-10-05，digest 清单形态）：
//
//	go run ./scripts/vm_diff --freeze   # 跑双侧 → 聚合 digest 清单落盘 golden_digest.json
//	go run ./scripts/vm_diff --golden   # mb ↔ 清单比对（基线模式）
//
//	清单 = 每例一行 {src_sha, exit_code, stdout_sha(提取后), memory_sha}；
//	**known 分叉例额外登记 mb 侧整例 hash（known_mb_digest）**——比对语义
//	统一为「mb 当前 hash ≡ 清单登记 hash」（非分叉例记 oracle 侧、分叉例
//	记 mb 侧），known digest 漂移即降级 DIFF 与现模式同构。oracle exe 不存
//	在时自动切 --golden（工序④删区后 CI 零改动）。全文产物兜底 = orphan
//	分支 frozen-oracle-snapshot（默认 clone 不拉）；重刷 diff = 影响面清单。
//	锚定语义：**一致性锚非正确性锚**——stdout 的正确性主锚是 shadow/Clang
//	golden，本清单锚白箱特有面（映像/退出码/oracle 特有 stdout 语义）。
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
// 三通道（第三通道 2026-09-26 升级为真 diff——oracle 侧映像出口已建）：
//  1. stdout：双侧提取纯程序输出（oracle 取「=== 运行输出 ===」分隔
//     段 + 剥末行尾注；MoonBit 剥标记行）后逐字节比对
//  2. 返回码：oracle 末行尾注 vs MoonBit `// EXIT N` 标记
//  3. 1MB 映像：双侧 --dump-memory（oracle 出口 = vitro_cli run
//     --dump-memory → VitroVM::memory_bytes，防线维护批）逐字节 diff，
//     首差地址 + 差异字节数入 issue；双侧编译失败（等价）无映像不比
//     **区间机判（2026-09-26 审阅销项）**：含映像差异的 known 条目必须
//     声明 memory_stack_only 且实际残渣必须全部落在栈窗口内（映像顶部
//     4096B），否则降级 DIFF——见 knownEntry 注释。
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
//	                 digest 漂移即降级 DIFF，防白名单腐化为万能豁免；
//	                 含映像差异者另过区间机判：未声明 memory_stack_only
//	                 或残渣越出栈窗口 ⇒ 仍判 DIFF）
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
//
// memory_stack_only（2026-09-26 审阅销项，**含映像差异的条目必填**）：
// digest 只钉「差异字节数 + 首差地址」（见 issueDigest 口径），差异搬家而
// 计数与首差恰好不变时 digest 不动；且 digest 不表达差异落在哪一段内存。
// 故含 1MB 映像差异的条目必须显式认领区间（`"memory_stack_only": true`），
// 由 main 里的 stackWindow 机判复核实际落点——未声明或越窗一律降级 DIFF。
// 这是"残渣必须是生命周期外栈内容"这条**归因**的机判替身（人写的 reason
// 文本不作依据）。
type knownEntry struct {
	Case            string `json:"case"`
	Digest          string `json:"digest"`
	Reason          string `json:"reason"`
	MemoryStackOnly bool   `json:"memory_stack_only,omitempty"`
}

// 栈窗口：`STACK_START = MEM_SIZE`、栈向下生长 ⇒ 栈天然占映像顶部。单源 =
// moonbit/bytecode/memory.mbt（MEM_SIZE / STACK_START / GLOBAL_REGION_LIMIT）。
// 窗口宽度取**实测标定**（2026-09-26，tmp/review_20260926/memdiff/）：5 个
// known 用例的存活数据（全局/argv/堆）最高落点 = 0x10015，qsort 族残渣落点
// = 0xFFF90–0xFFFEC ⇒ 取顶部 4KB 比实测栈用量（~112B）宽 36 倍，同时远低于
// 堆可达高度。方向是 fail loud：真栈深超过 4KB 的用例会红（逼人看一眼），
// 而"差异落在全局/堆/argv 区"必红。
// Case：对拍用例（rel = 语料内相对名，path = 绝对/仓库相对路径）。
type Case struct {
	rel  string
	path string
}

// skips/known：白名单包级单例（main 装载，digest 函数集消费）。
var skips *skipList
var known *knownList

// relOf：digest 清单键形态单源——四语料内 = "corpus/name.c"，外部路径
// = basename（--cases 外部路径的键形态与 freeze 的 goldenPathFor 同构）。
func relOf(path string) string {
	base := filepath.Base(path)
	dir := filepath.Base(filepath.Dir(path))
	for _, c := range corporaDefault {
		if dir == c {
			return c + "/" + base
		}
	}
	return base
}

// cleanup：临时映像回收（原 main 局部闭包，digest 路径共用）。
func cleanup(r *result) {
	if r != nil && r.memoryPath != "" {
		os.Remove(r.memoryPath)
	}
}

const stackWindowBytes = 4096

// memDiff：第三通道差异的地址画像（nil = 本用例无映像差异）。
type memDiff struct {
	count, first, last, size int
}

// allInStackWindow：全部差异地址落在映像顶部 stackWindowBytes 内。
func (d *memDiff) allInStackWindow() bool {
	return d.size > 0 && d.first >= d.size-stackWindowBytes
}

func (d *memDiff) describe() string {
	return fmt.Sprintf("映像残渣 %d 字节 @0x%X..0x%X（栈窗口 0x%X..0x%X）",
		d.count, d.first, d.last, d.size-stackWindowBytes, d.size)
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
	freeze := false
	freezeMB := false
	againstGolden := false
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
		case args[i] == "--freeze":
			// 工序③固化（2026-10-05）：oracle 侧三通道产物全量落盘 golden。
			freeze = true
		case args[i] == "--freeze-mb":
			// 删区后新用例入账（2026-10-05 BUG-B 语料批）：--freeze 的 oracle
			// 侧已随工序④删区断源，本通道以 mb 侧产物入账（见 freezeMBDigest）。
			freezeMB = true
		case args[i] == "--selftest":
			selftestFlag = true
		case args[i] == "--golden":
			// 工序③固化：mb ↔ golden 对拍（oracle 消失后的基线模式）。
			againstGolden = true
		default:
			fmt.Fprintf(os.Stderr, "vm_diff: 未知参数 %q\n", args[i])
			os.Exit(2)
		}
	}
	oracleBin := filepath.Join("native", "target", "release", "vitro_cli.exe")
	if againstGolden && freeze {
		fmt.Fprintln(os.Stderr, "vm_diff: --freeze 与 --golden 互斥（先 freeze 后 golden）")
		os.Exit(2)
	}
	if freeze && freezeMB {
		fmt.Fprintln(os.Stderr, "vm_diff: --freeze 与 --freeze-mb 互斥（双侧固化 vs mb 单侧入账）")
		os.Exit(2)
	}
	if againstGolden && freezeMB {
		fmt.Fprintln(os.Stderr, "vm_diff: --golden 与 --freeze-mb 互斥（比对 vs 入账）")
		os.Exit(2)
	}
	// 删区自动降级：oracle exe 不存在且未显式 --golden ⇒ 自动转 golden 模式
	// （工序④删区后零改动存活）；显式 --golden 而 oracle 仍在也照跑 golden。
	if !fileExists(oracleBin) && !freeze && !freezeMB {
		if !againstGolden {
			fmt.Fprintln(os.Stderr, "vm_diff: [裁判切换] oracle exe 不存在——本判定走 --golden 冻结基线（结构裁判自 oracle 切为 digest 清单；正确性主锚仍为 Clang/shadow）")
			againstGolden = true
		}
	}
	if freeze && !fileExists(oracleBin) {
		fmt.Fprintln(os.Stderr, "vm_diff: --freeze 需要 oracle exe（native/target/release/vitro_cli.exe）")
		os.Exit(1)
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

	skips = loadSkipList()
	known = loadKnownDiffs()

	// 用例收集：--cases 精确指定（相对 corpus 根）或四语料全量/抽样。
	var cases []Case
	if len(explicit) > 0 {
		for _, f := range explicit {
			path := f
			if !filepath.IsAbs(f) && !strings.ContainsAny(f, `/\`) {
				// 裸名在四语料里找第一个命中
				found := false
				for _, c := range corpora {
					p := filepath.Join("corpus", c, f)
					if fileExists(p) {
						path = p
						found = true
						break
					}
				}
				if !found {
					// fail loud（2026-10-05 审阅 P2）：此前 SKIP+continue 在混用
					// 合法/非法名时整体 rc=0——丢弃不反映在退出码（假绿实测）；
					// 且裸名分支曾漏改 native/ 前缀（同族漏改 C5），SKIP 掩盖了
					// 全部裸名恒不可达。与下方「含分隔符路径不存在」同口径。
					fmt.Fprintf(os.Stderr, "vm_diff: --cases 裸名在四语料均不存在: %s\n", f)
					os.Exit(2)
				}
			} else if !filepath.IsAbs(f) && !fileExists(f) {
				// 含分隔符的相对路径按仓库根原样使用（clang_direct 同口径）——
				// 此前静默跑不存在文件：oracle 报 ORACLE-MISSING、MoonBit 报
				// io COMPILE-ERROR，双侧 compileFail 凑成假 SAME（kruskalMST
				// 调查批实测踩中）；fail loud 优于静默空跑
				fmt.Fprintf(os.Stderr, "vm_diff: --cases 路径不存在: %s（相对仓库根，如 corpus/baseline/x.c）\n", f)
				os.Exit(2)
			}
			cases = append(cases, Case{rel: relOf(path), path: path})
		}
	} else {
		for _, c := range corpora {
			dir := filepath.Join("corpus", c)
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
	if fullCorpusRun(corpora, explicit, sample) {
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

	// ---- 工序③固化（2026-10-05）：freeze / golden 基线模式（digest 清单） ----
	if freeze {
		os.Exit(freezeDigest(cases))
	}
	if freezeMB {
		os.Exit(freezeMBDigest(cases))
	}
	if againstGolden {
		os.Exit(runAgainstDigest(cases))
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
			cleanup(o)
			cleanup(m)
			continue
		}
		issues, mem := compare(c.rel, o, m)
		cleanup(o)
		cleanup(m)
		if len(issues) == 0 {
			fmt.Printf("SAME  %s\n", c.rel)
			same++
			continue
		}
		// P3-7（2026-09-26 审阅）：digest 混入 case 名——两条用例的差异
		// 文本完全相同时 digest 亦同（指针宽度两例撞车实锤），白名单豁免
		// 必须钉到「这一例的这种差异」而非「任何一例的这种差异」。
		digest := issueDigest(append([]string{base}, issues...))
		if e, ok := known.lookup(base); ok {
			if e.Digest == digest {
				// 区间机判（见 knownEntry.MemoryStackOnly 注释）：含映像差异的
				// 条目必须显式认领 + 实际落点必须在栈窗口内，否则降级 DIFF。
				if mem != nil && !e.MemoryStackOnly {
					fmt.Printf("DIFF  %s：known 条目含 1MB 映像差异却未声明 \"memory_stack_only\": true——区间须显式认领（%s）\n",
						c.rel, mem.describe())
					diff++
					continue
				}
				if mem != nil && !mem.allInStackWindow() {
					fmt.Printf("DIFF  %s：%s——越出栈窗口，活数据差异不得豁免（重新归因或修真缺陷）\n",
						c.rel, mem.describe())
					diff++
					continue
				}
				extra := ""
				if mem != nil {
					extra = "；" + mem.describe()
				}
				fmt.Printf("DIFF-KNOWN %s（%s；digest=%s%s）\n", c.rel, e.Reason, digest, extra)
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
	if fullCorpusRun(corpora, explicit, sample) {
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

// fullCorpusRun：真·全量（默认四语料、无 --cases/--sample）——--corpus 单
// 语料是子集运行，白名单空转校验（静态与动态）只在此形态判，否则
// `--corpus gap` 会误报「engine_note_lookalike.c 不在本轮」（P3-6，
// 2026-09-26 审阅：usage 写着支持 --corpus 却恒误红）。
func fullCorpusRun(corpora []string, explicit []string, sample int) bool {
	if len(explicit) != 0 || sample != 0 {
		return false
	}
	if len(corpora) != len(corporaDefault) {
		return false
	}
	for i := range corpora {
		if corpora[i] != corporaDefault[i] {
			return false
		}
	}
	return true
}

// stdinFor：同名 .in 配对（x.c → x.in；无则空串）。2026-09-29 层 2 遗留
// stdin 34 例批——此前 34 例只测 EOF 形态。
func stdinFor(path string) string {
	p := strings.TrimSuffix(path, ".c") + ".in"
	if fileExists(p) {
		return p
	}
	return ""
}
func fileExists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}

// compare：三通道比对（第三通道 = 1MB 映像逐字节 diff）。返回 issues 与
// 第三通道的地址画像（nil = 未产出可比映像，含单侧编译失败/读取失败）。
func compare(name string, o, m *result) ([]string, *memDiff) {
	var issues []string
	var mem *memDiff
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
	// 第三通道：1MB 映像逐字节（双侧编译成功才比——双侧失败已在调用方
	// 判等价后 continue 到不了这里；单侧失败已由 issue 1 报明）
	if !o.compileFail && !m.compileFail {
		switch {
		case o.memoryPath == "" || m.memoryPath == "":
			issues = append(issues, "映像缺失（一侧未产出 dump）")
		default:
			od, err1 := os.ReadFile(o.memoryPath)
			md, err2 := os.ReadFile(m.memoryPath)
			switch {
			case err1 != nil || err2 != nil:
				issues = append(issues, fmt.Sprintf("映像读取失败（oracle=%v moonbit=%v）", err1, err2))
			case len(od) != 1024*1024 || len(md) != 1024*1024:
				issues = append(issues, fmt.Sprintf("映像非 1MB（oracle=%d moonbit=%d）", len(od), len(md)))
			case !bytes.Equal(od, md):
				n, first := 0, -1
				for i := range od {
					if od[i] != md[i] {
						if first < 0 {
							first = i
						}
						n++
					}
				}
				mem = &memDiff{count: n, first: first, last: first, size: len(od)}
				for i := len(od) - 1; i >= 0; i-- {
					if od[i] != md[i] {
						mem.last = i
						break
					}
				}
				issues = append(issues, fmt.Sprintf("1MB 映像 %d 字节不一致（首差 @0x%X）", n, first))
			}
		}
	}
	return issues, mem
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
		if strings.HasPrefix(t, "// TRAP ") || strings.HasPrefix(t, "// COMPILE-ERROR ") ||
			strings.HasPrefix(t, "// COMPILE-WARNING ") || strings.HasPrefix(t, "// COMPILE-HINT ") ||
			strings.HasPrefix(t, "// NOTE ") {
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
	tmp, err := os.CreateTemp("", "ovmem_*.bin")
	if err != nil {
		return &result{compileFail: true, stdout: "// TMPFAIL"}
	}
	tmp.Close()
	var out bytes.Buffer
	args := []string{"run", path}
	if in := stdinFor(path); in != "" {
		args = append(args, "-i", in)
	}
	args = append(args, "--dump-memory", tmp.Name())
	cmd := exec.Command(bin, args...)
	cmd.Stdout = &out
	cmd.Stderr = &out
	err = cmd.Run()
	code := 0
	if exitErr, ok := err.(*exec.ExitError); ok {
		code = exitErr.ExitCode()
	}
	r := &result{stdout: out.String(), exitCode: code, memoryPath: tmp.Name()}
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

	var out bytes.Buffer
	margs := []string{path}
	if in := stdinFor(path); in != "" {
		margs = append(margs, "-i", in)
	}
	margs = append(margs, "--dump-memory", tmp.Name())
	cmd := exec.Command(filepath.FromSlash(runnerExe), margs...)
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

// ============ 工序③固化：digest 清单（2026-10-05 定稿形态） ============
//
// 清单 = 每例一行聚合 digest（src_sha + exit_code + 提取后 stdout sha +
// 映像 sha；known 分叉例另记 mb 整例 hash）。比对语义统一为「mb 当前值
// ≡ 清单登记值」：非分叉例登记 oracle 侧值（freeze 时刻两侧一致的可证
// 错——freeze 顺带全量对拍，DIFF 即拒写清单），known 分叉例登记 mb 侧
// 整例 hash（分叉形状漂移即降级，与现模式 digest 漂移降级同构）。
// 全文产物兜底 = orphan 分支 frozen-oracle-snapshot；重刷 diff 即影响面
// 清单。一致性锚非正确性锚（stdout 正确性主锚 = shadow/Clang golden）。

const digestPath = "scripts/vm_diff/golden_digest.json"

// selftestFlag：golden 路径自证（审阅 P3——vm 原无 --selftest flag，本批补）。
var selftestFlag bool

type digestEntry struct {
	SrcSHA      string `json:"src_sha"`
	ExitCode    int    `json:"exit_code"`
	StdoutSHA   string `json:"stdout_sha"` // 提取后纯程序输出（两侧各自提取，语义面同构）
	MemorySHA   string `json:"memory_sha,omitempty"`
	CompileFail bool   `json:"compile_fail,omitempty"`
	// known 分叉例专用：freeze 时 mb 侧整例指纹（exit+stdout+memory 联合）
	KnownMbDigest string `json:"known_mb_digest,omitempty"`
}

type digestDoc struct {
	Version int                    `json:"version"`
	Note    string                 `json:"note"`
	Cases   map[string]digestEntry `json:"cases"` // 键 = "corpus/name.c"
}

func srcSHAOf(path string) string {
	h := sha256.New()
	for _, p := range append([]string{path}, stdinFor(path)) {
		if p == "" {
			continue
		}
		b, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		crlf := []byte{13, 10}
		lf := []byte{10}
		h.Write(bytes.ReplaceAll(b, crlf, lf))
	}
	return fmt.Sprintf("%x", h.Sum(nil))[:8]
}

func fileSHA(p string) string {
	b, err := os.ReadFile(p)
	if err != nil {
		return ""
	}
	return fmt.Sprintf("%x", sha256.Sum256(b))[:16]
}

// argvMaskHi：映像 hash 的环境脱敏上界——argv 区自 GLOBAL_REGION_LIMIT
// （0x10000）向下分配（R1 内存边界批），调用路径字节落在其下窗口。映像锚
// 定**程序数据面**（堆/栈/全局），调用环境（argv 路径）归 shadow/argv 专项
// 对拍——语料目录 mv（native/tests/cases → corpus，工序④）曾使 593 例
// memory hash 全翻（stdout 逐位同）实锤此耦合（2026-10-05）。
const argvMaskHi = 0x10000
const argvMaskLo = 0xF000 // 审阅 P3 收窄（2026-10-05）：argv 载荷实测 ~50B，16KB 掩窗过宽——无 argv 时堆自 0x5000 上行/全局数据可落入窗内成漏报面；4KB 仍余量 ~80×

// memorySHA：argv 窗口置零后取 hash（环境无关指纹）。
func memorySHA(p string) string {
	b, err := os.ReadFile(p)
	if err != nil {
		return ""
	}
	for i := argvMaskLo; i < argvMaskHi && i < len(b); i++ {
		b[i] = 0
	}
	return fmt.Sprintf("%x", sha256.Sum256(b))[:16]
}

// digestOfResult：从 result 提三通道指纹（stdout 用 oracle 侧提取器——
// golden 模式下 mb 侧经 extractMoonBitStdout 后应与 oracle 提取结果同
// 字节，这正是 compare 的语义面）。
func digestOfResult(r *result) (int, string, string, bool) {
	stdout := extractOracleStdout(r.stdout)
	memSHA := ""
	if r.memoryPath != "" {
		memSHA = memorySHA(r.memoryPath)
	}
	return r.exitCode, fmt.Sprintf("%x", sha256.Sum256([]byte(stdout)))[:16], memSHA, r.compileFail
}

func mbWholeDigest(exit int, stdoutSHA, memSHA string, cf bool) string {
	return fmt.Sprintf("%x", sha256.Sum256([]byte(fmt.Sprintf("%d|%s|%s|%v", exit, stdoutSHA, memSHA, cf))))[:16]
}

// freezeDigest：全量跑双侧 → 逐例对拍（现模式语义）→ 全绿才写清单
// （known 例按登记降级）；known 例登记 mb 整例指纹。
func freezeDigest(cases []Case) int {
	doc := digestDoc{Version: 1, Note: "freeze 落盘前已全量对拍（SAME/DIFF-KNOWN），DIFF 例拒绝写入", Cases: map[string]digestEntry{}}
	same, knownN := 0, 0
	for _, c := range cases {
		base := filepath.Base(c.rel)
		if _, ok := skips.lookup(base); ok {
			continue // skip 例不入清单（golden 模式同样跳过）
		}
		o := runOracle(c.path)
		m := runMoonBit(c.path)
		if o.compileFail && m.compileFail {
			doc.Cases[c.rel] = digestEntry{SrcSHA: srcSHAOf(c.path), CompileFail: true}
			same++
			cleanup(o)
			cleanup(m)
			continue
		}
		issues, _ := compare(c.rel, o, m)
		oe, os_, om, _ := digestOfResult(o)
		me, ms, mm, mcf := digestOfResultMB(m)

		if len(issues) > 0 {
			if e, ok := known.lookup(base); ok && e.Digest == issueDigest(append([]string{base}, issues...)) {
				doc.Cases[c.rel] = digestEntry{SrcSHA: srcSHAOf(c.path), ExitCode: me, StdoutSHA: ms, MemorySHA: mm, CompileFail: mcf, KnownMbDigest: mbWholeDigest(me, ms, mm, mcf)}
				fmt.Printf("DIFF-KNOWN %s（%s）——登记 mb 侧指纹\n", c.rel, e.Reason)
				knownN++
				cleanup(o)
				cleanup(m)
				continue
			}
			fmt.Printf("DIFF  %s [%s]：%s——freeze 拒写清单（先归因或修复）"+string(rune(10)), c.rel, issueDigest(append([]string{base}, issues...)), strings.Join(issues, "；"))
			cleanup(o)
			cleanup(m)
			os.Exit(1)
		}
		doc.Cases[c.rel] = digestEntry{SrcSHA: srcSHAOf(c.path), ExitCode: oe, StdoutSHA: os_, MemorySHA: om}
		same++
		cleanup(o)
		cleanup(m)
	}
	data, _ := json.MarshalIndent(doc, "", "  ")
	if err := os.WriteFile(digestPath, append(data, 10), 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "vm_diff freeze: 写清单失败: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("\nvm_diff freeze: digest 清单落盘 %d 例（SAME=%d KNOWN=%d）→ %s\n", len(doc.Cases), same, knownN, digestPath)
	return 0
}

// freezeMBDigest：删区后新用例入账通道（2026-10-05 BUG-B 语料批建）：
// --freeze 的 oracle 侧已随工序④删区断源，新语料无法走双侧对拍入账。
// 本通道以 mb 侧三通道产物入账（digestOfResultMB 提取器——与 golden
// 模式比对口径同源，known 例 KnownMbDigest 同构）；正确性背书 =
// clang_direct（stdout/退出码 vs Clang 真值）+ moon test 锚；memory
// 映像为白箱特有面（无 Clang 对照，快照 mb 当前行为作回归锚——与清单
// 头注定位一致）。**已存在键拒绝覆盖**：刷基线属修复批显式操作
// （先删旧键重跑），防新用例入账误刷存量基线。
func freezeMBDigest(cases []Case) int {
	raw, err := os.ReadFile(digestPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "vm_diff --freeze-mb: 缺清单 %s（首建基线属工序③ freeze 语义）: %v\n", digestPath, err)
		os.Exit(1)
	}
	var doc digestDoc
	if err := json.Unmarshal(raw, &doc); err != nil || doc.Version != 1 {
		fmt.Fprintf(os.Stderr, "vm_diff --freeze-mb: 清单坏或版本不识\n")
		os.Exit(1)
	}
	added, skipped := 0, 0
	for _, c := range cases {
		base := filepath.Base(c.rel)
		if _, ok := skips.lookup(base); ok {
			fmt.Printf("SKIP  %s（skip 清单——不入账）\n", c.rel)
			continue
		}
		if _, ok := doc.Cases[c.rel]; ok {
			skipped++ // 存量例跳过——不覆盖既有基线（刷基线先删旧键重跑）
			continue
		}
		m := runMoonBit(c.path)
		me, ms, mm, mcf := digestOfResultMB(m)
		doc.Cases[c.rel] = digestEntry{SrcSHA: srcSHAOf(c.path), ExitCode: me, StdoutSHA: ms, MemorySHA: mm, CompileFail: mcf}
		fmt.Printf("ADD  %s（exit=%d stdout=%s mem=%s cf=%v）\n", c.rel, me, ms, mm, mcf)
		added++
		cleanup(m)
	}
	if added == 0 {
		fmt.Fprintf(os.Stderr, "vm_diff --freeze-mb: 无新例可入账（%d 例均已在清单）\n", skipped)
		os.Exit(1)
	}
	data, _ := json.MarshalIndent(doc, "", "  ")
	if err := os.WriteFile(digestPath, append(data, 10), 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "vm_diff --freeze-mb: 写清单失败: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("\nvm_diff --freeze-mb: 新增 %d 例（跳过存量 %d）→ %s（正确性背书 = clang_direct + moon test；映像为白箱回归锚）\n", added, skipped, digestPath)
	return 0
}

// digestOfResultMB：mb 侧指纹（extractMoonBitStdout 提取器）。
func digestOfResultMB(r *result) (int, string, string, bool) {
	stdout := extractMoonBitStdout(r.stdout)
	memSHA := ""
	if r.memoryPath != "" {
		memSHA = memorySHA(r.memoryPath)
	}
	return r.exitCode, fmt.Sprintf("%x", sha256.Sum256([]byte(stdout)))[:16], memSHA, r.compileFail
}

// runAgainstDigest：golden 基线模式——mb 当前值 ≡ 清单登记值。
func runAgainstDigest(cases []Case) int {
	raw, err := os.ReadFile(digestPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "vm_diff[golden]: 缺清单 %s（先 --freeze）: %v\n", digestPath, err)
		os.Exit(1)
	}
	var doc digestDoc
	if err := json.Unmarshal(raw, &doc); err != nil || doc.Version != 1 {
		fmt.Fprintf(os.Stderr, "vm_diff[golden]: 清单坏或版本不识\n")
		os.Exit(1)
	}
	// 审阅 P3：golden 路径自证——--selftest 篡改**当前比对集**首例的 StdoutSHA（map 首键曾落集外例——lc_198 实测），随后比对必红
	if selftestFlag && len(cases) > 0 {
		k := cases[0].rel
		if e, ok := doc.Cases[k]; ok && e.KnownMbDigest == "" {
			e.StdoutSHA = "deadbeef12345678"
			doc.Cases[k] = e
			fmt.Println("[selftest][golden] 已篡改清单条目:", k, "——随后比对必须 FAIL")
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
		e, ok := doc.Cases[c.rel]
		if !ok {
			fmt.Fprintf(os.Stderr, "vm_diff[golden]: 清单缺例 %s——重跑 --freeze\n", c.rel)
			os.Exit(1)
		}
		if sha := srcSHAOf(c.path); sha != e.SrcSHA {
			fmt.Fprintf(os.Stderr, "vm_diff[golden]: 语料 %s 已变更而清单未重刷（%s ≠ %s）——重跑 --freeze\n", c.rel, sha, e.SrcSHA)
			os.Exit(1)
		}
		m := runMoonBit(c.path)
		me, ms, mm, mcf := digestOfResultMB(m)
		cleanup(m)
		if mcf && e.CompileFail {
			fmt.Printf("SAME  %s（双侧编译失败——等价）\n", c.rel)
			same++
			continue
		}
		whole := mbWholeDigest(me, ms, mm, mcf)
		if e.KnownMbDigest != "" {
			if whole == e.KnownMbDigest {
				fmt.Printf("DIFF-KNOWN %s（mb 分叉指纹一致；归因见 known_diffs.json）\n", c.rel)
				knownN++
			} else {
				fmt.Printf("DIFF  %s：known 分叉形状已变（登记 mb 指纹 %s 实测 %s）——重新归因后重跑 --freeze\n", c.rel, e.KnownMbDigest, whole)
				diff++
			}
			continue
		}
		if me == e.ExitCode && ms == e.StdoutSHA && mm == e.MemorySHA && mcf == e.CompileFail {
			fmt.Printf("SAME  %s\n", c.rel)
			same++
			continue
		}
		fmt.Printf("DIFF  %s：与冻结基线不符（exit %d≠%d / stdout %s≠%s / memory %s≠%s）——全文对照见 frozen-oracle-snapshot 分支\n",
			c.rel, me, e.ExitCode, ms, e.StdoutSHA, mm, e.MemorySHA)
		diff++
	}
	fmt.Printf("\nvm_diff[golden]: SAME=%d DIFF-KNOWN=%d DIFF=%d SKIP=%d（共 %d）\n",
		same, knownN, diff, skipN, same+knownN+diff+skipN)
	if diff > 0 {
		os.Exit(1)
	}
	return 0
}

func clip(s string) string {
	if len(s) > 40 {
		return s[:40] + "…"
	}
	return s
}
