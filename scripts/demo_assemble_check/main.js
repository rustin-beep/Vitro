#!/usr/bin/env node
// demo 组装资源存在性自检（2026-10-04 审阅 P2-2/P3-②/P3-③ 单源化）
//
// 缘起：pages.yml 原内联版正则要求 src="./..." 而 index.html 实写
// src="cases.js"（无 ./ 前缀）⇒ HTML 一路恒 0 命中，实测删 cases.js 自检
// 仍绿（缺它 DEMO_CASES 未定义直接白屏）——与该闸当初要堵的历史白屏同类。
// 单源化后 ci.yml（demo/ 原地发射面）与 pages.yml（demo-dist 发布面）双接。
//
// 判据（fail loud，无静默 default）：
//   ① <script src> 抽取面 ≥2（cases.js + app.js）——抽取退化/HTML 结构
//      变更即红（「某一路恒 0 命中不报」形态的定向哨兵）；
//   ② 全部 ref（script/img/app 产物 import 面）逐项存在性断言，缺即红
//      （外链 http(s)/data: 过滤不查）；
//   ③ --no-ts（发布面模式）：目录内出现 .ts/.mts 即红——源不随产物发布
//      （pages.yml 曾 cp -r demo/js 连 .ts 一起上传）。
//
// 用法：node scripts/demo_assemble_check/main.js <目录> [--no-ts]

"use strict";

const fs = require("fs");
const path = require("path");

function die(msg) {
  console.error("[demo_assemble_check] " + msg);
  process.exit(1);
}

const args = process.argv.slice(2);
const noTs = args.includes("--no-ts");
const dir = args.find((a) => !a.startsWith("--"));
if (!dir) die("用法: node scripts/demo_assemble_check/main.js <目录> [--no-ts]");
if (!fs.existsSync(dir) || !fs.statSync(dir).isDirectory()) die(`目录不可读: ${dir}`);

const indexPath = path.join(dir, "index.html");
if (!fs.existsSync(indexPath)) die(`缺 index.html: ${indexPath}`);
const html = fs.readFileSync(indexPath, "utf8");

// ── ① script src 抽取面哨兵（F4 收尾 2026-10-17：旧栈 3 个经典 script →
//   新栈单模块 script + vite 产物 assets/*.js；下限 1，防正则退化恒 0）──
const scriptRefs = [...html.matchAll(/<script[^>]+src="([^"]+)"/g)].map((m) => m[1]);
if (scriptRefs.length < 1) {
  die(
    `HTML <script src> 抽取面 ${scriptRefs.length} < 1——正则退化或 index.html 结构变更` +
      `（审阅 P2-2 形态：src 无 ./ 前缀曾致本路恒 0 命中不报）`
  );
}

// ── ② 收集全部本地资源 ref（script/img src + favicon link href——新栈
//    index.html 带 ./assets/logo 图标，缺了页面无图标但闸要拦）──
const isExternal = (s) => /^(https?:)?\/\//.test(s) || s.startsWith("data:");
const refs = new Set();
for (const m of html.matchAll(/<(script|img)[^>]+src="([^"]+)"/g)) {
  if (!isExternal(m[2])) refs.add(m[2]);
}
for (const m of html.matchAll(/<link[^>]+rel="icon"[^>]+href="([^"]+)"/g)) {
  if (!isExternal(m[1])) refs.add(m[1]);
}
if (noTs) {
  // 发布面（vite 产物）：入口 JS 由 html 的 assets/*.js 引用覆盖，无需 app.js
} else {
  // 源目录面：入口必须是 src/main.ts（vite 的唯一入口）
  const entry = path.join(dir, "src", "main.ts");
  if (!fs.existsSync(entry)) die(`缺入口源 src/main.ts: ${entry}`);
  refs.delete("/src/main.ts");
}

const missing = [];
for (const r of refs) {
  const p = path.join(dir, r.replace(/^\.\//, ""));
  if (!fs.existsSync(p)) missing.push(r);
}
if (missing.length) die(`组装缺资源: ${missing.join(", ")}`);

// ── ③ 发布面禁源（--no-ts）────────────────────────────────
if (noTs) {
  const leaked = [];
  const walk = (d) => {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) {
        if (e.name === "docs") continue; // docs 子站由 docs_preview 组装，不属本闸
        walk(p);
      } else if (/\.(ts|mts)$/.test(e.name)) {
        leaked.push(path.relative(dir, p));
      }
    }
  };
  walk(dir);
  if (leaked.length) die(`发布面含 TS 源（cp -r 应排除/发射产物面只留 .js）: ${leaked.join(", ")}`);
}

console.log(`[demo_assemble_check] ${refs.size} 项本地资源全在${noTs ? "（发布面无 .ts 源）" : ""}: ${dir}`);
