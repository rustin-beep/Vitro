# TimelinePlan Schema v0.2（语言中立）

> 状态：**v0.2 现行**（2026-11-15，动效编排下沉批四，refs #470；v0.1 批一/批二/批三已落）。
> 真源：`moonbit/timeline/plan.mbt`（结构 + 生成器 + 序列化单源）；
> 消费面：gateway `timeline.plan` 只读方法、MCP `render`/`animate` 的
> `doc.timeline` 字段、interactive 页内 `planStep` 镜像、demo session 组聚合。
> 归属：[DSH-MCP服务器](../../../docs/current/06-出口与协议/DSH-MCP服务器.md) 与
> [ViewDoc Schema v0.1.1](VIEW_DOC_SCHEMA_V0_1_1.md)（同一渲染数据信封）、
> [意图→类名映射表](../../../docs/current/06-出口与协议/意图-类名映射表.md)（三端执行器登记）。

本文档定义 **TimelinePlan**：帧选择（各宿主的关键帧抽取）之上的
「每帧动效意图」语义层。引擎只出**意图**（交换脉冲对 / 字幕段 / 量感档 /
变化格 / 相机提示 / 进场标识），**不出任何绘制**（类名表 / 时长 token /
布局几何 / 像素下限归宿主执行器）；场景不按变量名或字幕文本猜——交换归属
只认 `vis_events` 的 `context`。

---

## 0. 文档约定

| 约定 | 说明 |
|---|---|
| 传输编码 | UTF-8 JSON；作为渲染钩子 data 的 `doc.timeline` 原样嵌入（MCP 产物内 `window.__VITRO__.doc.timeline`）；gateway 方法结果为其裸值 |
| 字段命名 | `snake_case`（沿用协议层习惯） |
| 版本化纪律 | **字段只增不改语义**；不兼容变更递增 `pv`（additive-only，对齐 StepPayload 惯例） |
| 存在性纪律 | **键缺省 = 无，禁空串/空对象占位**——无字幕不产 `cap`、无交换不产 `sw`、无变化不产 `ch`、非数值数组不产 `bar`、栈不变不产 `cam`、无进场不产 `enter` |
| 对齐纪律 | `steps[k]` 与**选中帧集**零基同构（`steps.length == frames.length`）；消费方必须校验，错位即 fail loud |
| 帧集语义 | `ch`/`cam`/`enter` 的变化基准 = **输入帧集内前一帧**（选中帧集语义——与抽稀边界一致；不是全局上一指令帧） |
| 边界 | 不塞 StepPayload；v0.2 不含 `ptr`/`sem`（预留字段，本版不落） |

---

## 1. 顶层结构

```json
{"pv":2,"steps":[
  {"sw":{"name":"a","i":0,"j":1},"cap":{"t":"交换 a[0]↔a[1]","w":2,"dur":1},
   "ch":{"a":[3]},"bar":{"a":[0.62,0.31]},
   "cam":{"fit":"calltree","func":"bubble_sort","depth":2},"enter":"func:bubble_sort"}
]}
```

| 字段 | 类型 | 必有 | 语义 |
|---|---|---|---|
| `pv` | int | 是 | 本文档协议版本；v0.2 起恒 `2` |
| `steps` | array | 是 | 逐帧意图；与选中帧集**等长**（零基同构），可空（零帧） |

## 2. `steps[]` 项

| 字段 | 类型 | 必有 | 语义 |
|---|---|---|---|
| `sw` | object | 否 | 本帧交换脉冲对；缺省 = 本帧无交换 |
| `cap` | object | 否 | 本帧字幕段；缺省 = 本帧无字幕 |
| `ch` | object | 否 | 变化格差分集（v0.2）；缺省 = 无值变化 |
| `bar` | object | 否 | 量感条归一比例（v0.2）；缺省 = 无可绘数组 |
| `cam` | object | 否 | 相机关键帧（v0.2）；缺省 = 相机保持 |
| `enter` | string | 否 | 进场标识（v0.2）；缺省 = 无进场 |

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
5. 多事件帧取事件序首个可归属者（v0.2 仍单 `sw` 容量）；
6. **同名快照**：全局数组与数组形参解引用视图可能同名双发
   （`array_snapshots` 出现两条同名项）——按 name 去重（**后写覆盖**，
   与宿主 `r[name]=` 的 Map 语义同口径），**不算归属歧义**；不得因重名丢 `sw`
   （PR #530 审阅 P1-1：gateway 面曾整片丢光、MCP 面 Map 天然免疫）。

