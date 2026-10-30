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

## 界面（2026-10-18 前端改造）

信息架构与视觉语言按设计档案 `demo/design/2026-10-18-redesign/`（v4 定稿；本地档案，`.gitignore` 忽略）落地：

- **三态**：工作态（默认，**左仪右书**：左仪器三模式 / 右课页与编辑器——2026-10-18 用户反馈④对调）／课程目录（顶栏「课程」）／诊断手册（顶栏「诊断手册」或一句话诊断跳转）。
- **仪器三模式**：执行（诊断带 / 时间轴 / 数组索引格 / 调用树 / 局部变量 / 输出）· 内存（`memory.regions` 三段轨道 + freed/quarantine）· 协议（capabilities / contracts / labels 只读事实）。
- **五主题**（用户 2026-10-18 拍板）：明亮实验室 / 奶油手账 / 绒面深蓝（旧色板原样保留）+ 白天（纸）/ 夜航图（设计稿新增）。**奶油手账保留旧主题的新拟物双阴影**（面板/按钮/字段浮起，输出/搜索凹入；2026-10-18 反馈①）；旧键迁移：`light→ice`、`dark→paper`、`glass→blueprint`（深夜书房退役，由夜航图接替）；字号档 13/14/16、动效开关照旧持久化。
- **首访动线**：落地即载入上次课（无记录 = bubble）并采集到中段帧**暂停**（不自动播）；入口态「继续上次」回到上次课与帧。
- **保留能力**：运行条（运行 / 分享 / 重置）、实验参数（argv / stdin / 文件 / 打开文件夹）、断点、stdin 喂入续跑、Clang golden 末帧对照、课程叙述真源。
- **就地诊断卡**（2026-10-18 反馈③）：运行期 trap 与编译期首错都在仪器里直接给「**码表图标 + 码 + 标题**（点击进详情）→ 说明 → 常见原因」，引擎原文折叠在下一行——不用先跳手册；图标来自 `moonbit/icons/<id>.svg`（生成 `demo/js/icons.ts`）。
- **参考态覆盖**：左侧码表是 `error_catalog` 的**全部** 100 条 C 卡（**每条带码表 SVG 图标** + 按 catalog 自报 `category` 分组 + 搜索 + 粘性滚动）；右侧每条都有统一详情模板（标题 / 说明 / 常见原因 / 相关课 / 返回）。其中 E3060 另有 trap 三幕图，E3060·E3023·E3070·E3061·E3027·W1019 六条附「示例 / 怎么修」插图；其余条目只呈现 catalog 真字段，不手写第二份错误文案。对表纠正：E3061 按 catalog 是 Double-Free（cases 的 `e3061` 实为 NULL 解引用且无 E 码，旧标签已改「运行期 trap」）、E3027 是 free 参数类型错误（设计稿的「NULL 解引用 / 堆耗尽」是 mock，未沿用）。
- **键盘仪表盘**：空格播放/暂停、←/→ 单步、Home/End 首末帧、`[`/`]` 速度档（输入框与编辑器内不劫持）。
- **「此刻」读数**（实现层小巧思，设计稿未画）：时间轴悬停读数 + 点击跳帧、数组快照变化帧的交换刻度、按当前行 `a[j]` 与局部变量求值自动指认比较格、末帧收尾帧沿用最近一帧数据并在块头标注沿用来源。

## 课程叙述与分镜（2026-10-21 拍板）

- **唯一真源 = `course/**/lesson.md`**。分镜（scene）写在 body 顶部的可选注释块里，不新建前端 `beats.ts`：

  ```md
  <!-- vitri-scenes v1
  01 | 起点：数组与循环 | 0..4 | 3..4 | 数组初始化，i / j 还是 0。
  -->
  ```

