# ViewDoc Schema v0.1.1（语言中立）

> 状态：**v0.1.1 现行**（2026-11-14，绘制下沉批 E，refs #470 / #517）。
> v0.1.0 为词表随批 D 入仓的草案（未单独落纸）；本版把 **`doc.series_decl`
> 出口**与宿主消费契约落纸，字段与批 D 词表一一对应。
> 真源：`moonbit/view/projectors.json`（投影器词表）→ `@generated
> projectors_gen.mbt`（MoonBit 数据面）+ `demo/src/lib/projectors.ts`（demo
> TS 词表）；序列化出口单源：`moonbit/view/view.mbt`（`doc_value` /
> `doc_json` / `parse_series_decl(_block)`）。
> 归属：见 [DSH-MCP设计单源](../../../docs/current/06-出口与协议/DSH-MCP设计单源.md)
> §3.1（render/animate 的 `viz` 参数与 `doc` 字段）。
> 消费者（现行）：MCP 产物壳（`moonbit/cmd/mcp_js`，自包含 HTML 按
> `series_decl` 绘制 bars/line/polar/spectrum + cells/grid2d）。
> 后续消费者：demo 换源、第三方宿主——按本 schema 解析即可，无需了解引擎内部表示。

本文档定义 **ViewDoc**：一次渲染产物「哪几条数组序列用什么投影器画」的
语义文档。引擎只出**语义契约**（合法投影器、序列条数/维度约束、声明本身），
**不出任何绘制**（DOM/SVG/CSS/动效归宿主）；场景不按变量名推断——傅里叶
只是课程/宿主一条普通声明 `series re im -> polar`。

---

## 0. 文档约定

| 约定 | 说明 |
|---|---|
| 传输编码 | UTF-8 JSON；作为渲染钩子 data 的 `doc` 字段原样嵌入（MCP 产物内 `window.__VITRO__.doc`） |
| 字段命名 | `camelCase`（`projectors[]` 项）/ `snake_case`（顶层 `series_decl`，沿用协议层习惯） |
| 枚举取值 | 投影器 id 为小写标识符，全族以 `projectors[].id` 为准（当前 6 个） |
| 版本化纪律 | **字段只增不改语义**；新增字段必须可空/有默认值；消费方必须忽略未知字段 |
| 缺省退化 | 生产者无声明时 `series_decl: []`——旧宿主忽略本字段即退化为原一维索引格行为 |
| 解析边界 | 声明**形态**由引擎解析；投影器**存在性**由消费点判（错误面板），引擎不因未知 id 拒绝整份文档 |

---

## 1. 顶层结构

```json
{
  "pv": "0.1.1",
  "default": "cells",
  "projectors": [
    {"id":"bars","seriesMin":1,"seriesMax":1,"minDims":0,"opts":["baseline","gain"],"note":"柱状：幅值 / 频谱幅度"}
  ],
  "series_decl": [
    {"series":["re","im"],"projector":"polar","opts":{"gain":"1"}}
  ]
}
```

| 字段 | 类型 | 必有 | 语义 |
|---|---|---|---|
| `pv` | string | 是 | 本文档协议版本；当前恒 `"0.1.1"` |
| `default` | string | 是 | 未声明序列的回退投影器（当前恒 `"cells"`；宿主实现必须覆盖） |
| `projectors` | array | 是 | **全族**投影器规格（禁抽样——新增投影器不重生成即两产物漂移，`-check` 红） |
| `series_decl` | array | 是 | 声明列表；空数组 = 无声明（全部按 `default` 画） |

## 2. `projectors[]` 项

| 字段 | 类型 | 语义 |
|---|---|---|
| `id` | string | 投影器标识（`bars` / `cells` / `grid2d` / `line` / `polar` / `spectrum`） |
| `seriesMin` | int | 该投影器需要的最少序列条数 |
| `seriesMax` | int | 最多序列条数；`-1` = 不限 |
| `minDims` | int | 首序列所需维度表（`array_snapshots[].dims`）长度；`>1` 表示必须多维 |
| `opts` | string[] | 已知选项键（未知键**不判错**，宿主原样保留/提示） |
| `note` | string | 人类可读说明（不参与判定） |

宿主绘制分派表（实现建议，非协议字段）：`cells`/`grid2d` = 索引格；
`bars`/`line`/`polar`/`spectrum` = 参数化图形。该映射属宿主实现，
**语义约束一律读 `projectors[]`，不在宿主侧复刻**。

## 3. `series_decl[]` 项

| 字段 | 类型 | 语义 |
|---|---|---|
| `series` | string[] | 参与同一投影的序列名；顺序 = 绘制顺序（同组即同图） |
| `projector` | string | 投影器 id（未知 = 消费点错误面板，不静默回落） |
| `opts` | object | 选项键值对（字符串；如 `gain` / `baseline` / `axis` / `group`）；键按字节序发射 |

### 3.1 声明文法（单源 = `@view.parse_series_decl`）

```
series <名…> -> <投影器> [k=v …]
```

- `series` 起首；序列名 ≥1 个；标识符 `[A-Za-z_][A-Za-z0-9_]*`；
- `->` 分隔；投影器 id 同标识符形态；
- 选项 `k=v`（空白分隔，键/值均不得为空）；
- 多行块：空行与 `//` 起首注释跳过；错误带 1 起行号（`第 N 行：…`）。

与课源 `<!-- vitri-viz v1 -->` 内 series 行**同形**——课源与众宿主共用
同一文法；课源版本号域与本文档 `pv` 域互不绑定（课源解析器只校验形态）。

## 4. 消费点判定（宿主必须一致）

对 `series_decl[]` 逐条、**逐帧**：

1. 投影器不在 `projectors[].id` → 错误面板（未知投影器）；
2. 序列名在当前帧快照缺失 → 错误面板（缺失清单）；
3. 条数 < `seriesMin` 或（`seriesMax >= 0` 且 > `seriesMax`）→ 错误面板；
4. 首序列 `dims` 长度 < `minDims` → 错误面板（缺维度表）；
5. 通过 → 按投影器绘制；被声明的序列**不再**以默认索引格重复出现；
6. 未声明序列按 `default` 画（一维 cells；多维按 `dims` 走网格）。

错误面板**不得静默降级**为默认画法（demo 宿主与 MCP 产物同款语义）。

## 5. 兼容性

- **additive-only**：新增字段（如 v0.2 的 `bar`/`ptr`/`cam` 动效位）不得改变
  既有字段语义；不兼容变更递增 `pv`。
- 旧产物（无 `doc` 字段）在消费方 = 无声明 → 默认索引格；新产物在旧宿主 =
  忽略 `doc` → 同一退化路径。
- `projectors` 与 `series_decl` 的**引擎侧字节确定性**：同输入必同字节
  （键序构造序固化 + 选项键字节序排序），`view_wbtest` 有锚。

## 6. 变更记录

| 版本 | 日期 | 变更 |
|---|---|---|
| v0.1.1 | 2026-11-14 | 首版落纸：`doc.series_decl` 出口 + `projectors[]` 全族规格 + 文法与消费判定；MCP `render`/`animate` 新增 `viz` 参数 |
