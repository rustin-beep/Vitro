# DSH MCP 服务器（vitro/engine/mcp）

> as_of 2026-11-03（DSH mbt 化批建包）· 状态：代码落地 + 本地全验，发版随 0.10.0 节奏（待拍板）

## 定位

DeepSeek Harness（DSH）插件的 **MCP server 核心**——stdio JSON-RPC 2.0 上承载 Vitro 引擎的有状态会话工具面。单源 MoonBit（`vitro/engine/mcp`，L9 宿主层），随 mooncakes 主包发布；npm 侧只带 `moon build --release --target js cmd/mcp_js` 单文件产物 + DSH 包装（hub 层，实验目录 D:/tmp/vitro-dsh-plugin/hub）。

设计单源：[DSH-MCP设计单源.md](DSH-MCP设计单源.md) v2（Serena 形态；2026-11-04 收编入仓——动词化小工具 + 会话池 + 渐进披露 + 返回值投影 + readOnlyHint）。**工具数勘误**：design.md 自计「11 工具 / L0 4」，但 session_open 是解锁触发器、无会话时必须可见才能被调用——L0 可见集 5、总计 12；§3.3 的 available_now(5) + unlocks(7) 拆分即权威口径。

## 工具面（12）

| 层 | 工具 | readOnlyHint | 一句话 |
|---|---|---|---|
| L0 | animate | ✗ | 编排糖：临时会话→全采→render 预设（不翻披露） |
| L0 | diagnose | ✓ | 纯诊断 + 算法识别 |
| L0 | capabilities | ✓ | 支持面自述 + 披露引导 |
| L0 | sessions | ✓ | 活跃会话列表（含剩余寿命） |
| L0 | session_open | ✗ | 只编译不运行；首个成功解锁 L1（listChanged 通知） |
| L1 | frames_summary | ✓ | 帧结构索引（首调触发惰性全采） |
| L1 | frames_query | ✓ | 分页拉帧（默认投影 {i,l,f,s}，≤50/页；fields 扩 r/v/c/e/a/h） |
| L1 | annotations | ✓ | swap/compare/call/return 事件流 |
| L1 | run_to | ✗ | 断点行 / 首个事件 / max_frames 三停形态 |
| L1 | step_next | ✗ | 推进 n 个关键帧 |
| L1 | render | ✗ | 渲染会话缓冲（可区间 from/to），与执行分离 |
| L1 | session_close | ✗ | 末会话关闭即收回 L1（再通知） |

披露判据：L1 可见 ⇔ 会话池非空；翻转即发 `notifications/tools/list_changed`（布尔级——一次会话生命周期内工具集稳定，KV-cache 只在开关各失效一次）。

## 会话池与隔离

- 每会话独立 `@session.Session`，经 gateway 加法出口 `invoke_on(session, line)` 走 NDJSON 帧通道——**同进程多会话零 wasm 实例**（探针实证：`serve_handle` 本就 Session 参数化；wasm 实例 `#external` 句柄持有形态亦探通，作备选路径）。
- LRU 上限 8；空闲 5 分钟惰性逐出（每次 handle_line 入口扫描，过期收回披露）。
- 推进状态机：Opened（编译好未跑）→ Started（run+step.begin，可推进/暂停）→ 终态 Finished/Trapped/WaitingInput/Capped；**终局不可回退推进**，回看走缓冲。
- 引擎序列（v1 坑固化）：session.create → config.set（deterministic + 预算；漏调 = 快照面全空）→ compile →（惰性/推进）run → step.begin → step.next×N → output.delta。

## 壳层边界（TS 仅限无法 mbt 化的壳层——用户拍板）

- `cmd/mcp_js`（+js）：stdin 行循环 / 墙钟 / exit 全 extern "js"；渲染落盘 = v1 render.mjs（HTML 模板 + 播放器 + PNG 截图，浏览器资产）整体移植入 extern 块。产物 = node 直跑单文件。
- interactive 模式：gateway wasm-gc 产物（+wasmopt 后置）经 `VITRO_MCP_WASM` / `./engine/wasm.wasm` / `./wasm.wasm` 解析；缺失自动回落 static（mbt 恒算关键帧——回落即用；响应 mode/frame_count 取壳层实测值）。
- 帧数据逻辑（关键帧判据 / 预算抽稀 / 聚焦选择 / 投影）全在 mbt 侧单源。

## 验收与登记

- 白盒：`mcp/mcp_wbtest.mbt` 22 条（js/wasm-gc/native 三 target 全绿——**裸 moon test 含 mcp**，现值裸 1426；注入必红断言实验〔时点基线 1239〕变 1238/1 failed；mcp 挂 +wasm 随 gateway B3 口径入裸计数；含 PR #457 审阅 v2 批 P2×4 + P3-② 锚）。- 黑盒：`scripts/moonbit/mcp_smoke/accept.mts`（2026-11-04 收编入仓并挂 CI——原 D:/tmp 仓外件销案；27 断言 CI + PNG 预览断言仅本地）；CI 产物闸 = `scripts/moonbit/mcp_smoke`（18 断言，含 #468/#469 语法门与驱动对拍）。- 登记：pkg_deps L9 / surface 边表 10 条 / mbti_sync 豁免（同 gateway 病：canonical backend=wasm 而包不含 wasm）/ testcount 双 README（裸 1222→1275 / native 1271→1324，mcp 22 条 js/native 双域——as_of 2026-11-04 本地全量实测）。

## 待拍板

- mooncakes 0.10.0 发版节奏（mcp 随主包发布）/ npm `dsh-plugin-vitro` publish 时点。
- DSH 真机验证（hub/index.mjs 为推断级代码——本机未装 dsh）。
