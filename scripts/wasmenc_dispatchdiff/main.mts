#!/usr/bin/env node
// wasmenc_dispatchdiff —— REHOST 批 4b-3 三方对拍闸（设计单 §3.2 批 4′
// 验收面①：全语料**零禁译子集** dispatch 载体 V8 vs 引擎零 DIFF +
// wasmtime 同判——真 runtime 执行级独立证人，不可逆退役决策依据的
// 组成件〔2026-11-14 批次序修订〕）。
//
// 三臂形态：
//   - V8 臂：本进程 `WebAssembly`（CI node 即 V8）实例化 dump_wasm 的
//     dispatch 模块——data 铺设 → main() → steps；
//   - wasmtime 臂：`scripts/wasmtime_arm/rs` 的 `dispatch` 子命令（批
//     模式一次 spawn——MVP 模块零 js-string 面，wasmtime 50 默认配置）；
//   - 引擎臂：cmd/run --json（run 帧 result：return_value/steps_executed/
//     trap_code + stdout 帧 delta——权威真值）。
//
// 判定口径（结果级三锚 + 已知分叉豁免——dispatchloop 头注登记面）：
//   1. finished 例：三方 rc + steps + stdout（零 host 子集恒空，仍断言）
//      逐位一致；
//   2. trap 例：三方「trap 均发生」即绿（V8 RuntimeError / wasmtime trap
//      行 / 引擎 run.status=trap）——**steps 豁免**（块批量计步在 trap
//      点 overshoot ≤1 块——与预算例同族的已知分叉）；预算例（引擎
//      E3091 或 V8 main()==-1）同 trap 处理；
//   3. host 桩被调（host_used>0）即红——零 host 子集的运行期双保险
//     （静态 host_calls 计数互证）；
//   4. memory **不入锚**：VFS 预置写集（gateway 会话语义——0x10000 区）
//      与软件栈 12B 帧头内嵌（栈区布局）两类装载差异是登记的批 5
//      评估面（摸底归因 2026-11-15）；
//   5. 禁译面按 reason 前缀分桶登记（baseline.json 下限钉住——下跌即
//      红；callhost=host 回接批、wide-param/variadic/CallPtr=静态不可
//      展开面）；编译失败例计数不红（codegen_diff 域）；
//   6. 每目录磁盘 .c 递归计数 == dump 行数 + 磁盘对账 + 裸旗 fail loud
//      （emitgate/rundiff 同款 fail-open 防护三件套）。
//
// 产物：coverage.json（禁译覆盖率——facts 静态采集消费，随批提交）。
//
// 用法：node scripts/wasmenc_dispatchdiff/main.mts [--dir corpus/baseline ...]
//（无参 = 全目录集；零 host 子集三方对拍 + wasmtime 批模式，全量 ~1 分钟）。
import { spawnSync } from "node:child_process";
import { Worker } from "node:worker_threads";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { ensureFresh } from "../internal/freshness.mts";
import { projectRoot } from "../internal/capi.mts";
import { CORPUS_DIRS } from "../wasmenc_emitgate/main.mts";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const root = projectRoot();

/// dispatch dump 行（dump_wasm 成功行的 dispatch 段——字段面见 dump_wasm 头注）
export interface DispatchSeg {
  ok: boolean;
  module?: string;
  data?: string;
  base?: number;
  entry?: number;
  groups?: number;
  host_calls?: number;
  max_steps?: number;
  /// 窗口装载参数（批 4′ host 回接——中继 INIT 帧消费：堆基/argv 区
  /// 引擎侧同源铺设的布局输入）
  win_data_end?: number;
  win_argc?: number;
  win_argv0?: string;
  reason?: string;
}

/// V8 / wasmtime 臂统一结果形态（wasmtime 出口行解析同形）
export interface RuntimeArmResult {
  /// "ok"（main 返回，rc 携值）| "trap"（RuntimeError/trap 行）| "host"（桩被调）
  kind: "ok" | "trap" | "host";
  rc?: number;
  steps: number;
  /// V8 臂 stdout（host 回接 delta 累积——对拍锚；wasmtime 臂批 4″ 回接前恒空）
  stdout?: Buffer;
  /// trap 结构化码（RelayTrap 通道——终态类别对拍）
  trapCode?: string;
  /// wasmtime 侧编译失败单行信息（bad 行——逐例 catch 形态）
  badCompile?: string;
  note?: string;
}

