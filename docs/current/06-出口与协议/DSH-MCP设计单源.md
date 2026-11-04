> **收编说明（2026-11-04，PR #457 审阅 v2 P3-④ 销案）**：本设计单源原存仓外
> `D:/tmp/vitro-dsh-plugin/design.md`（读者无法核对——审阅实锤），现收编入仓
> 原样冻结（历史设计稿，文中「实现状态」为 v2 落地前时点快照；勘误与现状以
> [DSH-MCP服务器.md](DSH-MCP服务器.md) 与代码为准——「11 工具 / L0 4」勘误为
> 12 工具 / L0 5）。

# MCP 工具面设计 v2（vitro-dsh-plugin）

> **本版取代 v1（2026-11-02 用户拍板）**。v1→v2 的两点诊断：
> ① v1 的 `animate` 是上帝工具（编译→采帧→抽稀→渲染→截图一条龙）——agent 只做一次 RPC 转发，本质是 CLI 包壳，MCP 的 LLM-在环价值（工具组合、过程参与、上下文控制）全没用上；
> ② v1 三工具一次性全量披露——工具 schema 常驻每个请求的 system 前缀，且 DSH mcp-client 的 KV-cache 语义（调研实锤：*「工具定义前缀稳定才复用；工具集一变，从第一个变化的 schema token 起 invalidate」*）意味着全量披露是持续的 token 成本。
>
> v2 形态对标 **Serena**：有状态会话 + 动词化小工具 + 分层下钻 + **渐进披露（progressive disclosure）**。机制不照抄（serena 用配置过滤/onboarding，因它要适配多语言 LSP；我们用**会话状态驱动披露**，免配置，工具面 = 当下能做什么的函数）。
>
> **实现状态（诚实标注）**：当前 `server.mts` 实现的是 v1（3 工具，accept 7/7 PASS）；v2 为取代设计，落地清单见 §8。

## 1. 总原则

1. **agent 是操作员，不是售票员**：server 提供动作，agent 编排序列、控制上下文预算、做质量决策
2. **工具面 = f(会话状态)**：无会话时只挂 L0；首个 `session_open` 成功后解锁 L1，最后一个会话关闭后收回——布尔级切换，一次会话生命周期内工具集稳定（KV-cache 只在开关各失效一次）
3. **返回值同样分层**：默认紧凑投影 + 分页上限，显式 `fields` 要求才给全量（serena 的 overview→symbol→body 下钻逻辑用于帧数据）
4. **快捷层保留**：「用户就要一张动画」的场景真实存在，`animate` 作为编排糖（= `session_open` + 惰性采集 + `render` 预设）留在 L0——但不再是唯一路径

## 2. 工具命名

DeepSeek function-name contract 限 `[A-Za-z0-9_-]`，**一律下划线**（v2 弃用点号形态）：
DSH 侧暴露名 = `mcp__vitro__<name>`。

## 3. L0 永驻层（无会话即挂，4 工具，≈700 token schema）

### 3.1 `animate(source, options?)`
编排糖：open→惰性全采→render。返回 `{ok, html_path, frame_count, raw_step_count, algorithm_detected, arrays_focused, outputs, run, warnings[], size_bytes, ms}`；编译错产诊断卡 HTML。options 同 v1（mode/budget/focus/theme/audio_description/preview_png/title/out_dir）。

### 3.2 `diagnose(source)` → `{ok, diagnostics[], algorithm_matches[], ms}`
纯诊断，无会话、无产物。

### 3.3 `capabilities()` → 支持面自述 + **披露引导**
```json
{
  "progressive_disclosure": {
    "available_now": ["animate", "diagnose", "sessions", "capabilities"],
    "unlocked_by": "session_open(source)",
    "unlocks": ["frames_summary", "frames_query", "annotations", "run_to", "step_next", "render", "session_close"],
    "when_to_use": "一次性出动画用 animate；教学引导/质量调优/批量编排先 session_open"
  }
}
```
（serena 的 onboarding 话术压进一个工具返回，免专门 onboarding 机制。）

### 3.4 `sessions()` → `[{session_id, source_head, frames_collected, stopped, opened_at, expires_in_s}]`

## 4. L1 会话层（首个 session_open 后出现，7 工具，≈1.4K token）

### 4.1 `session_open(source, {files?, argv?, config_hint?, title?})`
引擎序列：`session.create → config.set（漏调=快照面全空，v1 实测坑，已固化） → compile`（**只编译不 run**）。返回：
```json
{
  "session_id": "s_a1b2",
  "compile_ok": true,
  "diagnostics": [{"code":"E2005","severity":"error","line":4,"column":13,"message":"…","fix":"…"}],
  "algorithm_matches": [{"name":"bubble_sort","display_name":"冒泡排序","confidence":85,"line":3}],
  "overview": {"functions":[{"name":"bubble_sort","lines":[3,11]}], "arrays":[{"name":"arr","len":6}], "line_count":18}
}
```
（get_symbols_overview 对应物：几百 token，agent 据此决策，不塞帧。）

