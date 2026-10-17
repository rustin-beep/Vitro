// Vitro demo · 唯一构建（F4 收尾，2026-10-17，refs #122）。root=demo：
// 入口 index.html（试点页升格）+ src/；tsc 原地发射与旧栈（app.ts/style.css/
// 旧 js 模块）已退役——本配置是唯一构建（npm run build → dist/）。
import { defineConfig, type Plugin } from "vite";
import { readFileSync } from "node:fs";
import path from "node:path";
import { svelte } from "@sveltejs/vite-plugin-svelte";

// 虚拟模块：把 cases.js / algorithms.js（经典 script 全局 const，审阅 D-#4
// 三方契约）以 ESM 形态暴露给 src/ 侧——构建期追加 export 行，**零改动**
// 现役文件（cases.js/algorithms.js/生成器/demo_smoke 全不动）；三方契约
// （export 化四处同批）延后到经典 script 面退役时一次清。TS 类型见
// src/vitro-demo-globals.d.ts。
function demoGlobals(): Plugin {
  const load = (p: string): string => readFileSync(path.resolve(process.cwd(), p), "utf8");
  const wrap = (p: string, name: string): string =>
    `${load(p)}\nexport { ${name} };\n`;
  return {
    name: "vitro-demo-globals",
    resolveId(id) {
      if (id === "virtual:demo-globals") return "\0virtual:demo-globals";
    },
    load(id) {
      if (id === "\0virtual:demo-globals") {
        return (
          wrap("cases.js", "DEMO_CASES") +
          "\n" +
          wrap("algorithms.js", "DEMO_ALGORITHMS")
        );
      }
    },
  };
}

export default defineConfig({
  plugins: [svelte(), demoGlobals()],
  base: "./",
  publicDir: false, // 无 public/；wasm.wasm 经 ?url 由打包器 emit（#139 同款构建期资产）
  build: {
    outDir: "dist",
    emptyOutDir: true,
    rollupOptions: { input: "index.html" },
    // #130 批② 形态裁定（2026-10-17 实测）：语言包被内联进 **worker chunk**
    // （engine.worker 2.9→87KB——vite worker bundle 默认 inlineDynamicImports，
    // advancedChunks 对 worker 不生效）。形态判定 = 可接受且语义吻合：主包
    // 无污染（622KB 为收口批代码自然增量），langpack 随 worker 装载与
    // 「texts.install 在引擎装载后立即注入」的 startup 语义一致。若未来要
    // 独立懒 chunk 需 worker.format="es" + worker 内 advancedChunks，收益
    // （worker 首载省 ~40KB gzip）不抵复杂度。
  },
});
