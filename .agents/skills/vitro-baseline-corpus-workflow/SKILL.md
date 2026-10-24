---
name: vitro-baseline-corpus-workflow
description: Vitro 新增/修改 C 测试语料用例的完整义务链（clang golden、直拍、facts、SVG 连坐）。Use when adding a C test case under corpus/, generating or fixing golden files, or when clang_direct/vm_diff/facts turn red after corpus changes. 触发词：新增用例、golden、baseline、语料、直拍红、gap 目录、arch_diff_bug。
---

# 新增 C 语料用例义务链

**适用场景**：往 `corpus/` 加（或改）C 用例；补/修 golden；加用例后 clang_direct / vm_diff / facts 红（原 `native/tests/cases/` 已随 2026-10-05 删区整体迁至 `corpus/`；shadow / e2e 驱动已随 Rust 区退役）。

（2026-10-11 勘误：本段曾预写「一键串联器」——该脚本从未入库（CI skill_path_check 实锤悬空引用），段落回撤；编排器真入库时随件重写。）

**参数语义陷阱**：vm_diff / clang_direct 的 `--corpus` 接 **suite 名**（如 `baseline`，内部自拼 `corpus/` 前缀）；codegen_diff 接**目录**（`corpus/baseline`）。手跑别混——串联器已内化此差异。

非直拍面 suite（cpp / codegen_skeleton / template_generated）自动跳过对拍步、明示告警，仅走 facts 收尾。

## 黄金验证序列（按序全跑；串联器内部即此序列）
1. **clang 实跑**取 stdout + exit code（golden 由实跑生成，**勿手写**）；
2. **golden 不落盘 `.out` 文件**（**[Rust oracle 退役 2026-10-05]** 改写——原「`corpus/cases_golden/<suite>/<name>.out` + 82 个 `*_default.out`」形态已消亡，`corpus/` 下实测 0 个 `.out`）：期望值由 `clang_direct` **现跑** clang 取真值（缓存 `.clang_cache_cd/`，gitignore 域；行级归一内置）；结构面由各差分驱动随包固化的 `golden_digest.json` 对账（工序③形态）；
   **五家 digest 冻结清单（2026-10-18 连红批改写——本行此前只写了 codegen 一家，10-17/10-18 两批语料各断供 2~3 家致 CI 连红，教训三条在案）**：新增/修改语料后**五家全跑** `--freeze-mb`（driver 均接 `corpus/<suite>`，vm_diff 接 suite 名）——
   - `node scripts/diff_gate/main.mts lexer corpus/baseline --freeze-mb`（语料文件数闸 + 样本 TSV——断供形态「现 N ≠ 落盘 M」）
   - `node scripts/diff_gate/main.mts parser corpus/baseline --freeze-mb`（样本级 hash 校验——新样本不在清单报「与 freeze 时不一致」，CI 上该 job 才红、本地不跑不报）
   - `node scripts/diff_gate/main.mts typeck corpus/baseline --freeze-mb`（逐 suite；**代码改动（含 typeck 行为改进）致存量 hash 漂移时 knr/leetcode/gap 三套件也要重跑**——kr_4_6 实锤：折叠改进只冻了 baseline，knr 旧 hash 连红两轮）
   - `node scripts/diff_gate/main.mts codegen <dir> --freeze-mb`（mb 侧产物指纹入账；**dir 须四套件各跑一次**——codegen 改指令发射面必漂存量：2026-10-20 CI 红实锤，只冻 baseline 漏 knr/leetcode 8 例 char 指令漂移）
   - `node scripts/diff_gate/main.mts vm --corpus <suite> --freeze-mb`（接 **suite 名**非目录）
   语义统一（2026-10-11）：`--freeze-mb` 默认含存量重算，代码改动致存量漂移时同命令自动刷新——`--refresh` 已删，出现即说明心智过时。**本地验证面必须四 suite 全跑**（baseline 绿 ≠ knr/leetcode/gap 绿——CI 是四套件全量，kr_4_6 教训）；
3. ~~`cargo test --test vitro_e2e`~~（已随删区退役——e2e 是 oracle 自身端到端防线，语义守护由 digest + clang_direct 双锚承接，见 S9冻结资产清单面四）；
4. ~~`cargo build --release` 重建后 `go run ./scripts/shadow_verify`~~（**[Rust oracle 退役 2026-10-05]**——`native/` 已整体删除，`scripts/shadow_verify` 同批消失；oracle 正确性底线职责由 clang golden + clang_direct 直拍承接）；
5. `go run ./scripts/facts --strict check` 漂移 0（CI 现役完整形态，flag 在子命令之前）。

