#!/usr/bin/env python3
# 图鉴生成器 —— 展示层排版（非判定型；判定型闸是 Go 的 scripts/icon_catalog）。
#
# 读 moonbit/icons/*.svg + moonbit/icons/index.tsv，按 category 分组排卡片，产出
# assets/icons-preview.svg：每卡 = 图标 + 英文 id + 中文短标签，深色底（图鉴是唯一
# 自带底色的文件——图标资产一律透明，由消费方叠底着色）。
#
# 用法：
#     python scripts/gen_icon_preview/main.py
#     python scripts/gen_icon_preview/main.py -check    # 只校验现有图鉴是否最新（不落盘）
#
# 幂等：卡片顺序按 category 固定序 + 组内 id 字典序，行尾固定 LF ⇒ 双次运行字节一致；
# -check 完全不落盘（不碰 mtime）。展示层与资产面解耦：改图标后重跑本脚本即可。
#
# 退出码：0 成功（含 -check 一致）/ 1 不一致或写出失败 / 2 环境错（fail loud）。

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ASSETS = os.path.join(ROOT, "moonbit", "icons")
TSV = os.path.join(ASSETS, "index.tsv")
OUT = os.path.join(ROOT, "assets", "icons-preview.svg")

FONT = "-apple-system,'Segoe UI','Microsoft YaHei UI',sans-serif"
CW, CH, COLS = 96, 96, 6
GAP = 4.8
X0 = 40
ORDER = ["词法", "语法", "语义", "C++", "运行时"]

# 图鉴专用中文短标签：tsv 的 desc 是完整语义（最长 9 字，96px 卡装不下），
# 这里给一个 4~6 字的短标签。新增 id 时必须补，否则回落成 id 本身（可接受的退化）。
SHORT = {
    "string": "字符串", "comment": "块注释", "operator": "操作符", "macro": "宏定义",
    "unsupported": "暂不支持", "complex": "声明复杂", "array-size": "数组大小",
    "expr-expected": "缺表达式", "switch-clause": "分支项", "semicolon": "分号",
    "bracket": "括号", "duplicate": "重复定义", "type-mismatch": "类型不符",
    "array-init": "数组初始化", "index": "索引", "jump-outside": "跳转越界",
    "return": "返回值", "cond-invalid": "条件非法", "undeclared": "未声明",
    "op-type": "运算类型", "deref": "解引用", "array-decay": "数组退化",
    "incdec": "自增自减", "alloc-args": "分配参数", "call-args": "实参",
    "call-target": "调用目标", "printf": "printf", "scanf": "scanf",
    "struct-member": "成员访问", "assign-readonly": "右值赋值", "case-const": "case 常量",
    "off-by-one": "差一错误", "implicit-cast": "隐式转换", "pointer-compat": "指针兼容",
    "promote": "类型提升", "uaf": "内存已释放", "double-free": "重复释放",
    "leak": "内存泄漏", "dangling": "悬垂引用", "slice": "对象切片",
    "ownership": "所有权", "move": "移动后使用", "buffer-overflow": "缓冲区溢出",
    "cause": "原因", "deny": "非法访问", "divide-zero": "除零", "fix": "解决方法",
    "inspect": "查看", "location": "位置", "note": "示例", "step-limit": "步数超限",
    "timeline": "时间轴",
    # 2026-10-10 C 语义全集批（24 枚新增，按 C 语言概念而非诊断码定粒度）
    "unknown-char": "未知字符", "string-multiline": "字符串跨行",
    "preproc-cond": "条件编译", "include-missing": "头文件缺失",
    "include-cycle": "循环包含", "token-paste": "记号粘贴",
    "depth-limit": "展开超限", "shadow": "遮蔽", "side-effect": "宏参副作用",
    "static-assert": "静态断言", "number-literal": "数字字面量",
    "char-literal": "字符字面量", "type-expected": "缺类型名",
    "paren-close": "缺右圆括号", "bracket-close": "缺右方括号",
    "static-linkage": "静态链接", "label-undefined": "标签未定义",
    "cond-assign": "条件里赋值", "const-qual": "const 限定",
    "printf-format": "输出格式串", "scanf-format": "输入格式串",
    "func-undefined": "未定义函数", "null-deref": "空指针",
    "uninit-read": "未初始化",
}

DESC_RE = re.compile(r"(?s)</desc>\n(.*?)\n</svg>")


