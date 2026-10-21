"""run_duel: one-command three-way duel driver (ISS-199, 2026-10-21).

Orchestrates the full pipeline from the Vitro repo root:
  1. build gateway dual flavors (js / nojs) via moon
  2. sanity both wasm host arms (wasmtime via wasmtime-py; wasmoon via its
     MoonBit host built against a wasmoon source checkout)
  3. generate per-case NDJSON requests from corpus/baseline
  4. run both arms over the corpus (parallel, per-arm timeout)
  5. optional: clang -O0 reference + three-way arbitration

Cross-platform by design: no bash, no hardcoded drives. The wasmoon arm build
branches on platform:
  - Windows: MSVC wrapper (vcvars + wasmoon-cl driver) is required because
    MSVC cl rejects C11 atomics used by the native stubs; the wrapper script
    lives next to this file (wasmoon_arm/build.cmd).
  - macOS/Linux: plain `moon build --target native` (clang handles C11
    atomics natively). NOTE: the Unix branch is written against the upstream
    CI layout but has not been exercised on this Windows machine.

Usage:
  python run_duel.py [--wasmoon-src DIR] [--corpus DIR] [--limit N]
                     [--workers N] [--skip-clang] [--skip-build]

`--wasmoon-src` must point at a wasmoon checkout (or worktree) containing
modules/wasmoon*. For reproducibility pin it to the upstream commit you want
to test (e.g. main after #552).
"""

import argparse
import json
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
IS_WIN = sys.platform == "win32"
NL = chr(10)
BS = chr(92)


def die(msg):
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(1)


def step(name):
    print(f"\n=== [{name}] ===", flush=True)


def sh(argv, **kw):
    print("+", " ".join(argv), flush=True)
    return subprocess.run(argv, **kw)


def find_vitro_root():
    # this file lives at <vitro>/scripts/wasm_arms/
    return os.path.dirname(os.path.dirname(HERE))


def which(name):
    from shutil import which as _w
    return _w(name)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--wasmoon-src",
                    default=os.path.join(os.path.dirname(find_vitro_root()), "wasmoon"),
                    help="wasmoon checkout containing modules/wasmoon* (default: sibling ./wasmoon)")
    ap.add_argument("--corpus", default=None, help="corpus dir (default: <vitro>/corpus/baseline)")
    ap.add_argument("--limit", type=int, default=0, help="only first N cases")
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--skip-clang", action="store_true")
    ap.add_argument("--skip-build", action="store_true", help="reuse existing gateway artifacts")
    args = ap.parse_args()

    vitro = find_vitro_root()
    corpus = args.corpus or os.path.join(vitro, "corpus", "baseline")
    cases_dir = os.path.join(HERE, "duel", "cases_per_case")
    wasmoon_src = os.path.abspath(args.wasmoon_src)

    step("0. environment check")
    if which("moon") is None:
        die("moon not in PATH")
    if not os.path.isdir(os.path.join(wasmoon_src, "modules", "wasmoon")):
        die(f"--wasmoon-src has no modules/wasmoon: {wasmoon_src}")
    if not args.skip_clang and which("clang") is None:
        die("clang not in PATH (--skip-clang to skip arbitration)")
    try:
        import wasmtime  # noqa: F401
    except ImportError:
        die("pip install wasmtime (python wasmtime arm)")
    print("wasmoon src:", wasmoon_src)
    print("corpus:", corpus)

    wasm_nojs = os.path.join(vitro, "moonbit", "_build", "wasm-gc", "release",
                             "build", "gateway", "wasm_nojs", "wasm_nojs.wasm")
    wasm_js = os.path.join(vitro, "moonbit", "_build", "wasm-gc", "release",
                           "build", "gateway", "wasm", "wasm.wasm")

    if not args.skip_build:
        step("1. gateway dual-flavor build")
        r = sh(["moon", "build", "--release", "--target", "wasm-gc",
                "gateway/wasm", "gateway/wasm_nojs"],
               cwd=os.path.join(vitro, "moonbit"))
        if r.returncode != 0:
            die("gateway dual-flavor build failed")
    if not (os.path.isfile(wasm_nojs) and os.path.isfile(wasm_js)):
        die("gateway artifacts missing; drop --skip-build")
    print(f"js-flavor:   {os.path.getsize(wasm_js)} bytes")
    print(f"nojs-flavor: {os.path.getsize(wasm_nojs)} bytes (duel artifact; import section must be 0)")

    step("2. wasmtime arm sanity (wasmtime-py)")
    ping = os.path.join(HERE, "duel", "_ping.ndjson")
    with open(ping, "w", encoding="utf-8", newline=NL) as f:
        f.write('{"method":"ping"}' + NL)
    wt = os.path.join(HERE, "wasmtime_arm", "wasmtime_arm.py")
    r = subprocess.run([sys.executable, wt, wasm_nojs, "--cases", ping],
                       capture_output=True, text=True, timeout=120)
    if "pong" not in r.stdout:
        die(f"wasmtime arm ping failed: ...{r.stdout[-160:]} ...{r.stderr[-160:]}")
    print("wasmtime arm:", r.stdout.strip().splitlines()[-1])

    step("3. wasmoon arm build + sanity")
    wasmoon_exe = build_wasmoon_arm(wasmoon_src)
    r = subprocess.run([wasmoon_exe, wasm_nojs, "--cases", ping],
                       capture_output=True, text=True, timeout=300)
    if "pong" not in r.stdout:
        die(f"wasmoon arm ping failed (if it hangs, the arm is likely linked against a "
            f"stale wasmoon instead of the pinned sources): ...{r.stdout[-160:]}")
    print("wasmoon arm:", r.stdout.strip().splitlines()[-1])

    step("4. corpus request generation")
    n = generate_cases(corpus, cases_dir)
    print(f"generated per-case files: {n}")

    step("5. dual-arm duel")
    runner = os.path.join(HERE, "duel", "runner.py")
    argv = [sys.executable, runner, "-wasm", wasm_nojs, "--workers", str(args.workers)]
    if args.limit:
        argv += ["--limit", str(args.limit)]
    r = sh(argv)
    duel_rc = r.returncode if r.returncode is not None else 1

    if args.skip_clang:
        print("\nSKIPPED: clang three-way arbitration (--skip-clang)")
        sys.exit(duel_rc)

    step("6. clang reference + three-way arbitration")
    arb = os.path.join(HERE, "duel", "arb.py")
    argv = [sys.executable, arb]
    if args.limit:
        argv.append(str(args.limit))
    r = sh(argv)

    step("7. done")
    sys.exit(max(duel_rc, r.returncode if r.returncode is not None else 1))


