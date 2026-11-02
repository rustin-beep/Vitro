# Vitro 桌面壳（desktop/）——proton 捉虫/测试壳

> as_of 2026-11-02（P 线实测前进拍板；实测报告 `tmp/batch_P_proton_REPORT.md` 不入库，结论摘要见本文 §5）

## 定位（一句话）

**独立下游 module，非发包面。** 引擎发布物仍只有 mooncakes `vitro/engine`（源在 `moonbit/`）；本工程 `import "vitro/engine@<pin>"` 消费**已发布包**，与 `demo/`（浏览器交付面）并列——`demo/` 走 wasm/js 产物，`desktop/` 走原生同进程直调。

零污染语义（机器可验）：

| 面 | 事实 |
|---|---|
| `moonbit/moon.mod` | 不 import 本工程；`moonbit/moon.work` 成员无本目录 |
| mooncakes publish | 只发 `moonbit/`（`vitro/engine`）；`desktop/` 不在任何 publish 流程 |
| CHANGELOG | 批次不写根 CHANGELOG（2026-11-02 拍板：记录=commit+PR）；`moonbit/CHANGELOG.md` 是发包面、与本区无关 |
| 依赖方向 | `desktop → mooncakes vitro/engine@pin`（单向）；引擎 HEAD 变化不影响本壳，壳崩不影响引擎 |

副作用=**发包哨兵**：本壳 `moon check` 红 ⇒ 已发布 `vitro/engine@pin` 在下游独立 module 里装不上/解析不过（0.9.0 core/abort 断供事故形态——见 `docs/current/08-发布档案/0.9.1.md`）。

## 做什么（2026-11-02 P2 批起：承载 demo UI）

**UI = `demo/`（Svelte 5 + Vite 教学前端）原样承载**：`proton_cli dev` 起 vite dev server 并以 `PROTON_FRONTEND_URL` 覆盖窗口 entry；引擎不在渲染进程的 wasm 里，而在**壳进程 native 同进程直调** gateway 单口。

- **引擎命令层**（`app/engine_commands.mbt`，官方 app-owned 形态 `..commands()`，JS 侧 op 名 `app:<name>`）四命令，与 demo Worker 的四个 op 一一对应（编排序列照抄 `demo/src/protocol/engine.worker.ts`，不做协议面发明）：

| 命令 | ← Worker op | native 侧编排 |
|---|---|---|
| `app:vitro_versions` | boot | `@gateway.engine_version()/protocol_version()` |
| `app:vitro_invoke` | invoke | 网关单口原样转发（错误帧不折叠） |
| `app:vitro_collect` | collect | reset→session.create→config.set→compile→run→step.begin→breakpoints.set→**step.next 采帧循环（native 内闭环）**→output.delta 四通道分页拉取 |
| `app:vitro_feed` | feed | input.feed→step.begin→重采循环 |

- **demo 侧适配点**（浏览器形态零变化）：`src/protocol/engine.ipc.ts`（Worker 同形 IPC shim——`{id,op,...}→{id,ok,data|error}` 消息形状逐字相同）+ `session.svelte.ts` 构造点经 `createEngineTransport()` **三段式选择**（PR #417 审阅 P1-1/P1-2 处置）：①桥已在⇒IPC 零等待；②壳内（dev_url `?shell=proton` 标记 / 打包形态 proton.localhost）桥未到⇒轮询 2s；③浏览器⇒立即 Worker（零固定等待）。实际分支写入 `window.__vitroTransport`（smoke 断言读它，与「桥存在」解耦）；`waitBridge` 失败弃负缓存（重试可复活）；session 侧 in-flight 缓存+代际守卫（双发 boot 不双建、kill 不泄漏）。字段映射（bpLines→bp_lines / method→api）在 shim 层完成。
- **桌面真实做法**（与 proton isomorphic 模板同构）：编排归 native 端——IPC 往返 = 整段一次而非每帧一次；demo 浏览器形态里这段循环在 Web Worker 内闭环，消息形状不变。
- 引擎调用**不要**改走 `@cli.run`：其 `COMPILE-ERROR` 行走 `say()`→进程 stderr，GUI 侧拿不到（P 线 v1 形态实锤 rc=1 而 output 空）。

