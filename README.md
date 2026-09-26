<p align="center">
  <img src="assets/logo/vitro-logo.svg" alt="vitro" width="640">
</p>

<p align="center">
  <a href="https://github.com/rustin-beep/Vitro/actions/workflows/ci.yml"><img src="https://github.com/rustin-beep/Vitro/actions/workflows/ci.yml/badge.svg" alt="CI status"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT"></a>
</p>

# Vitro

> 教学 C 子集参考执行引擎（白箱后端）

一个教学 C 子集编译器与字节码虚拟机：**Lexer → Parser → TypeChecker → BytecodeGen → VitroVM** 全链路自研，以 Clang 为行为基准做诚实对照，把"程序究竟怎么跑"变成可见、可解释、可回放的教学素材。**现役实现是 MoonBit**（`moonbit/`，mooncakes [`vitro/engine`](https://mooncakes.io/docs/#/vitro/engine/)）；同仓保留一份**已冻结的 Rust 实现**作为差分对照 oracle 与防线基座（tag `rust-oracle-freeze`，白名单 P1–P7/U1/U2 + 安全修复 + 防线维护），在 MoonBit 全量切换完成后整体退役删除。

> **本仓库只做后端（MIT 许可）。** 2026-09-11 完成前端切割：`CideFlutter/`、FRB 桥接、web 部署 workflow 与全部 Flutter 构建脚本已迁出，前端交给社区；原生移动端放弃（"看"的场景由 wasm32 + 任意 Web 前端的移动浏览器天然覆盖）。切割前最后完整状态由标签 `before-frontend-split` 保留（`git checkout before-frontend-split -- CideFlutter` 可取回）。
>
> **MoonBit 迁移（2026-09-18 起，同仓绞杀者模式）**：S2–S6 已收官——lexer / parser / typeck / codegen·bytecode / memory·host·vm 全部落地并对拍闭环；mooncakes 已发布 0.5.0（2026-09-23），0.6.0（S6 收官版）发布收尾中。迁移 v1 范围 = **C only**（C++ 已裁砍，2026-09-20），目标出口为 **wasm-gc 单出口多宿主**。形态裁定、包切分与逐片进度见 [MoonBit迁移总计划](docs/current/01-定位与路线/MoonBit迁移总计划.md)，活跃区操作手册见 [`moonbit/AGENTS.md`](moonbit/AGENTS.md)。
>
> 定位转型的决策依据与路线见 [`docs/current/01-定位与路线/后端定位与白箱计划.md`](docs/current/01-定位与路线/后端定位与白箱计划.md)。

## 现役引擎：MoonBit（`vitro/engine`）

- **已发布**：mooncakes [`vitro/engine`](https://mooncakes.io/docs/#/vitro/engine/) 0.1.0 → **0.5.0**（2026-09-23）；**0.6.0**（S6 收官版：`memory` / `host` / `vm` / `util` + `cmd/run`）已建册，发布收尾中——变更与性能披露见 [moonbit/CHANGELOG.md](moonbit/CHANGELOG.md)
- **已收官片**（各片收官时点数字，历史快照不连坐当前真值）：S2 lexer（token TSV 差分 6002 逐字节一致）/ S3 parser（597 语料 AST+诊断归一逐字节一致）/ S4 typeck·names·libc（598 语料 E1–E4 全绿）/ S5 codegen·bytecode（**A 级对拍 598/598 全闭环**，含 code 段逐指令）/ S6 memory·host·vm（135 opcode 穷尽执行器 + `VMSnapshot` 快照体系 + 110 host 路由 + `cmd/run` 端到端 runner）
- **验证**：`moon test` **443 用例**全绿 + 十五道闸门（token / AST / 诊断 / 字节码逐层对拍；第十五闸 = clang_direct 层 2 直拍，彼时 601 用例 = 595 一致 / 6 条既有登记 known / 引擎零新缺陷）；对外面以 `moonbit_surface -check` 机判对账
- **性能现状**（2026-09-26 实测，同机对拍 Rust oracle）：端到端小程序中位 **1.42×**（编译主导）；计算密集 fib(20) 1.92× / 冒泡 6.32× / 500×500 嵌套 15.7×。差距来自解释器 dispatch——全速执行规划于 0.7.0+（bytecode→wasm-GC 生成器路线），解释器形态持续服务单步语义与时间旅行
- **其后**：S7 协议/会话、S8 教学智能、S9 裁定批——排期权威见[总计划 §10](docs/current/01-定位与路线/MoonBit迁移总计划.md)

## Rust 冻结对照 oracle

`native/` 是迁移前的完整 Rust 实现（10 个子 crate + 三出口），2026-09-18 起冻结（tag `rust-oracle-freeze`，只收白名单维护 P1–P7/U1/U2、安全修复与防线维护，新特性一律不做）。它不再是开发目标，但仍是**活着的防线基座**：shadow 对拍、cargo 防线与 `vm_diff` 三联的 Rust 侧真值都跑在它上面，直到 MoonBit 全量切换完成后**整体删除**（档案 = tag + git 历史）。C++ 前端已随裁砍（2026-09-20）冻结在区内，防线继续跑到退役为止，MoonBit 侧零迁移。

<p align="center">
  <img src="docs/current/01-定位与路线/vitro-architecture-three-exits.svg" alt="vitro 三出口一核心架构（Rust oracle 历史架构）" width="900">
</p>

**三出口一核心（Rust oracle 历史架构）** —— 引擎核心（编译管线 + VitroVM + 统一模式 + 诊断）经 C ABI（capi）、wasm32、`vitro_cli serve` 三个薄出口对外，共用 `session_api` 会话语义中立层；MoonBit 侧的出口形态收敛为 wasm-gc 单出口多宿主（见总计划）。详图与决策：[架构设计.md](docs/current/01-定位与路线/架构设计.md)

**Rust oracle 实测状态（2026-09-23）**：

- **C 教学子集**：C Shadow Verification **683 个用例**（完全匹配 679 + known_issue 3 + gap_extension 1，无非预期差异；vitro_better 已清零）
- **C++ 教学子集**：99 个用例（95 一致 + 4 个已记录的 `clang_compile_fail`：`cpp_vitro_vec_class` / `cpp_vitro_list_class` / `cpp_u3_class_instantiate_in_template` / `cpp_u3_vec_class_twice`）；C++ E2E 回归 83 个用例
- **真实程序回归**：K&R 81 题全绿；LeetCode 138 题全部通过；Baseline 用例全部通过
- **全量测试**：`cargo test --workspace --all-features` 全绿（**实测数字行，随工具链版本漂移**：2026-09-23 实测 1029 用例 / 64 套件，CI `windows-latest` 与本地同平台——按实测行人工维护）；clippy 0 warning
- **出口与能力**：capi ABI `2.1.0`，StepPayload schema v0.1 已冻结；wasm32 零修改构建 3.75MB（Node 下 C API 全链路 + E3070 教学诊断）；时间旅行（VM 快照 / 检查点 / Seek / 异常回退）全链路可用

> 失败与差异一律如实记录在各 `*_FAILURES.md`（见下文"测试防线"），禁止通过修改测试预期值粉饰数据。

## 项目图览

<p align="center">
  <img src="docs/current/04-标准库与防线/shadow-verification-flow.svg" alt="影子验证门禁流水线" width="900">
</p>

**影子验证门禁** —— 同一份 C/C++ 语料喂给 Clang 与 Vitro 逐字节对拍，"通过 / 非预期差异"分流驱动扩展优先级；CI 硬门禁，图内规模数字由 facts 台账机判防漂移。
机制与判定表：[影子验证框架.md](docs/current/04-标准库与防线/影子验证框架.md)

<p align="center">
  <img src="docs/current/05-教学体验/unified-triple-cache.svg" alt="统一模式三态缓存" width="900">
</p>

**统一模式三态缓存** —— 时间旅行教学交互的三层缓存：Frame Cache 承接动画与面板的零延迟浏览，Checkpoint 支撑状态恢复，Active VM 保持唯一可执行现场（Rust oracle 已实现；MoonBit 侧随 S8 教学智能迁移）。
设计与落地口径：[统一模式设计.md](docs/current/05-教学体验/统一模式设计.md)

<p align="center">
  <img src="docs/current/05-教学体验/cognitive-knowledge-graph.svg" alt="P2 知识图谱概念三域" width="900">
</p>

**认知推理知识图谱** —— 把 C 语言离散知识点建模为编译 / 内存 / 控制流三域概念图，学生遇错时动态激活关联子图（Rust oracle 已实现；MoonBit 侧随 S8 教学智能迁移）。
节点分类树与已实现范围：[认知推理系统设计.md](docs/current/05-教学体验/认知推理系统设计.md)

> 以上插图由 `go run ./scripts/gen_svg` 从 `reports/facts.json` 生成（快照数字带 `data-fact` 锚，`go run ./scripts/facts check` 机判漂移），勿手改；全部 11 张插图（另含 MoonBit 包切分两张 / 统一模式架构与状态机 / 内存布局 / StepPayload 帧结构 / wasm 并发隔离）见 [`docs/README.md`](docs/README.md) 插图约定。

## 技术栈

| 层级 | 技术 |
|------|------|
| 现役实现 | **MoonBit**（`vitro/engine` workspace：L0–L7 共 15 包 + 5 个 `cmd` 工具；mooncakes 发布） |
| 执行 | 自研字节码解释器（135 opcode 穷尽 match，1MB 线性内存，指令级边界检查）+ `VMSnapshot` 快照体系（时间旅行基座） |
| 加速规划 | 0.7.0+ bytecode→wasm-GC 生成器（全速执行）；解释器持续服务单步语义与时间旅行 |
| 对照 oracle | **Rust 1.95.0**（`#![forbid(unsafe_code)]`；模板 JIT = 热点 trace → 预编译 Rust 函数指针序列，非机器码 JIT） |
| 行为基准 | Clang / Clang++（Golden 唯一来源，禁止来自 Vitro 自己） |
| 许可 | MIT |

> **注意**：模板 JIT 不是传统机器码 JIT。由于核心 crate 启用 `#![forbid(unsafe_code)]`，无法动态生成机器码，因此把热点循环的字节码 trace 编译为预编译 Rust 函数指针序列（超级指令），跳过解释器 dispatch 开销，不匹配时回退标准解释执行。

## 项目结构

```
moonbit/                   MoonBit 活跃区（vitro/engine workspace）——现役实现，全部新开发在此
├── source/ … util/        基础层（SourceLoc / 135 opcode / diag 生成物 / AST / 零语义机械件）
├── lexer/ parser/ typeck/ 前端（S2–S4 收官）
├── bytecode/ codegen/     字节码与生成器（S5 收官）
├── memory/ host/ vm/      运行时（S6 收官：1MB 内存状态机 / 110 host 路由 / 执行器 + 快照）
└── cmd/                   差分对拍工具 ×4（dump_tokens / dump_ast / dump_typeck / dump_compile）+ cmd/run 端到端 runner
native/                    Rust workspace——冻结差分对照 oracle（tag rust-oracle-freeze）
├── crates/                10 个子 crate（lexer → vm 全链路）
├── src/                   capi（C ABI 出口）/ session_api / unified 时间旅行 / serve 出口
├── runtime_libc/          标准库存根 + 内置 C++ 容器（.cpp 接口声明为唯一真相来源）
└── tests/                 五层测试防线与用例（baseline / knr / leetcode / cpp / shadow）
templates/                 算法模板源（source.c + meta.yaml；待社区前端或 wasm 出口认领）
scripts/                   Go 防线驱动与工具脚本（Shadow 驱动、vm_diff 三联、facts 对账、gen_diag / gen_svg 生成器；清单见 docs/current/02-构建与上手/脚本总清单与必跑防线.md）
docs/                      设计文档、规范与事故报告
  ├── current/             当前有效文档
  ├── spec/                语言中立协议 schema
  └── archive/             历史归档（仅供追溯，可能严重过时）
```

## 快速开始

```bash
# 1. MoonBit 现役引擎：443 测试用例 + 十五闸（构建/闸门/发布全流程见 moonbit/AGENTS.md）
cd moonbit && moon check && moon test

# 2. 端到端跑一个 C 程序（cmd/run：C 源码 → 编译 → VM 执行，stdout / 返回码 / 1MB 内存映像三通道）
cd moonbit && moon build --release --target native cmd/run
./_build/native/release/build/cmd/run/run.exe ../native/tests/cases/baseline/hello_world.c

# 3. Rust oracle CLI（冻结对照，退役前继续可用）
cd native && cargo build --release --bin vitro_cli
./target/release/vitro_cli run tests/cases/baseline/hello_world.c
./target/release/vitro_cli serve            # JSON-lines 会话（headless 交互出口）
cd native && cargo test --workspace --all-features
cd native && cargo clippy --workspace --all-targets --all-features -- -D warnings

# 4. 测试防线（Shadow Verification：与 Clang / Clang++ 对照 stdout）
go run ./scripts/shadow_verify

# 5. wasm32 出口（oracle 侧；MoonBit 侧目标 wasm-gc，随 0.7.0+ 生成器路线落地）
cd native && cargo build --target wasm32-unknown-unknown --release
```

> **Windows 提示**：`moon build --target native` 默认走 MSVC `cl` 链接后端，本仓实测病态慢（首跑 ~223s / 热态稳定 87–97s / 持续负载可漂至 180s 级——moon#2254 自述口径）；设 `MOON_CC=clang` 后全量约 17s（[moonbitlang/moon#2254](https://github.com/moonbitlang/moon/issues/2254)）。

完整上手流程见 [`docs/current/02-构建与上手/快速入门.md`](docs/current/02-构建与上手/快速入门.md)，构建细节见 [`docs/current/02-构建与上手/构建指南.md`](docs/current/02-构建与上手/构建指南.md)，CLI 命令手册见 [`docs/current/02-构建与上手/CLI使用手册.md`](docs/current/02-构建与上手/CLI使用手册.md)。

> 历史前端构建（Flutter / Android / iOS）已随前端迁出，脚本见标签 `before-frontend-split`。

## 测试防线

项目采用**双轨分层**的测试防线，核心哲学：*测试不是为了标榜通过率，而是为了诚实地发现自己可能存在的问题*。

**MoonBit 侧（现役）**：

1. **`moon test` 443 用例 + 十五道闸门**：token TSV / E1 AST dump / E1–E4 诊断 / A 级 codegen（含 code 段逐指令）逐层对拍；第十五闸 = clang_direct 层 2 直拍（601 用例，6 条 known 全为既有登记）
2. **运行期双防线**：`scripts/vm_diff` 三联差分（引擎 vs Rust oracle，stdout / 返回码 / 1MB 映像逐字节）与 `scripts/clang_direct` 层 2 直拍（引擎 vs Clang 本尊），共同被测物 = `cmd/run` 端到端 runner
3. **对外面对账**：`go run ./scripts/moonbit/moonbit_surface -check` 机判 `.mbti` 接口面

**Rust oracle 侧（退役前在跑）**：

1. **Shadow Verification**：同一份源码同时交给 Clang / Clang++ 与 Vitro 执行，比对纯程序 stdout（Golden 只能来自 Clang，不能来自 Vitro 自己）；自 2026-09-06 起为 CI 硬门禁
2. **K&R + LeetCode 真实程序回归**：验证"真实世界代码能不能跑"
3. **三层契约验证**：Host Contract / Bytecode Self-Consistency / Differential Stress
4. **Fuzz 压力测试**：确定性 RNG 生成恶意内存与调用序列，验证安全检测不泄漏
5. **CI 集成与一致性监控**：`*_FAILURES.md` 与测试结果双向对账，转绿未更新文档即 CI 失败

失败与差异记录位于 `native/tests/*_FAILURES.md`，每次 CI 运行生成一致性报告。

## 诚实声明：这是一个 AI 实验田

**Vitro 不是由一个完整掌握每一行代码的团队从零手写而成的项目。**

它是人与 AI 协作的产物：

- 项目设计者参与了整体架构、功能方向、关键决策与部分细节调整
- 大量代码、测试、文档由 AI（包括本 README）生成、重构与维护
- 设计者无法保证能够回答社区提出的每一个问题
- `docs/archive/` 中保留一部分协作交互文本

如果你在使用过程中发现：

- 某段代码的设计理由说不清
- 某个边界行为与标准不一致
- 某处文档滞后于实现
- 某些改动看起来是"为了通过测试而绕过问题"

这些都有可能是 AI 实验田的典型痕迹。我们宁可诚实记录，也不想伪装成一切尽在掌控。

**提交署名 = 审阅深度信号**（2026-09-19 起）：git 提交信息中**提及用户**（署名 / 审阅标记）表明该批代码经过项目所有者的深度审阅与探针测试；**未标明**则仅代表浏览过，不构成审阅背书。评估任何一段代码的可信度时，请以对应提交的署名状态为准。

## 如果你感到被浪费了时间

大可抨击我们。

批评是项目继续改进的真实动力。如果你愿意，可以通过 Issue 或 PR 指出问题；如果只想发泄，我们也接受——毕竟一个无法对全部代码负责的项目，本就配不上所有人的信任。

## 许可证

[MIT](LICENSE)
