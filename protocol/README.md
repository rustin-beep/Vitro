# `@vitro/protocol`

Vitro **StepPayload 协议**（schema v0.1，冻结锚 `10591ad`）的 TypeScript 类型定义。

**本包的类型不是手写的**——由 `scripts/gen_protocol_ts` 从权威 MoonBit 源（`moonbit/protocol/types.mbt`）生成，
并与 `docs/spec/STEP_PAYLOAD_SCHEMA_V0_1.md` **双向对账**。手抄就是又一处分叉温床。

> **真源沿革（#118 勘正，2026-10-15）**：初版生成链读 Rust 对照区结构体（`native/src/…`，
> 当时受 Rust 字段冻结测试守护）；Rust 区已随 2026-10-05 工序④**物理删除**（档案 tag
> `rust-oracle-freeze`），真源随 #39 迁移收拢至 MoonBit 侧 protocol 包（编译期受 wbtest
> 锚守护）。本节旧「权威 Rust 源」表述已过时——生成器 `-check` 的对账面以 MoonBit 生成源
> ↔ schema 文档为准（`node scripts/gen_protocol_ts/main.mts -check` 即验）。

**投放状态（#118 勘正）**：`@vitro/protocol` **尚未发布到 npm**（`npm view` 404 属预期）——
消费形态现阶段 = 仓内 `protocol/` 目录直接引用（`index.d.ts`/`fields.mjs` 生成物 +
`consumer.mjs` 消费者），npm 投放待下游需求出现时随批（勿按已上架接入）。

## 文件

| 文件 | 来源 | 说明 |
|---|---|---|
| `index.d.ts` | **生成物** | TS 接口与枚举类型（禁手改） |
| `fields.mjs` | **生成物** | 字段集 / 枚举值元数据（供无 TS 工具链的消费方做运行时校验） |
| `consumer.mjs` | 手写 | **第一个消费者**：用生成物消费真实引擎输出（字段级校验 + 最小渲染） |
| `package.json` | 手写 | npm 包元数据 |

## 权威源（谁说了算）

生成器读的是 **MoonBit 结构体**（`moonbit/protocol/types.mbt`——protocol 包零依赖自持），
不是 schema 文档。理由：该结构体是**编译期受 wbtest 字段锚守护**的真实源（字段数/词汇表
长度断言在 `protocol` 包测试面）；schema 文档是人工维护的表述层。
故采用「**从实现生成 + 与文档双向对账**」——任一方向不同步都判红。
（初版真源为 Rust 结构体，2026-10-05 删区后随 #39 迁移收拢 MoonBit 侧——见上方沿革注。）

## 用法

```bash
# 再生成（源改了之后）
node scripts/gen_protocol_ts/main.mts

# 幂等校验 + 字段集与文档对账（CI 入口）
node scripts/gen_protocol_ts/main.mts -check

# 判据证红（三路内存注入）
node scripts/gen_protocol_ts/main.mts --selftest

# 第一个消费者：消费真实引擎输出（现役 MoonBit 产物——初版的 rust 臂
# debug serve 已随 2026-10-05 删区退役）
cd moonbit && moon build --target native cmd/serve && cd ..
node protocol/consumer.mjs            # 字段级校验 + 最小渲染
node protocol/consumer.mjs --selftest # 消费者判据证红（含正向）
```

消费方（TS 侧）：

```ts
import type { StepPayload } from '@vitro/protocol';
import { SCHEMA_VERSION, FIELDS, ENUMS } from '@vitro/protocol/fields';
```

## 已知边界（诚实登记）

1. **§5 差分层未覆盖**：`StepStreamBatch` / `StepPayloadDelta` 不在生成范围。
   该节表格是压缩式（多字段合并一行，如 `step_index / code_line / func_name_idx /
   semantic_label_idx`），无法逐字段机判；且它们是编码细节，不是内容消费者的必需面。
   待 v0.2 轨道决定（见 `scripts/gen_protocol_ts/rules.json` 的 `_scope_note`）。
2. ~~编译期收益未验证~~ **已验证并反向证红（2026-10-04，demo TS 重写批顺带
   闭合）**：npm 10.9.7 + tsc 5.9.3 实测在位（原「无 npm」断言过时勘正）——
   正向：`import type { StepPayload }` + SCHEMA_VERSION/ENUMS/FIELDS 零错；
   反向：`PointerStatus = "Zombie"` → TS2322、字段拼错 → TS2339（编译期收益
   成立）。**剩余缺口**：`fields.mjs` 无声明文件（TS7016）——`gen_protocol_ts`
   量产 `fields.d.mts` 待做（rules.json 加 out 条目复用 writeOrCheck，成本低）。
3. **发布动作不在此处**：`npm publish` 属仓库持有者执行（贡献者无 npm 账号）。
   本目录只负责把包内容与门禁准备到可直接发布的状态。

## 版本纪律

`schema 字段只增不改语义`（见 schema §0）。包版本跟 schema 走：新增字段 = minor，
消费方**必须忽略未知字段**（`consumer.mjs` 对未知字段报错只是为了在 CI 暴露
「生成物落后于引擎」，不构成对消费方的要求）。
