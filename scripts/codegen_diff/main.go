// codegen_diff：S5 字节码生成层差分驱动（A 级产物对拍）。
//
// 用法（仓库根）：
//
//	go run ./scripts/codegen_diff <corpus_dir>              # A 级全量对拍
//	go run ./scripts/codegen_diff <corpus_dir> --baseline   # 基线期：one-sided 不计红（显式标志）
//	go run ./scripts/codegen_diff <corpus_dir> --selftest   # J9：注入差异先证红
//
// 对拍面（S5 版 A 级，勘察 §8.2 L1–L4 全量）：
//   - Rust `vitro_cli dump-compile`（CompileDump 14 键：version + CompileOutput
//     13 字段，含 export 不导出的 source_map/symbols/struct_defs/union_defs/
//     global_data_end 五项）vs MoonBit `cmd/dump_compile`（{"ok":true,"dump":
//     <同 14 键>}），双侧经归一器（scripts/internal/canonicalize，进程内调用
//     ——2026-09-22 抽库前为逐样本起进程）归一后逐字节 diff。
//   - 三条冻结（勘察 §8.2）：槽位策略 v1 逐位兼容 / 绝对 IP 跳转编码 /
//     libc 固定索引（1000/1024/1089 按名→索引比对）——本管道对 code 段
//     逐指令 diff 即三者共同的行为锚。
//
// 判定四类：
//
//	SAME          双 ok 且归一产物逐字节一致（锚绿）
//	AGREE-ERROR   双 fail 且失败层一致（lex/parse/type/gen 四层映射——
//	              Rust 按 dump-compile stderr 前缀归类，MoonBit 按 stage）
//	DIFF-ONE-SIDED 一 ok 一 fail（能力缺口——扩展批逐族收敛的目标面）
//	DIFF-CONTENT  双 ok 但产物不同（真红）
//
// exit 策略（fail loud，禁静默 default）：
//
//	DIFF-CONTENT > 0                 → exit 1（任何时候都是真红）
//	DIFF-ONE-SIDED > 0 且无 --baseline → exit 1（骨架/扩展期用 --baseline
//	                                    显式豁免 one-sided，content 红不豁免）
//	AGREE-ERROR 不计红（双侧同层拒绝是行为一致，但报告可见）
//
// selftest（J9 埋雷）：选一条"当前 SAME 且 Rust ok"的样本，Rust 侧
// code[1].operand 注入 +1 → 必须 DIFF-CONTENT 红（由绿转红的干净证红，
// 注入本就 DIFF 的样本无法归因——F3 复盘）。
//
// 槽位策略版本对账（2026-09-22 S5 收尾批 · 架构审阅 v2 A 组 #2）：
// MoonBit 侧包装层的 slot_strategy 与
// scripts/codegen_diff/slot_strategy.json 的期望值对账，不符即红
// （**空集亦红**）。**此前该字段被本驱动完全丢弃**——dump_compile 注释
// 承诺的「v2 切换时 codegen_diff 可按此分档」实测为零，属"注释声明的
// 机制未落地"。Rust 侧产物无该字段（平铺 14 键），故当前是单向对账；
// 补 Rust 字段后升级为两侧等值断言。J9 证红：把 JSON 的 expected 改为
// 非当前值 → 必红（exit 1），恢复即绿（已留痕）。
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
	"sync"

	canon "vitro/scripts/internal/canonicalize"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "用法: go run ./scripts/codegen_diff <corpus_dir> [--baseline|--freeze|--golden|--selftest]")
		os.Exit(2)
	}
	corpus, err := filepath.Abs(os.Args[1])
	if err != nil {
		fail("语料路径解析失败: %v", err)
	}
	baseline := false
	selftest := false
	for _, a := range os.Args[2:] {
		switch a {
		case "--baseline":
			baseline = true
		case "--selftest":
			selftest = true
		case "--freeze":
			freezeMode = true
		case "--freeze-mb":
			// 删区后新用例入账（2026-10-05 BUG-B 语料批）：oracle 断源，
			// 以 mb 侧产物指纹入账（见 freezeMBRun）
			freezeMBMode = true
		case "--golden":
			goldenMode = true
		default:
			fail("未知参数: %s", a)
		}
	}
	// 工序③固化（2026-10-05）：oracle 缺失自动切 golden（删区后零改动存活）
	selftestFlag = selftest
	if freezeMode && goldenMode {
		fail("--freeze 与 --golden 互斥")
	}
	if freezeMBMode && (freezeMode || goldenMode) {
		fail("--freeze-mb 与 --freeze/--golden 互斥（入账 vs 固化/比对）")
	}
	if !freezeMode && !freezeMBMode && !rustCliAlive() {
		if !goldenMode {
			fmt.Fprintln(os.Stderr, "codegen_diff: [裁判切换] oracle exe 不存在——本判定走 --golden 冻结基线（结构裁判自 oracle 切为 digest 清单；正确性主锚仍为 Clang/shadow）")
			goldenMode = true
		}
	}
	if freezeMode && !rustCliAlive() {
		fail("--freeze 需要 oracle exe（cargo build --release --bin vitro_cli）")
	}
	if freezeMBMode && rustCliAlive() {
		fail("--freeze-mb 仅删区后形态（oracle 在时应走 --freeze 双侧固化）")
	}
	rc := runCorpus(corpus, baseline, selftest)
	if rc == 0 {
		flushFreezePending()
	}
	os.Exit(rc)
}

