# Vitro MoonBit 引擎

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## English

**Vitro Engine** is the MoonBit implementation of the [Vitro C teaching engine](https://github.com/rustin-beep/Vitro) — a compiler front-end and bytecode codegen for a teaching subset of C, kept in byte-for-byte parity with the original [Rust oracle](https://github.com/rustin-beep/Vitro) (diagnostic catalog, AST dumps, canonical bytecode output).

| Package | Layer | What you get |
|---|---|---|
| `vitro/engine/source` | L0 | `SourceLoc` + column contract (UTF-8 byte offset + 1) + dual-coordinate `Pos` |
| `vitro/engine/opcode` | L0 | 135 opcodes with stable numbering (44–46 = C# exception triple, 47–49 reserved) + `Instruction` |
| `vitro/engine/util` | L0 | Zero-semantic mechanical helpers: `utf8_len` (UTF-8 byte length) / `str_cmp` (true lexicographic order — built-in String compare is not) / `i64_to_i32_bits` / little-endian byte reads |
| `vitro/engine/fs` | L0 | Native-only file-system helpers **vendored from moonbitlang/x@0.5.5** (2026-09-28): 7 public functions + `IOError`; C symbols prefixed `vitro_engine_fs_*`; upstream drift watched by `scripts/moonbit/vendor_drift` (content-hash probe, CI hygiene) |
| `vitro/engine/diag` | L1 | 137-arm `ErrorCode` + severity/lang + teaching catalog (77 cards), byte-exact export |
| `vitro/engine/ast` | L2 | Type 17 / Expr 26 / Stmt 16 family + depth metrics + `type_eq` + C rendering & mangle + JSON dump |
| `vitro/engine/names` | L3 | Naming single source: `__ctor__`/`__dtor__` family + 17-variant type-mangle suffix |
| `vitro/engine/lexer` | L4 | Standalone preprocessor pass + `LineMap` + host IO; token contract in `lexer/token` |
| `vitro/engine/parser` | L4 | token → AST: expression cascade / declarator spiral / stmt & decl families; depth-guarded with stall fuse |
| `vitro/engine/libc` | L5 | Builtin signature table (57) + libc call allowlist (175) |
| `vitro/engine/typeck` | L5 | C-subset type checking + lowering (4 passes); auto/typeof deduction; array/struct init sizing |
| `vitro/engine/bytecode` | L6 | Output schema + R1 layout pure functions + canonical dump emitter |
| `vitro/engine/codegen` | L6 | `BytecodeGen` state machine with dual entry: `compile` / `compile_library`; slot strategy v1 |
| `vitro/engine/memory` | L7 | 1 MiB linear-memory carrier + `MemoryMap` heap state machine (bump + bounded quarantine + first-fit) + single checked-access entry + ordered `freed_logs` |
| `vitro/engine/host` | L7 | Host-function domain: 110-route consumption side, byte-faithful output channels (`Bytes`), 100+ VM-independent handlers (memory / ctype / math / string / str-to-num / printf-scanner / VFS) returning structured replies |
| `vitro/engine/vm` | L7 | Executor state machine + snapshot system (`VMSnapshot` Full/Delta, two-endpoint single-point) + C# exception triple exec-state (handler stack / exception register / UNWINDING — v1 design input) |
| `vitro/engine/session` | L8 | 会话骨架 + SessionConfig 值对象（单一真相源 + 单一写入口，消 Rust setup_vm 覆盖事故面三段式）+ 多文件安全 source_line_at + 会话侧 DTO 族（S7 批二号） |
| `vitro/engine/protocol` | L8 | StepPayload schema contract (v0.1 frozen whitelist + v0.2 ledger/activation checklist + behavior contracts) + semantic_label controlled vocabulary (14 entries) + protocol DTO family + unwind granularity predicate (S7 batch 1, zero-dependency) |
| `vitro/engine/gateway` | L8 | wasm-gc single export (F-5 ruling): NDJSON frame protocol layer lifted to an engine-neutral carrier (`invoke` String→String carrying the 21-method table / `reset` / `protocol_version` / `engine_version`), js-builtin-string zero-copy passing, zero functional imports; `library` form shared by native consumers (cmd/serve shell) and the wasm shell (S7 batch 5) |
| `vitro/engine/gateway/wasm` | L8 | Thin wasm-gc-only shell: the four `#export_name` entry points (foreign_library + wasm-gc single target); Node host driver in repo `scripts/wasm_gateway/host.js` (16 assertions) |

Stability guarantees: diagnostic codes and opcode numbering are **versioned constants — append-only**; exhaustive matches have no fallback arm, so new enum cases surface as compile errors in dependents. Import the whole module or pick per-package dependencies — layers only point downward.

## Performance (honest disclosure, measured 2026-09-26)

The VM is an interpreter built for stepping and time-travel observability, not raw speed. Measured against the Rust oracle on the same machine: end-to-end small-program runs are **1.42×** slower (compile-dominated; median over 366 baseline cases), compute-intensive programs **1.92×–15.7×** slower (fib(20) / bubble-200 / 500×500 nested loops), and the full engine runs the 300×300 loop benchmark at **10.1×** the oracle's JIT path. Full-speed execution is scheduled to move to a bytecode→wasm-GC generator (planned for **0.7.0+**), whose mapping covers this gap; the interpreter keeps serving single-step and time-travel semantics.

```moonbit
let code = @diag.ErrorCode::from_code(3053).unwrap()
code.display_code()          // "W3053"
code.severity().to_str()     // "warning"
code.catalog()               // Some(teaching card: title / explanation / common causes)
```

The rest of this README is in Chinese.

---

C 教学引擎的 MoonBit 实现——137 个诊断错误码、135 条字节码操作码、Type/Expr/Stmt 全族 AST 与 C 渲染/mangle，码表与 [Vitro Rust oracle](https://github.com/rustin-beep/Vitro) 逐字节对拍对齐。

## 安装

```bash
moon add vitro/engine        # 或按包引入 vitro/engine/diag 等
```

**关于 `cmd/` 子包**：本模块附带 5 个命令行工具（`cmd/dump_tokens` /
`cmd/dump_ast` / `cmd/dump_typeck` / `cmd/dump_compile`——差分对拍工具，
与 Rust oracle 产物逐字节比对；`cmd/run`——端到端 runner，编译 C 源码
并在 VM 中执行）。它们是**仓库开发工具**（差分锚点的 MoonBit 侧入口），
随包分发但下游通常无需引用；`moon build` 会为每个 executable 生成独立
产物——如果只消费引擎库（`vitro/engine/vm` 等），这些 cmd 产物可以
忽略。

## 包清单

| 包 | 层 | 职责 |
|---|---|---|
| `vitro/engine/source` | L0 | SourceLoc 三字段 + 列单位契约（字节偏移+1 主坐标 / Pos 双坐标预留） |
| `vitro/engine/opcode` | L0 | 135 条 opcode（编号照搬不重排；44–46 = C# 异常三件 TryBegin/TryEnd/Throw，47–49 空号）+ 双向映射 + Instruction |
| `vitro/engine/util` | L0 | 零语义机械件单点（G-1）：`utf8_len`（UTF-8 字节长度）/ `str_cmp`（真字典序——内置 String 比较非字典序）/ `i64_to_i32_bits`（位截断）/ `le_u32_at`·`le_u64_at`（小端拼装读） |
| `vitro/engine/fs` | L0 | native-only 文件系统件（**vendored 自 moonbitlang/x@0.5.5**，2026-09-28）：pub 面 7 函数 + `IOError`；C 符号前缀 `vitro_engine_fs_*`；上游漂移由 `scripts/moonbit/vendor_drift` 监控（内容哈希探针，CI hygiene）；Apache-2.0 合规见 `THIRD_PARTY.md` |
| `vitro/engine/diag` | L1 | ErrorCode 137 臂 + Severity/SourceLang + 教学卡片 77 条 + 目录导出（对拍逐字节一致） |
| `vitro/engine/ast` | L2 | Type 17 / Expr 26 / Stmt 16 / decl 全族 + depth + type_eq + to_c_string + mangle + JSON dump |
| `vitro/engine/names` | L3 | 产名族唯一出口（`__ctor__`/`__dtor__`）+ type_mangle_suffix 17 变体 + method_mangled_name |
| `vitro/engine/lexer` | L4 | 独立预处理 pass + LineMap + 宿主 IO（token 契约面子包 `lexer/token`） |
| `vitro/engine/parser` | L4 | token → AST：表达式瀑布/声明符螺旋/语句族/声明族；depth 参数化防护 + 零推进熔断 |
| `vitro/engine/libc` | L5 | builtin 签名单表 57 条 + 放行名全集 175 |
| `vitro/engine/typeck` | L5 | C 子集类型检查 + lowering 4 Pass（auto/typeof 推导、数组/struct 初始化器尺寸推断） |
| `vitro/engine/bytecode` | L6 | 产物 schema + R1 布局纯函数 + canonical dump emitter |
| `vitro/engine/codegen` | L6 | BytecodeGen 状态机双入口（`compile` / `compile_library`）+ 槽位策略 v1 逐位兼容 |
| `vitro/engine/memory` | L7 | 1MB 载体（`Memory`）+ 堆状态机（`MemoryMap`：bump + 有界隔离 + first-fit）+ `checked_access` 单入口 + freed_logs 有序数组（S6 开工批） |
| `vitro/engine/host` | L7 | 宿主函数域：110 路由表消费侧 + 输出通道（`Bytes` 字节保真）+ **100+ 个 VM 无耦合 handler**（内存族 / ctype / math / 字符串 / 转数值 / printf-scanf / VFS；统一 `HostMemReply` 结构化回复）+ E3061/E3027 文案（S6 余量全批） |
| `vitro/engine/vm` | L7 | 执行器状态机（值栈 u64 位模式 / 调用栈 / 教学观测 / 宿主域三态）+ 快照体系（`VMSnapshot`/`MemoryImage` 两端单点）+ C# 异常三执行状态（handler 栈 / 异常寄存器 / UNWINDING——CS 批硬前置 v1 入形）+ ARC 帧退出清理占位（S6 vm 批一号） |
| `vitro/engine/session` | L8 | 会话骨架 + `SessionConfig` 值对象（单一真相源 + 单一写入口——Rust「配置散在 VM 字段 + setup 硬编码覆盖 + capi 静默丢弃」事故链结构性消除）+ 多文件安全 `source_line_at` + 会话侧 DTO 九型（S7 批二号） |
| `vitro/engine/protocol` | L8 | StepPayload schema 契约（v0.1 冻结白名单 + v0.2 台账/激活清单 + 行为契约表）+ semantic_label 受控词汇表（14 条）+ 协议 DTO 族 + 展开粒度判据（S7 批一号，零依赖自持） |
| `vitro/engine/gateway` | L8 | wasm-gc 单出口（F-5 裁定落点）：NDJSON 帧协议层上提为引擎无关载体（`invoke` String→String 单口承载 21 方法表 / `reset` / `protocol_version` / `engine_version` 四导出），js-builtin-string 零拷贝直传、零功能性 imports；`library` 形态由 native 消费者（cmd/serve 壳）与 wasm 外壳共用（S7 批五号） |
| `vitro/engine/gateway/wasm` | L8 | wasm-gc 单目标薄壳：四个 `#export_name` 导出面所在（foreign_library）；Node 宿主驱动见仓库 `scripts/wasm_gateway/host.js`（16 断言） |

各包 API 概览见对应目录的 `pkg.generated.mbti`；`diag` 的三上下文用法示例见 [`diag/README.mbt.md`](diag/README.mbt.md)（可执行文档测试）。

## 快速上手（diag）

```moonbit
let code = @diag.ErrorCode::from_code(3053).unwrap()
code.display_code()          // "W3053"
code.severity().to_str()     // "warning"
code.catalog()               // Some(教学卡片) —— 标题 / 解释 / 常见原因
```

## 契约要点

- **码位只增不改**（versioned 常量语义）——`ErrorCode::code` 是稳定 ABI；
- 穷尽 match 无兜底臂：新增枚举臂在依赖方重新编译时立即暴露；
- 坐标契约：`SourceLoc.column` = 行内 UTF-8 字节偏移 + 1；双坐标消费方用 `Pos{byte_off, col_scalar, col_utf16}`；
- 渲染与 mangle 单源（`Type::to_c_string` / `Type::mangle_name_into`）。

## 已知限制与差异（as-of 0.7.0）

主动披露的四分类清单（每条标注 Clang 对照状态）：**已知缺陷**（printf 旗标/atof 前缀等 8 条，已排修复轨道）/ **教学语义设计**（受检访存、E3070 栈缓冲校验——有意为之，Clang 在同输入下是未定义行为）/ **架构差异**（32 位指针 4 字节模型等）/ 路线图缺口（step 族时间旅行 S8 等）——完整清单见仓库 [docs/current/07-质量与裁定/已知限制与差异.md](../docs/current/07-质量与裁定/已知限制与差异.md)。

## 性能现状（诚实披露，2026-09-26 实测）

VM 是为单步执行与时间旅行可观测性构建的**解释器**，不以裸速度为目标。同机对拍
Rust oracle 的实测数字：

| 场景 | MoonBit / Rust oracle |
|---|---|
| 端到端小程序（baseline 366 例中位，编译主导） | **1.42×** |
| 计算密集：fib(20) 递归 / 冒泡 200 / 500×500 嵌套 | **1.92× / 6.32× / 15.7×** |
| 条件 A 300×300 循环（完整引擎 vs oracle JIT 路径） | **10.1×**（1425ms vs 141ms） |

全速执行差距的正解是 **bytecode→wasm-GC 生成器**（规划于 **0.7.0+**，栈式→栈式
机械映射，其覆盖域正是该量级差距）；解释器持续服务于单步语义与时间旅行。完整实测
方法与数字见上游仓库《性能探究实录》§11。

## 验证

```bash
moon check && moon test    # 548 测试（source 14 / opcode 10 / diag 21 / ast 14 / lexer 52 / parser 31 / names 5 / libc 4 / typeck 30 / bytecode 17 / codegen 15 / memory 31 / host 112 / vm 81 / time_travel 40 / util 7 / protocol 46 / session 12；分解和 542 + 根 README doc test 6）——util 7 = 白盒 4 + doc test 3（G-1 机械件锚，2026-09-26 入列）——S5 起 bytecode/codegen 入列、S6 起 memory/host/vm 入列、S7 起 protocol 入列、S8 起 time_travel 入列（CheckpointManager 自 vm 迁入 + 门 3 六锚随迁 + 批一号二段 FrameWindow/UnifiedEngine 十一锚（含整数积分界锚），2026-09-30/10-01）；protocol 46 = 白盒 39（schema 11 + types 5 + vocabulary 7 + stream 16〔8 锚照搬 Rust tests + 索引 0 预留 + 窗口直通 + 审阅 P1/P3 六锚：vis_events 幂等×2 + 符号表全内容 + 同长 return_line + 删除重现 + get_sym 越界〕）+ 黑盒 5（对外面消费面点名；stream encode/decode 往返）+ 包 README doc test 2（协议演化纪律三条成文 + json_or_null 组合子——批四号 openseek ①③）；白盒含审阅 P1/P3 批六锚（vis_events 双幂等锚 + 符号表全内容 + 同长 return_line + 删除重现 + get_sym 越界）；libc 4 为 N3/N4 漂移登记锚（审阅批四恢复）；bytecode 17 / memory 31 / host 112 各含 2 个包 README doc test（2026 年 09 月 23 日补指引批）；memory 31 = 白盒 23 + 黑盒 6 + doc test 2；host 112 = 白盒 102 + 黑盒 8（+G-3 桥保真锚与三 handler trap 锚〔审阅五轮：fopen/va_start/fread 非法地址→trap 文案〕） + doc test 2（黑盒承担对外面消费面点名）；vm 81 = 快照 wbtest 8 + 观测 wbtest 6（S8 批一号三段-a：变量快照作用域/find_var_name 数组区间与跨帧/数组快照 256 截断与元素形态/vis take 幂等；审阅 P1/P2 红锚 2026-10-01：find_var_name 元素宽度维度〔double 8/char 1——base_kind 修复锚〕+ 指针数组快照〔int*[2] 按 Int 取值/char*[2] 步长 1〕）/ 快照 wbtest〔门 3 六锚随 CheckpointManager 迁 time_travel（2026-09-30 批一号一段）〕+ executor wbtest 63〔含 void host 栈平衡红锚〕+ 黑盒 2（八族 + 审阅修复批符号扩展锚×10 + 段二 F/D/Q 三族锚 4 + 控制流锚 7 + 批三号一段分发锚 5〔ctype/math-exit/exit 族/malloc-free/输出与 rand〕+ 三轮审阅锚 3〔NegF 零符号/附注去重/fmod·atan2 非对称〕）+ 黑盒 2；对外面以 go run ./scripts/moonbit/moonbit_surface -check 对账；分解数以 moon test -p 逐包为准、裸总数以 facts `moonbit_test_passed` 为准；wasm-gc 库形态：`moon build --target wasm-gc gateway`（4 函数导出 + js-string 直传，Node 宿主驱动见仓库 scripts/wasm_gateway/host.js）；另有 native-only 包测试 85 个（fs 9 / gateway 76——step 族九锚 + dump 族七锚 2026-10-01）不在裸口径内——`moon test --target native` 全量 633（CI 门禁口径，2026-10-01 实测）；两口径并存系包目标后端差异（默认 wasm）
moon info                  # .mbti 接口面（API 变更信号）
```

## 目录说明

- `scripts/gen_diag/`：**仓库开发工具**（从同仓库 Rust 源生成 diag 码表，默认入参指向 `../native/...`——包消费者无需也不应运行；生成物已随包分发且带源 sha256 落款，`go run ./scripts/gen_diag -check` 可校验其未漂移）；
- `*/pkg.generated.mbti`：`moon info` 生成的公共接口面。

## 上游与对拍

本 module 是 [Vitro 项目](https://github.com/rustin-beep/Vitro)（C 教学引擎，MIT）MoonBit 迁移的第一阶段产物：诊断目录（77 卡片）与 Rust oracle 出口经 canonicalize 归一后逐字节一致；AST dump 与 mangle 黄金串同源断言。迁移路线与差分锚点见上游仓库 `docs/current/`。
