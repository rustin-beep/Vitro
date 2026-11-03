// desktop/tools/smoke.mts —— CI 全量防线编排：起 proton_cli dev（vite + 壳）→
// CDP 断言集 → 杀树。零第三方依赖；断言逻辑复用 cdp_probe/cdp_catch/page 资产
// （spawnSync 自身 node——单源不复制）。
//
// 用法：node tools/smoke.mts [port] [formC-port]（缺省 9335 / 9336；cwd 须为 desktop/）
// 前置（CI 步保证）：desktop 与 demo 的 npm ci、demo wasm.wasm + langpack 资产、
//   proton_cli 在 PATH、~/.proton CEF runtime 就位。
//
// 断言集（fail loud，逐条 stderr 标注后 rc=1）：
//   ① CDP 就绪（120s 内 /json/version 协议指纹——vite+壳+桥全链）
//   ② page-ready：title 非空且非 about:blank（≤90s，冷 runner vite 首访慢）
//   ③ demo_run.js 驱动完整采集：transport=ipc（读 window.__vitroTransport
//      实际选择结果，非桥存在性）/ golden ✓ / 42 帧 / 引擎 0.9.1 / stdout
//   ④ 命令层矩阵（demo_matrix.js invokeOp 直调四命令）
//   ⑤ cdp_catch：注入虫精确锚（probe-boom-uncaught 异常带堆栈 /
//      probe-console-err / net::ERR 网络域失败——三域各一）
//   ⑥ R3b 形态 C（release 捉虫通道）：临时改 app/main.mbt debug=false →
//      release 重建 → 直跑 exe（四件套 env + PROTON_REMOTE_DEBUGGING_PORT 钉
//      formC-port）→ CDP 可达（env 非空翻转 debug 的 facade 语义回归）→
//      url=proton.localhost（打包 asset 形态指纹）/ title 含 Vitro（真实渲染）
//      / 三虫捕获——关 F12 形态的捉虫通道断言；finally 还原 main.mbt
// 退出码：0=全过；1=断言失败；2=用法/环境错。
import { spawn, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";

const PORT = process.argv[2] ?? "9335";
const PORT_C = process.argv[3] ?? "9336";
const DEV_TIMEOUT_MS = 120_000;
const PROTON_CLI = process.env["PROTON_CLI"] ?? "proton_cli";

if (!existsSync("proton.project.json")) {
  console.error("smoke: 须在 desktop/ 目录下运行（proton.project.json 缺席）");
  process.exit(2);
}

const failures: string[] = [];
function check(name: string, ok: boolean, detail: string): void {
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? " — " + detail : ""}`);
  if (!ok) failures.push(name);
}

// 5173 被占 fail-fast（strictPort 下 vite 起不来，proton_cli 会空等——本地
// 被打断的上一跑残留 vite 实锤；120s 超时前 2s 内就该说清）
try {
  const r = await fetch("http://127.0.0.1:5173/", { signal: AbortSignal.timeout(1500) });
  console.error(`smoke: 127.0.0.1:5173 已有服务在应答（HTTP ${r.status}）——残留 vite？先清再跑`);
  process.exit(2);
} catch {
  // 未占用 = 正常
}

// ── 起 dev：proton_cli dev（进程树归本探针，finally taskkill /T 收树） ──
// TEMP 处方（README 坑表①）：沙箱约束会话里工作区 exe 建 %TEMP%\proton-cef-*
// 会 ACCESS_DENIED(5)——指到工作区内目录；CI runner 的 TEMP 本可写，指过去
// 无害（目录自建）。dev 与形态 C 两段同款。
const tmpDirShared = path.resolve("_build/tmp");
mkdirSync(tmpDirShared, { recursive: true });
console.log(`[smoke] spawn: ${PROTON_CLI} dev（CDP 端口 ${PORT}）`);
const dev = spawn(PROTON_CLI, ["dev"], {
  cwd: process.cwd(),
  env: { ...process.env, PROTON_REMOTE_DEBUGGING_PORT: PORT, TEMP: tmpDirShared, TMP: tmpDirShared },
  stdio: ["ignore", "pipe", "pipe"],
  shell: false,
});
dev.stdout.on("data", (d: Buffer) => process.stdout.write(`[dev] ${d}`));
dev.stderr.on("data", (d: Buffer) => process.stderr.write(`[dev] ${d}`));

function killTree(): void {
  // 只收自己的树（taskkill /PID /T）——不做 /IM 全局兜底：同名进程在
  // 开发者机上会误杀无关应用（审阅 P3）；CI 的残留清理由 job 的
  // cleanup 步在 runner 隔离环境里做
  if (dev.pid !== undefined && !dev.killed) {
    spawnSync("taskkill", ["/PID", String(dev.pid), "/T", "/F"], { stdio: "ignore" });
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

async function waitCdp(): Promise<boolean> {
  const t0 = Date.now();
  while (Date.now() - t0 < DEV_TIMEOUT_MS) {
    try {
      const r = await fetch(`http://127.0.0.1:${PORT}/json/version`, { signal: AbortSignal.timeout(1500) });
      if (r.ok) {
        const v = (await r.json()) as { Browser?: string };
        if (v.Browser !== undefined) return true;
      }
    } catch {
      // 未就绪
    }
    await sleep(1500);
  }
  return false;
}

