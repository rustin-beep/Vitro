# Vitro CLI 使用手册

> 最后核对日期：2026-10-16（**三臂单壳口径对齐 + 字段↔最低版本表批**——统一入口缺省臂 wasm→**js**〔三后端单壳批，三臂壳全 MoonBit〕、node ≥25 门槛勘正为 wasm 壳 MIN_NODE=22〔js-string builtins V8 下界，#132 降版批实测 node 24 全通〕、`scripts/vitro_cli/main.js` 已随 main.js 退役批删除、serve 节新增「字段 ↔ 最低版本」表〔#116〕、`step.next` 补 `frames` 参数〔病 76 实现化，2026-10-16〕。前一沿革 2026-10-07（**图标语义批〔#27〕**——协议面两变：`error_catalog` 的 `emoji` 字段退役为 **`icon`**〔语义图标 id，业务帧只携带 id 不携带字形〕；新接 **`icons.get`** 方法帧〔图标资产单通道下发，digest 与真源一致；protocol_frames 基线 31→33 帧〕。前一沿革 2026-10-06 统一入口批〔#49 批一〕——`scripts/bin/vitro` launcher 落地：默认 **wasm 臂**〔node 壳 `scripts/vitro_cli/main.js` 消费 `gateway/wasm/wasm.wasm`，需 node ≥25〕，node 缺失/过旧自动降级 native exe〔stderr 明示 `backend=` 行〕，`--backend native|wasm` 显式选边；双臂输出同形由 CI 闸 `scripts/vitro_cli_smoke` 对拍锁定。wasm 臂 `--dump-memory` 已支持（#49 批二：gateway `memory.dump` 帧——1MB 映像 base64 承载，双臂落盘逐字节一致由 CI 闸锁；`--json` 模式下不适用与 native 同口径〔spec §3〕）。更前一沿革 2026-10-05 S9 工序④删区整篇改单轨——Rust `vitro_cli` 章节整体退役〔历史形态见 tag `rust-oracle-freeze`〕；serve JSON-lines 协议语义章节保留——`moonbit/cmd/serve` 为同构现役实现））
> 出口定位：本文档是 CLI **使用指南**；输出协议契约（标记行/退出码/`--json` 事件流）见 [`docs/spec/CLI_PROTOCOL_V1.md`](../../spec/CLI_PROTOCOL_V1.md)——协议语义以 spec 为单一权威。完整出口清单与职责边界见 [出口分档与宿主策略.md](../06-出口与协议/出口分档与宿主策略.md)。

## 统一入口（推荐——agent / 脚本默认形态）

```bash
# sh 形态（Git Bash / Linux / macOS；Windows cmd 用 scripts\bin\vitro.cmd）
scripts/bin/vitro run corpus/baseline/array_sum_loop.c     # 缺省 js 臂
scripts/bin/vitro --backend native run <f>                 # 显式 native
scripts/bin/vitro --backend wasm   run <f>                 # 显式 wasm（node ≥22）
# 产物在位时零构建直跑；缺哪个臂构建哪个：
cd moonbit && moon build --release --target js cmd/vitro_js              # js 臂（缺省）
MOON_CC=clang moon build --release --target native cmd/vitro             # native 臂（防线基线）
cd moonbit && moon build --release --target wasm-gc gateway/wasm         # wasm 臂两件之一：wasm-gc 引擎
cd moonbit && moon build --release --target js cmd/vitro_wasm            # wasm 臂两件之二：MoonBit 胶水壳
```

臂语义（2026-10-15 三后端单壳批——三臂壳全 MoonBit，真相源 = `cmd/lib/cli` 单源）：**js** = `cmd/vitro_js` 直编 JS、node 直跑，免 wasm 实例化层，CLI 缺省臂；**native** = `cmd/vitro` exe，防线基线臂（vm_diff / clang_direct 消费面）；**wasm** = `cmd/vitro_wasm` 胶水拉 gateway wasm-gc，与浏览器分发同源。

