# CLI 输出协议 v1（语言中立）

> 状态：**v1**（2026-10-04，CLI 出口总账 issue #37 批①②③落地随批冻结）
> 冻结锚点：本批提交（fixes #16 / refs #37）
> 归属：CLI 出口（`moonbit/cmd/*`——四薄壳 + `cmd/lib/cli` 逻辑层 + `cmd/vitro` 总入口）
> 消费者：agent / shell 脚本 / 仓库防线（vm_diff、clang_direct 的标记行剥离器）/ 任何第三方
> 关联规格：[`STEP_PAYLOAD_SCHEMA_V0_1.md`](STEP_PAYLOAD_SCHEMA_V0_1.md)——`--json` 模式的帧语义**引用不重复定义**（帧 = gateway 协议单源）
> 最后核对日期：2026-10-04

本文档是 CLI 的**输出契约**：消费方按此解析，无需了解 MoonBit 内部。协议变更纪律与 StepPayload 同源：**标记行前缀与退出码语义只增不改**；新前缀/新事件 type 走追加。

---

## 0. 出口形态与分派

| 形态 | 入口 | 用途 |
|---|---|---|
| 总入口单 exe | `vitro <cmd> [args]`（`moonbit/_build/native/release/build/cmd/vitro/`） | agent 主入口（run/compile/step/api 四子命令） |
| 独立 exe | `cmd/run`、`cmd/compile`、`cmd/step`（薄壳，行为与总入口同名子命令**逐字节一致**） | 防线调用面（vm_diff/clang_direct 硬编码 run.exe 路径） |
| 交互面 | `cmd/serve`（stdio NDJSON 会话协议——**不在本规格**，见 gateway 协议） | 长会话/断点交互/input.feed |
| dump 族 | `cmd/dump_{tokens,ast,typeck,compile}`（位置参数形态，**有意保留**——语法分叉登记 #37 B3） | 静态产物 |

`vitro` 的 argv 偏移约定：子命令逻辑层（`cmd/lib/cli`）统一收**已剥子命令名的参数**（独立 exe 传 `args[1:]`、总入口传 `args[2:]`——对逻辑层零差异）。

## 1. 文本模式输出协议（标记行）

stdout 由两类内容按序混合：**程序输出**（C 层 printf 原样，非 UTF-8 字节按 Latin-1 落文本——字节级归一由消费方处理）与**引擎标记行**。标记行前缀白名单：

| 前缀 | 语义 | 示例 |
|---|---|---|
| `// COMPILE-ERROR ` | 错误诊断（带码） | `// COMPILE-ERROR E3004 2:14 类型不匹配：无法将 'char*' 赋值给 'int'` |
| `// COMPILE-WARNING ` | 警告诊断 | `// COMPILE-WARNING W1018 -1:0 宏 'va_arg' 被重复定义…` |
| `// COMPILE-HINT ` | 提示 | `// COMPILE-HINT H3054 3:1 …` |
| `// COMPILE-OK ` | 编译通过标记（仅 `compile` 命令） | `// COMPILE-OK` |
| `// TRAP ` | 受检终止附注 | `// TRAP [uaf] Use-After-Free (E3060)：…` |
| `// NOTE ` | note 通道（完成附注「程序运行完成，返回值：N」+ 内存泄漏检测报告——2026-10-04 二轮审 P2 补，此前 CLI 整段丢失；内容可多行） | `// NOTE 程序运行完成，返回值：0` |
| `// EXIT ` | **末行**返回码（ret=0 时省略） | `// EXIT 7` |

诊断行格式：`// COMPILE-<级别> <码> <line:col> <文案>`——码与 serve 帧 `code` 字段同源（`E`/`W`/`H` + 数字；lexer 行 `line:col` 可为 `-1:0`——预处理层无位置态）。错误早退前也输出已收集的警告（agent 修错不丢信息）。