/** cdp-ready 失败时的现场诊断（三轮 CI 红实锤：vite 只绑 ::1 而 proton_cli
 *  探 127.0.0.1 永远拒连——日志里只有「Waiting for frontend dev server」，
 *  无进一步信息）。端口监听态 + 进程表 + 两地址探活，下次红自解释。 */
async function diagnoseNotReady(): Promise<void> {
  const probe = async (url: string): Promise<string> => {
    try {
      const r = await fetch(url, { signal: AbortSignal.timeout(2000) });
      return `${url} → HTTP ${r.status}`;
    } catch (e) {
      return `${url} → ${(e as Error).message}`;
    }
  };
  console.error("[smoke/diag] 前端探活：", await probe("http://127.0.0.1:5173/"), "|", await probe("http://localhost:5173/"));
  const netstat = spawnSync("netstat", ["-an"], { encoding: "utf8" }).stdout ?? "";
  const listening = netstat
    .split(/\r?\n/)
    .filter((l) => /LISTEN/.test(l) && (l.includes(":5173 ") || l.includes(`:${PORT} `)));
  console.error("[smoke/diag] 监听端口（5173/CDP）：", listening.length > 0 ? listening.map((l) => l.trim()).join(" || ") : "无");
  const tasks = spawnSync("tasklist", ["/FI", "IMAGENAME eq app.exe", "/FI", "IMAGENAME eq node.exe"], { encoding: "utf8" }).stdout ?? "";
  console.error("[smoke/diag] 进程表（app/node）：", tasks.split(/\r?\n/).filter((l) => /app\.exe|node\.exe/.test(l)).join(" || ") || "无");
}

/** 跑一个探针脚本（同 node），回其 stdout 解析出的 JSON（eval 字段原样字符串）。 */
function runProbe(script: string, args: string[], port: string = PORT): { rc: number; stdout: string } {
  const r = spawnSync(process.execPath, [script, port, ...args], {
    cwd: process.cwd(),
    encoding: "utf8",
    timeout: 120_000,
  });
  return { rc: r.status ?? 1, stdout: (r.stdout ?? "") + (r.stderr ?? "") };
}