降级链：node 不在 PATH 或 js 产物缺失 → 自动 fallback native exe，stderr 明示原因；wasm 壳 node <22 报 rc=5 哨兵降级（js-string builtins 的 V8 下界，node 24 实测全通）。任何形态 stderr 恒一行 `[vitro] backend=…` 标注（脚本可断言所在臂）；`--backend` 尾置 fail loud rc=4（#70）。三臂同形性由 CI 闸 `scripts/vitro_cli_smoke` 多臂对拍锁定（js/native/wasm 逐行一致）。

防线插座（#49 批二起，三后端批续扩）：`vm_diff` / `clang_direct` 支持 `--backend native|wasm`（缺省 native）；壳 `serve` 子命令（NDJSON 会话——与 cmd/serve 同形：shutdown 判停/EOF/空行回错误帧）；replay / serve_smoke / protocol_frames / teaching_annotation_diff wasm 臂同款插座（CI 并行）；codegen_diff/host_contract_map/diff_ledger 裁定不迁（#49 批三评论在案）。

## MoonBit 侧 CLI（agent 主入口）

```bash
cd moonbit && MOON_CC=clang moon build --release --target native cmd/vitro cmd/run cmd/compile cmd/step
# 产物：moonbit/_build/native/release/build/cmd/vitro/vitro.exe（及三薄壳）
```

```
vitro run <f> [-i in] [--dump-memory out] [-- argv...] [--json]   编译+执行
vitro compile <f> [--json]                                        编译+诊断单出
vitro step <f> [--max-steps N] [--json|--summary]                 一次性 step 流（交互调试走 serve）
vitro api <method> [params-json] | api --batch < frames.ndjson    万能单帧 + 批式多帧（状态跨帧——seek/断点/喂入序列可脚本化）
```

`api` 子命令是全部 serve 协议方法的**脚本统一测试出口**——单帧形态 `vitro api memory.regions`、`vitro api compile '{"source":"…"}'` 一行命令直出响应帧；**批式形态 `cat frames.ndjson | vitro api --batch`** 同进程顺序执行帧序列（状态跨帧保留——step.begin→next→seek/payload.get/breakpoints.set/input.feed 续跑等前置依赖序列全部可脚本化；与 serve 的区别 = 管道终止型，无逐行交互锁）。退出码 0=全帧 ok:true / 1=任一帧 ok:false / 4=用法错；单帧形态会话态跨调用不保留（会话序列走 --batch，长活驻留归 serve）。命令语义、标记行协议、退出码五值表（0=正常/1=编译错/2=trap/3=步数超限/4=用法 IO）、`--json` NDJSON 事件流、`-` stdin 源码形态（全命令通用）与 argv 偏移约定**一律见 [CLI_PROTOCOL_V1.md](../../spec/CLI_PROTOCOL_V1.md)**（本手册不重复协议内容）。dump 族与 serve 走独立 exe（`cmd/dump_*`、`cmd/serve`——B1 不收敛裁定）。

## Rust 侧 vitro_cli（已退役）

Rust 后端的 `vitro_cli`（compile / run / step / unified / serve 五命令与交互式单步调试）已随 2026-10-05 工序④删区**整体退役**——对应章节自本手册移除，完整历史形态见 tag `rust-oracle-freeze` 与 git 历史。现行等价物：

| 原 vitro_cli 命令 | 现行等价 |
|:---|:---|
| `vitro_cli run <file>` | `vitro run <file>` |
| `vitro_cli compile <file>` | `vitro compile <file>` |
| `vitro_cli step <file>`（交互式） | `vitro step <file>`（一次性流；交互走 serve） |
| `vitro_cli unified <file>` | `vitro step <file> --summary` / serve `step.begin`+`step.next` |
| `vitro_cli serve` | `cmd/serve`（见下节） |

## serve：JSON-lines 会话模式

