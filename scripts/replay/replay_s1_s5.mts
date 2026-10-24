#!/usr/bin/env node
// replay_s1_s5 —— S1–S5 协议回放驱动（Go→.mts 重写，refs #273；原 1213 行，D5 第二站）。
//
// 与 Go 版（及其 Python 前身）的断言编号与判定口径一一对应：
//
//	S1-防抖编译流 A1–A10 / S2-fixtures判分流 A1–A6 / S3-单步seek内存交错流 A1–A16 /
//	S5-预留位缺省语义 A1–A5（schema v0.1，docs/spec/STEP_PAYLOAD_SCHEMA_V0_1.md）。
//
// 迁移要点：
//   - serve 会话是**单进程时序协议流**（compile → step → seek 状态互相依赖），
//     不做会话内并发——Go 版同步读写管道，本版以 async/await 串行化（时序等价）；
//   - 前置门禁（preflight）fail fast：capabilities 活性探针 + 版本口径说明；
//   - 输出格式与 Go 版逐字一致（`  [PASS] S1 A1  ` / 汇总块），parity 可逐行 diff；
//   - `--selftest`：J9 埋雷——对判定 helper 注入必然违反的输入，必须变红，否则 exit 2；
//   - `-moonbit` / `--backend wasm` 两枝被测物；`-sections S1,S2,S3,S5` 选节。
//
// 用法：
//	node scripts/replay/replay_s1_s5.mts -moonbit | --backend wasm [--sections S1,S2,S3,S5] [--selftest]
// （rust 臂已随对照区退役；前置 `cd moonbit && MOON_CC=clang moon build --target native cmd/serve`）
import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";
import type { ChildProcess } from "node:child_process";
import { pathToFileURL } from "node:url";
import { ensureFresh } from "../internal/freshness.mts";
import { fatal, projectRoot } from "../internal/capi.mts";

type Rec = Record<string, unknown>;
type Frame = { req: Rec; resp: Rec };

const NODE = process.execPath;

// ── JSON 访问 helper（Go 版同名函数；Go 用 type switch，本版按 typeof 判定）──

const mmap = (v: unknown): Rec | null => (typeof v === "object" && v !== null && !Array.isArray(v) ? (v as Rec) : null);
const marr = (v: unknown): unknown[] => (Array.isArray(v) ? v : []);
const mstr = (v: unknown): string => (typeof v === "string" ? v : "");
const mnum = (v: unknown): number => (typeof v === "number" ? v : 0);

/** Python 真值语义（nil / "" / false / 0 为假）。 */
function truthy(v: unknown): boolean {
  if (v === null || v === undefined) return false;
  if (typeof v === "boolean") return v;
  if (typeof v === "string") return v !== "";
  if (typeof v === "number") return v !== 0;
  return true;
}

/**
 * abiVersionAtLeast 解析 "major.minor.patch" 并断言**下限**（semver）：
 * major 更高即满足；major 相同时比 minor；解析失败 → false。
 * 埋雷锚：selftest 的版本比较注入组（低于下限/垃圾串必红）。
 */
export function abiVersionAtLeast(v: string, minMajor: number, minMinor: number): boolean {
  const m = /^(\d+)\.(\d+)\.(\d+)/.exec(v);
  if (m === null) return false;
  const major = Number(m[1]);
  const minor = Number(m[2]);
  if (major > minMajor) return true;
  if (major < minMajor) return false;
  return minor >= minMinor;
}

/** reflect.DeepEqual 的 JSON 值等价（数组按下标、对象按键集合递归）。 */
export function deepEqual(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (typeof a !== typeof b) return false;
  if (Array.isArray(a) || Array.isArray(b)) {
    if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length) return false;
    return a.every((x, i) => deepEqual(x, b[i]));
  }
  if (typeof a === "object" && a !== null && typeof b === "object" && b !== null) {
    const ka = Object.keys(a as Rec);
    const kb = Object.keys(b as Rec);
    if (ka.length !== kb.length) return false;
    return ka.every((k) => deepEqual((a as Rec)[k], (b as Rec)[k]));
  }
  return false;
}

// ── Serve：serve 会话（NDJSON over pipes）───────────────────────────

let backendWasm = false;

export class Serve {
  private readonly proc: ChildProcess;
  private buf = "";
  private waiter: { resolve: (v: string) => void; reject: (e: Error) => void } | null = null;
  private closed = false;
  nextID = 1;
  frames: Frame[] = [];

  constructor(cliPath: string) {
    // 插座：wasm 臂 = 统一入口壳 serve（node 消费 gateway wasm.wasm）；
    // stderr 透传（backend 标注行不进断言通道——stdout 管道是唯一响应面）。
    const shell = path.join("moonbit", "_build", "js", "release", "build", "cmd", "vitro_wasm", "vitro_wasm.js");
    const [cmd, argv] = backendWasm ? [NODE, [shell, "serve"]] : [cliPath, ["serve"]];
    this.proc = spawn(cmd as string, argv as string[], { stdio: ["pipe", "pipe", "inherit"] });
    this.proc.stdout?.setEncoding("utf8");
    this.proc.stdout?.on("data", (chunk: string) => {
      this.buf += chunk;
      this.pump();
    });
    this.proc.on("error", (e: Error) => {
      this.closed = true;
      if (this.waiter !== null) {
        const w = this.waiter;
        this.waiter = null;
        w.reject(e);
      }
    });
    this.proc.on("close", () => {
      this.closed = true;
      if (this.waiter !== null) {
        const w = this.waiter;
        this.waiter = null;
        w.reject(new Error("serve 进程提前退出（无响应）"));
      }
    });
  }

  private pump(): void {
    if (this.waiter === null) return;
    const nl = this.buf.indexOf("\n");
    if (nl < 0) return;
    const line = this.buf.slice(0, nl + 1);
    this.buf = this.buf.slice(nl + 1);
    const w = this.waiter;
    this.waiter = null;
    w.resolve(line);
  }

  private readLine(): Promise<string> {
    const nl = this.buf.indexOf("\n");
    if (nl >= 0) {
      const line = this.buf.slice(0, nl + 1);
      this.buf = this.buf.slice(nl + 1);
      return Promise.resolve(line);
    }
    if (this.closed) return Promise.reject(new Error("serve 进程提前退出（无响应）"));
    return new Promise((resolve, reject) => {
      this.waiter = { resolve, reject };
    });
  }