function evalField(stdout: string): Record<string, unknown> | null {
  const m = stdout.match(/"eval"\s*:\s*"((?:[^"\\]|\\.)*)"/s);
  if (m === null) return null;
  try {
    // 外层反转义后可能仍是字符串（页内 return 的 JSON 文本）——再解一层
    const outer = JSON.parse(`"${m[1]}"`) as unknown;
    const inner = typeof outer === "string" ? (JSON.parse(outer) as unknown) : outer;
    return typeof inner === "object" && inner !== null ? (inner as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

interface DemoRunResult {
  transport?: string;
  status?: string;
  stdout?: string;
  frames?: string;
  ver?: string;
  seek?: string;
  error?: string;
}

interface CaughtEvent {
  kind?: string;
  desc?: string;
  args?: string[];
  text?: string;
}

/** ⑤/⑥ 共用：跑 cdp_catch 并断言三虫精确锚（审阅 P3：caught_count>=N 在
 *  页面有有机异常时也 PASS，须锚到注入的三枚具体虫）。prefix 区分断言名。 */
function assertCatch(prefix: string, port: string): void {
  const catchRun = runProbe("tools/cdp_catch.mts", [], port);
  let caughtParsed: { caught_count?: number; caught?: CaughtEvent[] } | null = null;
  if (catchRun.rc === 0) {
    const start = catchRun.stdout.indexOf("{");
    const end = catchRun.stdout.lastIndexOf("}");
    if (start >= 0 && end > start) {
      try {
        caughtParsed = JSON.parse(catchRun.stdout.slice(start, end + 1)) as { caught_count?: number; caught?: CaughtEvent[] };
      } catch {
        caughtParsed = null;
      }
    }
  }
  const caught = caughtParsed?.caught ?? [];
  const hasBoom = caught.some((e) => e.kind === "exceptionThrown" && (e.desc ?? "").includes("probe-boom-uncaught"));
  const hasConsoleErr = caught.some(
    (e) => e.kind === "consoleAPICalled" && (e.args ?? []).some((a) => a.includes("probe-console-err")),
  );
  const hasNetErr = caught.some((e) => e.kind === "logEntry" && (e.text ?? "").includes("net::ERR"));
  check(`${prefix}cdp-catch-boom`, catchRun.rc === 0 && hasBoom, hasBoom ? "exceptionThrown@probe-boom-uncaught 命中" : `未命中（共 ${caught.length} 事件）`);
  check(`${prefix}cdp-catch-console`, catchRun.rc === 0 && hasConsoleErr, `consoleAPICalled@probe-console-err ${hasConsoleErr ? "命中" : "未命中"}`);
  check(`${prefix}cdp-catch-neterr`, catchRun.rc === 0 && hasNetErr, `logEntry@net::ERR ${hasNetErr ? "命中" : "未命中"}`);
}

try {
  // ① CDP 就绪
  const cdpOk = await waitCdp();
  check("cdp-ready", cdpOk, cdpOk ? `ws://127.0.0.1:${PORT}` : `${DEV_TIMEOUT_MS}ms 内未就绪`);
  if (!cdpOk) {
    await diagnoseNotReady();
    throw new Error("CDP 未就绪，后续断言跳过");
  }

  // ② 页面就绪等待（cdp-ready 只证 DevTools 端点——窗口刚建时页面可仍
  //    about:blank；冷 runner 上 vite 首访 optimize+挂载可 >30s，demo_run
  //    的按钮轮询窗曾在此翻车〔CI 六轮实锤〕）。显式等 title 非空 ≤90s，
  //    把「页面就绪」做成可诊断断言再谈 UI 驱动。
  let pageReady = false;
  let pageInfo = "n/a";
  for (let k = 0; k < 30 && !pageReady; k++) {
    const b = runProbe("tools/cdp_probe.mts", []);
    const be = b.rc === 0 ? evalField(b.stdout) : null;
    pageInfo = be === null ? `probe rc=${b.rc}` : `title=${String(be["title"])} url=${String(be["url"])}`;
    pageReady = be !== null && String(be["title"] ?? "").trim() !== "" && String(be["url"] ?? "") !== "about:blank";
    if (!pageReady) await sleep(3000);
  }
  check("page-ready", pageReady, pageReady ? pageInfo : `90s 内未就绪（${pageInfo}）`);
  console.log(`INFO  page — ${pageInfo}`);

  // ③ demo 完整采集断言（transport/golden/帧数/版本/stdout——基线 2026-11-02）
  const run = runProbe("tools/cdp_probe.mts", ["@tools/page/demo_run.js"]);
  const dr: DemoRunResult | null = run.rc === 0 ? (evalField(run.stdout) as DemoRunResult | null) : null;
  if (dr === null) {
    check("demo-run", false, `probe rc=${run.rc}（采集探针失败）`);
  } else if (dr.error !== undefined) {
    check("demo-run", false, String(dr.error));
  } else {
    // transport = window.__vitroTransport（engine.ipc.ts markKind 写的实际
    // 选择结果——审阅 P1-2：旧「桥存在?ipc:worker」对真走哪臂零判别力）
    check("transport-ipc", dr.transport === "ipc", `transport=${dr.transport}`);
    check("demo-golden", (dr.status ?? "").includes("golden ✓"), `status=${dr.status} seek=${dr.seek}`);
    check("demo-frames", dr.frames === "42", `frames=${dr.frames}`);
    check("demo-engine", (dr.ver ?? "").includes("0.9.1"), `ver=${dr.ver}`);
    check("demo-stdout", (dr.stdout ?? "").startsWith("1 2 3 4 5"), `stdout=${dr.stdout}`);
  }

  // ④ 命令层矩阵（审阅 P2-3）：四命令/argv 透传/feed 续跑/断点停采——
  //    直接 invokeOp 断言（零编辑器 DOM 依赖；demo 编辑器是 CodeMirror）。
  //    注意 feed 案依赖「此前本会话未 feed 过」的干净 stdin——smoke 每次
  //    全新 app 进程跑一次矩阵，自洽；引擎侧 stdin 跨 session.create 残留
  //    缺陷见 demo_matrix.js 头注 #451（矩阵内 feed 案排最后消费）。
  const mx = runProbe("tools/cdp_probe.mts", ["@tools/page/demo_matrix.js"]);
  const mxParsed = mx.rc === 0 ? (evalField(mx.stdout) as Record<string, { pass?: boolean; detail?: string }> | null) : null;
  if (mxParsed === null) {
    check("matrix", false, `probe rc=${mx.rc}（矩阵探针失败）`);
  } else {
    for (const [name, item] of Object.entries(mxParsed)) {
      check(`matrix-${name}`, item.pass === true, String(item.detail ?? "").slice(0, 60));
    }
  }

  // ⑤ 无 DevTools 窗口捉虫——精确锚（断言体在 assertCatch，与形态 C 共用）
  assertCatch("", PORT);

  // ── ⑥ R3b 形态 C：release 捉虫通道（builder debug=false + env 端口 → CDP）──
  // facade 语义（desktop/README.md CDP 矩阵）：env PROTON_REMOTE_DEBUGGING_PORT
  // 非空把 debug 0 翻转为 1——release 产物开 CDP 的唯一合法通道，也是「关 F12
  // 形态下仍可捉虫」的通道语义。CI 化 = 钉住该翻转不随 proton 升级漂移。
  // 形态模拟：临时改 app/main.mbt debug=false → release 重建（含 demo dist
  // 生产构建）→ 直跑 exe（不经 proton_cli dev——dev 会强制 PROTON_MODE=dev）。
  // 直跑三坑（本批实测）：asset 相对路径按 **cwd** 解析（spawn 须 cwd=desktop/，
  // 锚错则 entry_load_error 且 page targets 空）；node spawn 直跑无 MSYS 伪加载
  // 错（P 线坑系 MSYS bash 特有）；沙箱会话 %TEMP% 写围栏 → TEMP 指工作区内。
  const srcPath = "app/main.mbt";
  const originalMain = readFileSync(srcPath, "utf8");
  let formCApp: ReturnType<typeof spawn> | null = null;
  try {
    // debug=true, 只在代码行出现（注释行为「debug=true 缺省」无逗号）——替换
    // 计数≠1 即环境变了，fail loud 不猜
    const patched = originalMain.replace("debug=true,", "debug=false,");
    if (patched === originalMain) {
      check("formC-patch", false, "app/main.mbt 中未找到 'debug=true,'（字面变了？连坐更新本探针）");
    } else {
      writeFileSync(srcPath, patched);
      console.log(`[formC] rebuild with debug=false → port ${PORT_C}`);
      const build = spawnSync(PROTON_CLI, ["build", "--", "--release"], {
        cwd: process.cwd(),
        encoding: "utf8",
        timeout: 300_000,
      });
      process.stdout.write((build.stdout ?? "") + (build.stderr ?? ""));
      if (build.status !== 0) {
        check("formC-build", false, `proton_cli build rc=${build.status ?? "signal-" + String(build.signal)}`);
      } else {
        check("formC-build", true, "release 重建绿（debug=false）");
        const exe = "_build/native/release/build/app/app.exe";
        if (!existsSync(exe)) {
          check("formC-exe", false, `产物缺席：${exe}（构建布局变了？）`);
        } else {
          // CEF runtime 四件套：store 布局是内容寻址目录（cef-<hash>-layout-1），
          // glob 发现且要求唯一（多个=fail loud，宁红勿猜错 runtime）
          const storeDir = path.join(homedir(), ".proton", "store", "win32-x64");
          const layouts = existsSync(storeDir)
            ? readdirSync(storeDir).filter((d) => /^cef-.*-layout-1$/.test(d))
            : [];
          if (layouts.length !== 1) {
            check("formC-runtime", false, `~/.proton/store 布局异常（${layouts.length} 个 cef layout：${layouts.join(", ") || "无"}）`);
          } else {
            const runtimeRoot = path.join(storeDir, layouts[0]!, "runtime");
            const helper = path.join(homedir(), ".proton", "helpers", "win32-x64", "0.6.0", "cef_process.exe");
            formCApp = spawn(exe, [], {
              cwd: process.cwd(),
              env: {
                ...process.env,
                PROTON_RUNTIME_ROOT: runtimeRoot,
                PROTON_HELPER_PATH: helper,
                PROTON_PROJECT_CONFIG: path.resolve("proton.project.json"),
                PROTON_REMOTE_DEBUGGING_PORT: PORT_C,
                TEMP: tmpDirShared,
                TMP: tmpDirShared,
                PATH: path.join(runtimeRoot, "bin") + ";" + (process.env["PATH"] ?? ""),
              },
              stdio: ["ignore", "pipe", "pipe"],
            });
            formCApp.stdout?.on("data", (d: Buffer) => process.stdout.write(`[formC-app] ${d}`));
            formCApp.stderr?.on("data", (d: Buffer) => process.stderr.write(`[formC-app!] ${d}`));
            // CDP 探活（轮询 60s——release 直跑实测秒级就绪，dev 段的 120s 是
            // vite+dev server 链路开销，这里不背）
            let formCReady = false;
            const fc0 = Date.now();
            while (Date.now() - fc0 < 60_000) {
              try {
                const r = await fetch(`http://127.0.0.1:${PORT_C}/json/version`, { signal: AbortSignal.timeout(1500) });
                if (r.ok) {
                  const v = (await r.json()) as { Browser?: string };
                  if (v.Browser !== undefined) {
                    formCReady = true;
                    break;
                  }
                }
              } catch {
                // 未就绪
              }
              await sleep(1500);
            }
            check("formC-cdp-ready", formCReady, formCReady ? `ws://127.0.0.1:${PORT_C}（env 翻转 debug 语义在）` : "60s 内未就绪（release 形态 env 端口通道断？）");
            if (formCReady) {
              // release 形态指纹 + 真实渲染：url=proton.localhost（打包 asset 宿主
              // scheme，与 dev 形态 vite URL 互斥）、title 为 demo 生产构建标题
              const probe = runProbe("tools/cdp_probe.mts", [], PORT_C);
              const pe = probe.rc === 0 ? evalField(probe.stdout) : null;
              const url = pe === null ? "" : String(pe["url"] ?? "");
              const title = pe === null ? "" : String(pe["title"] ?? "");
              check("formC-url", url.includes("proton.localhost"), `url=${url}`);
              check("formC-title", title.includes("Vitro"), `title=${title}`);
              // 三虫捕获：关 F12 形态的捉虫通道断言（与 dev 段同锚不同端口）
              assertCatch("formC-", PORT_C);
            }
          }
        }
      }
    }
  } finally {
    if (formCApp !== null && formCApp.pid !== undefined && !formCApp.killed) {
      spawnSync("taskkill", ["/PID", String(formCApp.pid), "/T", "/F"], { stdio: "ignore" });
    }
    writeFileSync(srcPath, originalMain); // 还原 debug=true（幂等：字节级写回原文）
    console.log("[formC] main.mbt 已还原，树已收");
  }
} finally {
  killTree();
}

if (failures.length > 0) {
  console.error(`::error::desktop smoke 红：${failures.join(" / ")}`);
  process.exit(1);
}
console.log("[smoke] 全过");
