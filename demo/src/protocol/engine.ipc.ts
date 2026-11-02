// Vitro demo · 引擎 IPC 通道（desktop 批 2026-11-02）——proton 桌面壳内的
// 引擎传输层，与 engine.worker.ts 消息协议逐字相同（{id, op, ...} →
// {id, ok, data | error}），并实现 session.svelte.ts 对 Worker 的全部使用
// 面（postMessage/onmessage/onerror/onmessageerror/terminate）——构造点按
// 环境二选一，浏览器形态零变化。
//
// 桌面形态（desktop/README.md）：引擎不在渲染进程的 wasm 里，而在壳进程
// native 同进程直调 gateway 单口；collect/feed 的编排（step.next 采帧循环、
// output.delta 分页）也在壳进程内闭环——IPC 往返 = 整段一次，与 Worker 内
// 闭环同构。字段映射（bpLines→bp_lines / method→api）在本层完成，Worker
// 形态与 native 命令层（desktop/app/engine_commands.mbt）的键名各自惯用。
"use strict";

export interface EngineTransport {
  postMessage(msg: unknown): void;
  onmessage: ((e: MessageEvent) => void) | null;
  onerror: ((e: ErrorEvent) => void) | null;
  onmessageerror: ((e: MessageEvent) => void) | null;
  terminate(): void;
}

interface IpcOpMessage {
  id: number;
  op: string;
  source?: string;
  cap?: number;
  method?: string;
  params?: Record<string, unknown>;
  bpLines?: number[];
  files?: Array<{ filename: string; source: string }> | undefined;
  cfg?: Record<string, unknown>;
  argv?: string[];
  text?: string;
}

// proton 桥（app_commands_fixture 同形）——demo 无 proton 类型包，就地
// 最小结构声明；桥的真实存在性由 hasDesktopBridge() 运行时判。
interface ProtonBridge {
  core?: { invokeOp?: (op: string, payload: unknown) => Promise<unknown> };
}

declare global {
  interface Window {
    __MoonBit__?: ProtonBridge;
  }
}

/** 是否处于 proton 桌面壳（桥注入判定）。 */
export function hasDesktopBridge(): boolean {
  return (
    typeof window !== "undefined" &&
    typeof window.__MoonBit__?.core?.invokeOp === "function"
  );
}

/** 探针/诊断用：当前引擎通道形态。 */
export function engineTransportKind(): "ipc" | "worker" {
  return hasDesktopBridge() ? "ipc" : "worker";
}

type InvokeOp = (op: string, payload: unknown) => Promise<unknown>;

// 桥就绪等待：demo 的 boot() 在模块顶层就发首帖——桥注入可能晚于脚本
// 执行（渲染早期），poll 兜底而不是硬失败（超时按帖回 error，语义与
// Worker 起不来一致：session 层的「重试」重建通道）。
const BRIDGE_WAIT_TIMEOUT_MS = 5_000;
const BRIDGE_POLL_MS = 25;

let bridgeWait: Promise<InvokeOp> | null = null;

function waitBridge(): Promise<InvokeOp> {
  bridgeWait ??= new Promise<InvokeOp>((resolve, reject) => {
    const t0 = Date.now();
    const probe = (): void => {
      const fn = window.__MoonBit__?.core?.invokeOp;
      if (typeof fn === "function") resolve(fn);
      else if (Date.now() - t0 > BRIDGE_WAIT_TIMEOUT_MS)
        reject(new Error("proton 桥 5s 内未就绪（__MoonBit__.core.invokeOp 缺席）"));
      else setTimeout(probe, BRIDGE_POLL_MS);
    };
    probe();
  });
  return bridgeWait;
}

class IpcTransport implements EngineTransport {
  onmessage: ((e: MessageEvent) => void) | null = null;
  onerror: ((e: ErrorEvent) => void) | null = null;
  onmessageerror: ((e: MessageEvent) => void) | null = null;
  private alive = true;

  postMessage(msg: unknown): void {
    if (!this.alive) return;
    void this.dispatch(msg as IpcOpMessage);
  }

  terminate(): void {
    // 无进程/实例可杀；native 侧 gateway 会话由下一次 collect 的
    // reset() 重建等价语义（Worker 冷启动同构）。
    this.alive = false;
  }

  private reply(m: IpcOpMessage, ok: boolean, payload: unknown): void {
    const data = ok ? { id: m.id, ok: true, data: payload } : { id: m.id, ok: false, error: String(payload) };
    this.onmessage?.(new MessageEvent("message", { data }));
  }

  private async dispatch(m: IpcOpMessage): Promise<void> {
    try {
      const invokeOp = await waitBridge();
      if (m.op === "boot") {
        this.reply(m, true, await invokeOp("app:vitro_versions", {}));
      } else if (m.op === "collect") {
        this.reply(
          m,
          true,
          await invokeOp("app:vitro_collect", {
            source: m.source ?? "",
            cap: m.cap ?? 20000,
            bp_lines: m.bpLines ?? [],
            files: m.files,
            cfg: m.cfg ?? {},
            argv: m.argv,
          }),
        );
      } else if (m.op === "feed") {
        this.reply(m, true, await invokeOp("app:vitro_feed", { text: m.text ?? "", cap: m.cap ?? 20000 }));
      } else if (m.op === "invoke") {
        // 网关单口原样转发（错误帧不折叠——session 层拆帧抛 RpcError）
        this.reply(m, true, await invokeOp("app:vitro_invoke", { api: m.method ?? "", params: m.params ?? {} }));
      } else {
        this.reply(m, false, `未知 op: ${m.op}`);
      }
    } catch (err) {
      this.reply(m, false, (err as Error)?.message ?? err);
    }
  }
}

/** 构造 proton IPC 通道（Worker 同形接口）。 */
export function createIpcTransport(): EngineTransport {
  return new IpcTransport();
}
