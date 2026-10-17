# demo 页（浏览器直调 wasm-gc gateway）

本目录是 Vitro 引擎的静态单页展示面——**零后端、零运行时依赖**（页面本体不发
网络请求到第三方），浏览器内直接调
[`vitro/engine/gateway`](../moonbit/gateway/) 的 wasm-gc 产物（NDJSON 帧协议
v0.2）。**F4 收尾（2026-10-17）：Svelte 5 + Vite 为唯一构建**——入口
`index.html` + `src/`（组件 + `js/` 八个物理保留纯函数模块），构建产物
`dist/` **不入库**（与 `wasm.wasm` 对称，`.gitignore` 在案）；旧栈
（`app.ts`/`style.css`/旧 js 模块）已退役。开发期工具有 npm devDependencies
（vite + svelte + typescript——构建/检查用，不进页面产物）。

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

# 3. 构建前端（vite 唯一构建；dist/ 不入库，不构建 404 白屏）
cd demo && npm ci && npx vite build && cd ..
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
6. `node --test demo/tests/pure.test.mts`——纯函数十八锚（buildCallTree trie /
   isArrayAnimCase / latin1ToUtf8 / heapSpanOf / esc / workspace 四锚：
   toPosix·isSourceFile·shouldSkipDir·orderForCompile /
   share 七锚：base64url 往返·三形态 fail loud·片段解析三态·shareUrlFrom
   剥旧片段·压缩往返·**截断必被解压失败兜住**·长度告警边界；**须 node 25**，
   type stripping 直跑 .ts）。DOM 交互层不硬测，维持浏览器实测纪律。
7. **E-08 快照闸**（`ci.yml` 已接）——`vite build --ssr src/e08/entry.ts` 产
   node bundle 后 `node --test demo/tests/e08.test.mts`：13 锚 = 12 组件用例
   × 冻结 golden（`demo/e08/golden/*.html`）逐字节比对 + 用例表↔golden 目录
   全等锚；刷新只走 `tests/e08-update.mts` 显式人工令（E-04：快照禁测试内
   动态生成）。**课程叙述真源链**（2026-10-16 换真值）：coursenote 三用例
   （blocks/sorting/h3）直读 `course/*.md` 真源解析渲染，payload 手写 lesson
   段已退役；块型覆盖矩阵登记在 `src/e08/entry.ts` 头注（h3 为冻结样本块——
   两试点课真源无 ### 标题的真源缺口）。
8. **E2E 浏览器实测（本地资产，CI 无 Edge 不进流水线）**——`demo/tests/
   e2e_diagcard.mjs`（F4 残留①④：编译诊断卡 + 断点链 17 锚）+
   `demo/tests/e2e_workspace.mjs`（工作区 + 点课叙述 + 回放交互 + 设置面板 + 主题持久化 + 分享往返 31 锚，
   mock FSA 注入跑全链）。跑法：vite build 产物 → `node tests/serve_static.mjs
   8931` → Edge `--headless=new --remote-debugging-port=9222
   --no-proxy-server` → `node tests/e2e_*.mjs http://127.0.0.1:8931/`
   （**node 25**；环境带 HTTP_PROXY，CDP 与页面都禁走代理——脚本内
   /json/list 走 node:http 直连，Edge 加 --no-proxy-server）。前置：
   `moonbit/_build` 的 wasm-gc 产物须已 cp 到 `demo/wasm.wasm`（新鲜度
   闸缺口见 issue #123①——本地手 cp 无门禁，仍是已知缺口）。

## 链接分享（2026-10-09）

「🔗 分享链接」把**编辑器当前内容**压进 URL 的 `#` 片段：`#z1.<base64url>`。
点开链接的浏览器读到 `#` 就还原源码填进编辑器。**仍是零后端**——`#` 不参与
HTTP 请求，代码不出本机（不上传、不经第三方）。

- 压缩用浏览器原生 `CompressionStream/DecompressionStream("deflate-raw")`；
  本页浏览器底线（Chrome/Edge 130+、Firefox 134+）远超过该 API 可用点
  （103/113+），**零新依赖、零 polyfill**。
- **载荷只装源码**：版本 tag + 压缩载荷，不带步号/断点/课程 id/argv 任何运行
  上下文（2026-10-09 用户拍板：那是无关信息）。链接条会写清「源码 N 字符 →
  链接 M 字符」。
- **不花载荷买校验和**：DEFLATE 流缺尾必然解压失败（实测 17 份用例 × 4 个
  截断比 + 尾部少 1 字节共 85 例全抛错），故截断由解压失败兜住，省下校验字节
  ——**该结论是实测口径，未做形式化证明**（回归锚 = pure.test 的「截断载荷必
  被解压失败兜住」）。
- 片段解析三态：**无 `#` = 正常首访**（静默继续）／**有 `#` 但前缀不是 `z1.`**
  = 链接被截断或版本不认识（**明确报错，绝不静默退回默认示例**——半截链接
  最危险，朋友会拿到一段看着正常的空页面）／前缀对但载荷坏 = 同样报错。