// ---- 工序③固化：oracle 消费包装（result + stderr 双存） ----

var freezeMode, goldenMode bool

// freezeMBMode：删区后新用例入账模式（--freeze-mb；与 vm_diff --freeze-mb 同族）。
var freezeMBMode bool

// selftestFlag：golden 路径自证消费（main flag 解析后赋值——审阅 P3）。
var selftestFlag bool

const codegenGoldenRoot = "scripts/codegen_diff/golden"

func rustCliAlive() bool {
	for _, p := range []string{
		filepath.Join("native", "target", "release", "vitro_cli.exe"),
		filepath.Join("native", "target", "release", "vitro_cli"),
	} {
		if _, err := os.Stat(p); err == nil {
			return true
		}
	}
	return false
}

// oracleDumpBatch：freeze 落盘 / golden 读盘 / 默认活体。stderr 随序伴生
// （AGREE-ERROR 判定依赖），golden 双存。
func oracleDumpBatch(files []string) ([][]byte, [][]byte) {
	if freezeMode {
		// digest 清单：ok 例存 canonicalize 后 result hash；fail 例存 mb 侧
		// 失败层 stage（AGREE-ERROR 语义面的指纹化）；fork 例照存 oracle hash。
		// 比对照旧跑（freeze 即验证）。
		outs, stderrs := rustDumpBatch(files)
		doc := loadCgDigest()
		corpus := filepath.Base(filepath.Dir(files[0]))
		sec := doc.Corpora[corpus]
		if sec == nil {
			sec = &cgSec{Sources: map[string]string{}, Cases: map[string]cgDigestEntry{}}
			doc.Corpora[corpus] = sec
		}
		for i, f := range files {
			name := filepath.Base(f)
			sec.Sources[name] = cgSrcSHA(f)
			e := cgDigestEntry{}
			if outs[i] == nil {
				e.Fail = true
				e.FailStage = rustFailStage(stderrs[i], files[i])
			} else {
				e.ResultSHA = hash16(canonicalize(outs[i]))
			}
			sec.Cases[name] = e
		}
		freezePendingCg = &doc // P2-1：对拍全绿才落盘
		fmt.Printf("codegen_diff freeze[%s]: %d 例入清单 → %s\n", corpus, len(files), cgDigestFile)
		return outs, stderrs
	}
	if goldenMode {
		fail("golden 模式不走 oracleDumpBatch（runCorpus 入口已拦截到 goldenRun）")
	}
	return rustDumpBatch(files)
}

// ---- digest 清单（result hash + fail 例 stage 指纹；stderr 不入清单——
// 失败层语义由 Fail 布尔 + 现模式承担，全文兜底走 orphan 分支） ----

const cgDigestFile = "scripts/codegen_diff/golden_digest.json"

var freezePendingCg *cgDigestDoc

func flushFreezePending() {
	if freezePendingCg != nil {
		saveCgDigest(*freezePendingCg)
	}
}

type cgDigestEntry struct {
	ResultSHA string `json:"result_sha,omitempty"` // ok 例：canonicalize 后产物 sha16
	Fail      bool   `json:"fail,omitempty"`       // 失败例（失败层等价已由 freeze 时对拍验证）
	FailStage string `json:"fail_stage,omitempty"` // 失败层（lex/parse/type/gen——审阅 P3：删区后 AGREE-ERROR 层一致性锚）
}

type cgSec struct {
	Sources map[string]string        `json:"sources"`
	Cases   map[string]cgDigestEntry `json:"cases"`
}

type cgDigestDoc struct {
	Version int               `json:"version"`
	Note    string            `json:"note"`
	Corpora map[string]*cgSec `json:"corpora"`
}

func loadCgDigest() cgDigestDoc {
	d := cgDigestDoc{Version: 1, Note: "freeze 时已全量对拍（SAME/AGREE-ERROR/FORK）；golden = mb 指纹 ≡ 清单", Corpora: map[string]*cgSec{}}
	if b, err := os.ReadFile(cgDigestFile); err == nil {
		if err := json.Unmarshal(b, &d); err != nil || d.Version != 1 {
			fail("digest 清单坏或版本不识 %s", cgDigestFile)
		}
		if d.Corpora == nil {
			d.Corpora = map[string]*cgSec{}
		}
	}
	return d
}

