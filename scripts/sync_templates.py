#!/usr/bin/env python3
"""
sync_templates.py — 模板同步脚本

职责：
1. 扫描 templates/ 目录，读取 source.c + meta.yaml
2. 渲染 /*__PARAM_*/ → native/tests/cases_template_generated/*.c
3. 用 Clang 编译运行生成 Golden .out → native/tests/cases_golden/

（G1 恢复注：原第 4/5 步的 Flutter JSON Index / assets 输出已随前端切割移除。）

用法：
    python scripts/sync_templates.py
"""

import datetime
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent
TPL_DIR = PROJECT_ROOT / "templates"
GEN_DIR = PROJECT_ROOT / "native/tests/cases_template_generated"
GOLDEN_DIR = PROJECT_ROOT / "native/tests/cases_golden"
BASELINE_DIR = PROJECT_ROOT / "native/tests/cases/baseline"
BASELINE_GOLDEN_DIR = GOLDEN_DIR / "baseline"
CLANG_PATH = "clang"

PARAM_RE = re.compile(r'/\*__PARAM_(\w+)__\*/\s*([^ \t\n\r\[\]();,]+)')


def render_template(source: str, args: dict) -> str:
    def repl(m):
        key = m.group(1)
        return args.get(key, m.group(2))
    return PARAM_RE.sub(repl, source)


def scan_tutorial_anchors(source: str) -> dict:
    """扫描 // @tutorial-anchor: name，返回 {name: line_number}"""
    anchors = {}
    for i, line in enumerate(source.splitlines(), 1):
        m = re.search(r'@tutorial-anchor:\s*(\w+)', line)
        if m:
            anchors[m.group(1)] = i
    return anchors


def run_with_clang(source: str) -> str:
    """用 Clang 编译运行 C 代码，返回 stdout 文本"""
    header = '#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#undef min\n#undef max\n\n'
    full_source = header + source
    with tempfile.TemporaryDirectory() as tmpdir:
        c_file = Path(tmpdir) / "test.c"
        exe_file = Path(tmpdir) / "test.exe" if sys.platform == "win32" else Path(tmpdir) / "test"
        c_file.write_text(full_source, encoding="utf-8")

        compile_cmd = [CLANG_PATH, str(c_file), "-o", str(exe_file), "-Wno-implicit-function-declaration"]
        if sys.platform != "win32":
            compile_cmd.append("-lm")

        compile_proc = subprocess.run(compile_cmd, capture_output=True, text=True, timeout=30)
        if compile_proc.returncode != 0:
            raise RuntimeError(f"Clang compile failed: {compile_proc.stderr}")

        run_proc = subprocess.run([str(exe_file)], capture_output=True, text=True, timeout=10)
        return run_proc.stdout


def load_meta_yaml(path: Path) -> dict:
    """极简 YAML 解析（只处理本项目的 meta.yaml 格式）"""
    data = {"params": {}, "tutorial": {"steps": []}, "knowledge_nodes": []}
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    i = 0
    current_param = None
    current_step = None
    in_params = False
    in_tutorial = False
    in_knowledge = False

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        if not stripped or stripped.startswith('#'):
            i += 1
            continue

        # 顶级键（不在 params/tutorial/knowledge_nodes 子块中）
        if stripped.startswith('key:') and not in_params and not in_tutorial and not in_knowledge:
            data['key'] = stripped.split(':', 1)[1].strip()
        elif stripped.startswith('name:') and not in_params and not in_tutorial and not in_knowledge:
            data['name'] = stripped.split(':', 1)[1].strip()
        elif stripped.startswith('category:') and not in_params and not in_tutorial and not in_knowledge:
            data['category'] = stripped.split(':', 1)[1].strip()
        elif stripped == 'params:':
            in_params = True
            in_tutorial = False
            in_knowledge = False
        elif stripped == 'tutorial:':
            in_params = False
            in_tutorial = True
            in_knowledge = False
        elif stripped == 'knowledge_nodes:':
            in_knowledge = True
            in_tutorial = False
            in_params = False
        elif stripped.startswith('- ') and not stripped.startswith('- title:'):
            # 列表项
            val = stripped[2:].strip()
            if in_knowledge:
                data['knowledge_nodes'].append(val)
            elif in_tutorial and current_step is not None:
                # step 列表项（explanations 等）
                pass
        elif stripped.startswith('- title:'):
            in_tutorial = True
            in_knowledge = False
            current_step = {"title": stripped.split(':', 1)[1].strip()}
            data['tutorial']['steps'].append(current_step)
            current_param = None
        elif stripped.startswith('description:') and current_step is not None:
            current_step['description'] = stripped.split(':', 1)[1].strip()
        elif stripped.startswith('anchor:') and current_step is not None:
            current_step['anchor'] = stripped.split(':', 1)[1].strip()
        elif re.match(r'^\w+:$', stripped) and not in_tutorial and not in_knowledge:
            # param key
            current_param = stripped[:-1]
            data['params'][current_param] = {}
        elif stripped.startswith('label:') and current_param is not None:
            data['params'][current_param]['label'] = stripped.split(':', 1)[1].strip()
        elif stripped.startswith('type:') and current_param is not None:
            data['params'][current_param]['type'] = stripped.split(':', 1)[1].strip()
        elif stripped.startswith('default:') and current_param is not None:
            data['params'][current_param]['default'] = stripped.split(':', 1)[1].strip()

        i += 1

    return data


