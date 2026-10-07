package main

// 图标几何层生成器 —— 产出 moonbit/icons/icons.json（供 MAUI / MoonBit / 自绘方取 `d` 数据）。
//
// 真源是手写的 moonbit/icons/<id>.svg（逐个编辑），本脚本**只读真源、只产几何层**，
// 不反向改写 svg。demo 侧的内联表（demo/js/icons.ts）由 -demo 额外产出。
//
// 用法（flag 必须写在任何位置参数之前）：
//
//	go run ./scripts/gen_icons            # 生成 moonbit/icons/icons.json
//	go run ./scripts/gen_icons -check     # 只校验：现有 json 与重算结果是否一致（不改文件）
//	go run ./scripts/gen_icons -demo      # 额外产出 demo/js/icons.ts
//
// 幂等：icon 键按字典序输出（Go json 对 map 键排序）、行尾固定 LF、圆/矩形坐标用
// 最短往返浮点格式化 ⇒ 双次运行字节一致。-check 完全不落盘（不碰 mtime）。
//
// 退出码：0 成功（含 -check 一致）/ 1 不一致或写出失败 / 2 用法或环境错（fail loud）。

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

type Rules struct {
	AssetsDir      string            `json:"assets_dir"`
	IndexTsv       string            `json:"index_tsv"`
	GeometryJSON   string            `json:"geometry_json"`
	IconsMbt       string            `json:"icons_mbt"`
	DemoTs         string            `json:"demo_ts"`
	SvgAttrs       map[string]string `json:"svg_attrs"`
	GeometrySchema string            `json:"geometry_schema"`
	ScaleFormula   string            `json:"scale_formula"`
}

type IconEntry struct {
	Title    string   `json:"title"`
	Category string   `json:"category"`
	Scope    string   `json:"scope"`
	Paths    []string `json:"paths"`
}

type Geometry struct {
	Schema         string               `json:"schema"`
	Digest         string               `json:"digest"`
	ViewBox        string               `json:"viewBox"`
	StrokeWidth    float64              `json:"stroke_width"`
	StrokeLinecap  string               `json:"stroke_linecap"`
	StrokeLinejoin string               `json:"stroke_linejoin"`
	Fill           string               `json:"fill"`
	ScaleFormula   string               `json:"scale_formula"`
	Icons          map[string]IconEntry `json:"icons"`
}

var (
	elemRe  = regexp.MustCompile(`(?s)<(path|circle|rect)\b([^>]*?)/?>`)
	attrRe  = regexp.MustCompile(`([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*"([^"]*)"`)
	titleRe = regexp.MustCompile(`(?s)<title>(.*?)</title>`)
	descRe  = regexp.MustCompile(`(?s)<desc>(.*?)</desc>`)
	numRe   = regexp.MustCompile(`^-?[0-9.]+$`)
)

