# -*- coding: utf-8 -*-
"""剥壳探测器（skill §二）：把首层错机械绕开，看下一层诊断。

用途：引擎是四级 short-circuit（lex→parse→typeck→codegen，前级错后级不跑，见 #20），
      所以"首层码"不等于"缺陷分布"。本脚本做**机械等价变换**模拟"继续编译"，再复跑。

本轮（2026-10-14）实测有效的那一类变换：**常量标识符 → 字面量**
      把 `case <常量>` 与 `[<常量>]` 换成数值，副作用等价（Clang 侧由脚本内断言保）。
      适用于首层错为「枚举常量当 case 标签 / 当数组尺寸」的样本。

用法：改下方 CFG 的路径 → 跑 → 看「见底 / 层叠 / 判据故障」三类结论。

★ 血泪断言（2026-10-14 实锤）：**变换计数必须 > 0 才算剥壳生效**。
  首版只认十进制常量与 `//` 注释，遇到 `OP_PUSH = 0x01` 或成员后带 `/* */` 的枚举时
  **静默不变换**（case×0），表现为"剥壳后还是 REJECT" —— 极易被误读成"没有下一层"。
  ⇒ 本版在跑之前先断言总变换数 > 0，否则该份标 `NO_TRANSFORM` 并跳过。
"""
import json, os, re, subprocess

# ───────────────────────── CFG ─────────────────────────
RF   = r"<工作目录>"                      # 结果 JSON 所在目录
GEN  = os.path.join(RF, "gen_long")       # 原始 .c 所在
OUT  = os.path.join(RF, "gen_long_peeled")# 剥壳产物
RESJ = os.path.join(RF, "gen_long_v2.json")
JUDGE = r"<judge_dir>\vitro.exe"          # ★ 冻结快照的 native exe
CLANG = r"C:\clang+llvm-22.1.4-x86_64-pc-windows-msvc\bin\clang.exe"
CODES = ("E3047", "E0")                   # 要剥的首层码（按需改）
# ──────────────────────────────────────────────────────

os.makedirs(OUT, exist_ok=True)


def judge(path):
    try:
        p = subprocess.run([JUDGE, "compile", path, "--json"], capture_output=True, timeout=180)
    except Exception as e:
        return "ERR", []
    for l in p.stdout.decode("utf-8", "replace").splitlines():
        l = l.strip()
        if not l.startswith("{"):
            continue
        try:
            d = json.loads(l)
        except Exception:
            continue
        r = d.get("result") or d.get("frame", {}).get("result") or {}
        if "ok" in r:
            errs = [x for x in (r.get("diagnostics") or []) if x.get("severity") == "error"]
            return ("ACCEPT" if r["ok"] else "REJECT"), [(x.get("code"), x.get("line"), x.get("message", "")[:56]) for x in errs]
    return "NO_FRAME", []


def clang_ok(path):
    """等价性断言：变换后 Clang 必须仍然 ACCEPT，否则这次变换不等价。"""
    return subprocess.run([CLANG, "-w", "-fsyntax-only", path], capture_output=True).returncode == 0


def const_map(src):
    """常量表：`#define` 数值（十进制/十六进制/八进制）+ `enum` 自增成员。先剥注释。"""
    src = re.sub(r"/\*.*?\*/", " ", src, flags=re.S)   # ← 块注释必须先剥（实锤坑）
    src = re.sub(r"//[^\n]*", " ", src)
    m = {}
    num = r"(?:0[xX][0-9a-fA-F]+|0[0-7]+|\d+)"
    for mm in re.finditer(r"^\s*#define\s+([A-Za-z_]\w*)\s+\(?\s*(" + num + r")\s*\)?\s*$", src, re.M):
        m[mm.group(1)] = mm.group(2)
    for blk in re.finditer(r"enum\s*(?:\w+)?\s*\{(.*?)\}", src, re.S):
        cur = 0
        for item in blk.group(1).split(","):
            item = item.strip()
            if not item:
                continue
            if "=" in item:
                n, v = [t.strip() for t in item.split("=", 1)]
                if re.fullmatch(num, v):
                    cur = int(v, 0)
                else:
                    continue
            else:
                n = item
            if re.fullmatch(r"[A-Za-z_]\w*", n):
                m[n] = str(cur)
                cur += 1
    return m


def peel(src):
    """`case NAME:` → `case 值:`；`[NAME]` → `[值]`（仅当 NAME 在常量表里）。"""
    m = const_map(src)
    n_case = n_idx = 0

    def r_case(mo):
        nonlocal n_case
        name = mo.group(1)
        if name in m:
            n_case += 1
            return "case " + m[name] + ":"
        return mo.group(0)

    def r_idx(mo):
        nonlocal n_idx
        name = mo.group(1)
        if name in m:
            n_idx += 1
            return "[" + m[name] + "]"
        return mo.group(0)

    src = re.sub(r"\bcase\s+([A-Za-z_]\w*)\s*:", r_case, src)
    src = re.sub(r"\[\s*([A-Za-z_]\w*)\s*\]", r_idx, src)
    return src, n_case, n_idx, m


def main():
    rows = json.load(open(RESJ, encoding="utf-8"))
    targets = [x for x in rows if set(x.get("wasm_codes") or []) & set(CODES)]
    print(f"剥壳目标 {len(targets)} 份\n")
    summary = []
    for x in targets:
        fp = os.path.join(GEN, x["model"], f"{x['pid']}_s{x['sample']}.c")
        src = open(fp, encoding="utf-8").read()
        peeled, nc, ni, cm = peel(src)
        tag = f"{x['model']}_{x['pid']}_s{x['sample']}"
        if nc + ni == 0:
            print(f"── {tag} · NO_TRANSFORM（常量表 {len(cm)} 个，变换 0 处）⇒ 跳过，勿读作'无下一层'")
            summary.append({"tag": tag, "verdict": "NO_TRANSFORM", "n_case": nc, "n_idx": ni})
            continue
        pp = os.path.join(OUT, tag + ".peeled.c")
        open(pp, "w", encoding="utf-8", newline="\n").write(peeled)
        st, errs = judge(pp)
        ok_cl = clang_ok(pp)
        verdict = "见底" if st == "ACCEPT" else ("层叠" if st == "REJECT" else "判据故障")
        print(f"── {tag} · 原码 {sorted(set(x.get('wasm_codes') or []))}")
        print(f"   变换：case×{nc}  索引×{ni}  常量表 {len(cm)} 个")
        print(f"   剥壳后 vitro={st}（{verdict}）  clang={'OK' if ok_cl else '**REJ 不等价！**'}")
        for c, ln, msg in errs[:5]:
            print(f"      L{ln} [{c}] {msg}")
        summary.append({"tag": tag, "before": x.get("wasm_codes"), "after": st,
                        "after_codes": [c for c, _, _ in errs], "clang_ok": ok_cl,
                        "n_case": nc, "n_idx": ni})
        print()
    json.dump(summary, open(os.path.join(RF, "peel_summary.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    from collections import Counter
    print("结论分布:", dict(Counter(s.get("verdict", s.get("after")) for s in summary)))


main()
