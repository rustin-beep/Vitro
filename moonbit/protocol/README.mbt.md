# vitro/engine/protocol — StepPayload schema 契约与协议演化纪律

C 教学引擎的**协议冻结层**（L8）：StepPayload v0.1 十四字段白名单（冻结于 2026-09-12）+ v0.2 预留位与字段台账 + semantic_label 受控词汇表 + 协议 DTO 族（StepPayload/快照/帧数据，**零依赖自持**——协议冻结的意义即不随引擎内部类型漂移）+ 展开粒度可执行判据。L8 session/gateway 与 cmd/serve 消费本包，本包不依赖任何引擎包。

## 安装

```bash
moon add vitro/engine/protocol
```

## 协议演化纪律（三条，2026-09-28 成文——openseek 对照纪律批 ③）

同语言先行者 moonbitlang/openseek 的协议演化教训转译（架构不互鉴——其 stdout 是 57 变体单向事件流、Vitro 是 RPC 方法族；借的是纪律）。**这三条对协议的所有变更生效，包括 v0.2 激活与任何 v0.x 追加**：

### 1. 缺省字段双条件规则

一个协议字段**可以缺省**当且仅当满足以下两条之一：

- 它**晚于所在 schema 版本冻结引入**（git log -S 取证可证——如 v0.1 冻结后追加、按 v0.2 台账登记的字段）；
- 它**自诞生即可选**（schema 表格显式标注 optional）。

「下游暂时没人用」**不是**缺省理由——读者的未知 tolerance 不由写者代理决定。v0.1「词汇只增不改」的旧读者语义由此首次成文：旧读者读新帧，遇到不认识的字段按本规则推出版本信息，而不是靠字段缺省猜。

### 2. 未知容忍非对称：读不懂的请求必须报错帧

**写侧宽容、读侧严格**：

- **请求**（上行）：serve 收到未知 method / 无法解析的帧，必须回 `protocol` 错误帧——**沉默是调用方唯一无法处置的回应**（连接还开着但语义死了；openseek 实证：静默吞掉的坏请求直到下游数据缺失才暴露，链路越长排查越贵）。本仓 serve 的未知方法回错已同构（serve_wbtest `serve_unknown_method_error` 锚），本条补「为什么」的文档面。
- **响应**（下行）：新增字段是允许的（规则 1），但字段**语义**不得对旧读者突变——`semantic_label` 词汇表是先例：只增不改，扩充走追加条目。

### 3. 单解码器佐证：一个 wire format 只有一个解码器

本仓 MoonBit 侧的自写 `json_parse`（cmd/serve）是 serve 帧的**唯一**解码器；TS 侧类型由生成器从权威源产出（`scripts/gen_protocol_ts`）。openseek 的教训是反例背书：其 `usage` 类型故意只有 ToJson 无 FromJson——因为**双解码器意味着两个漂移面**，穷举测试都难以覆盖（其双写漂移直到穷举解码才被发现）。凡引入第二个解码路径（如缓存层重序列化、跨语言镜像解析），必须先在本包登记并给出为何无法收敛单解码器的理由。

## Option→Json 出口组合子（纪律的前置件）

```mbt check
///|
test {
  // Some → 值；None → null：绝不单元素数组、绝不字段省略
  inspect(
    @protocol.json_or_null(Some(Json::number(7))).stringify(),
    content="7",
  )
  inspect(@protocol.json_or_null(None).stringify(), content="null")
  // 派生 ToJson 的 [v] 形态在此通道上不可能出现（显式 match）
  let m : Map[String, Json] = Map([])
  m.set("hint", @protocol.json_or_null(None))
  m.set("payload", @protocol.json_or_null(Some(Json::boolean(true))))
  inspect(
    Json::object(m).stringify(),
    content="{\"hint\":null,\"payload\":true}",
  )
}
```

消费点：S8 step 族 emitter（`StepPayload.payload : StepPayload?` / root_cause_hint 字段族）与 dump 族——接线前落位（总计划批四号段排期），首个消费者出现前无主（surface 白名单登记）。

## schema 契约与词汇表的可执行面

```mbt check
///|
test {
  // v0.1 十四字段白名单（对账单源 = scripts/replay/v01_payload_fields.json）
  inspect(@protocol.step_payload_fields_v0_1().length(), content="14")
  // 词汇表 14 条 = 10 active c 域 + 4 reserved csharp 域（只增不改）
  inspect(@protocol.semantic_label_vocabulary().length(), content="14")
  // schema 版本轨道（v0.1 冻结日期是协议事实，不是文档装饰）
  inspect(@protocol.SCHEMA_VERSION, content="v0.1")
}
```
