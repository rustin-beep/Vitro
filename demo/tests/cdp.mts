// demo/tests/cdp.mts —— E2E 共享 CDP 客户端（7 个 mjs→mts 迁移批）。
//
// 原 5 份 E2E 脚本各自复制了 msgId/pending/ws/send/evaluate/waitFor 与
// /json/list 重试连接块；本模块把协议边界收成单源，让类型闸能覆盖调用面。
// 协议边界内部允许一次 unknown→泛型断言（CDP 返回形状由调用方按方法约定），
// 其余业务代码仍按最严档检查。
import http from "node:http";

export interface CdpTarget {
  type?: string;
  url?: string;
  webSocketDebuggerUrl?: string;
  [key: string]: unknown;
}

export interface CdpClient {
  send<T = Record<string, unknown>>(method: string, params?: Record<string, unknown>): Promise<T>;
  evaluate<T = unknown>(expr: string): Promise<T>;
  waitFor(expr: string, timeout?: number, step?: number): Promise<boolean>;
  close(): void;
}

export interface CheckResult {
  name: string;
  ok: boolean;
  detail?: string;
}

interface Pending {
  resolve: (value: unknown) => void;
  reject: (err: Error) => void;
}

interface RuntimeEvaluateResponse {
  result?: { value?: unknown };
  exceptionDetails?: { exception?: { description?: string }; text?: string };
}

export const sleep = (ms: number): Promise<void> => new Promise((r) => setTimeout(r, ms));

/** 导航切换窗瞬态错误：Page.navigate / Page.reload 进行中（旧 execution
 *  context 已销毁、新 context 未 commit）时，Runtime.evaluate 报 CDP -32000
 *  「Inspected target navigated or closed」等形态——页面没坏，是查询撞上
 *  导航窗。waitFor 轮询把它当「未就绪」继续等；顶层稳态 evaluate 不捕，
 *  保持 fail loud。实证：PR #344 CI 两次同形态红（run 40691154018 /
 *  40697364478，同 commit），本地快机 Edge 不复现（窗口毫秒级，CI 慢机上
 *  概率显著）；另两类是同窗口的历史形态，一并收编。 */
export function isTransientNavigationError(err: unknown): boolean {
  const msg = err instanceof Error ? err.message : String(err);
  return (
    (msg.includes("-32000") && msg.includes("navigated or closed")) ||
    msg.includes("Execution context was destroyed") ||
    msg.includes("Cannot find context")
  );
}

export interface ConnectOptions {
  port?: number;
  host?: string;
  pageUrlIncludes?: string;
  retries?: number;
  retryDelayMs?: number;
}

/** 连上 headless Chrome/Edge 的 page target；端口未就绪时按 ECONNREFUSED 退避重试。
 *  CDP_PORT 环境变量可改端口（默认 9222）——多会话并行跑 E2E 时各用各的浏览器。 */
export async function connectCdp(opts: ConnectOptions = {}): Promise<CdpClient> {
  const envPort = Number.parseInt(process.env["CDP_PORT"] ?? "", 10);
  const port = opts.port ?? (Number.isFinite(envPort) && envPort > 0 ? envPort : 9222);
  const host = opts.host ?? "127.0.0.1";
  const pageUrlIncludes = opts.pageUrlIncludes ?? "index.html";
  const retries = opts.retries ?? 20;
  const retryDelayMs = opts.retryDelayMs ?? 1000;

  let targets: CdpTarget[] = [];
  for (let attempt = 0; ; attempt++) {
    try {
      targets = await new Promise<CdpTarget[]>((resolve, reject) => {
        http
          .get({ host, port, path: "/json/list" }, (res) => {
            let body = "";
            res.on("data", (chunk: Buffer) => {
              body += chunk;
            });
            res.on("end", () => {
              try {
                resolve(JSON.parse(body) as CdpTarget[]);
              } catch (e) {
                reject(e instanceof Error ? e : new Error(String(e)));
              }
            });
          })
          .on("error", reject);
      });
      break;
    } catch (e) {
      if (attempt >= retries - 1 || !String(e).includes("ECONNREFUSED")) throw e;
      await sleep(retryDelayMs);
    }
  }

  const pages = targets.filter((t) => t.type === "page");
  const page =
    pages.find((t) => (t.url ?? "").includes(pageUrlIncludes)) ?? pages[pages.length - 1];
  if (page === undefined || page.webSocketDebuggerUrl === undefined) {
    throw new Error("CDP 无 page target");
  }

  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise<void>((resolve, reject) => {
    ws.onopen = () => resolve();
    ws.onerror = () => reject(new Error("CDP WebSocket 连接失败"));
  });

  let msgId = 0;
  const pending = new Map<number, Pending>();
  ws.onmessage = (ev: MessageEvent) => {
    const m = JSON.parse(String(ev.data)) as { id?: number; result?: unknown; error?: unknown };
    if (m.id === undefined) return;
    const p = pending.get(m.id);
    if (p === undefined) return;
    pending.delete(m.id);
    if (m.error) p.reject(new Error(JSON.stringify(m.error)));
    else p.resolve(m.result);
  };

  const client: CdpClient = {
    send<T = Record<string, unknown>>(
      method: string,
      params: Record<string, unknown> = {},
    ): Promise<T> {
      const id = ++msgId;
      return new Promise<T>((resolve, reject) => {
        pending.set(id, { resolve: (value) => resolve(value as T), reject });
        ws.send(JSON.stringify({ id, method, params }));
      });
    },
    async evaluate<T = unknown>(expr: string): Promise<T> {
      const r = await client.send<RuntimeEvaluateResponse>("Runtime.evaluate", {
        expression: expr,
        returnByValue: true,
        awaitPromise: true,
      });
      if (r.exceptionDetails) {
        throw new Error(
          "eval 异常: " +
            JSON.stringify(r.exceptionDetails.exception?.description ?? r.exceptionDetails.text),
        );
      }
      return r.result?.value as T;
    },
    async waitFor(expr: string, timeout = 20000, step = 250): Promise<boolean> {
      const t0 = Date.now();
      for (;;) {
        let v: unknown;
        try {
          v = await client.evaluate<unknown>(expr);
        } catch (e) {
          // 撞导航切换窗（瞬态）：视为本轮未就绪继续轮询；其余错误照旧炸出。
          if (!isTransientNavigationError(e)) throw e;
        }
        if (v) return true;
        if (Date.now() - t0 > timeout) throw new Error("waitFor 超时: " + expr.slice(0, 120));
        await sleep(step);
      }
    },
    close(): void {
      ws.close();
    },
  };
  return client;
}
