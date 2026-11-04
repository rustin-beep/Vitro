// accept —— stdio 黑盒验收（v2 mbt 化版；2026-11-03 建 / 2026-11-04 收编入仓
// ——原 D:/tmp/vitro-dsh-plugin/accept.mts 仓外件，PR #457 审阅 v2 P3-④ 销案）。
// 对 cmd/mcp_js 的 moon js 产物跑（VITRO_MCP_JS 覆盖路径；缺省 = 仓库根相对
// release 构建——与 mcp_smoke 同源）。断言面：initialize / 披露切换（L0 5 →
// session_open → list_changed → L1 12 → close 收回）/ readOnlyHint / 会话池
// （LRU 逐出 / 死会话可操作错误 / 缓冲复用）/ 每工具 happy path / 投影页边界 /
// 错误帧形态 / run_to 断点与事件停 / step_next 关键帧 / render+animate 产物。
// TTL 5 分钟过期无法黑盒假钟——白盒 mcp_wbtest::mcp_pool_ttl_expiry 覆盖。
// PNG 预览断言仅本地跑（依赖本机 Edge/Chrome 截图，CI 无浏览器跳过——审阅
// 「PNG 截图链路未覆盖」的诚实边界，本地形态全 28 断言）。
import { spawn } from "node:child_process";
import { existsSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

const PRODUCT = process.env.VITRO_MCP_JS ?? "moonbit/_build/js/release/build/cmd/mcp_js/mcp_js.js";
if (!existsSync(PRODUCT)) {
  console.error(`accept: 产物不存在 ${PRODUCT}（先 moon build --release --target js cmd/mcp_js）`);
  process.exit(2);
}
const OUT_DIR = mkdtempSync(path.join(tmpdir(), "mcp-accept-"));
const { VITRO_MCP_WASM: _wasmDrop, ...ENV } = process.env;
const srv = spawn(process.execPath, [PRODUCT], { stdio: ["pipe", "pipe", "pipe"], env: ENV });
srv.stderr.on("data", (d) => process.stderr.write("[srv] " + d));

/// bubble.c（v1 samples 逐字同源——锚值依据与 mcp_smoke/BUBBLE_C 同源，改语料须连坐锚）。
const bubble = `#include <stdio.h>

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

/// bad.c（v1 samples 逐字同源——E2005 锚：缺分号 + 未声明 y 两诊断）。
const bad = `#include <stdio.h>

int main(void) {
    int x = 5
    printf("%d\\n", y);
    return 0;
}
`;

interface Frame { id?: number | null; method?: string; result?: unknown; error?: { code: number; message: string } }
const results = new Map<number, Frame>();
const notifications: string[] = [];
let buf = "";
srv.stdout.on("data", (d) => {
  buf += d;
  let i: number;
  while ((i = buf.indexOf("\n")) >= 0) {
    const line = buf.slice(0, i).trim();
    buf = buf.slice(i + 1);
    if (!line) continue;
    const f = JSON.parse(line) as Frame;
    if (f.id !== undefined && f.id !== null) results.set(f.id as number, f);
    else if (f.method) notifications.push(f.method);
  }
});
let seq = 0;
const send = (method: string, params?: unknown): number => {
  const id = ++seq;
  void srv.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, ...(params === undefined ? {} : { params }) }) + "\n");
  return id;
};
const call = (name: string, args: Record<string, unknown>): number =>
  send("tools/call", { name, arguments: args });
const wait = (id: number, ms = 60000): Promise<Frame> =>
  new Promise((res, rej) => {
    const t0 = Date.now();
    const iv = setInterval(() => {
      const got = results.get(id);
      if (got !== undefined) { clearInterval(iv); res(got); }
      else if (Date.now() - t0 > ms) { clearInterval(iv); rej(new Error(`timeout id=${id}`)); }
    }, 30);
  });
const rpc = async (method: string, params?: unknown): Promise<Frame> => wait(send(method, params));
const tool = async <T,>(name: string, args: Record<string, unknown>): Promise<T> => {
  const f = await wait(call(name, args));
  if (f.error) throw new Error(`tool ${name} 协议错: ${JSON.stringify(f.error)}`);
  const r = f.result as { content: Array<{ type: string; text?: string; data?: string }>; isError: boolean };
  if (r.isError) throw new Error(`tool ${name} isError: ${r.content[0]?.text ?? ""}`);
  return JSON.parse(r.content[0]!.text!) as T;
};
const toolExpectError = async (name: string, args: Record<string, unknown>): Promise<string> => {
  const f = await wait(call(name, args));
  const r = f.result as { content: Array<{ text?: string }>; isError: boolean };
  if (!r.isError) throw new Error(`tool ${name} 期望 isError`);
  return r.content[0]?.text ?? "";
};

let fails = 0;
const chk = (name: string, ok: boolean, detail = ""): void => {
  console.log(`${ok ? "PASS" : "FAIL"} ${name}${detail ? " — " + detail : ""}`);
  if (!ok) fails++;
};

try {
  // ── 1. initialize ──
  const init = (await rpc("initialize", { protocolVersion: "2025-03-05" })).result as {
    protocolVersion: string;
    capabilities: { tools: { listChanged: boolean } };
    serverInfo: { name: string; version: string };
  };
  chk("initialize（回显客户端版本 + listChanged:true）",
    init.capabilities.tools.listChanged === true && init.protocolVersion === "2025-03-05" && init.serverInfo.name === "vitro-dsh-plugin",
    JSON.stringify(init.serverInfo));
  void srv.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");

  // ── 2. 无会话：L0 恰 5 工具 ──
  const list0 = (await rpc("tools/list")).result as { tools: Array<{ name: string; annotations?: { readOnlyHint?: boolean } }> };
  const names0 = list0.tools.map((t) => t.name);
  chk("无会话 tools/list = L0 5 工具",
    names0.join(",") === "animate,diagnose,capabilities,sessions,session_open",
    names0.join(","));

  // ── 3. readOnlyHint ──
  const byName = new Map(list0.tools.map((t) => [t.name, t.annotations?.readOnlyHint]));
  chk("readOnlyHint（diagnose/capabilities/sessions true；animate/session_open false）",
    byName.get("diagnose") === true && byName.get("capabilities") === true && byName.get("sessions") === true && byName.get("animate") === false && byName.get("session_open") === false);

  // ── 4. 无会话 L1 守卫（错误形态 = isError 可操作文案）──
  const guardText = await toolExpectError("frames_summary", {});
  chk("L1 无会话守卫（isError + 文案指向 session_open）", guardText.includes("session_open"), guardText.slice(0, 60));

  // ── 5. capabilities 渐进披露段 ──
  const caps = await tool<{ progressive_disclosure: { available_now: string[]; unlocked_by: string; unlocks: string[]; state: string } }>("capabilities", {});
  chk("capabilities 渐进披露段",
    caps.progressive_disclosure.available_now.length === 5 &&
    caps.progressive_disclosure.unlocked_by === "session_open(source)" &&
    caps.progressive_disclosure.unlocks.length === 7,
    `state=${caps.progressive_disclosure.state}`);

  // ── 6. session_open + 披露解锁 ──
  const opened = await tool<{ session_id: string; compile_ok: boolean; algorithm_matches: Array<{ name: string }>; overview: { functions: Array<{ name: string; lines: number[] }> } }>("session_open", { source: bubble });
  chk("session_open（compile_ok + bubble_sort + overview）",
    opened.compile_ok === true && opened.algorithm_matches?.[0]?.name === "bubble_sort" && opened.overview.functions.length === 2,
    `${opened.session_id} funcs=${opened.overview.functions.map((f) => f.name).join("/")}`);
  await new Promise((r) => setTimeout(r, 100));
  chk("session_open 后 list_changed 通知", notifications.includes("notifications/tools/list_changed"));
  const list1 = (await rpc("tools/list")).result as { tools: Array<{ name: string }> };
  chk("解锁后 tools/list = 12 工具", list1.tools.length === 12, String(list1.tools.length));

  // ── 7. frames_summary（惰性全采 + v1 同源锚）──
  const summary = await tool<{ summary: { total: number; vis_events: Record<string, number>; swap_pairs: number[][]; arrays: Array<{ name: string; len: number; mutations: number }>; stopped: string }; outputs: { stdout: string } }>("frames_summary", {});
  chk("frames_summary（1126 步 / swap 7 / compare 54 / finished）",
    summary.summary.total === 1126 && summary.summary.vis_events.swap === 7 && summary.summary.vis_events.compare === 54 && summary.summary.stopped === "finished",
    `total=${summary.summary.total} vis=${JSON.stringify(summary.summary.vis_events)}`);
  chk("frames_summary（stdout 锚 + 数组 mutations）",
    summary.outputs.stdout === "1 2 3 5 8 9 \n" && summary.summary.arrays[0]?.name === "arr" && summary.summary.arrays[0]?.mutations > 0,
    `stdout=${JSON.stringify(summary.outputs.stdout)}`);

  // ── 8. frames_query 默认投影 + 分页 ──
  const q = await tool<{ total: number; from: number; to: number; has_more: boolean; frames: Array<Record<string, unknown>> }>("frames_query", { limit: 5 });
  const projKeys = Object.keys(q.frames[0]!).sort().join(",");
  chk("frames_query 默认投影 {f,i,l,s}（无扩展字段）",
    projKeys === "f,i,l,s" && q.frames.length === 5 && q.has_more === true && q.total === 1126,
    `keys=${projKeys} n=${q.frames.length}`);

  // ── 9. fields=r + filter has_vis_event ──
  const q2 = await tool<{ total: number; frames: Array<{ r?: Record<string, string[]> }> }>("frames_query", { fields: ["r"], filter: { has_vis_event: true }, limit: 50 });
  chk("frames_query fields=r + filter（含事件帧 61）",
    q2.total === 54 + 7 && q2.frames.length === 50 && q2.frames.some((f) => f.r?.arr !== undefined),
    `total=${q2.total}`);

  // ── 10. 投影页边界 ──
  const q3 = await tool<{ from: number; to: number; frames: unknown[] }>("frames_query", { from: 1120 });
  chk("投影页边界（from 钳界 / to=总帧不含）", q3.from === 1120 && q3.to === 1126 && q3.frames.length === 6, `from=${q3.from} to=${q3.to}`);

  // ── 11. 错误帧形态：limit>50 → JSON-RPC -32602 ──
  const badLimit = await wait(call("frames_query", { limit: 51 }));
  chk("limit>50 → 协议错 -32602", badLimit.error?.code === -32602, JSON.stringify(badLimit.error));
  const badTool = await wait(call("no_such", {}));
  chk("未知工具 → 协议错 -32602", badTool.error?.code === -32602, JSON.stringify(badTool.error));

  // ── 12. 会话 B（推进式路径：事件停→断点停→终局→回看提示）──
  const B = await tool<{ session_id: string }>("session_open", { source: bubble });
  const rt1 = await tool<{ advanced: number; paused_at?: number; event_step?: number; stopped: string }>("run_to", { stop_event: "swap" });
  chk("run_to stop_event=swap（首交换帧 93 行 8）",
    rt1.event_step === 93 && rt1.paused_at === 8 && rt1.advanced > 0,
    JSON.stringify(rt1));
  const rt2 = await tool<{ paused_at?: number; advanced: number }>("run_to", { breakpoint_line: 8 });
  chk("run_to breakpoint_line=8（断点停）", rt2.paused_at === 8 && rt2.advanced > 0, `paused_at=${rt2.paused_at} advanced=${rt2.advanced}`);
  const rt3 = await tool<{ stopped: string; advanced: number; next?: string }>("run_to", { max_frames: 20000 });
  chk("run_to 到终局", rt3.stopped === "finished" && rt3.advanced > 0, rt3.stopped);
  const rt4 = await tool<{ advanced: number; next?: string }>("run_to", { stop_event: "swap" });
  chk("终局后 run_to（零推进 + 回看提示）", rt4.advanced === 0 && (rt4.next ?? "").includes("frames_query"), JSON.stringify(rt4));
  const sn0 = await tool<{ keyframes: number; next?: string }>("step_next", { n: 1 });
  chk("step_next 终局会话（零关键帧 + 回看提示）", sn0.keyframes === 0 && (sn0.next ?? "").includes("frames_query"));
  const C = await tool<{ session_id: string }>("session_open", { source: bubble });
  const sn = await tool<{ advanced: number; keyframes: number; frames: Array<{ i: number; l: number; f: string; s: string }> }>("step_next", { n: 3 });
  chk("step_next 活会话（3 关键帧 + 紧凑投影）", sn.keyframes === 3 && sn.frames.length === 3 && sn.frames.every((f) => "i" in f && "s" in f), `k=${sn.keyframes}`);
  void C;

  // ── 13. annotations（显式寻址 A——B 只推进了部分）──
  const an = await tool<{ annotations: { total: number; events: Array<{ kind: string; pair?: number[] }> } }>("annotations", { session_id: opened.session_id, kind: "swap" });
  chk("annotations swap（7 事件 + 首对 [0,1]）",
    an.annotations.total === 7 && an.annotations.events[0]?.pair?.[0] === 0 && an.annotations.events[0]?.pair?.[1] === 1,
    `total=${an.annotations.total}`);

  // ── 14. 会话复用（A 显式寻址，缓冲稳定）──
  const again = await tool<{ total: number }>("frames_query", { session_id: opened.session_id, limit: 1 });
  chk("会话复用（显式 session_id 寻址）", again.total === 1126, `total=${again.total}`);

  // ── 15. render（A 全量缓冲 → 301 帧）──
  const rendered = await tool<{ ok: boolean; html_path: string; frame_count: number; size_bytes: number; preview_png_path?: string; ms: { render: number } }>("render", { session_id: opened.session_id, budget: 300, out_dir: OUT_DIR, preview_png: false });
  chk("render（301 帧 HTML 落盘 >50KB）",
    rendered.ok === true && rendered.frame_count === 301 && rendered.size_bytes > 50000 && existsSync(rendered.html_path),
    `${rendered.frame_count} 帧 ${rendered.size_bytes}B`);
  // PNG 预览（image 块）仅本地跑——CI 无 Edge/Chrome，条件跳过不计数
  if (process.env.CI === undefined) {
    const withPng = await tool<{ preview_png_path?: string }>("render", { session_id: opened.session_id, budget: 300, out_dir: OUT_DIR, preview_png: true });
    const pngFrame = results.get(seq)!.result as { content: Array<{ type: string; data?: string }> };
    chk("render PNG 预览（image 块）",
      pngFrame.content.length === 2 && pngFrame.content[1]!.type === "image" && (pngFrame.content[1]!.data?.length ?? 0) > 5000,
      withPng.preview_png_path ?? "无");
  }

  // ── 16. LRU 逐出（池上限 8：第 9 开逐最旧）──
  for (let i = 0; i < 9; i++) {
    await tool("session_open", { source: "int main(){return 0;}" });
  }
  const evicted = await toolExpectError("frames_query", { session_id: B.session_id, limit: 1 });
  chk("LRU 逐出（最旧会话死——可操作错误）", evicted.includes("不存在或已过期"), evicted.slice(0, 60));

  // ── 17. sessions ──
  const ss = await tool<{ sessions: Array<{ session_id: string; frames_collected: number; expires_in_s: number }> }>("sessions", {});
  chk("sessions 列表（恰 8 条 + 剩余寿命）",
    ss.sessions.length === 8 && ss.sessions.every((s) => s.expires_in_s > 0 && s.expires_in_s <= 300),
    `n=${ss.sessions.length}`);

  // ── 18. animate happy path ──
  const anim = await tool<{ ok: boolean; frame_count: number; raw_step_count: number; algorithm_detected: { name: string } | null; size_bytes: number }>("animate", { source: bubble, budget: 400, out_dir: OUT_DIR, preview_png: false });
  chk("animate（static 401 帧 / 1126 原始步 / 算法识别）",
    anim.ok === true && anim.frame_count === 401 && anim.raw_step_count === 1126 && anim.algorithm_detected?.name === "bubble_sort",
    `${anim.frame_count}/${anim.raw_step_count}`);

  // ── 19. animate 编译错（诊断卡）——ok 语义 = 产物已落盘（审阅 v2 P3-② 翻面：
  // 修前断言 ok:false；编译态看 compile_ok，诊断卡 html_path 仍在响应体可交付）──
  const animBad = await tool<{ ok: boolean; compile_ok: boolean; frame_count: number; html_path: string; warnings: string[] }>("animate", { source: bad, out_dir: OUT_DIR, preview_png: false });
  chk("animate 编译错（诊断卡 HTML 落盘 + E2005 warning + compile_ok=false）",
    animBad.ok === true && animBad.compile_ok === false && animBad.frame_count === 0 && existsSync(animBad.html_path) && animBad.warnings.some((w) => w.includes("E2005")),
    animBad.html_path);

  // ── 20. diagnose ──
  const diag = await tool<{ ok: boolean; diagnostics: Array<{ code: string; message?: string; fix_suggestion?: string }> }>("diagnose", { source: bad });
  chk("diagnose（E2005 + 修复建议）",
    diag.ok === false && diag.diagnostics[0]?.code === "E2005" && typeof diag.diagnostics[0]?.fix_suggestion === "string",
    diag.diagnostics[0]?.message);

  // ── 21. 收回披露 ──
  notifications.length = 0;
  let closedCount = 0;
  for (let i = 0; i < 8; i++) {
    await tool("session_close", {});
    closedCount++;
  }
  await new Promise((r) => setTimeout(r, 100));
  const list2 = (await rpc("tools/list")).result as { tools: Array<{ name: string }> };
  chk("全关后披露收回（L0 5 + list_changed）",
    list2.tools.length === 5 && notifications.includes("notifications/tools/list_changed"),
    `closed=${closedCount} tools=${list2.tools.length}`);
} finally {
  srv.kill();
  rmSync(OUT_DIR, { recursive: true, force: true });
}
console.log(`\n验收完成：${fails === 0 ? "全绿" : `${fails} 失败`}`);
process.exit(fails ? 1 : 0);