> 数组长度进入生成器最小视图是**等价性要求**：不带长度会让 `a[4]↔a[5]`
> 越界事件也点亮，交换帧集合与旧路径 54 vs 56 分叉（等价对拍闸实测）。

### 2.2 `cap`（字幕段）

| 字段 | 类型 | 语义 |
|---|---|---|
| `t` | string | 字幕原文（= 帧 `semantic_label`；空标签不产 `cap`） |
| `w` | int | 量感档：`1` 常规字幕帧 / `2` 交换帧（`3` 预留） |
| `dur` | int | 持续档：v0.2 由 `w` 派生 = `w - 1`（`0` 快档 / `1` 标准档；`2` 慢档预留） |

### 2.3 `ch`（变化格差分集，v0.2）

`{数组名: [升序变化下标...]}`——cur 相对**输入帧集内前一帧**的逐元素比较
（快照 elements 显示字符串相等判据）。规则：

1. 前帧无该数组 / 长度不等 → 该名字不产键（首现与结构变化不是「值变了」）；
2. 全部下标无变化 → 不产 `ch` 键（禁空对象占位）；
3. 键序 = 数组快照首见序；值升序；
4. 多数组各自独立键；同名快照按 2.1-6 去重后比较。

> 消费边界：`ch` 的基准是 **plan 输入帧集**（MCP 静态 = 关键帧集）。demo 的
> 「值变化」基准是相邻**可视帧**（语句组选择层），与 plan 基准不同语义——
> demo 语句级 `changed` 由宿主差分承担（映射表登记），`insn` 粒度可用 plan.ch。

### 2.4 `bar`（量感条归一，v0.2）

`{数组名: [逐元素比例...]}`——`ratio = |v| / max(1, max|v|)`（本帧该数组）。
规则：

1. 仅**整组可解析为有限数值**且 `element_ty != "char"` 的数组产；
2. 元素数 = 数组长度；比例 ∈ `[0,1]`；
3. 像素下限 / 条高档 / 是否画条由宿主执行器决定（本字段只给内容量感）。

### 2.5 `cam`（相机关键帧，v0.2）

| 字段 | 类型 | 语义 |
|---|---|---|
| `fit` | string | 拟合目标类别；v0.2 只有 `"calltree"`（旧执行器按未知值回落默认档） |
| `func` | string | 栈顶函数名（`call_stack` 末项；空栈 = `""`） |
| `depth` | int | 调用栈深度 |

产帧条件：**首帧恒产**（初始镜头）；栈顶或深度相对前帧变化才产；其余帧缺省
（相机保持）。宿主按自身树把 func/depth 映射到节点几何（引擎不持有宿主树）。

### 2.6 `enter`（进场标识，v0.2）

字符串，受控值域：

| 值 | 语义 |
|---|---|
| `"diag:<category>"` | 根因首现（`root_cause_hint.category` 相对前帧变化）——优先级高 |
| `"func:<name>"` | 栈顶函数变化（进入/离开函数） |

首帧不产（初始不是「进场」）。宿主自行映射到 UI 动作（诊断卡级联 / 树入场 /
根因卡入场）；无消费面的宿主忽略。

---

## 3. 生成与消费

- **生成器输入** = 最小帧视图（`code_line` / `func_name` / `semantic_label` /
  `vis_events` / 数组快照「名字+元素+元素类型」/ `call_stack` / `root_category`）
  ——宿主无关，`timeline` 是 L0 纯语义包，不依赖任何宿主内部 Frame 类型
  （禁反向依赖）；唯一 core 依赖 = `moonbitlang/core/string`（bar 数值解析）。
- **gateway `timeline.plan`**：`{start?, end?}` 帧区间（左闭右开，缺省 0..窗尾，
  与 `payload.get` 同语义）→ plan JSON；会话须已 `step.begin`；负/倒序区间
  fail loud。