/// 引擎臂结果（cmd/run --json 的 run 帧 + stdout 帧）
export interface EngineArmResult {
  /// run.status: "finished" | "trap"（其余形态红——waiting_input 不该发生：零 host 无 scanf）
  status: string;
  returnValue?: number;
  trapCode?: string;
  steps: number;
  stdout: Buffer;
}

/// 判定一例三方对拍 → null（绿）或红描述（纯函数——node:test 消费）。
export function judgeCase(
  file: string,
  v8: RuntimeArmResult,
  wt: RuntimeArmResult,
  eng: EngineArmResult,
): string | null {
  // ① host 桩被调（任一 runtime 臂）即红
  if (v8.kind === "host" || wt.kind === "host") {
    return `${file}: host 桩被调（零 host 子集运行期违约——静态计数与运行态分叉）`;
  }
  // ② trap/预算形态：三方「终态类别」一致。预算归一**与引擎 E3091 绑定**
  //（PR #526 审阅 P2-1：合法 `main` 返回 -1 的零 host 例被无条件当预算态
  // 误报「终态类别分叉」——`ret_minus1` 探针实锤；修后 eng finished
  // rv=-1 的例走下方 finished 逐位对拍）
  const budgetEng = eng.status === "trap" && eng.trapCode === "E3091";
  const isTrapV8 = v8.kind === "trap" || (v8.kind === "ok" && v8.rc === -1 && budgetEng);
  const isTrapWt = wt.kind === "trap" || (wt.kind === "ok" && wt.rc === -1 && budgetEng);
  const isTrapEng = eng.status === "trap";
  if (isTrapV8 || isTrapWt || isTrapEng) {
    // 三方须同类别（全部 trap/预算 归一态）
    if (!(isTrapV8 && isTrapWt && isTrapEng)) {
      return `${file}: 终态类别分叉 v8=${v8.kind}${v8.rc ?? ""} wt=${wt.kind}${wt.rc ?? ""} eng=${eng.status}${eng.trapCode ?? ""}`;
    }
    // trap 例（批 4′ 起 host 输出合法先行——printf 后 trap 形态）：
    // stdout 两侧逐位（V8 delta 累积 vs 引擎）；steps 豁免（overshoot ≤1 块）
    const v8Out = v8.stdout ?? Buffer.alloc(0);
    if (!v8Out.equals(eng.stdout)) {
      return `${file}: trap 例 stdout 分叉 v8=${v8Out.length}B eng=${eng.stdout.length}B`;
    }
    return null;
  }
  // ③ finished 例：rc + steps + stdout 三方逐位
  if (eng.status !== "finished") {
    return `${file}: 引擎终态非常规 ${eng.status}`;
  }
  if (v8.kind !== "ok" || wt.kind !== "ok") {
    return `${file}: runtime 臂非 ok 态 v8=${v8.kind} wt=${wt.kind}`;
  }
  if (v8.rc !== eng.returnValue || wt.rc !== eng.returnValue) {
    return `${file}: rc 分叉 v8=${v8.rc} wt=${wt.rc} eng=${eng.returnValue}`;
  }
  if (v8.steps !== eng.steps || wt.steps !== eng.steps) {
    return `${file}: steps 分叉 v8=${v8.steps} wt=${wt.steps} eng=${eng.steps}`;
  }
  const v8OutF = v8.stdout ?? Buffer.alloc(0);
  if (!v8OutF.equals(eng.stdout)) {
    return `${file}: stdout 分叉 v8=${v8OutF.length}B eng=${eng.stdout.length}B`;
  }
  return null;
}

/// host 例对拍包装（批 4′）：wasmtime 臂未回接（批 4″）——wt 以 v8
/// 镜像代入（三方判定式恒过 wt 维 = V8×引擎双方实质判定；wt_pending
/// 计数已登记不静默）
export function judgeCaseHost(
  file: string,
  v8: RuntimeArmResult,
  wt: RuntimeArmResult,
  eng: EngineArmResult,
  isHostCase: boolean,
): string | null {
  if (!isHostCase) return judgeCase(file, v8, wt, eng);
  const wtMirror: RuntimeArmResult = {
    kind: v8.kind,
    rc: v8.rc,
    steps: v8.steps,
    stdout: v8.stdout,
    trapCode: v8.trapCode,
  };
  return judgeCase(file, v8, wtMirror, eng);
}

