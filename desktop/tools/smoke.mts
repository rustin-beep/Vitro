// desktop/tools/smoke.mts —— CI 全量防线编排：起 proton_cli dev（vite + 壳）→
// CDP 断言集 → 杀树。零第三方依赖；断言逻辑复用 cdp_probe/cdp_catch/page 资产
// （spawnSync 自身 node——单源不复制）。
//
// 用法：node tools/smoke.mts [port]（缺省 9335；cwd 须为 desktop/）
// 前置（CI 步保证）：desktop 与 demo 的 npm ci、demo wasm.wasm + langpack 资产、
//   proton_cli 在 PATH、~/.proton CEF runtime 就位。
//
// 断言集（fail loud，逐条 stderr 标注后 rc=1）：
//   ① CDP 就绪（120s 内 /json/version 协议指纹——vite+壳+桥全链）
//   ② page-ready：title 非空且非 about:blank（≤90s，冷 runner vite 首访慢）
//   ③ demo_run.js 驱动完整采集：transport=ipc（读 window.__vitroTransport
//      实际选择结果，非桥存在性）/ golden ✓ / 42 帧 / 引擎 0.9.1 / stdout
//   ④ cdp_catch：注入虫精确锚（probe-boom-uncaught 异常带堆栈 /
//      probe-console-err / net::ERR 网络域失败——三域各一）
// 退出码：0=全过；1=断言失败；2=用法/环境错。
import { spawn, spawnSync } from "node:child_process";
import { existsSync } from "node:fs";

const PORT = process.argv[2] ?? "9335";
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
console.log(`[smoke] spawn: ${PROTON_CLI} dev（CDP 端口 ${PORT}）`);
const dev = spawn(PROTON_CLI, ["dev"], {
  cwd: process.cwd(),
  env: { ...process.env, PROTON_REMOTE_DEBUGGING_PORT: PORT },
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
function runProbe(script: string, args: string[]): { rc: number; stdout: string } {
  const r = spawnSync(process.execPath, [script, PORT, ...args], {
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

  // ⑤ 无 DevTools 窗口捉虫——精确锚（审阅 P3：caught_count>=N 在页面有
  //    有机异常时也 PASS，须锚到注入的三枚具体虫）
  const catchRun = runProbe("tools/cdp_catch.mts", []);
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
  check("cdp-catch-boom", catchRun.rc === 0 && hasBoom, hasBoom ? "exceptionThrown@probe-boom-uncaught 命中" : `未命中（共 ${caught.length} 事件）`);
  check("cdp-catch-console", catchRun.rc === 0 && hasConsoleErr, `consoleAPICalled@probe-console-err ${hasConsoleErr ? "命中" : "未命中"}`);
  check("cdp-catch-neterr", catchRun.rc === 0 && hasNetErr, `logEntry@net::ERR ${hasNetErr ? "命中" : "未命中"}`);
} finally {
  killTree();
}

if (failures.length > 0) {
  console.error(`::error::desktop smoke 红：${failures.join(" / ")}`);
  process.exit(1);
}
console.log("[smoke] 全过");