func main() {
	doCheck := flag.Bool("check", false, "只校验现有几何层与重算一致（不落盘）")
	doDemo := flag.Bool("demo", false, "额外产出 demo/js/icons.ts")
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "用法：go run ./scripts/gen_icons [-check] [-demo]\n")
		flag.PrintDefaults()
	}
	flag.Parse()

	rulesPath := "scripts/icon_catalog/rules.json"
	raw, err := os.ReadFile(rulesPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "FATAL: 读不到规则文件 %s：%v\n", rulesPath, err)
		os.Exit(2)
	}
	var rules Rules
	if err := json.Unmarshal(raw, &rules); err != nil {
		fmt.Fprintf(os.Stderr, "FATAL: 规则文件解析失败：%v\n", err)
		os.Exit(2)
	}
	if rules.AssetsDir == "" || rules.GeometryJSON == "" {
		fmt.Fprintf(os.Stderr, "FATAL: 规则缺 assets_dir / geometry_json（fail loud）\n")
		os.Exit(2)
	}

	// 元信息（category / scope / emoji / desc）来自 index.tsv
	meta, terr := readTsv(rules.IndexTsv)
	if terr != nil {
		fmt.Fprintf(os.Stderr, "FATAL: index.tsv: %v\n", terr)
		os.Exit(2)
	}

	entries, err := os.ReadDir(rules.AssetsDir)
	if err != nil {
		fmt.Fprintf(os.Stderr, "FATAL: 读不到资产目录 %s：%v\n", rules.AssetsDir, err)
		os.Exit(2)
	}
	ids := []string{}
	byID := map[string][]byte{}
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".svg") {
			continue
		}
		id := strings.TrimSuffix(e.Name(), ".svg")
		b, rerr := os.ReadFile(filepath.Join(rules.AssetsDir, e.Name()))
		if rerr != nil {
			fmt.Fprintf(os.Stderr, "FATAL: 读取 %s 失败：%v\n", e.Name(), rerr)
			os.Exit(2)
		}
		ids = append(ids, id)
		byID[id] = b
	}
	sort.Strings(ids)

	geo := Geometry{
		Schema:         rules.GeometrySchema,
		ViewBox:        rules.SvgAttrs["viewBox"],
		StrokeWidth:    mustFloat(rules.SvgAttrs["stroke-width"]),
		StrokeLinecap:  rules.SvgAttrs["stroke-linecap"],
		StrokeLinejoin: rules.SvgAttrs["stroke-linejoin"],
		Fill:           rules.SvgAttrs["fill"],
		ScaleFormula:   rules.ScaleFormula,
		Icons:          map[string]IconEntry{},
	}
	for _, id := range ids {
		text := string(byID[id])
		paths, perr := extractPaths(text)
		if perr != nil {
			fmt.Fprintf(os.Stderr, "FATAL: %s.svg 图元解析失败：%v\n", id, perr)
			os.Exit(2)
		}
		if len(paths) == 0 {
			fmt.Fprintf(os.Stderr, "FATAL: %s.svg 没有可用图元\n", id)
			os.Exit(2)
		}
		title := ""
		if m := titleRe.FindStringSubmatch(text); m != nil {
			title = strings.TrimSpace(m[1])
		}
		e := IconEntry{Title: title, Paths: paths}
		if m, ok := meta[id]; ok {
			e.Category, e.Scope = m[0], m[1]
		}
		geo.Icons[id] = e
	}
	geo.Digest = digestOf(ids, byID)

	out, err := marshalGeo(geo)
	if err != nil {
		fmt.Fprintf(os.Stderr, "FATAL: 序列化失败：%v\n", err)
		os.Exit(2)
	}

	if *doCheck {
		cur, rerr := os.ReadFile(rules.GeometryJSON)
		if rerr != nil {
			fmt.Fprintf(os.Stderr, "FAIL: 几何层缺失 %s：%v\n", rules.GeometryJSON, rerr)
			os.Exit(1)
		}
		if !bytes.Equal(cur, out) {
			fmt.Fprintf(os.Stderr, "FAIL: 几何层与真源不一致（%d B vs %d B），跑 go run ./scripts/gen_icons 同步\n",
				len(cur), len(out))
			os.Exit(1)
		}
		// icons_gen.mbt（MoonBit 数据单源）与重算一致——gen_diag 同款
		// 「写盘→moon fmt→归一比对→不一致还原」模式（fmt 与 gen 互踩的
		// 既定解法：最终形态一律以 moon fmt 输出为准，gen 原始输出是中间态）
		if rules.IconsMbt != "" {
			curMbt, rmErr := os.ReadFile(rules.IconsMbt)
			if rmErr != nil {
				fmt.Fprintf(os.Stderr, "FAIL: icons_gen.mbt 缺失 %s：%v（跑 gen_icons 生成）\n", rules.IconsMbt, rmErr)
				os.Exit(1)
			}
			if werr := writeIconsMbt(rules.IconsMbt, ids, geo.Icons, geo.Digest, rules.SvgAttrs); werr != nil {
				fmt.Fprintf(os.Stderr, "FAIL: icons_gen.mbt 写盘失败：%v\n", werr)
				os.Exit(1)
			}
			nowMbt, nErr := os.ReadFile(rules.IconsMbt)
			if nErr != nil {
				fmt.Fprintf(os.Stderr, "FAIL: icons_gen.mbt 回读失败：%v\n", nErr)
				os.Exit(1)
			}
			nowLF := bytes.ReplaceAll(nowMbt, []byte{13, 10}, []byte{10})
			curLF := bytes.ReplaceAll(curMbt, []byte{13, 10}, []byte{10})
			if !bytes.Equal(nowLF, curLF) {
				// 还原旧内容再红（check 不留漂移副作用）
				if rerr := os.WriteFile(rules.IconsMbt, curMbt, 0o644); rerr != nil {
					fmt.Fprintf(os.Stderr, "FAIL: 还原 icons_gen.mbt 失败：%v\n", rerr)
				}
				fmt.Fprintf(os.Stderr, "FAIL: icons_gen.mbt 与真源不一致，跑 go run ./scripts/gen_icons 同步\n")
				os.Exit(1)
			}
		}
		// demo/js/icons.ts（内联表）：文件存在即校验漂移（真源 svg 变了
		// 未再 -demo 发射 = demo 徽章旧图）；不存在跳过（未发射态不强制）
		if rules.DemoTs != "" {
			if curTs, tsErr := os.ReadFile(rules.DemoTs); tsErr == nil {
				wantTs, rErr := renderDemoTs(ids, geo.Icons, geo.Digest)
				if rErr != nil {
					fmt.Fprintf(os.Stderr, "FAIL: icons.ts 渲染失败：%v\n", rErr)
					os.Exit(1)
				}
				curTsLF := bytes.ReplaceAll(curTs, []byte{13, 10}, []byte{10})
				wantLF := bytes.ReplaceAll(wantTs, []byte{13, 10}, []byte{10})
				if !bytes.Equal(curTsLF, wantLF) {
					fmt.Fprintf(os.Stderr, "FAIL: %s 与真源不一致，跑 go run ./scripts/gen_icons -demo 同步\n", rules.DemoTs)
					os.Exit(1)
				}
			}
		}
		fmt.Printf("OK：几何层与真源一致（%d 个图标，digest %s）\n", len(ids), geo.Digest)
		return
	}

	if err := os.WriteFile(rules.GeometryJSON, out, 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "FAIL: 写 %s 失败：%v\n", rules.GeometryJSON, err)
		os.Exit(1)
	}
	fmt.Printf("生成 %s：%d 个图标，%d B，digest %s\n",
		rules.GeometryJSON, len(ids), len(out), geo.Digest)

	// icons_gen.mbt（默认产物——MoonBit 数据单源，#27 方案 C）
	if rules.IconsMbt != "" {
		if err := writeIconsMbt(rules.IconsMbt, ids, geo.Icons, geo.Digest, rules.SvgAttrs); err != nil {
			fmt.Fprintf(os.Stderr, "FAIL: 写 %s 失败：%v\n", rules.IconsMbt, err)
			os.Exit(1)
		}
		fmt.Printf("生成 %s：%d 个图标（MoonBit 数据单源，icons.get 数据面）\n", rules.IconsMbt, len(ids))
	}

	if *doDemo {
		if rules.DemoTs == "" {
			fmt.Fprintf(os.Stderr, "FATAL: 规则未配 demo_ts\n")
			os.Exit(2)
		}
		if err := writeDemoTs(rules.DemoTs, ids, geo.Icons, geo.Digest); err != nil {
			fmt.Fprintf(os.Stderr, "FAIL: 写 %s 失败：%v\n", rules.DemoTs, err)
			os.Exit(1)
		}
		fmt.Printf("生成 %s：%d 个图标（内联 body 片段，消费方自行套 svg 壳）\n", rules.DemoTs, len(ids))
	}
}