**端到端实测基线（2026-11-02，CDP 读数字）**：demo UI 全量装载（title「Vitro · C 执行观察台」、桥注入 `hasBridge:true`）；点「运行」→ `编译 ✓ 运行 ✓ golden ✓`、stdout=`1 2 3 4 5 \n`、**42 帧**时间旅行回放可用、`引擎 0.9.1 协议 v0.2`（native 真值）、目录 114（invoke 透传递归亦通）。

## 依赖与环境（Windows x64）

- MoonBit `latest` 频道（仓 pin `.moonbit-version`，proton 0.6.0 要求 ≥2026-10 新语法）；MSVC（VS Build Tools）——moon 经 vswhere 自寻 `cl.exe`，**不需要开发者终端**
- `moon install moonbit-community/proton_cli@0.6.0`（22s 原生构建）→ `proton_cli cef setup`（164MB 自 cef-builds.spotifycdn.com，解压后 869MB 落 `~/.proton/store/`；helper `cef_process.exe` 落 `~/.proton/helpers/`；外壳调用系统 `curl`/`tar`，Win10+ 自带）
- node ≥22（探针走全局 `fetch`/`WebSocket`，零第三方运行时依赖）

## 命令

```sh
cd desktop
moon update && moon check --target native          # 类型面（CI 闸）——不编 C、不碰 CEF
npm ci && npm run check:all                        # tsc 严档 + oxlint（CI 闸）
proton_cli build -- --release                      # 原生构建（~26s，app.exe ~4.9MB）
PROTON_REMOTE_DEBUGGING_PORT=9335 proton_cli dev   # 起 ../demo 的 vite dev server + 壳窗口
                                                   #（dev_url=http://127.0.0.1:5173，首跑前 demo 需 npm ci）
node tools/smoke.mts 9335                          # CI 同款全链 smoke：起 dev → 八断言 → 杀树（~10-20s 不含 build）
```

不经 `proton_cli` 直跑 `_build/.../app.exe` 需环境四件套：`PROTON_RUNTIME_ROOT=<store>/runtime`、`PROTON_HELPER_PATH=<helpers>/0.6.0/cef_process.exe`、`PROTON_PROJECT_CONFIG=<本目录>/proton.project.json`、`PATH` 前置 `<runtime>/bin`（缺 config 时 `load_config()` 直读 exe 同目录，缺即 abort）。`proton_cli package` 打包后内嵌元数据可免——打包形态验证列下批。

## CDP 开关矩阵（P 线四形态实测）

源码语义：proton `facade_manifest.mbt:162-186` / `facade_entry.mbt:125-165`。

| builder `debug` | `PROTON_REMOTE_DEBUGGING_PORT` | 结果 |
|---|---|---|
| `true`（本壳缺省） | 无 / `0` | CDP 开，**临时随机端口**（用 `tools/find_cdp.mts <pid>` 发现） |
| `true` | `1024..65535` | CDP 开，**钉死该端口** |
| `false` | 无 | CDP **关**（零监听端口） |
| `false` | `1024..65535` | env 非空把 debug 翻为 1 ⇒ CDP 开钉死——release 产物开 CDP 的合法通道 |
| 任意 | （`proton_cli dev`） | `PROTON_MODE=dev` 强制开 |

## 探针（`tools/`，node 直跑 .mts）

