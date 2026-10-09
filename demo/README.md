# demo 页（浏览器直调 wasm-gc gateway）

本目录是 Vitro 引擎的静态单页展示面——**零后端、零运行时依赖**（页面本体不发
网络请求到第三方、不跑构建器），浏览器内直接调
[`vitro/engine/gateway`](../moonbit/gateway/) 的 wasm-gc 产物（NDJSON 帧协议
v0.1）。**开发期工具有 npm devDependencies**（typescript + @types/node——仅
类型检查/发射用，不进页面）；源码形态 = TS（`app.ts` + `js/*.ts` 十六模块），
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
6. `node --test demo/tests/pure.test.mts`——纯函数十八锚（buildCallTree trie /
   isArrayAnimCase / latin1ToUtf8 / tokenizeC / highlightLines / heapSpanOf /
   esc / workspace 四锚：toPosix·isSourceFile·shouldSkipDir·orderForCompile /
   share 七锚：base64url 往返·三形态 fail loud·片段解析三态·shareUrlFrom
   剥旧片段·压缩往返·**截断必被解压失败兜住**·长度告警边界；**须 node 25**，
   type stripping 直跑 .ts）。DOM 交互层不硬测，维持浏览器实测纪律。

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