长寿命 headless 会话进程：**stdin 每行一个 JSON 请求，stdout 每行一个 JSON 响应**（NDJSON）。
供 IDE 后端/判分服务/自动化脚本以任意语言消费，无需 ctypes 或 FFI。

```bash
cd moonbit && MOON_CC=clang moon build --release --target native cmd/serve
./_build/native/release/build/cmd/serve/serve.exe
```

现役实现 = `moonbit/cmd/serve`（native stdio 壳，协议层在 `gateway` 包——S7 批三号起以同构方法族承接，`serve_smoke` 以同一请求表对拍锁定）。

协议契约：

| 契约 | 说明 |
|---|---|
| **id 关联** | 请求可带 `id`（任意 JSON 值），响应原样回填 —— 便于异步/乱序对账 |
| **帧同构** | 成功帧 `{"id":N,"ok":true,"result":{…}}`，错误帧 `{"id":N,"ok":false,"error":{"kind":…,"message":…}}` —— 解析路径统一 |
| 错误 kind | `protocol`（请求格式/未知方法）/ `state`（会话状态不满足）/ `internal` |
| 入口语义 | 会话语义层单源（MoonBit 侧 = `vitro/engine/session` 包；运行结果/诊断/步 payload 形状各出口一致），出口间不产生语义分叉 |
| 会话配置 | `quarantine_budget` / `deterministic` / `max_steps` / `call_depth_limit` |
| 重置语义 | `session.reset` 清空编译/运行状态，**保留会话级配置**（隔离预算、判分确定性、argv） |
| **会话拓扑** | **单 serve 进程 = 单活跃会话**：方法表无并发句柄参数，`session.create`/`destroy` 都是"清空重建同一实例"；需要并发逻辑会话（如"长寿命诊断进程 + 瞬态运行进程"）时**起多个 serve 进程**——这是当前唯一受支持的并发形态（下游需求清单 D2）|

方法一览（**枚举权威 = `vitro api help` 生成物**〔gen_api_help 双产物单源，gateway dispatch 双向对账锁〕——本表为导览，方法扩张以 api help 为准，#113 归一）：

