# 实机勘探语料扩充方案——许可分流与 gcc 分桶裁判

> **as_of 2026-10-02**。探索结论全部来自亲跑命令（GitHub API 许可核验 / 本机 Clang 22.1.4 与 MinGW-w64 gcc 16.2 全量扫描 / Vitro serve 试金石），无脑测数字。
>
> **定位**：实机代码勘探（`scripts/realcode_diff/`，见 [vitro-realcode-diff-workflow](../../../.agents/skills/vitro-realcode-diff-workflow/SKILL.md)）的语料扩充设计。现状 = TheAlgorithms/C fork 基线 407 份金样本（fork 方案已落地，见该 skill 第四节）。本方案回答两件事：**更多语料从哪来、按什么规则收纳**；**单 Clang 裁判的盲区怎么补**。
>
> issue 台账：<https://github.com/rustin-beep/Vitro/issues>（本方案对应 issue = [#25](https://github.com/rustin-beep/Vitro/issues/25)，2026-10-02 立案在册）。

## 一、探索实录（2026-10-02）

### 1.1 候选仓许可 triage（三级核验：仓库 SPDX → 嵌套许可文件 → 文件头）

| 仓库 | 许可 | 实测 commit | 嵌套许可 | 结论 |
|---|---|---|---|---|
| rui314/chibicc | MIT（© 2019 Rui Ueyama） | `90d1f7f` | 无（仅根 LICENSE） | **进 Vitro**（test/ 41 个 .c） |
| rui314/8cc | MIT（© 2012 Rui Ueyama） | `b480958` | 无 | **进 Vitro**（test/ 43 个 .c） |
| antirez/sds | BSD（© 2006-2014 antirez） | `5347739` | 无 | **进 Vitro**（sds.c + 3 头；无 main，运行对比 skip） |
| csmith-project/csmith | BSD 系（© 2007-2018 Univ. of Utah，COPYING） | `0cdc710` | — | **进 Vitro**（仅收**生成物**——生成文件无上游版权，工具许可不传染） |
| gcc-mirror/gcc `gcc/testsuite/gcc.c-torture/` | GPL-3 | — | — | **留 fork**（execute/compile 两目录各 ~1000 文件，抽样纳入） |
| haoel/leetcode | **无 license**（1.8 万星） | — | — | **排除**（无 license = 默认保留所有权利，比 GPL 更麻烦） |

### 1.2 可勘探性实测（chibicc 试点深探）

**Clang 真值全量**（`-std=c11 -Wall -Wextra -fsyntax-only`，本机 22.1.4）：

- chibicc test/：**16/41 绿**；8cc test/：**33/43 绿**。
- 24 个红的归因（抽验 bitfield/control/typedef 三例）：**用例故意测非标准语义**——重复位域成员（C11 禁止）、隐式 int（C99 起禁止）、chibicc 自家怪癖语义（"expression is not assignable"）。**gcc 同拒**（见 1.3 双口径数据）——这些是"编译器怪癖测试"不是 GNU 扩展问题。
- 红文件进金样本 `clang_red` 桶（与现 TheAlgorithms 122 红同桶，双拒无立案信号）。

**Vitro serve 试金石**（cwd 注入后，enum.c/cast.c）：

- **E2005 ×169/×349**：`({...})` GNU 语句表达式被引擎系统性拒绝——**教学边界内行为**（C 子集不含 GNU 扩展，F-2），非缺陷；Clang 以扩展警告放行。chibicc 断言风格 `ASSERT(x, ({...}))` 使语句表达式饱和 ⇒ 该语料的 Vitro 信号集中在 parse 层的边界确认，**不经过语句表达式提升变换到不了 typeck 层**（变换成本高且损耗语义，不做——语料按"扩展边界桶"消费）。
- **W1019 ×6**（宏 ASSERT 实参副作用 ×2 警告）：既有警告面正常工作。
- **8cc 新形状**：test.h 用 `#include "stdio.h"`（**引号包标准头**）+ 老式无原型声明——引号形态标准头的解析路由待实测（后续批次探针）。

**方法解锁（本探索最大产出之一）**：serve 进程 **cwd = 语料目录** 时，同目录 quote-include（`#include "test.h"`）解析成功——E1021 消失。此前的"serve 无 base_dir"方法限制（E1021×104 登记）对**同目录形态**有零改造解法：勘探驱动把 cwd 设为被测文件目录即可。多文件项目（跨目录相对 include）仍需后续 include 解析批。

### 1.3 gcc 分桶裁判（真实基线交叉矩阵——含一次基线漂移的发现与修复）

**基线漂移的发现（本节数据的前情，诚实记录）**：初测 gcc 对 fork 语料"救回 ≥77 份 clang_red"（362 vs 285 绿）——复核发现这是**假象**：金样本聚合自 **v1 勘探**（2026-10-01，autofix 补 include **之前**的树），而分支提交态 `462074f6` = **v2 勘探**（autofix 累积后）。三方对照（clang 现扫 407 文件）：现扫 361 绿 = v2 361 绿（零不一致）≠ v1 285 绿——**金样本曾指向错误的测量版本**。已修复：以 v2 重聚合金样本（407 文件集不变，测量值刷新；新增的 120 文件留待指纹定性后按"持续纳入"批单独入），`-check` 码白名单扩 E/W/H 三族（v2 起 hints 入签名）。修复后金样本 buckets：**clang_red 46 / both_green 208 / vitro_red 153**（旧 122/155/130 退役）；运行判定：match 53 + rand 6+3 / mismatch 23 / clang_build_fail 92 / 其余超时与运行失败。

