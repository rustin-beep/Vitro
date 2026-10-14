#!/usr/bin/env python3
"""LLM 语料探针 · 生成 + 四裁判模板（从实跑批蒸馏）。

用法：改 CFG 段 → 交给计划任务跑（**不要**在 agent 会话里跑生成/判据，见 skill 04 C12–C14）。

内置的"判据五铁律"（改代码时别删）：
  1. fail loud —— 裁判启动失败记 JUDGE_ERROR，禁静默当 REJECT
  2. subprocess 一律 bytes，禁 text=True（计划任务里会读成空串）
  3. Windows 找 exe 用当前进程 PATH ⇒ clang/gcc/node/被测 exe 全用绝对路径
  4. vitro 的 rc 是编译结果，判据必须解析 stdout 的 JSON 帧
  5. 帧两种 ok（外层=命令成功 / frame.result.ok=编译结果），三种形状都认
"""
import json, os, re, subprocess, time, urllib.error, urllib.request

# ───────────────────────── CFG ─────────────────────────
RF      = r"<工作目录>"
PROMPTS = os.path.join(RF, "prompts.json")
OUTD    = os.path.join(RF, "gen")
LOG     = os.path.join(RF, "gen.log")
RESJ    = os.path.join(RF, "gen.json")
DONE, FAIL = os.path.join(RF, "DONE.txt"), os.path.join(RF, "FAIL.txt")

SERVER  = r"<llama.cpp>\llama-server.exe"          # 生成侧
# ★ 判据侧：一律指向**冻结快照**（复制自足目录），不用工作区里那个
JUDGE_DIR  = os.path.join(RF, "_judge_v1")
NATIVE_EXE = os.path.join(JUDGE_DIR, "vitro.exe")
NODE       = r"C:\Program Files\nodejs\node.exe"
WASM_JS    = os.path.join(JUDGE_DIR, "scripts", "vitro_cli", "main.js")
CLANG      = r"C:\clang+llvm-22.1.4-x86_64-pc-windows-msvc\bin\clang.exe"
GCC        = r"D:\code\mingw64\bin\gcc.exe"

MODELS  = [("tag", r"<model.gguf>", "显示名"), ]      # 顺序执行，一时刻只驻留一个模型
PORT    = 8092
SAMPLES = 2
MAXTOK  = 2000
# ──────────────────────────────────────────────────────

def judge_id():
    """冻结快照指纹 —— 结果按它归属；快照变了整批重判。"""
    try:
        d = json.load(open(os.path.join(JUDGE_DIR, "judge_fingerprint.json"), encoding="utf-8"))
        return d["vitro.exe"]["sha256"][:12]
    except Exception:
        return "unknown"

JID = judge_id()

def log(*a):
    m = f"[{time.strftime('%m-%d %H:%M:%S')}] " + " ".join(str(x) for x in a)
    with open(LOG, "a", encoding="utf-8") as f: f.write(m + "\n")
    print(m, flush=True)

