# realcode_diff —— 实机代码对拍勘探（外置语料基线 + 仓内语料批）

Vitro 引擎 vs Clang 对 [TheAlgorithms/C](https://github.com/TheAlgorithms/C)（GPL-3.0）全量 C 文件的逐文件对比勘探工具与回归金样本。

**另含仓内语料批**（#25 许可分流落地侧）：`corpus/<name>/` 下的无毒（MIT/BSD）语料，收进主仓做对拍——详见 [`README.corpus.md`](./README.corpus.md)。

## 外置语料锚（provenance）

- 上游 TheAlgorithms/C@`e5dad3f`（2023-09 终态，不再漂移）
- **fork [rustin-beep/C](https://github.com/rustin-beep/C)，默认分支即基线**：`vitro-probe-baseline` = 上游终态 + 89 文件探针态（补 include 128 处 + leetcode 注释内 struct 模板反注释为可编译真定义）——上游代码与探针 diff 都只在 fork，**永不进 Vitro 仓**（GPL 红线）
- `gold_signatures.json` 的 `_meta`（source_fork / source_commit / regen）是重建配方的单源

## 四模式

| 命令 | 用途 | 前置 |
|---|---|---|
| `node scripts/realcode_diff/main.mts -repo <fork克隆> -out <目录>` | 外置仓全量对比（P1 walk→P2 Clang 真值→P3 serve 连发→P4 剥壳重试→P5 运行对比→P6 report） | Clang 22+ + `moon build --target native cmd/serve` |
| `node scripts/realcode_diff/main.mts -corpus <name> -out <目录> [-probe]` | **仓内语料批**对拍（Clang + gcc 分桶 + Vitro 三方；`-probe` 出语句表达式消解对照） | 同上 |
| `node scripts/realcode_diff/main.mts -aggregate <result.json> [-gold-out <名>] [-agg-repo <名>]` | result → 金样本聚合（只取码计数，不透传诊断 message） | 无 |
| `node scripts/realcode_diff/main.mts -check` | **仓内金样本静态合规闸**（CI hygiene）：schema 键集白名单 / 值域 / 诊断码形态 / provenance 锚四道 + **多金样本扫描** + `corpora.json` 三向对账 | 无 |

## 仓内语料批（2026-10-22 试点批落地）

| 批 | 类型 | 规模 | 许可 | 金样本 |
|---|---|---|---|---|
| `corpus/chibicc/` | 单文件 | 41 `.c` + 5 `.h` | MIT（chibicc 活跃 fork RunThem/chibicc-repo @ `b9c1f031`） | `gold_chibicc.json` |
| `corpus/multifile/` | 多文件工程 | 36 工程（74 `.c` + 38 `.h`） | MIT（本仓生成） | `gold_multifile.json` |

登记单源 = `corpora.json`。`-corpus` 模式下**子目录视为多文件工程**（目录内 `.c` + `.h` 作为一个 compile 请求的 files 数组一次编译）——这是防线唯一零覆盖的形态（#237）。

## 协议红线

- 勘探产物（report.md / result.json）**不进仓**——诊断 message 可引用源码 token；
- 金样本只存测量事实（文件名→诊断码/计数/层/运行判定），零源码文本（`-check` 机判守住）；
- 上游与探针 diff 只活在 fork 仓；
- **仓内语料批不进防线扫描域**（`corpus/<suite>/` 与 `scripts/realcode_diff/corpus/` 物理隔离，实证见 `README.corpus.md`）。

完整工作流（单份代码七步/剥壳/指纹归类/批量勘探）见 `.agents/skills/vitro-realcode-diff-workflow/`。