| 脚本 | 作用 | 用法 |
|---|---|---|
| `cdp_probe.mts` | 在 page 目标上 `Runtime.evaluate`（awaitPromise）；缺省表达式读 url/title/通道形态/引擎版本 | `node tools/cdp_probe.mts 9335 [expr \| @file]` |
| `find_cdp.mts` | 按 PID 扫 LISTEN 端口 + `/json/version` 协议指纹 ⇒ 发现临时端口 | `node tools/find_cdp.mts <pid>` |
| `cdp_catch.mts` | 不开 DevTools 窗口，订阅 exceptionThrown/consoleAPICalled/Log 三域并注入三枚虫 | `node tools/cdp_catch.mts 9335` ⇒ `caught_count ≥ 3` |
| `smoke.mts` | CI 全量防线编排：spawn `proton_cli dev` → 等 CDP → 八断言（复用上三脚本 + page 资产为单源）→ `taskkill /T` 收树 | `node tools/smoke.mts 9335`（cwd=desktop/） |
| `page/demo_matrix.js` | 页内表达式：命令层矩阵（四命令 invokeOp 直调：argv 透传〔契约=数组含 argv[0〕/ feed 续跑 / 断点停采 / invoke 透传——#451 stdin 残留缺陷注意单轮语义） | `node tools/cdp_probe.mts 9335 @tools/page/demo_matrix.js` |
| `page/demo_run.js` | 页内表达式：驱动 demo UI 完整采集（等按钮就绪→点运行→等采集与 golden 末帧→读 golden/stdout/帧数/版本） | `node tools/cdp_probe.mts 9335 @tools/page/demo_run.js` |
| `page/fps_probe.js` | 页内表达式：CSS 动画 + rAF 计数 2s ⇒ fps/min/max 帧间隔（窗口须可见） | 同上 |

**表达式一律走 `@file`**：bash→node argv→JSON→JS 串→C 串多级转义必吃反斜杠（P 线实锤 `\n` 变真换行 ⇒ `E1002 字符串未闭合` 假阳性）。

`find_cdp` 判「CDP 关」须先确认窗口已起（`MainWindowTitle` 非空）——挂起实例也是零监听（P 线对照组 B 首跑假阴性实锤）。

## 实测基线（2026-11-02，Win11 26200 / 32 核 / 高刷屏）

| 指标 | 值 |
|---|---|
| `moon check --target native` | ~2s（91 任务；缓存命中后 <1s） |
| `proton_cli build -- --release` | 21.5–26s / 229 任务 / app.exe 4.9MB（**#2254 MSVC 悬崖不随下游独立工程迁移**） |
| 冷启动（独立 exe 形态） | 943ms 见窗；进程内 runtime→renderer ready 271–357ms |
| 引擎往返（JS→桥→同进程引擎→回显） | 首次 45–70ms（会话预热）；暖态 1.5–3.5ms |
| 常驻内存树 | WS 289MB / Private 118MB（app ~114 + 5×cef_process ~175） |
| 帧率 | 160.5fps（min 3.8 / max 8.1ms）=显示器满速 |

## 已知坑（agent 自测向）

- **工具会话沙箱写围栏**：在受沙箱约束的 agent 会话里，**工作区内**的 `app.exe` 建 `%TEMP%\proton-cef-*` 会 `ERROR_ACCESS_DENIED(5)`（`failed to create temporary browser storage: 5`）——同一 exe 拷到工作区外即正常。处方：`TEMP`/`TMP` 指到工作区内目录（如 `_build/tmp`）再起。普通开发机/CI runner 无此现象。
- **MSYS bash 直 spawn 本产物 exe** 会报伪加载错 `api-ms-win-shcore-scaling-l1-1-1.dll cannot open shared object file`（同 exe PowerShell 启动正常）——脚本化启动走 PowerShell / `proton_cli dev`。
- **进程存活**：PowerShell `Start-Process` 带重定向句柄的实例随会话关闭被 `CTRL_CLOSE` 连坐杀树（renderer 死 `STATUS_CONTROL_C_EXIT`）；WMI 会话 0 建不了 GUI。跨工具调用存活的可靠形态=bash `(proton_cli dev &)`。
- CEF CDN 首段可能停滞 ~2min 后冲完（`cef setup` 自带 `--retry 5`）。

## 下批（拍板后）

打包形态验证（`proton_cli package --dry-run` → `--format app`，**含 `../demo/dist` 跨目录前端装配**、dist 内嵌元数据免四件套、CDP env 钉端口在打包产物上复验）· feed 通道（scanf 续跑）E2E 锚进 smoke · 探针收编 `vitro-demo-mcp` 工具面 · native vs wasm 双臂对拍（demo 通道形态运行时可切——GUI 内 `arm_divergence` 的第三现场）。