**例外登记（2026-10-04 性能实测复核）**：
- **codegen 段暂无 E 码**——行形态 `// COMPILE-ERROR codegen <文案>`（无码无位）：根因 = codegen 错误体系无诊断码（三出口三形态：Rust compile 零诊断 / mb CLI 出文案 / serve 进 errors 串不进 diagnostics——均照搬分叉④在案），且 E4 号段已被 C++ 预埋码占死（E4001~E4031/E4100+——砍 C++ 后死码但号段语义占用）；立码段与三出口统一挂 issue（退役后或码段拍板时）。
- **`// TRAP ` 标记可跨多行**（trap 教学文案：首行 `[语义 id]` 徽章 + `[timeline]`/`[cause]`/`[fix]`/`[location]` 附注行——**#27 方案 C（2026-10-07）：原 emoji 码点已退役为语义图标 id**，字形由下游按 id 经 serve `icons.get` 自取，文本消费方按方括号 id 归一比对不受影响）——消费方剥离按首行前缀 + 后续无前缀行与 oracle 同形（归一比对不受影响）。
- **stdout 通道尾换行形态**：`println(text)` 在程序输出后补一个换行（text 自带尾换行时双换行；空输出 2 个）——**两侧同形旧债**（Rust 同形态），防线归一器（首尾空行剥 + 恰一尾换行）吸收，退役随 Rust 消解。
- **文本模式 stdout 行尾为 CRLF**（Windows native 的 println 文本模式产物；`--json` 的 delta 为 LF）——仓库内消费方归一器已 `TrimRight(l,"\r")` 吸收；第三方按「程序输出原样」解析时须注意该平台差异（2026-10-04 二轮审 P3 登记）。
- **note 通道内容经 stdout 同管道输出**（Latin-1 折回形态与程序 stdout 同族——中文在 Windows 控制台呈现 mojibake 属 stdout 通道已知形态；字节级归一由消费方处理）。

**剥离规则（消费方实现要点，仓库内两处同构剥离器为参考实现**：`scripts/vm_diff` `extractMoonBitStdout` / `scripts/clang_direct` `extractMoonStdout`）：按精确前缀剥整行 + 末行 `// EXIT `；程序输出 `printf("// hi")` 是合法输出，**不得按 `// ` 前缀整行剥**。

## 2. 进程退出码（唯一消费方 = shell/agent——防线全部读标记行）

| 码 | 语义 |
|---|---|
| 0 | 正常结束（含 C `return 0`；非零返回值走 `// EXIT N` 标记行） |
| 1 | 编译错误（四阶段任一） |
| 2 | trap（受检终止） |
| 3 | 步数超限（trap 形态按步数事实判——`vm.step_count >= vm.max_steps`） |
| 4 | 用法/IO 错（文件不存在、参数不合法、未知子命令；**未收拢命令**（`dump-*`/`serve`）的分派提示也归此类——命令名合法但本入口不承载，属用法指导非执行错误） |

历史注：Rust oracle CLI 的 trap 退出码 = 1（与编译错混淆）——本表为 mb 侧有意规范化（#37 超越项）。**步数超限判定口径（2026-10-04 审阅 P3 统一）**：`run` 文本 = 引擎事实（`vm.step_count >= vm.max_steps`）；`run --json` = 帧结构位（`steps_executed` 恰等 max_steps——实测超限到达即停）；`step` = trap_message 的引擎固定文案前缀「程序执行步数超过限制」（帧无结构化步数位——该文案是引擎格式字符串，变更连坐 cli_step 判定）。

## 3. `run` 命令

```
vitro run <file.c> [-i <input.in>] [--dump-memory <out.bin>] [-- <argv...>] [--json]
```

- `-i`：stdin 注入文件（batch 模式——输入耗尽即 EOF 不交互，`while(scanf...)!=EOF` 习语不挂起；`--json` 模式下等效实现 = waiting_input 时 `input.feed` 续跑后重拉输出——2026-10-04 修正：初版静默丢弃，agent 得空输出 + rc=0 的静默错误）；
- `--`：其后全部透传给 C 程序 argv（`argv[0]` = 源文件路径，C 惯例）；**首个裸位置参数后的其余位置参数同样进 argv**（Rust vitro_cli :1010「未识别位置参数视为传给 main 的 argv」口径——2026-10-04 修正：初版取最后一个位置参数，分叉未登记）；
- `-`（文件位）：源码从进程 stdin 读（UTF-8）——**全命令通用**（run/compile/step；Rust `read_source` 同品类，B2）；
- `--dump-memory`：**`--json` 模式下不适用**（gateway 协议无 1MB 映像导出面——同时给出两旗标按 dump-memory 忽略处理）；
- `--json`：见 §6。

## 4. `compile` 命令

```
vitro compile <file.c | -> [--json]
```

只编译+诊断不执行；文本模式 = 三级诊断行 + `// COMPILE-OK`；`--json` 见 §6。

## 4.5 `api` 命令（万能单帧——全部协议方法的脚本化出口）

```
vitro api <method> [params-json]
```

