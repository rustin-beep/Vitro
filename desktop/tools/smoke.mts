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
//   ② 缺省读数：transport=ipc（IPC 通道激活而非 wasm Worker）+ 页 title
//   ③ demo_run.js 驱动完整采集：golden ✓ / 42 帧 / 引擎 0.9.1 / stdout=1 2 3 4 5
//   ④ cdp_catch：无 DevTools 窗口 caught_count ≥ 3（exceptionThrown/console/Log）
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
  if (dev.pid !== undefined && !dev.killed) {
    spawnSync("taskkill", ["/PID", String(dev.pid), "/T", "/F"], { stdio: "ignore" });
  }
  // 兜底：逃逸树外的同名进程（CEF 子进程模型下 dev 树收不净的残余）
  for (const img of ["app.exe", "cef_process.exe", "proton_cli.exe"]) {
    spawnSync("taskkill", ["/IM", img, "/F"], { stdio: "ignore" });
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

try {
  // ① CDP 就绪
  const cdpOk = await waitCdp();
  check("cdp-ready", cdpOk, cdpOk ? `ws://127.0.0.1:${PORT}` : `${DEV_TIMEOUT_MS}ms 内未就绪`);
  if (!cdpOk) {
    await diagnoseNotReady();
    throw new Error("CDP 未就绪，后续断言跳过");
  }

  // ② 现场信息行（页面加载前 title 可为空、桥可能未注入——不作断言，
  //    断言挂 ③ demo_run 的 transport 字段：页面加载后采样，桥在必命中）
  const base = runProbe("tools/cdp_probe.mts", []);
  const baseEval = base.rc === 0 ? evalField(base.stdout) : null;
  console.log(
    `INFO  page — ${baseEval === null ? `probe rc=${base.rc}` : `title=${String(baseEval["title"])} url=${String(baseEval["url"])}`}`,
  );

  // ③ demo 完整采集断言（transport/golden/帧数/版本/stdout——基线 2026-11-02）
  const run = runProbe("tools/cdp_probe.mts", ["@tools/page/demo_run.js"]);
  const dr: DemoRunResult | null = run.rc === 0 ? (evalField(run.stdout) as DemoRunResult | null) : null;
  if (dr === null) {
    check("demo-run", false, `probe rc=${run.rc}（采集探针失败）`);
  } else if (dr.error !== undefined) {
    check("demo-run", false, String(dr.error));
  } else {
    // transport=ipc = 走 native 同进程引擎；worker = 桥缺席静默回退 wasm 臂
    // （四轮前缺省读数时序假阴性实锤——构造点已改等待式选择，此处兜底）
    check("transport-ipc", dr.transport === "ipc", `transport=${dr.transport}`);
    check("demo-golden", (dr.status ?? "").includes("golden ✓"), `status=${dr.status} seek=${dr.seek}`);
    check("demo-frames", dr.frames === "42", `frames=${dr.frames}`);
    check("demo-engine", (dr.ver ?? "").includes("0.9.1"), `ver=${dr.ver}`);
    check("demo-stdout", (dr.stdout ?? "").startsWith("1 2 3 4 5"), `stdout=${dr.stdout}`);
  }

  // ④ 无 DevTools 窗口捉虫
  const catchRun = runProbe("tools/cdp_catch.mts", []);
  const caught = Number((catchRun.stdout.match(/"caught_count"\s*:\s*(\d+)/) ?? ["", "-1"])[1]);
  check("cdp-catch", catchRun.rc === 0 && caught >= 3, `caught_count=${caught}`);
} finally {
  killTree();
}

if (failures.length > 0) {
  console.error(`::error::desktop smoke 红：${failures.join(" / ")}`);
  process.exit(1);
}
console.log("[smoke] 全过");
