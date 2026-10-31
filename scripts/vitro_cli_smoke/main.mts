#!/usr/bin/env node
// vitro_cli_smoke —— 统一 CLI 入口（三臂壳 + launcher）的判定型闸
// （Go→.mts 重写，refs #273；原 main.go 617 行，#49 批一/批二）。
//
// 断言三组：
//
//	A. 壳四子命令 rc 契约（CLI_PROTOCOL_V1 五值表的壳侧覆盖面）；
//	B. **三臂同形对拍**——launcher 默认臂（wasm 壳）vs native exe vs js 臂跑同一
//	   用例，**语义层** = stdout/stderr CRLF 归一后逐行一致（三臂消费同一
//	   gateway/引擎语义：note 通道 UTF-8、trap 文本同源、标记行协议同构，
//	   任何一臂漂移即红——唯一允许差异 = backend 标注行）。**字节层** =
//	   附 6 锚（#315/#316，2026-10-26）：三臂 stdout **原始字节逐位比较、
//	   零归一**——CRLF/编码/二进制保真的壳层漂移在此可见（语义层的
//	   normalize 不吸收本锚判定的任何差异）。
//	C. launcher 语义：backend 标注行（stderr）+ --backend 覆盖转发。
//
// --corpus N：B 组语料级扩面（#49 批二）——corpus/baseline 按稳定序取前 N
// 例三臂对拍（wasm+js+native 同判定口径；js 臂连坐 2026-10-15）。缺省
// 0 = 只跑内置三 fixture；CI 接 30 例。
//
// 前置：moonbit/_build 四产物在位（wasm-gc release gateway + native release
// cmd/vitro + js release cmd/vitro_js + cmd/vitro_wasm）——CI 步骤先建；
// 缺产物即红（fail loud）。
//
// 迁移口径（#292 批）：
//   - stdout/stderr/退出码与 Go 版逐字对齐（默认模式 + `--corpus 2` 两模式进
//     parity 闸；本闸**依赖四臂产物**，故注册为 parity 的 artifact 组，只在
//     构建过产物的 job 里跑，见 parity_gate 的 requires）；
//   - node 定位：Go 走 `exec.LookPath("node")`；本进程**自身就是 node**，直接
//     用 process.execPath + process.versions（同源、免 PATH 抖动）。差异面仅在
//     「node 不在 PATH」这一分支（Go 会红，本版不会）；
//   - 子进程输出按 utf8 解码（Go 侧 []byte→string 零拷贝保字节）；本闸比对面
//     全为文本输出，不涉非法 UTF-8 字节；
//   - 失败路径的诊断文案（spawn 失败 / D 组执行异常）按 .mts 习惯重写。
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { byteSort } from "../internal/text.mts";

let repoRoot = ".";
let failures = 0;

/** Go `fatalf`：FAIL 行走 **stdout**（与既有 CI 日志抓取口径一致），累计计数。 */
function fatalf(msg: string): void {
  process.stdout.write("FAIL: " + msg + "\n");
  failures++;
}

function normalize(s: string): string {
  return s.split("\r\n").join("\n");
}

/**
 * 剥 `[vitro] backend=…` 标注行——B 组**语义层**对拍的唯一允许差异
 * （#322 补登 2026-10-28：该行已是协议面第十种「壳层标注行」——壳层
 * 三臂不对称是设计：仅 wasm 壳打（浏览器直调无 launcher 需判臂），js/
 * native 壳不打、launcher 层恒打；对拍两侧一有一无，故剥后比。其余任何
 * 行差异都红）。注：本函数作用于归一后文本；字节层（附 6 锚）比 stdout
 * 原始字节，不经此函数（#316）。
 */
export function stripBackendLine(s: string): string {
  const kept: string[] = [];
  for (const ln of s.split("\n")) {
    if (ln.startsWith("[vitro] backend=")) continue;
    kept.push(ln);
  }
  return kept.join("\n");
}

/** 两 buffer 首个差异偏移（等长前提；映像对拍诊断用）。 */
export function firstDiff(a: Buffer, b: Buffer): number {
  const n = Math.min(a.length, b.length);
  for (let i = 0; i < n; i++) if (a[i] !== b[i]) return i;
  return n;
}

const bufStr = (b: Buffer | null | undefined): string => (b === null || b === undefined ? "" : b.toString("utf8"));

/** Go `%v` 对 []string 的形态（诊断文案用）。 */
const goList = (argv: readonly string[]): string => `[${argv.join(" ")}]`;

export interface RunOut {
  /** stdout + "\n--stderr--\n" + stderr（CRLF 归一） */
  out: string;
  rc: number;
}

/** 执行并返回 (stdout+stderr 归一, rc)。缺产物/启动失败 = fail loud。 */
export function runOut(exe: string, argv: readonly string[], stdin?: string): RunOut {
  const r = spawnSync(exe, argv, {
    cwd: repoRoot,
    maxBuffer: 64 * 1024 * 1024,
    input: stdin,
  });
  if (r.error !== undefined) {
    fatalf(`启动失败 ${exe} ${goList(argv)}: ${r.error.message}`);
    return { out: "", rc: -1 };
  }
  const rc = r.status ?? -1;
  return { out: normalize(bufStr(r.stdout) + "\n--stderr--\n" + bufStr(r.stderr)), rc };
}

export interface RunSplit {
  out: string;
  err: string;
  rc: number;
}

/** 分离捕获 (stdout, stderr, rc)——通道归属断言用（#215 不变式的机判）。 */
export function runSplit(exe: string, argv: readonly string[]): RunSplit {
  const r = spawnSync(exe, argv, { cwd: repoRoot, maxBuffer: 64 * 1024 * 1024 });
  if (r.error !== undefined) fatalf(`启动失败 ${exe} ${goList(argv)}: ${r.error.message}`);
  return { out: bufStr(r.stdout), err: bufStr(r.stderr), rc: r.status ?? -1 };
}

/** 按字节截断（Go 侧 `s[:n]` 是字节切片；避免 UTF-16 code unit 口径漂移）。 */
const headBytes = (s: string, n: number): string => Buffer.from(s, "utf8").subarray(0, n).toString("utf8");

const toSlash = (p: string): string => p.split(path.sep).join("/");

const NODE_BIN = process.execPath;