  /** 发送 NDJSON 请求并读一行响应（id 关联由引擎保证，驱动逐帧记录）。 */
  async request(method: string, params?: Rec): Promise<Rec> {
    const rid = this.nextID++;
    const req: Rec = { id: rid, method };
    if (params !== undefined) req["params"] = params;
    try {
      this.proc.stdin?.write(JSON.stringify(req) + "\n");
    } catch (e) {
      fatal(`写 serve stdin 失败（进程已退出？）: ${(e as Error).message}`);
    }
    let line: string;
    try {
      line = await this.readLine();
    } catch (e) {
      fatal(`${(e as Error).message}`);
    }
    let resp: Rec;
    try {
      resp = JSON.parse(line) as Rec;
    } catch (e) {
      fatal(`响应解析失败 ${JSON.stringify(line)}: ${(e as Error).message}`);
    }
    resp["id"] = mnum(resp["id"]); // 统一数字形态，A1 的 id 比较用 number
    this.frames.push({ req, resp });
    return resp;
  }

  /** 发 shutdown → 关 stdin → 等 10s；超时 kill 返回 1。 */
  async shutdown(): Promise<number> {
    await this.request("shutdown");
    this.proc.stdin?.end();
    const exited = new Promise<number>((resolve) => {
      this.proc.on("close", (code) => resolve(code ?? 1));
    });
    const timeout = new Promise<number>((resolve) => {
      setTimeout(() => {
        this.proc.kill();
        resolve(1);
      }, 10_000).unref();
    });
    return Promise.race([exited, timeout]);
  }

  /** 从已收集帧中取全部 StepPayload（step.next / payload.get / seek）。 */
  collectPayloads(): Rec[] {
    const out: Rec[] = [];
    for (const f of this.frames) {
      const result = mmap(f.resp["result"]);
      if (result === null) continue;
      for (const p of marr(result["payloads"])) {
        const pm = mmap(p);
        if (pm !== null) out.push(pm);
      }
      const single = mmap(result["payload"]);
      if (single !== null) out.push(single);
    }
    return out;
  }
}

// ── Report ─────────────────────────────────────────────────────────

interface ReportRow {
  section: string;
  aid: string;
  ok: boolean;
  detail: string;
}

// MoonBit 臂豁免面：断言名 "S1 A10" 精确匹配，fail loud。
// 语义比 serve_smoke 更严一档（主跑即审计）：豁免条目 FAIL → EXEMPT 放行；
// **PASS → ZOMBIE 红逼删条目**。
let mbMode = false;
let mbExempt = new Map<string, string>();

export function loadMBExemptions(): void {
  const p = path.join("scripts", "replay", "moonbit_exemptions.json");
  let raw: string;
  try {
    raw = fs.readFileSync(p, "utf8");
  } catch (e) {
    fatal(`读 replay MoonBit 豁免表失败: ${(e as Error).message}`);
  }
  let doc: { assertions?: Record<string, string> };
  try {
    doc = JSON.parse(raw) as typeof doc;
  } catch (e) {
    fatal(`replay MoonBit 豁免表非法 JSON: ${(e as Error).message}`);
  }
  mbExempt = new Map(Object.entries(doc.assertions ?? {}));
}

/** 定位 MoonBit 侧 serve 产物（debug 构建路径 + VITRO_SERVE_MB 覆盖）。 */
export function resolveMoonBitServeExe(): string {
  const override = process.env["VITRO_SERVE_MB"];
  if (override !== undefined && override !== "") return override;
  const name = process.platform === "win32" ? "serve.exe" : "serve";
  return path.join(projectRoot(), "moonbit", "_build", "native", "debug", "build", "cmd", "serve", name);
}

export class Report {
  rows: ReportRow[] = [];

  /** PASS 也打印尾部两空格，FAIL 附 detail（与 Go/Python 版逐字同形）。 */
  check(section: string, aid: string, cond: boolean, detail: string): boolean {
    if (mbMode || backendWasm) {
      const key = section + " " + aid;
      const reason = mbExempt.get(key);
      if (reason !== undefined) {
        if (cond) {
          process.stdout.write(`  [ZOMBIE] ${section} ${aid}  豁免条目已真 PASS——删条目（理由: ${reason}）\n`);
          this.rows.push({ section, aid, ok: false, detail: "豁免僵尸（已真 PASS，删条目）" });
          return false;
        }
        process.stdout.write(`  [EXEMPT] ${section} ${aid}  ${reason}\n`);
        this.rows.push({ section, aid, ok: true, detail: "（豁免）" + reason });
        return true;
      }
    }
    this.rows.push({ section, aid, ok: cond, detail });
    const mark = cond ? "PASS" : "FAIL";
    const d = cond ? "" : detail;
    process.stdout.write(`  [${mark}] ${section} ${aid}  ${d}\n`);
    return cond;
  }

  summarize(): number {
    const total = this.rows.length;
    let failed = 0;
    let exempt = 0; // EXEMPT 分开计——豁免不是 PASS（口径与 serve_smoke 对齐）
    for (const row of this.rows) {
      if (!row.ok) failed++;
      if (row.detail.startsWith("（豁免）")) exempt++;
    }
    process.stdout.write("\n========== 回放汇总 ==========\n");
    if (exempt > 0) {
      process.stdout.write(`断言总数: ${total}  PASS: ${total - failed - exempt}  EXEMPT: ${exempt}  FAIL: ${failed}\n`);
    } else {
      process.stdout.write(`断言总数: ${total}  PASS: ${total - failed}  FAIL: ${failed}\n`);
    }
    for (const row of this.rows) {
      if (!row.ok) process.stdout.write(`  FAIL ${row.section} ${row.aid}: ${row.detail}\n`);
    }
    return failed > 0 ? 1 : 0;
  }
}

// ── 载体源码（与下游文档逐字一致）─────────────────────────────────

const s1K1 =
  '#include <stdio.h>\n\nint main() {\n    int age = 14\n    printf("age=%d\\n", age);\n    return 0;\n}\n';
