# demo 页（浏览器直调 wasm-gc gateway）

本目录是 Vitro 引擎的静态单页展示面——**零后端、零运行时依赖**（页面本体不发
网络请求到第三方、不跑构建器），浏览器内直接调
[`vitro/engine/gateway`](../moonbit/gateway/) 的 wasm-gc 产物（NDJSON 帧协议
v0.1）。**开发期工具有 npm devDependencies**（typescript + @types/node——仅
类型检查/发射用，不进页面）；源码形态 = TS（`app.ts` + `js/*.ts` 十二模块），
发射产物 `app.js`/`js/*.js` **不入库**（与 `wasm.wasm` 对称，`.gitignore`
在案）。

## 在线版

push 到 master 后由 [pages.yml](../.github/workflows/pages.yml) 自动部署：
<https://rustin-beep.github.io/Vitro/>（首次发布前需在仓库 Settings → Pages 把
Source 设为 "GitHub Actions"——`GITHUB_TOKEN` 无法自动启用 Pages）。

## 本地预览

`wasm.wasm` 与 JS 发射产物都是构建产物，**不入库**——本地起服务前须先备齐两
件；页面用 `fetch` 加载 wasm，`file://` 直开 `index.html` 会被浏览器拒绝，必须
走静态服务器：

```bash
# 1. 构建 wasm（或已有产物可跳过）
cd moonbit && moon build --release --target wasm-gc gateway/wasm && cd ..

# 2. 拷产物到 demo/
cp moonbit/_build/wasm-gc/release/build/gateway/wasm/wasm.wasm demo/

# 3. 发射 JS 产物（TS 源 → 原地发射；不发射页面 404 app.js 白屏）
cd demo && npm ci && npx tsc -p tsconfig.json && cd ..

# 4. 起静态服务器（任选其一）
cd demo && python -m http.server 8931   # http://127.0.0.1:8931/
# 或：npx serve demo
```

浏览器要求：支持 wasm-gc 与 js-string builtins 的现代内核（Chrome/Edge 130+、
Firefox 134+），加载失败页面会显示降级提示。

## 门禁

本页有五路判定闸（全部已接 CI）：

1. **tsc 类型检查**——`cd demo && npx tsc -p tsconfig.json --noEmit`（strict，
   `strictNullChecks` 单档收窄——裁定见 tsconfig 注释）；`tests/` 另有独立
   tsconfig（`@types/node` 面）。
2. `node scripts/demo_smoke/main.js`——对 `cases.js` 每个预置用例实跑协议链并
   逐字节比对 golden，断言渲染所需的响应字段存在，并含 **step 族字段契约**
   （StepPayload 顶层 = 协议 v0.1 十四字段白名单键集全等；LocalVar/CallFrame/
   ArraySnapshot 必备键）。篡改 golden、页面引用字段名漂移、wire 键集漂移即红。
3. `go run ./scripts/demo_ui_lint`——JS↔CSS 字符串契约三路对账：`classList`
   写操作的类名对「CSS 复合单元 ∪ JS 生成面 ∪ 元素候选闭包 ∪ rules.json
   白名单」对账、`var(--x)` 引用对定义面对账、`$("id")` 对 html id 集对账
   （**含 TS 泛型形态 `$<T>("id")`**；动态 className 拼接簇与动态 id 前缀在
   rules.json 显式登记，僵尸条目无条件红）。抓「操作永不生效的类」「引用不存
   在的 CSS 变量」形态——2026-10-02 批的 stdin-row 死类与 `--fg-muted` 幽灵变
   量两实锤即其证红锚。
4. `go run ./scripts/gen_demo_algorithms`——算法侧栏数据发射（**产物不入库**，CI/pages 消费前现场发射；分组并集 == rules.json 43 族 + 82 模板全集对账，发射即闸）。本地起页须先跑此步生成 `algorithms.js`。
5. `node scripts/demo_assemble_check/main.js demo`——组装资源存在性自检
   （index.html script/img 面 + 入口 import 面逐项存在；HTML 抽取面哨兵；
   pages.yml 发布面加 `--no-ts` 断言源不随产物发布）。
6. `node --test demo/tests/pure.test.mts`——纯函数七锚（buildCallTree trie /
   isArrayAnimCase / latin1ToUtf8 / tokenizeC / highlightLines / heapSpanOf /
   esc；**须 node 25**，type stripping 直跑 .ts）。DOM 交互层不硬测，维持
   浏览器实测纪律。

## 诚实边界

- 渲染逻辑暂放宿主页内 TS（门面定位，非架构件）；MoonBit SVG 渲染纯函数包
  落地后由其接管（总计划既定路线）。
- Clang golden 参考值为预置真值（CI shadow 防线持续对拍），页面内无实时
  交叉编译。
- 时间旅行（step 流采集-回放）与算法可视化（「内容」页课程树：43 算法族
  + 变体 + 82 模板全量）均已接 gateway 通道（step.begin/step.next/seek/
  breakpoints.set）；引擎侧行号偏移两族标注边界见 issue #34。