export function runMain(argv: readonly string[]): number {
  let corpusN = 0;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i] ?? "";
    if (a === "-corpus" || a === "--corpus") {
      const v = argv[i + 1];
      if (v === undefined) {
        process.stdout.write("flag needs an argument: -corpus\n");
        return 2;
      }
      corpusN = Number.parseInt(v, 10);
      if (!Number.isFinite(corpusN)) {
        process.stdout.write(`invalid value ${JSON.stringify(v)} for flag -corpus\n`);
        return 2;
      }
      i++;
      continue;
    }
    process.stdout.write(`flag provided but not defined: ${a}\n`);
    return 2;
  }
  // cwd = 仓库根（防线惯例——vm_diff 等同款相对路径约定）
  repoRoot = ".";

  // main.js 退役批（2026-10-16）：wasm 臂被测物 = cmd/vitro_wasm js 产物
  const shell = path.join(repoRoot, "moonbit", "_build", "js", "release", "build", "cmd", "vitro_wasm", "vitro_wasm.js");
  const nativeExe = path.join(repoRoot, "moonbit", "_build", "native", "release", "build", "cmd", "vitro", "vitro.exe");
  const serveExe = path.join(repoRoot, "moonbit", "_build", "native", "release", "build", "cmd", "serve", "serve.exe");
  const wasmMod = path.join(repoRoot, "moonbit", "_build", "wasm-gc", "release", "build", "gateway", "wasm", "wasm.wasm");
  const jsEntry = path.join(repoRoot, "moonbit", "_build", "js", "release", "build", "cmd", "vitro_js", "vitro_js.js");
  const wasmGlue = shell;
  for (const p of [wasmGlue, nativeExe, wasmMod, jsEntry, serveExe]) {
    if (!fs.existsSync(p)) {
      process.stdout.write(
        `vitro_cli_smoke: 前置产物缺失 ${p}（先构建：moon build --release --target wasm-gc gateway/wasm + MOON_CC=clang moon build --release --target native cmd/vitro + cmd/serve + moon build --release --target js cmd/vitro_js + moon build --release --target js cmd/vitro_wasm）\n`,
      );
      return 1;
    }
  }
  const nodeBin = NODE_BIN;
  // node 版本前置闸（P2，2026-10-15 用户审阅提醒；2026-10-17 审阅处置批勘正文案）：
  // vitro_wasm 的 MIN_NODE=22（f49794f6 降 LTS 批——原 25）以下 wasm 壳恒退 rc=5
  // 哨兵（#106）——不前置拦截会把宿主版本不足误报成整片「输出不一致」（node 22 下
  // 92 条误导红的实录），真因被埋。版本不足即红，不静默跳过（fail loud）。
  {
    const v = process.versions.node;
    const major = Number.parseInt(v.split(".")[0] ?? "", 10);
    if (Number.isFinite(major) && major < 22) {
      process.stdout.write(
        `vitro_cli_smoke: 宿主 node ${v} < 22（wasm 臂 js-string builtins 需要——vitro_wasm MIN_NODE=22 同源门槛，f49794f6 降 LTS 批同步）。\n` +
          "wasm 臂将恒退 rc=5 降级哨兵，后续对拍会整片误报「输出不一致」。先升级 node ≥ 22 再跑本闸。\n",
      );
      return 1;
    }
  }

  // fixture：trap 用例 + quote-include 双文件（B 组对拍用）
  const tmpDir = path.join(repoRoot, "tmp", "cli_smoke_fixtures");
  fs.mkdirSync(tmpDir, { recursive: true });
  const trapC = path.join(tmpDir, "trap_case.c");
  fs.writeFileSync(
    trapC,
    '#include <stdio.h>\n#include <string.h>\nint main(){ char buf[4]; strcpy(buf, "hello"); printf("x\\n"); return 0; }\n',
  );
  const incC = path.join(tmpDir, "inc_case.c");
  const incH = path.join(tmpDir, "util.h");
  fs.writeFileSync(incH, "#define MAGIC 42\n");
  fs.writeFileSync(incC, '#include <stdio.h>\n#include "util.h"\nint main(){ printf("MAGIC=%d\\n", MAGIC); return 0; }\n');
  const plainC = path.join(repoRoot, "corpus", "baseline", "array_sum_loop.c");

  // ── A 组：壳 rc 契约 ─────────────────────────────────────────
  for (const c of [
    { name: "run 正常", argv: ["run", plainC], want: 0 },
    { name: "run trap", argv: ["run", trapC], want: 2 },
    { name: "run 编译错", argv: ["run", "tmp/cli_smoke_fixtures/none.c"], want: 4 },
    { name: "compile 正常", argv: ["compile", plainC], want: 0 },
    { name: "compile trap 源（编译面=0）", argv: ["compile", trapC], want: 0 },
    { name: "step 正常", argv: ["step", plainC], want: 0 },
    { name: "api 单帧 ok", argv: ["api", "capabilities"], want: 0 },
    // DX P2（2026-10-11）：未知方法 cli 预检 rc=4（用法错）——旧锚 1 是 gateway
    // 帧协议内失败码位（shell 会误读编译错同码），翻锚
    { name: "api 单帧 ok:false", argv: ["api", "bogus.method"], want: 4 },
  ]) {
    const { rc } = runOut(nodeBin, [shell, ...c.argv]);
    if (rc !== c.want) fatalf(`A[壳 rc] ${c.name}: rc=${rc} want ${c.want}`);
    else process.stdout.write(`ok  A[壳 rc] ${c.name} rc=${rc}\n`);
  }
  // api --batch（stdin 帧序列——状态跨帧：compile→run 连续）
  const batch = `{"id":1,"method":"ping","params":{}}
{"id":2,"method":"compile","params":{"source":"int main(){return 0;}"}}
{"id":3,"method":"run","params":{}}
`;
  {
    const r = spawnSync(nodeBin, [shell, "api", "--batch"], {
      cwd: repoRoot,
      maxBuffer: 64 * 1024 * 1024,
      input: batch,
    });
    const ob = bufStr(r.stdout);
    if (r.error !== undefined || (r.status ?? -1) !== 0) {
      fatalf(`A[api --batch] 启动/rc 异常: ${r.error?.message ?? `rc=${r.status}`}（输出 ${ob}）`);
    } else if (!ob.includes('"pong":true') || !ob.includes('"status":"finished"')) {
      fatalf(`A[api --batch] 帧序列断言失败：${ob}`);
    } else {
      process.stdout.write("ok  A[api --batch] ping+compile+run 状态跨帧\n");
    }
  }
  // #335（2026-10-27）：帧通道字节锚——println 出口不走红/黑 write stub，
  // native 修前 CRT 文本模式每换行 +0d（constructor 进程级二进制治本）。
  // 三臂同喂 batch 序列，原始 stdout 字节逐位比对零归一 + native 零 0d。
  {
    const arms = [
      { label: "js", exe: jsEntry },
      { label: "wasm", exe: shell },
      { label: "native", exe: nativeExe },
    ];
    const outs: Buffer[] = [];
    for (const a of arms) {
      const r = spawnSync(a.label === "native" ? a.exe : nodeBin, [
        ...(a.label === "native" ? [] : [a.exe]),
        "api",
        "--batch",
      ], { cwd: repoRoot, maxBuffer: 64 * 1024 * 1024, input: batch });
      if (r.error !== undefined || (r.status ?? -1) !== 0) {
        fatalf(`B[帧通道字节] ${a.label} 启动/rc 异常: ${r.error?.message ?? `rc=${r.status}`}`);
      }
      outs.push(r.stdout);
    }
    const [j = Buffer.alloc(0), w = Buffer.alloc(0), n = Buffer.alloc(0)] = outs;
    if (j.equals(w) && w.equals(n)) {
      if (n.includes(13)) {
        fatalf(`B[帧通道字节] native 帧输出含 0d（CRT 文本模式 CRLF 回潮，#335 治本回归）`);
      }
      process.stdout.write(`ok  B[帧通道字节] 三臂 api --batch 原始字节逐位一致（${n.length}B，native 零 0d，#335）\n`);
    } else {
      const fd = firstDiff(j, n);
      fatalf(`B[帧通道字节] 三臂帧输出不一致（len j=${j.length} w=${w.length} n=${n.length} 首差 offset=${fd}——native 帧尾 CRLF 形态，#335）`);
    }
  }
  // #335 审阅 P3-1（2026-10-27）：serve 帧——唯一 NDJSON 行协议 exe 此前
  // 无字节锚（serve_smoke/protocol_frames 的 JSON 规范化吸收 CRLF，突变
  // 实证摘 main 前置调用后仍 67 PASS 全绿）。两帧+shutdown 收尾，原始字节
  // 零归一断言：帧内容 + 帧尾 LF + 全文零 0d。
  {
    const r = spawnSync(serveExe, [], {
      cwd: repoRoot,
      maxBuffer: 64 * 1024 * 1024,
      input: '{"id":1,"method":"ping","params":{}}\n{"id":2,"method":"shutdown","params":{}}\n',
    });
    const ob = r.stdout.toString("latin1");
    if (r.error !== undefined || (r.status ?? -1) !== 0) {
      fatalf(`B[serve 帧字节] 启动/rc 异常: ${r.error?.message ?? `rc=${r.status}`}`);
    } else if (!ob.includes('"pong":true') || !ob.includes('"shutdown":true')) {
      fatalf(`B[serve 帧字节] 帧内容断言失败：${ob}`);
    } else if (r.stdout.includes(13)) {
      fatalf(`B[serve 帧字节] serve 帧输出含 0d（CRT 文本模式 CRLF 回潮，#335 治本回归——serve_stdio 的 main 前置调用被摘）`);
    } else {
      process.stdout.write(`ok  B[serve 帧字节] serve 两帧+shutdown 零 0d（${r.stdout.length}B，#335 审阅 P3-1）\n`);
    }
  }
  // #366（2026-10-28）：大帧管道口径锚——api/step 帧出口走壳注入同步通道前，
  // js/wasm 臂帧走 println → node 对管道是异步写，帧后立即 process.exit 丢弃
  // 未刷写队列：>1MB 帧管道口径静默截断（WSL 实测 65808B/128KB 边界浮动、
  // rc=0 零信号、产出非法 JSON；文件口径完整——node 对文件同步写）。本锚
  // 同帧序列双口径对拍：管道（spawnSync 默认 stdout=pipe）vs 文件（fd 直
  // 写），断言 rc=0 + 逐字节等长 + 每帧 JSON 可解析 + 帧量 >1MB（门量保证
  // 覆盖截断边界）。native 臂 CRT exit 刷缓冲不受影响，一并入锚作对照。
  {
    const bigBatch =
      `{"id":1,"method":"compile","params":{"source":"int main(){return 0;}"}}\n` +
      `{"id":2,"method":"run","params":{"argv":["m.c"],"batch_input":true}}\n` +
      `{"id":3,"method":"memory.dump","params":{}}\n`;
    const bigFile = path.join(tmpDir, "b366_control.out");
    const arms = [
      { label: "js", exe: jsEntry },
      { label: "wasm", exe: shell },
      { label: "native", exe: nativeExe },
    ];
    const pipeOuts = new Map<string, Buffer>();
    for (const a of arms) {
      const argv = [...(a.label === "native" ? [] : [a.exe]), "api", "--batch"];
      const exe = a.label === "native" ? a.exe : nodeBin;
      // 文件口径（对照）：stdout 直写 fd——node 对文件同步写，完整性质押
      const fd = fs.openSync(bigFile, "w");
      const rf = spawnSync(exe, argv, {
        cwd: repoRoot,
        maxBuffer: 64 * 1024 * 1024,
        input: bigBatch,
        stdio: ["pipe", fd, "pipe"],
      });
      fs.closeSync(fd);
      // 管道口径（被测）：spawnSync 默认 stdout=pipe——正是 #366 病灶形态
      const rp = spawnSync(exe, argv, { cwd: repoRoot, maxBuffer: 64 * 1024 * 1024, input: bigBatch });
      const fbytes = fs.readFileSync(bigFile);
      const pbytes = rp.stdout ?? Buffer.alloc(0);
      if (rf.error !== undefined || rp.error !== undefined || (rf.status ?? -1) !== 0 || (rp.status ?? -1) !== 0) {
        fatalf(`B[大帧管道] ${a.label} rc 异常: file=${rf.status ?? rf.error?.message} pipe=${rp.status ?? rp.error?.message}`);
        continue;
      }
      if (fbytes.length <= 1024 * 1024) {
        fatalf(`B[大帧管道] ${a.label} 帧量 ${fbytes.length}B 未过 1MB 门量（锚失效——换更大帧源）`);
        continue;
      }
      if (!pbytes.equals(fbytes)) {
        fatalf(`B[大帧管道] ${a.label} 管道口径截断/漂移：pipe=${pbytes.length}B file=${fbytes.length}B（#366 帧出口未走同步通道）`);
        continue;
      }
      let lines = 0;
      let allJson = true;
      for (const ln of pbytes.toString("utf8").split("\n")) {
        if (ln.length === 0) continue;
        lines++;
        try {
          JSON.parse(ln);
        } catch {
          allJson = false;
          break;
        }
      }
      if (!allJson || lines !== 3) {
        fatalf(`B[大帧管道] ${a.label} 帧完整性失败：${lines} 帧可解析=${allJson}（截断产出非法 JSON）`);
        continue;
      }
      pipeOuts.set(a.label, pbytes);
      process.stdout.write(`ok  B[大帧管道] ${a.label} 双口径逐字节一致（${pbytes.length}B / 3 帧合法 JSON，#366）\n`);
    }
    // 三臂大帧内容同形（同帧序列同引擎——顺带锁 memory.dump 跨臂一致）
    const j = pipeOuts.get("js");
    const w = pipeOuts.get("wasm");
    const n = pipeOuts.get("native");
    if (j === undefined || w === undefined || n === undefined) {
      // 上方已 fatalf 过对应臂——此处不重复计数
    } else if (!j.equals(w) || !w.equals(n)) {
      fatalf(`B[大帧管道] 三臂 memory.dump 帧不一致：j=${j.length} w=${w.length} n=${n.length}B`);
    } else {
      process.stdout.write(`ok  B[大帧管道] 三臂大帧内容逐位一致（#366+#14 三臂纪律）\n`);
    }
  }
  // #363（2026-10-28）：invalid UTF-8 源码三臂同形锚——修前三臂三结局
  //（native SIGABRT/0xC0000409、wasm 裸 unreachable、js 双态：3 字节截断
  // 形态 E1001+E1003 / 4 字节越界形态 rc=0 静默容忍）；修后 fs 解码统一
  // U+FFFD 替换、源码面 lexer E1001 拒收。断言：三臂 rc=1 + 输出剥
  // backend 行后逐行一致 + 含 E1001（锁「同形」而非具体文案——文案属
  // error_catalog 单源）。
  {
    const badSrc = path.join(tmpDir, "bad_utf8_363.c");
    fs.writeFileSync(badSrc, Buffer.from([0x69, 0x6e, 0x74, 0x20, 0x6d, 0x61, 0x69, 0x6e, 0x28, 0x29, 0x7b, 0x72, 0x65, 0x74, 0x75, 0x72, 0x6e, 0x20, 0x30, 0x3b, 0x7d, 0xff, 0xfe, 0x80]));
    const relBad = toSlash(path.relative(repoRoot, badSrc));
    const arms = [
      { label: "js", exe: nodeBin, pre: [jsEntry] },
      { label: "wasm", exe: nodeBin, pre: [shell] },
      { label: "native", exe: nativeExe, pre: [] as string[] },
    ];
    const outs363: string[] = [];
    let rcs363: number[] = [];
    for (const a of arms) {
      const r = runOut(a.exe, [...a.pre, "compile", relBad]);
      rcs363.push(r.rc);
      outs363.push(stripBackendLine(r.out));
    }
    const [j363 = "", w363 = "", n363 = ""] = outs363;
    if (!(rcs363[0] === 1 && rcs363[1] === 1 && rcs363[2] === 1)) {
      fatalf(`B[坏字节源码] 三臂 rc 非 1：js=${rcs363[0]} wasm=${rcs363[1]} native=${rcs363[2]}（#363 应为 E1001 拒收）`);
    } else if (!j363.includes("E1001") || !j363.includes("\u{FFFD}")) {
      fatalf(`B[坏字节源码] 诊断不含 E1001/U+FFFD：${j363.slice(0, 200)}`);
    } else if (j363 !== w363 || w363 !== n363) {
      fatalf(`B[坏字节源码] 三臂输出不同形（#363 修复回归——native 崩/wasm 裸 trap/js 静默任一复发）`);
    } else {
      process.stdout.write(`ok  B[大帧管道] 三臂大帧内容逐位一致（#366+#14 三臂纪律）\n`);
    }
  }
  // PR #367 审阅 P2-3/P3-1（2026-10-28）：① stderr 通道同族锚——node 对
  // 管道的 stderr 写同样异步，实测分界 = 单次写大小 vs 管道缓冲 64KB
  //（超长标识符诊断单段 70106B 修前截断于 65536B；小段多写不触发）——
  // 三臂编译错风暴 + 单段大写双口径（pipe vs fd 文件）逐字节比对。
  // ② run --json 大帧（type:stdout 帧 >1MB）——api --batch 之外的帧出
  // 口路径（frame_pipeline）此前零锚。
  {
    const arms = [
      { label: "js", exe: jsEntry },
      { label: "wasm", exe: shell },
      { label: "native", exe: nativeExe },
    ];
    const armCmd = (a: { label: string; exe: string }, argv: readonly string[]): { exe: string; pre: string[] } =>
      a.label === "native" ? { exe: a.exe, pre: [] } : { exe: nodeBin, pre: [a.exe] };
    // ① stderr 双形态：编译错风暴（小段多写）+ 超长标识符（单段 >64KB）
    const bigErrC = path.join(tmpDir, "big_err_storm.c");
    const stormLines: string[] = ["int main(){"];
    for (let i = 0; i < 600; i++) stormLines.push(`  undefined_var_${i} = ${i};`);
    stormLines.push("  return 0; }");
    fs.writeFileSync(bigErrC, stormLines.join("\n") + "\n");
    const hugeIdentC = path.join(tmpDir, "huge_ident.c");
    fs.writeFileSync(hugeIdentC, `int main(){ ${"a".repeat(70000)} = 1; return 0; }\n`);
    for (const spec of [
      { name: "stderr 风暴", file: bigErrC, min: 60000 },
      { name: "stderr 单段大写", file: hugeIdentC, min: 65536 },
    ]) {
      for (const a of arms) {
        const { exe, pre } = armCmd(a, []);
        const argv = [...pre, "compile", toSlash(path.relative(repoRoot, spec.file))];
        const errFile = path.join(tmpDir, "p2_3_control.err");
        const fd = fs.openSync(errFile, "w");
        const rf = spawnSync(exe, argv, { cwd: repoRoot, maxBuffer: 64 * 1024 * 1024, stdio: ["ignore", "ignore", fd] });
        fs.closeSync(fd);
        const rp = spawnSync(exe, argv, { cwd: repoRoot, maxBuffer: 64 * 1024 * 1024 });
        const fbytes = fs.readFileSync(errFile);
        const pbytes = rp.stderr ?? Buffer.alloc(0);
        if (rf.error !== undefined || rp.error !== undefined) {
          fatalf(`B[stderr 通道] ${a.label} ${spec.name} 启动异常: ${String(rf.error ?? rp.error)}`);
          continue;
        }
        if (fbytes.length <= spec.min) {
          fatalf(`B[stderr 通道] ${a.label} ${spec.name} 量 ${fbytes.length}B 未过门量 ${spec.min}B（锚失效）`);
          continue;
        }
        if (!pbytes.equals(fbytes)) {
          fatalf(`B[stderr 通道] ${a.label} ${spec.name} 管道口径截断/漂移：pipe=${pbytes.length}B file=${fbytes.length}B（P2-3 stderr 未走同步通道）`);
          continue;
        }
        process.stdout.write(`ok  B[stderr 通道] ${a.label} ${spec.name} 双口径一致（${pbytes.length}B，P2-3）\n`);
      }
    }
    // ② run --json 大 stdout 帧（frame_pipeline 路径）：程序输出 >1MB →
    // type:stdout 帧 >1MB，三臂双口径比对
    const bigOutC = path.join(tmpDir, "big_stdout.c");
    fs.writeFileSync(bigOutC, '#include <stdio.h>\nint main(){ for(int i=0;i<25000;i++) printf("line-%06d-abcdefghijklmnopqrstuvwxyz-0123456789\\n", i); return 0; }\n');
    for (const a of arms) {
      const { exe, pre } = armCmd(a, []);
      const argv = [...pre, "run", "--json", toSlash(path.relative(repoRoot, bigOutC))];
      const outFile = path.join(tmpDir, "p3_1_control.out");
      const fd = fs.openSync(outFile, "w");
      const rf = spawnSync(exe, argv, { cwd: repoRoot, maxBuffer: 64 * 1024 * 1024, stdio: ["ignore", fd, "ignore"] });
      fs.closeSync(fd);
      const rp = spawnSync(exe, argv, { cwd: repoRoot, maxBuffer: 64 * 1024 * 1024 });
      const fbytes = fs.readFileSync(outFile);
      const pbytes = rp.stdout ?? Buffer.alloc(0);
      if (rf.error !== undefined || rp.error !== undefined || (rf.status ?? -1) !== 0 || (rp.status ?? -1) !== 0) {
        fatalf(`B[run json 大帧] ${a.label} rc 异常: ${String(rf.status)} / ${String(rp.status)}`);
        continue;
      }
      if (fbytes.length <= 1024 * 1024) {
        fatalf(`B[run json 大帧] ${a.label} 帧量 ${fbytes.length}B 未过 1MB 门量（锚失效）`);
        continue;
      }
      if (!pbytes.equals(fbytes)) {
        fatalf(`B[run json 大帧] ${a.label} 管道口径截断/漂移：pipe=${pbytes.length}B file=${fbytes.length}B（frame_pipeline 出口回归）`);
        continue;
      }
      process.stdout.write(`ok  B[run json 大帧] ${a.label} 双口径逐字节一致（${pbytes.length}B，P3-1）\n`);
    }
  }

  // ── B 组：三臂同形对拍（核心锚——差异消灭的机判）────────────
  const warnC = path.join(tmpDir, "warn_case.c");
  // 病 85 修（2026-10-16）：旧 fixture 实产出 2E+0W——补 double→int 窄化（W3053）
  // 成真 E+W 混合，失败路径的 warning 行渲染自此有双臂对拍锚
  fs.writeFileSync(warnC, "int main(){ int *p; char *c = p; int y = c; double d = 3.14; int z = d; return y + z; }\n");
  for (const c of [
    { name: "普通用例", file: plainC },
    { name: "trap 用例", file: trapC },
    { name: "quote-include 双文件", file: incC },
    { name: "编译错+类型警告（失败路径诊断）", file: warnC },
    { name: "scanf EOF（headless 语义）", file: path.join(repoRoot, "corpus", "baseline", "scanf_return_value.c") },
  ]) {
    const relPath = toSlash(path.relative(repoRoot, c.file));
    const w = runOut(nodeBin, [shell, "run", relPath]);
    const n = runOut(nativeExe, ["run", relPath]);
    if (w.rc !== n.rc) {
      fatalf(`B[双臂对拍] ${c.name}: rc 不一致 wasm=${w.rc} native=${n.rc}`);
    }
    const wasmOut = stripBackendLine(w.out);
    const natOut = stripBackendLine(n.out);
    if (wasmOut !== natOut) {
      fatalf(`B[双臂对拍] ${c.name}: stdout/stderr 不一致\n--- wasm ---\n${wasmOut}\n--- native ---\n${natOut}`);
    }
    // 审阅 P1-②（2026-10-15）：js 臂进语义对拍面——此前只在前置产物检查出现
    const j = runOut(nodeBin, [jsEntry, "run", relPath]);
    if (j.rc !== n.rc) {
      fatalf(`B[三臂对拍] ${c.name}: rc 不一致 js=${j.rc} native=${n.rc}`);
    }
    const jsOut = stripBackendLine(j.out);
    if (jsOut !== natOut) {
      fatalf(`B[三臂对拍] ${c.name}: js 与 native 不同形\n--- js ---\n${jsOut}\n--- native ---\n${natOut}`);
    }
    process.stdout.write(`ok  B[三臂对拍] ${c.name}（rc=${w.rc} 同形）\n`);
  }

  // B 组附 2：api help 三态双臂对拍（#67）——数据 = 生成器双产物，此处锁
  // 「双臂查表打印逐字节同形」+ 三态 rc + 内容锚（形状漂移双闸之一）。
  for (const c of [
    // 方法计数随 gen_api_help rules.json 走（#52 codegen.dump 29，2026-10-17 合并批连坐）
    { name: "api help 清单", args: ["api", "help"], wantRc: 0, needle: "api 方法清单（31）" },
    {
      name: "api help compile 详情",
      args: ["api", "help", "compile"],
      wantRc: 0,
      needle: "params: files:[{filename?,source}] | source:string[,filename:string]",
    },
    { name: "api help 未知方法", args: ["api", "help", "no.such"], wantRc: 4, needle: "用法错: 未知方法 'no.such'" },
  ]) {
    const w = runOut(nodeBin, [shell, ...c.args]);
    const n = runOut(nativeExe, c.args);
    if (w.rc !== c.wantRc || n.rc !== c.wantRc) {
      fatalf(`B[api help] ${c.name}: rc 期望 ${c.wantRc}，实得 wasm=${w.rc} native=${n.rc}`);
    }
    const wOut = stripBackendLine(w.out);
    const nOut = stripBackendLine(n.out);
    if (wOut !== nOut) {
      fatalf(`B[api help] ${c.name}: 双臂不同形\n--- wasm ---\n${wOut}\n--- native ---\n${nOut}`);
    }
    if (!wOut.includes(c.needle)) {
      fatalf(`B[api help] ${c.name}: 内容锚缺失（期望含 ${JSON.stringify(c.needle)}）\n${wOut}`);
    }
    process.stdout.write(`ok  B[api help] ${c.name}（rc=${c.wantRc} 同形+内容锚）\n`);
  }

  // B 组附 3：api 失败形态三臂 rc 对拍（#227 机判锚）——spec §4.5 两层判据的
  // 回归锚：编译错帧〔外层 ok:true + result.ok:false〕rc=1、协议错帧〔外层
  // ok:false〕rc=1、成功帧 rc=0。三臂必须同码。
  for (const c of [
    { name: "api 编译错帧（result.ok:false）", args: ["api", "compile", '{"source":"int main(){ int a = ; }"}'], want: 1 },
    { name: "api 协议错帧（外层 ok:false）", args: ["api", "output.delta", '{"cursor":0,"stream":"nope"}'], want: 1 },
    { name: "api 成功帧", args: ["api", "compile", '{"source":"int main(){return 0;}"}'], want: 0 },
  ]) {
    const w = runOut(nodeBin, [shell, ...c.args]).rc;
    const n = runOut(nativeExe, c.args).rc;
    const j = runOut(nodeBin, [jsEntry, ...c.args]).rc;
    if (w !== c.want || n !== c.want || j !== c.want) {
      fatalf(`B[api rc] ${c.name}: 期望 ${c.want}，实得 wasm=${w} native=${n} js=${j}`);
    }
    process.stdout.write(`ok  B[api rc] ${c.name} 三臂同 rc=${c.want}\n`);
  }

  // B 组附 4：rc=4 用法错路径 stdout 恒空（#215）——spec §1「stdout 只承载程序
  // 输出」的用法错面：文案全走 stderr；三臂同守。
  for (const c of [
    { name: "壳无参", args: [] as string[] },
    { name: "壳未知命令", args: ["bogus-cmd"] },
    { name: "dump 指引（独立 exe 族）", args: ["dump-tokens"] },
    { name: "api 无参", args: ["api"] },
    { name: "api 未知方法", args: ["api", "bogus.method", "{}"] },
    { name: "api params 非 JSON", args: ["api", "compile", "notjson"] },
    { name: "api help 未知方法", args: ["api", "help", "no.such"] },
    { name: "run 未知旗标", args: ["run", "--no-such-flag"] },
  ]) {
    for (const arm of [
      { label: "wasm", argv: [shell, ...c.args], exe: nodeBin },
      { label: "native", argv: c.args, exe: nativeExe },
      { label: "js", argv: [jsEntry, ...c.args], exe: nodeBin },
    ]) {
      const r = runSplit(arm.exe, arm.argv);
      if (r.rc !== 4) fatalf(`B[rc=4 stdout 空] ${c.name}/${arm.label}: rc=${r.rc} 期望 4`);
      if (r.out !== "") fatalf(`B[rc=4 stdout 空] ${c.name}/${arm.label}: stdout 应为空，实得:\n${r.out}`);
      if (r.err === "") fatalf(`B[rc=4 stdout 空] ${c.name}/${arm.label}: stderr 不应为空（文案去向）`);
    }
  }
  process.stdout.write("ok  B[rc=4 stdout 空] 8 路径 × 三臂（用法错全走 stderr）\n");

  // B 组附 5：--realtime 生效面探针（PR #280 审阅 P2-1）——js/native 臂断 time()
  // 非 0（真墙钟），wasm 臂断恒 0（F5 无熵源分臂口径）。
  {
    const rtC = path.join(tmpDir, "realtime_probe.c");
    fs.writeFileSync(
      rtC,
      '#include <stdio.h>\nlong time(long*);\nint main(){ long t = time((long*)0); printf("t=%d", t != 0); return 0; }\n',
    );
    const relRT = toSlash(path.relative(repoRoot, rtC));
    for (const arm of [
      { label: "wasm", argv: [shell, "run", "--realtime", relRT], exe: nodeBin, wantT: "t=0" },
      { label: "native", argv: ["run", "--realtime", relRT], exe: nativeExe, wantT: "t=1" },
      { label: "js", argv: [jsEntry, "run", "--realtime", relRT], exe: nodeBin, wantT: "t=1" },
    ]) {
      const r = runSplit(arm.exe, arm.argv);
      if (r.rc !== 0) fatalf(`B[--realtime] ${arm.label}: rc=${r.rc}\n${r.out}`);
      if (!r.out.startsWith(arm.wantT)) {
        fatalf(`B[--realtime] ${arm.label}: 期望输出前缀 ${JSON.stringify(arm.wantT)}（分臂口径），实得 ${JSON.stringify(headBytes(r.out, 24))}`);
      }
      // 缺省对照：无旗标时三臂恒 t=0（判分口径不变）
      const dArgv =
        arm.label === "wasm" ? [shell, "run", relRT] : arm.label === "native" ? ["run", relRT] : [jsEntry, "run", relRT];
      const d = runSplit(arm.exe, dArgv);
      if (d.rc !== 0 || !d.out.startsWith("t=0")) {
        fatalf(`B[--realtime 缺省] ${arm.label}: 期望恒 t=0（deterministic 判分口径），rc=${d.rc} 实得 ${JSON.stringify(headBytes(d.out, 24))}`);
      }
    }
    process.stdout.write("ok  B[--realtime] 三臂分口径（js/native 真 t、wasm 恒 0、缺省恒 0）\n");
  }

  // B 组附 6：字节级三臂 stdout/stderr 对拍（#315/#316，2026-10-26；P2-2 审阅
  // 处置扩双通道）——语义层锚的 normalize（CRLF→LF）曾把「native CRT 文本
  // 模式每换行多 1 字节」吸收在判定处（注释宣称零 canonicalize 而代码有全局
  // 归一——闸门失守面）；审阅实锤 stderr 半边无锚（只还原 stderr stub 仍全绿）。
  // 本锚**零归一裸比**三臂两通道原始 Buffer：不 utf8 解码（0xC8 等非 UTF-8
  // 字节保真比）、不做任何行尾处理。stdout 面 = 程序输出；stderr 面 = CLI
  // 标记行（// STDERR // NOTE 等教学文案承载通道——程序 fprintf(stderr) 被引
  // 擎包装为 // STDERR 行）；CLI 帧通道（api/serve 的 println 出口）不在此面
  // （存量 P3，spec TrimRight 注记）。fixture 覆盖三形态：常规换行 / 非 UTF-8
  // 字节 + 换行（最能区分 CRLF 改写）/ 尾部无换行。
  {
    const binC = path.join(tmpDir, "byte_probe.c");
    fs.writeFileSync(
      binC,
      '#include <stdio.h>\nint main(){ printf("line1\\nline2\\n"); putchar(200); putchar(255); putchar(65); printf("\\n"); printf("tail-no-nl"); fprintf(stderr, "e\\n"); fputc(200, stderr); fputc(10, stderr); return 0; }\n',
    );
    const relBin = toSlash(path.relative(repoRoot, binC));
    const armDefs = [
      { label: "wasm", exe: nodeBin, argv: [shell, "run", relBin] },
      { label: "native", exe: nativeExe, argv: ["run", relBin] },
      { label: "js", exe: nodeBin, argv: [jsEntry, "run", relBin] },
    ];
    const outs: Buffer[] = [];
    const errs: Buffer[] = [];
    let byteProbeRc = 0;
    for (const arm of armDefs) {
      const r = spawnSync(arm.exe, arm.argv, { cwd: repoRoot, maxBuffer: 64 * 1024 * 1024 });
      if (r.error !== undefined || (r.status ?? -1) !== 0) {
        fatalf(`B[字节对拍] ${arm.label}: rc=${String(r.status)}（${r.error?.message ?? ""}）`);
        byteProbeRc = 1;
      }
      outs.push(r.stdout ?? Buffer.alloc(0));
      errs.push(r.stderr ?? Buffer.alloc(0));
    }
    // stderr 侧唯一允许差异 = [vitro] backend= 前置行（wasm 壳打，#322）——
    // latin1 双射按行剥（字节保真；行尾 \r 若在场仍保留——本锚不归一）
    const stripBackendLineBytes = (b: Buffer): Buffer => {
      const kept = b
        .toString("latin1")
        .split("\n")
        .filter((ln) => !ln.startsWith("[vitro] backend="));
      return Buffer.from(kept.join("\n"), "latin1");
    };
    if (byteProbeRc === 0) {
      const w = outs[0] ?? Buffer.alloc(0);
      const n = outs[1] ?? Buffer.alloc(0);
      const j = outs[2] ?? Buffer.alloc(0);
      if (!w.equals(n)) {
        fatalf(
          `B[字节对拍] wasm vs native stdout 原始字节不一致（len w=${w.length} n=${n.length} 首差 offset=${firstDiff(w, n)}——native CRT 文本模式 CRLF 改写形态，#315）`,
        );
      } else if (!w.equals(j)) {
        fatalf(`B[字节对拍] wasm vs js stdout 原始字节不一致（len w=${w.length} j=${j.length} 首差 offset=${firstDiff(w, j)}）`);
      } else {
        process.stdout.write(`ok  B[字节对拍] 三臂 stdout 原始字节逐位一致（${w.length}B，含非 UTF-8 字节与无尾换行形态，零归一）\n`);
      }
      const we = stripBackendLineBytes(errs[0] ?? Buffer.alloc(0));
      const ne = stripBackendLineBytes(errs[1] ?? Buffer.alloc(0));
      const je = stripBackendLineBytes(errs[2] ?? Buffer.alloc(0));
      if (!we.equals(ne)) {
        fatalf(
          `B[字节对拍 stderr] wasm vs native stderr 原始字节不一致（len w=${we.length} n=${ne.length} 首差 offset=${firstDiff(we, ne)}——stderr stub 的 CRLF 改写半边，P2-2）`,
        );
      } else if (!we.equals(je)) {
        fatalf(`B[字节对拍 stderr] wasm vs js stderr 原始字节不一致（len w=${we.length} j=${je.length} 首差 offset=${firstDiff(we, je)}）`);
      } else {
        process.stdout.write(`ok  B[字节对拍 stderr] 三臂 stderr 原始字节逐位一致（${we.length}B 剥 backend 行后零归一，// STDERR // NOTE 教学文案面）\n`);
      }
    }
  }

  // B 组附 7：2>&1 合流顺序锚（#357，2026-10-30）——重定向/管道消费形态
  // （CI `2>&1 | tee`、`> out 2>&1`）下，C 语义的 stdout 对非 tty 全缓冲与
  // stderr 无缓冲天然错序：native 臂程序 stdout（stdout_stub fwrite 落 CRT
  // 缓冲、进程退出才刷）被 stderr 标记行（// STDERR // NOTE——stderr 无缓冲
  // 立即落盘）反超，合并流里标记行抢在程序输出之前；js/wasm 臂出口同步写
  // （#366/#388 后 writeSync 形态）无此病。附 6 与 B 组语义层对拍均为**分通道
  // 抓取**（spawnSync stdout/stderr 分离捕获），抓不到交错序——本锚以两 fd
  // 指向同一文件复现 shell 级 `> f 2>&1`：断言合并文本中程序输出行全部先于
  // stderr 标记行，且三臂合并文本（剥 backend 行、CRLF 归一）逐位一致。
  {
    const ordC = path.join(tmpDir, "order_probe.c");
    fs.writeFileSync(
      ordC,
      '#include <stdio.h>\nint main(){ printf("A-line-1\\n"); printf("A-line-2\\n"); fprintf(stderr, "E-line\\n"); return 0; }\n',
    );
    const relOrd = toSlash(path.relative(repoRoot, ordC));
    const mergedFile = path.join(tmpDir, "order_merged.txt");
    const mergedByArm: string[] = [];
    let orderRc = 0;
    for (const arm of [
      { label: "wasm", argv: [shell, "run", relOrd], exe: nodeBin },
      { label: "native", argv: ["run", relOrd], exe: nativeExe },
      { label: "js", argv: [jsEntry, "run", relOrd], exe: nodeBin },
    ]) {
      const fd = fs.openSync(mergedFile, "w");
      let spawnOk = true;
      try {
        const r = spawnSync(arm.exe, arm.argv, { cwd: repoRoot, stdio: ["ignore", fd, fd], maxBuffer: 64 * 1024 * 1024 });
        if (r.error !== undefined || (r.status ?? -1) !== 0) {
          fatalf(`B[合流序] ${arm.label}: rc=${String(r.status)}（${r.error?.message ?? ""}）`);
          spawnOk = false;
        }
      } finally {
        fs.closeSync(fd);
      }
      if (!spawnOk) {
        orderRc = 1;
        mergedByArm.push("");
        continue;
      }
      const merged = normalize(stripBackendLine(fs.readFileSync(mergedFile, "utf8")));
      mergedByArm.push(merged);
      const firstOut = merged.indexOf("A-line-1");
      const markPos: number[] = [];
      for (const m of ["// STDERR", "// NOTE"]) {
        const i = merged.indexOf(m);
        if (i >= 0) markPos.push(i);
      }
      // fail loud：两标记行均缺席 = fixture/通道漂移，不静默绿
      const firstMark = markPos.length === 0 ? -1 : Math.min(...markPos);
      if (!(firstOut >= 0 && firstMark >= 0 && firstOut < firstMark)) {
        orderRc = 1;
        fatalf(`B[合流序] ${arm.label}: 合并流顺序错乱（程序输出首位=${firstOut} 标记行首位=${firstMark}——native stdout 全缓冲被 stderr 反超形态，#357）:\n${merged}`);
      }
    }
    if (orderRc === 0) {
      if (mergedByArm[0] !== mergedByArm[1]) {
        fatalf(`B[合流序] wasm vs native 合并文本不一致（归一后）:\n--- wasm ---\n${mergedByArm[0]}\n--- native ---\n${mergedByArm[1]}`);
      } else if (mergedByArm[0] !== mergedByArm[2]) {
        fatalf(`B[合流序] wasm vs js 合并文本不一致（归一后）:\n--- wasm ---\n${mergedByArm[0]}\n--- js ---\n${mergedByArm[2]}`);
      } else {
        process.stdout.write("ok  B[合流序] 三臂 2>&1 合并流：程序输出先于标记行、三臂同形（#357）\n");
      }
    }
  }

  // B 组附 8：SIGABRT 崩溃路径防线锚（#357，2026-10-30；Linux only）——
  // stdout_stub 的 ensure_binary_mode 现同点挂 SIGABRT handler（fflush(NULL)
  // 刷全部输出流 + 恢复默认处置 + re-raise，防 panic→abort 下 stdio 缓冲
  // 诊断蒸发）。本锚锁「死形态保真」面：外部注入 ABRT 后进程仍须死于
  // SIGABRT（shell 视角 rc=134），不得因 handler 偏差（只刷不 re-raise /
  // _exit 顶替）变成退出码形态或挂死。**边界登记**：防线「刷出实效」
  // （panic 诊断不蒸发）当前 master 无端到端触面——唯一已知 panic 触点
  // （invalid surrogate pair）已被 #363 批治成 U+FFFD 折回，缓冲无货可刷；
  // 待未来真实 panic 语料回补端到端锚。Windows skip：node/MSYS 的信号是
  // 进程终止模拟、不进 CRT handler，判定无意义（CI ubuntu 覆盖）。
  if (process.platform !== "linux") {
    process.stdout.write("skip B[SIGABRT 防线]（非 Linux——信号模拟不进 CRT handler；CI ubuntu 覆盖，#357）\n");
  } else {
    const loopC = path.join(tmpDir, "abort_probe.c");
    fs.writeFileSync(loopC, "int main(){ int i=0; while(1){ i=i+1; } return 0; }\n");
    const relLoop = toSlash(path.relative(repoRoot, loopC));
    // 大步数预算（缺省 10M 步 0.7s 即 trap，kill 窗口不稳；2G 步 ≈ 分钟级）
    const script = `"${nativeExe}" run --max-steps 2000000000 "${relLoop}" & p=$!; sleep 0.5; kill -ABRT $p; wait $p; echo "RC=$?"`;
    const r = spawnSync("/bin/bash", ["-c", script], { cwd: repoRoot, encoding: "utf8", timeout: 60000 });
    const m = /RC=(\d+)/.exec(r.stdout ?? "");
    if (r.error !== undefined || m === null) {
      fatalf(`B[SIGABRT 防线] 运行失败（spawn 超时/错误）：${r.error?.message ?? ""} out=${(r.stdout ?? "").trim()}`);
    } else if (m[1] !== "134") {
      fatalf(`B[SIGABRT 防线] 死形态走样：期望 shell rc=134（SIGABRT），实得 ${m[1]}——handler 只许刷 + 恢复默认 + re-raise，不得改死形态（#357）`);
    } else {
      process.stdout.write("ok  B[SIGABRT 防线] 外部 abort 死形态保真（rc=134，handler 刷 + re-raise 链）\n");
    }
  }

  // B 组附 1：note 去重语义锚（审阅 P3-1）——note 通道语义不在 vm_diff /
  // clang_direct 比对面，apply_reply 全量同文本去重此前零闸。
  {
    const dupC = path.join(tmpDir, "malloc0_dup.c");
    fs.writeFileSync(dupC, "#include <stdlib.h>\nint main(){ void*p; p=malloc(0); p=malloc(0); p=malloc(0); return p==0; }\n");
    const relDup = toSlash(path.relative(repoRoot, dupC));
    const w = runOut(nodeBin, [shell, "run", relDup]);
    const n = runOut(nativeExe, ["run", relDup]);
    if (w.rc !== n.rc || stripBackendLine(w.out) !== stripBackendLine(n.out)) {
      fatalf(`B[双臂对拍] malloc(0)×3: 双臂不同形\n--- wasm ---\n${w.out}\n--- native ---\n${n.out}`);
    }
    const cnt = stripBackendLine(w.out).split("[warning] malloc(0)").length - 1;
    if (cnt !== 1) {
      fatalf(`B[note 去重语义] malloc(0)×3 期望恰 1 条教学附注，实得 ${cnt} 条——apply_reply 全量同文本去重回归（批五第一片）`);
    }
    process.stdout.write("ok  B[note 去重语义] malloc(0)×3 恰 1 条附注（双臂同形）\n");
  }

  // B 组附：1MB 映像双臂对拍（--dump-memory——memory.dump 帧链路，#49 批二段二）
  {
    const wasmDump = path.join(tmpDir, "dump_wasm.bin");
    const natDump = path.join(tmpDir, "dump_native.bin");
    fs.rmSync(wasmDump, { force: true });
    fs.rmSync(natDump, { force: true });
    const w = runOut(nodeBin, [shell, "run", "corpus/baseline/bubble_sort.c", "--dump-memory", toSlash(wasmDump)]);
    const n = runOut(nativeExe, ["run", "corpus/baseline/bubble_sort.c", "--dump-memory", toSlash(natDump)]);
    if (w.rc !== 0 || n.rc !== 0) {
      fatalf(`B[映像对拍] rc 异常 wasm=${w.rc} native=${n.rc}`);
    } else if (!fs.existsSync(wasmDump)) {
      fatalf("B[映像对拍] dump 文件读取失败 wasm");
    } else if (!fs.existsSync(natDump)) {
      fatalf("B[映像对拍] dump 文件读取失败 native");
    } else {
      const wb = fs.readFileSync(wasmDump);
      const nb = fs.readFileSync(natDump);
      if (wb.length !== 1024 * 1024) {
        fatalf(`B[映像对拍] wasm dump 尺寸 ${wb.length} ≠ 1MB`);
      } else if (!wb.equals(nb)) {
        fatalf(`B[映像对拍] 1MB 映像逐字节不一致（首差 offset=${firstDiff(wb, nb)}）`);
      } else {
        process.stdout.write("ok  B[映像对拍] 1MB dump 双臂逐字节一致（memory.dump 帧）\n");
      }
    }
  }

  // B 组扩面：语料级三臂对拍（--corpus N；#49 批二）——稳定序 = 文件名字典序取前 N
  if (corpusN > 0) {
    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(path.join(repoRoot, "corpus", "baseline"), { withFileTypes: true });
    } catch (e) {
      fatalf(`B[语料对拍] corpus/baseline 不可读: ${(e as Error).message}`);
      entries = [];
    }
    const names = byteSort(entries.filter((e) => !e.isDirectory() && e.name.endsWith(".c")).map((e) => e.name));
    if (names.length === 0) {
      fatalf("B[语料对拍] corpus/baseline 零 .c 用例——目录形态异常");
    }
    if (corpusN > names.length) corpusN = names.length;
    let pass = 0;
    for (const name of names.slice(0, corpusN)) {
      const rel = "corpus/baseline/" + name;
      const w = runOut(nodeBin, [shell, "run", rel]);
      const n = runOut(nativeExe, ["run", rel]);
      if (w.rc !== n.rc) fatalf(`B[语料对拍] ${name}: rc 不一致 wasm=${w.rc} native=${n.rc}`);
      const wasmOut = stripBackendLine(w.out);
      const natOut = stripBackendLine(n.out);
      if (wasmOut !== natOut) {
        fatalf(`B[语料对拍] ${name}: 输出不一致\n--- wasm ---\n${wasmOut}\n--- native ---\n${natOut}`);
      }
      // js 臂语料级连坐（P2，2026-10-15 用户审阅提醒）：原 --corpus N 只比
      // wasm↔native，缺省臂反而语料零覆盖。
      const j = runOut(nodeBin, [jsEntry, "run", rel]);
      if (j.rc !== n.rc) fatalf(`B[语料对拍] ${name}: rc 不一致 js=${j.rc} native=${n.rc}`);
      const jsOut = stripBackendLine(j.out);
      if (jsOut !== natOut) {
        fatalf(`B[语料对拍] ${name}: js 与 native 不同形\n--- js ---\n${jsOut}\n--- native ---\n${natOut}`);
      }
      pass++;
    }
    if (failures === 0) {
      process.stdout.write(`ok  B[语料对拍] 前 ${pass} 例（字典序）三臂同形（wasm+js+native）\n`);
    }
  }

  // ── C 组：launcher 语义（fatalf 不终止——ok 行须 else 门控）────────────
  const shLauncher = path.join(repoRoot, "scripts", "bin", "vitro");
  {
    const r = runOut("sh", [shLauncher, "run", "corpus/baseline/array_sum_loop.c"]);
    if (r.rc !== 0) fatalf(`C[launcher sh] 默认臂 rc=${r.rc}`);
    else if (!r.out.includes("backend=js")) {
      fatalf(`C[launcher sh] 默认臂缺 backend=js 标注（三后端批 2026-10-15 缺省臂=js）：${r.out}`);
    } else process.stdout.write("ok  C[launcher sh] 默认臂 backend 标注\n");
  }
  {
    const r = runOut("sh", [shLauncher, "--backend", "native", "run", "corpus/baseline/array_sum_loop.c"]);
    if (r.rc !== 0) fatalf(`C[launcher sh] --backend native rc=${r.rc}`);
    else if (!r.out.includes("backend=native") || !r.out.includes("程序运行完成")) {
      fatalf(`C[launcher sh] --backend native 输出异常：${r.out}`);
    } else process.stdout.write("ok  C[launcher sh] --backend native 转发\n");
  }
  {
    const r = runOut("sh", [shLauncher, "--backend", "wasm", "run", "corpus/baseline/array_sum_loop.c"]);
    if (r.rc !== 0) fatalf(`C[launcher sh] --backend wasm rc=${r.rc}`);
    else if (!r.out.includes("backend=wasm")) {
      fatalf(`C[launcher sh] --backend wasm 标注缺失：${r.out}`);
    } else process.stdout.write("ok  C[launcher sh] --backend wasm 转发\n");
  }
  // cmd 形态仅 Windows 断言（CI 双 runner 覆盖；sh 版全平台）
  if (process.platform === "win32") {
    const r = runOut("cmd.exe", ["/c", path.join(repoRoot, "scripts", "bin", "vitro.cmd"), "run", "corpus/baseline/array_sum_loop.c"]);
    if (r.rc !== 0) fatalf(`C[launcher cmd] 默认臂 rc=${r.rc}：${r.out}`);
    else if (!r.out.includes("backend=js")) fatalf(`C[launcher cmd] 默认臂缺 backend=js 标注：${r.out}`);
    else process.stdout.write("ok  C[launcher cmd] 默认臂（Windows）\n");
  }

  if (failures > 0) {
    process.stdout.write(`vitro_cli_smoke: ${failures} 失败\n`);
    return 1;
  }

  // ── G 组：#129 通道分立（2026-10-16 用户拍板，推翻 #69 混流裁定）──
  // 文本模式 stdout 只承载被测程序输出（无 // 标记行——字节精确）；诊断行/note/
  // EXIT 标记行/用法错走 stderr（gcc/clang 先例）。J9：本断言先于实现存在。
  {
    const hintC = path.join(repoRoot, "corpus", "baseline", "bsearch_basic.c");
    for (const g of [
      { name: "wasm", argv: [nodeBin, wasmGlue] },
      { name: "js", argv: [nodeBin, jsEntry] },
      { name: "native", argv: [] as string[] },
    ]) {
      const argv = g.name === "native" ? [nativeExe, "run", hintC] : [...g.argv, "run", hintC];
      const r = runSplit(argv[0] ?? "", argv.slice(1));
      if (r.rc === 0) {
        // stdout：不得有任何 "// " 前缀行
        for (const line of r.out.split("\n")) {
          if (line.startsWith("// ")) {
            fatalf(`G[#129 通道分立] ${g.name}: stdout 含标记行 ${JSON.stringify(line)}（#69 翻案后 stdout 只承载程序输出）`);
          }
        }
        // stderr：必含 hint 诊断行与 note 行
        if (!r.err.includes("// COMPILE-HINT") || !r.err.includes("// NOTE ")) {
          fatalf(`G[#129 通道分立] ${g.name}: stderr 缺诊断/note 标记行（应走 stderr）——stderr=${JSON.stringify(headBytes(r.err, 200))}`);
        }
        process.stdout.write(`ok  G[#129 通道分立] ${g.name} 臂：stdout 纯程序输出 + stderr 标记行\n`);
      } else {
        fatalf(`G[#129 通道分立] ${g.name}: 执行失败 rc=${r.rc}`);
      }
    }
  }

  // ── D 组：薄壳 include 接线（病 43，#71 第二梯队 2026-10-11）────
  // 薄壳 compile/step 不经 cmd/vitro——注册下沉 cmd/lib/cli 后，薄壳
  // quote-include 必须过（修复前恒 E1021；防线此前三层全漏）。
  const thinCompile = path.join(repoRoot, "moonbit", "_build", "native", "release", "build", "cmd", "compile", "compile.exe");
  const thinStep = path.join(repoRoot, "moonbit", "_build", "native", "release", "build", "cmd", "step", "step.exe");
  if (fs.existsSync(thinCompile)) {
    const r = runOut(thinCompile, [incC]);
    if (r.rc !== 0 || r.out.includes("E1021")) fatalf(`D[薄壳 compile] quote-include 断链 rc=${r.rc}：${r.out}`);
    else process.stdout.write("ok  D[薄壳 compile] quote-include 接线\n");
  } else {
    process.stdout.write("skip D[薄壳 compile]（release exe 未构建——本地非全量态）\n");
  }
  if (fs.existsSync(thinStep)) {
    const r = runOut(thinStep, [incC]);
    if (r.rc !== 0 || r.out.includes("E1021")) fatalf(`D[薄壳 step] quote-include 断链 rc=${r.rc}：${r.out}`);
    else process.stdout.write("ok  D[薄壳 step] quote-include 接线\n");
  } else {
    process.stdout.write("skip D[薄壳 step]（release exe 未构建——本地非全量态）\n");
  }

  process.stdout.write("vitro_cli_smoke: 全绿（rc 契约 + 双臂同形对拍 + launcher + 薄壳 include）\n");
  return 0;
}

const invokedDirectly =
  process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) {
  process.exit(runMain(process.argv.slice(2)));
}
