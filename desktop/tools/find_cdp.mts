// desktop/tools/find_cdp.mts —— CDP 端口发现：给定 PID，列其 LISTEN 端口，
// 逐个探 /json/version 协议指纹（Browser + Protocol-Version 双键）。
// 场景：builder debug=true 未钉端口时为临时随机端口，日志不可得（独立
// exe 无 stderr 重定向时）——读数字不读日志。零监听端口 ⇒ CDP 关
// （对照组 B 判定依据；注意须先确认窗口已起——挂起实例也是零监听，P 线假阴性实锤）。
// 用法：node tools/find_cdp.mts <pid>
// 仅 Windows（Get-NetTCPConnection）。
import { execFileSync } from "node:child_process";

interface CdpVersion {
  Browser?: string;
  "Protocol-Version"?: string;
  webSocketDebuggerUrl?: string;
}

interface Found {
  port: number;
  browser: string;
  ws: string;
}

const pid = process.argv[2];
if (pid === undefined || !/^\d+$/.test(pid)) {
  console.error("usage: node tools/find_cdp.mts <pid>");
  process.exit(2);
}

let out = "";
try {
  out = execFileSync(
    "powershell",
    [
      "-NoProfile",
      "-c",
      `Get-NetTCPConnection -State Listen -OwningProcess ${pid} -ErrorAction SilentlyContinue | Select-Object -ExpandProperty LocalPort | Sort-Object -Unique`,
    ],
    { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] },
  );
} catch (e) {
  // 零监听端口时 cmdlet 退 1——空结果即答案，不是错误
  const err = e as { stdout?: Buffer | string };
  out = err.stdout === undefined ? "" : String(err.stdout);
}
const ports = out
  .split(/\s+/)
  .map((s) => parseInt(s, 10))
  .filter((n) => Number.isFinite(n) && n > 0);

const found: Found[] = [];
for (const port of ports) {
  try {
    const r = await fetch(`http://127.0.0.1:${port}/json/version`, { signal: AbortSignal.timeout(800) });
    if (r.ok) {
      const v = (await r.json()) as CdpVersion;
      if (v.Browser !== undefined && v["Protocol-Version"] !== undefined) {
        found.push({ port, browser: v.Browser, ws: v.webSocketDebuggerUrl ?? "" });
      }
    }
  } catch {
    // 非 CDP 端口
  }
}
console.log(JSON.stringify({ pid: Number(pid), listen_ports: ports, cdp: found }, null, 2));
