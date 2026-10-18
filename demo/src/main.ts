// Vitro 前端入口（2026-10-18 前端改造）。验收/对拍钩子只在带 query 时生效，
// 正常访问零副作用：
//   ?autorun=1  启动即采默认程序
//   ?bench=1    autorun + 帧回放计时（flushSync 同步口径，与 #119 spike 同口径）
// 新增 window.__pilot 暴露面：session / ui / lessonSession / progress——浏览器
// 实测（CDP）直接读状态，不靠 DOM 猜。
import { mount, flushSync } from "svelte";
import "./app.css";
import App from "./App.svelte";
import { boot, collect, frameAt, seek, session } from "./session.svelte.ts";
import { ui } from "./ui.svelte.ts";
import { lessonSession } from "./lib/lessonSession.svelte.ts";
import { progress } from "./lib/progress.svelte.ts";
import { workspace } from "./lib/workspace.svelte.ts";
import { BENCH_PROGRAM, DEFAULT_PROGRAM } from "./program.ts";

const app = mount(App, { target: (() => {
  const target = document.getElementById("app")!;
  // index.html 的 #boot-hint 是 bundle 下载期的首帧面；Svelte 5 mount 是
  // **追加**而非替换（实测：不清理则装载提示永久留在页面顶端），此处显式清场。
  target.replaceChildren();
  return target;
})() });

(window as unknown as Record<string, unknown>).__pilot = {
  session, seek, collect, frameAt, DEFAULT_PROGRAM, ui, lessonSession, progress, workspace,
};

const q = new URLSearchParams(location.search);
if (q.has("autorun") || q.has("bench")) {
  boot()
    .then(() => collect(BENCH_PROGRAM)) // 基准钩子固定跑冒泡基准
    .then(() => {
      if (!q.has("bench")) return;
      session.batching = true; // 批量推进：FLIP 等交互动画关闭
      const t0 = performance.now();
      for (let i = 0; i < session.frames.length; i += 1) {
        session.idx = i;
        flushSync(); // 与 spike 同口径：逐帧强制同步刷
      }
      session.batching = false;
      seek(session.frames.length - 1);
      const ms = performance.now() - t0;
      const per = (ms / Math.max(session.frames.length, 1)) * 1000;
      session.perf.replayPerFrameUs = Math.round(per);
      // eslint-disable-next-line no-console
      console.log(`[pilot-bench] frames=${session.frames.length} total=${ms.toFixed(1)}ms perFrame=${per.toFixed(1)}µs`);
      (window as unknown as Record<string, unknown>).__pilotBench = {
        frames: session.frames.length,
        totalMs: ms,
        perFrameUs: per,
      };
    })
    .catch((err) => {
      session.status = "钩子失败：" + String((err as Error).message);
    });
}

export default app;
