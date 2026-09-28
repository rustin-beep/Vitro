// vendor_drift：vendored 上游依赖漂移探针（唯一依赖清除 B 路线批，2026-09-28）。
//
// 用法（仓库根）：
//
//	go run ./scripts/moonbit/vendor_drift                    # 比对上游 main vs 基线
//	go run ./scripts/moonbit/vendor_drift --update-baseline  # 拉上游 main 现状重建基线（人工评估跟进后）
//	go run ./scripts/moonbit/vendor_drift -baseline <file>   # J9：在基线副本上篡改证红
//
// 背景：vitro/engine 的 fs 实现 vendored 自 moonbitlang/x@0.5.5（文件级搬迁 +
// 符号前缀/pub 收窄/内联 utf8 三项机械改造，见 moonbit/fs/ 文件头标注）。
// 上游是活仓库，且实测发生过「内容已漂移而 version 未 bump」（fs_native.mbt
// 的 unicode→core/utf8 迁移，2026-09-27 实测：上游 sha 已变、moon.mod 仍
// 0.5.5）——只盯版本号的探针在该案例零报警，故本探针主口径走**文件内容哈希**。
//
// 双层口径：
//
//	层 1（主口径）内容哈希：拉上游 main 被跟踪文件的 sha256 与基线比对；
//	     不等 / 404（删移=结构变更）→ 漂移。
//	层 2（辅助）版本号：上游 moon.mod 的 version 与基线记录比对；
//	     仅报告不单独判红（版本号口径漏报已实证）。
//
// 退出码契约（fail loud，禁静默 default）：
//
//	0 = 上游与基线一致
//	1 = 漂移——红 = 评估令，非自动同步令（人工裁定后手工同步 vendored 文件、
//	    跑全量防线、--update-baseline、CHANGELOG 留痕；流程见
//	    docs/current/01-定位与路线/唯一依赖清除路线.md §3B-4）
//	2 = 无法判定（网络失败/超时/非 404 异常状态码/基线损坏）——与漂移区分，
//	    避免把网络抖动误报成上游变更（检测机制自己不能成为假绿/假红源头）
//
// 纪律：零第三方依赖；基线外置 JSON（scripts/moonbit/vendor_baseline.json，
// 规则与数据分离）；形态对齐 toolchain_probe（--update-baseline 迁移式基线）。
// 环境变量 VENDOR_DRIFT_RAW_BASE 可覆盖 raw 域名（默认
// raw.githubusercontent.com；J9 假域名证 exit 2 与镜像场景共用）。
package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"regexp"
	"strings"
	"time"
)

const defaultRawBase = "https://raw.githubusercontent.com"

const trackedModule = "moonbitlang/x" // 基线 repo 字段必须一致（防基线张冠李戴）
const trackedRef = "main"             // 跟踪上游 main（非版本 tag：漂移要在发版前暴露）

// baseline 基线 JSON 形态（scripts/moonbit/vendor_baseline.json）。
type baseline struct {
	GeneratedBy     string      `json:"_generated_by"`
	AsOf            string      `json:"as_of"`
	Repo            string      `json:"repo"`
	Ref             string      `json:"ref"`
	UpstreamVersion string      `json:"upstream_version"`
	VersionNote     string      `json:"version_note"`
	Files           []fileEntry `json:"files"`
}

type fileEntry struct {
	Path     string `json:"path"`     // 上游仓库内路径（raw URL 后缀）
	Sha256   string `json:"sha256"`   // 上游 main 该文件内容的 sha256（hex）
	Vendored string `json:"vendored"` // 对应本仓 vendored 文件（元数据：跟进流程定位用，探针不校验其存在）
}

// driftResult 单文件比对结论。
type driftResult struct {
	entry  fileEntry
	status fetchStatus
	actual string // 实测 sha256（可判定时）
	note   string
}

