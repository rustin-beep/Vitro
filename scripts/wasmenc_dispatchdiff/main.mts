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
  reason?: string;
}

/// V8 / wasmtime 臂统一结果形态（wasmtime 出口行解析同形）
export interface RuntimeArmResult {
  /// "ok"（main 返回，rc 携值）| "trap"（RuntimeError/trap 行）| "host"（桩被调）
  kind: "ok" | "trap" | "host";
  rc?: number;
  steps: number;
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
  // ② trap/预算形态：三方「终态类别」一致（trap↔trap；预算例引擎 trap_code=E3091、
  //    V8/wasmtime main()==-1 是「ok -1」形态——按 (trap || rc===-1) 归一）
  const isTrapV8 = v8.kind === "trap" || (v8.kind === "ok" && v8.rc === -1);
  const isTrapWt = wt.kind === "trap" || (wt.kind === "ok" && wt.rc === -1);
  const isTrapEng = eng.status === "trap";
  if (isTrapV8 || isTrapWt || isTrapEng) {
    // 三方须同类别（全部 trap/预算 归一态）
    if (!(isTrapV8 && isTrapWt && isTrapEng)) {
      return `${file}: 终态类别分叉 v8=${v8.kind}${v8.rc ?? ""} wt=${wt.kind}${wt.rc ?? ""} eng=${eng.status}${eng.trapCode ?? ""}`;
    }
    // trap 例：stdout 仍断言（教学 trap 无输出）；steps 豁免（overshoot ≤1 块）
    if (eng.stdout.length !== 0) {
      return `${file}: trap 例引擎 stdout 非空（${eng.stdout.length}B）`;
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
  if (eng.stdout.length !== 0) {
    return `${file}: 零 host 例引擎 stdout 非空（${eng.stdout.length}B）`;
  }
  return null;
}

/// wasmtime 出口行（`ok <rc> <steps>` / `trap <steps> <msg..>` / `host <steps>`）
/// → RuntimeArmResult（纯函数——node:test 消费）
export function parseWasmtimeLine(line: string): RuntimeArmResult | null {
  const sp = line.indexOf(" ");
  if (sp < 0) return null;
  const kind = line.slice(0, sp);
  const rest = line.slice(sp + 1);
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

/// V8 臂：进程内实例化 + data 铺设 + main()（host 桩被调即 kind=host）
export function v8Arm(disp: DispatchSeg): RuntimeArmResult | null {
  let inst: WebAssembly.Instance;
  let hostUsed = 0;
  try {
    const mod = new WebAssembly.Module(Buffer.from(disp.module ?? "", "hex"));
    inst = new WebAssembly.Instance(mod, {
      env: {
        vitro_host_call: () => {
          hostUsed++;
          return 0n;
        },
      },
    });
  } catch {
    return null; // 编译失败——上层按「产物非法」红
  }
  const data = Buffer.from(disp.data ?? "", "hex");
  const mem = inst.exports.memory as WebAssembly.Memory;
  new Uint8Array(mem.buffer, disp.base ?? 0, data.length).set(data);
  let rc: number | undefined;
  let trapped = false;
  try {
    rc = (inst.exports.main as () => number)();
  } catch {
    trapped = true;
  }
  const steps = Number((inst.exports.steps as WebAssembly.Global).value);
  if (hostUsed > 0) return { kind: "host", steps };
  if (trapped) return { kind: "trap", steps };
  return { kind: "ok", rc, steps };
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
  ok: number; // dispatch 组装成功（零 host 对拍例）
  callhost: number; // H2 宿主回接批域
  unsupported: number; // 变参/wide-param/CallPtr/jump-to-dead 静态不可展开
  other: number; // 其余组装红（BadReturnPoint 等——若 >0 须归因新增桶）
  compile: number; // 编译期失败（codegen_diff 域）
}

function classify(disp: DispatchSeg): keyof Bucket {
  if (disp.ok) return "ok";
  const r = disp.reason ?? "";
  if (r.includes("callhost")) return "callhost";
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
    const b: Bucket = { ok: 0, callhost: 0, unsupported: 0, other: 0, compile: 0 };
    for (const line of lines) {
      const d = JSON.parse(line) as { file: string; ok: boolean; dispatch?: DispatchSeg };
      if (!d.ok) {
        b.compile++;
        continue;
      }
      const disp = d.dispatch ?? { ok: false, reason: "dispatch 段缺失（dump_wasm 产物形态破损）" };
      const k = classify(disp);
      b[k]++;
      if (k === "ok" && (disp.host_calls ?? 1) === 0) {
        pairCases.push({ file: d.file, rel: path.join(dir, d.file).replaceAll("\\", "/"), disp });
      }
    }
    perDir[label] = b;
  }
  // 三方对拍（V8 进程内逐例；wasmtime 批模式一次 spawn；引擎逐例 --json）
  const wtCases = path.join(root, "tmp_dispatchdiff_cases.tsv");
  const wtOut = path.join(root, "tmp_dispatchdiff_out.tsv");
  fs.writeFileSync(
    wtCases,
    pairCases
      .map(c => `${c.disp.module} ${c.disp.data} ${c.disp.base} ${c.disp.max_steps}`)
      .join("\n") + "\n",
    "utf8",
  );
  const wtRun = spawnSync(wasmtimeExe, ["dispatch", wtCases, wtOut], { cwd: root, timeout: 300000, maxBuffer: 64 << 20 });
  fs.rmSync(wtCases, { force: true });
  if (wtRun.status !== 0) {
    console.error(`wasmtime dispatch 批跑 rc=${wtRun.status}: ${wtRun.stderr?.toString().slice(0, 400)}`);
    return 1;
  }
  const wtLines = fs.readFileSync(wtOut, "utf8").split("\n").filter(x => x.trim());
  fs.rmSync(wtOut, { force: true });
  if (wtLines.length !== pairCases.length) {
    console.error(`wasmtime 出口行数 ${wtLines.length} ≠ 对拍例 ${pairCases.length}（批协议破裂）`);
    return 1;
  }
  let red = 0;
  for (let i = 0; i < pairCases.length; i++) {
    const c = pairCases[i]!;
    const v8 = v8Arm(c.disp);
    if (v8 === null) {
      console.error(`RED ${c.file}: V8 编译失败（dispatch 产物非法 wasm——组装器缺陷面）`);
      red++;
      continue;
    }
    const wt = parseWasmtimeLine(wtLines[i]!);
    if (wt === null) {
      console.error(`RED ${c.file}: wasmtime 出口行不可解析：${wtLines[i]}`);
      red++;
      continue;
    }
    const eng = engineArm(c.rel);
    if (eng === null) {
      console.error(`RED ${c.file}: 引擎臂失败（超时/帧形态）`);
      red++;
      continue;
    }
    const verdict = judgeCase(c.file, v8, wt, eng);
    if (verdict !== null) {
      console.error(`RED ${verdict}`);
      red++;
    }
  }
  // 基线对账（桶下限——下跌即红；增长不红）+ coverage 落盘
  const baseline = loadBaseline();
  for (const [label, b] of Object.entries(perDir)) {
    const base = baseline[label];
    if (base === undefined) continue;
    for (const k of ["ok", "callhost", "unsupported", "other"] as const) {
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
  const totals = { ok: 0, callhost: 0, unsupported: 0, other: 0, compile: 0, dirs: targets.length };
  for (const b of Object.values(perDir)) {
    for (const k of ["ok", "callhost", "unsupported", "other", "compile"] as const) {
      totals[k] += b[k];
    }
  }
  // coverage.json 只在全量默认目录集跑时落盘（facts 采集面 = 九目录全集）；
  // --dir 部分跑覆盖全量 coverage 会污染禁译覆盖率真值（批 4b-3 实锤：
  // 2 目录调试跑把 dualrun=22 覆写成 1）
  if (dirs.length === 0) {
    fs.writeFileSync(
      path.join(scriptDir, "coverage.json"),
      JSON.stringify(
        { as_of: new Date().toISOString().slice(0, 10), per_dir: perDir, totals, paired: pairCases.length - red, red },
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
