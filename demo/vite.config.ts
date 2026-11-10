// Vitro demo · 唯一构建（F4 收尾，2026-10-17，refs #122）。root=demo：
// 入口 index.html（试点页升格）+ src/；tsc 原地发射与旧栈（app.ts/style.css/
// 旧 js 模块）已退役——本配置是唯一构建（npm run build → dist/）。
import { defineConfig, type Plugin } from "vite";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { homedir } from "node:os";
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

// 第三方许可声明插件（P1 许可合规，2026-11-10）：vite 压缩把注释全剥，
// dist 产物内 @license/Copyright/MIT 命中 0（实测 2026-11-10），而 GitHub
// Pages 线上跑的正是这份产物——MIT「保留版权与许可文本」义务缺承接。
// 本插件在 generateBundle 从 bundle **实际模块表**反查 node_modules 第三方
// 包——不能按 package-lock 的非 dev 口径过滤（devDependencies 里的 svelte
// 运行时实打实进了产物，2026-11-10 实测 svelte.dev 运行时错误链接 19 处），
// 逐包拼 LICENSE 全文发射 THIRD-PARTY-NOTICES.txt（页脚链接可见——MIT
// 「保留版权与许可文本」义务的承接件）。chunk 头部指针走 output.postBanner
// （见 config 内注释）。存在性由 demo_assemble_check 判据 ④（--no-ts 发布
// 面）守（该断言先于本插件落地、对旧产物证红——红→绿纪律）。口径纪律：
// 主构建包清单空即 throw（防 modules 字段缺失静默产出空声明）、LICENSE/
// license 字段缺失一律 fail loud、包名排序输出（字节确定性）。
//
// 双实例分工（engine.worker 是 vite **worker 子构建**，主构建模块表看不到
// 其内部模块——主构建 emit、worker 构建 collect，共享 COLLECTED 合并口径）：
// worker 子构建在主构建 transform 阶段先完成（generateBundle 先跑），
// 主构建 emit 时合并两者反查结果。
type PkgMeta = { version: string; license: string; repo?: string; text: string };
const COLLECTED = new Map<string, PkgMeta>();
const POST_BANNER =
  "/*! Vitro demo — bundled third-party software (CodeMirror, Svelte runtime, ...) is MIT-licensed; " +
  "full copyright & permission notices: THIRD-PARTY-NOTICES.txt */";
