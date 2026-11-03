// mcp_smoke —— cmd/mcp_js 产物 stdio 冒烟闸（DSH mbt 化批 CI 接线，2026-11-03）。
// 驱动 moon build --release --target js 的单文件产物：协议契约（initialize/
// listChanged）+ 渐进披露（L0 5 → session_open → list_changed → L1 12 → 收回）+
// readOnlyHint + 池语义（run_to 事件停/终局回看）+ 投影（默认 {i,l,f,s} 分页
// + fields/filter）+ render 落盘（301 帧 HTML）+ interactive 无 wasm 回落
// static（CI 无 wasm 资产——恰测回落路径；真 interactive 归本地 accept.mts）。
// 锚值与 mcp_wbtest/accept 同源（bubble.c：1126 步 / swap 7 / 首交换帧 93 行 8
// / stdout "1 2 3 5 8 9 \n" / budget 300 → 301 帧）——引擎行为变更连坐红。
// 用法：node scripts/moonbit/mcp_smoke/main.mts（前置：moon build --release
// --target js cmd/mcp_js；产物路径可用 VITRO_MCP_JS 覆盖，缺产物 fail loud）。
import { spawn } from "node:child_process";
import { existsSync, mkdtempSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";

/// bubble.c（v1 samples 逐字同源——锚值依据，改语料须连坐锚）。
const BUBBLE_C = `#include <stdio.h>

void bubble_sort(int arr[], int n) {
    for (int i = 0; i < n - 1; i++) {
        for (int j = 0; j < n - 1 - i; j++) {
            if (arr[j] > arr[j + 1]) {
                int tmp = arr[j];
                arr[j] = arr[j + 1];
                arr[j + 1] = tmp;
            }
        }
    }
}

int main(void) {
    int arr[6] = {5, 2, 8, 1, 9, 3};
    bubble_sort(arr, 6);
    for (int i = 0; i < 6; i++) printf("%d ", arr[i]);
    printf("\\n");
    return 0;
}
`;

/** 行缓冲累积器：feed 返回本次成行的完整帧（不带换行）；残行留存。 */
export function makeLineAcc(): { feed(chunk: string): string[] } {
  let buf = "";
  return {
    feed(chunk: string): string[] {
      buf += chunk;
      const out: string[] = [];
      let i = buf.indexOf("\n");
      while (i >= 0) {
        const line = buf.slice(0, i).trim();
        if (line.length > 0) out.push(line);
        buf = buf.slice(i + 1);
        i = buf.indexOf("\n");
      }
      return out;
    },
  };
}

/** 工具返回体提取：{isError, text}；畸形 content fail loud（throw）。 */
export function toolTextOf(frame: unknown): { isError: boolean; text: string } {
  const r = (frame as { result?: { content?: Array<{ text?: string }>; isError?: boolean } }).result;
  if (r === undefined || !Array.isArray(r.content) || r.content.length === 0 || r.content[0]?.text === undefined) {
    throw new Error(`toolTextOf: 畸形 tools/call 结果——${JSON.stringify(frame).slice(0, 160)}`);
  }
  return { isError: r.isError === true, text: r.content[0].text };
}

/** 断言账本（纯计数与清单；judgment 由调用方驱动）。 */
export class CheckRun {
  readonly failures: string[] = [];
  #n = 0;
  get total(): number { return this.#n; }
  check(name: string, ok: boolean, detail = ""): void {
    this.#n += 1;
    if (!ok) this.failures.push(detail === "" ? name : `${name} — ${detail}`);
  }
}

interface Frame { id?: number | null; method?: string; result?: unknown; error?: { code: number } }

async function drive(): Promise<number> {
  const product = process.env.VITRO_MCP_JS ?? "moonbit/_build/js/release/build/cmd/mcp_js/mcp_js.js";
  if (!existsSync(product)) {
    console.error(`mcp_smoke: 产物不存在 ${product}——前置 moon build --release --target js cmd/mcp_js`);
    return 2;
  }
  const outDir = mkdtempSync(path.join(tmpdir(), "mcp-smoke-"));
  const srv = spawn(process.execPath, [product], { stdio: ["pipe", "pipe", "pipe"] });
  srv.stderr.on("data", () => { /* 启动横幅等——不判 */ });
  const acc = makeLineAcc();
  const results = new Map<number, Frame>();
  const notifications: string[] = [];
  srv.stdout.on("data", (d) => {
    for (const line of acc.feed(d.toString("utf8"))) {
      const f = JSON.parse(line) as Frame;
      if (f.id !== undefined && f.id !== null) results.set(f.id, f);
      else if (f.method !== undefined) notifications.push(f.method);
    }
  });
  let seq = 0;
  const send = (method: string, params?: Record<string, unknown>): number => {
    const id = ++seq;
    void srv.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, ...(params === undefined ? {} : { params }) }) + "\n");
    return id;
  };
  const wait = (id: number, ms = 90_000): Promise<Frame> =>
    new Promise((resolve, reject) => {
      const t0 = Date.now();
      const iv = setInterval(() => {
        const got = results.get(id);
        if (got !== undefined) { clearInterval(iv); resolve(got); }
        else if (Date.now() - t0 > ms) { clearInterval(iv); reject(new Error(`timeout id=${id}`)); }
      }, 25);
    });
  const call = (name: string, args: Record<string, unknown>): Promise<{ isError: boolean; text: string; frame: Frame }> =>
    wait(send("tools/call", { name, arguments: args })).then((frame) => ({ ...toolTextOf(frame), frame }));
  function body<T>(r: { isError: boolean; text: string }): T {
    return JSON.parse(r.text) as T;
  }

  const chk = new CheckRun();
  try {
    // ── 协议契约 ──
    const init = (await wait(send("initialize", { protocolVersion: "2025-03-05" }))).result as {
      protocolVersion: string; capabilities: { tools: { listChanged: boolean } }; serverInfo: { name: string };
    };
    chk.check("initialize（回显版本 + listChanged）",
      init.capabilities.tools.listChanged === true && init.protocolVersion === "2025-03-05" && init.serverInfo.name === "vitro-dsh-plugin",
      JSON.stringify(init.serverInfo));
    void srv.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
    void await wait(send("ping"));

    // ── L0 披露 + readOnlyHint ──
    const list0 = (await wait(send("tools/list"))).result as { tools: Array<{ name: string; annotations?: { readOnlyHint?: boolean } }> };
    chk.check("L0 = 5 工具",
      list0.tools.map((t) => t.name).join(",") === "animate,diagnose,capabilities,sessions,session_open",
      list0.tools.map((t) => t.name).join(","));
    const ro = new Map(list0.tools.map((t) => [t.name, t.annotations?.readOnlyHint === true]));
    chk.check("readOnlyHint（只读三真 / animate·session_open 假）",
      ro.get("diagnose") === true && ro.get("sessions") === true && ro.get("animate") === false && ro.get("session_open") === false);
    const guard = await call("frames_summary", {});
    chk.check("无会话 L1 守卫（isError + 指向 session_open）",
      guard.isError && guard.text.includes("session_open"), guard.text.slice(0, 60));

    // ── 会话 B：推进式（run_to 事件锚）──
    const openedB = body<{ session_id: string; compile_ok: boolean; algorithm_matches: Array<{ name: string }>; overview: { functions: unknown[] } }>(
      await call("session_open", { source: BUBBLE_C }));
    chk.check("session_open（compile_ok + bubble_sort + overview）",
      openedB.compile_ok && openedB.algorithm_matches?.[0]?.name === "bubble_sort" && openedB.overview.functions.length === 2,
      openedB.session_id);
    await new Promise((r) => setTimeout(r, 80));
    chk.check("解锁通知 list_changed", notifications.includes("notifications/tools/list_changed"));
    const list1 = (await wait(send("tools/list"))).result as { tools: unknown[] };
    chk.check("L1 = 12 工具", list1.tools.length === 12, String(list1.tools.length));
    const rt = body<{ event_step?: number; paused_at?: number; advanced: number }>(
      await call("run_to", { stop_event: "swap" }));
    chk.check("run_to stop_event=swap（首交换帧 93 行 8）",
      rt.event_step === 93 && rt.paused_at === 8 && rt.advanced > 0, JSON.stringify(rt));

    // ── 会话 A：惰性全采 + 投影 + 渲染（显式寻址 B 避免串扰）──
    const openedA = body<{ session_id: string }>(await call("session_open", { source: BUBBLE_C }));
    const summary = body<{ summary: { total: number; vis_events: Record<string, number>; stopped: string }; outputs: { stdout: string } }>(
      await call("frames_summary", { session_id: openedA.session_id }));
    chk.check("frames_summary（1126 / swap 7 / finished）",
      summary.summary.total === 1126 && summary.summary.vis_events.swap === 7 && summary.summary.stopped === "finished",
      `total=${summary.summary.total} vis=${JSON.stringify(summary.summary.vis_events)}`);
    chk.check("stdout 锚", summary.outputs.stdout === "1 2 3 5 8 9 \n", JSON.stringify(summary.outputs.stdout));
    const q = body<{ frames: Array<Record<string, unknown>>; has_more: boolean; to: number }>(
      await call("frames_query", { session_id: openedA.session_id, limit: 5 }));
    const keys = Object.keys(q.frames[0] ?? {}).sort().join(",");
    chk.check("默认投影 {f,i,l,s} + 分页", keys === "f,i,l,s" && q.frames.length === 5 && q.has_more && q.to === 5, keys);
    const q2 = body<{ total: number; frames: Array<{ r?: Record<string, string[]> }> }>(
      await call("frames_query", { session_id: openedA.session_id, fields: ["r"], filter: { has_vis_event: true } }));
    chk.check("fields=r + filter（61 含事件帧）",
      q2.total === 54 + 7 && q2.frames.length === 50 && q2.frames.some((f) => f.r?.arr !== undefined), `total=${q2.total}`);
    const rendered = body<{ ok: boolean; frame_count: number; size_bytes: number; html_path: string }>(
      await call("render", { session_id: openedA.session_id, budget: 300, out_dir: outDir, preview_png: false }));
    chk.check("render（301 帧 HTML 落盘）",
      rendered.ok && rendered.frame_count === 301 && rendered.size_bytes > 50_000 && existsSync(rendered.html_path),
      `${rendered.frame_count} 帧 ${rendered.size_bytes}B`);
    // interactive 回落（CI 无 wasm 资产——恒走回落，恰锁该路径）
    const anim = body<{ ok: boolean; mode: string; frame_count: number; warnings: string[] }>(
      await call("animate", { source: BUBBLE_C, mode: "interactive", out_dir: outDir, preview_png: false }));
    chk.check("animate interactive 无 wasm 回落 static（401 帧 + 回落 warning）",
      anim.ok && anim.mode === "static" && anim.frame_count === 401 && anim.warnings.some((w) => w.includes("回落")),
      `mode=${anim.mode} frames=${anim.frame_count}`);

    // ── 收回披露 ──
    notifications.length = 0;
    await call("session_close", { session_id: openedB.session_id });
    await call("session_close", { session_id: openedA.session_id });
    await new Promise((r) => setTimeout(r, 80));
    const list2 = (await wait(send("tools/list"))).result as { tools: unknown[] };
    chk.check("全关收回（L0 5 + list_changed）",
      list2.tools.length === 5 && notifications.includes("notifications/tools/list_changed"));

    // EOF 退出语义（探针①的产物级复核）：关 stdin → 进程 exit 0
    const exitCode = await new Promise<number>((resolve) => {
      srv.once("exit", (c) => resolve(c ?? -1));
      srv.stdin.end();
    });
    chk.check("EOF 即 exit(0)", exitCode === 0, String(exitCode));
  } catch (e) {
    chk.check("驱动异常（超时/畸形帧）", false, e instanceof Error ? e.message : String(e));
    srv.kill();
  } finally {
    rmSync(outDir, { recursive: true, force: true });
  }
  const stat = existsSync(product) ? `产物 ${Math.round(statSync(product).size / 1024)}KB` : "";
  if (chk.failures.length === 0) {
    console.log(`mcp_smoke: PASS——${chk.total} 项断言全绿（${stat}）`);
    return 0;
  }
  console.error(`mcp_smoke: FAIL——${chk.failures.length}/${chk.total} 项红：`);
  for (const f of chk.failures) console.error(`  ✗ ${f}`);
  return 1;
}

if (process.argv[1] !== undefined && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url) {
  void drive().then((rc) => { process.exit(rc); });
}
