#!/usr/bin/env node
// step_invariant —— step 帧流不变量检查器（过程语义防线，tmp/moon_prove/report.md §8.2 方案 B）。
//
// 输入 = `vitro step <file.c> --json` 的 NDJSON 帧流（cli_step.mbt:128-146 编排：
// compile 帧 → step.next 行×N（每行 result.payloads 全量快照帧，frames=1 语义）
// → stdout 帧 → summary 收口帧）。逐帧断言四条语义不变量（report §5 设计稿的
// 运行时降格——字段以 cli_step/serve_step/collector 实况为准）+ 帧流结构层契约：
//
// 语义不变量（引擎侧单源镜像——违反 = 引擎产坏帧或发射层缺陷）：
//   INV1a 内存视图域内：local_vars[].addr 与 pointer_snapshots[].addr 恒满足
//        addr >= NULL_TRAP_SIZE && addr+4 <= MEM_SIZE（vm/observe.mbt
//        get_variable_snapshot 同款过滤口径——NULL 陷阱区与域外地址不得
//        出现在动画内存图）
//   INV1b 全局区上界：is_local=false 的变量 addr ∈ [GLOBAL_START,
//        GLOBAL_REGION_LIMIT)（R1 判据单源常量——全局编址越界=布局缺陷）
//   INV1c Freed 堆域：status=Freed 的指针 target_addr >= HEAP_START
//        （collector is_freed_heap 只可能命中堆区 region，堆起点 >= HEAP_START）
//   INV2a 栈深域：0 <= call_stack.length <= call_depth_limit
//        （cli_step config.set 的 10000）
//   INV2b 栈深增量：相邻帧栈深差 ∈ {-1,0,+1}——单步至多一次 call/ret
//        （bytecode/verify VKnown「栈深非负且受控」的运行时降格）
//   INV2c main 底帧：call_stack 非空 ⇒ [0].func_name == "main"（C 入口恒底帧）
//   INV3a cursor 连续：step_index 全流从 0 起严格 +1（CLI 路径无 seek/采样；
//        「cursor 单调」的最强形态——发布滞后缓冲只重排发布时机不重编号）
//   INV4  指针四态域自洽（time_travel/collector.mbt:302-311 判定镜像）：
//        Null ⇒ target==0；Dangling ⇒ target!=0 且越区（<NULL_TRAP_SIZE 或
//        >=MEM_SIZE）；Valid|Freed ⇒ target ∈ [NULL_TRAP_SIZE, MEM_SIZE)
//
// 结构层契约（帧流编排）：
//   ST1 每行合法 JSON；ST2 step 行 ok:true 且 result 八字段齐；
//   ST3 行 id 严格递增（cli_step id+=1 单调）；ST4 终态行恰一行
//   （finished/trapped/waiting_input 三选一）；ST5 首行 payloads=[]
//   （滞后一帧发布缓冲——R2 语义）；ST7 summary.frames==帧总数且终态位
//   与末行一致。
//   ST6（每行 payloads<=2）已随 #477 案 a 退役（2026-11-05）：宿主回调段
//   一条 CallHost 指令合法产出多帧（comparator 逐指令出帧——INV3a 修复
//   语义），发布行 payloads 无静态上界；帧不丢不重由 INV3a（全流严格
//   +1）+ ST7（summary 对账）锁。id 保留注释形态防报告引用断链。
//
// 边界（如实登记）：quarantine 隔离区**区间**数据不在帧流（可观测面只有
// 指针四态与变量地址域）——「隔离区两两不交」的区间级检查需 gateway
// memory.regions 逐步快照面扩张，本批不做；本检查器以 INV1b/INV1c 的域级
// 投影覆盖其可观测部分。
//
// 义务：真实引擎帧流全绿是防线基线；构造违例帧（手工篡改 NDJSON）必红
// （J9——main.test.mts 每不变量一例）。检查器发现的引擎真产坏帧不修只
// 登记（行为修复归 B 轮线，arm_divergence 同款处置）。
//
// 用法：node scripts/step_invariant/main.mts <file.c> [...]
//       node scripts/step_invariant/main.mts --corpus <dir> [--sample N]
//            [--jobs N] [--timeout-ms N] [--json] [--audit-known]
// rc：0 全绿；1 违例/用法错/驱动失败。脚本消费一律 --json。
//
// 已知违例白名单（known_violations.json，(case, invariant) 粒度）三态：
// 未登记违例 = RED；命中登记 = EXPECTED_RED 放行（登记条目附 reason/issue，
// 修复归 B 轮线）；--audit-known（全量轮专用）时登记未命中 = ZOMBIE 红
// （防语料/引擎演化后白名单僵尸化——vm_diff known_diffs 同款纪律）。
import fs from "node:fs";
import path from "node:path";
import readline from "node:readline";
import { spawn } from "node:child_process";
import { pathToFileURL } from "node:url";
import { projectRoot } from "../internal/capi.mts";
import { ensureFresh } from "../internal/freshness.mts";

