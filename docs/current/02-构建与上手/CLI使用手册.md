# Vitro CLI 使用手册

> 最后核对日期：2026-10-06（**统一入口批〔#49 批一〕**——`scripts/bin/vitro` launcher 落地：默认 **wasm 臂**〔node 壳 `scripts/vitro_cli/main.js` 消费 `gateway/wasm/wasm.wasm`，需 node ≥25〕，node 缺失/过旧自动降级 native exe〔stderr 明示 `backend=` 行〕，`--backend native|wasm` 显式选边；双臂输出同形由 CI 闸 `scripts/vitro_cli_smoke` 对拍锁定。wasm 臂 `--dump-memory` 已支持（#49 批二：gateway `memory.dump` 帧——1MB 映像 base64 承载，双臂落盘逐字节一致由 CI 闸锁；`--json` 模式下不适用与 native 同口径〔spec §3〕）。前一沿革 2026-10-05 S9 工序④删区整篇改单轨——Rust `vitro_cli` 章节整体退役〔历史形态见 tag `rust-oracle-freeze`〕；serve JSON-lines 协议语义章节保留——`moonbit/cmd/serve` 为同构现役实现）
> 出口定位：本文档是 CLI **使用指南**；输出协议契约（标记行/退出码/`--json` 事件流）见 [`docs/spec/CLI_PROTOCOL_V1.md`](../../spec/CLI_PROTOCOL_V1.md)——协议语义以 spec 为单一权威。完整出口清单与职责边界见 [出口分档与宿主策略.md](../06-出口与协议/出口分档与宿主策略.md)。

## 统一入口（推荐——agent / 脚本默认形态）

```bash
# sh 形态（Git Bash / Linux / macOS；Windows cmd 用 scripts\bin\vitro.cmd）
scripts/bin/vitro run corpus/baseline/array_sum_loop.c     # 默认 wasm 臂
scripts/bin/vitro --backend native run <f>                 # 显式 native
# 前置产物（缺哪个臂构建哪个）：
cd moonbit && moon build --release --target wasm-gc gateway/wasm            # wasm 臂
MOON_CC=clang moon build --release --target native cmd/vitro                # native 臂
```

降级链：node 不在 PATH 或版本 <25（壳 exit 3 哨兵）→ 自动 fallback native exe，stderr 明示原因；任何形态 stderr 恒一行 `[vitro] backend=…` 标注（脚本可断言所在臂）。

防线插座（#49 批二）：`vm_diff` / `clang_direct` 支持 `--backend native|wasm`（缺省 native）——wasm 臂被测物 = 统一入口壳（gateway wasm.wasm 主出口产物的实证面）；两臂 CI 并行全量。批三扩：壳 `serve` 子命令（NDJSON 会话——与 cmd/serve 同形：shutdown 判停/EOF/空行回错误帧；行长无上限对齐 oracle）；replay / serve_smoke / protocol_frames / teaching_annotation_diff wasm 臂同款插座（CI 并行）；codegen_diff/host_contract_map/diff_ledger 裁定不迁（#49 批三评论在案）。

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

方法一览：

| 方法 | 参数 | 说明 |
|---|---|---|
| `ping` | — | 存活探测，返回引擎版本 |
| `compile` | `source`（或 `files:[{filename,source}]`） | 覆盖式编译当前单元集合，返回诊断 JSON |
| `run` | `input` / `argv` / `batch_input` / `max_steps` / `deterministic` | 全速运行，返回 `status`/`return_value`/`steps_executed` |
| `input.feed` | `text` | 增量喂入交互输入并续跑（`run` 返回 `waiting_input` 后调用；`text` 可多行，省略则仅续推进一步） |
| `output.delta` | `cursor` | 增量取输出（字节游标，UTF-8 边界安全） |
| `step.begin` | — | 初始化统一模式（时间旅行），需先编译成功 |
| `step.next` | — | 单步推进，返回 `payloads`（StepPayload，见 [`docs/spec/STEP_PAYLOAD_SCHEMA_V0_1.md`](../../spec/STEP_PAYLOAD_SCHEMA_V0_1.md)） |
| `payload.get` | `start` / `end` | 取窗口内步 payload（窗口 2000 帧，越窗静默裁剪） |
| `seek` | `step` | 时间旅行定位（窗口外走检查点恢复 + 正向重放） |
| `breakpoints.set` | `lines:[int]` | 设置断点行集合（应在 `step.begin` 之后） |
| `memory.regions` | — | **三段式内存地图**（`kind` = `global`/`stack`/`heap`，见下方说明）+ 隔离区统计 |
| `config.get` / `config.set` | 同上配置项 | 读写会话级配置 |
| `error_catalog` | — | 错误码表机器可读导出（`{catalog:[{code,code_str,lang,category,emoji,title,explanation,common_causes[]}]}`，按 code 升序） |
| `semantic_labels` | — | `semantic_label` 受控词汇表导出（`{schema,discipline,labels:[{id,domain,template,example,status,since}]}`；词汇只增不改） |
| `contracts` | — | schema 版本轨道与行为契约（预留位字段名、v0.2 激活清单与字段台账、行为契约表） |
| `capabilities` | — | 机器可读能力清单（`engine_version`（含构建期 git 短哈希，可用于产物自检）、版本宏名义锚点、语言子集、内存模型常量、schema 轨道、行为契约） |
| `session.create` / `session.reset` / `session.destroy` | — | 会话生命周期（响应带 `session` 拓扑语义字段，见上表"会话拓扑"）|
| `shutdown` | — | 结束 serve 进程（EOF 亦可） |

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
{"id":6,"method":"session.reset"}
{"id":7,"method":"shutdown"}
EOF
{"id":1,"ok":true,"result":{"diagnostics":[],"ok":true}}
{"id":2,"ok":true,"result":{"ok":true,"return_value":0,"status":"finished","steps_executed":13,"trap":"","waiting_input":false}}
{"id":3,"ok":true,"result":{"cursor":36,"delta":"3程序运行完成，返回值：0\n","stream":"display","total":36}}
{"id":4,"ok":true,"result":{"max_collected_step":-1,"ready":true}}
{"id":5,"ok":true,"result":{"cache_start_step":0,"current_line":0,"finished":false,"paused":false,"payloads":[{"accessed_vars":[],"algorithm_step":null,"array_snapshots":[],"call_stack":[],"code_line":0,"func_name":"","heatmap_count":0,"heatmap_line":0,"local_vars":[],"pointer_snapshots":[],"root_cause_hint":null,"semantic_label":"","step_index":0,"vis_events":[]}],"trapped":false,"waiting_input":false}}
{"id":6,"ok":true,"result":{"config":{"compiled":false,"deterministic":false,"input_mode_batch":false,"quarantine_budget":262144},"reset":true}}
{"id":7,"ok":true,"result":{"shutdown":true}}
```

> 上述输出为 2026-09-11 实测（Rust 侧 oracle 时代记录；MoonBit 侧同一请求表经 serve_smoke 对拍锁定同一帧形状——字段顺序由 JSON 对象语义决定，消费方不应依赖顺序）。
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