/// wasmtime 出口行（`ok <rc> <steps>` / `trap <steps> <msg..>` / `host <steps>` /
/// `bad <msg..>`〔编译失败——PR #526 审阅 P2-4 逐例 catch，不再中止整批〕）
/// → RuntimeArmResult（纯函数——node:test 消费）
export function parseWasmtimeLine(line: string): RuntimeArmResult | null {
  const sp = line.indexOf(" ");
  if (sp < 0) return null;
  const kind = line.slice(0, sp);
  const rest = line.slice(sp + 1);
  if (kind === "bad") {
    return { kind: "trap", steps: -1, badCompile: rest };
  }
  if (kind === "host") {
    return { kind: "host", steps: Number(rest) };
  }
  if (kind === "trap") {
    const m = rest.match(/^(\d+) /);
    if (m === null) return null;
    return { kind: "trap", steps: Number(m[1]) };
  }
  if (kind === "ok") {
    const m = rest.match(/^(-?\d+) (\d+)$/);
    if (m === null) return null;
    return { kind: "ok", rc: Number(m[1]), steps: Number(m[2]) };
  }
  return null;
}

/// 中继停机语义（import 回调 throw 穿透 wasm 帧——V8 异常透传标准行为；
/// wasmtime 走 trap 头 unreachable 通道〔批 4″ 回接〕）
export class RelayTrap extends Error {
  readonly code: string;
  readonly msg: string;
  constructor(code: string, msg: string) {
    super(`relay-trap ${code}`);
    this.code = code;
    this.msg = msg;
  }
}

///|
export class RelayHalt extends Error {
  readonly exitCode: number;
  constructor(exitCode: number) {
    super(`relay-halt ${exitCode}`);
    this.exitCode = exitCode;
  }
}

///|
/// host 中继客户端（批 4′）：spawn `cmd/host_relay` js 产物——同步帧协议
/// （协议单源见 moonbit/cmd/host_relay/main.mbt 头注）。**同步桥形态**
/// （node 26 Windows 子进程管道无同步 fd——`stdin.fd` undefined 实锤）：
/// IO Worker 持有子进程做异步读写，主线程 Atomics.wait 同步等待——
/// V8 的 wasm import 回调是同步语义，桥接是唯一形态。每例一个 INIT
/// （幂等重建：VM 状态/堆/值栈不跨例污染）。
///
/// SAB 布局（4MB 双向复用）：[0]=state（0=空闲/1=请求就绪/2=响应就绪/
/// 3=worker 错误）、[1]=请求长、[2]=响应长、[8..]=payload。
export class HostRelayProc {
  private worker: Worker;
  private sab: Int32Array;
  private payload: Uint8Array;
  private errText: string;

  constructor(relayJs: string) {
    this.sab = new Int32Array(new SharedArrayBuffer(4 * 1024 * 1024));
    this.payload = new Uint8Array(this.sab.buffer);
    this.errText = "";
    const sabBuf = this.sab.buffer;
    this.worker = new Worker(
      `const fs = require("node:fs");
       const { spawn } = require("node:child_process");
       const { parentPort, workerData } = require("node:worker_threads");
       const sab = new Int32Array(workerData.sab);
       const payload = new Uint8Array(workerData.sab);
       const child = spawn(process.execPath, [workerData.relayJs], { stdio: ["pipe", "pipe", "inherit"] });
       let out = Buffer.alloc(0);
       child.stdout.on("data", (c) => { out = Buffer.concat([out, c]); });
       child.on("exit", (c) => { sab[0] = 3; sab[2] = 0; Atomics.notify(sab, 0); });
       parentPort.on("message", (m) => {
         if (m !== "wake") return;
         const n = sab[1];
         const req = Buffer.from(payload.buffer, 16, n);
         out = Buffer.alloc(0);
         child.stdin.write(req, (e) => {
           if (e) { sab[0] = 3; Atomics.notify(sab, 0); return; }
           pump();
         });
         function pump() {
           // 同步等待应答字节齐：应答长度由首行解析——逐段读直到可切帧
           //（帧自描述：行内含 delta_len/code_len；镜像恒 1MB 尾随）
           const tryOnce = () => {
             for (;;) {
               const nl = out.indexOf(0x0a);
               if (nl < 0) return false;
               const line = out.subarray(0, nl).toString("latin1").split(" ");
               if (line[0] === "OK") { flush(nl + 1); return true; }
               if (line[0] !== "RES" || line.length < 7) return false;
               const codeLen = Number(line[5]); const deltaLen = Number(line[6]);
               if (out.length >= nl + 1 + codeLen + deltaLen + 1048576) { flush(nl + 1 + codeLen + deltaLen + 1048576); return true; }
               return false;
             }
           };
           const flush = (bodyLen) => {
             const body = out.subarray(0, bodyLen);
             if (body.length > payload.length - 16) { sab[0] = 3; Atomics.notify(sab, 0); return; }
             payload.set(body, 16);
             sab[2] = body.length;
             sab[0] = 2;
             Atomics.notify(sab, 0);
           };
           const wait = () => {
             if (tryOnce()) return;
             const t = setTimeout(() => { clearTimeout(t); if (!tryOnce()) wait(); }, 5);
           };
           wait();
         }
       });`,
      { eval: true, workerData: { sab: sabBuf, relayJs } },
    );
    this.worker.on("error", (e) => {
      this.errText = String(e).slice(0, 200);
      Atomics.store(this.sab, 0, 3);
      Atomics.notify(this.sab, 0);
    });
    this.worker.unref();
  }