def main():
    check = "-check" in sys.argv[1:]
    if not os.path.isdir(ASSETS):
        sys.stderr.write("FATAL: 读不到资产目录 %s\n" % ASSETS)
        sys.exit(2)
    rows = []
    with open(TSV, encoding="utf-8") as f:
        lines = [ln for ln in f.read().splitlines() if ln.strip()]
    for ln in lines[1:]:
        cols = ln.split("\t")
        if len(cols) != 5:
            sys.stderr.write("FATAL: index.tsv 列数=%d（应 5）：%s\n" % (len(cols), ln))
            sys.exit(2)
        rows.append(cols)

    body_of = {}
    for r in rows:
        p = os.path.join(ASSETS, r[0] + ".svg")
        if not os.path.exists(p):
            sys.stderr.write("FATAL: index.tsv 有 id 但缺资产：%s\n" % p)
            sys.exit(2)
        with open(p, encoding="utf-8") as f:
            m = DESC_RE.search(f.read())
        body_of[r[0]] = m.group(1).replace("\n", "") if m else ""

    groups = [(c, [r[0] for r in rows if r[1] == c]) for c in ORDER]
    groups = [(c, ids) for c, ids in groups if ids]
    h = 66 + sum(18 + ((len(ids) + COLS - 1) // COLS) * (CH + 12) + 10 for _, ids in groups) + 56

    p = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 680 %d" width="680" height="%d" role="img">' % (h, h)]
    p.append("<title>Vitro 语义图标图鉴</title>")
    p.append("<desc>按 category 分组的语义图标，每卡为图标、英文 id 与中文语义</desc>")
    p.append('<rect x="0" y="0" width="680" height="%d" fill="#17171b"/>' % h)
    p.append('<text x="40" y="30" font-family="%s" font-size="15" font-weight="500" fill="#f2f2f2">Vitro 语义图标图鉴 · %d 个</text>' % (FONT, len(rows)))
    p.append('<text x="40" y="48" font-family="%s" font-size="11" fill="#8a8a90">viewBox 24 · stroke 1.8 · currentColor · 语义 id 与图形严格双射</text>' % FONT)
    y = 66
    for gname, ids in groups:
        p.append('<text x="40" y="%d" font-family="%s" font-size="12" font-weight="500" fill="#c9c9cf">%s · %d</text>' % (y, FONT, gname, len(ids)))
        p.append('<line x1="40" y1="%d" x2="640" y2="%d" stroke="#3a3a40" stroke-width="1"/>' % (y + 6, y + 6))
        y += 18
        for i, key in enumerate(ids):
            col, row = i % COLS, i // COLS
            x = X0 + col * (CW + GAP)
            cy = y + row * (CH + 12)
            p.append('<rect x="%g" y="%d" width="%d" height="%d" rx="10" fill="#2b2b2e"/>' % (x, cy, CW, CH))
            p.append('<g transform="translate(%g,%d) scale(1.7)" fill="none" stroke="#e8e8e8" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">%s</g>' % (x + CW / 2 - 20.4, cy + 10, body_of[key]))
            p.append('<text x="%g" y="%d" text-anchor="middle" font-family="%s" font-size="11" fill="#f2f2f2">%s</text>' % (x + CW / 2, cy + 74, FONT, key))
            p.append('<text x="%g" y="%d" text-anchor="middle" font-family="%s" font-size="11" fill="#9a9aa0">%s</text>' % (x + CW / 2, cy + 89, FONT, SHORT.get(key, key)))
        y += ((len(ids) + COLS - 1) // COLS) * (CH + 12) + 10
    p.append('<text x="40" y="%d" font-family="%s" font-size="11" fill="#7a7a80">真源 moonbit/icons/&lt;id&gt;.svg · 清单 index.tsv · 几何层 moonbit/icons/icons.json（gen_icons 产，随 mooncakes 包发布）· 图鉴为展示层，不进契约闸</text>' % (y + 16, FONT))
    p.append('<text x="40" y="%d" font-family="%s" font-size="11" fill="#6b6b72">设计准则：代码字面量 / 经典 CS 隐喻优先，禁生活化抽象比喻（灯泡≠原因 · 水滴≠内存 · 角尺≠语汇）</text>' % (y + 34, FONT))
    p.append("</svg>")
    out = "\n".join(p) + "\n"

    if check:
        if not os.path.exists(OUT):
            sys.stderr.write("FAIL: 图鉴缺失 %s（跑 python scripts/gen_icon_preview/main.py）\n" % OUT)
            sys.exit(1)
        with open(OUT, encoding="utf-8") as f:
            cur = f.read()
        if cur != out:
            sys.stderr.write("FAIL: 图鉴与真源不一致（%d B vs %d B），重跑生成器\n" % (len(cur), len(out)))
            sys.exit(1)
        print("OK：图鉴与真源一致（%d 个图标）" % len(rows))
        return

    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(out)
    print("生成 %s：%d 个图标，%d B，%d 组" % (OUT, len(rows), len(out), len(groups)))


if __name__ == "__main__":
    main()