func main() {
	update := flag.Bool("update-baseline", false, "拉上游 main 现状重建基线（人工评估跟进后使用）")
	baselinePath := flag.String("baseline", "scripts/moonbit/vendor_baseline.json", "基线 JSON 路径（J9 可指向副本）")
	flag.Parse()

	rawBase := os.Getenv("VENDOR_DRIFT_RAW_BASE")
	if rawBase == "" {
		rawBase = defaultRawBase
	}
	client := &http.Client{Timeout: 30 * time.Second}

	if *update {
		if err := updateBaseline(client, rawBase, *baselinePath); err != nil {
			fatal("基线更新失败: %v", err)
		}
		return
	}

	if err := check(client, rawBase, *baselinePath); err != nil {
		// 退出码语义在 error 文本里约定：漂移（exit 1）与无法判定（exit 2）。
		if de, ok := err.(driftError); ok {
			fmt.Fprintf(os.Stderr, "vendor_drift: FAIL——上游漂移（%d 处）：\n%s\n", de.count, de.details)
			fmt.Fprintln(os.Stderr, "处置：读 diff 评估（无关/有利/有害）→ 跟进则手工同步 vendored 文件 + 全量防线 + --update-baseline；见 唯一依赖清除路线.md §3B-4")
			os.Exit(1)
		}
		fatal("无法判定: %v", err)
	}
	fmt.Println("vendor_drift: PASS（上游 moonbitlang/x main 与基线一致）")
}

type driftError struct {
	count   int
	details string
}

func (d driftError) Error() string {
	return fmt.Sprintf("漂移 %d 处:\n%s", d.count, d.details)
}

// check：层 1 内容哈希（判红）+ 层 2 版本号（仅报告）。
func check(client *http.Client, rawBase, baselinePath string) error {
	bl, err := loadBaseline(baselinePath)
	if err != nil {
		return err
	}
	if len(bl.Files) == 0 {
		return fmt.Errorf("基线 files 为空（空集不得绿）: %s", baselinePath)
	}
	var drifts []string
	for _, f := range bl.Files {
		body, st, ferr := fetch(client, rawBase, bl.Repo, bl.Ref, f.Path)
		if ferr != nil {
			return ferr // 网络/超时/异常状态码 → 无法判定
		}
		if st == statusNotFound {
			drifts = append(drifts, fmt.Sprintf("  %s: 404（上游删移=结构变更）", f.Path))
			continue
		}
		actual := sha256Hex(body)
		if actual != f.Sha256 {
			drifts = append(drifts, fmt.Sprintf("  %s: 哈希不等\n    基线: %s\n    实测: %s", f.Path, f.Sha256, actual))
		} else {
			fmt.Printf("[绿] %s（sha256 一致）\n", f.Path)
		}
	}
	// 层 2：版本号仅报告（1.3 实证内容变而 version 不 bump 的漏报形态）。
	if body, st, err := fetch(client, rawBase, bl.Repo, bl.Ref, "moon.mod"); err == nil && st == statusOK {
		if v := parseVersion(string(body)); v != "" && v != bl.UpstreamVersion {
			fmt.Printf("[报告·不判红] 上游版本号 %s → %s（内容哈希是主口径，见基线 version_note）\n", bl.UpstreamVersion, v)
		}
	}
	if len(drifts) > 0 {
		return driftError{count: len(drifts), details: strings.Join(drifts, "\n")}
	}
	return nil
}