// ── 引擎侧常量单源镜像（bytecode/memory.mbt——改动连坐此处）──
/** 总内存 1MB（MEM_SIZE）。 */
export const MEM_SIZE = 0x100000;
/** NULL 陷阱区大小（NULL_TRAP_SIZE）。 */
export const NULL_TRAP_SIZE = 0x1000;
/** 全局区起始（GLOBAL_START）。 */
export const GLOBAL_START = 0x1000;
/** 堆区起点下限（HEAP_START）。 */
export const HEAP_START = 0x5000;
/** 全局区编译期硬上界，绝对地址（GLOBAL_REGION_LIMIT = MEM_SIZE/16）。 */
export const GLOBAL_REGION_LIMIT = MEM_SIZE / 16;
/** 调用栈深上限（cli_step config.set call_depth_limit）。 */
export const CALL_DEPTH_LIMIT = 10000;

/** 违例条目。invariant = INV1a..INV4/ST1..ST7 稳定 id（报告引用）。 */
export interface Violation {
  source: string;
  /** NDJSON 行号（1 起）。 */
  line: number;
  /** 帧 step_index（帧级不变量在場；行级为 undefined）。 */
  stepIndex?: number;
  invariant: string;
  detail: string;
}

/** 单条帧流的检查结果。 */
export interface StreamCheckResult {
  violations: Violation[];
  /** payload 帧总数（step_index 计数）。 */
  frames: number;
  /** 流终态。compile-error = 编译失败单行形态（不变量面不适用）；
   * timeout = 两轮预算尽仍超时（单列不红——预算问题与防线违例分账，
   * PR #478 审阅 P1-1）；unreadable = 源不可读/用法错（cli_step rc=4，
   * P3-6——语料形态问题非防线红）。 */
  terminal: "finished" | "trapped" | "waiting_input" | "compile-error" | "timeout" | "unreadable" | "none";
}

interface StepRow {
  id: number;
  ok: boolean;
  result?: {
    ok?: boolean;
    payloads?: unknown[];
    finished?: boolean;
    trapped?: boolean;
    waiting_input?: boolean;
    paused?: boolean;
    current_line?: number;
    trap_message?: string | null;
    cache_start_step?: number;
  };
}

interface VarSnapshot {
  name?: string;
  addr?: number;
  is_local?: boolean;
}

interface PtrSnapshot {
  name?: string;
  addr?: number;
  target_addr?: number;
  status?: string;
}

interface FramePayload {
  step_index?: number;
  call_stack?: Array<{ func_name?: string }>;
  local_vars?: VarSnapshot[];
  pointer_snapshots?: PtrSnapshot[];
}

const STEP_RESULT_FIELDS = [
  "payloads",
  "finished",
  "trapped",
  "waiting_input",
  "paused",
  "current_line",
  "trap_message",
  "cache_start_step",
] as const;

