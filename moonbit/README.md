# Vitro MoonBit 引擎

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## English

**Vitro Engine** is the MoonBit implementation of the [Vitro C teaching engine](https://github.com/jingwei108/vitro) — a compiler front-end and bytecode codegen for a teaching subset of C, kept in byte-for-byte parity with the original [Rust oracle](https://github.com/jingwei108/vitro) (diagnostic catalog, AST dumps, canonical bytecode output).

| Package | Layer | What you get |
|---|---|---|
| `vitro/engine/source` | L0 | `SourceLoc` + column contract (UTF-8 byte offset + 1) + dual-coordinate `Pos` |
| `vitro/engine/opcode` | L0 | 135 opcodes with stable numbering (44–46 = C# exception triple, 47–49 reserved) + `Instruction` |
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

Stability guarantees: diagnostic codes and opcode numbering are **versioned constants — append-only**; exhaustive matches have no fallback arm, so new enum cases surface as compile errors in dependents. Import the whole module or pick per-package dependencies — layers only point downward.

```moonbit
let code = @diag.ErrorCode::from_code(3053).unwrap()
code.display_code()          // "W3053"
code.severity().to_str()     // "warning"
code.catalog()               // Some(teaching card: title / explanation / common causes)
```

The rest of this README is in Chinese.

---

C 教学引擎的 MoonBit 实现——137 个诊断错误码、135 条字节码操作码、Type/Expr/Stmt 全族 AST 与 C 渲染/mangle，码表与 [Vitro Rust oracle](https://github.com/jingwei108/vitro) 逐字节对拍对齐。

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

## 验证

```bash
moon check && moon test    # 433 测试（source 14 / opcode 10 / diag 21 / ast 14 / lexer 51 / parser 31 / names 5 / libc 4 / typeck 30 / bytecode 17 / codegen 15 / memory 31 / host 107 / vm 77；分解和 427 + 根 README doc test 6）——S5 起 bytecode/codegen 入列、S6 起 memory/host/vm 入列；libc 4 为 N3/N4 漂移登记锚（审阅批四恢复）；bytecode 17 / memory 31 / host 106 各含 2 个包 README doc test（2026-09-23 补指引批）；memory 31 = 白盒 23 + 黑盒 6 + doc test 2；host 106 = 白盒 96 + 黑盒 8 + doc test 2（黑盒承担对外面消费面点名）；vm 77 = 快照 wbtest 13〔+门 3 五锚〕+ executor wbtest 62 + 黑盒 2（八族 + 审阅修复批符号扩展锚×10 + 段二 F/D/Q 三族锚 4 + 控制流锚 7 + 批三号一段分发锚 5〔ctype/math-exit/exit 族/malloc-free/输出与 rand〕+ 三轮审阅锚 3〔NegF 零符号/附注去重/fmod·atan2 非对称〕）+ 黑盒 2；对外面以 go run ./scripts/moonbit/moonbit_surface -check 对账；分解数以 moon test -p 逐包为准、裸总数以 facts `moonbit_test_passed` 为准
moon info                  # .mbti 接口面（API 变更信号）
```

## 目录说明

- `scripts/gen_diag/`：**仓库开发工具**（从同仓库 Rust 源生成 diag 码表，默认入参指向 `../native/...`——包消费者无需也不应运行；生成物已随包分发且带源 sha256 落款，`go run ./scripts/gen_diag -check` 可校验其未漂移）；
- `*/pkg.generated.mbti`：`moon info` 生成的公共接口面。

## 上游与对拍

本 module 是 [Vitro 项目](https://github.com/jingwei108/vitro)（C 教学引擎，MIT）MoonBit 迁移的第一阶段产物：诊断目录（77 卡片）与 Rust oracle 出口经 canonicalize 归一后逐字节一致；AST dump 与 mangle 黄金串同源断言。迁移路线与差分锚点见上游仓库 `docs/current/`。