func mustFloat(s string) float64 {
	f, err := strconv.ParseFloat(strings.TrimSpace(s), 64)
	if err != nil {
		fmt.Fprintf(os.Stderr, "FATAL: 规则里的描边宽度不是数字：%q\n", s)
		os.Exit(2)
	}
	return f
}

// extractPaths 按出现顺序把图元转成 d 字符串。
// circle → 两条 A 弧（SVG 规范定义的等价替换）；rect（无 rx）→ 四段直线闭合。
func extractPaths(svg string) ([]string, error) {
	out := []string{}
	for _, m := range elemRe.FindAllStringSubmatch(svg, -1) {
		tag, raw := m[1], m[2]
		attrs := map[string]string{}
		for _, am := range attrRe.FindAllStringSubmatch(raw, -1) {
			attrs[am[1]] = am[2]
		}
		switch tag {
		case "path":
			d := strings.TrimSpace(attrs["d"])
			if d == "" {
				return nil, fmt.Errorf("path 缺 d")
			}
			out = append(out, d)
		case "circle":
			cx, e1 := f64(attrs, "cx")
			cy, e2 := f64(attrs, "cy")
			r, e3 := f64(attrs, "r")
			if e1 != nil || e2 != nil || e3 != nil {
				return nil, fmt.Errorf("circle 属性非法（cx/cy/r 须为数字）")
			}
			out = append(out, fmt.Sprintf("M%s %sa%s %s 0 1 0 %s 0a%s %s 0 1 0 %s 0z",
				n(cx-r), n(cy), n(r), n(r), n(2*r), n(r), n(r), n(-2*r)))
		case "rect":
			if _, bad := attrs["rx"]; bad {
				return nil, fmt.Errorf("rect 带 rx（契约要求手写为 path）")
			}
			x, e1 := f64(attrs, "x")
			y, e2 := f64(attrs, "y")
			w, e3 := f64(attrs, "width")
			h, e4 := f64(attrs, "height")
			if e1 != nil || e2 != nil || e3 != nil || e4 != nil {
				return nil, fmt.Errorf("rect 属性非法（x/y/width/height 须为数字）")
			}
			out = append(out, fmt.Sprintf("M%s %sh%sv%sh%s 0z", n(x), n(y), n(w), n(h), n(-w)))
		}
	}
	return out, nil
}

