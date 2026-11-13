// wasmenc_rundiff —— REHOST 批 2b 双跑对拍闸（设计单 §3.3「迁移期新旧
// 载体并存的对拍形态」：同一语料 legacy 装载 vs wasm 载体往返装载
// 〔--wasm-rehost：发射→折叠→恒等断言→重建 code 驱动〕双跑 digest
// 逐位对拍——stdout 逐字节 + rc + 1MB 映像（--dump-memory）+ 装载状态
// 标记行断言）。
//
// 判定（PR #505 审阅 P2-1 同款 fail-open 防护）：
//   1. rehost 臂 stderr 须含 `// WASM-REHOST ok`——**fallback 即红**
//      （装载失败静默回退会让双臂 digest 恒一致而闸失明——标记行是
//      「真的走了 wasm 装载」的证明，vm 侧 fail loud 的归口在此）；
//   2. 双臂 stdout 逐字节 + rc 一致；编译失败例（COMPILE-ERROR 两臂
//      同形——编译期不是本闸域，codegen_diff 既有防线管）不红；
//   3. 每目录磁盘 .c 递归计数 == 双跑例数（扫描面退化即红）；
//   4. ok 基线钉住（baseline.json 下限——增长不红）；
//   5. --dir 裸旗/空目录集 fail loud。
//
// 用法：node scripts/wasmenc_rundiff/main.mts [--dir corpus/baseline ...]
//（无参 = 全目录集；CI 每轮全量，九目录基线 ~1 分钟）。
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { ensureFresh } from "../internal/freshness.mts";
import { projectRoot } from "../internal/capi.mts";
import { CORPUS_DIRS } from "../wasmenc_emitgate/main.mts";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));

/// 单例双跑结果
export interface ArmResult {
  status: number | null;
  stdout: Buffer;
  stderr: string;
  /// --dump-memory 映像（读回字节；臂失败/未写 = null）
  mem: Buffer | null;
}

/// 判定一例双跑 → null（绿）或红描述（纯函数——node:test 消费）
export function judgeCase(
  file: string,
  leg: ArmResult,
  reh: ArmResult,
): string | null {
  if (leg.status === null || reh.status === null) {
    return `${file}: 超时（30s/例——长跑语料须单独登记）`;
  }
  const mark = reh.stderr.match(/^\/\/ WASM-REHOST (\S+)/m);
  if (mark === null) {
    // 无标记 = 未到 run 帧：编译失败例（两臂同形）不红，否则红
    if (leg.stderr.includes("COMPILE-ERROR") && reh.stderr.includes("COMPILE-ERROR")
      && leg.stdout.equals(reh.stdout) && leg.status === reh.status) {
      return null;
    }
    return `${file}: rehost 臂缺 WASM-REHOST 标记行（非编译失败例）——装载链断裂`;
  }
  if (mark[1] !== "ok") {
    return `${file}: 装载回退（${reh.stderr.match(/^\/\/ WASM-REHOST (.+)$/m)?.[1] ?? "?"}）——fail loud 面`;
  }
  if (leg.status !== reh.status) {
    return `${file}: rc 不一致 legacy=${leg.status} rehost=${reh.status}`;
  }
  if (!leg.stdout.equals(reh.stdout)) {
    return `${file}: stdout 不一致（${leg.stdout.length} vs ${reh.stdout.length} 字节）`;
  }
  // 程序 stderr 对比（P3-6：剥装载标记行后逐字节——文本模式 `// STDERR`
  // 行落 CLI stderr，两臂分叉此前不可见）
  if (!stripRehostMark(leg.stderr).equals(stripRehostMark(reh.stderr))) {
    return `${file}: 程序 stderr 不一致（剥 WASM-REHOST 行后比对）`;
  }
  if (leg.mem === null || reh.mem === null || !leg.mem.equals(reh.mem)) {
    return `${file}: 1MB 映像不一致（dump-memory 对拍）`;
  }
  return null;
}

/// 剥装载标记行（`// WASM-REHOST …`——CLI 层通道，两臂合法差异面；
/// 其余 stderr（程序 STDERR 行/TRAP 行）逐字节保留参与比对）
export function stripRehostMark(stderr: string): Buffer {
  const kept = stderr.split("\n").filter((l) => !l.startsWith("// WASM-REHOST "));
  return Buffer.from(kept.join("\n"), "latin1");
}

/// 递归数目录下 .c 条数（与 emitgate countCFiles 同口径）
export function countCFiles(dir: string): number {
  let n = 0;
  for (const name of fs.readdirSync(dir)) {
    const full = path.join(dir, name);
    if (fs.statSync(full).isDirectory()) {
      n += countCFiles(full);
    } else if (name.endsWith(".c")) {
      n += 1;
    }
  }
  return n;
}