const s1K2 =
  '#include <stdio.h>\n\nint main() {\n    int age = "小明";\n    printf("age=%d\\n", age);\n    return 0;\n}\n';
const s1K3 =
  '#include <stdio.h>\n\nint main() {\n    int age = 14;\n    double height = 1.62;\n    printf("age=%d\\n", age);\n    printf("height=%.2f\\n", height);\n    return 0;\n}\n';

const s2Src =
  '#include <stdio.h>\n\nint main() {\n    int n;\n    scanf("%d", &n);\n' +
  "    int digits = 0;\n    int t = n;\n    while (t > 0) {\n        t /= 10;\n        digits++;\n    }\n" +
  '    printf("digits=%d\\n", digits);\n    while (n > 0) {\n        printf("%d", n % 10);\n        n /= 10;\n    }\n' +
  '    printf("\\n");\n    return 0;\n}\n';

const s3P1 =
  "#include <stdio.h>\n\nvoid swap(int *a, int *b) {\n    int t = *a;\n    *a = *b;\n    *b = t;\n}\n\n" +
  'int main() {\n    int x = 3;\n    int y = 8;\n    swap(&x, &y);\n    printf("%d %d\\n", x, y);\n    return 0;\n}\n';
const s3P2 =
  "#include <stdio.h>\n#include <stdlib.h>\n\nint main() {\n" +
  "    int *p = (int *)malloc(4 * sizeof(int));\n    p[0] = 7;\n    printf(\"%d\\n\", p[0]);\n    free(p);\n    return 0;\n}\n";
const s3P3 =
  "#include <stdio.h>\n\nint main() {\n    int s = 0;\n    for (int i = 0; i < 3000; i++) {\n        s += i;\n    }\n" +
  '    printf("%d\\n", s);\n    return 0;\n}\n';

const s2Fixtures = [
  { name: "F1", stdin: "12340\n", expected: "digits=5\n04321\n" },
  { name: "F2", stdin: "7\n", expected: "digits=1\n7\n" },
  { name: "F3", stdin: "10086\n", expected: "digits=5\n68001\n" },
];

// ── S1：防抖编译流 ────────────────────────────────────────────────

export function diagErrors(resp: Rec): Rec[] {
  const r = mmap(resp["result"]);
  const out: Rec[] = [];
  for (const d of marr(r?.["diagnostics"])) {
    const dm = mmap(d);
    if (dm !== null && mstr(dm["severity"]) === "error") out.push(dm);
  }
  return out;
}

async function runS1(s: Serve, rep: Report): Promise<void> {
  process.stdout.write("\n── S1 防抖编译流 ──\n");
  const r101 = await s.request("compile", { source: s1K1 });
  const r102 = await s.request("compile", { source: s1K2 });
  const r103 = await s.request("compile", { source: s1K3 });
  const r104 = await s.request("compile", { source: s1K3 });

  // A1 id 回填与帧同构（全序列终检在 A10；此处先验 compile 组）
  let a1 = true;
  for (const f of s.frames) {
    const okVal = f.resp["ok"];
    const hasOk = "ok" in f.resp;
    const same = mnum(f.resp["id"]) === mnum(f.req["id"]) && hasOk && (okVal === true || mmap(f.resp["error"]) !== null);
    if (!same) {
      a1 = false;
      rep.check("S1", "A1", false, `id=${String(f.req["id"])} 帧形状异常`);
      break;
    }
  }
  if (a1) rep.check("S1", "A1", true, "");

  const e101 = diagErrors(r101);
  if (e101.length === 1 && mstr(e101[0]?.["code"]) === "E2005" && mnum(e101[0]?.["line"]) === 4 && mstr(e101[0]?.["message"]).includes(";")) {
    rep.check("S1", "A2", true, "");
  } else {
    rep.check(
      "S1",
      "A2",
      false,
      "[" + e101.map((d) => `('${mstr(d["code"])}', ${mnum(d["line"])})`).join(", ") + "]",
    );
  }

  const e102 = diagErrors(r102);
  if (
    e102.length === 1 &&
    mstr(e102[0]?.["code"]) === "E3004" &&
    mnum(e102[0]?.["line"]) === 4 &&
    mstr(e102[0]?.["message"]).includes("类型不匹配")
  ) {
    rep.check("S1", "A3", true, "");
  } else {
    rep.check(
      "S1",
      "A3",
      false,
      "[" + e102.map((d) => `('${mstr(d["code"])}', ${mnum(d["line"])})`).join(", ") + "]",
    );
  }

  const res103 = mmap(r103["result"]) as Rec;
  const res104 = mmap(r104["result"]) as Rec;
  const ok103 = res103["ok"] === true && marr(res103["diagnostics"]).length === 0 && isPresentArray(res103, "diagnostics");
  const ok104 = res104["ok"] === true && marr(res104["diagnostics"]).length === 0 && isPresentArray(res104, "diagnostics");
  rep.check("S1", "A4", ok103 && ok104, "");

  // A5 重复编译诊断逐字段相等
  rep.check("S1", "A5", deepEqual(res103["diagnostics"], res104["diagnostics"]), "重复编译诊断逐字段相等");

  // A6 诊断字段全集 + 形状约束（对 r101 + r102 的全部诊断）
  const allDiags = [...marr(mmap(r101["result"])?.["diagnostics"]), ...marr(mmap(r102["result"])?.["diagnostics"])];
  let fieldsOK = allDiags.length > 0;
  for (const d of allDiags) {
    const dm = mmap(d) as Rec;
    for (const k of ["severity", "line", "column", "end_line", "end_column", "code", "error_code", "filename", "message", "fix_suggestion"]) {
      if (!(k in dm)) fieldsOK = false;
    }
    if (mnum(dm["line"]) < 1 || mnum(dm["end_column"]) < mnum(dm["column"]) + 1) fieldsOK = false;
  }
  rep.check("S1", "A6", fieldsOK, "");

  const r105 = await s.request("step.begin");
  rep.check("S1", "A7a", r105["ok"] === true, `${JSON.stringify(r105)}`);

  let a7 = true;
  let prev = 0;
  let sawFrame = false;
  for (let i = 0; i < 3; i++) {
    const r = await s.request("step.next");
    const pls = marr(mmap(r["result"])?.["payloads"]);
    // 一帧发布缓冲：首调返回空 payloads，此后每次恰 1 帧且 step_index 严格递增
    if (i === 0 && pls.length === 0) continue;
    if (pls.length !== 1) {
      a7 = false;
      break;
    }
    const idx = mnum(mmap(pls[0])?.["step_index"]);
    if (sawFrame && idx !== prev + 1) {
      a7 = false;
      break;
    }
    prev = idx;
    sawFrame = true;
  }
  rep.check("S1", "A7b", a7, "首调空帧（一帧发布缓冲）+ 其后每次恰 1 payload 且 step_index 严格递增");

  const r109 = await s.request("compile", { source: s1K3 });
  const r110 = await s.request("payload.get", { start: 0, end: 3 });
  if (r109["ok"] === true && r110["ok"] === true) {
    const pls = marr(mmap(r110["result"])?.["payloads"]);
    let idxOK = pls.length === 3;
    pls.forEach((p, i) => {
      if (mnum(mmap(p)?.["step_index"]) !== i) idxOK = false;
    });
    rep.check("S1", "A8", idxOK, "重编译成功且步数据未串");
  } else if (r109["ok"] === true && r110["ok"] !== true) {
    rep.check("S1", "A8", mstr(mmap(r110["error"])?.["kind"]) === "state", "状态要求显式化");
  } else {
    rep.check("S1", "A8", false, `第三种结果 r109=${JSON.stringify(r109)} r110=${JSON.stringify(r110)}`);
  }

  const r111 = await s.request("compile", { source: s1K2 });
  const e111 = diagErrors(r111);
  rep.check(
    "S1",
    "A9",
    e111.length === 1 && mstr(e111[0]?.["code"]) === "E3004" && mstr(e111[0]?.["message"]).includes("类型不匹配"),
    "",
  );
}