function isObj(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

/**
 * 流式检查器——逐行 feed（readline 直连，行即弃：大语料 NDJSON 数十 MB
 * 不驻留，全量并发下旧「行数组终检」形态曾 4GB 堆 OOM，2026-11-04 改造）。
 * feed 完调 finish() 收终态；checkStepStream 是它的数组薄壳（测试共用）。
 */
export class StreamChecker {
  private readonly source: string;
  private readonly violations: Violation[] = [];
  private frames = 0;
  private terminal: StreamCheckResult["terminal"] = "none";
  private terminalSeen = 0;
  private lastFinished = false;
  private lastTrapped = false;
  private lastId = -Infinity;
  private firstStepRow = true;
  private readonly frameState: FrameState = { prevStepIndex: -1, prevDepth: -1 };
  private summaryRow: { frames?: number; finished?: boolean; trapped?: boolean } | null = null;
  private lineCount = 0;

  constructor(source: string) {
    this.source = source;
  }

  private push(line: number, invariant: string, detail: string, stepIndex?: number): void {
    const v: Violation = { source: this.source, line, invariant, detail };
    if (stepIndex !== undefined) v.stepIndex = stepIndex;
    this.violations.push(v);
  }

  /** 已喂行中累计的 payload 帧数（超时报告用——finish 前可读）。 */
  get frameCount(): number {
    return this.frames;
  }

  /** 喂一行 NDJSON（空行跳过——驱动侧 readline 仍可能给尾部空行）。 */
  feed(raw: string): void {
    if (raw.trim() === "") return;
    this.lineCount++;
    const lineNo = this.lineCount;
    let row: unknown;
    try {
      row = JSON.parse(raw);
    } catch (e) {
      this.push(lineNo, "ST1", `非法 JSON：${String(e)}`);
      return;
    }
    if (!isObj(row)) {
      this.push(lineNo, "ST1", `非对象行：${typeof row}`);
      return;
    }
    // type:diag 包装帧（SWEEP1 #444，2026-11-05）：step --json 的 compile 失败 /
    // run 协议错路径改 {"type":"diag","frame":{id,ok,result}} 包装（三子命令事件流
    // 对称）——frame 即旧裸帧，terminal 语义同源（result.ok:false → compile-error，
    // 后续 summary 检查走 compile-error 豁免——与旧裸帧行为等价）
    if (row["type"] === "diag") {
      const frame = row["frame"];
      if (isObj(frame) && isObj(frame["result"]) && frame["result"]["ok"] === false) {
        this.terminal = "compile-error";
      }
      return;
    }
    // stdout / summary 收口行
    if (row["type"] === "stdout") {
      const frame = row["frame"];
      if (!isObj(frame) || !isObj(frame["result"]) || typeof frame["result"]["delta"] !== "string") {
        this.push(lineNo, "ST7", "stdout 帧形状缺 frame.result.delta");
      }
      return;
    }
    if (row["type"] === "summary") {
      this.summaryRow = {
        frames: typeof row["frames"] === "number" ? row["frames"] : undefined,
        finished: row["finished"] === true,
        trapped: row["trapped"] === true,
      };
      return;
    }
    // step 行（step.next 响应 / compile 帧透传）
    if (typeof row["id"] !== "number" || typeof row["ok"] !== "boolean") {
      this.push(lineNo, "ST2", `step 行缺 id/ok：keys=${Object.keys(row).join(",")}`);
      return;
    }
    const id = row["id"];
    if (id <= this.lastId) this.push(lineNo, "ST3", `行 id 非严格递增：${this.lastId} -> ${id}`);
    this.lastId = id;
    const result = row["result"];
    if (!isObj(result)) {
      this.push(lineNo, "ST2", "step 行缺 result 对象");
      return;
    }
    // compile 失败帧：result.ok=false 单行形态（cli_step rc=1 透传）——不变量面不适用
    if (result["ok"] === false) {
      this.terminal = "compile-error";
      return;
    }
    for (const f of STEP_RESULT_FIELDS) {
      if (!(f in result)) this.push(lineNo, "ST2", `result 缺字段 ${f}`);
    }
    const r = result as StepRow["result"];
    if (r === undefined) return;
    // ST2 形状：payloads 必为数组（null/退化形态不静默吞——帧形状退化曾零判别力，
    // PR #478 审阅 P2-2 探针：payloads:null 时 frames 计 0 只靠 ST7 兜底）
    if (!Array.isArray(r.payloads)) {
      this.push(lineNo, "ST2", `payloads 非数组：${typeof r.payloads}`);
      return;
    }
    const payloads = r.payloads as FramePayload[];
    if (this.firstStepRow && payloads.length !== 0) {
      this.push(lineNo, "ST5", `首 step 行 payloads 非空（滞后一帧缓冲）：${payloads.length}`);
    }
    this.firstStepRow = false;
    // ST6 数量上限退役（#477 案 a，2026-11-05）：宿主回调段一条 CallHost
    // 指令合法多帧（comparator 嵌套帧），静态上限误伤合法形态；帧不丢
    // 不重由 INV3a + ST7 锁（头注结构契约表）。
    const finished = r.finished === true;
    const trapped = r.trapped === true;
    const waiting = r.waiting_input === true;
    if (finished || trapped || waiting) {
      this.terminalSeen++;
      if (this.terminalSeen > 1) this.push(lineNo, "ST4", `第 ${this.terminalSeen} 个终态行（应恰一行）`);
      if (this.terminal === "none") {
        this.terminal = finished ? "finished" : trapped ? "trapped" : "waiting_input";
      } else if (this.terminal !== "compile-error") {
        this.push(lineNo, "ST4", `终态冲突：${this.terminal} 后再见终态位`);
      }
      this.lastFinished = finished;
      this.lastTrapped = trapped;
    }
    for (const p of payloads) {
      this.frames++;
      checkFrame(p, lineNo, (l, inv, d, s) => this.push(l, inv, d, s), this.frameState);
    }
  }

  /** 收口：ST7 summary 对账 + 终态返回。 */
  finish(): StreamCheckResult {
    if (this.summaryRow !== null) {
      if (this.summaryRow.frames !== undefined && this.summaryRow.frames !== this.frames) {
        this.push(this.lineCount, "ST7", `summary.frames=${this.summaryRow.frames} != 帧总数 ${this.frames}`);
      }
      if (this.terminal !== "compile-error") {
        if (this.summaryRow.finished !== this.lastFinished || this.summaryRow.trapped !== this.lastTrapped) {
          this.push(this.lineCount, "ST7", `summary 终态位与末终态行不一致`);
        }
      }
    } else if (this.terminal !== "compile-error") {
      this.push(this.lineCount, "ST7", "缺 summary 收口行");
    }
    return { violations: this.violations, frames: this.frames, terminal: this.terminal };
  }
}

/**
 * 检查一条 NDJSON 帧流（数组薄壳——测试与完整流消费面共用）。
 */
export function checkStepStream(lines: readonly string[], source: string): StreamCheckResult {
  const c = new StreamChecker(source);
  for (const l of lines) c.feed(l);
  return c.finish();
}

type PushFn = (line: number, invariant: string, detail: string, stepIndex?: number) => void;

/** 跨帧检查状态（INV2b/INV3a 的相邻帧比较载体）。 */
interface FrameState {
  prevStepIndex: number;
  prevDepth: number;
}

/** 帧级形状断言（ST2 后半——发射层退化防线：三数组必为数组、字段类型必达，
 * PR #478 审阅 P2-2：local_vars/call_stack/pointer_snapshots 全 null 曾零违例）。
 * 值域正确性归 INV 族，此处只管「形状在」——类型错即红，防静默退化。 */
function checkFrameShape(p: unknown, lineNo: number, push: PushFn): void {
  if (!isObj(p)) {
    push(lineNo, "ST2", `帧 payload 非对象：${typeof p}`);
    return;
  }
  for (const f of ["local_vars", "call_stack", "pointer_snapshots", "vis_events", "accessed_vars", "array_snapshots"] as const) {
    const v = p[f];
    if (v !== undefined && !Array.isArray(v)) {
      push(lineNo, "ST2", `帧字段 ${f} 非数组：${typeof v}`);
    }
  }
  for (const v of (Array.isArray(p["local_vars"]) ? p["local_vars"] : []) as unknown[]) {
    if (!isObj(v) || typeof v["name"] !== "string" || typeof v["addr"] !== "number" || typeof v["is_local"] !== "boolean") {
      push(lineNo, "ST2", `local_vars 元素形状缺（name/addr/is_local）：${JSON.stringify(v)?.slice(0, 80)}`);
    }
  }
  for (const v of (Array.isArray(p["call_stack"]) ? p["call_stack"] : []) as unknown[]) {
    if (!isObj(v) || typeof v["func_name"] !== "string") {
      push(lineNo, "ST2", `call_stack 元素形状缺（func_name）：${JSON.stringify(v)?.slice(0, 80)}`);
    }
  }
  for (const v of (Array.isArray(p["pointer_snapshots"]) ? p["pointer_snapshots"] : []) as unknown[]) {
    if (!isObj(v) || typeof v["addr"] !== "number" || typeof v["target_addr"] !== "number" || typeof v["status"] !== "string") {
      push(lineNo, "ST2", `pointer_snapshots 元素形状缺（addr/target_addr/status）：${JSON.stringify(v)?.slice(0, 80)}`);
    }
  }
}

/** 单帧语义不变量（INV1-4）；跨帧状态经 state 对象就地推进。 */
function checkFrame(p: FramePayload, lineNo: number, push: PushFn, st: FrameState): void {
  checkFrameShape(p, lineNo, push);
  // INV3a cursor 连续
  const idx = p.step_index;
  if (typeof idx !== "number" || !Number.isSafeInteger(idx)) {
    push(lineNo, "INV3a", `step_index 非整数：${String(idx)}`, idx);
  } else {
    if (idx !== st.prevStepIndex + 1) {
      push(lineNo, "INV3a", `step_index 不连续：${st.prevStepIndex} -> ${idx}`, idx);
    }
    st.prevStepIndex = idx;
  }
  // INV2 栈深
  const cs = Array.isArray(p.call_stack) ? p.call_stack : [];
  const depth = cs.length;
  if (depth < 0 || depth > CALL_DEPTH_LIMIT) {
    push(lineNo, "INV2a", `栈深 ${depth} 越域 [0,${CALL_DEPTH_LIMIT}]`, idx);
  }
  if (st.prevDepth >= 0 && Math.abs(depth - st.prevDepth) > 1) {
    push(lineNo, "INV2b", `栈深跳变 ${st.prevDepth} -> ${depth}（单步至多一次 call/ret）`, idx);
  }
  st.prevDepth = depth;
  const bottom = cs[0];
  if (depth > 0 && bottom?.func_name !== "main") {
    push(lineNo, "INV2c", `底帧非 main：${String(bottom?.func_name)}`, idx);
  }
  // INV1a/1b 变量地址域
  const vars = Array.isArray(p.local_vars) ? p.local_vars : [];
  for (const v of vars) {
    const addr = v.addr;
    if (typeof addr !== "number" || !(addr >= NULL_TRAP_SIZE && addr + 4 <= MEM_SIZE)) {
      push(lineNo, "INV1a", `变量 ${String(v.name)} addr=${String(addr)} 越 [${NULL_TRAP_SIZE},${MEM_SIZE}-4]`, idx);
      continue;
    }
    if (v.is_local === false && !(addr >= GLOBAL_START && addr < GLOBAL_REGION_LIMIT)) {
      push(lineNo, "INV1b", `全局变量 ${String(v.name)} addr=${addr} 越全局区 [${GLOBAL_START},${GLOBAL_REGION_LIMIT})`, idx);
    }
  }
  // INV1c/INV4 指针快照
  const ptrs = Array.isArray(p.pointer_snapshots) ? p.pointer_snapshots : [];
  for (const q of ptrs) {
    const addr = q.addr;
    if (typeof addr !== "number" || !(addr >= NULL_TRAP_SIZE && addr + 4 <= MEM_SIZE)) {
      push(lineNo, "INV1a", `指针 ${String(q.name)} addr=${String(addr)} 越 [${NULL_TRAP_SIZE},${MEM_SIZE}-4]`, idx);
    }
    const t = q.target_addr;
    const status = q.status;
    if (typeof t !== "number" || typeof status !== "string") {
      push(lineNo, "INV4", `指针 ${String(q.name)} target_addr/status 形状缺：${String(t)}/${String(status)}`, idx);
      continue;
    }
    const inDomain = t >= NULL_TRAP_SIZE && t < MEM_SIZE;
    if (status === "Null") {
      if (t !== 0) push(lineNo, "INV4", `Null 指针 ${String(q.name)} target=${t} 非 0`, idx);
    } else if (status === "Dangling") {
      if (!(t !== 0 && !inDomain)) {
        push(lineNo, "INV4", `Dangling 指针 ${String(q.name)} target=${t} 未越区（判定与域不自洽）`, idx);
      }
    } else if (status === "Valid" || status === "Freed") {
      if (!inDomain) {
        push(lineNo, "INV4", `${status} 指针 ${String(q.name)} target=${t} 越区 [${NULL_TRAP_SIZE},${MEM_SIZE})`, idx);
      }
      if (status === "Freed" && t < HEAP_START) {
        push(lineNo, "INV1c", `Freed 指针 ${String(q.name)} target=${t} < HEAP_START=${HEAP_START}（Freed 命中区必为堆）`, idx);
      }
    } else {
      push(lineNo, "INV4", `指针 ${String(q.name)} 未知 status=${status}`, idx);
    }
  }
}

// ── 驱动 ──

function jsShellPath(root: string): string {
  return path.join(root, "moonbit", "_build", "js", "release", "build", "cmd", "vitro_js", "vitro_js.js");
}

/** REHOST 批 3 装载标记判定（纯函数——checkFile close 回调消费）：
 * 终态驱动形态（rc 0 正常 / 2 trap / 3 步数超限——rc=1 编译失败早退未达
 * step.begin 不在断言面）stderr 须含 `// WASM-REHOST-STEP ok`；缺失
 * （旗标未生效/协议破损）或 fallback（装载回退）返回违例文案，否则 null。
 * 「fallback 即红」与批 2b wasmenc_rundiff 同款纪律——flag on 形态的
 * 受检前提是装载真实生效，静默回退会让不变量检查跑在 legacy 上假绿。 */
export function rehostMarkerViolation(rc: number, stderrTail: string): string | null {
  if (rc !== 0 && rc !== 2 && rc !== 3) return null;
  if (stderrTail.includes("// WASM-REHOST-STEP ok")) return null;
  return `rehost 装载标记缺失/回退（stderr 尾部：${stderrTail.slice(-300)}）`;
}

/** 采一语料帧流并检查（流式逐行 feed 即弃——大语料 NDJSON 数十 MB 不驻留）。
 * stepBudget > 0 时透传 `--max-steps`（spot 轮大语料降档——预算封顶换墙钟，
 * 截断流仍是合法检查面；PR #478 审阅 P1-2）。
 * rehost = true 时透传 `--wasm-rehost`（REHOST 批 3：step 态装载走 wasm
 * 载体往返）并断言装载标记行（判定单源 rehostMarkerViolation）。 */
export async function checkFile(
  shell: string,
  file: string,
  source: string,
  timeoutMs: number,
  stepBudget = 0,
  rehost = false,
): Promise<StreamCheckResult & { rc: number; timedOut: boolean }> {
  return new Promise((resolve) => {
    const args = [shell, "step", file, "--json"];
    if (stepBudget > 0) args.push("--max-steps", String(stepBudget));
    if (rehost) args.push("--wasm-rehost");
    const child = spawn(process.execPath, args, {
      stdio: ["ignore", "pipe", "pipe"],
    });
    const checker = new StreamChecker(source);
    let timedOut = false;
    let settled = false;
    const timer = setTimeout(() => {
      timedOut = true;
      child.kill();
    }, timeoutMs);
    const rl = readline.createInterface({ input: child.stdout });
    rl.on("line", (line) => checker.feed(line));
    let stderrTail = "";
    child.stderr.on("data", (d: Buffer) => {
      if (stderrTail.length < 2000) stderrTail += d.toString("utf8");
    });
    // spawn 级失败（node 缺失/脚本路径坏）立即落账——不等超时（P1-1 处方）
    child.on("error", (e) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve({ violations: [{ source, line: 0, invariant: "DRIVER", detail: `spawn 失败：${String(e)}` }], frames: 0, terminal: "none", rc: -1, timedOut: false });
    });
    child.on("close", (rc) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (timedOut) {
        // 超时不在此落违例——driver 层复跑一次，两轮尽才收 timeout 单列（P1-1）
        resolve({ violations: [], frames: checker.frameCount, terminal: "timeout", rc: rc ?? -1, timedOut: true });
        return;
      }
      // rc=4 = 用法错/源不可读（cli_step 契约）——语料形态单列，不红（P3-6）。
      // **rehost 轮例外（PR #520 审阅 P2-2 fail-open 修）**：rc=4 在
      // rehost 轮计 DRIVER 红——「未知旗标 → rc=4」的桩形态下 rc=4 恰是
      // 旗标未生效的信号，旧形态被 rc 豁免分支吞掉 = 防线被绕过。
      if (rc === 4) {
        if (rehost) {
          resolve({ violations: [{ source, line: 0, invariant: "DRIVER", detail: "rehost 轮 rc=4（用法错/不可读——若 js 壳为「未知旗标」桩形态即旗标未生效）" }], frames: 0, terminal: "none", rc, timedOut: false });
          return;
        }
        resolve({ violations: [], frames: 0, terminal: "unreadable", rc, timedOut: false });
        return;
      }
      // rc 非 0/1/2/3 的驱动级失败（js 壳崩溃等）——fail loud
      if (rc !== null && rc !== 0 && rc !== 1 && rc !== 2 && rc !== 3) {
        resolve({ violations: [{ source, line: 0, invariant: "DRIVER", detail: `js 壳异常退出 rc=${rc}：${stderrTail.slice(0, 400)}` }], frames: 0, terminal: "none", rc, timedOut: false });
        return;
      }
      // REHOST 批 3 装载断言（rehost 轮专用——判定单源 rehostMarkerViolation，
      // 纯函数可测；rc=1 编译失败早退未达 step.begin，不在断言面）
      if (rehost) {
        const marker = rehostMarkerViolation(rc ?? -1, stderrTail);
        if (marker !== null) {
          resolve({ violations: [{ source, line: 0, invariant: "DRIVER", detail: marker }], frames: checker.frameCount, terminal: "none", rc: rc ?? -1, timedOut: false });
          return;
        }
      }
      resolve({ ...checker.finish(), rc: rc ?? -1, timedOut: false });
    });
  });
}

