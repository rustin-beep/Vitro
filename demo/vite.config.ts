// Vitro demo · Svelte 5 试点构建（F1，refs #119/#122）。root=demo：试点与
// 现役 demo 共根（dev 时可 import js/types.ts 等 TS 源）；正式入口 index.html
// 仍走 tsc 原地发射（零构建纪律），试点入口 src/pilot.html 单独打包——F4 全量
// 替换时本配置升格为唯一构建（input 换 index.html、outDir 换 dist）。
import { defineConfig } from "vite";
import { svelte } from "@sveltejs/vite-plugin-svelte";

export default defineConfig({
  plugins: [svelte()],
  base: "./",
  publicDir: false, // 无 public/；wasm.wasm 经 new URL(..., import.meta.url) 由打包器 emit
  build: {
    outDir: "dist-pilot",
    emptyOutDir: true,
    rollupOptions: { input: "src/pilot.html" },
  },
});
