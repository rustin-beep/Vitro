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
- `--vr-swap` 是交换事件标记色（D1）：ice/rose/soft/paper 四主题当前**有意复用**
  `--vr-ty` 同值（语法青），blueprint 独立取青蓝（不与 `--vr-ty` 同值）。
  **改 `--vr-ty` 时须同步四主题 `--vr-swap`**——tokens.json 没有 alias 机制，
  等值关系是设计约定；五主题存在性由 pure 测试锁，等值关系不在机判面。
- 语法色 `--vr-kw/ty/str/num/cmt` 是**主题化 token**：paper 主题用印刷批注色系
  （朱批/青碧/墨绿/赭石），e2e_editor N9 以「色度 ≥40」守门。

## 3. 字

- 三个字族各司其职：`--vr-serif` 标题与讲解、`--vr-sans` 界面正文、
  `--vr-mono` 一切数据面（帧号、地址、码表、代码）。
- **等宽面必须关连字**（`font-variant-ligatures: none`）——教学文本里的 `<=`
  不能被渲染成 `≤`（#121① 实锤；`demo_ui_lint` 有专项对账）。
- 字号档由 `--vr-fs` / `--vr-fs-code` 驱动（`data-size` 三档），组件不写死 px。

## 4. 形与动

- 圆角 `--vr-r`（纸/实验台系与手账系两档；具体数值唯一真源 `tokens.json`），阴影只给**锚定浮层**
  （`--vr-shadow`）；卡片/面板一律不投影。
- 动效只用于**状态过渡**与**事件指示**，不插值数据语义（柱高/格值永不 tween）；
  时长/曲线走 `--vr-t-fast / --vr-t / --vr-t-slow` + `--vr-ease / -emphasis /
  -enter`。相机平滑用 Tween（Svelte Spring damping 上限 1，快速档会过冲）。
  时间轴指针（D3）由 `src/lib/relayPlan.ts` 的计划表排程、`playhead.svelte.ts`
  按表执行（plan/play 两段分离；变速 = 整表乘系数）；指针的浮点位置只做视觉
  补间，读数与画面帧仍以整数帧为准，scrub 与 reduced 一律瞬时。
- `data-motion="off"` 必须整体关断（用户设置与 `prefers-reduced-motion` 双入口）；
  WAAPI 脉冲与 Svelte JS 过渡同样走 motion 层预算/门（批量 / scrub 全关；播放期
  swap 脉冲按计划表节拍抽稀放行，变量/树过渡仍让位），但**静态语义
  （class/attr/连线）不得随动效一起消失**——动效让位，语义不让位。
- **事件驱动优先**：交换/比较指示以引擎 `vis_events` 为准，相邻帧差分闪烁只在
  无事件时作兜底（差分是猜测，事件是引擎说的原话）。**没有帧级数据的地方不
  伪造生命周期动效**（MemoryView 用会话结束态，不做 alloc/free 进出场）。

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
- 改完跑：`node scripts/gen_demo_tokens/main.mts -check`、`npm run check`、
  `npm run lint`、`npm run build`、`node scripts/demo_ui_lint/main.mts`（本段全部命令以**仓库根**为 cwd，与本表其余行一致——#292 审阅 P3 实测此处原写 `../scripts/…` 混用）。

**Don't**

- 不写裸 hex / 裸 px 字号（主题切换时会各错一次）。
- 不用渐变、玻璃拟态、卡片阴影表达层级（层级靠字号/字重/留白/规则线）。
- 不为单一主题写例外色（例外 = 该主题的 token 值，不是组件里的分支）。
- 不手改 `src/tokens.css`（`@generated`）；改 `tokens.json` 后重跑生成器。
- 不给等宽面开连字，不用 emoji 承担语义。

## 7. 验证面

| 面 | 闸 |
|---|---|
| token 单源 ↔ 产物 | `node scripts/gen_demo_tokens/main.mts -check`（+ `-selftest`） |
| CSS 变量 / id / 连字 | `node scripts/demo_ui_lint/main.mts`（class 写操作位点当前 0——Svelte 组件态由 svelte-check 与 E2E DOM 锚守；文本闸只查 var/id/mono） |
| 裸值棘轮（禁裸 hex / 禁裸 px 字号） | `node scripts/demo_ui_lint/main.mts`（基线 `scripts/demo_ui_lint/raw_literals_baseline.json`：存量冻结、只减不增；清理后 `-update-raw` 收窄为人工令；`-selftest` 五路证红） |
| 类型 + a11y | `cd demo && npm run check` |
| 语义 lint | `cd demo && npm run lint` |
| 行为 | `node --test demo/tests/pure.test.mts` + E2E 五套（107 锚） |
| 样式契约（令牌 → 组件接线） | `node demo/tests/style_contract.mts`（五主题 × 选择器集 × computed 颜色/字体族/连字/字距；基线 `demo/tests/style_contract.json` 入库；`--update` 为人工令）。覆盖面只取工作态 exec 首课 DOM；目录/手册/内存/协议/专注页不在选择器集内（由 E2E 结构锚 + ui_lint 守，审查 P3 显式登记） |

> 像素闸（PNG 基线入库）已于 2026-10-22 由用户裁定退役：逐状态 PNG 基线跨 OS
> 需 CI 专用生成、入库体积与维护噪声大于收益。画面语义改由「样式契约（computed
> 值）+ E2E 行为锚 + ui_lint 文本面」三者守；不再保留截图基线目录/生成步骤。

## 8. 本文件的边界

- 不复制 token 数值（复制即第二真源）；需要查值看 `tokens.json`。
- 不写组件级实现细节（那是代码注释的事）。
- 改动本文件不触发任何闸——它是给人读的契约；机器闸只认 `tokens.json`。
