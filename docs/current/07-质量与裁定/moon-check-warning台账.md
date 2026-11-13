# moon check warning 台账

> **建账背景（B3 台账机制，2026-11-13）**：两轮独立评审实锤 `moonbit/AGENTS.md` 发布流程段「余额 34 条全为带据豁免」硬数字失真——0db534ec 实测 **98 条**（`moon check --target all` 口径；两轮评审各时点 80/98，批合入不清 warning 的活性缺口）。本台账为**止涨机制**的锚点文档：facts 键 `moonbit_check_warnings` 采集真值，本文裸数字声明对账——**warning 数增减即 facts 漂移红，须归因清点并更新本文**（涨须逐条归因入下表；清零是理想终态，减亦须同步）。

moon check warning 台账现值：**98 条**（`moon check --target all` 全目标口径）。

> **上一行是机判锚——禁写日期 / as_of / 截至等词**：现值行带日期会被 audit 冻结豁免旁路（`classifyLine` 命中 `RE_DATE|RE_ASOF_WORD` 即整行冻结，永不进 drift——PR #511 审阅 P1-1 实锤：12 处候选全冻结、止涨闸拦截力为零）。现值行只写活数字（2026-10-04 格式裁定：冻结豁免被门面现值句搭便车 = 文档格式问题，处置是改文档不加机制兜底）；带日期的更新记录写文末。

## 计数口径（防双计，实测踩坑在案）

- **只计助记形 `Warning (name)` 行**——同一 warning 双行呈现（码行 `Warning: [NNNN]` + 块内助记行），裸 grep `Warning` 会双计（196 vs 真值 98，2026-11-13 实测）。
- **Finished 行总数互证**：`Finished … (N warnings, 0 errors)` 的 N 与助记计数做相等断言（两者不等 = 输出形态漂移，不采——防 moonc 格式变化静默少计；PR #511 审阅 P3-3 处置）。
- 采集判据：输出须含 `Finished` 行（SIGPIPE/截断形态不采）且 exit=0（类型红输出非同口径面不采）——采集器 `scripts/facts/facts.mts::collectMoonbitCheckWarnings`，J9 测试五锚（三埋雷 + 绿路径 + RUN_KEYS 在册）`moonbit_fact.test.mts`。

## 首版清点（98 条归因）

### 按码 × 助记（块级配对实测，PR #511 审阅复核双证）

| 码 | 助记 | 条数 | 归因 |
|---|---|---|---|
| 0002 | unused_value | 28 | 未用变量/函数——REHOST 批中间态（wasmenc 16 条接线前哨）+ 历史散件 |
| 0020 | deprecated | 24 | 弃用 API（工具链漂移面——旧手册「0020=inspect 系」叙事与现测不符，码表语义以现测为准，历史漂移待工具链批归因） |
| 0001 | unused_value | 20 | 未用值族（历史豁免族膨胀） |
| 0029 | unused_package | 10 | 未用 import（历史豁免族膨胀） |
| 0021 | missing_pattern_arguments | 3 | 模式参数缺失 |
| 0060 | unused_struct_update | 3 | struct 更新未用 |
| 0050 | method_shadowing | 2 | 方法遮蔽 |
| 0035 | reserved_keyword | 2 | 保留字标识符 |
| 0046 | unused_rest_mark | 2 | rest 标记未用 |
| 0024 | unused_error_type | 1 | 错误类型未用 |
| 0007 | unused_field | 1 | 字段未用 |
| 0057 | missing_pattern_payload | 1 | 模式载荷缺失 |
| 0004 | missing_priv | 1 | 缺 priv 标注 |

旧口径 34 条（0.9.1 发版时点）= 0020×18 + 0001/0002/0029/0050/0007 族；当前这些族合计 85（膨胀 +51），新码族 13（0021/0060/0035/0046/0024/0057/0004）。

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
| cmd/run · cmd/vitro | unused_package | 各 2 | import 清理面 |
| 其余 24 面 | — | 49 | 零散（1~2 条/面；全量分布以块级配对探针为准——PR #511 审阅复核数据 `tmp/review_20261113/wt511/tmp_check1.log` 同源） |

（前 12 面 49 条 + 其余 49 条 = 98。）

## 处置原则

1. **每批不涨**：批合入前 `moon check --target all` 计数 ≤ 台账现值；涨须逐条归因更新本表（新豁免须写理由）。
2. **REHOST 中间态豁免**：接线前哨的 unused（如 wasmenc 16 条）登记在案、批收口时清零。
3. **deprecated 面**：工具链升级引入的弃用 API 警告随 vitro-toolchain-upgrade 批次清（升级批义务），不做长期豁免。
4. **发布前置**（替代旧「余额 34」口径）：发版前 warning 数与本文现值一致 + 全部条目有据（本表或其引用的批次登记）。

## 更新记录

- 2026-11-13：建账（B3 批）——首版清点 98 条（master 0db534ec）；旧手册口径 34（0.9.1 发版时点）随之退役。同日 PR #511 审阅处置：现值行去 as_of（冻结豁免旁路修复，P1-1）、码×助记块级配对修正（0001/0029 归因对调勘正、0020 实测 deprecated、余面 24 面/49 条勘正，P2-3）、Finished 行总数互证入采集器（P3-3）。