- 解析在 `src/lib/lessonMd.ts`（demo 自家消费端，不走 `content_parser.c`）：`from..to` 是 `viewFrames` 闭区间，`lines` 是源码行范围；注释块解析时从 `blocks` 剥离，`CourseNote` / E-08 golden 逐字节不变。
- 无 scene 的课 = `scenes: []`，回退现有长文；scene 范围重叠 / 格式错误 fail loud。锚在 `tests/pure.test.mts`（解析 / 无 scene / 格式错误 / bubble 0..41 覆盖）。
- **消费面（P1 第二/四片，2026-10-21）**：左栏是**竖向分镜轨**（`src/lib/BeatRail.svelte`：点幕 = 跳到幕首帧；当前幕高亮 + 一句本幕要点 + 帧范围 + 幕内进度），时间轴上方是按帧格等分的**分幕带**（当前幕高亮）。样式走既有 `--vr-*` token，不新增主题变量。定位单点在 `src/lib/scenes.ts`（`sceneIndexAt` / `sceneProgress` / `sceneBand` / `sceneKicker`，纯函数，锚在 `tests/pure.test.mts`）；交互锚 `B0`（未迁移课无分镜条）/ `B1`（点幕跳首帧 + 当前幕/注记同步）在 `tests/e2e_session.mts`。
- **幕头与浅树压扁（P1 第三片，2026-10-21）**：代码上方是**幕头**（`src/lib/StageHead.svelte`：幕号 / 帧范围 / 源码行 + 标题 + 一句要点 + 上一幕/下一幕）；调用树节点 ≤3（`prog → main` 一族）时**不画 214px 画布**，压成一行面包屑 + 当前语句（深树仍走画布）——把首屏让给局部变量与输出。锚 `B2` 在 `tests/e2e_session.mts`。
- **三栏布局（P1 第四片，2026-10-21）**：工作台 = 左 rail（课头 + 运行条 + 分镜轨）/ 中 stage（幕头 + 代码 + 参数）/ 右 now（仪器三模式）+ 底栏 **dock**（时间轴 + 输出 strip，横跨三栏）+ 课文殿后；容器 ≥1180px 走三栏，窄容器回落单列（DOM 序即阅读序，无 `order` 重排）。1440×900 首屏量测：代码 187 / 数组 191 / 局部变量 487 / 时间轴 648–847 / 输出 strip 874。锚 `B3`（三栏几何 + 底栏通栏 + 首屏）在 `tests/e2e_session.mts`。
- **逐行注记（P1 第五片，2026-10-21）**：src/lib/annotations.ts 从帧流差分出「本幕每行最近一次执行改了什么」——局部量 t ← 5、数组元素 a[1] ← 1；只取当前帧及之前、跨函数不比较、首帧无前态不猜；**归行校验**（该行源码不写这个变量就不贴注记——语句级帧会把 for 的 j++ 并进循环体末行，实测 a[j+1] = t 帧里 j 已递增）。渲染走 CM6 **行装饰属性 + CSS ::after**（注记不进 .cm-content 文本面，E2E docLen 不被污染），源码编辑（docChanged）即整体作废。锚 B4（帧 12 的三行注记 = 拍板稿 08/09/10 形态）在 tests/e2e_session.mts。
- **本幕讲解 + 展开全文（P1 第六片，2026-10-21）**：scene 课程的课文改为「当前幕卡片（幕号/帧范围/源码行 + 标题 + 一句要点）+ 默认折叠的全文」（src/lib/SceneNote.svelte）——本幕卡片只读 lesson.md 真源字段，不手写第二份讲解；无 scene 的课 100% 回退现有长文。全文走 details（内容始终在 DOM，E-08/W9 锚不受折叠影响），换课自动回折叠。锚 B5（默认折叠 + 本幕跟随 + 可展开）在 tests/e2e_session.mts。
- **交换事件优先（D1，#122，2026-10-29）**：`session.eventsAt(i)` 暴露第 i 个回放帧的 vis_events 全集。语句级按**组内聚合**：VM 的 StepEvent 落在组内命中的那条指令上，组尾帧自身常无事件——bubble 课实测 7 个 ty=2 交换全部落在非尾帧，只读组尾会全丢（`src/lib/visEvents.ts` 的 `statementEvents`，帧序列与 `coalesceStmt` 同源同序）。ArrayCells 在 ty=2 时用 extras（j/j+1）做双格静态高亮 + 两格连线 + WAAPI 脉冲，「本帧交换 a[0] ↔ a[1]」进入块头读数；**无事件才回落相邻帧差分闪烁**（猜测降级为兜底）。extras 只有下标没有数组名——多数组课按事件 `context` 的 `name[` 归属过滤（A 数组的交换不会点亮 B 数组的同号格；D1b 用合成课做接线锚）。Editor 左缘按 ty 分色：compare 琥珀 / swap `--vr-swap`（五主题各一枚）。纯函数锚 `statementEvents` / `swapPairs` 在 `tests/pure.test.mts`。
- **动效治理层（D0，#122，2026-10-29）**：`src/lib/motion.svelte.ts` 单点管三件事——①用户开关 + 系统 `prefers-reduced-motion`（`data-motion="off"` 的唯一写口，CSS 一刀切）；②脉冲预算（播放 / 批量推进 / 时间轴 scrub 时 WAAPI 脉冲让位，静态高亮与连线不让位）；③`pulse()` 原语（同元素单动画键控，重复触发先取消上一次）。时长/缓动**运行期**读 tokens.css（`--vr-t-fast/base/slow` + `--vr-ease / -emphasis / -enter`），不在 JS 抄数；spring 数值参数在 motion 层（CSS 变量无法回喂 Svelte spring）。
- **结构过渡（D2，#122，2026-10-29）**：CallTree 相机跟随/全览切换走 `Tween`（160ms cubicOut）——Svelte Spring 的 damping 被钳在 0..1，快速档必然过冲，做不出「过阻尼仪器感」（改动理由写在 motion 头注）；拖拽/缩放/scrub/批量/reduced 一律瞬时。树节点换树时从父节点旧位置生长、边淡入；**首帧落地不演**（`ui.navEpoch` 区分首帧与用户换页），visited 祖先链走 CSS 过渡。VarsList 行进出 `gatedFade` + 值变化 WAAPI 脉冲（预算外只留静态左缘线）。**MemoryView 的 alloc/free 帧级进出场本轮不做**：组件数据源是会话结束态 `memory.regions`（非帧级），按 `pointer_snapshots` 伪造生命周期会违反「动效不撒谎」——等 D4/#53 的帧级内存数据。
- **view→raw 映射修正（D2 连带）**：CallTree 的 `frameNode` 按指令帧建，语句级拿 view 下标直查会错帧（global_struct deep 帧 view 10 ↔ raw 56）——新增 `session.rawIndexAt` 单点映射，路径/当前节点/相机取景同源修正；D2 深树锚以 `frameAt().call_stack` 真值全等断言。