/** 两轮预算：首跑超时自动复跑一次（编码原手工 workaround——挂起复现率
 * ~0.2%/spawn，复跑即解；预算真不够则两轮尽收 timeout 单列不红，P1-1）。 */
export async function checkFileRetry(
  shell: string,
  file: string,
  source: string,
  timeoutMs: number,
  stepBudget = 0,
  rehost = false,
): Promise<StreamCheckResult & { rc: number; timedOut: boolean }> {
  const first = await checkFile(shell, file, source, timeoutMs, stepBudget, rehost);
  if (!first.timedOut) return first;
  const second = await checkFile(shell, file, source, timeoutMs, stepBudget, rehost);
  return second;
}

function listCorpus(dir: string): string[] {
  const out: string[] = [];
  const walk = (d: string): void => {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) walk(p);
      else if (e.isFile() && e.name.endsWith(".c")) out.push(p);
    }
  };
  walk(dir);
  out.sort();
  return out;
}

function usage(): never {
  process.stderr.write(`用法: node scripts/step_invariant/main.mts <file.c> [...]
      node scripts/step_invariant/main.mts --corpus <dir> [--sample N] [--jobs N]
            [--timeout-ms N] [--step-budget N] [--json] [--audit-known] [--rehost]
`);
  process.exit(1);
}