function thirdPartyNotices(role: "collect" | "emit"): Plugin {
  const LICENSE_CANDIDATES = ["LICENSE", "LICENSE.md", "LICENSE.txt", "LICENCE", "COPYING"];
  let ssr = false;
  const readLicense = (pkgDir: string, name: string): string => {
    for (const f of LICENSE_CANDIDATES) {
      const p = path.join(pkgDir, f);
      if (existsSync(p)) return readFileSync(p, "utf8").trim();
    }
    throw new Error(`[thirdPartyNotices] ${name}: node_modules 内无 LICENSE 文件（fail loud，禁静默缺声明）`);
  };
  return {
    name: `vitro-third-party-notices-${role}`,
    // SSR 构建（e08）复用本 config——不发射（dist-e08 是 CI 内部测试产物，
    // 非分发面；混入只会造误导性清单）。engineNotices 同款守卫。
    configResolved(c) {
      ssr = !!c.build?.ssr;
    },
    generateBundle(_opts, bundle) {
      if (ssr) return;
      const nmRoot = path.resolve(process.cwd(), "node_modules");
      const ids = new Set<string>();
      for (const out of Object.values(bundle)) {
        if (out.type === "chunk") {
          for (const id of Object.keys(out.modules ?? {})) ids.add(id);
        }
      }
      for (const rawId of ids) {
        const id = rawId.replaceAll("\\", "/");
        const at = id.lastIndexOf("node_modules/");
        if (at < 0) continue;
        // 嵌套依赖取最后一个 node_modules 段；@scope/name 占两段
        const rest = id.slice(at + "node_modules/".length);
        const name = rest.startsWith("@") ? rest.split("/").slice(0, 2).join("/") : rest.split("/")[0];
        if (!name || COLLECTED.has(name)) continue;
        const pkgDir = path.join(nmRoot, name);
        const pj = JSON.parse(readFileSync(path.join(pkgDir, "package.json"), "utf8")) as {
          version?: string;
          license?: string;
          repository?: { url?: string } | string;
        };
        if (!pj.version || !pj.license) {
          throw new Error(`[thirdPartyNotices] ${name}: package.json 缺 version/license 字段（fail loud）`);
        }
        const repo = typeof pj.repository === "string" ? pj.repository : pj.repository?.url;
        COLLECTED.set(name, {
          version: pj.version,
          license: pj.license,
          repo: repo?.replace(/^git\+/, "").replace(/\.git$/, ""),
          text: readLicense(pkgDir, name),
        });
      }
      if (role !== "emit") {
        console.log(`[thirdPartyNotices] worker 子构建反查：累计 ${COLLECTED.size} 包（emit 由主构建负责）`);
        return;
      }
      if (COLLECTED.size === 0) {
        throw new Error(
          "[thirdPartyNotices] bundle 模块表反查出 0 个第三方包——chunk.modules 缺失或产物形态变更，禁静默空声明"
        );
      }
      let source =
        "Vitro demo — third-party software notices\n" +
        "=========================================\n\n" +
        "Generated at build time from the bundle's actual module table\n" +
        "(vite.config.ts :: thirdPartyNotices). Bundled third-party packages\n" +
        "are MIT licensed; full copyright & permission texts follow.\n" +
        "Engine (wasm) side notices: moonbit/THIRD_PARTY.md\n" +
        "— https://github.com/rustin-beep/Vitro\n\n";
      const names = [...COLLECTED.keys()].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
      for (const name of names) {
        const p = COLLECTED.get(name);
        if (!p) throw new Error(`[thirdPartyNotices] 内部不一致：${name} 丢失`);
        source +=
          `── ${name}@${p.version} ──────────────────────────────\n` +
          `license: ${p.license}${p.repo ? `\nsource:   ${p.repo}` : ""}\n\n` +
          `${p.text}\n\n`;
      }
      this.emitFile({ type: "asset", fileName: "THIRD-PARTY-NOTICES.txt", source });
      console.log(`[thirdPartyNotices] THIRD-PARTY-NOTICES.txt: ${COLLECTED.size} 包（license 全文随附）`);
    },
  };
}

