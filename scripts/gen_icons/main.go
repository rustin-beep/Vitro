package main

// 图标几何层生成器 —— 产出 assets/icons.json（供 MAUI / MoonBit / 自绘方取 `d` 数据）。
//
// 真源是手写的 assets/icons/<id>.svg（逐个编辑），本脚本**只读真源、只产几何层**，
// 不反向改写 svg。demo 侧的内联表（demo/js/icons.ts）由 -demo 额外产出。
//
// 用法（flag 必须写在任何位置参数之前）：
//
//	go run ./scripts/gen_icons            # 生成 assets/icons.json
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
	"math"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

type Rules struct {
	AssetsDir     string            `json:"assets_dir"`
	IndexTsv      string            `json:"index_tsv"`
	GeometryJSON  string            `json:"geometry_json"`
	DemoTs        string            `json:"demo_ts"`
	SvgAttrs      map[string]string `json:"svg_attrs"`
	GeometrySchema string           `json:"geometry_schema"`
	ScaleFormula  string            `json:"scale_formula"`
}

type IconEntry struct {
	Title    string   `json:"title"`
	Category string   `json:"category"`
	Scope    string   `json:"scope"`
	Paths    []string `json:"paths"`
}

type Geometry struct {
	Schema          string                `json:"schema"`
	Digest          string                `json:"digest"`
	ViewBox         string                `json:"viewBox"`
	StrokeWidth     float64               `json:"stroke_width"`
	StrokeLinecap   string                `json:"stroke_linecap"`
	StrokeLinejoin  string                `json:"stroke_linejoin"`
	Fill            string                `json:"fill"`
	ScaleFormula    string                `json:"scale_formula"`
	Icons           map[string]IconEntry  `json:"icons"`
}

var (
	elemRe    = regexp.MustCompile(`(?s)<(path|circle|rect)\b([^>]*?)/?>`)
	attrRe    = regexp.MustCompile(`([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*"([^"]*)"`)
	titleRe   = regexp.MustCompile(`(?s)<title>(.*?)</title>`)
	descRe    = regexp.MustCompile(`(?s)<desc>(.*?)</desc>`)
	numRe     = regexp.MustCompile(`^-?[0-9.]+$`)
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
		fmt.Printf("OK：几何层与真源一致（%d 个图标，digest %s）\n", len(ids), geo.Digest)
		return
	}

	if err := os.WriteFile(rules.GeometryJSON, out, 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "FAIL: 写 %s 失败：%v\n", rules.GeometryJSON, err)
		os.Exit(1)
	}
	fmt.Printf("生成 %s：%d 个图标，%d B，digest %s\n",
		rules.GeometryJSON, len(ids), len(out), geo.Digest)

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

func writeDemoTs(path string, ids []string, icons map[string]IconEntry, digest string) error {
	if dir := filepath.Dir(path); dir != "" {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
	}
	var sb strings.Builder
	sb.WriteString("// @generated by scripts/gen_icons —— 禁手改（真源 = assets/icons/<id>.svg）\n")
	sb.WriteString("// 契约：viewBox 24 / stroke 1.8 / currentColor；本表只存 body 片段，消费方自行套 svg 壳。\n")
	fmt.Fprintf(&sb, "// digest %s\n", digest)
	sb.WriteString("export const ICONS: Record<string, string> = {\n")
	for _, id := range ids {
		fmt.Fprintf(&sb, "  %q: '%s',\n", id, strings.Join(escapeAll(icons[id].Paths), ""))
	}
	sb.WriteString("};\n")
	return os.WriteFile(path, []byte(sb.String()), 0o644)
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