## 设计契约与主题 token（P0 契约批，2026-10-21）

- **token 单源 = `demo/tokens.json`**（W3C DTCG 子集：每 token = `{$value, $type}`；`base` 字体/尺寸/动效 + `themes` 五主题色板〔`colorScheme` + `tokens`〕+ `sizes` 三字号档；`themeOrder` 定序）。
- 产物 `demo/src/tokens.css` 由 `scripts/gen_demo_tokens` 生成（`@generated` 禁手改），`app.css` 顶部只 `@import`。改色板流程：改 `tokens.json` → `node scripts/gen_demo_tokens/main.mts` → `-check` 绿 → `node demo/tests/style_contract.mts` 比对（computed 值；像素闸已退役，不再以截图作门）。
- 门：`node scripts/gen_demo_tokens/main.mts -check`（逐字节，CRLF 归一）+ `-selftest`（同集绿 + 篡改必红，J9）；`ci.yml` demo 段同步步。意图 / Do-Don't / 五主题语义见 [DESIGN.md](DESIGN.md)（不复制数值——数值只在 tokens.json）。
- 本批迁移实测（一次性取证，非门）：五主题 1440×900 截图迁移前后逐字节一致（ice / rose / soft / paper / blueprint 五张 PNG 的 sha256 全等）；像素闸已于 2026-10-22 退役。
- **样式契约闸（P0 第二批）**：`node demo/tests/style_contract.mts http://127.0.0.1:8931/`——五主题 × 19 选择器 × 9 个 computed 属性（颜色 / 字体族 / 连字 / 字距 / 大小写）对账基线 `demo/tests/style_contract.json`；取跨 OS 确定值（不经栅格化），CI 与本地同基线，`--update` 为人工令。
- **像素闸（P0 第三批）已于 2026-10-22 退役**（用户裁定：PNG 基线只能 CI 专用生成、入库体积与维护噪声大于收益）。画面语义改由样式契约（computed 值）+ E2E 行为锚 + `demo_ui_lint` 文本面守，不再保留截图基线目录与生成步骤。

## 本地预览

`wasm.wasm` 与 JS 发射产物都是构建产物，**不入库**——本地起服务前须先备齐两
件；页面用 `fetch` 加载 wasm，`file://` 直开 `index.html` 会被浏览器拒绝，必须
走静态服务器：

> ⚠️ **产物必须与当前 commit 同源**（2026-10-29 实测）：主仓 `demo/wasm.wasm`
> 曾是 0.8.0 旧产物、`langpack.js` 曾是 10-23 旧包——浏览器里
> `algorithm_matches` 恒空（vis_events / 交换事件全丢）、`error_catalog` 返回
> 空表，而同一 commit 的 CLI js 臂一切正常。遇到「demo 没事件 / 手册空」先
> 核对三件产物（wasm / langpack / algorithms.js）的新鲜度，不要先怀疑引擎
> 代码；重建命令见下，CI 侧由 build-artifacts 同批产物保证。