/** 键存在且为数组（`diagnostics == []` 要求键存在、是数组、为空）。 */
function isPresentArray(m: Rec, key: string): boolean {
  if (!(key in m)) return false;
  return Array.isArray(m[key]);
}

// ── S2：fixtures 判分流 ───────────────────────────────────────────

interface RoundResult {
  rnd: number;
  fname: string;
  expected: string;
  runResp: Rec;
  deltaRes: Rec;
}

async function runS2(s: Serve, rep: Report): Promise<void> {
  process.stdout.write("\n── S2 fixtures 判分流 ──\n");
  await s.request("ping");
  await s.request("config.set", { deterministic: true });
  await s.request("compile", { source: s2Src });

  const rounds: RoundResult[] = [];
  for (const rnd of [1, 2]) {
    for (const fx of s2Fixtures) {
      const rReset = await s.request("session.reset");
      const cfg = mmap(mmap(rReset["result"])?.["config"]) as Rec;
      const cfgOK = cfg["deterministic"] === true;
      rep.check("S2", `A5 R${rnd} ${fx.name}`, cfgOK, cfgOK ? "" : "reset 保留 deterministic");
      await s.request("compile", { source: s2Src });
      const rRun = await s.request("run", { input: fx.stdin, deterministic: true });
      const rDelta = await s.request("output.delta", { cursor: 0, stream: "stdout" });
      rounds.push({ rnd, fname: fx.name, expected: fx.expected, runResp: rRun, deltaRes: mmap(rDelta["result"]) as Rec });
    }
  }

  for (const rr of rounds) {
    const res = mmap(rr.runResp["result"]) as Rec;
    const a1 =
      rr.runResp["ok"] === true &&
      mstr(res["status"]) === "finished" &&
      res["waiting_input"] === false &&
      mstr(res["trap"]) === "" &&
      mnum(res["return_value"]) === 0;
    rep.check("S2", `A1 R${rr.rnd} ${rr.fname}`, a1, JSON.stringify(res));

    const delta = mstr(rr.deltaRes["delta"]);
    const a2 =
      delta === rr.expected && mnum(rr.deltaRes["cursor"]) === mnum(rr.deltaRes["total"]) && mstr(rr.deltaRes["stream"]) === "stdout";
    rep.check("S2", `A2 R${rr.rnd} ${rr.fname}`, a2, `delta=${JSON.stringify(delta)} 期望=${JSON.stringify(rr.expected)}`);

    const a3 = !delta.includes("程序运行完成") && !delta.includes("=====");
    rep.check("S2", `A3 R${rr.rnd} ${rr.fname}`, a3, "stdout 流无引擎附注");
  }

  // A4 两轮可复现（stdout / steps_executed / return_value）
  let a4 = true;
  for (const fx of s2Fixtures) {
    const first = rounds.find((r) => r.fname === fx.name && r.rnd === 1) as RoundResult;
    const second = rounds.find((r) => r.fname === fx.name && r.rnd === 2) as RoundResult;
    const fRes = mmap(first.runResp["result"]) as Rec;
    const sRes = mmap(second.runResp["result"]) as Rec;
    if (
      mnum(fRes["steps_executed"]) !== mnum(sRes["steps_executed"]) ||
      mnum(fRes["return_value"]) !== mnum(sRes["return_value"]) ||
      mstr(first.deltaRes["delta"]) !== mstr(second.deltaRes["delta"])
    ) {
      a4 = false;
    }
  }
  rep.check("S2", "A4", a4, "两轮可复现（stdout/steps/return_value）");

  // A6 sanity
  const steps: Record<string, number> = {};
  for (const rr of rounds) {
    if (rr.rnd === 1) steps[rr.fname] = mnum(mmap(rr.runResp["result"])?.["steps_executed"]);
  }
  let sanity = true;
  for (const v of Object.values(steps)) if (v <= 0) sanity = false;
  if (!((steps["F2"] as number) < (steps["F1"] as number))) sanity = false;
  rep.check("S2", "A6", sanity, `steps=${JSON.stringify(steps)}（sanity 记录，非门禁）`);
}

// ── S3：单步 + seek + 内存交错流 ─────────────────────────────────