func saveCgDigest(d cgDigestDoc) {
	data, _ := json.MarshalIndent(d, "", "  ")
	must2(os.WriteFile(cgDigestFile, append(data, 10), 0o644), "写 digest 清单")
}

func hash16(b []byte) string {
	return fmt.Sprintf("%x", sha256.Sum256(b))[:16]
}

func cgSrcSHA(f string) string {
	b, err := os.ReadFile(f)
	if err != nil {
		fail("读样本失败 %s: %v", f, err)
	}
	crlf := []byte{13, 10}
	lf := []byte{10}
	return fmt.Sprintf("%x", sha256.Sum256(bytes.ReplaceAll(b, crlf, lf)))[:8]
}

// moonRawOf：读 mb 侧 dump_compile 产物（.c.compile.json 优先，fallback .compile.json）。
func moonRawOf(moonDir, f string) []byte {
	stem := stemOf(f)
	moonRaw, err := os.ReadFile(filepath.Join(moonDir, stem+".c.compile.json"))
	if err != nil {
		moonRaw, err = os.ReadFile(filepath.Join(moonDir, stem+".compile.json"))
		if err != nil {
			fail("MoonBit 侧输出缺失: %s (%v)", stem, err)
		}
	}
	return moonRaw
}

// freezeMBRun：删区后新用例入账（2026-10-05 BUG-B 语料批建，与 vm_diff
// --freeze-mb 同族）——oracle 断源后新语料以 mb 侧产物指纹入 Cases（golden
// 比对同口径：ok 例 hash16(canonicalize(dump))）；正确性背书 = clang_direct
// （stdout/退出码 vs Clang 真值）+ moon test 锚。**mb 编译失败例拒绝入账**
// （单侧缺口会被固化为 Fail 基线掩盖——先归因：两侧编译失败例走 known/
// 人工评估）；存量例跳过不覆盖；零新例即红。
func freezeMBRun(corpus string) int {
	doc := loadCgDigest()
	corpusName := filepath.Base(corpus)
	sec := doc.Corpora[corpusName]
	if sec == nil {
		fail("清单缺语料节 %s（首建节属工序③ freeze 语义——oracle 在时全量 freeze）", corpusName)
	}
	files := listCFiles(corpus)
	if len(files) == 0 {
		fail("语料目录无 .c 文件: %s", corpus)
	}
	moonDir := moonDump(corpus)
	added, skipped := 0, 0
	for _, f := range files {
		name := filepath.Base(f)
		if _, ok := sec.Cases[name]; ok {
			skipped++
			continue
		}
		raw := moonRawOf(moonDir, f)
		mok, dump, stage, _ := parseMoonDoc(raw)
		e := cgDigestEntry{}
		if mok {
			e.ResultSHA = hash16(canonicalize(dump))
		} else {
			// mb 侧失败例入账（与 freeze 存量形态同构——如 include 族在
			// dump_compile 的存量 lex-fail 盲区）；固化的是工具现状而非
			// 正确性，单侧缺口归因走 known/人工评估，醒目提示操作者
			e.Fail = true
			e.FailStage = stage
			fmt.Printf("WARN %s: mb 侧编译失败（stage=%s）按现状入账——若属单侧缺口先归因勿固化\n", name, stage)
		}
		sec.Sources[name] = cgSrcSHA(f)
		sec.Cases[name] = e
		fmt.Printf("ADD %s\n", name)
		added++
	}
	if added == 0 {
		fail("无新例可入账（%d 例均已在清单）", skipped)
	}
	saveCgDigest(doc)
	fmt.Printf("codegen_diff --freeze-mb[%s]: 新增 %d 例（跳过存量 %d）→ %s（背书 = clang_direct + moon test）"+string(rune(10)), corpusName, added, skipped, cgDigestFile)
	return 0
}

// goldenRun：mb 指纹 ≡ 清单——ok 例 canonicalize hash 比；fail 例布尔比；
// fork 例跳过（清单存 oracle hash 仅供溯源）。

type cgSelftestEntry = cgDigestEntry

// goldenSelftestHit：--selftest 的 golden 路径自证——篡改当前节首值（ResultSHA），随后比对必红（审阅 P3）。
func goldenSelftestHit(m map[string]cgDigestEntry) {
	if !selftestFlag {
		return
	}
	for k, e := range m {
		if e.ResultSHA == "" {
			continue // fail 例无 ResultSHA（布尔比对篡不动，fail_stage 例外）
		}
		e.ResultSHA = "deadbeef00000000"
		m[k] = e
		fmt.Println("[selftest][golden] 已篡改清单条目:", k, "——随后比对必须 FAIL")
		return
	}
}