# ── 生成 ──
def chat(prompt, temp):
    # ★ 关思考：Qwen 用 enable_thinking、gpt-oss 用 reasoning_effort —— 两个都发，400 时逐级降级
    body = {"model": "g", "messages": [{"role": "user", "content": prompt}],
            "max_tokens": MAXTOK, "temperature": temp, "stream": False,
            "chat_template_kwargs": {"enable_thinking": False, "reasoning_effort": "low"}}
    for attempt in (1, 2, 3):
        try:
            req = urllib.request.Request(f"http://127.0.0.1:{PORT}/v1/chat/completions",
                data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
            t0 = time.time()
            r = json.load(urllib.request.urlopen(req, timeout=1800))
            m = r["choices"][0]["message"]
            return (m.get("content") or m.get("reasoning_content") or ""), time.time() - t0
        except urllib.error.HTTPError as e:
            if e.code == 400 and attempt == 1:
                body["chat_template_kwargs"] = {"enable_thinking": False}; continue
            if e.code == 400 and attempt == 2:
                body.pop("chat_template_kwargs", None); continue
            log(f"    chat HTTP {e.code}"); return "", 0
        except Exception as e:
            log(f"    chat err {e!r}"); time.sleep(3)
    return "", 0

def extract_c(s):
    if not s: return ""
    m = re.findall(r"```(?:c|cpp)?\s*\n(.*?)```", s, re.S)
    return (m[-1] if m else s).strip()

# ── 判据 ──
def run(cmd, env=None):
    """★ 铁律 2：bytes 模式。"""
    try:
        p = subprocess.run(cmd, capture_output=True, timeout=240, env=env)
    except FileNotFoundError as e:
        return -1, "", f"NOT_FOUND:{e}"
    except Exception as e:
        return -2, "", repr(e)
    dec = lambda b: (b or b"").decode("utf-8", errors="replace")
    return p.returncode, dec(p.stdout), dec(p.stderr)

def verdict(rc, tool):
    """★ 铁律 1：未知一律 JUDGE_ERROR。"""
    if rc == 0: return "ACCEPT"
    if rc == 1: return "REJECT"
    return f"JUDGE_ERROR(rc={rc}:{tool})"

def parse_vitro(so, rc=None):
    """★ 铁律 5：三种帧形状都认。"""
    for line in so.splitlines():
        line = line.strip()
        if not line.startswith("{"): continue
        try: d = json.loads(line)
        except Exception: continue
        fr = d.get("frame") if isinstance(d.get("frame"), dict) else {}
        r = d.get("result") or (fr.get("result") if fr else None) or {}
        if isinstance(r, dict) and "ok" in r:
            return ("ACCEPT" if r["ok"] else "REJECT"), [x.get("code") for x in (r.get("diagnostics") or [])][:8]
        if fr and "ok" in fr:
            return ("ACCEPT" if fr["ok"] else "REJECT"), [x.get("code") for x in (fr.get("diagnostics") or [])][:8]
        if "ok" in d:
            return ("ACCEPT" if d["ok"] else "REJECT"), [x.get("code") for x in (d.get("diagnostics") or [])][:8]
    return (f"JUDGE_ERROR(no-frame,rc={rc},len={len(so)})", [])

def judge(path, env):
    """
    ★ 铁律 4：rc 只作旁证，判定看帧。
    """
    rc, _, _ = run([CLANG, "-w", "-fsyntax-only", path]); cl = verdict(rc, "clang")
    rc, _, _ = run([GCC,   "-w", "-fsyntax-only", path]); gc = verdict(rc, "gcc")
    rc, so, _ = run([NATIVE_EXE, "compile", path, "--json"], env=env); n, nc = parse_vitro(so, rc)
    rc, so, _ = run([NODE, WASM_JS, "compile", path, "--json"], env=env); w, wc = parse_vitro(so, rc)
    return {"clang": cl, "gcc": gc, "wasm": w, "native": n,
            "wasm_codes": wc, "native_codes": nc, "judge_id": JID}

def bucket(r, expect):
    """顺序敏感：判据自身故障最先暴露，臂分歧次之。"""
    vals = [r["clang"], r["gcc"], r["wasm"], r["native"]]
    if any(str(v).startswith("JUDGE_ERROR") for v in vals): return "judge_error"
    if r["wasm"] != r["native"]: return "arm_divergence"
    if r["clang"] == "REJECT" and r["wasm"] == "ACCEPT": return "vitro_accept_clang_reject"
    if r["clang"] == "ACCEPT" and r["wasm"] == "REJECT": return "vitro_reject_clang_accept"
    if r["clang"] != r["gcc"]: return "judge_divergence"
    return "no_signal"

# ── 服务 ──
def start_server(mpath, tag):
    so = open(os.path.join(RF, f"server_{tag}.log"), "w")
    p = subprocess.Popen([SERVER, "-m", mpath, "--host", "127.0.0.1", "--port", str(PORT),
                          "-ngl", "999", "-c", "8192", "--jinja"],
                         stdout=so, stderr=subprocess.STDOUT)
    for _ in range(180):
        try:
            urllib.request.urlopen(f"http://127.0.0.1:{PORT}/v1/models", timeout=5); return p
        except Exception:
            if p.poll() is not None: log(f"  !! 服务退出 rc={p.returncode}"); return None
            time.sleep(5)
    log("  !! 服务超时"); return None

def baseline():
    try:
        out = subprocess.run(["git", "-C", os.path.dirname(RF), "rev-parse", "HEAD"],
                             capture_output=True).stdout.decode().strip()
    except Exception:
        out = "?"
    json.dump({"head": out, "at": time.strftime("%Y-%m-%d %H:%M:%S")},
              open(os.path.join(RF, "baseline.json"), "w", encoding="utf-8"), indent=2)
    return out

def main():
    for f in (DONE, FAIL):
        try: os.remove(f)
        except OSError: pass
    os.makedirs(OUTD, exist_ok=True)
    spec = json.load(open(PROMPTS, encoding="utf-8"))
    plist, meta = spec["prompts"], spec["meta"]
    log("=" * 64)
    log(f"判据基线 HEAD = {baseline()}   判据快照 {JID}")
    log(f"{len(MODELS)} 模型 × {len(plist)} 提示词 × {SAMPLES} 采样 = {len(MODELS)*len(plist)*SAMPLES} 例")

    env = dict(os.environ)
    env["PATH"] = ";".join([os.path.dirname(CLANG), os.path.dirname(GCC),
                            os.path.dirname(NODE)]) + ";" + env.get("PATH", "")

    rows = json.load(open(RESJ, encoding="utf-8")) if os.path.exists(RESJ) else []
    BAD = ("judge_error", "NO_CODE")
    # ★ 判据换了 / 坏结果 ⇒ 按**已有源码**重判，不重生成
    stale = [r for r in rows if r.get("bucket") in BAD or r.get("judge_id") != JID]
    if stale:
        log(f"  需重判 {len(stale)} 条")
        for r in stale:
            cp = os.path.join(OUTD, r["model"], f"{r['pid']}_s{r['sample']}.c")
            if not os.path.exists(cp): continue
            v = judge(cp, env)
            v.update({k: r.get(k) for k in ("model", "mname", "pid", "expect", "sample", "axis", "target")})
            v["bucket"] = bucket(v, r["expect"])
            rows[rows.index(r)] = v
            json.dump(rows, open(RESJ, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    rows = [r for r in rows if r.get("bucket") not in BAD and r.get("judge_id") == JID]
    done = {(r["model"], r["pid"], r["sample"]) for r in rows}

    for tag, mpath, mname in MODELS:
        need = [(p, s) for p in plist for s in range(1, SAMPLES + 1) if (tag, p["id"], s) not in done]
        if not need: log(f"=== {mname}：已完成，跳过 ==="); continue
        log(f"=== {mname} ===")
        if not os.path.exists(mpath): log(f"  !! 模型不存在 {mpath}"); continue
        mdir = os.path.join(OUTD, tag); os.makedirs(os.path.join(mdir, "raw"), exist_ok=True)
        srv = start_server(mpath, tag)
        if srv is None: continue
        try:
            for pp, s in need:
                pid, exp = pp["id"], pp["expect"]
                log(f"  [{tag}] {pid} s{s}")
                txt, code, dt = "", "", 0
                tpl = meta["template_p"] if exp == "correct" else meta["template_n"]
                for t in range(3):
                    txt, dt = chat(tpl.format(DIR=pp["dir"]), 0.5 if exp == "correct" else 1.0)
                    code = extract_c(txt)
                    if not (len(code) < 150 or "main" not in code): break
                    log(f"    截断/空，重试 {t+1}")
                open(os.path.join(mdir, "raw", f"{pid}_s{s}.txt"), "w", encoding="utf-8").write(txt)
                if not code.strip():
                    rows.append({"model": tag, "mname": mname, "pid": pid, "expect": exp,
                                 "sample": s, "bucket": "NO_CODE", "judge_id": JID,
                                 "axis": pp["axis"], "target": pp.get("target", "")})
                else:
                    cp = os.path.join(mdir, f"{pid}_s{s}.c")
                    open(cp, "w", encoding="utf-8", newline="\n").write(code + "\n")
                    v = judge(cp, env)
                    v.update({"model": tag, "mname": mname, "pid": pid, "expect": exp, "sample": s,
                              "axis": pp["axis"], "target": pp.get("target", ""),
                              "bytes": len(code), "dt": round(dt, 1)})
                    v["bucket"] = bucket(v, exp); rows.append(v)
                    log(f"    clang={v['clang']} gcc={v['gcc']} wasm={v['wasm']}({','.join(v['wasm_codes'])})"
                        f" native={v['native']} => {v['bucket']}")
                json.dump(rows, open(RESJ, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        finally:
            try: srv.terminate(); time.sleep(3); srv.kill()
            except Exception: pass

    from collections import Counter
    per = {}
    for r in rows: per.setdefault(r["model"], Counter())[r["bucket"]] += 1
    for k, c in per.items(): log(f"  {k}: {dict(c)}")
    bad = len([r for r in rows if r["bucket"] in BAD])
    (open(DONE, "w") if bad <= len(rows) * 0.3 else open(FAIL, "w")).write("ok\n" if bad <= len(rows)*0.3 else "fail\n")
    log(f"结束：{len(rows)} 条，坏结果 {bad}")

# ★ 会话外必带：任务环境丢弃 stderr ⇒ 未捕获异常只会表现为「日志停在半路 + 结果码 1」
try:
    main()
except Exception:
    import traceback
    log("!! 未捕获异常：")
    for line in traceback.format_exc().splitlines():
        log("   " + line)
    raise