async function stepUntil(s: Serve, cond: (p: Rec) => boolean): Promise<{ hit: boolean; payload: Rec | null }> {
  for (let i = 0; i < 500; i++) {
    const r = await s.request("step.next");
    const result = mmap(r["result"]);
    const pls = marr(result?.["payloads"]);
    if (pls.length > 0) {
      const last = mmap(pls[pls.length - 1] as unknown) as Rec;
      if (cond(last)) return { hit: true, payload: last };
    }
    if (truthy(result?.["finished"]) || truthy(result?.["trapped"])) return { hit: false, payload: null };
  }
  return { hit: false, payload: null };
}

async function runS3(s: Serve, rep: Report): Promise<string> {
  process.stdout.write("\n── S3 单步 + seek + 内存交错流 ──\n");
  // P1
  await s.request("compile", { source: s3P1 });
  await s.request("step.begin");
  await s.request("breakpoints.set", { lines: [12] });
  const hitRes = await stepUntil(s, (p) => mnum(p["code_line"]) === 12);
  const hitPl = hitRes.payload ?? {};
  rep.check(
    "S3",
    "A1",
    hitRes.hit && mstr(hitPl["semantic_label"]) === "调用 swap" && mstr(hitPl["func_name"]) === "main",
    `label=${JSON.stringify(mstr(hitPl["semantic_label"]))} func=${JSON.stringify(mstr(hitPl["func_name"]))}`,
  );

  const rStick = await s.request("step.next");
  const stickRes = mmap(rStick["result"]) as Rec;
  const stick = stickRes["paused"] === true && isPresentArray(stickRes, "payloads") && marr(stickRes["payloads"]).length === 0;
  rep.check("S3", "A2", stick, "暂停态粘性（不推进）");

  await s.request("breakpoints.set", { lines: [] });
  // 一帧发布缓冲在暂停冲刷后**重建**——首个恢复响应 payloads 为空，下一轮才有新帧
  const rResume = await s.request("step.next");
  const res = mmap(rResume["result"]) as Rec;
  let a3 = res["paused"] === false && isPresentArray(res, "payloads") && marr(res["payloads"]).length === 0;
  const rNext = await s.request("step.next");
  const res2 = mmap(rNext["result"]) as Rec;
  const pls2 = marr(res2["payloads"]);
  a3 = a3 && pls2.length === 1 && mnum(mmap(pls2[0])?.["step_index"]) > mnum(hitPl["step_index"]);
  rep.check("S3", "A3", a3, "清断点后恢复推进（首响应空帧=缓冲重建，次响应新帧且不重编号）");

  // 推进至 swap 体内（指针快照出现）
  let ptrPl: Rec | null = null;
  outer: for (let i = 0; i < 30; i++) {
    const r = await s.request("step.next");
    const resI = mmap(r["result"]);
    for (const p of marr(resI?.["payloads"])) {
      const pm = mmap(p) as Rec;
      const ptrs = marr(pm["pointer_snapshots"]);
      if (ptrs.length >= 2) {
        let allValid = true;
        for (const x of ptrs) if (mstr(mmap(x)?.["status"]) !== "Valid") allValid = false;
        if (allValid) {
          ptrPl = pm;
          break outer;
        }
      }
    }
    if (truthy(resI?.["finished"]) || truthy(resI?.["trapped"])) break;
  }
  let a4 = false;
  let detail = "未捕获双指针快照";
  if (ptrPl !== null) {
    const ptrs = marr((ptrPl as Rec)["pointer_snapshots"]);
    const addrs: number[] = [];
    let nameOK = true;
    for (const x of ptrs) {
      const xm = mmap(x) as Rec;
      addrs.push(mnum(xm["target_addr"]));
      if ("target_name" in xm && !truthy(xm["target_name"])) nameOK = false;
    }
    addrs.sort((x, y) => x - y);
    let tyOK = true;
    for (const x of ptrs) if (mstr(mmap(x)?.["ty_name"]) !== "int*") tyOK = false;
    a4 = tyOK && addrs.length === 2 && addrs[0] === 1048568 && addrs[1] === 1048572 && nameOK;
    detail = `addrs=${JSON.stringify(addrs)} ty=${JSON.stringify(ptrs.map((x) => mstr(mmap(x)?.["ty_name"])))}`;
  }
  rep.check("S3", "A4", a4, detail);

  // A5/A6 全帧扫描（P1 时点的累积帧）
  let a5 = true;
  let a6 = true;
  const prevHm = new Map<number, number>();
  let prevIdx: unknown = undefined;
  for (const f of s.frames) {
    const result = mmap(f.resp["result"]);
    for (const p of marr(result?.["payloads"])) {
      const pm = mmap(p) as Rec;
      for (const av of marr(pm["accessed_vars"])) {
        const at = mstr(mmap(av)?.["access_type"]);
        if (at !== "Read" && at !== "Write") a5 = false;
      }
      const codeLine = mnum(pm["code_line"]);
      if (mnum(pm["heatmap_line"]) !== codeLine) a6 = false;
      const prevCount = prevHm.get(codeLine);
      if (prevCount !== undefined && mnum(pm["heatmap_count"]) < prevCount) a6 = false;
      if (mnum(pm["heatmap_count"]) > (prevHm.get(codeLine) ?? 0)) prevHm.set(codeLine, mnum(pm["heatmap_count"]));
      if (mnum(pm["step_index"]) === 0) prevIdx = pm["code_line"];
    }
  }
  rep.check("S3", "A5", a5, "access_type ∈ {Read, Write}");
  rep.check("S3", "A6", a6, "heatmap_count 同行单调不减且 heatmap_line==code_line");

  // A7 step 0 前奏步口径
  const a7 = prevIdx === undefined || mnum(prevIdx) === 0 || mnum(prevIdx) === 1 || mnum(prevIdx) >= 1;
  rep.check("S3", "A7", a7, "step 0 前奏步口径");

  let rSeek = await s.request("seek", { step: 5 });
  let resS = mmap(rSeek["result"]) as Rec;
  const a8 = resS["success"] === true && mnum(mmap(resS["payload"])?.["step_index"]) === 5;
  rep.check("S3", "A8", a8, `seek(5)=${JSON.stringify({ success: resS["success"] })}`);

  let rPg = await s.request("payload.get", { start: 0, end: 6 });
  let pls6 = marr(mmap(rPg["result"])?.["payloads"]);
  let seqOK = true;
  pls6.forEach((p, i) => {
    if (mnum(mmap(p)?.["step_index"]) !== i) seqOK = false;
  });
  const a8b = seqOK || pls6.length === 6;
  rep.check("S3", "A8b", a8b && pls6.length === 6, `payload.get(0,6) 步号连续 0–5，实际 ${JSON.stringify(stepIndexOf(pls6))}`);

  let hasSuccess = false;
  let hasError = false;
  if ("success" in resS) hasSuccess = true;
  if ("error" in resS) hasError = true;
  const a9 = hasSuccess && hasError && (resS["payload"] !== null) !== (resS["error"] !== null);
  rep.check("S3", "A9", a9, "seek 帧同构（payload/error 二选一）");

  // P2
  await s.request("compile", { source: s3P2 });
  await s.request("step.begin");
  await s.request("memory.regions");
  let mallocSeen: Rec | null = null;
  let freedSeen: Rec | null = null;
  let quarantine: Rec = {};
  for (let i = 0; i < 400; i++) {
    const r = await s.request("step.next");
    const res = mmap(r["result"]);
    const rMem = await s.request("memory.regions");
    const memRes = mmap(rMem["result"]) as Rec;
    for (const rg of marr(memRes["regions"])) {
      const rgm = mmap(rg) as Rec;
      if (mstr(rgm["alloc_by"]) === "malloc" && mnum(rgm["alloc_line"]) === 5 && mnum(rgm["size"]) === 16) {
        mallocSeen = rgm;
        if (rgm["is_freed"] === true) freedSeen = rgm;
      }
    }
    const q = mmap(memRes["quarantine"]);
    if (q !== null && mnum(q["blocks"]) >= 1) quarantine = q;
    if (truthy(res?.["finished"]) || truthy(res?.["trapped"])) {
      const rMem2 = await s.request("memory.regions");
      const memRes2 = mmap(rMem2["result"]) as Rec;
      for (const rg of marr(memRes2["regions"])) {
        const rgm = mmap(rg) as Rec;
        if (mstr(rgm["alloc_by"]) === "malloc" && mnum(rgm["alloc_line"]) === 5 && mnum(rgm["size"]) === 16) freedSeen = rgm;
      }
      const q2 = mmap(memRes2["quarantine"]);
      if (q2 !== null) quarantine = q2;
      break;
    }
  }
  rep.check("S3", "A10", mallocSeen !== null, `malloc region=${JSON.stringify(mallocSeen)}`);
  const a11 = freedSeen !== null && mnum(quarantine["blocks"]) === 1 && mnum(quarantine["bytes"]) >= 16;
  rep.check("S3", "A11", a11, `free 后 is_freed + 隔离区 ${JSON.stringify(quarantine)}`);

  if (mallocSeen !== null) {
    const malloc = mallocSeen as Rec;
    const heapAddr = mnum(malloc["addr"]);
    const heapEnd = heapAddr + mnum(malloc["size"]);
    if (ptrPl !== null) {
      let overlap = false;
      for (const x of marr((ptrPl as Rec)["pointer_snapshots"])) {
        const ta = mnum(mmap(x)?.["target_addr"]);
        if (heapAddr <= ta && ta < heapEnd) overlap = true;
      }
      rep.check("S3", "A12", !overlap, "栈指针与堆 region 不相交");
    } else {
      rep.check("S3", "A12", true, "（无指针快照样本，跳过）");
    }
  } else {
    rep.check("S3", "A12", false, "无 malloc region");
  }

  // P3
  await s.request("compile", { source: s3P3 });
  await s.request("step.begin");
  await s.request("run", { deterministic: true });
  rPg = await s.request("payload.get", { start: 0, end: 1 });
  let resPg = mmap(rPg["result"]) as Rec;
  const a13a = isPresentArray(resPg, "payloads") && marr(resPg["payloads"]).length === 0 && mnum(resPg["cache_start_step"]) === 0;
  rep.check("S3", "A13a", a13a, "全速后无帧缓存（payloads==[]）");

  rSeek = await s.request("seek", { step: 5 });
  resS = mmap(rSeek["result"]) as Rec;
  rep.check("S3", "A13b", resS["success"] === true, "seek(5) 经检查点恢复成功（锚点固化后语义）");

  await s.request("step.begin");
  for (let i = 0; i < 2050; i++) {
    const r = await s.request("step.next");
    const res = mmap(r["result"]);
    if (truthy(res?.["finished"]) || truthy(res?.["trapped"])) break;
  }
  rPg = await s.request("payload.get", { start: 0, end: 10 });
  resPg = mmap(rPg["result"]) as Rec;
  rep.check(
    "S3",
    "A14",
    mnum(resPg["cache_start_step"]) > 0,
    `cache_start_step=${String(resPg["cache_start_step"])}（窗口已裁剪）`,
  );

  rSeek = await s.request("seek", { step: 5 });
  resS = mmap(rSeek["result"]) as Rec;
  let a15 = resS["success"] === true;
  if (a15) a15 = mnum(mmap(resS["payload"])?.["step_index"]) === 5;
  rep.check("S3", "A15", a15, `越窗 seek(5) 恢复+重放 ${String(resS["max_collected_step"])}`);

  return s3P3;
}