func f64(attrs map[string]string, key string) (float64, error) {
	s, ok := attrs[key]
	if !ok {
		return 0, fmt.Errorf("缺属性 %s", key)
	}
	if !numRe.MatchString(strings.TrimSpace(s)) {
		return 0, fmt.Errorf("属性 %s=%q 非数字", key, s)
	}
	return strconv.ParseFloat(strings.TrimSpace(s), 64)
}

// n 用最短往返格式化，且先把运算结果收敛到 1e-6 —— 否则 cx+r 这类加法会把
// 20.1 算成 20.099999999999998，噪声会一路传到消费侧的几何层。
func n(f float64) string {
	r := math.Round(f*1e6) / 1e6
	s := strconv.FormatFloat(r, 'f', -1, 64)
	if s == "-0" {
		return "0"
	}
	return s
}

func marshalGeo(g Geometry) ([]byte, error) {
	b, err := json.MarshalIndent(g, "", "  ")
	if err != nil {
		return nil, err
	}
	return append(append(b, '\n'), '\n'), nil
}

// writeIconsMbt 产 MoonBit 数据单源（issue #27 方案 C）：icons.get 协议方法的
// 引擎侧数据面。常量（契约）+ 全量表（id 字典序插入——Map 迭代序即插入序，
// emitter 全量输出序由此单源）+ 显式 emitter + ids 校验面。
func renderIconsMbt(ids []string, icons map[string]IconEntry, digest string, attrs map[string]string) ([]byte, error) {
	var sb strings.Builder
	sb.WriteString("// @generated by scripts/gen_icons —— 禁手改（真源 = moonbit/icons/<id>.svg）。\n")
	sb.WriteString("// 图标资产 MoonBit 单源（issue #27 方案 C）：digest 与 moonbit/icons/icons.json\n")
	sb.WriteString("// 同源同值，gen_icons -check 锁两产物字节一致。本包 L0 纯数据零依赖。\n")
	fmt.Fprintf(&sb, "// digest %s\n", digest)
	sb.WriteString("\n///|\n/// icons.get 帧契约常量（icons/v1——几何层契约的 MoonBit 单源）。\nconst ICONS_SCHEMA : String = \"icons/v1\"\n\n///|\n/// 资产表 digest（52 枚 svg 按 id 字典序逐个 sha256 汇总，与 icons.json 同算法同值）。\n")
	fmt.Fprintf(&sb, "const ICONS_DIGEST : String = %q\n", digest)
	fmt.Fprintf(&sb, "\nconst ICONS_VIEWBOX : String = %q\n", attrs["viewBox"])
	fmt.Fprintf(&sb, "\n///|\n/// 描边宽度（相对 24 viewBox；消费端换算 strokeWidth = %s × S / 24）。\nconst ICONS_STROKE_WIDTH_TEXT : String = %q\n", attrs["stroke-width"], attrs["stroke-width"])
	fmt.Fprintf(&sb, "\nconst ICONS_STROKE_LINECAP : String = %q\n", attrs["stroke-linecap"])
	fmt.Fprintf(&sb, "\nconst ICONS_STROKE_LINEJOIN : String = %q\n", attrs["stroke-linejoin"])
	fmt.Fprintf(&sb, "\nconst ICONS_FILL : String = %q\n", attrs["fill"])
	sb.WriteString(`
///|
/// 全量几何表（id 字典序插入——Map 迭代序 = 插入序，emitter 全量输出序单源；
/// d 属性字符集不含引号/反斜杠，仍统一走 mbt_escape 防御）。
let icon_paths_table : Map[String, Array[String]] = {
  let m : Map[String, Array[String]] = Map([])
`)
	for _, id := range ids {
		quoted := make([]string, 0, len(icons[id].Paths))
		for _, p := range icons[id].Paths {
			quoted = append(quoted, mbtEscape(p))
		}
		fmt.Fprintf(&sb, "  m.set(%q, [%s])\n", id, strings.Join(quoted, ", "))
	}
	sb.WriteString(`  m
}

///|
/// icons.get 帧 emitter（显式序列化，字段序单点：schema / digest / viewBox /
/// stroke_width / stroke_linecap / stroke_linejoin / fill / icons）。
/// ids 空数组 = 全量（字典序）；否则按请求序输出、重复 id 跳过、
/// 任一未知 id 整帧拒绝（返回 None——调用方转 invalid-params，fail loud）。
pub fn export_icons_json(ids : Array[String]) -> String? {
  let buf = StringBuilder()
  buf.write_string("{\"schema\":\"\{ICONS_SCHEMA}\"")
  buf.write_string(",\"digest\":\"\{ICONS_DIGEST}\"")
  buf.write_string(",\"viewBox\":\"\{ICONS_VIEWBOX}\"")
  buf.write_string(",\"stroke_width\":\{ICONS_STROKE_WIDTH_TEXT}")
  buf.write_string(",\"stroke_linecap\":\"\{ICONS_STROKE_LINECAP}\"")
  buf.write_string(",\"stroke_linejoin\":\"\{ICONS_STROKE_LINEJOIN}\"")
  buf.write_string(",\"fill\":\"\{ICONS_FILL}\"")
  buf.write_string(",\"icons\":{")
  if ids.length() == 0 {
    let mut first = true
    for id, paths in icon_paths_table {
      if first {
        first = false
      } else {
        buf.write_string(",")
      }
      write_icon_entry(buf, id, paths)
    }
  } else {
    let seen : Map[String, Bool] = Map([])
    let mut first = true
    for id in ids {
      if seen.get(id).unwrap_or(false) {
        continue
      }
      seen.set(id, true)
      match icon_paths_table.get(id) {
        None => return None
        Some(paths) => {
          if first {
            first = false
          } else {
            buf.write_string(",")
          }
          write_icon_entry(buf, id, paths)
        }
      }
    }
  }
  buf.write_string("}}")
  Some(buf.to_string())
}

///|
/// 单图标条目（{"paths":[...]}——paths = path d 字面量数组）。
fn write_icon_entry(buf : StringBuilder, id : String, paths : Array[String]) -> Unit {
  buf.write_string("\"\{id}\":{\"paths\":[")
  for i, p in paths {
    if i > 0 {
      buf.write_string(",")
    }
    buf.write_string("\"\{p}\"")
  }
  buf.write_string("]}")
}
`)
	return []byte(sb.String()), nil
}