interface Opts {
  files: string[];
  corpus: string | null;
  sample: number;
  jobs: number;
  timeoutMs: number;
  /** 透传 `vitro step --max-steps`（spot 轮大语料降档，0 = 不透传）。 */
  stepBudget: number;
  /** REHOST 批 3：透传 `vitro step --wasm-rehost`（step 态装载走 wasm
   * 载体往返）+ 装载标记行断言（fallback/缺失即红——见 checkFile 头注）。 */
  rehost: boolean;
  json: boolean;
  auditKnown: boolean;
}

function parseArgs(argv: string[]): Opts {
  const o: Opts = { files: [], corpus: null, sample: 0, jobs: 4, timeoutMs: 120_000, stepBudget: 0, rehost: false, json: false, auditKnown: false };
  let i = 0;
  while (i < argv.length) {
    const a = argv[i++];
    if (a === undefined) usage();
    if (a === "--corpus") {
      o.corpus = argv[i++] ?? usage();
    } else if (a === "--sample") {
      const v = Number(argv[i++]);
      if (!Number.isInteger(v) || v < 1) usage();
      o.sample = v;
    } else if (a === "--jobs") {
      const v = Number(argv[i++]);
      if (!Number.isInteger(v) || v < 1 || v > 64) usage();
      o.jobs = v;
    } else if (a === "--timeout-ms") {
      const v = Number(argv[i++]);
      if (!Number.isInteger(v) || v < 1000) usage();
      o.timeoutMs = v;
    } else if (a === "--step-budget") {
      const v = Number(argv[i++]);
      if (!Number.isInteger(v) || v < 1) usage();
      o.stepBudget = v;
    } else if (a === "--rehost") {
      o.rehost = true;
    } else if (a === "--json") {
      o.json = true;
    } else if (a === "--audit-known") {
      o.auditKnown = true;
    } else if (a.startsWith("-")) {
      usage();
    } else {
      o.files.push(a);
    }
  }
  if (o.files.length === 0 && o.corpus === null) usage();
  return o;
}