func goldenRun(corpus string) int {
	doc := loadCgDigest()
	corpusName := filepath.Base(corpus)
	sec, ok := doc.Corpora[corpusName]
	if !ok {
		fail("清单缺语料节 %s（先 --freeze）", corpusName)
	}
	goldenSelftestHit(sec.Cases)
	files := listCFiles(corpus)
	if len(files) == 0 {
		fail("语料目录无 .c 文件: %s", corpus)
	}
	for _, f := range files {
		name := filepath.Base(f)
		if sha := cgSrcSHA(f); sec.Sources[name] != sha {
			fail("语料 %s 已变更而清单未重刷（%s ≠ %s）——重跑 --freeze", name, sha, sec.Sources[name])
		}
	}
	moonDir := moonDump(corpus)
	failures, forkN, matched := 0, 0, 0
	for _, f := range files {
		name := filepath.Base(f)
		if _, isFork := knownForkFiles[name]; isFork {
			fmt.Printf("FORK(known-golden-skip) %s——有意分叉例，形状校验走现模式"+string(rune(10)), name)
			forkN++
			continue
		}
		e, ok := sec.Cases[name]
		if !ok {
			fmt.Printf("DIFF 缺失: 清单无 %s"+string(rune(10)), name)
			failures++
			continue
		}
		raw := moonRawOf(moonDir, f)
		mok, dump, _, _ := parseMoonDoc(raw)
		if e.Fail {
			if mok {
				fmt.Printf("DIFF %s: 冻结基线为编译失败，mb 现 ok——行为漂移（全文对照见 frozen-oracle-snapshot 分支）"+string(rune(10)), name)
				failures++
				continue
			}
			if _, _, mStage, _ := parseMoonDoc(raw); mStage != e.FailStage {
				fmt.Printf("DIFF %s: 失败层漂移 mb=%s ≠ 冻结 %s（AGREE-ERROR 语义面）"+string(rune(10)), name, mStage, e.FailStage)
				failures++
			} else {
				matched++
			}
			continue
		}
		if !mok {
			fmt.Printf("DIFF %s: 冻结基线 ok，mb 现编译失败（%s）——行为漂移"+string(rune(10)), name, name)
			failures++
			continue
		}
		if got := hash16(canonicalize(dump)); got != e.ResultSHA {
			fmt.Printf("DIFF %s: hash %s ≠ 清单 %s（全文对照见 frozen-oracle-snapshot 分支）"+string(rune(10)), name, got, e.ResultSHA)
			failures++
		} else {
			matched++
		}
	}
	if failures > 0 {
		fmt.Printf("codegen_diff[golden:%s]: FAIL——%d/%d 差异"+string(rune(10)), corpusName, failures, len(files))
		return 1
	}
	fmt.Printf("codegen_diff[golden:%s]: PASS——%d 指纹一致（fork 跳过 %d）"+string(rune(10)), corpusName, matched, forkN)
	return 0
}
func cgSrcSHAs(files []string) map[string]string {
	out := map[string]string{}
	for _, f := range files {
		b, err := os.ReadFile(f)
		if err != nil {
			fail("读样本失败 %s: %v", f, err)
		}
		h := sha256.Sum256(bytes.ReplaceAll(b, []byte("\r\n"), []byte("\n")))
		out[filepath.Base(f)] = fmt.Sprintf("%x", h)[:8]
	}
	return out
}

func writeCgManifest(files []string, dir string) {
	data, _ := json.MarshalIndent(map[string]any{"version": 1, "sources": cgSrcSHAs(files)}, "", "  ")
	must2(os.WriteFile(filepath.Join(dir, "_manifest.json"), append(data, '\n'), 0o644), "写 _manifest.json")
}

func verifyCgManifest(files []string, dir string) {
	data, err := os.ReadFile(filepath.Join(dir, "_manifest.json"))
	if err != nil {
		fail("缺 _manifest.json %s（先 --freeze）: %v", dir, err)
	}
	var m struct {
		Version int               `json:"version"`
		Sources map[string]string `json:"sources"`
	}
	if err := json.Unmarshal(data, &m); err != nil || m.Version != 1 {
		fail("_manifest.json 坏或版本不识 %s", dir)
	}
	cur := cgSrcSHAs(files)
	if len(cur) != len(m.Sources) {
		fail("语料已变（现 %d ≠ 落盘 %d）——重跑 --freeze：%s", len(cur), len(m.Sources), dir)
	}
	for name, sha := range m.Sources {
		if cur[name] != sha {
			fail("语料 %s 已变更而 golden 未重刷（%s ≠ %s）——重跑 --freeze", name, cur[name], sha)
		}
	}
}

