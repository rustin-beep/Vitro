# realcode_diff —— 实机代码对拍勘探（外置语料基线）

Vitro 引擎 vs Clang 对 [TheAlgorithms/C](https://github.com/TheAlgorithms/C)（GPL-3.0）全量 C 文件的逐文件对比勘探工具与回归金样本。

## 外置语料锚（provenance）

- 上游 TheAlgorithms/C@`e5dad3f`（2023-09 终态，不再漂移）
- **fork [rustin-beep/C](https://github.com/rustin-beep/C)，默认分支即基线**：`vitro-probe-baseline` = 上游终态 + 89 文件探针态（补 include 128 处 + leetcode 注释内 struct 模板反注释为可编译真定义）——上游代码与探针 diff 都只在 fork，**永不进 Vitro 仓**（GPL 红线）
- `gold_signatures.json` 的 `_meta`（source_fork / source_commit / regen）是重建配方的单源

## 三模式

| 命令 | 用途 | 前置 |
|---|---|---|
| `go run ./scripts/realcode_diff/vitro_clang_diff.go -repo <fork克隆> -out <目录>` | 全量勘探（P1 walk→P2 Clang 真值→P3 serve 连发→P4 剥壳重试→P5 运行对比→P6 report） | Clang 22+ + `moon build --target native cmd/serve` |
| `go run ./scripts/realcode_diff/vitro_clang_diff.go -aggregate <result.json>` | result → gold_signatures 聚合（只取码计数，不透传诊断 message） | 无 |
| `go run ./scripts/realcode_diff/vitro_clang_diff.go -check` | **仓内金样本静态合规闸**（CI hygiene）：schema 键集白名单 / 值域 / 诊断码形态 / provenance 锚四道 | 无 |

## 协议红线

- 勘探产物（report.md / result.json）**不进仓**——诊断 message 可引用源码 token；
- 金样本只存测量事实（文件名→诊断码/计数/层/运行判定），零源码文本（`-check` 机判守住）；
- 上游与探针 diff 只活在 fork 仓。

完整工作流（单份代码七步/剥壳/指纹归类/批量勘探）见 `.agents/skills/vitro-realcode-diff-workflow/`。