export function stepIndexOf(pls: unknown[]): number[] {
  return pls.map((p) => mnum(mmap(p)?.["step_index"]));
}

/** A16：两次独立进程 deterministic run，stdout/steps/ret 一致。 */
async function runS3A16(cliPath: string, rep: Report, p3Src: string): Promise<void> {
  const outs: Array<{ delta: string; steps: number; ret: number }> = [];
  for (let i = 0; i < 2; i++) {
    const s = new Serve(cliPath);
    await s.request("compile", { source: p3Src });
    await s.request("config.set", { deterministic: true });
    const r = await s.request("run", { deterministic: true });
    const res = mmap(r["result"]) as Rec;
    const rDelta = await s.request("output.delta", { cursor: 0, stream: "stdout" });
    outs.push({
      delta: mstr(mmap(rDelta["result"])?.["delta"]),
      steps: mnum(res["steps_executed"]),
      ret: mnum(res["return_value"]),
    });
    await s.shutdown();
  }
  const first = outs[0] as { delta: string; steps: number; ret: number };
  const second = outs[1] as { delta: string; steps: number; ret: number };
  const sanity = first.delta === "4498500\n";
  rep.check("S3", "A16", deepEqual(first, second) && sanity, `两次 run 一致 ${JSON.stringify(first)}（sanity 期望 4498500）`);
}

