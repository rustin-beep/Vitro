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
 * （backend 标注是设计差异非协议面：wasm 臂恒报 wasm、launcher 降级臂
 * 报 native；其余任何行差异都红）。注：本函数作用于归一后文本；字节层
 * （附 6 锚）比 stdout 原始字节，不经此函数（#316）。
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
  const wasmMod = path.join(repoRoot, "moonbit", "_build", "wasm-gc", "release", "build", "gateway", "wasm", "wasm.wasm");
  const jsEntry = path.join(repoRoot, "moonbit", "_build", "js", "release", "build", "cmd", "vitro_js", "vitro_js.js");
  const wasmGlue = shell;
  for (const p of [wasmGlue, nativeExe, wasmMod, jsEntry]) {
    if (!fs.existsSync(p)) {
      process.stdout.write(
        `vitro_cli_smoke: 前置产物缺失 ${p}（先构建：moon build --release --target wasm-gc gateway/wasm + MOON_CC=clang moon build --release --target native cmd/vitro + moon build --release --target js cmd/vitro_js + moon build --release --target js cmd/vitro_wasm）\n`,
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
    { name: "api help 清单", args: ["api", "help"], wantRc: 0, needle: "api 方法清单（30）" },
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

  // B 组附 6：字节级三臂 stdout 对拍（#315/#316，2026-10-26）——语义层锚的
  // normalize（CRLF→LF）曾把「native CRT 文本模式每换行多 1 字节」吸收在判定
  // 处（注释宣称零 canonicalize 而代码有全局归一——闸门失守面）。本锚**零归一
  // 裸比**三臂 stdout 原始 Buffer：不 utf8 解码（putchar(0xC8) 非 UTF-8 字节
  // 保真比）、不做任何行尾处理。fixture 覆盖三形态：常规换行 / 非 UTF-8 字节
  // + 换行（最能区分 CRLF 改写）/ 尾部无换行。
  {
    const binC = path.join(tmpDir, "byte_probe.c");
    fs.writeFileSync(
      binC,
      '#include <stdio.h>\nint main(){ printf("line1\\nline2\\n"); putchar(200); putchar(255); putchar(65); printf("\\n"); printf("tail-no-nl"); return 0; }\n',
    );
    const relBin = toSlash(path.relative(repoRoot, binC));
    const armDefs = [
      { label: "wasm", exe: nodeBin, argv: [shell, "run", relBin] },
      { label: "native", exe: nativeExe, argv: ["run", relBin] },
      { label: "js", exe: nodeBin, argv: [jsEntry, "run", relBin] },
    ];
    const outs: Buffer[] = [];
    let byteProbeRc = 0;
    for (const arm of armDefs) {
      const r = spawnSync(arm.exe, arm.argv, { cwd: repoRoot, maxBuffer: 64 * 1024 * 1024 });
      if (r.error !== undefined || (r.status ?? -1) !== 0) {
        fatalf(`B[字节对拍] ${arm.label}: rc=${String(r.status)}（${r.error?.message ?? ""}）`);
        byteProbeRc = 1;
      }
      outs.push(r.stdout ?? Buffer.alloc(0));
    }
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