func must2(err error, what string) {
	if err != nil {
		fail("%s 失败: %v", what, err)
	}
}

// knownForkFiles：parser 层已知有意分叉（S3 F3-v2 累加器裁定 b 白名单，
// 见 scripts/parser_diff / scripts/typeck_diff 同名表——根因在 parser：
// 局部函数指针/函数原型声明符 oracle 双层 Pointer(Pointer(Function)) 不符
// C 语义，MoonBit 按 C 单层）在 **codegen 消费面**的放大（symbols 的 ty
// 定型分叉连带 dump 产物）。与 typeck 侧同规则：命中降级 FORK(known)
// 报告不计失败；S8 差异台账收编时一并裁定。2026-09-21 扩展批三号首条
// CONTENT-DIFF 即此根因（code 段两侧一致，纯类型定型面分叉）。
var knownForkFiles = map[string]string{
	"function_pointer_return_ptr.c": "局部函数指针双层→C 单层（F3-v2）——codegen 消费面放大（symbols.ty）",
	"kr_5_11.c":                     "局部函数原型双层→C 单层（F3-v2）——codegen 消费面放大",
}

func runCorpus(corpus string, baseline bool, selftest bool) int {
	if freezeMBMode {
		return freezeMBRun(corpus)
	}
	if goldenMode {
		return goldenRun(corpus)
	}
	files := listCFiles(corpus)
	if len(files) == 0 {
		fail("语料目录无 .c 文件: %s", corpus)
	}
	rustOuts, rustStderrs := oracleDumpBatch(files)
	moonDir := moonDump(corpus)
	// 归一化：Rust 全文件；MoonBit 抽 .dump（ok=false 保留原文件形态参与
	// stage 判定）
	type side struct {
		ok   bool
		dump []byte // ok=true 时为 14 键 dump 的归一形态
		aggr string // ok=false 时的失败层（lex/parse/type/gen）
	}
	sides := make([][2]side, len(files))
	moonSlots := map[int]int{} // 槽位策略版本 → 成功样本数（-1 = 字段缺失）
	for i, f := range files {
		stem := stemOf(f)
		moonRaw, err := os.ReadFile(filepath.Join(moonDir, stem+".c.compile.json"))
		if err != nil {
			moonRaw, err = os.ReadFile(filepath.Join(moonDir, stem+".compile.json"))
			if err != nil {
				fail("MoonBit 侧输出缺失: %s (%v)", stem, err)
			}
		}
		rustOK := len(rustOuts[i]) > 0
		moonOK, moonDumpRaw, moonStage, moonSlot := parseMoonDoc(moonRaw)
		if moonOK {
			moonSlots[moonSlot]++
		}
		sides[i][0] = side{rustOK, nil, ""}
		if rustOK {
			sides[i][0].dump = canonicalize(rustOuts[i])
		}
		sides[i][1] = side{moonOK, nil, moonStage}
		if moonOK {
			sides[i][1].dump = canonicalize(moonDumpRaw)
		}
	}
	injectIdx := -1
	if selftest {
		for i := range files {
			if sides[i][0].ok && sides[i][1].ok && bytes.Equal(sides[i][0].dump, sides[i][1].dump) {
				rustOuts[i] = selftestInject(rustOuts[i])
				sides[i][0].dump = canonicalize(rustOuts[i])
				injectIdx = i
				fmt.Printf("codegen_diff: selftest 已注入差异（样本 %s 当前 SAME，Rust 侧 code[1].operand +1）\n",
					filepath.Base(files[i]))
				break
			}
		}
		if injectIdx < 0 {
			fail("selftest 语料无『当前 SAME 且双 ok』样本——由绿转红的干净证红无从建立")
		}
	}
	nSame, nAgree, nOneSided, nContent := 0, 0, 0, 0
	injectRed := false
	for i, f := range files {
		r, m := sides[i][0], sides[i][1]
		switch {
		case r.ok && m.ok:
			if bytes.Equal(r.dump, m.dump) {
				nSame++
			} else {
				// parser 层已知分叉在 codegen 消费面的放大（白名单与
				// typeck_diff 同源）——降级 FORK 报告不计失败
				if reason, ok := knownForkFiles[filepath.Base(f)]; ok {
					fmt.Printf("FORK(known) %s——%s\n", filepath.Base(f), reason)
					continue
				}
				nContent++
				fmt.Printf("DIFF-CONTENT %s\n  rust: %s\n  moon: %s\n", filepath.Base(f),
					preview(r.dump), preview(m.dump))
				if i == injectIdx {
					injectRed = true
				}
			}
		case !r.ok && !m.ok:
			// 双 fail：MoonBit stage vs Rust stderr 归类（dump 不可得，层一致
			// 即行为一致——诊断文本不同源不比）
			rStage := rustFailStage(rustStderrs[i], files[i])
			if rStage == m.aggr {
				nAgree++
			} else {
				// 层不同：一侧在更早层失败——按 content 级红处理（行为分叉）
				nContent++
				fmt.Printf("DIFF-STAGE %s：rust=%s moon=%s\n", filepath.Base(f), rStage, m.aggr)
			}
		default:
			nOneSided++
			which := "rust-ok/moon-fail"
			if !r.ok {
				which = "rust-fail/moon-ok"
			}
			fmt.Printf("DIFF-ONE-SIDED %s（%s）\n", filepath.Base(f), which)
		}
	}
	if selftest && !injectRed {
		fail("selftest 未证红——注入样本 %s 未判 DIFF-CONTENT，锚失效", filepath.Base(files[injectIdx]))
	}
	slotOK := checkSlotStrategy(moonSlots)
	fmt.Printf("codegen_diff: SAME=%d AGREE-ERROR=%d ONE-SIDED=%d CONTENT-DIFF=%d（语料 %s, %d 文件）\n",
		nSame, nAgree, nOneSided, nContent, corpus, len(files))
	if nContent > 0 {
		fmt.Println("codegen_diff: FAIL——产物层差异（真红）")
		return 1
	}
	if nOneSided > 0 && !baseline {
		fmt.Println("codegen_diff: FAIL——能力缺口（one-sided）未豁免；基线期可显式 --baseline")
		return 1
	}
	if !slotOK {
		fmt.Println("codegen_diff: FAIL——槽位策略版本未过闸（见上方 slot_strategy 行）")
		return 1
	}
	fmt.Println("codegen_diff: PASS")
	return 0
}

