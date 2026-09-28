---
name: vitro-facts-reconciliation
description: Vitro 文档数字对账（scripts/facts）的判读手册——假红/假绿形态、判定优先级、埋雷证红方法、文档数字统一格式三规范。Use when facts check turns red or green unexpectedly, writing numeric claims into docs, planting J9 landmine tests, or adding facts rules. 触发词：facts、文档数字、漂移、埋雷、doc_fact_drift、对账、as_of。
---

# facts 文档对账判读手册

**适用场景**：`go run ./scripts/facts check` 红/绿异常判读；往需维护文档写数字；J9 埋雷证红；新增 facts 规则。

## 机制认知
- facts = CI `hygiene` job 的文档数字对账门禁；真值存 `reports/facts.json`（**gitignored**，防双真相）——本地对账前先采集。
- `cached` 真值沿用不红，`--run` 才刷新；子命令顺序与 flag 位置**照抄 CI 接线**（flag 必须写在子命令之前）。
- ⚠️ **无子命令 ⇒ 不对账、恒 exit 0**：`main.go` 的 `switch cmd` 只有 `check` / `report` / `sync`，**没有 default**。`go run ./scripts/facts --run` 只采集刷新真值，**不判红**；要"确认无回归"必须带子命令——`facts --run check`（CI 完整形态 `facts --run --cargo-log native/cargo_test_ci.log check`）。
- cargo 真值走 `--cargo-log`，规范形态 = cargo test 输出 tee 落在 `native/cargo_test_ci.log`（gitignored）再传该相对路径。日志放 Git Bash 的 `/tmp` 时，Go 进程看到的是不同路径——解析**静默失败**、真值沿用 cached 而不报错。处置 = 把日志拷到规范路径再跑。

## 假绿四形态（绿 ≠ 账对）
- **cached 沿用**：要 `--run` 才刷新；
- **shadow 产物陈旧**：对着旧 shadow_data_latest.json「对齐」出绿，校验 as_of 新鲜度；
- **CI 产物落位错层**：hygiene 的 artifact 下载后目录层级会变，采集器按原位路径读 → 键一直 unavailable——CI 里须有「恢复产物到引擎报告路径」的步骤；
- **真值键缺位**：历史上发生过采到的套件数在下一次落盘时被无声丢弃（现两处已对称补 unavailable 占位，本地可预演 CI）。见怪先查**并发**（用户/CI 同时在跑 facts 覆写报告）。

## 假红三形态（红 ≠ 文档错）
- **Context 命中无紧邻单位约束**：同行的无关数字会被就近规则吸走判漂移（行数被当用例数、包版本被当 ABI 版本）；
- **超龄按 provenance 分流**：read_const / fs_scan 类的 as_of = 源文件 mtime，源未变即真值有效，按「采集动作超龄」判是假红；只有须重跑才保真的 provenance（run / read_report 类）超龄才真红；
- **新表格行裸写数字**：会被邻近规则的区间吸走判漂移——口径括注引用上行（「语料口径同上行」）或去数字化。另：往表格中间插说明段落会把表物理拆断，说明段放表后。

## 判定优先级与冻结盲区
- 行分类优先级：**frozen > manual > suspect 兜底**。
- 分解式行（`680 个（676 + 3 + 1）`）归 manual 人工维护，**不机判红**；
- 行内**任何位置**命中 as-of 词（截至 / 彼时 / 当时 / 历史…）即**整行冻结**，且 frozen 优先于一切——测试数声明行带个无关时点括注就全通道失明。**时点括注用词表外词**：写「时点见 git log」，勿写「git 历史」（「历史」在词表内）。

## 写文档数字：统一格式三规范（长期免维护）
1. 实测记录句必带日期（`YYYY-MM-DD`）；
2. 历史 / 计划对照句必带时点词（截至 / 彼时 / 当时 / 历史）；
3. **外部项目事实**（第三方仓库的测试数 / 行数等）不写入需维护文档正文——确需留档，整份走豁免白名单 `scripts/facts/exempt_docs.json`（path + reason 必填，条目指向不存在的文件即红）。

**裁定**：不修改 facts 判据脚本迁就文档——处置一律改文档写法或入白名单，效果 = check 与 `--strict` 双模式全绿后不再回头。

## J9 埋雷方法
- 埋雷选**非分解式、非实测绑定**的行（分解式不机判红，埋了白埋）；
- 证红后用「通道可见性探针」（读 classifyLine / 候选数字 / 行内是否含真值）比静态断言更能抓住盲区；
- SVG 内嵌数字走 `<tspan data-fact>` 通道，漂移红后重跑 `gen_svg`，**禁手改**；md 通道 `<img` / `width=` 行整行豁免。

## 权威源与时效
- `scripts/facts/` 头注与 `img_line_test.go` / `cargo_fact_test.go` 的 J9 锚
- **相关规程**：`vitro-baseline-corpus-workflow`（加语料后的连坐面）、`vitro-generator-contract`（SVG `data-fact` 由生成器出，漂移红后重生成）、`vitro-toolchain-upgrade`（升级后刷新真值）
- as_of: 2026-09-28（判据词表与白名单路径以仓库现行实现为准）