def build_wasmoon_arm(wasmoon_src):
    arm_dir = os.path.join(HERE, "wasmoon_arm")
    exe = os.path.join(HERE, "_build", "native", "debug", "build", "wasm_arms",
                       "wasmoon_arm", "wasmoon_arm.exe" if IS_WIN else "wasmoon_arm")
    mods = ["wasm_core", "wasmoon_runtime", "wasmoon", "wasmoon_jit",
            "wasm_milkir", "milkir", "vcode", "regalloc", "vcode_regalloc",
            "x64_target", "aarch64_target"]
    member_lines = ["members = [", '  "./wasmoon_arm",']
    for m in mods:
        member_lines.append(f'  "{forward(os.path.join(wasmoon_src, "modules", m))}",')
    member_lines.append("]")
    ws = os.path.join(HERE, "moon.work")
    with open(ws, "w", encoding="utf-8", newline=NL) as f:
        f.write(NL.join(member_lines) + NL)
    os.makedirs(os.path.join(HERE, ".mooncakes"), exist_ok=True)
    # a stale mooncakes/wasmoon shadows the workspace (both are "0.17.0"); drop it
    stale = os.path.join(HERE, ".mooncakes", "Milky2018")
    if os.path.isdir(stale):
        import shutil
        shutil.rmtree(stale)
    if IS_WIN:
        env = os.environ.copy()
        env["MOON_WORK"] = ws
        log = os.path.join(HERE, "_wasmoon_arm_build.log")
        with open(log, "w") as lf:
            r = subprocess.run(["cmd", "/c", os.path.join(arm_dir, "build.cmd")],
                               env=env, stdout=lf, stderr=subprocess.STDOUT)
        if r.returncode != 0:
            die(f"wasmoon arm build failed rc={r.returncode}; log: {log} (Windows needs "
                "vcvars64 + the wasmoon-cl driver wrapper; see wasmoon_arm/build.cmd)")
    else:
        env = os.environ.copy()
        env["MOON_WORK"] = ws
        r = sh(["moon", "build", "--target", "native"], cwd=arm_dir, env=env)
        if r.returncode != 0:
            die("wasmoon arm build failed (Unix branch; NOTE: not yet exercised on a Unix host)")
    if not os.path.isfile(exe):
        die(f"wasmoon arm exe missing after build: {exe}")
    return exe


def generate_cases(corpus, cases_dir):
    os.makedirs(cases_dir, exist_ok=True)
    for old in os.listdir(cases_dir):
        if old.endswith(".ndjson") and not old.startswith("_"):
            os.remove(os.path.join(cases_dir, old))
    n = 0
    for c in corpus_files(corpus):
        name = os.path.basename(c)[:-2]
        fls = [{"filename": name + ".c", "source": read(c)}]
        seen = {fls[0]["filename"]}
        queue = list(fls)
        while queue:  # recursive header collection (harness gap #4)
            cur = queue.pop()
            cur_dir = os.path.dirname(os.path.join(corpus, cur["filename"]))
            for inc in re.findall(r'#include\s+"([^"]+)"', cur["source"]):
                hp = os.path.normpath(os.path.join(cur_dir, inc))
                rel = os.path.relpath(hp, corpus).replace(os.sep, "/")
                if os.path.isfile(hp) and rel not in seen:
                    fls.append({"filename": rel, "source": read(hp)})
                    seen.add(rel)
                    queue.append(fls[-1])
        lines = [json.dumps({"method": "compile", "params": {"files": fls}}, ensure_ascii=False),
                 '{"method": "run"}',
                 '{"method": "output.delta"}']
        idx = len([x for x in os.listdir(cases_dir) if not x.startswith("_")])
        with open(os.path.join(cases_dir, f"cases_{idx:04d}.{name}.ndjson"),
                  "w", encoding="utf-8", newline=NL) as f:
            f.write(NL.join(lines) + NL)
        n += 1
    return n


def corpus_files(corpus):
    return [os.path.join(corpus, f) for f in sorted(os.listdir(corpus))
            if f.endswith(".c") and os.path.isfile(os.path.join(corpus, f))]


def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


def forward(p):
    return p.replace(BS, "/")


if __name__ == "__main__":
    main()
