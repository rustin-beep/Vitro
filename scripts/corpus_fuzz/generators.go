package main

// 域生成器（2026-10-19 随机分叉对抗补做批收编——用户令「加进 Go 防线」）。
// 与语义靶算子（存量语料 × 变换）互补：生成器凭模板 + 确定性随机参数
// 凭空造域内程序，覆盖「修复域没有存量语料」的对抗盲区（#177/#198 char
// 字节域与 #174/#175/#182/#156/#154 诊断面防误伤即首批两域）。
//
// 契约（与算子同款 fail loud）：
//   - rules.json `generators` 段的 name 必须在 generatorByName 注册；
//   - 生成一律确定性（detRand + 域内固定派生种子——同规则 hash 同产物）；
//   - 生成器先自证合法（clang 必须过——生成器 bug 不得伪装成引擎分叉；
//     本批教训：python 原型的 13→8→0 条「分叉」全是生成器自身转义/语法
//     bug）。对拍口径与算子一致：stdout + REJECT/OK 族（CLI rc 不映射
//     程序返回值）。

import (
	"fmt"
)

type generator struct {
	name string
	fn   func(r *detRand, idx int) string
}

var generators = []generator{
	{name: "char_arith", fn: genCharArith},
	{name: "diag_legal", fn: genDiagLegal},
}

func generatorByName(name string) (generator, bool) {
	for _, g := range generators {
		if g.name == name {
			return g, true
		}
	}
	return generator{}, false
}

// 域 1：char 全局/局部/static/邻接排布的算术字节域（#177/#198 定向）。
// 随机维度：边界值（±1 绕界 + 200/255/256 高位）× 作用域 × 运算族
// （复合赋值/自增自减）× signed/unsigned；邻接形态带哨兵串验越权写窗。
func genCharArith(r *detRand, idx int) string {
	edgeVals := []int{-129, -128, -127, -1, 0, 1, 47, 126, 127, 128, 129, 200, 254, 255, 256}
	v1 := edgeVals[r.intn(len(edgeVals))]
	v2 := edgeVals[r.intn(len(edgeVals))]
	scopes := []string{"global", "local", "static", "adjacent"}
	scope := scopes[r.intn(len(scopes))]
	tys := []string{"char", "unsigned char"}
	uty := tys[r.intn(len(tys))]
	ops := [][2]string{{"+=", "1"}, {"-=", "1"}, {"*=", "2"}, {"++", ""}, {"--", ""}}
	op := ops[r.intn(len(ops))]

	var b sourceBuilder
	b.line("#include <stdio.h>")
	b.line("")
	switch scope {
	case "global":
		b.linef("%s c1 = %d; %s c2 = %d; char nb = 'Z';", uty, v1, uty, v2)
	case "static":
		b.linef("static %s c1 = %d; static %s c2 = %d;", uty, v1, uty, v2)
	default:
		b.linef("%s nb = 'Z';", uty)
	}
	b.line("int main(void) {")
	if scope == "local" || scope == "adjacent" {
		b.linef("  %s c1 = %d; %s c2 = %d;", uty, v1, uty, v2)
	}
	if scope == "adjacent" {
		b.line("  char a1 = 'A', a2 = 'B', a3 = 'C';")
	}
	if op[1] == "" {
		b.linef("  c1%s; c2%s;", op[0], op[0])
	} else {
		b.linef("  c1 = %d; c2 = %d;", v1, v2)
		b.linef("  c1 %s %s; c2 %s %s;", op[0], op[1], op[0], op[1])
	}
	b.line(`  printf("%d %d\n", c1, c2);`)
	if scope == "adjacent" {
		b.line(`  printf("%c%c%c\n", a1, a2, a3);`)
	}
	b.line("  return 0;")
	b.line("}")
	return b.String()
}

// 域 2：六诊断面的合法邻域（#175/#174/#182/#156/#154 防误伤）——
// 合法形态随机填充，vitro 必须与 clang 同判 ACCEPT 且 stdout 逐字节一致
// （任何误拒 = 误伤红）。
func genDiagLegal(r *detRand, idx int) string {
	k := r.intn(6)
	var b sourceBuilder
	b.line("#include <stdio.h>")
	switch k {
	case 0: // 数组合法操作（赋值左值禁令邻域）
		sizes := []int{2, 3, 5}
		sz := sizes[r.intn(len(sizes))]
		muls := []int{1, 2, 3}
		m := muls[r.intn(len(muls))]
		b.linef("int arr1[%d]; int arr2[%d];", sz, sz)
		b.line("int main(void) {")
		b.linef("  for (int i = 0; i < %d; i++) arr1[i] = i * %d;", sz, m)
		b.line("  int *p = arr1;")
		b.line(`  printf("%d %d\n", arr1[0], p[1]);`)
		b.line("  return 0; }")
	case 1: // struct 合法多声明器成员（重复成员/重复说明符禁令邻域）
		members := []int{2, 3, 4}
		m := members[r.intn(len(members))]
		b.linef("struct S { int f0")
		for j := 1; j < m; j++ {
			b.linef(", f%d", j)
		}
		b.line("; };")
		b.line("int main(void) { struct S s = {0};")
		b.linef("  s.f0 = %d; s.f1 = s.f0 + %d;", r.intn(100), 1+r.intn(9))
		b.line(`  printf("%d\n", s.f0 + s.f1);`)
		b.line("  return 0; }")
	case 2: // enum 合法多定义（重定义禁令邻域）
		b.linef("enum A { X1 = %d };", r.intn(10))
		b.line("enum B { Y1, Y2 };")
		b.line("int main(void) { enum A a = X1; enum B b = Y2;")
		b.line(`  printf("%d %d\n", a, b);`)
		b.line("  return 0; }")
	case 3: // register 合法使用（取址禁令邻域）
		b.linef("int main(void) { register int r = %d; register int s = r * %d;",
			1+r.intn(50), 2+r.intn(4))
		b.line(`  printf("%d\n", r + s);`)
		b.line("  return r + s; }")
	case 4: // typedef 合法同类型重定义（不同类型重定义禁令邻域）
		b.line("typedef int T; typedef int T; typedef double D;")
		b.linef("int main(void) { T v = %d; D w = v / %d.0;", 1+r.intn(99), []int{2, 4}[r.intn(2)])
		b.line(`  printf("%.1f\n", w);`)
		b.line("  return 0; }")
	default: // 合法数组尺寸族（负尺寸禁令邻域）
		sizes := []int{1, 4, 7}
		sz := sizes[r.intn(len(sizes))]
		b.linef("int g[%d];", sz)
		b.line("int main(void) {")
		b.linef("  char s[] = \"ok%d\"; int a[%d] = {0};", sz, sz)
		b.linef("  for (int i = 0; i < %d; i++) a[i] = i;", sz)
		b.linef("  printf(\"%%d %%s %%d\\n\", a[%d], s, (int)sizeof(g));", sz-1)
		b.line("  return 0; }")
	}
	return b.String()
}

// sourceBuilder：行拼装（生成器输出统一走此口，行尾 \n 由 String 补齐）。
type sourceBuilder struct {
	lines []string
}

func (b *sourceBuilder) line(s string) {
	b.lines = append(b.lines, s)
}

func (b *sourceBuilder) linef(format string, args ...any) {
	b.lines = append(b.lines, fmt.Sprintf(format, args...))
}

func (b *sourceBuilder) String() string {
	out := ""
	for _, l := range b.lines {
		out += l + "\n"
	}
	return out
}