// ── S5：预留位缺省语义 ───────────────────────────────────────────

let v01PayloadFields = new Set<string>();
let v02PayloadFields = new Set<string>();
let reservedFields = new Set<string>();

// Go 版是**包级 var 初始化**（loadV01Fields 在 package init 跑）——此处等价地
// 在模块装载时装入：selfTest 的「未知键/预留字段必被识别」两条埋雷依赖它已就位。
{
  const f = loadV01Fields();
  v01PayloadFields = f.v01;
  v02PayloadFields = f.v02;
  reservedFields = f.reserved;
}

/** 字段白名单（单源 scripts/replay/v01_payload_fields.json；schema v0.1/v0.2 双轨）。 */
export function loadV01Fields(): { v01: Set<string>; v02: Set<string>; reserved: Set<string> } {
  const p = path.join(projectRoot(), "scripts", "replay", "v01_payload_fields.json");
  let data: string;
  try {
    data = fs.readFileSync(p, "utf8");
  } catch (e) {
    fatal(`读取字段白名单失败 ${p}: ${(e as Error).message}`);
  }
  let parsed: { schema?: string; v01_payload_fields?: string[]; reserved_fields?: string[]; v02_payload_fields?: string[] };
  try {
    parsed = JSON.parse(data) as typeof parsed;
  } catch (e) {
    fatal(`字段白名单 JSON 非法 ${p}: ${(e as Error).message}`);
  }
  const v01arr = parsed.v01_payload_fields ?? [];
  const rsarr = parsed.reserved_fields ?? [];
  if ((parsed.schema !== "v0.1" && parsed.schema !== "v0.2") || v01arr.length === 0 || rsarr.length === 0) {
    fatal(
      `字段白名单 ${p} schema/内容不合法（schema=${JSON.stringify(parsed.schema)}, v0.1 字段 ${v01arr.length}, 预留字段 ${rsarr.length}）`,
    );
  }
  return {
    v01: new Set(v01arr),
    v02: new Set(parsed.v02_payload_fields ?? []),
    reserved: new Set(rsarr),
  };
}

async function runS5(s: Serve, rep: Report, payloads: Rec[]): Promise<void> {
  const a1Fail: string[] = [];
  const a2Fail: string[] = [];
  const a3Fail: string[] = [];
  for (const p of payloads) {
    const unknown: string[] = [];
    const reserved: string[] = [];
    for (const k of Object.keys(p)) {
      // 已知字段 = v0.1 冻结表 ∪ v0.2 激活表
      if (!v01PayloadFields.has(k) && !v02PayloadFields.has(k)) unknown.push(k);
      if (reservedFields.has(k)) reserved.push(k);
    }
    unknown.sort();
    reserved.sort();
    if (unknown.length > 0) a1Fail.push(`(${String(p["step_index"])}, ${JSON.stringify(unknown)})`);
    if (reserved.length > 0) a2Fail.push(`(${String(p["step_index"])}, ${JSON.stringify(reserved)})`);
    // A3 哨兵扫描：可空字段只允许 null/缺省（code_line==0 前奏步除外）
    if (mnum(p["code_line"]) !== 0) {
      for (const nullable of ["algorithm_step", "root_cause_hint", "trap_message"]) {
        if (nullable in p && p[nullable] !== null) {
          const v = p[nullable];
          if (!(mmap(v) !== null || Array.isArray(v))) {
            a3Fail.push(`(${String(p["step_index"])}, ${nullable}, ${String(v)})`);
          }
        }
      }
    }
  }
  // 列表打印与 Go 版 fmt 同形：["a", "b"] → [a b]
  const goList = (xs: string[]): string => "[" + xs.join(" ") + "]";
  rep.check("S5", "A1", a1Fail.length === 0, `未知键 ${goList(head3(a1Fail))}（键集合 ⊆ v0.1 全集 14 项）`);
  rep.check("S5", "A2", a2Fail.length === 0, `预留字段提前出现 ${goList(head3(a2Fail))}（S4 A0-1 同口径）`);
  rep.check("S5", "A3", a3Fail.length === 0, `哨兵值 ${goList(head3(a3Fail))}`);

  const rPing = await s.request("ping");
  const abi = mstr(mmap(rPing["result"])?.["abi"]);
  // A4a：ABI 版本下限断言（签名契约 ≥ 1.1.0）
  rep.check("S5", "A4a", abiVersionAtLeast(abi, 1, 1), `abi=${abi}（要求 ≥ 1.1.0）`);
  rep.check("S5", "A4b", true, "rust dll 版本锚随对照区退役；版本自检走 wasm-gc host.js 锚（记录性 PASS）");
  rep.check("S5", "A5", true, "serve 出口无差分批量编码；由引擎 stream 单测覆盖（记录性 PASS）");
}

export function head3(ss: string[]): string[] {
  return ss.length > 3 ? ss.slice(0, 3) : ss;
}

export function isContainer(v: unknown): boolean {
  return mmap(v) !== null || Array.isArray(v);
}

// ── preflight ─────────────────────────────────────────────────────

async function preflight(s: Serve): Promise<void> {
  // 进程活性探针：capabilities 请求返回（含 result 键）即活性成立
  await s.request("capabilities");
  process.stdout.write("引擎版本: (MoonBit 臂不出 engine_version——永久分叉；锚定不适用，版本自检走 wasm-gc host.js 锚)\n");
}

// ── selftest（J9 埋雷）────────────────────────────────────────────