// rustDumpBatch：逐文件 `vitro_cli dump-compile`（并行，每文件一进程）。
// 失败返回 nil（层归类走 stderr，由 rustFailStage 读取）。
//
// P1-1（审阅修复）：此前 os.CreateTemp 预创建 + 子进程覆写的握手在
// Windows 偶发 os error 5（拒绝访问——句柄关闭竞态/杀毒瞬时锁），导致
// 同语料同二进制判定不确定（批跑 rust-fail、单跑 rust-ok）。改为：
// 输出路径不预创建（子进程独占创建）+ error 5 重试一次；失败判定以
// **产物文件是否存在**为准（exit 0 必有文件、exit≠0 无文件）。
// 返回 (产物, stderr)：失败样本的 stderr 随序返回供 rustFailStage 查表
// 归类（2026-09-21 审阅修复：此前批量已捕获却丢弃、逐例重跑 CLI）。
func rustDumpBatch(files []string) ([][]byte, [][]byte) {
	cli := rustCli()
	outs := make([][]byte, len(files))
	stderrs := make([][]byte, len(files))
	outDir, err := os.MkdirTemp("", "codegen_rust_out_*")
	if err != nil {
		fail("临时目录失败: %v", err)
	}
	defer os.RemoveAll(outDir)
	var wg sync.WaitGroup
	sem := make(chan struct{}, 8)
	for i, f := range files {
		wg.Add(1)
		go func(i int, f string) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			outPath := filepath.Join(outDir, fmt.Sprintf("%d.json", i))
			var lastStderr []byte
			for attempt := 0; attempt < 2; attempt++ {
				cmd := exec.Command(cli, "dump-compile", f, "-o", outPath)
				var stderr bytes.Buffer
				cmd.Stderr = &stderr
				err := cmd.Run()
				lastStderr = stderr.Bytes()
				if err == nil {
					break
				}
				if attempt == 0 && bytes.Contains(lastStderr, []byte("拒绝访问")) {
					continue // error 5 瞬态：重试一次
				}
				break
			}
			data, readErr := os.ReadFile(outPath)
			if readErr != nil || len(data) == 0 {
				outs[i] = nil // 编译失败（无产物）；层归类走查表
				stderrs[i] = lastStderr
				return
			}
			outs[i] = data
		}(i, f)
	}
	wg.Wait()
	return outs, stderrs
}