## corpus_fuzz 基线 freeze 的语料集一致性（2026-10-20 CI 红教训）

`-freeze` 的抽样种子吃**磁盘语料文件集合**（非提交集）——工作区躺着未提交语料时 freeze，基线按「含未来语料」的抽样入账，而 CI 检出集更小 → 轮换差异 → 桶恶化假红（gap/file_fopen 族 VFS 预置差异面延迟两批才在 CI 轮到）。**freeze 前核 `git status --short corpus/` 为空**（未提交语料先提交或 stash 再 freeze）；口径级变更（如 clangOutcome 判定修复）会改变存量桶，须主动全量重算而非等抽样轮到。

## golden 规则
- **stdout 为空的用例，golden 就是 0 字节文件，合法**（比对按 trim 后非空行）。
- **必须 LF**：clang 在 Windows 直出 CRLF——现役形态下归一由 `clang_direct` 的 `normalizeClangStdout` 内置承接（原「落盘前 `tr -d '\r'`」随 `.out` 落盘形态消亡）；查形态仍是一律看字节，别信 Read 渲染。
- 「golden 从未生成」与「用例被 exclude 排除」是两种不同故障，别混判。

## 两个通道陷阱
- **e2e 的 ret ≠ CLI 打印的返回值**：e2e ret 是引擎状态码，程序 `return 42` 不等于 e2e 失败。勿凭 CLI 输出预判 e2e 红。
- ~~**shadow_verify --rebuild 只看 mtime**~~（**[Rust oracle 退役 2026-10-05]**——本坑对象已删；教训由现役防线继承：vm_diff / clang_direct 自带「mtime 触发 + 构建复核」新鲜度门禁，统一入口 `scripts/bin/vitro` 的 native 降级臂有 **stderr 大字告警**（不阻断；只扫 `cmd/host/parser/typeck/lexer/codegen/vm` 7 目录，gateway 族改源不在告警面）——陈旧 exe 会用旧代码下结论，查法见 `vitro-workspace-review` 03 的 D16 同族面「陈旧制品」条）。

## 加用例的连坐面（facts）
1 个用例会牵动 clang_direct / vm_diff 的对拍计数（原「shadow 总数与 match 计数」**[Rust oracle 退役 2026-10-05]**），下游同步面约 6 处：markdown 现值句、**SVG 内嵌数字（生成物，`node scripts/gen_svg/main.mts` 重生成，禁手改；重生成后 `grep -o` 抽查数字落位）**、README 分解式行（人工维护不机判但须诚实同步）+ 更新 as_of 实测日期。

## 输出差异类用例：gap 目录配方
双侧可跑但输出**必然不同**时（如 `putchar(>=128)` 的 UTF-8 重编码差异），不进 baseline。照 `corpus/gap/` 先例：
1. 落 `corpus/gap/`（clang_direct 直拍六目录含 gap 与 `template_generated`；gap 例通常须登记 `known_direct.json` 白名单〔case+digest 锁定〕）；
2. 源内标 `// @category: arch_diff_bug`（shadow 的 known_issue 豁免通道）；
3. golden = clang 实跑原始字节，不做任何归一。
进 clang_direct known 台账的条目：`go run ./scripts/clang_direct --check-known` 做静态校验（悬空/格式）；known 是**双向监控**——缺陷修复转绿而台账未移除会红，这是自动提醒器，不是噪音。

## clang 实跑注意（Windows）
- clang 编译的原生程序 stdout 是**文本模式**（`\n` 伸缩为 `\r\n`），直拍比对前剥行尾 `\r`；
- 并发多路时 Defender 实时扫描会瞬态锁目标文件使 clang 非零退出——重试判据须「编译成功且非异常才接受」；
- 数组形参 `sizeof` 在 Clang/gcc 都**不是**整型常量表达式（形参退化为指针）——别用 `_Static_assert` 给「Clang 能跑」造证据。Clang 能跑 ≠ 符合标准，两件事分开记。

## 权威源与时效
- `scripts/clang_direct` / `scripts/facts` 头注（`shadow_verify` 已随 2026-10-05 删区退役）；原 `native/AGENTS.md` §测试防线（已删区，档案 tag `rust-oracle-freeze`）
- **相关规程**：`vitro-facts-reconciliation`（连坐面的判读）、`vitro-generator-contract`（SVG 重生成属生成器闸）
- as_of: 2026-10-18（五家 digest 冻结清单改写——lexer/parser/typeck 断供连红批）