- **MCP `render`/`animate`**：`doc.timeline = plan(选中帧)`（与 `doc.series_decl`
  同一版本化 `doc` 信封；`doc.pv` 不因 additive 字段递增）；壳层 PLAYER 只读
  plan 字段渲染（static）；interactive 页内 `planStep(fr, prev)` 镜像按 live
  帧实时产 plan（同函数两语言，等价由 mcp_smoke 逐帧锚锁）。
- **demo**：worker `collect`/`feed` 后拉 `timeline.plan`（指令帧全集）→ session
  按语句组聚合（sws/bar/cam/enter）；归属判据不在宿主重复实现。
- **消费方义务**：读 `steps[k]` 前校验 `steps.length == frames.length`
  （生成器侧 `validate` 与产物侧 smoke/等价闸双保险）；`pv` 不兼容即拒读。

## 4. 兼容性

- **additive-only**：v0.2 新增字段不改变 `sw`/`cap` 语义；不兼容变更递增 `pv`
  （v0.1 = 1，v0.2 = 2）。旧消费方（只认 pv=1）读 v0.2 plan 必须拒读并按
  「无计划」处理——fail loud 或回退旧判据，不得静默半读。
- 旧产物（无 `doc.timeline`）在消费方 = 无计划（壳层字幕回空、无交换高亮、
  无 changed/bar）；新产物在旧宿主 = 忽略 `doc.timeline` → 原行为。
- 字节确定性：键序构造序固化（`pv→steps`、`sw→cap→ch→bar→cam→enter`、
  `name→i→j`、`t→w→dur`、`fit→func→depth`），`timeline` 白盒锚锁逐字节形态。

## 5. 等价与内容证据

| 闸 | 覆盖 |
|---|---|
| `timeline_equiv`（CI cli_smoke） | 旧规则冻结副本 vs plan 路径：bubble 301 帧 / bubble_sort 81 帧（真名 a ≠ 展示名 arr，含 2 帧越界）/ same-name 59 帧——交换帧集合、swap/changed 类名、字幕 HTML 逐帧一致；人造分叉锚锁静态路径真消费 plan |
| `mcp_smoke`（CI cli_smoke，24 断言） | doc.timeline pv=2 / steps==frames / sw 真名 54 帧 / ch 与帧差分一致 / bar 长度与域 / cam 首帧栈变 / enter 值域；**EMBED planStep 镜像 == 引擎 plan 逐帧全字段**（v0.2 六字段）；旧归属规则退役断言 |
| `timeline_wasm_anchor`（CI serve_channel） | wasm-gc 产物经 Node 宿主实例化：timeline.plan 内容不变量（pv=2 / steps==payloads / ch 差分一致 / bar 域 / cam/enter 形态）——浏览器交付同源面内容锚 |
| `mcp_wbtest` / `serve_timeline_wbtest` / `plan_wbtest` | 生成器判据与字节形态（含 v0.2 四字段、ch 差分、bar 归一、cam/enter 帧集语义、J9 错位/pv 不兼容） |
| demo E2E（D1/D1b/D3） | plan 链路真消费（planPv=2 / planSteps==rawN / sw 真名 / bar 长度 / cam 首帧）+ 多数组归属 + 双数组计划表 |

## 6. 变更记录

| 版本 | 日期 | 变更 |
|---|---|---|
| v0.1 | 2026-11-15 | 首版落纸：`sw`/`cap` 字段面 + 归属/存在性/对齐纪律 + gateway `timeline.plan` 与 MCP `doc.timeline` 接线 |
| v0.1 | 2026-11-15 | PR #530 审阅处置：§2.1-6 补「同名快照按 name 去重（后写覆盖长度）」口径（gateway 面曾整片丢 sw、MCP 面 Map 免疫） |
| v0.2 | 2026-11-15 | 批二：interactive 页内 `planStep` 镜像换源（旧 legacySwapPair/ctxMentions 退役）。批三：demo 消费换源（pairList/字幕/`@swap` 锚读 plan）+ root_cause 显示。批四：v0.2 字段 `ch`/`bar`/`cam`/`enter` additive 落纸（`pv` 1→2）；MCP 静态壳层 ch/bar 换源；interactive 镜像同步六字段；wasm 臂内容锚 |