// rustFailStage：Rust 侧失败层归类（dump-compile stderr 前缀——与
// cmd_dump_compile 的 eprintln 文本耦合，文本变更须同步此处）。
// stderr 由 rustDumpBatch 随序伴生返回，查表不重跑（2026-09-21 审阅
// 修复：.err 伴生文件方案已废弃——死码且泄漏 %TEMP）。
func rustFailStage(stderrRaw []byte, f string) string {
	s := string(stderrRaw)
	for _, p := range [][2]string{
		{"词法错误", "lex"},
		{"语法错误", "parse"},
		{"类型错误", "type"},
		{"生成错误", "gen"},
	} {
		if strings.Contains(s, p[0]) {
			return p[1]
		}
	}
	// P1-1：基础设施错误（拒绝访问/找不到二进制等）不是语料属性。
	// 〔2026-09-21 审阅降级〕fail 会把单文件异常升级成整轮 abort——批量
	// 判定可用性缺陷。改返回哨兵 stage "infra"：该文件计 DIFF-STAGE 红
	// （与 MoonBit stage 永不相等）、其余文件继续判定，不再吞整轮证据；
	// 真基础设施故障由多数文件齐红 + 人工看 stderr 暴露。
	return "infra"
}

// parseMoonDoc：解析 MoonBit 侧输出——ok 与 .dump 原始字节与失败 stage。
// **必须走 json.RawMessage**：map[string]any 往返会把 u64 位模式
// （globals_init_64 第二元，> 2^53）重编为 float64 最短十进制（末位漂移，
// 实测 4609434218613702656 → 4609434218613702700）——产物字节失真。
func parseMoonDoc(raw []byte) (bool, []byte, string, int) {
	var doc struct {
		OK           bool            `json:"ok"`
		Stage        string          `json:"stage"`
		SlotStrategy *int            `json:"slot_strategy"`
		Dump         json.RawMessage `json:"dump"`
	}
	if err := json.Unmarshal(raw, &doc); err != nil {
		fail("MoonBit 输出解析失败: %v (%s)", err, preview(raw))
	}
	if !doc.OK {
		return false, nil, doc.Stage, -1
	}
	slot := -1
	if doc.SlotStrategy != nil {
		slot = *doc.SlotStrategy
	}
	return true, doc.Dump, "", slot
}

// selftestInject：Rust 侧产物 code[1].operand +1。RawMessage 分段重组——
// 只有 code[1] 一条经解码重编（operand 是跳转 IP/立即数，值域远小于
// 2^53，float64 安全），其余字段保留原始字节（大整数文本不失真——
// 见 parseMoonDoc 的 RawMessage 理由）。
func selftestInject(raw []byte) []byte {
	var doc map[string]json.RawMessage
	if err := json.Unmarshal(raw, &doc); err != nil {
		fail("selftest 注入解析失败: %v", err)
	}
	var code []json.RawMessage
	if err := json.Unmarshal(doc["code"], &code); err != nil {
		fail("selftest 注入失败：code 段解析失败: %v", err)
	}
	if len(code) < 2 {
		fail("selftest 注入失败：code 段不足 2 条")
	}
	var ins map[string]any
	if err := json.Unmarshal(code[1], &ins); err != nil {
		fail("selftest 注入失败：code[1] 解析失败: %v", err)
	}
	operand, ok := ins["operand"].(float64)
	if !ok {
		fail("selftest 注入失败：code[1].operand 非数值")
	}
	ins["operand"] = operand + 1
	reIns, err := json.Marshal(ins)
	if err != nil {
		fail("selftest 注入重序列化失败: %v", err)
	}
	code[1] = reIns
	reCode, err := json.Marshal(code)
	if err != nil {
		fail("selftest 注入 code 重序列化失败: %v", err)
	}
	doc["code"] = reCode
	re, err := json.Marshal(doc)
	if err != nil {
		fail("selftest 注入顶层重序列化失败: %v", err)
	}
	return re
}

// ---------------------------------------------------------------------------
// 槽位策略版本对账（S5 收尾批 · 架构审阅 v2 A 组 #2）
// ---------------------------------------------------------------------------

// slotRulesPath：期望值外置（规则与代码分离——本仓判定型脚本纪律）。
const slotRulesPath = "scripts/codegen_diff/slot_strategy.json"

type slotRules struct {
	Schema   int `json:"schema"`
	Expected int `json:"expected"`
}

func loadSlotExpect() slotRules {
	raw, err := os.ReadFile(slotRulesPath)
	if err != nil {
		fail("读槽位策略期望失败（须在仓库根运行）: %v", err)
	}
	var r slotRules
	if err := json.Unmarshal(raw, &r); err != nil {
		fail("槽位策略期望解析失败: %v", err)
	}
	if r.Schema != 1 {
		fail("槽位策略期望 schema 不支持: %d（期望 1）", r.Schema)
	}
	return r
}