| 方法 | 参数 | 说明 |
|---|---|---|
| `ping` | — | 存活探测，返回引擎版本 |
| `compile` | `source`（或 `files:[{filename,source}]`） | 覆盖式编译当前单元集合，返回诊断 JSON |
| `run` | `input` / `argv` / `batch_input` / `max_steps` / `deterministic` | 全速运行，返回 `status`/`return_value`/`steps_executed` |
| `input.feed` | `text` | 增量喂入交互输入并续跑（`run` 返回 `waiting_input` 后调用；`text` 可多行，省略则仅续推进一步） |
| `output.delta` | `cursor` | 增量取输出（`cursor`/`total` 按**字节**计；`delta` 字符串为**逐字节 Latin-1 折回**——见 E-P1-5 字节语义） |
| `step.begin` | — | 初始化统一模式（时间旅行），需先编译成功 |
| `step.next` | `frames`（可选，缺省 1） | 单步/多帧推进，返回 `payloads`（StepPayload，见 [`docs/spec/STEP_PAYLOAD_SCHEMA_V0_1.md`](../../spec/STEP_PAYLOAD_SCHEMA_V0_1.md)）；`frames` ≤0/在场非整数（浮点·字符串·超 Int32 域）fail loud、超上限钳 `config.max_steps`（病 76 实现化 + 2026-10-17 审阅批值域补严——**在架 0.8.0 无此参数**，见下表） |
| `payload.get` | `start` / `end` | 取窗口内步 payload（窗口 2000 帧，越窗静默裁剪） |
| `seek` | `step` | 时间旅行定位（窗口外走检查点恢复 + 正向重放） |
| `ast.dump` / `typeck.dump` / `symbols.dump` | — | 静态 dump 族（AST / 类型检查 / 符号表导出——无需会话，只读语义不碰会话态） |
| `diagnostics_probe` | 位置参数 | 诊断探针（补全/悬停位——M15 无实现面，fail loud） |
| `memory.dump` | — | 1MB 内存映像 base64（与 CLI `--dump-memory` 同通道） |
| `breakpoints.set` | `lines:[int]` | 设置断点行集合（应在 `step.begin` 之后；**传 `[]` 清空断点 = 恢复执行**——命中暂停后的唯一"continue"口，见下方恢复语义） |
| `memory.regions` | — | **三段式内存地图**（`kind` = `global`/`stack`/`heap`，见下方说明）+ 隔离区统计 |
| `config.get` / `config.set` | 同上配置项 | 读写会话级配置 |
| `error_catalog` | — | 错误码表机器可读导出（`{catalog:[{code,code_str,lang,category,icon,title,explanation,common_causes[]}]}`，按 code 升序；`icon` = 语义图标 id（#27 方案 C——原 `emoji` 码点字段已退役），字形经 `icons.get` 单通道下发） |
| `icons.get` | `ids:[string]`（可选，缺省/空 = 全量） | **图标资产帧（#27 方案 C，2026-10-07）**：响应 `{schema,digest,viewBox,stroke_width,stroke_linecap,stroke_linejoin,fill,icons:{<id>:{paths:[…]}}}`——SVG path 数据 + 统一渲染参数按 digest 锁定下发；值域 = `moonbit/icons/index.tsv` 单源（icon_catalog 闸锁）；按请求序输出、重复 id 去重、含未知 id 整帧拒绝（fail loud 不静默缩水） |
| `texts.install` | `payload:string`（四段可选集：suggestions/builtin_notes/trap_messages/error_catalog） | **语言包装载帧（#130 批②/③b，2026-10-17）**：四段（suggestions/builtin_notes/trap_messages/error_catalog）运行时覆盖装载——批③b 扩诊断卡片段（码值域闸=catalog_codes——卡数随码表增长，2026-10-23 实测 108〔A 线 #214 批 +E3084/E3085〕，装前以 `error_catalog` 帧实数为准）——校验（suggestions/builtin_notes 两必到键 + trap_messages 可选段〔批③a：缺席=不碰引擎烘焙 trap，在场=校验后替换〕/suggestions 值域 43 名单/trap 占位符双向契约）全过后原子换装，失败 error 帧不落半装；成功回 `{suggestions,builtin_notes,trap_messages,error_catalog}` 四表装后计数。浏览器宿主懒加载语言包 js（`teaching/langpack` 产物）后经本帧注入；CLI wasm 臂启动即注入（烘焙语义保持）。**段内 schema（#244，2026-10-22 成文——此前下游须试错三轮才能装上）**：`payload` 是 JSON 文本，顶层四段**每段都是「整表等键替换」**（少一条即整帧拒绝——与 `texts.install` 装载门「含未知 id 整帧拒绝」同族裁定，#130）：`suggestions` = `{<43 算法名>: string}`（43 名单单源）、`builtin_notes` = `{<12 名>: string}`、`trap_messages` = `{<45 整数码>: string}`、`error_catalog` = `{<108 整数码>: {icon,title,explanation,common_causes[]}}`（卡数随码表增长——装前以 `error_catalog` 方法帧的实数为准，审阅 P2-6）——**键必须整数码**（`"E1001"` 字符串键会被拒），装前对照 `error_catalog`/`semantic_labels` 方法帧拿当前键集。**覆盖面分工（#243，2026-10-22 成文）**：装载替换的是 **`error_catalog` 帧的卡与三张文本表**；**编译/运行诊断帧的 `message`（静态码表文案——「发生了什么」）与 `fix_suggestion` 不受语言包控制**（本地化生效的是「怎么教」层——卡与附注）。「装语言包 → 诊断 message 变中/英」不成立属既定分工，非缺陷 |
| `semantic_labels` | — | `semantic_label` 受控词汇表导出（`{schema,discipline,labels:[{id,domain,template,example,status,since}]}`；词汇只增不改） |
| `contracts` | — | schema 版本轨道与行为契约（预留位字段名、v0.2 激活清单与字段台账、行为契约表） |
| `capabilities` | — | 机器可读能力清单（`engine_version`（含构建期 git 短哈希，可用于产物自检）、版本宏名义锚点、语言子集、内存模型常量、schema 轨道、行为契约） |
| `session.create` / `session.reset` / `session.destroy` | — | 会话生命周期（响应带 `session` 拓扑语义字段，见上表"会话拓扑"）|
| `shutdown` | — | 结束 serve 进程（EOF 亦可） |

