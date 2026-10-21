"""runner——全语料对拍驱动（#199 独立防线版，2026-10-20）。

每用例独立进程（隔离 wasmoon 非确定性挂起与内存累积：单进程连跑时
GC/资源相关挂起会在 20+ 用例后出现，内存单调上涨——ISS-199 备注），
双臂并发各跑一份，per-case 30s 超时；Python 池 4 并发。

判据（与 corpus_fuzz 桶对齐）：
  AGREE            双臂逐帧 JSON 语义一致
  HOST_DIVERGENCE  同请求不同结果（宿主 bug，最高优先）
  WASMOON_TIMEOUT  wasmoon 臂超时（wasmtime 正常）
  WASMTIME_TIMEOUT 对称
  BOTH_TIMEOUT     双超时（可能是语料本身死循环，非宿主病）
  ARM_ERROR        臂进程异常退出

用法：python runner.py [-wasm path] [-cases dir] [--limit N]
输出：stdout 每用例一行 verdict JSON；末尾统计。
"""

import argparse
import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

WASMOON = r"D:\code\Vitro\scripts\wasm_arms\_build\native\debug\build\wasm_arms\wasmoon_arm\wasmoon_arm.exe"
WASMTIME = r"D:\code\Vitro\scripts\wasm_arms\wasmtime_arm\wasmtime_arm.py"
CASES_DIR = r"D:\code\Vitro\scripts\wasm_arms\duel\cases_per_case"
TIMEOUT = 30
# wasmtime-py lives on this interpreter (3.14.4); runner itself may run on another
PYTHON = "C:" + chr(92) + "Users" + chr(92) + "liangjingwei" + chr(92) + "AppData" + chr(92) + "Local" + chr(92) + "Programs" + chr(92) + "Python" + chr(92) + "Python314" + chr(92) + "python.exe"


def run_arm(exe: str, wasm: str, cases_path: str, timeout: int):
    argv = [PYTHON, exe, wasm, "--cases", cases_path] if exe.endswith(".py") else [exe, wasm, "--cases", cases_path]
    try:
        r = subprocess.run(
            argv,
            capture_output=True, text=True, timeout=timeout, encoding="utf-8", errors="replace",
        )
        frames = [l for l in r.stdout.splitlines() if l.strip()]
        return frames, None
    except subprocess.TimeoutExpired:
        return None, "TIMEOUT"
    except OSError as e:
        return None, str(e)


def duel_one(name: str, wasm: str, cases_path: str):
    wm_frames, wm_err = run_arm(WASMOON, wasm, cases_path, TIMEOUT)
    wt_frames, wt_err = run_arm(WASMTIME, wasm, cases_path, TIMEOUT)

    def is_timeout(e):
        return e == "TIMEOUT"

    if is_timeout(wm_err) and is_timeout(wt_err):
        return {"name": name, "verdict": "BOTH_TIMEOUT"}
    if is_timeout(wm_err):
        return {"name": name, "verdict": "WASMOON_TIMEOUT", "wasmtime": (wt_frames or ["?"])[-1][:200] if wt_frames else wt_err}
    if is_timeout(wt_err):
        return {"name": name, "verdict": "WASMTIME_TIMEOUT", "wasmoon": (wm_frames or ["?"])[-1][:200] if wm_frames else wm_err}
    if wm_err or wt_err:
        return {"name": name, "verdict": "ARM_ERROR", "detail": f"{wm_err} / {wt_err}"}
    if len(wm_frames) != len(wt_frames):
        return {"name": name, "verdict": "HOST_DIVERGENCE", "detail": f"frame count {len(wm_frames)} vs {len(wt_frames)}"}
    for a, b in zip(wm_frames, wt_frames):
        try:
            same = json.loads(a) == json.loads(b)
        except json.JSONDecodeError:
            same = a == b
        if not same:
            return {"name": name, "verdict": "HOST_DIVERGENCE",
                    "wasmoon": a[:400], "wasmtime": b[:400]}
    return {"name": name, "verdict": "AGREE"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-wasm", required=True)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--workers", type=int, default=4)
    args = ap.parse_args()

    cases = sorted(
        (os.path.join(CASES_DIR, f) for f in os.listdir(CASES_DIR)
         if f.endswith(".ndjson") and not f.startswith("_")
         and f.split("_", 1)[1].split(".", 1)[0].isdigit()),
        key=lambda p: int(os.path.basename(p).split("_")[1].split(".")[0]),
    )
    if args.limit:
        cases = cases[: args.limit]
    names = {
        p: os.path.basename(p)[6:-7]  # strip "cases_<n>." and ".ndjson"
        for p in cases
    }

    print(f"cases: {len(cases)}  workers: {args.workers}", file=sys.stderr)
    counts = {}
    divergent = []
    done = 0

    def work(p):
        return p, duel_one(names[p], args.wasm, p)

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        for p, v in pool.map(work, cases):
            done += 1
            counts[v["verdict"]] = counts.get(v["verdict"], 0) + 1
            print(json.dumps(v, ensure_ascii=False), flush=True)
            if v["verdict"] != "AGREE":
                divergent.append(v)
            if done % 25 == 0:
                print(f"  progress {done}/{len(cases)}: {counts}", file=sys.stderr)

    print("== SUMMARY ==")
    for k, n in sorted(counts.items()):
        print(f"  {k}: {n}")
    if divergent:
        print("non-AGREE cases:")
        for v in divergent:
            print(f"  {v['name']}: {v['verdict']} {v.get('detail','')[:120]}")


if __name__ == "__main__":
    main()
