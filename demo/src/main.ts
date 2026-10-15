// Vitro 前端试点入口（F1）。对拍钩子只在带 query 时生效，正常访问零副作用：
//   ?autorun=1  启动即采默认程序
//   ?bench=1    autorun + 1925 帧回放计时（flushSync 同步口径，与 #119 spike
//               同口径可对表；结果挂 window.__pilotBench 与 console）
import { mount, flushSync } from "svelte";
import "./app.css";
import App from "./App.svelte";
import { boot, collect, frameAt, seek, session } from "./session.svelte.ts";
import { DEFAULT_PROGRAM } from "./program.ts";

const app = mount(App, { target: document.getElementById("app")! });

// 验收/对拍钩子（延续 fw_pilot 形态）：浏览器实测经 window.__pilot 操作
(window as unknown as Record<string, unknown>).__pilot = { session, seek, collect, frameAt, DEFAULT_PROGRAM };

const q = new URLSearchParams(location.search);
if (q.has("autorun") || q.has("bench")) {
  boot()
    .then(() => collect(DEFAULT_PROGRAM))
    .then(() => {
      if (!q.has("bench")) return;
      session.batching = true; // 批量推进：FLIP 等交互动画关闭（见 ArrayBars 注）
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