**字段 ↔ 最低版本（#116，2026-10-16 起）**：协议纪律「只增不改」的版本归属落点——下游按在架版写消费代码前先查此表。在架 mooncakes 最新版 = **0.8.0**（`moon add --upgrade vitro/engine` 实测口径，2026-10-14）；标「HEAD」的条目**在架版尚不携带**，随下一版发布转正：

| 字段 / 方法 / 参数 | 载体 | 最低版本 | 出处 |
|---|---|---|---|
| `run` 响应 `output_truncated` | run 帧 | **HEAD（未发布）** | #91 截断位 |
| `run` 响应 `trap_code` | run 帧 | **HEAD（未发布）** | #261 trap 结构化 E 码（空串 = 无码形态；带码 trap 文案首段同步带 `(E####)`——按码查 error_catalog 教学卡） |
| `output.delta` 响应 `truncated_bytes` | delta 帧 | **HEAD（未发布）** | [CLI_PROTOCOL_V1](../../spec/CLI_PROTOCOL_V1.md) §8 DX ③（2026-10-11 追加） |
| `error_catalog[].icon`（替代 `emoji` 码点） | error_catalog 帧 | **HEAD（未发布）** | #27 语义图标 |
| `icons.get` 方法帧 | 方法表 | **HEAD（未发布）** | #27 图标资产单通道（protocol_frames 基线 33 帧） |
| `memory.dump` 方法帧 | 方法表 | **HEAD（未发布）** | #49 批二（git tag `vitro-engine-0.8.0` 实证无此方法） |
| 错误帧 `error.expected` | 错误帧 | **HEAD（未发布）** | #68 机器可读期望形状（错误帧白名单三键 kind/message/expected） |
| `step.next` 参数 `frames` | 方法参数 | **HEAD（未发布）** | 病 76（2026-10-16 实现化） |
| `texts.install` 方法帧 | 方法表 | **HEAD（未发布）** | #130 装载门（protocol_frames 基线 47 帧内容位更新） |

> 本表人工维护、以 `vitro api help` 生成物与 protocol_frames 基线为行为权威；**新字段上帧时必须在此登记版本归属**（#116），「HEAD」条目随发版改为实版号。表中未列出 = 0.8.0 在架已携带。

**`memory.regions` 的三段式（2026-09-12，下游需求清单 C2）**：`regions` 是统一数组，
每项带 `kind`，数组按地址升序；响应另带 `region_counts{global,stack,heap}`。

| `kind` | `name` | `alloc_line` | `alloc_by` | 备注 |
|---|---|---|---|---|
| `heap` | `heap_N` / `FILE:<path>` | 分配点行号 | `malloc` / `calloc` / `realloc` / `strdup` / `fopen` / `vfs` | 保留 `is_freed`（三色堆图） |
| `global` | 变量名 | 声明行 | `static` | 由 VM 全局符号合成 |
| `stack` | 函数名 | **进入该帧的调用行**（`main` 为 0） | `call` | `size` = 帧跨度 |

栈/全局区域**只在导出层合成**，不写回内部堆清单（堆统计口径不受影响）。

示例（一次会话跑完编译 → 运行 → 取输出 → 单步 → 收尾）：