  private transact(req: Buffer): Buffer {
    Atomics.store(this.sab, 0, 0);
    Atomics.store(this.sab, 1, req.length);
    this.payload.set(req, 16);
    Atomics.store(this.sab, 0, 1);
    Atomics.notify(this.sab, 0);
    this.worker.postMessage("wake");
    for (;;) {
      const r = Atomics.wait(this.sab, 0, 1);
      if (r === "ok" && this.sab[0] !== 1) break;
      if (this.sab[0] === 1) continue;
    }
    const state = Atomics.load(this.sab, 0);
    if (state === 3) throw new Error(`relay worker/child 失败${this.errText}`);
    const n = this.sab[2]!;
    return Buffer.from(this.payload.buffer, 16, n);
  }

  /// INIT 帧（data 铺设后的 1MB 镜像 + 布局参数——堆基/argv 引擎侧同源）
  init(dataEnd: number, argcMain: number, argv0: string, mem: Uint8Array): void {
    const hex = Buffer.from(argv0, "utf8").toString("hex");
    const head = Buffer.from(`INIT ${dataEnd} ${argcMain} ${hex}
`, "latin1");
    const req = Buffer.concat([head, Buffer.from(mem.buffer, mem.byteOffset, mem.byteLength)]);
    const resp = this.transact(req);
    if (resp.toString("latin1").trim() !== "OK") {
      throw new Error(`relay init failed: ${resp.toString("latin1").slice(0, 100)}`);
    }
  }

  /// CALL 帧：参数（窗口 i64×argc）+ wasm 内存全量 → 应答三态 + stdout 增量 + 引擎镜像
  call(id: number, args: bigint[], mem: Uint8Array): {
    kind: 0 | 1 | 2;
    value: bigint;
    exitCode: number;
    code: string;
    msg: string;
    waiting: boolean;
    delta: Buffer;
    image: Buffer;
  } {
    const head = Buffer.alloc(args.length * 8);
    let o = 0;
    for (const a of args) {
      head.writeBigUInt64LE(a & 0xffffffffffffffffn, o);
      o += 8;
    }
    const req = Buffer.concat([
      Buffer.from(`CALL ${id} ${args.length}
`, "latin1"),
      head,
      Buffer.from(mem.buffer, mem.byteOffset, mem.byteLength),
    ]);
    const resp = this.transact(req);
    const nl = resp.indexOf(0x0a);
    if (nl < 0) throw new Error("relay proto: 无应答行");
    const line = resp.subarray(0, nl).toString("latin1").split(" ");
    if (line[0] !== "RES" || line.length < 7) throw new Error(`relay proto: ${resp.subarray(0, 80).toString("latin1")}`);
    const kind = Number(line[1]) as 0 | 1 | 2;
    const lo = BigInt(line[2]!);
    const hi = BigInt(line[3]!);
    const waiting = line[4] === "1";
    const codeLen = Number(line[5]);
    const deltaLen = Number(line[6]);
    let p = nl + 1;
    let code = "";
    let msg = "";
    if (codeLen > 0) {
      const payloadB = resp.subarray(p, p + codeLen).toString("utf8").split("\x00");
      code = payloadB[0] ?? "";
      msg = payloadB.slice(1).join("\x00");
      p += codeLen;
    }
    const delta = Buffer.from(resp.subarray(p, p + deltaLen));
    p += deltaLen;
    const image = Buffer.from(resp.subarray(p, p + 1048576));
    return { kind, value: lo | (hi << 32n), exitCode: Number(lo), code, msg, waiting, delta, image };
  }

  dispose(): void {
    void this.worker.terminate();
  }
}

