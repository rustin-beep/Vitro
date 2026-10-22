---
name: Vitro demo 前端设计契约
tokens: ./tokens.json
themes: [ice, rose, soft, paper, blueprint]
generated: src/tokens.css（@generated，禁手改）
---

# Vitro demo · 设计契约（DESIGN.md）

> 本文件只写**意图与负约束**，不复制任何 token 数值——数值唯一真源是
> [`tokens.json`](tokens.json)，CSS 产物 `src/tokens.css` 由
> `scripts/gen_demo_tokens` 生成（CI `-check` 逐字节比对）。三层分工：
> **行为** `AGENTS.md`／**任务** `.agents/skills/`／**外观** 本文件 + tokens.json。

## 1. 一句话主张

**教科书的左页 × 实验仪器的右页**：讲解与执行同屏，一屏回答「执行到哪、为什么、
下一步」。三个关键词：**分镜（scene）· 此刻（now）· 可验证（verifiable）**。

## 2. 色

- **每个主题只有一枚强调色**（`--vr-amber*` 家族，即该主题的「此刻」色）；其余
  颜色只承担语义：`--vr-red*` = 错误/trap，`--vr-green*` = 通过/golden。
- 结构色一律走 `--vr-bg / panel / panel-2 / ink / ink-2 / ink-3 / rule / rule-2`，
  **禁止**在组件里写裸 hex（五主题会各错一次）。
- 语义底色一律用 `*-tint` 变体，不手调透明度。
- 语法色 `--vr-kw/ty/str/num/cmt` 是**主题化 token**：paper 主题用印刷批注色系
  （朱批/青碧/墨绿/赭石），e2e_editor N9 以「色度 ≥40」守门。

## 3. 字

- 三个字族各司其职：`--vr-serif` 标题与讲解、`--vr-sans` 界面正文、
  `--vr-mono` 一切数据面（帧号、地址、码表、代码）。
- **等宽面必须关连字**（`font-variant-ligatures: none`）——教学文本里的 `<=`
  不能被渲染成 `≤`（#121① 实锤；`demo_ui_lint` 有专项对账）。
- 字号档由 `--vr-fs` / `--vr-fs-code` 驱动（`data-size` 三档），组件不写死 px。

## 4. 形与动

- 圆角 `--vr-r`（纸/实验台系 3px、手账系 8px），阴影只给**锚定浮层**
  （`--vr-shadow`）；卡片/面板一律不投影。
- 动效只用于状态过渡，时长/曲线走 `--vr-t` / `--vr-ease`；`data-motion="off"`
  必须整体关断（设置与 `prefers-reduced-motion` 双入口）。

## 5. 五主题的意图（不是五套皮肤）

| 键 | 名称 | 意图 |
|---|---|---|
| `ice` | 明亮实验室 | 冷白底 + 蓝强调；默认的「实验台」 |
| `rose` | 奶油手账 | 暖粉底 + 新拟物双阴影；只在本主题允许软阴影语言 |
| `soft` | 绒面深蓝 | 深底 + 低对比；长时间阅读 |
| `paper` | 白天（纸） | 纸色底 + 印刷批注色；投影/课堂 |
| `blueprint` | 夜航图 | 技术图纸：直角、细线、网格；录屏/展示 |

## 6. Do / Don't

**Do**

- 新颜色/尺寸先问「这是 token 吗」：是 → 加进 `tokens.json` 再生成；不是 → 说明
  它为什么是一次性局部值。
- 数据面（帧号、地址、输出、代码）用 mono；叙事面用 serif/sans。
- 状态用语义 token（red/green/amber）+ 一句话原因 + 一个动作。
- 改完跑：`go run ./scripts/gen_demo_tokens -check`、`npm run check`、
  `npm run lint`、`npm run build`、`go run ./scripts/demo_ui_lint`。

**Don't**

- 不写裸 hex / 裸 px 字号（主题切换时会各错一次）。
- 不用渐变、玻璃拟态、卡片阴影表达层级（层级靠字号/字重/留白/规则线）。
- 不为单一主题写例外色（例外 = 该主题的 token 值，不是组件里的分支）。
- 不手改 `src/tokens.css`（`@generated`）；改 `tokens.json` 后重跑生成器。
- 不给等宽面开连字，不用 emoji 承担语义。

## 7. 验证面

| 面 | 闸 |
|---|---|
| token 单源 ↔ 产物 | `go run ./scripts/gen_demo_tokens -check`（+ `-selftest`） |
| 类名/CSS 变量/连字 | `go run ./scripts/demo_ui_lint` |
| 裸值棘轮（禁裸 hex / 禁裸 px 字号） | `go run ./scripts/demo_ui_lint`（基线 `scripts/demo_ui_lint/raw_literals_baseline.json`：存量冻结、只减不增；清理后 `-update-raw` 收窄为人工令；`-selftest` 五路证红） |
| 类型 + a11y | `cd demo && npm run check` |
| 语义 lint | `cd demo && npm run lint` |
| 行为 | `node --test demo/tests/pure.test.mts` + E2E 五套 |
| 样式契约（令牌 → 组件接线） | `node demo/tests/style_contract.mjs`（五主题 × 选择器集 × computed 颜色/字体族/连字/字距；基线 `demo/tests/style_contract.json` 入库；`--update` 为人工令） |
| 画面语义（像素） | `node demo/tests/visual_regress.mjs`——16 状态（工作台首/中帧 × paper/blueprint、目录、手册、内存、协议、trap / 编译失败 / 空输出 / 坏链、768/390）× 逐像素 diff（阈值 0.1%），耗时文本走掩膜；**基线只能由 CI runner + Chrome 生成**（本仓 CI = `windows-latest`；拍板稿的 Ubuntu 假设与现状不符——基线在同一 runner 镜像内自洽，跨 OS 复用仍由 `platform` 守卫拦住）（`workflow_dispatch` 选 `visual_baseline=yes` → artifact → 入库），未武装时打印 `::warning::` 跳过（不伪造通过） |

## 8. 本文件的边界

- 不复制 token 数值（复制即第二真源）；需要查值看 `tokens.json`。
- 不写组件级实现细节（那是代码注释的事）。
- 改动本文件不触发任何闸——它是给人读的契约；机器闸只认 `tokens.json`。
