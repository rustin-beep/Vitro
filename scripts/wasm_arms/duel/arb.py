"""arb: three-way arbitration wasmoon x wasmtime x clang (ISS-199, 2026-10-21).

Per case: compile -> run -> output.delta on both wasm hosts, then compare the
delta payload (guest stdout) against a clang -O0 reference. The engine appends
a localized footer to program stdout; strip everything from the footer marker
on before comparing.
"""
import json
import os
import pickle
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

BASE = os.path.dirname(os.path.abspath(__file__))
PY = os.path.join("C:" + os.sep + "Users", "liangjingwei", "AppData", "Local",
                  "Programs", "Python", "Python314", "python.exe")
WASMOON = os.path.join(os.path.dirname(BASE), "_build", "native", "debug", "build", "wasm_arms",
                       "wasmoon_arm", "wasmoon_arm.exe")
WT = os.path.join(BASE, "..", "wasmtime_arm", "wasmtime_arm.py")
WASM = os.path.join("D:" + os.sep + "code", "Vitro", "moonbit", "_build",
                    "wasm-gc", "release", "build", "gateway", "wasm_nojs", "wasm_nojs.wasm")
CASES = os.path.join(BASE, "cases_per_case")
CLANG_PICKLE = os.path.join("C:" + os.sep + "Users", "liangjingwei", "AppData",
                            "Local", "Temp", "clang_ref", "clang_ref.pkl")
TMO = 300
NL = chr(10)

CLANG = pickle.load(open(CLANG_PICKLE, "rb"))


def frames(exe, is_py, wasm, cases):
    argv = ([PY, exe] if is_py else [exe]) + [wasm, "--cases", cases]
    try:
        r = subprocess.run(argv, capture_output=True, timeout=TMO,
                           encoding="utf-8", errors="replace")
        return [l for l in r.stdout.splitlines() if l.strip()], None
    except subprocess.TimeoutExpired:
        return None, "TIMEOUT"
    except OSError as e:
        return None, str(e)


def strip_footer(delta):
    # The delta payload arrives mojibake'd (engine UTF-8 bytes surfaced as
    # Latin-1 code points) and is not losslessly recoverable here; program
    # output is ASCII in this corpus, so cutting at the first non-ASCII
    # byte removes the localized footer while keeping the program output.
    for i, ch in enumerate(delta):
        if ord(ch) > 127:
            return delta[:i]
    return delta


def one(f):
    name = f.split(".", 1)[1].replace(".ndjson", "")
    src = os.path.join(CASES, f)
    lines = open(src, encoding="utf-8").read().splitlines()
    lines.append(json.dumps({"method": "output.delta"}))
    import threading
    q = os.path.join(CASES, "_with_delta_" + str(threading.get_ident()) + ".ndjson")
    with open(q, "w", encoding="utf-8", newline=NL) as fh:
        fh.write(NL.join(lines) + NL)

    wm, wme = frames(WASMOON, False, WASM, q)
    wt, wte = frames(WT, True, WASM, q)
    if wme or wte:
        return {"name": name, "verdict": "ARM-FAIL", "detail": f"{wme} / {wte}"}
    if len(wm) < 3 or len(wt) < 3:
        return {"name": name, "verdict": "FRAME-SHORT", "detail": f"{len(wm)}/{len(wt)}"}
    try:
        runf = json.loads(wm[1])
        runf2 = json.loads(wt[1])
        d_wm = json.loads(wm[2])
        d_wt = json.loads(wt[2])
    except json.JSONDecodeError:
        return {"name": name, "verdict": "JSON-BAD", "detail": wm[-1][:80]}
    out = d_wm.get("result", {}).get("delta", "")
    if out != d_wt.get("result", {}).get("delta", ""):
        return {"name": name, "verdict": "HOST-DIVERGE", "detail": out[:80]}
    status = runf.get("result", {}).get("status", "")
    if status == "trap":
        return {"name": name, "verdict": "TRAP"}
    ref = CLANG.get(name + ".c")
    if not ref:
        return {"name": name, "verdict": "NO-REF"}
    tag, refout = ref
    if tag == "COMPILE-ERROR":
        return {"name": name, "verdict": "CLANG-REJECT"}
    clean = strip_footer(out)
    # Windows clang emits CRLF; engine emits LF. Normalize before comparing
    # (same norm() discipline as corpus_fuzz).
    norm = lambda s: s.replace("\r\n", "\n").rstrip()
    if norm(clean) == norm(refout):
        return {"name": name, "verdict": "AGREE-CLANG"}
    return {"name": name, "verdict": "DIFF-VS-CLANG",
            "engine": clean[:200], "clang": refout[:200]}


def main():
    limit = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    files = sorted(f for f in os.listdir(CASES)
                   if f.endswith(".ndjson") and not f.startswith("_"))
    if limit:
        files = files[:limit]
    print("cases:", len(files), file=sys.stderr)
    counts = {}
    bad = []
    with ThreadPoolExecutor(max_workers=4) as pool:
        for v in pool.map(one, files):
            counts[v["verdict"]] = counts.get(v["verdict"], 0) + 1
            if v["verdict"] not in ("AGREE-CLANG", "TRAP", "CLANG-REJECT"):
                bad.append(v)
    print("SUMMARY:", dict(sorted(counts.items())))
    for v in bad:
        print(json.dumps(v, ensure_ascii=False)[:400])


if __name__ == "__main__":
    main()