/// V8 臂：进程内实例化 + data 铺设 + main()（批 4′ 起 host 真回接——
/// import 回调经 HostRelayProc 驱动引擎单源分发；stdout 增量累积为
/// 对拍锚；trap/halt 经异常通道分类终态）
export function v8Arm(
  disp: DispatchSeg,
  relay?: HostRelayProc,
): RuntimeArmResult | null {
  let inst: WebAssembly.Instance;
  const stdoutChunks: Buffer[] = [];
  // host 回接：窗口读取（trap@+0/argc@+4/参数@+8×argc——dispatchloop
  // push_host_call_expand 布局单源）→ 中继调用（wasm 内存全量 → 引擎
  // 单源分发 → 镜像回写）→ 三态应答
  const hostCall = (routeId: number, argvPtr: number): bigint => {
    if (relay === undefined) {
      throw new RelayTrap("E-RELAY", "host 桩被调（无中继——零 host 域违约）");
    }
    const mem = inst.exports.memory as WebAssembly.Memory;
    const view = new DataView(mem.buffer);
    const argc = view.getInt32(argvPtr + 4, true);
    const args: bigint[] = [];
    for (let i = 0; i < argc; i++) {
      args.push(view.getBigUint64(argvPtr + 8 + i * 8, true));
    }
    const snap = new Uint8Array(1048576);
    snap.set(new Uint8Array(mem.buffer, 0, 1048576));
    const r = relay.call(routeId, args, snap);
    if (r.waiting) {
      throw new RelayTrap("E-WAITING", "Stdin 族在白名单域命中（协议破裂）");
    }
    if (r.kind === 1) throw new RelayTrap(r.code, r.msg);
    if (r.kind === 2) throw new RelayHalt(r.exitCode);
    // 引擎镜像回写（引擎→wasm 方向全量）
    new Uint8Array(mem.buffer).set(r.image);
    if (r.delta.length > 0) stdoutChunks.push(r.delta);
    return r.value;
  };
  try {
    const mod = new WebAssembly.Module(Buffer.from(disp.module ?? "", "hex"));
    inst = new WebAssembly.Instance(mod, {
      env: {
        vitro_host_call: hostCall,
      },
    });
  } catch {
    return null; // 编译失败——上层按「产物非法」红
  }
  const data = Buffer.from(disp.data ?? "", "hex");
  const mem = inst.exports.memory as WebAssembly.Memory;
  new Uint8Array(mem.buffer, disp.base ?? 0, data.length).set(data);
  // 中继会话装载（data 铺设后的 1MB 镜像 + 布局参数——堆基/argv 单源）
  if (relay !== undefined) {
    relay.init(disp.win_data_end ?? 0, disp.win_argc ?? 0, disp.win_argv0 ?? "", new Uint8Array(mem.buffer, 0, 1048576));
  }
  let rc: number | undefined;
  let trapped = false;
  let trapCode = "";
  try {
    rc = (inst.exports.main as () => number)();
  } catch (e) {
    trapped = true;
    if (e instanceof RelayHalt) {
      trapped = false;
      rc = e.exitCode;
    } else if (e instanceof RelayTrap) {
      trapCode = e.code;
    }
  }
  const steps = Number((inst.exports.steps as WebAssembly.Global).value);
  const stdout = Buffer.concat(stdoutChunks);
  if (trapped) return { kind: "trap", steps, stdout, trapCode };
  return { kind: "ok", rc, steps, stdout, trapCode };
}

/// 引擎臂：cmd/run --json（rc/steps/trap 从 run 帧；stdout 从 stdout 帧）
function engineArm(rel: string): EngineArmResult | null {
  const r = spawnSync(
    path.join(root, "moonbit/_build/native/debug/build/cmd/run/run.exe"),
    ["--json", rel],
    { cwd: root, maxBuffer: 64 << 20, timeout: 30000 },
  );
  if (r.status === null) return null;
  const frames = r.stdout
    .toString()
    .split("\n")
    .filter(x => x.trim())
    .map(x => JSON.parse(x) as { type?: string; frame?: { result?: Record<string, unknown> } });
  const run = frames.find(f => f.type === "run");
  const out = frames.find(f => f.type === "stdout");
  if (run === undefined || out === undefined) return null;
  const res = (run.frame?.result ?? {}) as Record<string, unknown>;
  const outRes = (out.frame?.result ?? {}) as Record<string, unknown>;
  return {
    status: String(res.status ?? ""),
    returnValue: res.return_value as number | undefined,
    trapCode: res.trap_code === undefined ? "" : String(res.trap_code),
    steps: res.steps_executed as number,
    stdout: Buffer.from(String(outRes.delta ?? ""), "latin1"),
  };
}

