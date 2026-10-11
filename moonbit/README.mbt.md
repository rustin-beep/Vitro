# Vitro MoonBit 引擎（活跃区）

> Rust 冻结对照区（`../native/`）的渐进迁移目标实现。上位文档：
> [MoonBit迁移总计划](../docs/current/01-定位与路线/MoonBit迁移总计划.md) ｜
> [第一阶段计划](../docs/current/01-定位与路线/MoonBit迁移第一阶段计划.md)

## 包清单（S1 基础片）

| 包 | 层 | 职责 | 锚 |
|---|---|---|---|
| `vitro/engine/source` | L0 | SourceLoc 三字段 + 列单位契约（字节偏移+1 主坐标 / Pos 双坐标预留） | 白盒单测（三量纲分歧锚） |
| `vitro/engine/opcode` | L0 | 135 条 opcode（编号照搬不重排；44–46 = C# 异常三件，47–49 空号）+ 双向映射 + Instruction | 0..255 全空间断言 |
| `vitro/engine/diag` | L1 | ErrorCode 137 臂（**gen_diag 生成，禁手抄**）+ Severity/SourceLang + catalog 77 条 + E4 出口 | 覆盖率断言 + E4 全量对拍（canonicalize 后逐字节一致） |
| `vitro/engine/ast` | L2 | Type 17 / Expr 26 / Stmt 16 / decl 全族 + depth（显式栈）+ type_eq + to_c_string 单源 + mangle + E1 dump emitter | E1 对拍两样本 diff 空 + E5 黄金串 `prefix_p_a2_3_int` |

## 关于 cmd/ 子包

本模块附带 6 个命令行工具（4 个 `cmd/dump_*` 差分对拍 + `cmd/run` 端到端
runner + `cmd/serve` JSON-lines 会话模式 native 壳）——它们是仓库开发工具，
随包分发但下游只消费引擎库时可忽略 `moon build` 生成的 cmd 产物。

## 生成物纪律

```bash
cd moonbit
go run ./scripts/gen_diag          # 从 Rust 源再生成 diag 包机器单源部分
go run ./scripts/gen_diag -check   # 幂等校验（源变产物变 / 产物被篡改即红）
```

- `diag/error_code_gen.mbt`、`diag/catalog_gen.mbt` 为生成物（**禁手改**，文件头有源 sha256 落款）；
- 生成流程内置 `moon fmt`——产物最终形态以 fmt 输出为准，gen 与 fmt 不互踩；
- 基线漂移（137 臂 / 77 卡片）fail loud：源变更须人工核对后更新 `expectedArms` / `expectedCatalog` 并登记差异。

## 性能现状（诚实披露；2026-09-26 首测，2026-10-04 S8 收官批复跑）

VM 是为单步执行与时间旅行可观测性构建的**解释器**，不以裸速度为目标。
同机对拍 Rust oracle：端到端小程序（编译主导）**1.42×**；计算密集
fib(20) / 冒泡 200 / 500×500 嵌套 **1.92× / 6.32× / 15.7×**；条件 A
300×300 循环（完整引擎 vs oracle JIT 路径）**10.1×**。
S8 收官批复跑：计算密集三项同量级（1.58–15.8×），HEAD vs 0.7.0 同时段
A/B 判**无回归**；**wasm-gc 主出口有实测背书——同请求七场景全部快
native CLI 1.5–6.3×**。诚实短板：全速执行慢 CPython 9.6–19.8×（wasm-gc），
系 VM 解释循环本身（自 Rust 期继承）；bytecode→wasm-GC 生成器实测仅
2–2.8×、量级不足（issue #41 评估中）；解释器持续服务单步语义与时间旅行。
完整口径见 `README.md`「性能现状」节与 `CHANGELOG.md`。

## 验证

```bash
moon check && moon test    # 729 测试（裸总数以 facts `moonbit_test_passed` 为准；逐包批注明细外迁 CHANGELOG——#45 裁定；裸分解：分解和 729 + 根 README doc test 0）
                           # native-only 包测试 122 个（fs 9 / gateway 99 / cli 14）；`--target native` 全量 851（CI 门禁口径）
moon info                  # .mbti 接口面（API 变更信号）
moon info                  # .mbti 接口面（API 变更信号）
moon info                  # .mbti 接口面（API 变更信号）
```

## 坐标契约（vitro/engine/source）

输入档案：[列号口径冻结](../docs/current/07-质量与裁定/列号口径冻结.md) §2。

```mbt nocheck
SourceLoc { line, column, file_id }  // column = 行内 UTF-8 字节偏移 + 1
Pos { byte_off, col_scalar, col_utf16 }  // 双坐标预留，三值同源派生
```