/** 白名单条目（(case, invariant) 粒度；count = 期望命中条数上限——
 * 超过即「白名单数量恶化」红，防同根因恶化静默放行，PR #478 审阅 P3-2）。 */
export interface KnownEntry {
  case: string;
  invariant: string;
  reason: string;
  issue: string;
  count?: number;
}

export const KNOWN_PATH = "scripts/step_invariant/known_violations.json";

export function loadKnown(root: string): KnownEntry[] {
  const p = path.join(root, KNOWN_PATH);
  if (!fs.existsSync(p)) return [];
  return JSON.parse(fs.readFileSync(p, "utf8")) as KnownEntry[];
}

/** 白名单三态判定（纯函数）：RED（未登记或超 count 恶化）/ EXPECTED_RED
 * （登记命中）/ ZOMBIE 候选（登记未命中——audit 轮收）。case 斜杠归一
 * （Windows path.relative 产反斜杠——白名单一律正斜杠）。 */
export function classifyViolations(
  allViolations: readonly Violation[],
  known: readonly KnownEntry[],
  source = "",
): { reds: Violation[]; expected: Violation[]; hitKeys: Set<string>; worsened: Violation[] } {
  const hitCount = new Map<string, number>();
  const reds: Violation[] = [];
  const expected: Violation[] = [];
  const worsened: Violation[] = [];
  for (const v of allViolations) {
    const key = `${v.source.split(path.sep).join("/")}::${v.invariant}`;
    const entry = known.find((k) => `${k.case}::${k.invariant}` === key);
    if (entry === undefined) {
      reds.push(v);
      continue;
    }
    hitCount.set(key, (hitCount.get(key) ?? 0) + 1);
    const cap = entry.count ?? Number.POSITIVE_INFINITY;
    if (hitCount.get(key) === cap + 1) {
      worsened.push(v);
    }
    expected.push(v);
  }
  // 恶化条目从 expected 挪入 red（cap 内仍 expected，超出即红）
  if (worsened.length > 0) {
    const wset = new Set(worsened);
    for (let i = expected.length - 1; i >= 0; i--) {
      if (wset.has(expected[i] ?? ({} as Violation))) {
        const x = expected.splice(i, 1)[0];
        if (x !== undefined && !reds.includes(x)) reds.push(x);
      }
    }
  }
  void source;
  return { reds, expected, hitKeys: new Set(hitCount.keys()), worsened };
}