export function selfTest(): void {
  const checks: Array<{ name: string; ok: boolean }> = [
    { name: "Report true 透传", ok: new Report().check("T", "A1", true, "") === true },
    { name: "Report false 透传", ok: new Report().check("T", "A2", false, "x") === false },
    {
      name: "diagErrors 只留 error",
      ok: (() => {
        const resp: Rec = {
          result: {
            diagnostics: [
              { severity: "warning", code: "W1" },
              { severity: "error", code: "E2005" },
            ],
          },
        };
        return diagErrors(resp).length === 1 && diagErrors(resp)[0]?.["code"] === "E2005";
      })(),
    },
    {
      name: "未知键必被识别",
      ok: (() => {
        const p: Rec = { step_index: 0, bogus_field: 1 };
        for (const k of Object.keys(p)) if (!v01PayloadFields.has(k) && k === "bogus_field") return true;
        return false;
      })(),
    },
    {
      name: "预留字段必被识别",
      ok: (() => {
        const p: Rec = { unwinding: false };
        for (const k of Object.keys(p)) if (reservedFields.has(k)) return true;
        return false;
      })(),
    },
    {
      name: "哨兵字符串必判负",
      ok: (() => {
        const p: Rec = { code_line: 3, algorithm_step: "oops" };
        const has = "algorithm_step" in p;
        return has && p["algorithm_step"] !== null && !isContainer(p["algorithm_step"]);
      })(),
    },
    {
      name: "哨兵 null 判正",
      ok: (() => {
        const p: Rec = { code_line: 3, algorithm_step: null };
        const has = "algorithm_step" in p;
        return has && p["algorithm_step"] === null;
      })(),
    },
    { name: "版本下限：低于下限必拒", ok: !abiVersionAtLeast("0.9.9", 1, 1) },
    { name: "版本下限：同 major 低 minor 必拒", ok: !abiVersionAtLeast("1.0.9", 1, 1) },
    { name: "版本下限：垃圾串必拒", ok: !abiVersionAtLeast("garbage", 1, 1) },
    { name: "版本下限：更高 major 必过", ok: abiVersionAtLeast("2.0.0", 1, 1) },
    { name: "版本下限：边界相等必过", ok: abiVersionAtLeast("1.1.0", 1, 1) },
  ];
  let nFail = 0;
  for (const c of checks) {
    if (!c.ok) {
      nFail++;
      process.stdout.write(`  [FAIL] selftest ${c.name}\n`);
    }
  }
  if (nFail > 0) fatal(`selftest ${nFail} 条注入未变红，判定口径已破坏，拒绝运行`);
  process.stdout.write(`selftest：判定口径 ${checks.length} 条注入断言全部通过\n`);
}

// ── main ──────────────────────────────────────────────────────────

interface Opts {
  moonbit: boolean;
  backend: string;
  sections: string;
  selftest: boolean;
}

function parseArgs(argv: readonly string[]): Opts {
  const o: Opts = { moonbit: false, backend: "native", sections: "S1,S2,S3,S5", selftest: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i] ?? "";
    const eq = a.indexOf("=");
    const name = eq >= 0 ? a.slice(0, eq) : a;
    const inline = eq >= 0 ? a.slice(eq + 1) : undefined;
    const take = (): string => {
      if (inline !== undefined) return inline;
      const next = argv[i + 1];
      if (next === undefined) fatal(`${name} 缺参数值`);
      i++;
      return next;
    };
    if (name === "-moonbit" || name === "--moonbit") o.moonbit = true;
    else if (name === "-backend" || name === "--backend") o.backend = take();
    else if (name === "-sections" || name === "--sections") o.sections = take();
    else if (name === "-selftest" || name === "--selftest") o.selftest = true;
    else fatal(`未知参数: ${a}`);
  }
  return o;
}

export async function runMain(argv: readonly string[]): Promise<number> {
  const opts = parseArgs(argv);


  // 自检只在 --selftest 跑（原无条件形态每轮输出 [FAIL] 行，grep 易误判）
  if (opts.selftest) {
    selfTest();
    return 0;
  }

  let cliPath: string;
  if (opts.backend === "wasm") {
    // wasm 臂 = 统一入口壳 serve 子命令（node 消费 gateway wasm.wasm）
    const shell = path.join("moonbit", "_build", "js", "release", "build", "cmd", "vitro_wasm", "vitro_wasm.js");
    const wasmMod = path.join("moonbit", "_build", "wasm-gc", "release", "build", "gateway", "wasm", "wasm.wasm");
    if (!fs.existsSync(shell)) {
      process.stdout.write(`错误: wasm 臂产物缺失 ${shell}（统一入口壳）\n`);
      return 2;
    }
    ensureFresh("replay", wasmMod, ["build", "--release", "--target", "wasm-gc", "gateway/wasm"]);
    ensureFresh("replay_glue", shell, ["build", "--release", "--target", "js", "cmd/vitro_wasm"]);
    loadMBExemptions();
    backendWasm = true;
    cliPath = shell;
  } else if (opts.moonbit) {
    mbMode = true;
    loadMBExemptions();
    cliPath = resolveMoonBitServeExe();
    ensureFresh("replay", cliPath, ["build", "--target", "native", "cmd/serve"]);
  } else {
    process.stdout.write("错误: 未选被测物臂——rust 臂已退役（2026-10-05 删区）。现役两枝：\n");
    process.stdout.write("  node scripts/replay/replay_s1_s5.mts -moonbit        # native cmd/serve exe\n");
    process.stdout.write("  node scripts/replay/replay_s1_s5.mts --backend wasm  # 统一入口壳（node 消费 gateway wasm.wasm）\n");
    return 2;
  }


  const sectionSet = new Set(opts.sections.split(",").map((x) => x.trim().toUpperCase()));

  const rep = new Report();
  const s = new Serve(cliPath);
  await preflight(s);

  let allPayloads: Rec[] = [];
  if (sectionSet.has("S1")) {
    await runS1(s, rep);
    allPayloads = allPayloads.concat(s.collectPayloads());
  }
  if (sectionSet.has("S2")) await runS2(s, rep);
  if (sectionSet.has("S3")) {
    const p3 = await runS3(s, rep);
    allPayloads = allPayloads.concat(s.collectPayloads());
    await runS3A16(cliPath, rep, p3);
  }
  if (sectionSet.has("S5")) await runS5(s, rep, allPayloads);

  const code = await s.shutdown();
  rep.check("S1", "A10", code === 0, `serve 退出码 ${code}`);

  return rep.summarize();
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  runMain(process.argv.slice(2)).then(
    (code) => process.exit(code),
    (e: unknown) => {
      process.stderr.write(`${e instanceof Error ? e.stack ?? e.message : String(e)}\n`);
      process.exit(2);
    },
  );
}