- **不自动运行**：`#` 内容是不可信输入，只落到编辑器，点了「运行」才编译。
- 长度（deflate-raw + base64url 实测，链接含 60 字符域名前缀）：源码中位
  300 B → 约 430 字符；1.2 KB → 约 510 字符；3.5 KB → 约 960 字符；90 KB 的
  语料大文件 → 约 1140 字符（C 代码重复度高，deflate 压缩比极狠）。**交叉点**：
  源码 < 约 300 字符时链接比代码本身还长（此时复制代码更划算），≥ 500 字符
  时 72% 的样本链接更短，≥ 1200 字符时 100% 更短。链接超 8000 字符仍会生成，
  但状态提示明确劝阻（聊天工具多半截断）。

## 打开本地文件夹（工作区模式，2026-10-05）

「📂 打开文件夹」按钮（File System Access API，`showDirectoryPicker`）授权
后可读写本地 C 工程目录：递归枚举 `.c/.h`（跳过隐藏目录与 node_modules 等
大目录，200 文件 / 单文件 2MB / 深度 8 上限）→ 文件 chips 切换编辑 → 运行
时全量打包 `compile.files`（集合内 `#include "x.h"` 由引擎内存 vfs 解析，
`.h` 只进 vfs 不进编译单元拼接——C 语义对齐）→ Ctrl+S / 保存按钮写回磁盘
原文件。**不自动保存**：dirty 文件以 chip 圆点标记，关页由浏览器原生
beforeunload 提示兜底；点课离开时 confirm 后保存并关闭工作区。仅桌面
Chromium（Chrome/Edge）支持；移动端（≤960px）入口整体隐藏，不做降级。

> F4 前端批状态：上述能力已随 `src/` 新栈（Svelte 5）迁移落地——store 在
> `src/lib/workspace.svelte.ts`（纯函数物理保留 import `js/workspace.ts`，
> pure.test 四锚零改动），UI 在 `src/lib/WorkspaceBar.svelte`；采集通道经
> `session.collect` 自动带 `compile.files`（单一源，对齐旧栈
> buildCompileParams 纪律）。mock FSA E2E 15 锚见门禁第 8 条。

## 课程叙述消费（2026-10-16 glob 懒加载格式）

`course/*/lesson.md` 真源由 `src/lib/lessonNotes.ts` 经
`import.meta.glob("../../../course/**/lesson.md", { query: "?url", eager: false })`
**按文件懒加载**（每课一枚 base64 data-URL 小块，不进首屏包——试点期 2 课
`?raw` 内联是全量 110 课即爆的过渡形态，裁定见 #122 末条）。运行时
`loadLessonNote("<chap>/<id>")` fetch + `lessonMd.ts` 解析；解析失败 /
无此课叙述 = 不渲染面板 + 控制台 fail loud（宽容于用户）。E-08 快照闸的
coursenote 用例走同一真源（SSR 侧 `?raw` 内联——node 无 fetch 面），
两形态同源联动，改真源两边一起验。切分线：`course/*.md` 是 demo 自家资产，
消费端 TS 解析自家格式合规（parser.c 不加 demo 模式）。

## 诚实边界

- 渲染逻辑暂放宿主页内 TS（门面定位，非架构件）；MoonBit SVG 渲染纯函数包
  落地后由其接管（总计划既定路线）。
- Clang golden 参考值为预置真值（CI shadow 防线持续对拍），页面内无实时
  交叉编译。
- 时间旅行（step 流采集-回放）与算法可视化（「内容」页课程树：43 算法族
  + 变体 + 82 模板全量）均已接 gateway 通道（step.begin/step.next/seek/
  breakpoints.set）；引擎侧行号偏移两族标注边界见 issue #34。
- 链接分享**只带编辑器当前文件**（工作区模式下不打包整个工程）——多文件
  容器未做；也**没有**走「分享编译产物（字节码）」路线：实测 libc 那组
  真值里，字节码 JSON 形态 deflate 后仍是压缩源码的 7.8 倍（未压缩形态
  238 倍），且字节码不可逆（朋友端编辑器要显示源码）、与引擎版本强绑定
  （opcode/schema 一变链接即失效），而 `moonbit/bytecode/` 目前也没有任何
  序列化出口——要做等于给引擎新增协议方法 + 版本兼容面，收益为负。
- 链接长度有物理地板：源码 deflate+base64url 后约等于源码字符数的 0.4~0.9 倍，
  5.5KB 教学程序 → 约 2600 字符。实测换更强压缩器（brotli q11 -15%）、加
  32KB 共享词典（-11%）、域内预分词（-0.2%）都到不了「短链」量级——**瓶颈
  不是压缩率，是「URL 里要塞下整个程序」**；真要百字符量级必须把代码存到
  别处（= 引入后端/第三方存放点），与「零后端」定位冲突，故 2026-10-09 用户
  拍板**不做**，先保证前端功能全可用。