```bash
$ ./_build/native/release/build/cmd/serve/serve.exe <<'EOF'
{"id":1,"method":"compile","params":{"source":"#include <stdio.h>\nint main(){ printf(\"%d\", 1+2); return 0; }\n"}}
{"id":2,"method":"run"}
{"id":3,"method":"output.delta","params":{"cursor":0}}
{"id":4,"method":"step.begin"}
{"id":5,"method":"step.next"}
{"id":6,"method":"step.next"}
{"id":7,"method":"session.reset"}
{"id":8,"method":"shutdown"}
EOF
{"id":1,"ok":true,"result":{"diagnostics":[],"ok":true,"preprocessor_trace":[],"algorithm_matches":[]}}
{"id":2,"ok":true,"result":{"ok":true,"return_value":0,"status":"finished","steps_executed":13,"trap":"","trap_code":"","waiting_input":false,"output_truncated":false}}
{"id":3,"ok":true,"result":{"cursor":36,"delta":"3程序运行完成，返回值：0\n","stream":"display","total":36}}
{"id":4,"ok":true,"result":{"max_collected_step":-1,"ready":true}}
{"id":5,"ok":true,"result":{"payloads":[],"finished":false,"trapped":false,"waiting_input":false,"paused":false,"current_line":0,"trap_message":null,"cache_start_step":0}}
{"id":6,"ok":true,"result":{"payloads":[{"step_index":0,"code_line":0,"func_name":"","semantic_label":"","algorithm_step":null,"local_vars":[],"call_stack":[],"vis_events":[],"heatmap_line":0,"heatmap_count":0,"accessed_vars":[],"array_snapshots":[],"pointer_snapshots":[],"root_cause_hint":null}],"finished":false,"trapped":false,"waiting_input":false,"paused":false,"current_line":0,"trap_message":null,"cache_start_step":0}}
{"id":7,"ok":true,"result":{"reset":true,"session":{"model":"single-active-session","active_sessions":1,"concurrent_sessions":false,"handle_parameter":false,"create_semantics":"clear-and-rebuild（清空重建同一实例）","reset_semantics":"清空编译/运行状态，保留会话级配置（隔离预算/deterministic/argv）","destroy_semantics":"清空重建（进程存活；如需回收进程请用 shutdown）","concurrency_recommendation":"并发场景起多个 serve 进程"},"config":{"deterministic":false,"quarantine_budget":262144,"input_mode_batch":false,"compiled":false,"max_steps":10000000,"call_depth_limit":10000,"output_budget":16777216}}}
{"id":8,"ok":true,"result":{"shutdown":true}}
```