def sync():
    GEN_DIR.mkdir(parents=True, exist_ok=True)
    GOLDEN_DIR.mkdir(parents=True, exist_ok=True)

    index = {"templates": []}
    golden_new = 0
    golden_skipped = 0
    gen_count = 0
    golden_fails = []
    # Dart 硬编码教程读取已删（2026-09-29 模块审阅 14 P2-3）：CideFlutter 目录随
    # 2026-09-11 前端切割移出，该读取恒返回空——死代码；S8 教学智能批按新契约重建。

    for d in sorted(TPL_DIR.iterdir()):
        if not d.is_dir():
            continue

        # 支持 C 模板（source.c）和 C++ 模板（source.cpp）
        source_c_path = d / "source.c"
        source_cpp_path = d / "source.cpp"
        meta_path = d / "meta.yaml"
        if source_c_path.exists():
            source_path = source_c_path
            ext = "c"
        elif source_cpp_path.exists():
            source_path = source_cpp_path
            ext = "cpp"
        else:
            print(f"[SKIP] {d.name}: missing source.c or source.cpp")
            continue
        if not meta_path.exists():
            print(f"[SKIP] {d.name}: missing meta.yaml")
            continue

        source_c = source_path.read_text(encoding="utf-8")
        meta = load_meta_yaml(meta_path)
        anchors = scan_tutorial_anchors(source_c)
        key = meta.get("key", d.name)

        # 构建 tutorial steps：现从 meta.yaml 构建（anchor 匹配现状见模板维护指南
        # 「anchor 现状与 S8 契约」节——95 锚点全失配，标记随 S8 铺设）
        tutorial_steps = []
        if not tutorial_steps:
            # fallback: 从 meta.yaml 构建（无 explanations）
            for step in meta.get("tutorial", {}).get("steps", []):
                anchor_name = step.get("anchor", "")
                focus_lines = [anchors[anchor_name]] if anchor_name and anchor_name in anchors else []
                tutorial_steps.append({
                    "title": step.get("title", ""),
                    "description": step.get("description", ""),
                    "focusLines": focus_lines,
                    "explanations": [],
                })

        # 构建 Index 条目
        tpl_entry = {
            "key": meta.get("key", d.name),
            "name": meta.get("name", d.name),
            "category": meta.get("category", "其他"),
            "ext": ext,
            "params": meta.get("params", {}),
            "tutorialAnchors": anchors,
            "tutorialSteps": tutorial_steps,
            "knowledgeNodes": meta.get("knowledge_nodes", []),
        }
        index["templates"].append(tpl_entry)  # 仅用于 Synced 计数

        # C++ 模板暂不参与 C 模式 shadow 用例生成与 golden 生成
        if ext == "cpp":
            print(f"[CPP TEMPLATE] {meta['key']}: skipped shadow case generation")
            continue

        # 生成默认参数的 shadow 用例
        default_args = {k: v.get("default", "") for k, v in meta.get("params", {}).items()}
        rendered = render_template(source_c, default_args)
        case_name = f"{meta['key']}_default"

        # 写入生成的 .c（添加 @category 注释）
        c_path = GEN_DIR / f"{case_name}.c"
        c_content = f"// @category: baseline\n{rendered}\n"
        c_path.write_bytes(c_content.encode("utf-8"))
        gen_count += 1

        # 生成/更新 Golden .out
        out_path = GOLDEN_DIR / f"{case_name}.out"
        if not out_path.exists():
            try:
                out = run_with_clang(rendered)
                out_path.write_bytes(out.encode("utf-8"))
                golden_new += 1
                print(f"[NEW GOLDEN] {out_path.name}")
            except Exception as e:
                print(f"[GOLDEN FAIL] {case_name}: {e}")
                golden_fails.append((case_name, str(e)))
        else:
            golden_skipped += 1

    # G1 恢复注：原"写入 Flutter Index"步骤已随前端切割移除
    print(f"\nSynced {len(index['templates'])} templates")
    print(f"  Generated {gen_count} template cases -> {GEN_DIR}")
    print(f"  Golden: {golden_new} new, {golden_skipped} existing")

    if golden_fails:
        print(f"\n[WARNING] Golden generation failed for {len(golden_fails)} case(s), see {GOLDEN_DIR}/golden_failures.log")
        print(f"          Please analyze root causes and update {GOLDEN_DIR}/GOLDEN_FAILURES.md")
        log_path = GOLDEN_DIR / "golden_failures.log"
        lines = [f"# Generated {datetime.datetime.now().isoformat()}", ""]
        for case_name, reason in golden_fails:
            lines.append(f"{case_name}: {reason}")
        log_path.write_text("\n".join(lines), encoding="utf-8")

    # Baseline golden generation
    BASELINE_GOLDEN_DIR.mkdir(parents=True, exist_ok=True)
    baseline_new = 0
    baseline_skipped = 0
    baseline_fails = []
    if BASELINE_DIR.exists():
        for c_path in sorted(BASELINE_DIR.glob("*.c")):
            source = c_path.read_text(encoding="utf-8")
            lines = source.splitlines()
            if lines and lines[0].startswith("// @category:"):
                source = "\n".join(lines[1:])
            out_path = BASELINE_GOLDEN_DIR / f"{c_path.stem}.out"
            if out_path.exists():
                baseline_skipped += 1
                continue
            try:
                out = run_with_clang(source)
                out_path.write_bytes(out.encode("utf-8"))
                baseline_new += 1
            except Exception as e:
                baseline_fails.append((c_path.stem, str(e)))
        print(f"\nBaseline golden: {baseline_new} new, {baseline_skipped} existing")
        if baseline_fails:
            print(f"[WARNING] Baseline golden generation failed for {len(baseline_fails)} case(s)")


if __name__ == "__main__":
    sync()