// 引擎侧许可声明插件（MoonBit core，2026-11-10）：wasm.wasm / langpack.js
// 由 MoonBit 工具链编译，**core 标准库代码编译进产物随 Pages 分发**——
// Apache-2.0 §4(a) 要求随附许可副本、§4(d) 要求转载 NOTICE 内容（core 的
// NOTICE 含 fdlibm(Sun) / V8 / Go / musl(Arm·Rich Felker) / FreeBSD 归属
// 声明，缺了即违约面；与前端 MIT 不同，Apache 系义务不因无版权头而消失）。
// 发射器读**构建该产物的同一工具链**的 LICENSE/NOTICE（~/.moon/lib/core）
// ——版本随构建自洽，比仓内钉快照无陈旧风险；CI（ci.yml demo job /
// pages.yml）均先 setup-moonbit 后 vite build，路径恒在。文件缺失 fail
// loud。SSR 构建（e08）复用本 config，守卫跳过发射防 dist-e08 混入。
function engineNotices(): Plugin {
  let ssr = false;
  return {
    name: "vitro-engine-notices",
    configResolved(c) {
      ssr = !!c.build?.ssr;
    },
    generateBundle() {
      if (ssr) return;
      const coreDir = path.join(homedir(), ".moon", "lib", "core");
      const p = (f: string): string => path.join(coreDir, f);
      for (const f of ["LICENSE", "NOTICE", "moon.mod"]) {
        if (!existsSync(p(f))) {
          throw new Error(
            `[engineNotices] 缺 ${p(f)}——MoonBit core 许可/NOTICE 不可读，禁静默缺声明（Apache-2.0 §4(a)/(d)）`
          );
        }
      }
      const license = readFileSync(p("LICENSE"), "utf8").trim();
      const notice = readFileSync(p("NOTICE"), "utf8").trim();
      const ver = readFileSync(p("moon.mod"), "utf8").match(/^version\s*=\s*"([^"]+)"/m)?.[1];
      if (!ver) throw new Error("[engineNotices] core/moon.mod 无 version 字段——provenance 戳失败，禁静默");
      const source =
        "Vitro engine artifacts (wasm.wasm / langpack.js) — MoonBit core runtime notices\n" +
        "===============================================================================\n\n" +
        "Generated at build time from the MoonBit toolchain that produced the engine\n" +
        "artifacts. The MoonBit standard library \"core\" (Apache-2.0) is compiled into\n" +
        "these artifacts; per Apache-2.0 §4(a)/(d) its license text and NOTICE contents\n" +
        "(fdlibm / V8 / Go / musl / FreeBSD attributions) follow verbatim.\n" +
        "Vendored moonbitlang/x fs/unicode subset (Apache-2.0, with modification\n" +
        "declarations): moonbit/THIRD_PARTY.md —\n" +
        "https://github.com/rustin-beep/Vitro/blob/master/moonbit/THIRD_PARTY.md\n\n" +
        `── core@${ver} ──────────────────────────────\n` +
        "license: Apache-2.0\n" +
        "copyright: 2026 International Digital Economy Academy (IDEA)\n\n" +
        `${license}\n\n` +
        `── core NOTICE ──────────────────────────────\n\n${notice}\n\n`;
      this.emitFile({ type: "asset", fileName: "ENGINE-NOTICES.txt", source });
      console.log(`[engineNotices] ENGINE-NOTICES.txt: core@${ver}（Apache-2.0 + NOTICE 全文）`);
    },
  };
}

export default defineConfig({
  plugins: [svelte(), demoGlobals(), thirdPartyNotices("emit"), engineNotices()],
  worker: {
    plugins: () => [thirdPartyNotices("collect")],
    rollupOptions: { output: { postBanner: POST_BANNER } },
  },
  base: "./",
  publicDir: false, // 无 public/；wasm.wasm 经 ?url 由打包器 emit（#139 同款构建期资产）
  server: {
    fs: {
      // course/（课程叙述真源）在 demo root 之外——dev 的 ?url 动态 import 走
      // /@fs/ 路径，默认 allow 表只放行 root 内文件 → loadLessonNote 全 404
      // 「Failed to fetch dynamically imported module」（2026-10-18 dev 实测；
      // 生产构建不受影响——build 把 md 发射为哈希资产不走 @fs）。
      allow: [".."],
    },
  },
  build: {
    outDir: "dist",
    emptyOutDir: true,
    rollupOptions: {
      input: "index.html",
      output: {
        // 指针注释必须走 postBanner：rolldown 的 banner/footer 在 renderChunk
        // 前拼、随内置 minify 被剥（类型注释实锤「before renderChunk hook」，
        // 2026-11-10 产物头部实测 0 命中）；postBanner 是「after renderChunk
        // hook and minification」。vite 8 的 rollupOptions = rolldownOptions
        // 别名通道，原生转发。
        postBanner: POST_BANNER,
      },
    },
    // #130 批② 形态裁定（2026-10-17 实测）：语言包被内联进 **worker chunk**
    // （engine.worker 2.9→87KB——vite worker bundle 默认 inlineDynamicImports，
    // advancedChunks 对 worker 不生效）。形态判定 = 可接受且语义吻合：主包
    // 无污染（622KB 为收口批代码自然增量），langpack 随 worker 装载与
    // 「texts.install 在引擎装载后立即注入」的 startup 语义一致。若未来要
    // 独立懒 chunk 需 worker.format="es" + worker 内 advancedChunks，收益
    // （worker 首载省 ~40KB gzip）不抵复杂度。
  },
});