/// 递归 .c 计数（emitgate 同口径——内置 String 分隔符域本目录集 ASCII 安全）
function countCFiles(dir: string): number {
  let n = 0;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.isDirectory()) n += countCFiles(path.join(dir, e.name));
    else if (e.name.endsWith(".c")) n++;
  }
  return n;
}

interface Bucket {
  ok: number; // dispatch 组装成功（批 4′ 起含 host 回接例——对拍例全集）
  callhost_stdin: number; // Stdin 族禁译（waiting_input——wasm 无 ip 回退）
  callhost_vfs: number; // VFS 文件族禁译（FILE* 句柄态）
  callhost_callback: number; // qsort/bsearch 回调族（CallPtr 双禁）
  callhost_va: number; // va_list 游标族
  callhost_other: number; // Observe/未知路由/侧车错配/窗口溢出等——>0 须归因
  badreturn: number; // 块图多前驱会合分歧（短路×host 组合形态——批 4″ 收口登记）
  unsupported: number; // 变参用户函数/CallPtr/jump-to-dead 静态不可展开
  other: number; // 其余组装红（BadReturnPoint 等——若 >0 须归因新增桶）
  compile: number; // 编译期失败（codegen_diff 域）
}

function classify(disp: DispatchSeg): keyof Bucket {
  if (disp.ok) return "ok";
  const r = disp.reason ?? "";
  if (r.includes("callhost-Stdin")) return "callhost_stdin";
  if (r.includes("callhost-Vfs")) return "callhost_vfs";
  if (r.includes("callhost-Callback")) return "callhost_callback";
  if (r.includes("callhost-VaList")) return "callhost_va";
  if (r.includes("callhost-")) return "callhost_other";
  if (r.startsWith("dispatch-bad-return-point")) return "badreturn";
  if (r.startsWith("dispatch-not-supported")) return "unsupported";
  return "other";
}

function loadBaseline(): Record<string, Record<string, number>> {
  const p = path.join(scriptDir, "baseline.json");
  if (!fs.existsSync(p)) return {};
  return JSON.parse(fs.readFileSync(p, "utf8")) as Record<string, Record<string, number>>;
}

