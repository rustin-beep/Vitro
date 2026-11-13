# moon check warning 台账

> **建账背景（B3 台账机制，2026-11-13）**：两轮独立评审实锤 `moonbit/AGENTS.md` 发布流程段「余额 34 条全为带据豁免」硬数字失真——0db534ec 实测 **98 条**（`moon check --target all` 口径；两轮评审各时点 80/98，批合入不清 warning 的活性缺口）。本台账为**止涨机制**的锚点文档：facts 键 `moonbit_check_warnings` 采集真值，本文裸数字声明对账——**warning 数增减即 facts 漂移红，须归因清点并更新本文**（涨须逐条归因入下表；清零是理想终态，减亦须同步）。

## 现值声明

moon check warning 台账现值：**98 条**（as_of 2026-11-13，master `0db534ec`，`moon check --target all` 全目标口径）。

## 计数口径（防双计，实测踩坑在案）

- **只计助记形 `Warning (name)` 行**——同一 warning 双行呈现（码行 `Warning: [NNNN]` + 块内助记行），裸 grep `Warning` 会双计（196 vs 真值 98，2026-11-13 实测）。
- 采集判据：输出须含 `Finished` 行（SIGPIPE/截断形态不采）且 exit=0（类型红输出非同口径面不采）——采集器 `scripts/facts/facts.mts::collectMoonbitCheckWarnings`，J9 三埋雷锚 `moonbit_fact.test.mts`。

## 首版清点（98 条归因）

### 按数字码（moonc 码族）

| 码 | 条数 | 归因 |
|---|---|---|
| 0002 | 28 | unused 变量/函数族——REHOST 批中间态（`wasmenc` 16 条：批 2 接线前哨函数）+ 历史散件 |
| 0020 | 24 | inspect 系（历史豁免族「Show→Debug 迁移期噪音」——当年 18 条，core 稳定后清零的预期未兑现，持续膨胀） |
| 0001 | 20 | unused import/package 族（历史豁免族） |
| 0029 | 10 | A3 批登记族 |
| 0060/0021/0046/0035/0057/0024/0004 | 13 | **新涌入码族**（工具链漂移 deprecated + method_shadowing/reserved_keyword 等结构性警告——非旧豁免面，须逐条清） |

旧口径 34 条 = 0020×18 + 0001/0002/0029/0050/0007 族；当前这些族合计 85 条（膨胀 +51），新码族 13 条。

### 按包 × 助记（前 12 面）

| 包 | 助记 | 条数 | 备注 |
|---|---|---|---|
| wasmenc | unused_value | 16 | REHOST 批 2 接线前哨（批 2 合入后应清） |
| names | unused_value | 5 | 待归因 |
| bytecode | unused_value | 4 | 待归因 |
| gateway/serve_step_wbtest | deprecated | 4 | 工具链弃用 API |
| parser | deprecated | 4 | 工具链弃用 API |
| lexer | unused_value | 3 | 待归因（含 `utf8_len` 待接线族） |
| time_travel | deprecated | 3 | 工具链弃用 API |
| typeck | unused_struct_update | 3 | 待归因 |
| vm | unused_value | 3 | 待归因 |
| cmd/run·cmd/vitro | unused_package | 各 2 | import 清理面 |
| 其余 37 面 | — | 47 | 零散（1~2 条/面） |

## 处置原则

1. **每批不涨**：批合入前 `moon check --target all` 计数 ≤ 台账现值；涨须逐条归因更新本表（新豁免须写理由）。
2. **REHOST 中间态豁免**：接线前哨的 unused（如 wasmenc 16 条）登记在案、批收口时清零。
3. **deprecated 面**：工具链升级引入的弃用 API 警告随 vitro-toolchain-upgrade 批次清（升级批义务），不做长期豁免。
4. **发布前置**（替代旧「余额 34」口径）：发版前 warning 数与本文现值一致 + 全部条目有据（本表或其引用的批次登记）。

## 历史与演化

- 2026-11-13：建账（B3 批）——首版清点 98 条（master 0db534ec）；旧手册口径 34（0.9.1 发版时点，2026-10-31）随之退役，发布流程段改指本台账。