> 上述输出为 2026-10-15 实测（MoonBit 侧；2026-10-16 文档批按 `serve_run.mbt` 现行
> 字段面补 id2 的 `output_truncated` 位——#91 字段恒携带，与快速入门同形示例一致；
> 替换 Rust oracle 时代旧示例——旧 id5 响应带
> `step_index:0` payload，早于「一帧发布缓冲」语义冻结日 2026-09-14）。**注意 id5**：
> `step.begin` 后**首次 `step.next` 恒返回 `"payloads": []`**（缓冲建立，尚无帧可发——
> spec STEP_PAYLOAD_SCHEMA「一帧发布缓冲」冻结契约第 1 条），第二次调用才吐出
> `step_index:0` 的帧；下游消费方不得假设首调有帧（#98 实测勘正）。字段顺序由 JSON
> 对象语义决定，消费方不应依赖顺序。
>
> **断点命中后的恢复语义（#101，2026-10-15 实测成文——两条路径，无专用 resume 方法）**：
> 断点命中后 `step.next` 恒返回 `paused:true` 且不推进——方法表**没有** `resume`/`continue`
> 方法，恢复走以下两条路径之一：
>
> 1. **清空断点续跑**（"continue" 语义）：`breakpoints.set {"lines":[]}` 后，下一次
>    `step.next` 起恢复推进（实测：命中行 line=5 paused 连续 7 帧 → 清空 → 下一帧
>    `paused:false`，此后正常出帧直至 finished）；
> 2. **`seek` 跳转**（"jump" 语义）：`seek {"step":N}` 落点即解除暂停，后续 `step.next`
>    正常推进。
>
> spec STEP_PAYLOAD_SCHEMA 的「恢复后缓冲重建——首个恢复响应为空 payloads（同首调）」
> 中的"恢复"即指上述两路径的触发，无隐式第三入口。IDE 实现方按路径 1 做 continue、
> 按路径 2 做 jump-to-line；每帧轮询 `paused` 位判断是否命中。
>
> **E-P1-5（输出通道）**：`output.delta` 默认返回 `stream:"display"` —— 即展示视图，除程序输出外
> 还含 Vitro 追加的"程序运行完成"提示与（有泄漏时的）泄漏报告，供 UI 原样显示。
> 需要**纯净程序 stdout**（判分 / 与 Clang golden 比对）时传 `"stream":"stdout"`：
>
> ```json
> {"id":3,"method":"output.delta","params":{"cursor":0,"stream":"stdout"}}
> ```
>
> 可用取值：`display`（默认）/ `stdout` / `stderr` / `note`（引擎附注）。引擎内部按
> `OutputKind` 给每段输出打标，消费方**不得**再对文本做正则清洗——此前散落十余处的
> "程序运行完成"清洗规则已在 E-P1-5 中全部废除（程序自己打印同类文本时会被误删）。
> **未知流名整帧拒绝（#258，2026-10-22）**：取值域是本节文档化的契约——传
> `"stream":"nope"` 等未登记值返回 `ok:false` + `error.kind:"protocol"`（`expected`
> 字段给值域），**不再静默降级 display**（旧形态表现为「成功但空内容」，下游无法
> 区分「程序没输出」与「流名写错」——`std_out`/`out` 等误拼会被吞）。大小写与首尾
> 空白经归一，别名仅 `note|notes`。
>
> **通道容量（#235/#241，2026-10-22 成文）**：单帧形态 `vitro api <method> '<params>'`
> 的参数走**进程命令行（argv）**，受 OS 命令行长度上限约束——Windows 约 32K 字符
>（实测约 27KB 源码，JSON 转义后）、Linux 约 2MB、macOS 约 256KB。**整表语言包
>（`texts.install` 四段全发，error_catalog 108 张卡实测 18.7KB 量级〔卡数随码表增长〕）与大源码必须走
> `--batch`（stdin 帧序列）**：
>
> ```bash
> cat langpack.ndjson | vitro api --batch   # {"id":1,"method":"texts.install","params":{"payload":"…"}}
> ```
>
> 超长参数在 Windows 上以底层 `CreateProcess`「文件名或扩展名太长」失败（连进程都
> 起不来，与 JSON 合法性无关）——遇到该错误即改走 `--batch`。
>
> **字节语义（#112，2026-10-15 成文——判分必读）**：所有通道的 `delta` 字符串都是
> **程序输出字节流的逐字节 Latin-1 折回**（每字节 → 一个 U+0000~U+00FF 字符），`cursor`/
> `total` 按字节计。这是**设计行为而非缺陷**：学生程序可能输出任意字节（含非法 UTF-8
> 的 GBK 中文），Latin-1 是唯一能无损过 JSON 字符串的单字节全字节域编码。**判分与
> Clang golden（UTF-8 文本）比对前必须先还原字节**：
>
> ```js
> // node：Latin-1 折回 → 原始字节 → UTF-8 文本
> const text = Buffer.from(frame.result.delta, "latin1").toString("utf8");
> ```
>
> ```python
> # python：同语义
> text = bytes(frame["result"]["delta"], "latin1").decode("utf-8")
> ```
>
> 若源程序输出非 UTF-8 编码（如 GBK），第二次 decode 换对应编码即可——字节在 `delta`
> 里始终无损。直接拿 `delta` 字符串与 golden 比对，中文程序必 mismatch。
> 同语义覆盖三出口：serve NDJSON 帧 / `vitro api output.delta` / `vitro run --json`
> 的 stdout/stderr/note 事件帧（见 CLI_PROTOCOL_V1 §6 通道总则）。
>
> 与 `jq` 配合：`serve < session.ndjson | jq -c 'select(.ok|not)'` 可只筛错误帧。
>
> **输入语义（`InputMode`）**：`run` 的 `batch_input`（默认 `false`）决定"输入耗尽"的含义：
>
> - `batch_input:false`（默认，交互）：`scanf`/`getchar` 在流耗尽时置 `waiting_input` 挂起，
>   等待 `input.feed` 供给——适合"学生逐行键入"的教学交互；
> - `batch_input:true`（批量/判分）：流耗尽即 **EOF**（`scanf` 返回 `-1`、`getchar` 返回 `-1`），
>   程序正常 `finished`——`while (scanf("%d", &n) != EOF)` 这类 C 第一课习语依赖此语义。
>   **判分 / 批量路径应以 `batch_input:true` 为准**（一次性给全 stdin 时语义等价于 EOF）。
>
> CLI 的 `vitro run <file> -i <input>`（headless 批处理）固定走 Batch，无需额外参数。
>
> **EOF 粘滞**（2026-09-12 补，对齐 C11 7.21.5.1 `feof`）：Batch 下**任一路径**首次判定
> "流耗尽"即置位 `stdin_eof` 并把读取游标推到底——此后 `scanf`/`getchar` 一律返回 `-1`，
> 未消费的尾部空白不会被"复活"重读。此前 `scanf` 触发的 EOF 对 `getchar` 不可见：
> 输入 `7\n` 时 Clang 给 `r1=1 r2=-1 c=-1`，Vitro 曾给 `c=10`。交互模式下调 `input.feed`
> 属"新内容到达"，会清除该粘滞位（管道语义下本不可复活，教学交互例外）。
>
> **交互喂入状态机**：`run` → `waiting_input` → `input.feed {text}` → `running`
> → `waiting_input | finished | trap`（`feed` 在非等待态亦可调用，文本追加到缓冲末尾后续跑）。
>
> ```json
> {"id":2,"method":"run","params":{"input":"7\n"}}          // → waiting_input
> {"id":3,"method":"input.feed","params":{"text":"35\n"}}   // → finished，读入 a=7, b=35
> ```
>
> 防线：`go run ./scripts/serve_smoke` 覆盖 id 关联 / 帧同构 / 生命周期 / 配置一致性 / 三段式内存地图 / schema 轨道与词汇表断言（CI 已纳入，脚本自报口径）。
>
> **已知形态差（登记不照搬）**：请求行 ≥65535 字节时 MoonBit 侧回 protocol
> 错误帧后干净退出（2026-09-29 超长行修复——静默丢弃违反协议演化纪律②）。

## 快速测试片段

无需创建临时文件，直接通过标准输入快速验证代码（`-` 文件位 = 源码从 stdin 读，全命令通用，见 spec）：

```bash
# 测试 printf（管道方式）
echo '#include <stdio.h>
int main() { printf("ok\n"); return 0; }' | vitro run -

# 测试循环（here-document 方式）
vitro run - <<'EOF'
#include <stdio.h>
int main() {
    int s = 0;
    for (int i = 1; i <= 100; i++) s += i;
    printf("%d\n", s);
    return 0;
}
EOF

# 测试 scanf + 输入（输入数据写文件后 -i 注入）
vitro run sum.c -i input.txt
```

> **注意**：当使用 `-` 从 stdin 读取源代码时，不能再通过 `-i -` 从同一 stdin 读取输入数据，建议将输入数据写入文件后使用 `-i data.txt`。