/// 单臂跑（--dump-memory 落 tmp 后读回删除；30s 超时）
function runArm(exe: string, args: string[], tag: string): ArmResult {
  const memPath = path.join(os.tmpdir(), `vitro_rundiff_${tag}_${process.pid}.bin`);
  const r = spawnSync(exe, [...args, "--dump-memory", memPath], {
    encoding: "buffer",
    timeout: 30000,
    maxBuffer: 64 * 1024 * 1024,
  });
  let mem: Buffer | null = null;
  try {
    mem = fs.readFileSync(memPath);
  } catch {
    mem = null;
  }
  try {
    fs.unlinkSync(memPath);
  } catch {
    /* 竞态自愈面——tmp 文件残留无害 */
  }
  return {
    status: r.status,
    stdout: r.stdout ?? Buffer.alloc(0),
    stderr: (r.stderr ?? Buffer.alloc(0)).toString("latin1"),
    mem,
  };
}

/// 基线钉住（emitgate baseline.json 同款形态——ok 数下跌即红）
interface Baseline {
  [dir: string]: number;
}

export async function main(): Promise<number> {
  const root = projectRoot();
  const rawArgv = process.argv.slice(2);
  if (rawArgv[rawArgv.length - 1] === "--dir") {
    console.error("--dir 后缺目录参数——fail loud");
    return 1;
  }
  const argv = rawArgv.filter((a) => a !== "--dir");
  const corpusDirs = argv.length > 0 ? argv : [...CORPUS_DIRS];
  if (corpusDirs.length === 0) {
    console.error("目录集为空——fail loud，不给 0 例全绿");
    return 1;
  }
  const baseline = JSON.parse(fs.readFileSync(path.join(scriptDir, "baseline.json"), "utf8")) as Baseline;
  const exe = path.join(root, "moonbit", "_build", "native", "debug", "build", "cmd", "run", "run.exe");
  ensureFresh("rundiff", exe, ["build", "--target", "native", "cmd/run"]);
  const totalReds: string[] = [];
  let totalOk = 0;
  let totalCompile = 0;
  for (const d of corpusDirs) {
    const corpusDir = path.join(root, "corpus", d);
    if (!fs.existsSync(corpusDir)) {
      console.error(`语料目录不存在：${d}`);
      return 1;
    }
    const files: string[] = [];
    (function walk(dir: string): void {
      for (const name of fs.readdirSync(dir)) {
        const full = path.join(dir, name);
        if (fs.statSync(full).isDirectory()) {
          walk(full);
        } else if (name.endsWith(".c")) {
          files.push(full);
        }
      }
    })(corpusDir);
    // 条数对账（P2-1 同款）：磁盘 .c 数 vs 双跑例数
    const diskN = countCFiles(corpusDir);
    if (diskN !== files.length) {
      totalReds.push(`${d}: 条数对账红（递归计数 ${diskN} vs 收集 ${files.length}）`);
    }
    let okN = 0;
    let compileFail = 0;
    const reds: string[] = [];
    for (const f of files) {
      const leg = runArm(exe, [f], "leg");
      const reh = runArm(exe, ["--wasm-rehost", f], "reh");
      const red = judgeCase(path.relative(root, f), leg, reh);
      if (red !== null) {
        reds.push(red);
        continue;
      }
      if (leg.stderr.includes("COMPILE-ERROR") && reh.stderr.includes("COMPILE-ERROR")) {
        compileFail += 1;
      } else {
        okN += 1;
      }
    }
    totalOk += okN;
    totalCompile += compileFail;
    totalReds.push(...reds);
    const floorOk = baseline[d];
    if (floorOk !== undefined && okN < floorOk) {
      totalReds.push(`${d}: ok 基线红（${okN} < 基线 ${floorOk}）——双跑一致面退化`);
    }
    console.log(`${d.padEnd(20)} ${String(files.length).padStart(4)} 例：双跑一致 ${okN}（基线 ${floorOk ?? "-"}）/ 编译期 ${compileFail}（既有防线域）/ 红 ${reds.length}`);
    for (const red of reds.slice(0, 5)) console.log(`  RED ${red}`);
  }
  console.log(`wasmenc_rundiff: 双跑一致 ${totalOk} / 编译期 ${totalCompile} / 红 ${totalReds.length}（legacy vs --wasm-rehost：stdout+rc+1MB 映像+装载标记）`);
  return totalReds.length === 0 ? 0 : 1;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  process.exit(await main());
}
