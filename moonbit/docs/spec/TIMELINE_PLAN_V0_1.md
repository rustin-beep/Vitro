# TimelinePlan Schema v0.1（语言中立）

> 状态：**v0.1 现行**（2026-11-15，动效编排下沉批一，refs #470；#469 归属口径沿用）。
> 真源：`moonbit/timeline/plan.mbt`（结构 + 生成器 + 序列化单源）；
> 消费面：gateway `timeline.plan` 只读方法、MCP `render`/`animate` 的
> `doc.timeline` 字段；demo/interactive 宿主换源属后续批。
> 归属：[DSH-MCP服务器](../../../docs/current/06-出口与协议/DSH-MCP服务器.md) 与
> [ViewDoc Schema v0.1.1](VIEW_DOC_SCHEMA_V0_1_1.md)（同一渲染数据信封）。

本文档定义 **TimelinePlan**：帧选择（各宿主的关键帧抽取）之上的
「每帧动效意图」语义层。引擎只出**意图**（交换脉冲对 + 字幕段 + 量感/持续档），
**不出任何绘制**（类名表 / 时长 token / 布局几何归宿主执行器）；
场景不按变量名或字幕文本猜——交换归属只认 `vis_events` 的 `context`。

---

## 0. 文档约定

| 约定 | 说明 |
|---|---|
| 传输编码 | UTF-8 JSON；作为渲染钩子 data 的 `doc.timeline` 原样嵌入（MCP 产物内 `window.__VITRO__.doc.timeline`）；gateway 方法结果为其裸值 |
| 字段命名 | `snake_case`（沿用协议层习惯） |
| 版本化纪律 | **字段只增不改语义**；不兼容变更递增 `pv`（additive-only，对齐 StepPayload 惯例） |
| 存在性纪律 | **键缺省 = 无，禁空串**——无字幕不产 `cap`、无交换不产 `sw`；不得用 `""` 占位 |
| 对齐纪律 | `steps[k]` 与**选中帧集**零基同构（`steps.length == frames.length`）；消费方必须校验，错位即 fail loud |
| 边界 | 不塞 StepPayload；v0.1 只有 `sw`/`cap`，v0.2 的 `bar`/`ptr`/`cam` 等预留字段**不提前落** |

---

## 1. 顶层结构

```json
{"pv":1,"steps":[
  {"sw":{"name":"a","i":0,"j":1},"cap":{"t":"交换 a[0]↔a[1]","w":2,"dur":1}},
  {}
]}
```

| 字段 | 类型 | 必有 | 语义 |
|---|---|---|---|
| `pv` | int | 是 | 本文档协议版本；当前恒 `1` |
| `steps` | array | 是 | 逐帧意图；与选中帧集**等长**（零基同构），可空（零帧） |

## 2. `steps[]` 项

| 字段 | 类型 | 必有 | 语义 |
|---|---|---|---|
| `sw` | object | 否 | 本帧交换脉冲对；缺省 = 本帧无交换 |
| `cap` | object | 否 | 本帧字幕段；缺省 = 本帧无字幕 |

### 2.1 `sw`（交换脉冲对）

| 字段 | 类型 | 语义 |
|---|---|---|
| `name` | string | **真实数组名**（`vis_events.context` 点名的快照名；非字幕展示名） |
| `i` | int | 升序下界（`min(extra0, extra1)`） |
| `j` | int | 升序上界（`max(extra0, extra1)`） |

归属判据（生成器单源，逐条）：

1. 只认 `ty == 2` 且 `context` 非空的 vis 事件；
2. `context` 须**唯一点名**本帧数组快照中的一个名字（标识符边界：
   `obj.arr[` / `barr[` 不算 `arr[`；名字后可跳空白接 `[`）；
3. 下标须整数、非负、`i != j`、`j < 数组长度`（越界事件丢弃——旧壳层规则
   `hi >= len` 属可观察行为，bubble_sort 实测 2 帧 `a[4]↔a[5]` 越界）；
4. 归属缺失（无 context / context 不点名 / 多数组歧义）→ **不产 `sw`，不猜**；
5. 多事件帧取事件序首个可归属者（v0.1 单 `sw` 容量）。

> 数组长度进入生成器最小视图是**等价性要求**：不带长度会让 `a[4]↔a[5]`
> 越界事件也点亮，交换帧集合与旧路径 54 vs 56 分叉（等价对拍闸实测）。

### 2.2 `cap`（字幕段）

| 字段 | 类型 | 语义 |
|---|---|---|
| `t` | string | 字幕原文（= 帧 `semantic_label`；空标签不产 `cap`） |
| `w` | int | 量感档：`1` 常规字幕帧 / `2` 交换帧（`3` 预留 v0.2 高亮事件） |
| `dur` | int | 持续档：v0.1 由 `w` 派生 = `w - 1`（`0` 快档 / `1` 标准档；`2` 慢档预留 v0.2） |

---

## 3. 生成与消费

- **生成器输入** = 最小帧视图（`code_line` / `func_name` / `semantic_label` /
  `vis_events` / 数组快照「名字+长度」）——宿主无关，`timeline` 是 L0 纯语义包，
  不依赖任何宿主内部 Frame 类型（禁反向依赖）。
- **gateway `timeline.plan`**：`{start?, end?}` 帧区间（左闭右开，缺省 0..窗尾，
  与 `payload.get` 同语义）→ plan JSON；会话须已 `step.begin`；负/倒序区间
  fail loud。
- **MCP `render`/`animate`**：`doc.timeline = plan(选中帧)`（与 `doc.series_decl`
  同一版本化 `doc` 信封；`doc.pv` 不因 additive 字段递增）；壳层 PLAYER 只读
  `plan.sw`/`plan.cap` 渲染交换高亮与字幕，不再自带归属正则。
- **消费方义务**：读 `steps[k]` 前校验 `steps.length == frames.length`
  （生成器侧 `validate` 与产物侧 smoke/等价闸双保险）。

## 4. 兼容性

- **additive-only**：新增字段（v0.2 的 `bar`/`ptr`/`cam`）不得改变既有字段语义；
  不兼容变更递增 `pv`。
- 旧产物（无 `doc.timeline`）在消费方 = 无计划（壳层字幕回空、无交换高亮）；
  新产物在旧宿主 = 忽略 `doc.timeline` → 原行为。
- 字节确定性：键序构造序固化（`pv→steps`、`sw→cap`、`name→i→j`、`t→w→dur`），
  `timeline` 白盒锚锁逐字节形态。

## 5. 等价证据（批一）

`timeline_equiv`（CI `cli_smoke` slice）对同一真实产物逐帧对比「旧规则冻结副本
vs plan 路径」：

| 案例 | 帧数 | 交换帧（旧/plan/DOM） | 交换格（旧/plan/DOM） | 字幕 / stage 类名 |
|---|---|---|---|---|
| bubble（真名=展示名 `arr`） | 301 | 3 / 3 / 3 | 6 / 6 / 6 | 逐帧一致 |
| bubble_sort（真名 `a` ≠ 展示名 `arr`） | 81 | 54 / 54 / 54 | 108 / 108 / 108 | 逐帧一致 |

## 6. 变更记录

| 版本 | 日期 | 变更 |
|---|---|---|
| v0.1 | 2026-11-15 | 首版落纸：`sw`/`cap` 字段面 + 归属/存在性/对齐纪律 + gateway `timeline.plan` 与 MCP `doc.timeline` 接线 |
