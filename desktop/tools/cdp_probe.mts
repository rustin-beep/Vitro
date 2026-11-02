// desktop/tools/cdp_probe.mts —— CDP 求值探针：连 proton/CEF DevTools 端点，
// 列目标并在 page 目标上 Runtime.evaluate（awaitPromise+returnByValue）。
// 用法：node tools/cdp_probe.mts <port> [expr | @file]
//   expr 省略 ⇒ 通用读取（url/title/通道形态/引擎版本文本）
//   @file ⇒ 从文件读表达式（绕开 bash→node→JSON→JS 多级转义吃反斜杠——P 线实锤）
// 页内表达式资产：tools/page/（demo_run.js 驱动 demo UI 采集 / fps_probe.js 帧率）
// 输出单个 JSON：{version, targets, eval}
// 依赖：node ≥22 全局 fetch/WebSocket（lib dom 类型面）；零第三方包。
import { readFileSync } from "node:fs";

interface CdpTarget {
  type: string;
  title: string;
  url: string;
  webSocketDebuggerUrl: string;
}

interface CdpVersion {
  Browser: string;
  "Protocol-Version": string;
  webSocketDebuggerUrl: string;
  [key: string]: unknown;
}

interface CdpReply {
  id?: number;
  method?: string;
  result?: { result?: { value?: unknown; type?: string; description?: string } };
  error?: { code: number; message: string };
}

const DEFAULT_EXPR =
  "JSON.stringify({url:location.href, title:document.title, transport:window.__MoonBit__?'ipc':'worker', ver:(document.body.textContent.match(/引擎 [\\d.]+ 协议 [\\w.]+/)||[''])[0]})";

const port = process.argv[2];
if (port === undefined || port === "") {
  console.error("usage: node tools/cdp_probe.mts <port> [expr | @file]");
  process.exit(2);
}
const exprArg = process.argv[3] ?? "";
const expr = exprArg.startsWith("@")
  ? readFileSync(exprArg.slice(1), "utf8")
  : exprArg === "" ? DEFAULT_EXPR : exprArg;

const base = `http://127.0.0.1:${port}`;
const listRes = await fetch(`${base}/json`);
if (!listRes.ok) {
  console.error(`GET /json failed: ${listRes.status}`);
  process.exit(3);
}
const targets = (await listRes.json()) as CdpTarget[];
const verRes = await fetch(`${base}/json/version`);
const version = verRes.ok ? ((await verRes.json()) as CdpVersion) : null;

const page = targets.find((t) => t.type === "page");
if (page === undefined) {
  console.log(JSON.stringify({ version, targets, eval: null, error: "no page target" }));
  process.exit(4);
}

const ws = new WebSocket(page.webSocketDebuggerUrl);
let nextId = 1;
const pending = new Map<number, (msg: CdpReply) => void>();
ws.addEventListener("message", (ev: MessageEvent) => {
  const msg = JSON.parse(String(ev.data)) as CdpReply;
  if (msg.id !== undefined) {
    const cb = pending.get(msg.id);
    if (cb !== undefined) {
      pending.delete(msg.id);
      cb(msg);
    }
  }
});
function send(method: string, params: Record<string, unknown> = {}): Promise<CdpReply> {
  return new Promise((resolve) => {
    const id = nextId++;
    pending.set(id, resolve);
    ws.send(JSON.stringify({ id, method, params }));
  });
}
await new Promise<void>((resolve, reject) => {
  ws.addEventListener("open", () => resolve());
  ws.addEventListener("error", () => reject(new Error("websocket error")));
});
const evalRes = await send("Runtime.evaluate", { expression: expr, returnByValue: true, awaitPromise: true });
const value = evalRes.result?.result?.value;
console.log(
  JSON.stringify(
    {
      version,
      targets: targets.map((t) => ({ type: t.type, title: t.title, url: t.url })),
      eval: value !== undefined ? value : evalRes,
    },
    null,
    2,
  ),
);
ws.close();