### 4.2 惰性采集与推进式采集（会话内两条采集路径，共享同一帧缓冲）

- **惰性全采**：首次 `frames_summary / frames_query / annotations / render` 触发 `run → step.begin → step.next×N`（cap 20000），结果进缓冲
- **推进式**：`run_to / step_next` 面向交互引导，逐段推进写缓冲；批量采已 finished（终局）后 `run_to` 返回「已终局，用 frames_query 回看」
- 约束（如实）：每会话独占一个引擎实例（wasm 装载 8ms/实例，池上限 8 个 LRU；实例终局后不可回退推进，回看走缓冲）

### 4.3 `frames_summary()` → 帧结构索引（agent 的下钻入口，只读）
```json
{"total": 401, "labels_freq": {"交换 arr[0]↔arr[1]": 72, "循环 n=6, i=0": 11},
 "vis_events": {"loop": 54, "swap": 7}, "swap_pairs": [[0,1],[1,2],…],
 "arrays": [{"name":"arr","len":6,"mutations":21}], "heat_lines": [[4,33],[6,72]]}
```

### 4.4 `frames_query({from?, to?, limit?, filter?, fields?})` → 分页拉帧（只读）
- 默认投影 `{i,l,f,s}`（步/行/函数/字幕），limit≤50/页
- `fields:["r","v","c","e","a"]` 显式要求才给数组快照/变量/栈/vis_events/算法步
- `filter`: `{label_prefix?, line?, func?, has_vis_event?}`

### 4.5 `annotations({kind?})` → 语义事件流（只读）
交换对/循环迭代/调用事件的时序列表——「哪些帧值得看」的索引，供 agent 挑区间再 render。

### 4.6 `run_to({breakpoint_line | max_frames | stop_condition})` → `{advanced, paused_at?, trapped?, stopped}`
**形态 B 交互性的 agent 侧翻版**：agent 当导游（推进到第一次交换暂停，看现场，跟用户对话，再继续）。引擎 `breakpoints.set` 须在 `step.begin` 后（v1 调研实锤），已在序列固化。

### 4.7 `step_next({n?})` → 推进 n 个关键帧（推进式采集的细粒度档）

### 4.8 `render({mode, focus?, budget?, from?, to?, theme?, audio_description?, preview_png?, title?, out_dir?})`
**渲染与执行分离**：渲染会话缓冲的帧（可区间 `from/to`），不重跑引擎。返回同 v1 animate 的产物字段。

## 5. 渐进披露机制（MCP 原生）

1. `initialize` 回 `capabilities.tools.listChanged: true`
2. `tools/list` 按当前会话状态过滤返回集
3. 首个 `session_open` 成功 / 末会话关闭 → 发 `notifications/tools/list_changed`（DSH supervisor 的 re-sync 换代语义，其文档写明支持）
4. **annotations 权限分层**：只读工具（frames_*/annotations + L0 的 diagnose/capabilities/sessions）打 `readOnlyHint:true`——DSH 的 `tools/pre-execute` allow/deny/ask 门据此自动放行只读探查、仅对 render/run_to/session_open 问用户
5. 多会话并发：L1 工具靠 `session_id` 参数寻址（参数含 last-used 会话默认值），**工具集不随会话数变化**

## 6. 会话生命周期

- 池：每会话一个引擎实例，LRU 上限 8；空闲过期 5 分钟（`sessions()` 可见剩余寿命）
- `session_close({session_id?})` 显式关；无参关最近会话
- 过期后 L1 工具若指向死会话，返回可操作错误（「会话已过期，重新 session_open」）

## 7. v1 → v2 映射

| v1 | v2 去向 |
|---|---|
| animate | L0 保留（编排糖） |
| diagnose | L0 保留 |
| capabilities | L0 保留 + progressive_disclosure 段 |
| （无） | L1 全新 7 工具 + sessions + listChanged |

## 8. v2 落地清单（未实现，待批）

- `lib/engine.mjs`：会话池（EngineSession 类：实例+缓冲+推进状态机）+ 惰性采集触发器
- `server.mts`：工具表 11 条（L0 4 + L1 7）、`listChanged:true` + 通知时机、`tools/list` 状态过滤、annotations 标注、返回值投影/分页
- `accept.mts` 断言扩到 ~18 条，新增关键断言：**无会话时 tools/list 不含 frames_\*；session_open 后收到 list_changed 且重拉出现 L1；readOnlyHint 标注正确；frames_query 默认投影不含数组快照**
- 估 ~300 行改动，半天批；v1 行为（animate/diagnose）零破坏
