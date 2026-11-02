// desktop/tools/cdp_catch.mts —— 捉虫探针：不开任何 DevTools 窗口，经 CDP
// 订阅 Runtime.exceptionThrown / Runtime.consoleAPICalled / Log.entryAdded 三域，
// 注入三枚「虫」（异步未捕获异常 / console.error / 404 资源请求）并回收事件。
// 用法：node tools/cdp_catch.mts <port>
// 预期（P 线实锤）：caught_count ≥ 3——exceptionThrown 带 `at <anonymous>:L:C` 堆栈。
// 零第三方包；node ≥22 全局 fetch/WebSocket。

interface CdpTarget {
  type: string;
  webSocketDebuggerUrl: string;
}

interface ExceptionDetails {
  text: string;
  lineNumber: number;
  url?: string;
  exception?: { description?: string };
}

interface RemoteObject {
  value?: unknown;
  description?: string;
}

interface CdpEvent {
  id?: number;
  method?: string;
  params?: {
    exceptionDetails?: ExceptionDetails;
    type?: string;
    args?: RemoteObject[];
    entry?: { level: string; text?: string };
  };
}

type Caught =
  | { kind: "exceptionThrown"; text: string; desc: string; line: number }
  | { kind: "consoleAPICalled"; type: string; args: string[] }
  | { kind: "logEntry"; level: string; text: string };

const port = process.argv[2];
if (port === undefined || port === "") {
  console.error("usage: node tools/cdp_catch.mts <port>");
  process.exit(2);
}
const targets = (await (await fetch(`http://127.0.0.1:${port}/json`)).json()) as CdpTarget[];
const page = targets.find((t) => t.type === "page");
if (page === undefined) {
  console.error("no page target");
  process.exit(3);
}

const events: Caught[] = [];
const ws = new WebSocket(page.webSocketDebuggerUrl);
let nextId = 1;
const pending = new Map<number, (msg: CdpEvent) => void>();
ws.addEventListener("message", (ev: MessageEvent) => {
  const msg = JSON.parse(String(ev.data)) as CdpEvent;
  if (msg.id !== undefined) {
    const cb = pending.get(msg.id);
    if (cb !== undefined) {
      pending.delete(msg.id);
      cb(msg);
    }
    return;
  }
  const p = msg.params;
  if (msg.method === "Runtime.exceptionThrown" && p?.exceptionDetails !== undefined) {
    const d = p.exceptionDetails;
    events.push({
      kind: "exceptionThrown",
      text: d.text,
      desc: (d.exception?.description ?? "").slice(0, 200),
      line: d.lineNumber,
    });
  } else if (msg.method === "Runtime.consoleAPICalled" && p !== undefined) {
    events.push({
      kind: "consoleAPICalled",
      type: p.type ?? "",
      args: (p.args ?? []).slice(0, 3).map((a) => String(a.value ?? a.description ?? "")),
    });
  } else if (msg.method === "Log.entryAdded" && p?.entry !== undefined) {
    events.push({ kind: "logEntry", level: p.entry.level, text: (p.entry.text ?? "").slice(0, 120) });
  }
});
function send(method: string, params: Record<string, unknown> = {}): Promise<CdpEvent> {
  return new Promise((resolve) => {
    const id = nextId++;
    pending.set(id, resolve);
    ws.send(JSON.stringify({ id, method, params }));
  });
}
const sleep = (ms: number): Promise<void> => new Promise((r) => setTimeout(r, ms));

await new Promise<void>((resolve, reject) => {
  ws.addEventListener("open", () => resolve());
  ws.addEventListener("error", () => reject(new Error("websocket error")));
});
await send("Runtime.enable");
await send("Log.enable");
// 虫①② 发生在页面上下文（非求值结果）：异步抛错 + console.error
await send("Runtime.evaluate", {
  expression: "setTimeout(()=>{ throw new Error('probe-boom-uncaught') },0); console.error('probe-console-err'); 1",
});
await sleep(1200);
// 虫③ 资源 404（网络域形态——proton.localhost 自定义 scheme 对未知资源回 404）
await send("Runtime.evaluate", {
  expression: "fetch('https://proton.localhost/nonexistent-probe.json').catch(e=>console.warn('probe-fetch-fail:'+e.message)); 1",
});
await sleep(800);
console.log(
  JSON.stringify({ port: Number(port), devtools_window_opened: false, caught_count: events.length, caught: events }, null, 2),
);
ws.close();