/** 抽样（确定性——等距 stride 取样，可复现；P3-5 勘正原「hash 取样」误注）。 */
function sampleFiles(files: string[], n: number): string[] {
  const picked: string[] = [];
  const step = Math.max(1, Math.floor(files.length / n));
  for (let i = 0; i < files.length && picked.length < n; i += step) {
    picked.push(files[i] ?? "");
  }
  return picked;
}

async function main(): Promise<void> {
  const opts = parseArgs(process.argv.slice(2));
  const root = projectRoot();
  const shell = jsShellPath(root);
  ensureFresh("step_invariant", shell, ["build", "--release", "--target", "js", "cmd/vitro_js"]);
  let files = opts.files.map((f) => path.resolve(f));
  if (opts.corpus !== null) {
    const dir = path.resolve(opts.corpus);
    let all = listCorpus(dir);
    if (opts.sample > 0) all = sampleFiles(all, opts.sample);
    files = files.concat(all);
  }
  const t0 = Date.now();
  const results: Array<{ file: string; r: Awaited<ReturnType<typeof checkFile>> }> = [];
  let cursor = 0;
  const worker = async (): Promise<void> => {
    for (;;) {
      const f = files[cursor];
      if (f === undefined) break;
      cursor++;
      const r = await checkFileRetry(shell, f, path.relative(root, f), opts.timeoutMs, opts.stepBudget, opts.rehost);
      results.push({ file: f, r });
    }
  };
  await Promise.all(Array.from({ length: Math.min(opts.jobs, files.length) }, worker));
  results.sort((a, b) => a.file.localeCompare(b.file));
  const elapsed = Date.now() - t0;
  const totalFrames = results.reduce((s, x) => s + x.r.frames, 0);
  const compileError = results.filter((x) => x.r.terminal === "compile-error").length;
  const terminals = { finished: 0, trapped: 0, waiting_input: 0, none: 0, "compile-error": 0, timeout: 0, unreadable: 0 } as Record<string, number>;
  for (const x of results) terminals[x.r.terminal] = (terminals[x.r.terminal] ?? 0) + 1;
  const allViolations = results.flatMap((x) => x.r.violations);
  // 白名单三态（classifyViolations 纯函数——RED/EXPECTED_RED/恶化/ZOMBIE；
  // timeout/unreadable 已在 checkFile 单列不产生违例）
  const known = loadKnown(root);
  const { reds, expected, hitKeys } = classifyViolations(allViolations, known);
  const zombies = opts.auditKnown ? known.filter((k) => !hitKeys.has(`${k.case}::${k.invariant}`)) : [];
  if (opts.json) {
    process.stdout.write(
      JSON.stringify(
        {
          files: files.length,
          frames: totalFrames,
          compile_error: compileError,
          terminals,
          red: reds.length,
          expected_red: expected.length,
          zombie: zombies.length,
          elapsed_ms: elapsed,
          red_details: reds.slice(0, 200),
          zombie_details: zombies,
        },
        null,
        0,
      ) + "\n",
    );
  } else {
    for (const v of reds.slice(0, 50)) {
      process.stdout.write(`RED ${v.source}:${v.line}${v.stepIndex !== undefined ? ` step${v.stepIndex}` : ""} [${v.invariant}] ${v.detail}\n`);
    }
    for (const v of expected.slice(0, 20)) {
      process.stdout.write(`EXPECTED_RED ${v.source} [${v.invariant}] ${v.detail}\n`);
    }
    for (const z of zombies) {
      process.stdout.write(`ZOMBIE ${z.case} [${z.invariant}] 白名单条目本轮未命中（语料/引擎已演化？）\n`);
    }
    process.stdout.write(
      `语料 ${files.length} | 帧 ${totalFrames} | compile-error ${compileError} | 终态 ${JSON.stringify(terminals)} | RED ${reds.length} | EXPECTED_RED ${expected.length} | ZOMBIE ${zombies.length} | ${elapsed}ms\n`,
    );
  }
  process.exit(reds.length > 0 || zombies.length > 0 ? 1 : 0);
}

// 测试侧 import 时不跑驱动（仓内惯例：argv[1] 与本模块 URL 判同）
const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  void main();
}
