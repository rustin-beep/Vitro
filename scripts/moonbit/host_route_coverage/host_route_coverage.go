// host_route_coverage：110 路由 ↔ host 实现覆盖闸（P2-memchr 事故族，2026-09-23）。
//
// 用法（仓库根）：
//
//	go run ./scripts/moonbit/host_route_coverage -check
//
// **事故族**：`memchr` 在 oracle 有 handler（`host/string.rs:426-442`）、在
// 110 路由表中占位，但月球侧整批漏实现——既有对账锚（bytecode 的
// `host_route_anchor_wbtest`）只校验"常量 ↔ 名字"双表一致，**不校验
// "路由名 ↔ 有实现"**，缺口对全部门禁不可见（用户审阅抓出，2026-09-23）。
//
// 判据：路由表每个名字必须解析到 moonbit/host 下的 `pub fn host_<name>`
// （或经 host_route_rules.json 的 aliases 命中实现名），否则红；
// vm_whitelist（随 vm 片落地的控制流/回调族）豁免，**但双向对账**——
// 白名单条目一旦出现实现即红（逼清理，防白名单腐化）。
//
// 规则外置：scripts/moonbit/host_route_rules.json（aliases / vm_whitelist）。
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

var (
	// 路由名：host_func_id_gen.mbt 的 `"name" => <id>` / `"name"` 形态
	reRoute = regexp.MustCompile(`"([a-z_][a-z_0-9]*)"`)
	// 实现名：host 包 `pub fn host_<name>`
	reImpl = regexp.MustCompile(`pub fn host_([a-z_][a-z_0-9]*)`)
)

type rules struct {
	Aliases     map[string]string `json:"aliases"`
	VMWhitelist []string          `json:"vm_whitelist"`
}

func main() {
	root := repoRoot()
	_ = os.Chdir(root)

	var r rules
	rulesRaw, err := os.ReadFile("scripts/moonbit/host_route_rules.json")
	if err != nil {
		fatal("读规则失败：%v", err)
	}
	if err := json.Unmarshal(rulesRaw, &r); err != nil {
		fatal("规则 JSON 解析失败：%v", err)
	}
	if len(r.VMWhitelist) == 0 {
		fatal("vm_whitelist 为空——fail loud（空集不得绿）")
	}

	// 路由名表（生成物：bytecode 包，单源 = Rust host_func_id.rs）
	genRaw, err := os.ReadFile("moonbit/bytecode/host_func_id_gen.mbt")
	if err != nil {
		fatal("读路由表失败：%v", err)
	}
	routes := map[string]bool{}
	for _, m := range reRoute.FindAllStringSubmatch(string(genRaw), -1) {
		routes[m[1]] = true
	}
	if len(routes) < 100 {
		fatal("路由名解析异常（%d 个 < 100）——形态变更须先改本闸", len(routes))
	}

	// 实现名集合（host 包非测试源码）
	impls := map[string]bool{}
	files, _ := filepath.Glob("moonbit/host/*.mbt")
	if len(files) == 0 {
		fatal("host 包源码为空")
	}
	for _, f := range files {
		if strings.Contains(filepath.Base(f), "test") {
			continue
		}
		data, err := os.ReadFile(f)
		if err != nil {
			fatal("读 %s: %v", f, err)
		}
		for _, m := range reImpl.FindAllStringSubmatch(string(data), -1) {
			impls[m[1]] = true
		}
	}

	vmSet := map[string]bool{}
	for _, n := range r.VMWhitelist {
		vmSet[n] = true
	}

	names := make([]string, 0, len(routes))
	for n := range routes {
		names = append(names, n)
	}
	sort.Strings(names)

	bad := 0
	for _, n := range names {
		key := n
		if a, ok := r.Aliases[n]; ok {
			key = a
		}
		_, implemented := impls[key]
		// 别名名与其解析目标均查（__vitro_output → output 同属 vm 族）
		whitelisted := vmSet[n] || vmSet[key]
		if implemented {
			if whitelisted {
				fmt.Printf("过期白名单: %s 已有实现（host_%s）——须从 vm_whitelist 清理\n", n, key)
				bad++
			}
			continue
		}
		if whitelisted {
			continue
		}
		// 别名指向的名字也无实现（防别名目标名写错）
		hint := ""
		if key != n {
			hint = fmt.Sprintf("（经别名 → %s，该名亦无实现）", key)
		}
		fmt.Printf("未实现路由: %s%s\n", n, hint)
		bad++
	}
	if bad > 0 {
		fatal("host_route_coverage: %d 条路由无实现或白名单过期", bad)
	}
	fmt.Printf("host_route_coverage: OK（%d 条路由全部有实现或已登记 vm 白名单）\n", len(names))
}

func repoRoot() string {
	d, err := os.Getwd()
	if err != nil {
		fatal("getwd: %v", err)
	}
	for {
		if _, err := os.Stat(filepath.Join(d, "go.mod")); err == nil {
			return d
		}
		parent := filepath.Dir(d)
		if parent == d {
			fatal("未找到仓库根（go.mod）")
		}
		d = parent
	}
}

func fatal(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "host_route_coverage: "+format+"\n", args...)
	os.Exit(2)
}