**真实基线交叉矩阵**（clang 22.1.4 现扫 × mingw64 gcc 16.2，407 文件）：

| 桶 | 数量 | 明细 |
|---|---|---|
| 双绿（正常三方对拍） | 358 | 现有流程 |
| **rescued**（clang 红 + gcc 绿） | **4** | avl_tree.c / leetcode/src/110.c / durand_kerner_roots.c / newton_raphson_root.c——语法形状 gcc 收 clang 拒 |
| **divergence**（clang 绿 + gcc 红） | **3** | tcp_full_duplex_client/server.c（BOOL enum 与 MinGW windows.h 冲突）+ modified_binary_search.c（指针类型不兼容——gcc 14+ 已将 -Wincompatible-pointer-types 升为 error） |
| 双红 | 42 | 双拒桶 |

**gcc 价值重定位（基于真实数字）**：救回面小（4 份——autofix 补 include 已把缺头类红提前消化）；**真正的价值是分歧探测**——双裁判不一致 = 平台/版本敏感代码的机判旗标（3 份 divergence 全部需人工归因：MinGW 环境特有冲突、gcc 版本 error 化升级），加上 358 双绿的置信度交叉验证。角色仍是**分桶裁判非第二真值**（golden 只来自 Clang 不变），成本极低（P2.5 一 pass，+~60 行）。

**工具链事实**：clang 22.1.4（PATH 内）+ mingw64 gcc 16.2.0（`D:\code\mingw64`，PATH 外——勘探脚本探测序 `--gcc` 参数 → PATH → 该路径）。

## 二、方案：许可分流格局

### 2.1 分流规则

| 许可 | 去处 | 先例 |
|---|---|---|
| 无毒（MIT/BSD/Apache/PD，三级核验过） | **Vitro 主仓** `scripts/realcode_diff/corpus/<name>/` | fs vendor（Apache-2.0）+ moonbit/THIRD_PARTY.md |
| 有毒（GPL 系） | **rustin-beep/C** 的 `corpus/<name>` 孤儿分支 | C-master（GPL3）外置红线 |
| 无 license | **排除**（不进任何一侧） | — |

依据：根仓 MIT（实测 LICENSE）；GPL 进树会强迫整个分发转 GPL——"毒"的准确定义；MIT 收 MIT/BSD 仅归属义务。

### 2.2 进 Vitro 的落位与义务链（每语料五步）

1. 许可 triage 三级核验（1.1 表为已完成件）；
2. 落位 `scripts/realcode_diff/corpus/<name>/` + `README.corpus.md`（上游 sha/许可/探针改动清单）+ `LICENSE.upstream`（全文）；
3. 探针态 = 主仓普通 commit（MIT 代码可直接改——补 include/内联共享头；复现链零外部跳转）；
4. **入库即验证不进防线扫描域**：golden/e2e/shadow 只走 `native/tests/cases/**`（已确认 scripts/shadow_verify 的用例加载域），跑全套闸留证；
5. 金样本扩 `gold_<corpus>.json` + `_meta.corpora` 登记 + `-check` 多文件扫描。

注意：`scripts/` 是冻结区——所有改动走防线维护通道。

### 2.3 语料梯队与推进序

| 批 | 语料 | 价值 | 前置 |
|---|---|---|---|
| 试点 | chibicc tests（MIT，41 份） | 编译器作者写的 C11 系统形状（声明符/常量表达式/位域/预处理器）；断言密集型表达式 | 无（cwd 解锁已实证） |
| 二 | 8cc tests（MIT，43 份） | 互补形状 + 引号包标准头新形态 | 无 |
| 二 | sds（BSD，1 库文件） | 真实工具库的语法/类型面 | 无 |
| 三 | csmith 生成语料（N=确定性种子） | 机械广度（声明符/表达式组合爆炸）；与总计划 §10 防线表"层 2 直拍 fuzz 模式"候补合流 | csmith 本机构建 |
| 三 | gcc c-torture 抽样（GPL，execute/compile 各 ~100） | C 语义酷刑测试经典；过滤 Clang 拒绝的 GCC 扩展后入 fork 分支 | fork 分支流程 |
| 后续 | lua / musl src/string+math / sqlite（MIT/PD） | 真实世界多文件项目最高价值面 | **include 解析批**（跨目录 quote-include，同 E1021×104 方法限制根治） |

### 2.4 gcc 裁判的接线（脚本改造点）

`scripts/realcode_diff/vitro_clang_diff.go`：P2 Clang 真值后加 P2.5 gcc 分桶（`gcc -std=c11 -fsyntax-only`，探测顺序 `--gcc` 参数 → PATH → `D:\code\mingw64\bin`）；金样本条目增 `gcc_ok` 字段；`-check` 值域白名单同步。约 +60 行，防线维护通道。

## 三、验收锚与待拍板点

- **已定**（本方案落档即生效的裁定）：许可分流规则；gcc = 分桶裁判非第二真值；chibicc 语料按"扩展边界桶"消费（不做语句表达式提升变换）；haoel/leetcode 排除。
- **待拍板**：① 试点批（chibicc）开工时机；② 无毒语料勘探接 CI（仓内语料 pinned 可复现——原"勘探不接 CI"拍板的前提变化，条件性重提）；③ include 解析批立项（第三梯队解锁钥匙，同时根治 E1021×104）。
- **诚实边界（2026-10-02 已补测）**：初版"救回 ≥77"系 v1 基线漂移假象，已按真实基线修正（本节 1.3）；8cc 的 gcc 口径与 Vitro 引号标准头形态探针仍待补。