// checkSlotStrategy：MoonBit 侧产物包装层 slot_strategy 与期望值对账。
//
// 为什么需要它：cmd/dump_compile 自 S5 开工批起就在包装层携带该字段，其
// 注释承诺「对拍面只取 .dump，本字段不参与 14 键比对，v2 切换时
// codegen_diff 可按此分档」——但本驱动此前把外层整个丢弃，**该承诺实测
// 为零**（S5 收尾批复核，2026-09-22）。本检查把「槽位策略版本」变成机判
// 事件：策略变更（v1→v2）必须显式改 slot_strategy.json 过闸，否则红。
//
// 诚实边界：Rust 侧产物无该字段（平铺 14 键），故只能单向对账期望值，
// 不能断言两侧等值——补 Rust 字段后本检查可升级（见 slot_strategy.json
// 的 _rust_side_gap）。**空集不得绿**：所有成功样本都缺该字段即判红
// （出口协议变更不得静默通过）。
func checkSlotStrategy(seen map[int]int) bool {
	expect := loadSlotExpect().Expected
	nTotal := 0
	for _, c := range seen {
		nTotal += c
	}
	if nTotal == 0 {
		fmt.Println("codegen_diff: slot_strategy=FAIL——无任何成功样本携带外层字段可供对账")
		return false
	}
	var parts []string
	ok := true
	for v, c := range seen {
		tag := fmt.Sprintf("%d×%d", v, c)
		if v != expect {
			tag += "(≠期望)"
			ok = false
		}
		parts = append(parts, tag)
	}
	sort.Strings(parts)
	fmt.Printf("codegen_diff: slot_strategy=%s（期望 %d；Rust 侧无该字段，见 slot_strategy.json）\n",
		strings.Join(parts, ", "), expect)
	if !ok {
		fmt.Println("codegen_diff:   槽位策略已变更——须同步 codegen 包 SLOT_STRATEGY_VERSION、本 JSON，并重跑全量 A 级对拍（v2 前提见 JSON 的 _v2_plan）")
	}
	return ok
}

// ---------------------------------------------------------------------------
// 基础设施（与 typeck_diff 同款，独立复制避免跨脚本依赖）
// ---------------------------------------------------------------------------

var (
	rustCliOnce sync.Once
	rustCliPath string
)

// canonicalize：本地包装（fail loud 口径与抽库前一致——归一失败即拒绝给
// 判定）。归一逻辑单源在 scripts/internal/canonicalize。
//
// 2026-09-22 抽库改造：原实现每次调用都 exec.Command 起一个新进程，旧 CLI
// 单次实测 **224.6ms**（那基本就是进程创建成本）；进程内单次实测
// **4.6ms / 225KB 载荷**。本驱动**每文件调 2 次**（Rust 侧 + MoonBit 侧，见
// sides 装配处）；CI 五条调用合起来 = 四语料 600（baseline 365 + knr 81 +
// leetcode 138 + gap 16）+ 骨架 13 = **613 文件 → 1226 次进程创建**。
//
// 口径：改造省下的是这 1226 次**进程创建**，不是"归零"——进程内仍有
// ~4.6ms/次。判定语义不变（锚逐字节，SAME/AGREE-ERROR/ONE-SIDED/CONTENT-DIFF
// 四类计数均未变）。
func canonicalize(raw []byte) []byte {
	out, err := canon.Bytes(raw)
	if err != nil {
		fail("canonicalize 失败: %v\ninput: %s", err, preview(raw))
	}
	return out
}

func rustCli() string {
	rustCliOnce.Do(func() {
		for _, p := range []string{
			"native/target/release/vitro_cli.exe",
			"native/target/release/vitro_cli",
		} {
			if _, err := os.Stat(p); err == nil {
				rustCliPath = p
				return
			}
		}
		fail("未找到 vitro_cli release 二进制（native/target/release/）——先 cargo build --release --bin vitro_cli")
	})
	return rustCliPath
}

func moonDump(corpus string) string {
	out, err := os.MkdirTemp("", "codegen_moon_*")
	if err != nil {
		fail("临时目录失败: %v", err)
	}
	cmd := exec.Command("moon", "run", "--target", "native", "cmd/dump_compile", "--", corpus, out)
	cmd.Dir = "moonbit"
	var buf bytes.Buffer
	cmd.Stdout = &buf
	cmd.Stderr = &buf
	if err := cmd.Run(); err != nil {
		fail("moon run cmd/dump_compile 失败: %v\n%s", err, buf.String())
	}
	return out
}

func listCFiles(dir string) []string {
	entries, err := os.ReadDir(dir)
	if err != nil {
		fail("读语料目录失败: %v (%s)", err, dir)
	}
	var files []string
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), ".c") {
			files = append(files, filepath.Join(dir, e.Name()))
		}
	}
	sort.Strings(files)
	return files
}

func stemOf(path string) string {
	base := filepath.Base(path)
	return strings.TrimSuffix(base, ".c")
}

func preview(b []byte) string {
	s := string(b)
	if len(s) > 120 {
		return s[:120] + "…"
	}
	return s
}

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "codegen_diff: "+format+"\n", args...)
	os.Exit(2)
}