async function main(): Promise<number> {
  // argv 三段式防护（emitgate 同款：裸旗 → 剥旗取位置参 → 空集 fail loud）
  const argv = process.argv.slice(2);
  if (argv.length > 0 && argv[argv.length - 1] === "--dir") {
    console.error("--dir 尾置缺值（须跟目录路径）");
    return 1;
  }
  const dirs = argv.filter(a => a !== "--dir");
  if (dirs.some(d => d.startsWith("-"))) {
    console.error(`未知旗标：${dirs.find(d => d.startsWith("-"))}`);
    return 1;
  }
  const targets = dirs.length > 0 ? dirs : CORPUS_DIRS.map(d => `corpus/${d}`);
  if (targets.length === 0) {
    console.error("目录集为空（不给 0 例全绿）");
    return 1;
  }
  // 产物链（dump_wasm 含 dispatch 出口——vm 依赖链）
  const exe = path.join(root, "moonbit/_build/native/debug/build/cmd/dump_wasm/dump_wasm.exe");
  ensureFresh("dispatchdiff", exe, ["build", "--target", "native", "cmd/dump_wasm"]);
  const wasmtimeExe = path.join(
    root,
    "scripts/wasmtime_arm/rs/target/release/wasmtime_arm.exe",
  );
  if (!fs.existsSync(wasmtimeExe)) {
    console.error(`wasmtime 跑器缺失：${wasmtimeExe}（cd scripts/wasmtime_arm/rs && cargo build --release --locked）`);
    return 1;
  }
  const perDir: Record<string, Bucket> = {};
  const pairCases: Array<{ file: string; rel: string; disp: DispatchSeg }> = [];
  for (const dir of targets) {
    const label = path.basename(dir);
    const disk = countCFiles(dir);
    const r = spawnSync(exe, [dir], { cwd: root, maxBuffer: 256 << 20, timeout: 600000 });
    if (r.status !== 0) {
      console.error(`${label}: dump_wasm rc=${r.status}`);
      return 1;
    }
    const lines = r.stdout.toString().split("\n").filter(x => x.trim());
    if (lines.length !== disk) {
      console.error(`${label}: 磁盘 ${disk} .c ≠ dump ${lines.length} 行（扫描面退化）`);
      return 1;
    }
    const b: Bucket = { ok: 0, callhost_stdin: 0, callhost_vfs: 0, callhost_callback: 0, callhost_va: 0, callhost_other: 0, badreturn: 0, unsupported: 0, other: 0, compile: 0 };
    for (const line of lines) {
      const d = JSON.parse(line) as { file: string; ok: boolean; stage?: string; dispatch?: DispatchSeg };
      // PR #526 审阅 P3：compile 桶只收编译期失败（lex/parse/type/gen）；
      // emit/verify/assemble 失败已由 ok:false 整行红化，不混入 codegen_diff 域
      if (!d.ok) {
        if (d.stage !== undefined && ["lex", "parse", "type", "gen"].includes(d.stage)) {
          b.compile++;
        } else {
          // 产物形态破损（dump 旧版行等）——按 other 计（fail loud 面）
          b.other++;
        }
        continue;
      }
      const disp = d.dispatch ?? { ok: false, reason: "dispatch 段缺失（dump_wasm 产物形态破损）" };
      const k = classify(disp);
      b[k]++;
      // 批 4′：ok 例全收（host_calls>0 走中继回接；wasmtime 臂回接随批 4″，
      // 该面例记 pending 桶——三方对拍降 V8×引擎双方 + 登记）
      if (k === "ok") {
        pairCases.push({ file: d.file, rel: path.join(dir, d.file).replaceAll("\\", "/"), disp });
      }
    }
    perDir[label] = b;
  }
  // 三方对拍（V8 进程内逐例 + host 中继回接；wasmtime 批模式一次 spawn——
  // 批 4′ 起 host_calls>0 例 wasmtime 臂未回接〔Rust 侧同步胶水归批 4″〕，
  // 该面例三方降 V8×引擎双方对拍、wtPending 计数登记不静默）
  const zeroHost = pairCases.filter(c => (c.disp.host_calls ?? 0) === 0);
  const hostCases = pairCases.filter(c => (c.disp.host_calls ?? 0) > 0);
  const wtCases = path.join(root, "tmp_dispatchdiff_cases.tsv");
  const wtOut = path.join(root, "tmp_dispatchdiff_out.tsv");
  fs.writeFileSync(
    wtCases,
    zeroHost
      .map(c => `${c.disp.module} ${c.disp.data} ${c.disp.base} ${c.disp.max_steps}`)
      .join("\n") + "\n",
    "utf8",
  );
  let wtLines: string[] = [];
  if (zeroHost.length > 0) {
    const wtRun = spawnSync(wasmtimeExe, ["dispatch", wtCases, wtOut], { cwd: root, timeout: 300000, maxBuffer: 64 << 20 });
    fs.rmSync(wtCases, { force: true });
    if (wtRun.status !== 0) {
      console.error(`wasmtime dispatch 批跑 rc=${wtRun.status}: ${wtRun.stderr?.toString().slice(0, 400)}`);
      return 1;
    }
    wtLines = fs.readFileSync(wtOut, "utf8").split("\n").filter(x => x.trim());
    fs.rmSync(wtOut, { force: true });
    if (wtLines.length !== zeroHost.length) {
      console.error(`wasmtime 出口行数 ${wtLines.length} ≠ 零 host 对拍例 ${zeroHost.length}（批协议破裂）`);
      return 1;
    }
  }
  const wtOf = new Map<number, string>();
  for (let i = 0; i < zeroHost.length; i++) {
    wtOf.set(pairCases.indexOf(zeroHost[i]!), wtLines[i]!);
  }
  // host 中继进程（批 4′——每例 INIT 幂等重建：VM 状态/堆/值栈不跨例污染）
  const relayJs = path.join(root, "moonbit/_build/js/release/build/cmd/host_relay/host_relay.js");
  if (hostCases.length > 0 && !fs.existsSync(relayJs)) {
    console.error(`host 中继产物缺失：${relayJs}（moonbit/ 下 moon build --release --target js cmd/host_relay）`);
    return 1;
  }
  const relay = hostCases.length > 0 ? new HostRelayProc(relayJs) : undefined;
  // 对拍例红与基线桶红**分账**（PR #526 审阅 P2-2：paired = 对拍一致例数，
  // 曾把基线桶红计入致 coverage.paired 少报——审阅实验「抬 baseline.ok 9→10
  // 跑一次 paired=21 实际 22 例全过」实锤）
  let red = 0;
  let pairRed = 0;
  for (let i = 0; i < pairCases.length; i++) {
    const c = pairCases[i]!;
    const isHostCase = (c.disp.host_calls ?? 0) > 0;
    const v8 = v8Arm(c.disp, isHostCase ? relay : undefined);
    if (v8 === null) {
      console.error(`RED ${c.file}: V8 编译失败（dispatch 产物非法 wasm——组装器缺陷面）`);
      red++;
      pairRed++;
      continue;
    }
    const wtLine = wtOf.get(i);
    const wtOrNull: RuntimeArmResult | null = isHostCase
      ? { kind: "ok", steps: -1, note: "wasmtime-host-pending（批 4″ 回接——三方降双方）" }
      : parseWasmtimeLine(wtLine ?? "");
    if (!isHostCase && wtOrNull === null) {
      console.error(`RED ${c.file}: wasmtime 出口行不可解析：${wtLine}`);
      red++;
      pairRed++;
      continue;
    }
    // 收窄依据：isHostCase 分支构造必非 null；非 host 分支上方已 continue 拦 null。
    const wt: RuntimeArmResult = wtOrNull!;
    if (!isHostCase && wt.badCompile !== undefined) {
      console.error(`RED ${c.file}: wasmtime 编译失败（dispatch 产物非法 wasm）：${wt.badCompile.slice(0, 120)}`);
      red++;
      pairRed++;
      continue;
    }
    const eng = engineArm(c.rel);
    if (eng === null) {
      console.error(`RED ${c.file}: 引擎臂失败（超时/帧形态）`);
      red++;
      pairRed++;
      continue;
    }
    const verdict = judgeCaseHost(c.file, v8, wt, eng, isHostCase);
    if (verdict !== null) {
      console.error(`RED ${verdict}`);
      red++;
      pairRed++;
    }
  }
  relay?.dispose();
  // 基线对账（桶下限——下跌即红；增长不红）+ coverage 落盘
  const baseline = loadBaseline();
  const BUCKET_KEYS = ["ok", "callhost_stdin", "callhost_vfs", "callhost_callback", "callhost_va", "callhost_other", "badreturn", "unsupported", "other"] as const;
  for (const [label, b] of Object.entries(perDir)) {
    const base = baseline[label];
    if (base === undefined) {
      // PR #526 审阅 P3：默认全量目录集下无基线 = fail-open（新目录不设
      // 下限即无守护）——红化登记义务；--dir 显式传入的调试目录豁免
      if (dirs.length === 0) {
        console.error(`RED ${label}: 无基线条目（默认目录集新目录须连坐 baseline.json——fail-open 防线）`);
        red++;
      }
      continue;
    }
    for (const k of BUCKET_KEYS) {
      if (base[k] !== undefined && b[k] < base[k]) {
        console.error(`RED ${label}: 桶 ${k} ${b[k]} < 基线 ${base[k]}（覆盖面退化或桶迁移未连坐 baseline）`);
        red++;
      }
    }
    if (base.compile !== undefined && b.compile > base.compile) {
      console.error(`RED ${label}: 编译失败例 ${b.compile} > 基线 ${base.compile}（负例语料异常增长）`);
      red++;
    }
  }
  const totals: Record<string, number> = { ok: 0, callhost_stdin: 0, callhost_vfs: 0, callhost_callback: 0, callhost_va: 0, callhost_other: 0, badreturn: 0, unsupported: 0, other: 0, compile: 0, dirs: targets.length, wt_pending: hostCases.length };
  for (const b of Object.values(perDir)) {
    for (const k of BUCKET_KEYS) {
      totals[k] = (totals[k] ?? 0) + b[k];
    }
    totals.compile = (totals.compile ?? 0) + b.compile;
  }
  // coverage.json 只在全量默认目录集跑时落盘（facts 采集面 = 九目录全集）；
  // --dir 部分跑覆盖全量 coverage 会污染禁译覆盖率真值（批 4b-3 实锤：
  // 2 目录调试跑把 dualrun=22 覆写成 1）
  if (dirs.length === 0) {
    fs.writeFileSync(
      path.join(scriptDir, "coverage.json"),
      JSON.stringify(
        { as_of: new Date().toISOString().slice(0, 10), per_dir: perDir, totals, paired: pairCases.length - pairRed, red },
        null,
        2,
      ) + "\n",
      "utf8",
    );
  }
  console.log(
    `dispatchdiff: ${targets.length} 目录 = 对拍 ${pairCases.length} 例（红 ${red}）｜禁译 callhost=${totals.callhost} unsupported=${totals.unsupported} other=${totals.other}｜编译期 ${totals.compile}`,
  );
  return red === 0 ? 0 : 1;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  process.exit(await main());
}