- **用途（2026-10-04 用户拍板补）**：任何 serve 协议方法一次性调用——脚本统一测试出口（serve 交互式 stdio 需会话驱动胶水，前端测试人肉——api 把 21+4 方法全部拉平为「一行命令」）；响应帧 stdout 原样直出；
- params 缺省 `{}`；非 JSON 对象字面量 → 用法错 rc=4（fail loud）；
- 退出码：0=帧 `ok:true` / **1=帧 `ok:false`（协议内错误统一——含编译错/trap 报错帧，api 是透传层不细分语义）** / 4=用法错；
- **`--batch` 批式（状态跨帧保留）**：stdin 喂 NDJSON 请求帧序列 → 同进程顺序 invoke → 响应 NDJSON → EOF 退出——step.begin→next→seek/payload.get/breakpoints.set/input.feed 续跑等**前置依赖序列自此全部可脚本化**（`cat frames.ndjson | vitro api --batch` 即全链）；与 serve 的区别 = 管道终止型（无逐行交互锁）；rc=0 全帧 ok / 1 任一帧 ok:false / 4 用法错；
- 单帧形态会话态：每次 api 调用独立进程会话（跨调用不保留——会话场景走 --batch 或 serve 长会话）；
- 例：`vitro api ping` / `vitro api compile '{"source":"int main(){return 0;}"}'` / `vitro api ast.dump '{"source":"…"}'`。

## 5. `step` 命令（有意分叉登记：Rust `step` 是交互 REPL，mb 是一次性——交互面归 serve）

```
vitro step <file.c | -> [--max-steps N] [--json | --summary]
```

- `--max-steps` 经 config.set 传导至 step 族引擎预算（**2026-10-04 性能实测 Blocker 1 修正**：原引擎恒 UnifiedEngine::new() 默认 100_000——参数完全无效且 engine<vm 错配时预算到顶返回**假 finished**〔程序 35% 即报正常结束〕；修正后消费会话 config，到顶走 vm 层步数超限 trap 真语义）；默认 100_000；
- 默认 `--summary`：帧数 / 终态（`finished` / `trap` / `waiting_input/截断`）/ trap 死因文案；
- `--json`：每批 `step.next` 的 result JSON 一行（NDJSON——帧数组嵌行内，字段语义见 StepPayload schema）+ 末行 `{"type":"summary","frames":N,"finished":B,"trapped":B}` 收口；
- 执行序列：compile → run → step.begin → step.next（**run 先行**注入算法检测 matches——缺则帧的 `algorithm_step`/`vis_events` 恒空，demo 通道同坑实证）。

## 6. `--json` 事件流约定

**单一 NDJSON 流走 stdout**；程序原样输出保留给文本模式（标记行协议可管道解析）——agent 拿结构化、shell 管道拿原文，两模式各取所需：

| 命令 | 事件 |
|---|---|
| `run --json` | `{"type":"diag",...}` → `{"type":"run",...}` → `{"type":"stdout",...}` → `{"type":"note",...}`（note 通道：完成附注+泄漏报告——二轮审 P2 补） |
| `compile --json` | `<compile 帧>` 单行直透（含 `fix_suggestion` 七元组 + `algorithm_matches`〔teaching detect wire 出口——2026-10-04 补，#36 最小路径〕——比文本形态富） |
| `step --json` | `<step.next 完整响应帧 {id,ok,result}>` × N + `{"type":"summary",…}` |

`<帧>` = gateway 协议响应（`{id, ok, result…}`）**单源引用**——帧内字段语义一律见 [`STEP_PAYLOAD_SCHEMA_V0_1.md`](STEP_PAYLOAD_SCHEMA_V0_1.md) 与 gateway 协议文档，本规格不重复定义。

## 7. dump 族语法（有意分叉，登记保留）

Rust oracle 为 flag 形态（`-o`/`--raw`）；mb 为位置参数（`dump_tokens <dir|file> <out_dir> <raw|pp|both>` 等）——消费者是仓库内 Go 防线（调用面稳定优先），不收敛（#37 B1/B3）。

## 8. 版本与演进

- v1 冻结面：标记行前缀六种 / 退出码五值 / `--json` 事件 type 三种 + summary；
- 演进纪律：只增不改（新前缀、新事件 type、新子命令走追加；语义变更需版本化）；
- 历史分叉登记：Rust oracle CLI 与本协议的差异（trap 退出码 / dump 语法 / step 形态）随 Rust 退役自然消失。