// updateBaseline：拉上游全部被跟踪文件 + moon.mod 版本号，重建基线。
// 语义：把「当前上游状态」登记为已评估基线——调用前提是人工已完成
// 评估/跟进（vendored 文件已是想要的形态），不是自动同步令。
func updateBaseline(client *http.Client, rawBase, baselinePath string) error {
	bl, err := loadBaseline(baselinePath)
	if err != nil {
		return err
	}
	today := time.Now().Format("2006-01-02")
	for i, f := range bl.Files {
		body, st, ferr := fetch(client, rawBase, bl.Repo, bl.Ref, f.Path)
		if ferr != nil {
			return ferr
		}
		if st != statusOK {
			return fmt.Errorf("拉取 %s 状态 %d（非 200，基线不更新）", f.Path, st)
		}
		bl.Files[i].Sha256 = sha256Hex(body)
		fmt.Printf("[更新] %s → %s\n", f.Path, bl.Files[i].Sha256)
	}
	if body, st, err := fetch(client, rawBase, bl.Repo, bl.Ref, "moon.mod"); err == nil && st == statusOK {
		if v := parseVersion(string(body)); v != "" {
			if v != bl.UpstreamVersion {
				fmt.Printf("[更新] 上游版本号 %s → %s\n", bl.UpstreamVersion, v)
			}
			bl.UpstreamVersion = v
		}
	}
	bl.AsOf = today
	bl.GeneratedBy = "go run ./scripts/moonbit/vendor_drift --update-baseline"
	out, err := json.MarshalIndent(bl, "", "  ")
	if err != nil {
		return err
	}
	if werr := os.WriteFile(baselinePath, append(out, '\n'), 0o644); werr != nil {
		return werr
	}
	fmt.Printf("vendor_drift: 基线已更新 → %s（as_of %s）\n", baselinePath, today)
	return nil
}

func loadBaseline(path string) (*baseline, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("基线缺失/不可读 %s（首建参照 README 手工落基线后 --update-baseline）: %w", path, err)
	}
	var bl baseline
	if err := json.Unmarshal(raw, &bl); err != nil {
		return nil, fmt.Errorf("基线 JSON 损坏 %s: %w", path, err)
	}
	if bl.Repo != trackedModule {
		return nil, fmt.Errorf("基线 repo=%q 与探针跟踪对象 %q 不符（基线张冠李戴，拒绝判定）", bl.Repo, trackedModule)
	}
	if bl.Ref != trackedRef {
		return nil, fmt.Errorf("基线 ref=%q 与探针跟踪引用 %q 不符（口径变更须同步改探针常量）", bl.Ref, trackedRef)
	}
	if len(bl.Files) == 0 {
		return nil, fmt.Errorf("基线 files 为空: %s", path)
	}
	for _, f := range bl.Files {
		if f.Path == "" || f.Sha256 == "" {
			return nil, fmt.Errorf("基线条目缺 path/sha256: %#v", f)
		}
	}
	return &bl, nil
}

type fetchStatus int

const (
	statusOK fetchStatus = iota
	statusNotFound
	statusOther
)

// fetch 拉上游 raw 文件。错误三分类：网络错误（返 error→无法判定）、
// 404（statusNotFound→漂移：删移=结构变更）、其余非 200（statusOther，
// 本实现归无法判定——5xx 抖动不应当成上游变更）。
func fetch(client *http.Client, rawBase, repo, ref, path string) ([]byte, fetchStatus, error) {
	url := fmt.Sprintf("%s/%s/%s/%s", strings.TrimSuffix(rawBase, "/"), repo, ref, path)
	resp, err := client.Get(url)
	if err != nil {
		return nil, statusOther, fmt.Errorf("网络失败（%s）: %w", url, err)
	}
	defer resp.Body.Close()
	switch {
	case resp.StatusCode == http.StatusOK:
	case resp.StatusCode == http.StatusNotFound:
		return nil, statusNotFound, nil
	default:
		return nil, statusOther, fmt.Errorf("异常状态码 %d（%s）——非 404 的失败不判漂移", resp.StatusCode, url)
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, statusOther, fmt.Errorf("读响应体失败（%s）: %w", url, err)
	}
	return body, statusOK, nil
}

func sha256Hex(b []byte) string {
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:])
}

var reVersion = regexp.MustCompile(`(?m)^version\s*=\s*"([^"]+)"`)

// parseVersion 解析上游 moon.mod 的 version 字段（层 2 辅助口径）。
func parseVersion(mod string) string {
	if m := reVersion.FindStringSubmatch(mod); m != nil {
		return m[1]
	}
	return ""
}

func fatal(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "vendor_drift: "+format+"\n", args...)
	os.Exit(2)
}
