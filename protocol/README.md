# `@vitro/protocol`

Vitro **StepPayload 协议**（schema v0.1，冻结锚 `10591ad`）的 TypeScript 类型定义。

**本包的类型不是手写的**——由 `scripts/gen_protocol_ts` 从权威 Rust 源生成，
并与 `docs/spec/STEP_PAYLOAD_SCHEMA_V0_1.md` **双向对账**。手抄就是又一处分叉温床。

## 文件

| 文件 | 来源 | 说明 |
|---|---|---|
| `index.d.ts` | **生成物** | TS 接口与枚举类型（禁手改） |
| `fields.mjs` | **生成物** | 字段集 / 枚举值元数据（供无 TS 工具链的消费方做运行时校验） |
| `consumer.mjs` | 手写 | **第一个消费者**：用生成物消费真实引擎输出（字段级校验 + 最小渲染） |
| `package.json` | 手写 | npm 包元数据 |

## 权威源（谁说了算）

生成器读的是 **Rust 结构体**，不是 schema 文档：

- `native/src/unified/types.rs` — `StepPayload` 及多数子结构
- `native/src/unified/root_cause.rs` — `RootCauseHint`
- `native/src/session.rs` — `VisEvent`

理由：这些结构体是**编译期受字段冻结测试守护**的真实源
（`native/tests/step_payload_schema_v0_1_test.rs`）；schema 文档是人工维护的表述层。
故采用「**从实现生成 + 与文档双向对账**」——任一方向不同步都判红。

## 用法

```bash
# 再生成（源改了之后）
go run ./scripts/gen_protocol_ts

# 幂等校验 + 字段集与文档对账（CI 入口）
go run ./scripts/gen_protocol_ts -check

# 判据证红（三路内存注入）
go run ./scripts/gen_protocol_ts --selftest

# 第一个消费者：消费真实引擎输出（需先构建 release 引擎）
cd native && cargo build --release --bin vitro_cli && cd ..
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
2. **编译期收益未验证**：本环境有 node 但**无 npm / npx / tsc**，故只能验
   「生成物描述得了真实输出」（运行时字段校验），**验不了**「字段名写错在 tsc
   编译期即红」——而后者才是 TS 类型的核心收益。待 tsc 环境就绪后补。
3. **发布动作不在此处**：`npm publish` 属仓库持有者执行（贡献者无 npm 账号）。
   本目录只负责把包内容与门禁准备到可直接发布的状态。

## 版本纪律

`schema 字段只增不改语义`（见 schema §0）。包版本跟 schema 走：新增字段 = minor，
消费方**必须忽略未知字段**（`consumer.mjs` 对未知字段报错只是为了在 CI 暴露
「生成物落后于引擎」，不构成对消费方的要求）。