func writeIconsMbt(path string, ids []string, icons map[string]IconEntry, digest string, attrs map[string]string) error {
	if dir := filepath.Dir(path); dir != "" {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
	}
	b, err := renderIconsMbt(ids, icons, digest, attrs)
	if err != nil {
		return err
	}
	if err := os.WriteFile(path, b, 0o644); err != nil {
		return err
	}
	// 落盘后经 moon fmt 规范化（gen_diag writeProducts 同款契约——最终
	// 形态以 fmt 为准；52 条 m.set 长行折行由 fmt 单点裁决）。
	// cwd = 产物目录：moon fmt 须在 moon 项目内执行（向上寻 moon.mod）
	fmtCmd := exec.Command("moon", "fmt", filepath.Base(path))
	fmtCmd.Dir = filepath.Dir(path)
	out, ferr := fmtCmd.CombinedOutput()
	if ferr != nil {
		return fmt.Errorf("moon fmt 失败（moon 须在 PATH）: %v\n%s", ferr, out)
	}
	return nil
}

// mbtEscape：MoonBit 字符串字面量防御性转义（d 属性字符集本不含引号/反斜杠）。
func mbtEscape(s string) string {
	r := strings.NewReplacer(`\`, `\\`, `"`, `\"`)
	return `"` + r.Replace(s) + `"`
}

// renderDemoTs 渲染 demo 内联表源码（body 片段——消费方套 svg 壳）。
func renderDemoTs(ids []string, icons map[string]IconEntry, digest string) ([]byte, error) {
	var sb strings.Builder
	sb.WriteString("// @generated by scripts/gen_icons —— 禁手改（真源 = moonbit/icons/<id>.svg）\n")
	sb.WriteString("// 契约：viewBox 24 / stroke 1.8 / currentColor；本表只存 body 片段，消费方自行套 svg 壳。\n")
	fmt.Fprintf(&sb, "// digest %s\n", digest)
	sb.WriteString("// 本地表优先（#27 拍板）：渲染一律用本表；icons.get 帧只做 digest 对拍，\n")
	sb.WriteString("// 不一致 = 版本漂移信号（console.warn，不回退引擎表）。\n")
	fmt.Fprintf(&sb, "export const ICONS_DIGEST = %q;\n", digest)
	sb.WriteString("export const ICONS: Record<string, string> = {\n")
	for _, id := range ids {
		fmt.Fprintf(&sb, "  %q: '%s',\n", id, strings.Join(escapeAll(icons[id].Paths), ""))
	}
	sb.WriteString("};\n")
	return []byte(sb.String()), nil
}

// writeDemoTs 落盘 demo 内联表（-check 侧经 renderDemoTs 比对——文件存在
// 即校验，防「真源 svg 变了但 icons.ts 未再发射」的徽章旧图漂移）。
func writeDemoTs(path string, ids []string, icons map[string]IconEntry, digest string) error {
	if dir := filepath.Dir(path); dir != "" {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
	}
	b, err := renderDemoTs(ids, icons, digest)
	if err != nil {
		return err
	}
	return os.WriteFile(path, b, 0o644)
}

func escapeAll(paths []string) []string {
	out := make([]string, 0, len(paths))
	for _, p := range paths {
		out = append(out, "<path d=\""+p+"\"/>")
	}
	return out
}

func digestOf(ids []string, byID map[string][]byte) string {
	h := sha256.New()
	for _, id := range ids {
		h.Write([]byte(id))
		h.Write([]byte{0})
		h.Write(byID[id])
		h.Write([]byte{0})
	}
	return "sha256:" + hex.EncodeToString(h.Sum(nil))
}

func readTsv(path string) (map[string][2]string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	if strings.Contains(string(b), "\r\n") {
		return nil, fmt.Errorf("含 CRLF 行尾")
	}
	lines := strings.Split(strings.TrimRight(string(b), "\n"), "\n")
	out := map[string][2]string{}
	for _, ln := range lines[1:] {
		if strings.TrimSpace(ln) == "" {
			continue
		}
		cs := strings.Split(ln, "\t")
		if len(cs) < 5 {
			return nil, fmt.Errorf("列数不足：%s", ln)
		}
		out[cs[0]] = [2]string{cs[1], cs[2]}
	}
	return out, nil
}
