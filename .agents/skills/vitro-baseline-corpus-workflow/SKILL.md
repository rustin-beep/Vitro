---
name: vitro-baseline-corpus-workflow
description: Vitro 新增/修改 C 测试语料用例的完整义务链（clang golden、e2e、shadow、facts、SVG 连坐）。Use when adding a C test case under native/tests/cases/, generating or fixing golden files, or when e2e/shadow/facts turn red after corpus changes. 触发词：新增用例、golden、baseline、语料、e2e 红、shadow、gap 目录、arch_diff_bug。
---

# 新增 C 语料用例义务链

**适用场景**：往 `native/tests/cases/` 加（或改）C 用例；补/修 golden；加用例后 e2e / shadow / facts 红。

## 黄金验证序列（按序全跑）
1. **clang 实跑**取 stdout + exit code（golden 由实跑生成，**勿手写**）；
2. golden 落 `native/tests/cases_golden/<suite>/<name>.out`——`<suite>` ∈ `baseline` / `knr` / `leetcode` / `cpp`，与 `cases/` 同名子目录**一一对应**。⚠️ `cases_golden/` **根下另有 82 个 `*_default.out` 散文件**（模板/算法那套），别与用例 golden 放混；
3. `cargo test --test vitro_e2e`（cwd=`native/`）；
4. `cargo build --release` 重建后 `go run ./scripts/shadow_verify`（cwd=仓库根）；
5. `go run ./scripts/facts check` 漂移 0。

## golden 规则
- **stdout 为空的用例，golden 就是 0 字节文件，合法**（比对按 trim 后非空行）。
- **必须 LF**：clang 在 Windows 直出 CRLF，落盘前 `tr -d '\r'` 归一，与仓库既有形态一致。查形态：`od -c <golden> | head`（看 `\n` 而非 `\r\n`）。
- 「golden 从未生成」与「用例被 exclude 排除」是两种不同故障，别混判。

## 两个通道陷阱
- **e2e 的 ret ≠ CLI 打印的返回值**：e2e ret 是引擎状态码，程序 `return 42` 不等于 e2e 失败。勿凭 CLI 输出预判 e2e 红。
- **shadow_verify --rebuild 只看 mtime**：DLL 构建自旧提交但 mtime 新鲜（改的是别的文件）时不触发重建——靠 `engine_version()` 里的 git hash 检查 exit 2 fail fast 拦截；处置 = 手动 `cd native && cargo build --release`。

## 加用例的连坐面（facts）
1 个用例会牵动 shadow 总数与 match 计数，下游同步面约 6 处：markdown 现值句、**SVG 内嵌数字（生成物，`go run ./scripts/gen_svg` 重生成，禁手改；重生成后 `grep -o` 抽查数字落位）**、README 分解式行（人工维护不机判但须诚实同步）+ 更新 as_of 实测日期。

## 输出差异类用例：gap 目录配方
双侧可跑但输出**必然不同**时（如 `putchar(>=128)` 的 UTF-8 重编码差异），不进 baseline（会被 e2e 硬性 golden 比对卡死）。照 `native/tests/cases/gap/` 先例：
1. 落 `native/tests/cases/gap/`（e2e 扫 `cases/` 下的 baseline / knr / leetcode / cpp，外加**独立目录** `tests/cases_template_generated`——不是 `cases/template`；**不扫 gap**）；
2. 源内标 `// @category: arch_diff_bug`（shadow 的 known_issue 豁免通道）；
3. golden = clang 实跑原始字节，不做任何归一。
进 clang_direct known 台账的条目：`go run ./scripts/clang_direct --check-known` 做静态校验（悬空/格式）；known 是**双向监控**——缺陷修复转绿而台账未移除会红，这是自动提醒器，不是噪音。

## clang 实跑注意（Windows）
- clang 编译的原生程序 stdout 是**文本模式**（`\n` 伸缩为 `\r\n`），直拍比对前剥行尾 `\r`；
- 并发多路时 Defender 实时扫描会瞬态锁目标文件使 clang 非零退出——重试判据须「编译成功且非异常才接受」；
- 数组形参 `sizeof` 在 Clang/gcc 都**不是**整型常量表达式（形参退化为指针）——别用 `_Static_assert` 给「Clang 能跑」造证据。Clang 能跑 ≠ 符合标准，两件事分开记。

## 权威源与时效
- `scripts/shadow_verify` / `scripts/clang_direct` / `scripts/facts` 头注；`native/AGENTS.md` §测试防线
- **相关规程**：`vitro-facts-reconciliation`（连坐面的判读）、`vitro-generator-contract`（SVG 重生成属生成器闸）
- as_of: 2026-09-28
