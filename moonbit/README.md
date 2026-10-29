# Vitro MoonBit 引擎

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![在线 demo（浏览器直调 wasm-gc）](https://img.shields.io/badge/%E5%9C%A8%E7%BA%BF%20demo-浏览器直调-2ea44f)](https://rustin-beep.github.io/Vitro/)

## English

**Vitro Engine** is the MoonBit implementation of the [Vitro C teaching engine](https://github.com/rustin-beep/Vitro) — a compiler front-end and bytecode codegen for a teaching subset of C. Byte-exactness was originally locked in by diffing against the Rust oracle during the migration; since the oracle's retirement (2026-10-05, tag `rust-oracle-freeze`) the guardrails are Clang-golden direct checks and frozen digest baselines (diagnostic catalog, AST dumps, canonical bytecode output).

| Package | Layer | What you get |
|---|---|---|
| `vitro/engine/source` | L0 | `SourceLoc` + column contract (UTF-8 byte offset + 1) + dual-coordinate `Pos` |
| `vitro/engine/opcode` | L0 | 153 opcodes with stable numbering (0..137 inherited segment: 44–46 = C# exception triple, 47–49 reserved; 138..150 unsigned-dual extensions; 151..153 global-char byte-granule segment; 154..155 u64→fp unsigned-dual CastUQ2D/CastUQ2F) + `Instruction` |
| `vitro/engine/util` | L0 | Zero-semantic mechanical helpers: `utf8_len` (UTF-8 byte length) / `str_cmp` (true lexicographic order — built-in String compare is not) / `i64_to_i32_bits` / little-endian byte reads |
| `vitro/engine/fs` | L0 | Native-only file-system helpers **vendored from moonbitlang/x@0.5.5** (2026-09-28): 7 public functions + `IOError`; C symbols prefixed `vitro_engine_fs_*`; upstream drift watched by `scripts/moonbit/vendor_drift` (content-hash probe, CI hygiene) |
| `vitro/engine/diag` | L1 | 156-arm `ErrorCode` + severity/lang + teaching catalog (114 cards), byte-exact export |
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
| `vitro/engine/protocol` | L8 | StepPayload schema contract (v0.1 frozen whitelist + v0.2 ledger/activation checklist + behavior contracts) + semantic_label controlled vocabulary (15 entries) + protocol DTO family + unwind granularity predicate (S7 batch 1, zero-dependency) |
| `vitro/engine/gateway` | L8 | wasm-gc single export (F-5 ruling): NDJSON frame protocol layer lifted to an engine-neutral carrier (`invoke` String→String carrying the 30-method table / `reset` / `protocol_version` / `engine_version`), js-builtin-string zero-copy passing, zero functional imports; `library` form shared by native consumers (cmd/serve shell) and the wasm shell (S7 batch 5) |
| `vitro/engine/time_travel` | L8 | 时间旅行引擎域：`CheckpointManager`（无策略快照原语）+ `FrameWindow`（O(1) 摊还窗口，push 唯一写入口）+ `UnifiedEngine`（run_batch / seek_to 越窗五步契约；Trap 回退改「最近检查点+正向重放」——每步 1MB 快照机制消亡） |
| `vitro/engine/teaching/steps` | L8 | 算法语义标注：43 算法判据（误判收紧照搬）+ 43 步骤推断 + 文案全表；serve 通道端到端接线；族级 golden 对拍 311/311 全覆盖 |
| `vitro/engine/diagnostics` | L8 | 诊断教学域：A3–A7 数据层四表（gen_diagnostics 双产物，JSON 人审/vendor 面）+ M1–M5 机制（generate_fix 字节域坐标 / apply_fix / 误区滑窗 f32 语义化 / 路径组装 / 图激活）；serve probe 接线随段三 |
| `vitro/engine/gateway/wasm` | L8 | Thin wasm-gc-only shell: the four `#export_name` entry points (foreign_library + wasm-gc single target); Node host driver in repo `scripts/wasm_gateway/host.mts` (17 assertions) |

Stability guarantees: diagnostic codes and opcode numbering are **versioned constants — append-only**; exhaustive matches have no fallback arm, so new enum cases surface as compile errors in dependents. Import the whole module or pick per-package dependencies — layers only point downward.

## Performance (honest disclosure; first measured 2026-09-26, re-measured 2026-10-04 after S8)

The VM is an interpreter built for stepping and time-travel observability, not raw speed. **Historical record (frozen)**: the Rust-oracle comparison numbers below were measured 2026-09-26 ~ 2026-10-04, before the oracle's retirement (2026-10-05) — the comparison target no longer exists, so these ratios are archival, not reproducible baselines: end-to-end small-program runs were **1.42×** slower than the oracle (compile-dominated; median over baseline cases), compute-intensive programs **1.92×–15.7×** slower (fib(20) / bubble-200 / 500×500 nested loops), and the full engine ran the 300×300 loop benchmark at **10.1×** the oracle's JIT path. The S8 release re-measured everything and verified **no regression** vs 0.7.0 (same-hour A/B: pipeline 0.86–1.01×, execution 0.99–1.08×). **Live, still-reproducible anchors**: the **wasm-gc target beats the native CLI on all seven benchmark scenarios by 1.5–6.3×** (step-frame streaming 21.4 μs/frame vs 88.5) — browsers and Node are the fastest host form; and full-speed execution remains **9.6–19.8× slower than CPython** on wasm-gc / 31–54× on native (fib(20) / bubble-200 / 500×500 nested loops as the load; CPython is a pure interpreter, the fairest baseline) — inherent to the VM interpreter loop. A bytecode→wasm-GC generator would only cover 2–2.8× of that gap (issue #41, under evaluation). The interpreter keeps serving single-step and time-travel semantics. Full methodology and numbers live in the upstream repo's 《性能探究实录》 §11–§17.

```moonbit
let code = @diag.ErrorCode::from_code(3053).unwrap()
code.display_code()          // "W3053"
code.severity().to_str()     // "warning"
code.catalog()               // Some(teaching card: title / explanation / common causes)
```

The rest of this README is in Chinese.

---

C 教学引擎的 MoonBit 实现——156 个诊断错误码、153 条字节码操作码、Type/Expr/Stmt 全族 AST 与 C 渲染/mangle；码表经迁移期 Rust oracle 逐字节对拍锁定（oracle 已于 2026-10-05 删区退役，档案 tag `rust-oracle-freeze`），现役防线 = Clang golden 直拍 + 冻结 digest 基线。

## 安装

```bash
moon add vitro/engine        # 或按包引入 vitro/engine/diag 等
```

**关于 `cmd/` 子包**：本模块附带 9 个命令行工具——`cmd/vitro`（CLI 总入口：
`run`/`compile`/`step`/`api` 四子命令——`api` 可单帧或 `--batch` 批式调用全部
协议方法，输出契约见 [CLI_PROTOCOL_V1.md](docs/spec/CLI_PROTOCOL_V1.md)）；
`cmd/run`/`cmd/compile`/`cmd/step`（独立薄壳，行为与总入口同名子命令一致）；
`cmd/dump_tokens`/`cmd/dump_ast`/`cmd/dump_typeck`/`cmd/dump_compile`（差分
对拍工具，与 Rust oracle 产物逐字节比对）；`cmd/serve`（JSON-lines 会话模式
stdio 壳）。它们是**仓库开发工具 + agent 调用端口**，随包分发但下游通常
无需引用（仓库侧另有统一入口 launcher `scripts/bin/vitro`——默认走 wasm-gc
gateway 产物的 node 壳、自动降级本 native exe，见仓库 CLI 手册「统一入口」节）；`moon build` 会为每个 executable 生成独立产物——如果只消费引擎库
（`vitro/engine/vm` 等），这些 cmd 产物可以忽略。Windows/MSVC 冷态全量构建
有分钟级悬崖（见 [moon#2254](https://github.com/moonbitlang/moon/issues/2254)），
建议 `MOON_CC=clang`。

## 包清单

| 包 | 层 | 职责 |
|---|---|---|
| `vitro/engine/source` | L0 | SourceLoc 三字段 + 列单位契约（字节偏移+1 主坐标 / Pos 双坐标预留） |
| `vitro/engine/opcode` | L0 | 153 条 opcode（0..137 照搬段不重排；44–46 = C# 异常三件 TryBegin/TryEnd/Throw，47–49 空号；138..150 自扩 U 系对偶段；151..153 全局 char 字节粒度段；154..155 u64→fp 无符号对偶 CastUQ2D/CastUQ2F，#345 审阅 P1）+ 双向映射 + Instruction |
| `vitro/engine/util` | L0 | 零语义机械件单点（G-1）：`utf8_len`（UTF-8 字节长度）/ `str_cmp`（真字典序——内置 String 比较非字典序）/ `i64_to_i32_bits`（位截断）/ `le_u32_at`·`le_u64_at`（小端拼装读） |
| `vitro/engine/fs` | L0 | native-only 文件系统件（**vendored 自 moonbitlang/x@0.5.5**，2026-09-28）：pub 面 7 函数 + `IOError`；C 符号前缀 `vitro_engine_fs_*`；上游漂移由 `scripts/moonbit/vendor_drift` 监控（内容哈希探针，CI hygiene）；Apache-2.0 合规见 `THIRD_PARTY.md` |
| `vitro/engine/diag` | L1 | ErrorCode 156 臂 + Severity/SourceLang + 教学卡片 114 条 + 目录导出（gen_diag 单源生成） |
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
| `vitro/engine/protocol` | L8 | StepPayload schema 契约（v0.1 冻结白名单 + v0.2 台账/激活清单 + 行为契约表）+ semantic_label 受控词汇表（15 条）+ 协议 DTO 族 + 展开粒度判据（S7 批一号，零依赖自持） |
| `vitro/engine/gateway` | L8 | wasm-gc 单出口（F-5 裁定落点）：NDJSON 帧协议层上提为引擎无关载体（`invoke` String→String 单口承载 30 方法表 / `reset` / `protocol_version` / `engine_version` 四导出），js-builtin-string 零拷贝直传、零功能性 imports；`library` 形态由 native 消费者（cmd/serve 壳）与 wasm 外壳共用（S7 批五号） |
| `vitro/engine/gateway/wasm` | L8 | wasm-gc 单目标薄壳：四个 `#export_name` 导出面所在（foreign_library）；Node 宿主驱动见仓库 `scripts/wasm_gateway/host.mts`（17 断言） |

各包 API 概览见对应目录的 `pkg.generated.mbti`；`diag` 的三上下文用法示例见 [`diag/README.mbt.md`](diag/README.mbt.md)（可执行文档测试）。

## 快速上手（diag）

```moonbit
@content_data.install_baked() // 教学卡片经装载门（#130 拆包：lean 默认空、引擎不兜底）——import "vitro/engine/teaching/content_data"
let code = @diag.ErrorCode::from_code(3053).unwrap()
code.display_code()          // "W3053"
code.severity().to_str()     // "warning"
code.catalog()               // Some(教学卡片)（装载后）—— 标题 / 解释 / 常见原因
```

## 契约要点

- **码位只增不改**（versioned 常量语义）——`ErrorCode::code` 是稳定 ABI；
- 穷尽 match 无兜底臂：新增枚举臂在依赖方重新编译时立即暴露；
- 坐标契约：`SourceLoc.column` = 行内 UTF-8 字节偏移 + 1；双坐标消费方用 `Pos{byte_off, col_scalar, col_utf16}`；
- 渲染与 mangle 单源（`Type::to_c_string` / `Type::mangle_name_into`）。

## 已知限制与差异（as-of S9 修复批，2026-10-07）

主动披露的四分类清单（每条标注 Clang 对照状态）：**已知缺陷**（S9 修复批批一~批五已全销案——当前活缺陷为零，表留作历史账）/ **教学语义设计**（受检访存、E3070 栈缓冲校验——有意为之，Clang 在同输入下是未定义行为）/ **架构差异**（32 位指针 4 字节模型等）/ 路线图缺口（差异台账在册 30 条）——完整清单见仓库 [docs/current/07-质量与裁定/已知限制与差异.md](https://github.com/rustin-beep/Vitro/blob/master/docs/current/07-质量与裁定/已知限制与差异.md)。

## 性能现状（诚实披露；2026-09-26 首测，2026-10-04 S8 收官批全量复跑）

VM 是为单步执行与时间旅行可观测性构建的**解释器**，不以裸速度为目标。**下表为历史档案**——对照对象 Rust oracle 已于 2026-10-05 删区退役（tag `rust-oracle-freeze`），数字冻结为迁移期记录、不再可复现：

| 场景 | MoonBit / Rust oracle（历史档案） |
|---|---|
| 端到端小程序（baseline 例中位，编译主导） | **1.42×** |
| 计算密集：fib(20) 递归 / 冒泡 200 / 500×500 嵌套 | **1.92× / 6.32× / 15.7×** |
| 条件 A 300×300 循环（完整引擎 vs oracle JIT 路径） | **10.1×**（1425ms vs 141ms） |

- **S8 收官批复跑（2026-10-04）**：计算密集三项复测 1.58–1.74× / 6.43–6.89× / 15.8×（同量级）；**HEAD vs 0.7.0 同时段 A/B 判「无回归」**（四层管线 0.86–1.01× / 执行层 0.99–1.08×）。
- **wasm-gc 是主出口且有实测背书（现役可复现锚）**：同请求对照**全部七场景快 native CLI 1.5–6.3×**（step 帧流 21.4 μs/帧 vs 88.5）——浏览器 / Node 宿主是性能更优的消费形态。
- **诚实短板（负载：fib(20) 递归 / 冒泡 200 / 500×500 嵌套，同机 CPython 纯解释器基准）**：全速执行慢 CPython **9.6–19.8×**（wasm-gc）/ 31–54×（native）——VM 解释循环本身（自 Rust 期继承，oracle 亦慢 CPython ~2×）。bytecode→wasm-GC 生成器实测仅覆盖 **2–2.8×**、量级不足以补齐（issue #41 单独评估）；解释器持续服务于单步语义与时间旅行。

完整实测方法与数字见上游仓库《性能探究实录》§11–§17。

## 验证

```bash
moon check && moon test    # 963 测试（裸口径，facts 键 moonbit_test_passed 机判，漂移即 CI 红；批注明细单源 CHANGELOG——#308；2026-10-26 #314-#318 五案批 +2 裸域 +1 native-only；#330/#336 四段批 +1 裸域 wbtest；#338 批三 vprintf 族 +8、批四零测试包 +9 裸域；2026-10-27 #87 seek 几何化淘汰+重放快道 +5；2026-10-28 #342 审阅处置 P2-1 窗口塌缩锚 +1；2026-10-28 #325 swap 相位结构判据 +1；2026-10-28 #347 审阅处置 selection 判别力锚 +1；2026-10-28 #251 ULL 翻案批 +2；2026-10-28 #337/#343 声明点语义双案批 +17；2026-10-28 PR #344 审阅处置批 +8；2026-10-28 #213 语法错照跑 typeck 批 +2 native-only；2026-10-29 #356 POSIX 绝对锚批 +2 裸域 +1 native-only；同日审阅处置 +1 裸域 +1 native-only；2026-10-29 #364 compile{files} 双重拼接剔除批 +5 native-only）
                           # moon test --target native 全量 1136（CI 门禁口径，facts 键 moonbit_test_passed_native 机判；native-only 包〔fs/gateway/cli〕逐包分解以 moon test -p 为准）
moon info                  # .mbti 接口面（API 变更信号）
```

## 目录说明

- `scripts/gen_diag/`：**仓库开发工具**（#39 真值源迁移后从 `scripts/moonbit/diagnostics_data/{error_codes,catalog}.json` 单源生成 diag 码表——包消费者无需也不应运行；生成物已随包分发且带源 sha256 落款，`node scripts/moonbit/gen_diag/main.mts -check` 可校验其未漂移）；
- `*/pkg.generated.mbti`：`moon info` 生成的公共接口面。

## 上游与对拍

本 module 是 [Vitro 项目](https://github.com/rustin-beep/Vitro)（C 教学引擎，MIT）MoonBit 迁移的第一阶段产物。迁移期经 Rust oracle 逐字节对拍锁定（诊断目录 canonicalize 归一一致、AST dump 与 mangle 黄金串同源断言）；oracle 已于 2026-10-05 删区退役，现役防线 = Clang golden 直拍 + 三臂（js/native/wasm-gc）冻结 digest 对拍。迁移路线与差分锚点见上游仓库 `docs/current/`。
