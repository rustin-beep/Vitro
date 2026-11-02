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
    /** 实际选定的引擎通道（选择结果非桥存在性——PR #417 审阅 P1-2：
     *  取值式 __MoonBit__?ipc:worker 对「真走哪臂」零判别力）。 */
    __vitroTransport?: "ipc" | "worker";
  }
}

/** 是否处于 proton 桌面壳（桥注入判定）。 */
export function hasDesktopBridge(): boolean {
  return (
    typeof window !== "undefined" &&
    typeof window.__MoonBit__?.core?.invokeOp === "function"
  );
}

/** 是否**可能**处于 proton 桌面壳（不等桥）：dev 形态入口由 desktop 的
 *  proton.project.json dev_url 带 ?shell 标记（proton_cli 以 PROTON_FRONTEND_URL
 *  覆盖窗口 entry）；打包形态页面在 proton.localhost 自定义 scheme 宿主。
 *  浏览器直开（无标记）不满足——通道选择零等待回 Worker。 */
function maybeInDesktopShell(): boolean {
  // 非浏览器环境（探针 stub）两者皆缺——判否走零等待 Worker 分支
  if (typeof window === "undefined" || typeof location === "undefined") return false;
  return location.host === "proton.localhost" || new URLSearchParams(location.search).has("shell");
}

/** 探针/诊断用：桥**当前**是否在（注意：这不等于通道选择结果）。 */
export function engineTransportKind(): "ipc" | "worker" {
  return hasDesktopBridge() ? "ipc" : "worker";
}

// 通道选择（PR #417 审阅 P1-1/P1-2 处置）三段式：
// ① 桥已在（壳内注入早于页面脚本——常见）⇒ IPC，零等待；
// ② 桥未在但处于壳（dev_url 标记 / proton.localhost）⇒ 轮询 2s 等注入
//    （CI runner 实锤注入可晚于首条 rpc，2s 窗口内命中即 IPC）；
// ③ 浏览器（无标记无桥）⇒ 立即 Worker——零固定等待（旧形态所有宿主都
//    白等满窗，线上首屏 +2s——审阅探针 A_no_bridge 实测 2011ms）。
const BRIDGE_SELECT_WAIT_MS = 2_000;
const BRIDGE_SELECT_POLL_MS = 25;

let activeKind: "ipc" | "worker" = "worker";

/** 实际选定的通道形态（选择结果，供 smoke/探针断言）。 */
export function activeTransportKind(): "ipc" | "worker" {
  return activeKind;
}

function markKind(kind: "ipc" | "worker"): void {
  activeKind = kind;
  if (typeof window !== "undefined") window.__vitroTransport = kind;
}

/** 构造引擎通道（三段式选择，见上）：壳内桥在/将到走 native IPC，
 *  浏览器零等待回 Web Worker。 */
export async function createEngineTransport(): Promise<EngineTransport> {
  if (hasDesktopBridge()) {
    markKind("ipc");
    return createIpcTransport();
  }
  if (maybeInDesktopShell()) {
    const t0 = Date.now();
    while (Date.now() - t0 < BRIDGE_SELECT_WAIT_MS) {
      await new Promise((r) => setTimeout(r, BRIDGE_SELECT_POLL_MS));
      if (hasDesktopBridge()) {
        markKind("ipc");
        return createIpcTransport();
      }
    }
  }
  markKind("worker");
  return new Worker(new URL("./engine.worker.ts", import.meta.url), { type: "module" });
}

type InvokeOp = (op: string, payload: unknown) => Promise<unknown>;

// 桥就绪等待：demo 的 boot() 在模块顶层就发首帖——桥注入可能晚于脚本
// 执行（渲染早期），poll 兜底而不是硬失败（超时按帖回 error，语义与
// Worker 起不来一致：session 层的「重试」重建通道）。
const BRIDGE_WAIT_TIMEOUT_MS = 5_000;
const BRIDGE_POLL_MS = 25;

let bridgeWait: Promise<InvokeOp> | null = null;

function waitBridge(): Promise<InvokeOp> {
  if (bridgeWait === null) {
    const p = new Promise<InvokeOp>((resolve, reject) => {
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
    // 负缓存（PR #417 审阅 P2-1）：失败的 Promise 若留在模块级，「重试」
    // 重建通道后仍拿到旧失败值——重试永久失效。失败即弃缓存，下次重探。
    void p.catch(() => {
      if (bridgeWait === p) bridgeWait = null;
    });
    bridgeWait = p;
  }
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