```bash
# 1. 构建 wasm（或已有产物可跳过）
cd moonbit && moon build --release --target wasm-gc gateway/wasm && cd ..

# 2. 拷产物到 demo/（wasm 引擎 + 语言包懒加载两件，#130 批②）
cp moonbit/_build/wasm-gc/release/build/gateway/wasm/wasm.wasm demo/
moon build --release --target js teaching/langpack
mkdir -p demo/teaching/langpack
cp moonbit/_build/js/release/build/teaching/langpack/langpack.js demo/teaching/langpack/langpack.js

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

本页判定闸全部已接 CI（ci.yml `demo` job，与本地命令一一对应）：

1. **TS 类型检查（三面，2026-10-25 起拉到最严）**——`npm run check:all`：
   - `npm run check:main`：`js/` 八个物理保留纯函数模块；
   - `npm run check:tests`：`tests/*.mts`（含 E2E/CDP）与 `@types/node` 面；
   - `npm run check`：`src/` + `.svelte`（svelte-check）。
   三套 tsconfig 共用最严档：`strict` + `strictNullChecks` +
   `noUncheckedIndexedAccess` + `exactOptionalPropertyTypes` +
   `noImplicitOverride` + `noImplicitReturns` +
   `noPropertyAccessFromIndexSignature` + `noUnusedParameters` 等；
   旧 2026-10-04 的 `strictNullChecks=false` 单档收窄已废止。
2. `node scripts/gen_demo_algorithms/main.mts`——算法侧栏数据发射（**产物不入
   库**，CI/pages 消费前现场发射；分组并集 == rules.json 43 族 + 82 模板全
   集对账，发射即闸）。本地起页须先跑此步生成 `algorithms.js`。
3. `node scripts/course_catalog/main.mts`——课程目录闸（reconcile + lesson.c 双
   臂 diff）。
4. `node scripts/demo_assemble_check/main.mts demo`——组装资源存在性自检
   （index.html script/img 面 + 入口 import 面逐项存在；HTML 抽取面哨兵；
   pages.yml 发布面加 `--no-ts` 断言源不随产物发布）。
5. `npm run check`——F4 svelte-check（type + a11y gate，零错零警）。
6. `npm run lint:all`——F4 oxlint（`src/` + `tests/*.mts` 显式清单；零错误 gate）。
7. `npm run build`——F4 vite build（构建成功 gate；产物 `dist/` 不入库）。
8. **E-08 快照闸**——`vite build --ssr src/e08/entry.ts` 产 node bundle 后
   `node --test demo/tests/e08.test.mts`：17 锚 = 16 组件用例 × 冻结 golden
   （`demo/e08/golden/*.html`）逐字节比对 + 用例表↔golden 目录全等锚；刷新
   只走 `tests/e08-update.mts` 显式人工令（E-04：快照禁测试内动态生成）。
   **课程叙述真源链**（2026-10-16 换真值）：coursenote 三用例
   （blocks/sorting/h3）直读 `course/*.md` 真源解析渲染；块型覆盖矩阵登记
   在 `src/e08/entry.ts` 头注。
9. `node scripts/demo_smoke/main.mts`——**协议层实跑闸**：对 `cases.js` 每个
   预置用例经 wasm gateway 实跑协议链并逐字节比对 golden，断言渲染所需的
   响应字段存在，含 **step 族字段契约**（StepPayload 顶层 = 协议 v0.1 十四
   字段白名单键集全等）与 **方法面计数对账**（gateway 错误帧自报清单 ==
   index.html 宣称数 == src/ `method:` 字面量去重数，三方法面单源对账）。
   篡改 golden、页面引用字段名漂移、wire 键集漂移即红。
10. `node scripts/demo_ui_lint/main.mts`——JS↔CSS 字符串契约对账：`classList`
   写操作的类名对「CSS 复合单元 ∪ JS 生成面 ∪ 元素候选闭包 ∪ rules.json
   白名单」对账、`var(--x)` 引用对定义面对账、`$("id")` 对 html id 集对账、
   **mono 连字对账**（`var(--mono)` / `var(--vr-mono)` 消费面必须同行关闭
   连字——2026-10-18 扩面到五主题令牌，位点下限 40 兜抽取面塌缩；#121①
   教学硬伤防线）。抓「操作永不生效的类」「引用不存在的 CSS 变量」「连字
   复活」形态。
11. `node scripts/teaching_phase_vocab/main.mts`——教学阶段词表冻结闸。
12. `node --test demo/tests/pure.test.mts`——纯函数 46 锚（buildCallTree
    trie / isArrayAnimCase / latin1ToUtf8 / heapSpanOf / esc / workspace 四
    锚 / share 七锚 / **decorateBadges·formatTrap 徽章码表** / scene 解析与
    scenes 纯函数 / 逐行注记差分 / **visEvents 组内聚合与交换对** /
    **motionTokens 兜底↔tokens 等值** / 三门旗舰课 scene 覆盖 / 全量
    course scene 连续与行界 / 第〇章 5 门 N 帧与四节 / 码表键与关联课；
    Node 24+（CI 钉 `.node-version`），type stripping 直跑 .ts）。DOM
    交互层不硬测，走第 13 条浏览器 E2E。
13. **浏览器 E2E（已进 CI，2026-10-17 收口）**——`demo/tests/
    e2e_diagcard.mts`（诊断带 + 断点行为链 S1-S5，18 锚）+
    `demo/tests/e2e_workspace.mts`（工作区 + 点课叙述 + 回放交互 + 设置
    面板 + 主题持久化 + 分享往返 + **stdin 喂入/golden 对照/统计卡**
    W1-W17，38 锚）+ `demo/tests/e2e_session.mts`（会话/回放/分享族
    F1-F8 + B0-B11 + **D0/D1/D2**，30 锚——2026-10-18 实测立账批防线锚：
    坏分享 hash 横幅 / argv 采集零克隆崩 / 语句级 frameAt 口径〔突变证红
    留痕〕/ 播完 status 提示 / char 数组**全帧 sweep** 零
    each_key_duplicate / trap E 码联动手册 / **课程目录全章渲染**〔重名
    课 id 防护，structures/josephus 实测〕；D0/D1/D2 锚：交换帧双格 + 连线 +
    编辑分色〔修前只有 1 格差分，红→绿留痕〕、动效开关持久化 +
    预算/reduced-motion 旁路、变量值脉冲/行进出、深树 view→raw 当前节点与
    相机平滑/reduced 旁路、多数组归属接线）+ `e2e_editor.mts`（10 锚）+
    `e2e_bootfail.mts`（6 锚）。共 102 锚。
    ⚠️ 旧锚点（`.pilot-head` / `.tab` / `button.lesson` / `.bars`）随五 tab
    旧 DOM 在 2026-10-18 改造批退役；仍跑旧脚本会在 boot 等待即超时
    （`.pilot-head .badge` 永不出现）——请以当前 `tests/e2e_*.mts` 为准。
    CI 步用 ubuntu runner 预装 Google Chrome headless
    CDP（与 Edge 同协议，脚本零改动）；本地跑法：vite build 产物 →
    `node tests/serve_static.mts 8931` → Edge/Chrome `--headless=new
    --remote-debugging-port=9222 --no-proxy-server` → `node tests/e2e_*.mts
    http://127.0.0.1:8931/`（**node 25**；环境带 HTTP_PROXY 时 CDP 与页面
    都禁走代理）。前置：`moonbit/_build` 的 wasm-gc 产物须已 cp 到
    `demo/wasm.wasm`（新鲜度闸缺口见 issue #123①——本地手 cp 无门禁，
    仍是已知缺口）。

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
> buildCompileParams 纪律）。mock FSA E2E（W1-W10）见门禁第 13 条。

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
- 时间旅行（step 流采集-回放）与算法可视化（课程目录：43 算法族
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
- **Safari/iOS 装载硬约束（#127）**：`WebAssembly.compileStreaming` /
  `instantiateStreaming` 在 Safari 26.2 上对 js-string builtins **不工作**
  （WebKit bug 308136，报 `TypeError: import wasm:js-string:fromCharCode
  must be an object`）——本仓装载（`js/gw.ts` + `src/protocol/engine.worker.ts`）
  走 `fetch → new WebAssembly.Module(buf, { builtins }) → instantiate` 两步，
  **天然规避**。禁令：任何人不得以「少一次拷贝」为由把 demo 改成 streaming
  形态，否则 Safari 26.2 直接失效；JS 侧 polyfill 亦不可行（`fromCharCodeArray`
  入参为 wasm GC array，宿主不可索引读取），兜底只能在引擎内部实现。
  浏览器底线 = Chrome/Edge 130+、Firefox 134+、**Safari 26.2+/iOS 26.2+**
  （18.2–26.1 因 js-string builtins 缺失已知不可达）。
