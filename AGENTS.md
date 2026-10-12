# Vitro 项目 Agent 指南

> [English Version](AGENTS_EN.md)
>
> 本文件只保留**分区路由与全域纪律**。唯一活跃分区 `moonbit/` 的操作手册——[`moonbit/AGENTS.md`](moonbit/AGENTS.md)（构建命令 / 语言与工具链陷阱 / 编码纪律 / 发布流程）——**触碰该分区时才读取**，避免上下文挤占。

## 仓库分区（Rust 对照区已于 2026-10-05 退役删除）

| 区 | 范围 | 状态 | 规则来源 |
|---|---|---|---|
| **MoonBit 活跃区** | `moonbit/`（MoonBit workspace，已发布 mooncakes `vitro/engine`） | **唯一实现区**，全部新开发在此 | [`moonbit/AGENTS.md`](moonbit/AGENTS.md)（**按需读取**：命令 / 语言与工具链陷阱 / 编码纪律 / 发布流程）+ [`MoonBit迁移总计划`](docs/current/01-定位与路线/MoonBit迁移总计划.md)（含包切分 / 锚点体系 / 工程约定 / 工具陷阱） |
| **Rust 对照区（已退役）** | 原 `native/` 已于 2026-10-05 工序④删区**物理删除**；`scripts/`、`.github/` 为 Go 防线层（语言中立，无分区手册） | 档案态：tag `rust-oracle-freeze` · 分支 `frozen-oracle-snapshot` · git 历史 | 无手册可读；Rust 语义问题查档案 tag 与 [S9冻结资产清单](docs/current/07-质量与裁定/S9冻结资产清单.md) |

**路由规则**：触碰 `moonbit/` → **先读** [`moonbit/AGENTS.md`](moonbit/AGENTS.md)；只在文档 / 讨论中工作 → **不要读**（避免上下文挤占）。

**MoonBit 包命名规则（2026-09-19 拍板）**：module 名 = `vitro/engine`（mooncakes owner `vitro`），包全名一律 `vitro/engine/<pkg>`（如 `vitro/engine/diag`）；`moon.pkg` 的 import 块、`gen_diag` 等生成脚本注释、`.mbti` 接口面均用全名；计划文档语境可简称 `vitro/<pkg>`，但代码与配置**禁用**简称。

## 全域纪律（语言无关）

1. **必须中文输出思考与回答**
2. **未经允许禁止 git 提交**
3. **实测大于脑测、统一真相来源**：结论须来自亲跑命令 / 亲读代码；报告与文档声明只作线索不作依据；数字对真值（`reports/facts.json` 的 key + as_of）。**口径注（2026-09-29 拍板；2026-10-01 起 CI 已含 `--strict`——Suspect 兜底进 CI 判红，合法误报面经 `scripts/facts/suspect_exemptions.json` 显式过闸，僵尸条目无条件红）**：CI 的 facts 步是 `check --strict`；测试数键 `moonbit_test_passed` = 裸 `moon test` 口径——引用测试数时须带口径
4. **诚实记录**：以 Clang 为标准，任何与标准不符之处必须记录；禁止修改测试预期值粉饰数据
5. **红→绿纪律**：每个缺陷修复先有会失败的用例，修复提交引用用例名；护栏 / 判定型脚本必须先证会红（J9 埋雷义务）
6. `docs/archive/` 下的归档文档**不具备参考价值**，禁止引用
7. **文档体系**：新文档进 `docs/current/` 对应分类子目录（中文文件名），同步 `docs/README.md` 索引；被取代的移入 `docs/archive/`（`ARCHIVE_` 前缀 + 归档横幅）。CHANGELOG 的 `[Unreleased]` 全文**唯一一段**——新条目**追加**到该段既有小节、禁止新插第二个 `[Unreleased]` 标题，已发布内容随发版移入对应版本节（2026-10-06 拍板：曾堆出四段重复 Unreleased 致防线计数多版本并存，agent 引用即幻觉）
8. **判定型脚本默认 Go**：零第三方依赖、规则外置 JSON、fail loud、禁止静默 default
8.5. **存在即接入注册表（2026-10-11 建，`scripts/ci_checklist`）**：scripts 下每个 package main 驱动**落地即须被 ci.yml 活行引用或在 `scripts/ci_checklist/exceptions.json` 带 reason 自证**——三向对账（漏登记/悬空/僵尸例外）CI 红。新驱动入库从此不再依赖「记得接线」的人肉清单（libc_boot 断供类红的事前形态根除）；例外三类合法形态=库目录/本地工具/CLI 资产（闸头注）。
9. **工具陷阱五条**：`| head` 会 SIGPIPE 杀编译器（判"构建失败"前必须 tail 全量输出）；管道 `$?` 是尾命令退出码（用 PIPESTATUS 或裸命令取）；哨兵先证红再采信结论；基准对照必须校验和逐位一致才计时；Windows 路径的 grep 过滤要 `[/\]` 双兼容
10.5. **决策登记含被驳记录与否掉理由**（2026-10-11 定）：用户拍板与 agent 被驳都要一句「为什么」落 issue 评论/判定书（S9 判定书「不做会怎样」列即此形态）；**不建结构化模板/状态机/闸**（同日评估否决——msime 决策笔记形态与单 issue 代际链冲突，第二真相源）。
10. **提交署名 = 审阅深度信号**（2026-09-19 拍板）：git 提交信息中**提及用户**（署名 / 审阅标记）表明该批代码经过用户深度审阅与探针测试；**未标明**仅代表用户浏览过，不构成审阅背书。机器判读提交可信度时以此为准。
11. **MoonBit native 目标构建默认 clang、放弃 MSVC**（2026-10-04 拍板）：Windows 上 moon 探测序默认绑 MSVC，撞 [moon#2254](https://github.com/moonbitlang/moon/issues/2254) 构建悬崖（每个链引擎闭包的 exe 冷态 ~130s——本仓已 5 个此类 exe，全量分钟级；`MOON_CC=clang` 同构建 29s 实测）。**一律 `MOON_CC=clang` 后再 `moon build --target native`**；另**新增包或出口面须连坐 surface 边表/pkg_deps 白名单登记，否则 CI 红**。
12. **agent 日常验证默认吃自家狗粮 + 统一入口（2026-10-04 拍板；2026-10-06 #49 批一改向统一入口）**：agent 日常临时验证 C 行为（试编译 / 查行为 / 复现小片段）默认走统一入口 `scripts/bin/vitro`（sh；Windows cmd 环境用 `vitro.cmd`）——**默认 wasm 臂**（node 壳消费 `gateway/wasm/wasm.wasm`，需 node ≥25），node 缺失/过旧自动降级 native exe（stderr 明示 `backend=`）；`--backend native|wasm` 显式选边。四子命令 `run`/`compile`/`step`/`api` 参数面与 rc 五值表 = CLI_PROTOCOL_V1 spec 单源；wasm 臂产物重建 `moon build --release --target wasm-gc gateway/wasm`、native 臂按第 11 条 `MOON_CC=clang`。脚本消费一律 `--json`。同形性由 CI 闸 `scripts/vitro_cli_smoke`（双臂对拍）锁。**真值源边界**照旧：vitro 输出只作「Vitro 行为」依据、不作「C 语义正确」依据——存疑或对外断言必对拍 gcc/clang 定责，不一致按 vitro-realcode-diff-workflow 登记缺陷。防线既有通道（clang golden / e2e / 双侧对拍）豁免照旧。
13.5. **git 钩子（2026-10-11 建，`.githooks/` 三分——msime 形态适配）**：`git config core.hooksPath .githooks` 一次启用（worktree 共享配置）——pre-commit 亚秒文本闸（冲突标记新增行扫描 / moon fmt 漂移·staged 限定 / gofmt / editorconfig 硬性项；**moon fmt 不扫包外散文件**——新 .mbt 必须落进有 moon.pkg 的包，否则 fmt/CI 双盲）；pre-push + pre-merge-commit = moon check 类型面兜底（热 1.1s/冷最坏 ~30s）。跳过：`--no-verify`（逃生门保留）。**不做 --quick 改动面裁剪**（2026-10-11 拍板：单仓 MoonBit+Go 互相耦合，改动面映射切不准——msime 的多语言天然边界在本地不存在）。
13. **`.json.mbt` 数据真相源纪律（2026-10-07 拍板，铺开批随行）**：本仓数据真源分两层——手写面（diagnostics_data / ledger / known 族，第二批迁移中）与机器写回面（五套 golden digest，已伴生 `.mbt` 真源）+ 11 张 rules（jsonmbt 迁移批②，.mbt 唯一真源、.json 由 CI `jsonmbt build` 再生不入仓）。**agent 修改数据的固定流程**：改 `.json.mbt` 真源 → `jsonmbt check`（或 `moon check`）→ `jsonmbt build` 再生 → round-trip 对拍绿才提交；**禁止手改再生 .json / @generated 标注的 .mbt**（跑头部标注的再生命令）；五套 digest 的 .mbt 由 freeze 循环自动再生（`--freeze-mb` 写回点接线 `scripts/jmemit`），人工不直改。使用指南见 skill `jsonmbt-authoring`（本仓 `.agents/skills/` 本地副本，权威源在 jsonmbt 仓）。
14. **双端强制（2026-10-12 拍板；第二次实锤升格全域）**：任何语料验证 / 对拍 / 防线验收结论必须 **wasm + native 双臂各跑一次、双方一致才可采信**——单臂结论只作线索不作验收依据（两次实锤：历史语料管线曾因双端不一致整线清出；2026-10-12 LLM 语料探针第二次复证，#73）。双臂产物构建照第 12 条（wasm 臂 `moon build --release --target wasm-gc gateway/wasm` / native 臂按第 11 条 `MOON_CC=clang`）；分桶体系 `arm_divergence`（wasm≠native）列**最高 severity 独立桶**。

## Agent Skills（`.agents/skills/`，2026-09-28 建）

踩过实锤的操作手册——工具链升级 / 生成器 `-check` 契约 / 语料用例义务链 / facts 判读 / 发版彩排 / 仓库审阅规程——按**通用 Agent Skills 格式**（目录 + `SKILL.md`）存放于 `.agents/skills/`，与分区手册分工：AGENTS.md 是每批都读的静态纪律，skills 是 agent 命中触发场景时才加载的详细手册。ZCode 直接扫描该目录无需安装；其他工具 `go run .agents/install_skills.go --all`（零依赖 Go 安装器，详见 [`.agents/README.md`](.agents/README.md)）。**维护义务**：改动 skill 覆盖的流程须连坐更新对应 `SKILL.md`（各文件尾部有 as_of）。

## 当前阶段与档案

> **时点口径（as_of 2026-09-29）**：本节只做指针，版本/阶段状态一律以排期权威为准，勿在此堆时点事实（13 号模块审阅 P2-1 实锤：时点句写进"静态纪律"文件必陈旧）。发版连坐清单须点名本文件。

- **当前**：**S9 进行中**——0.8.0 已于 2026-10-05 线上发布（S8 收官版，tag `vitro-engine-0.8.0`，线上验收三件全绿，[发布档案](docs/current/08-发布档案/0.8.0.md)）；S9 = Rust oracle 脱钩批（工序四步）+ S9 裁定批 + 解锁修复面（#3~#24 等 22 条）、1.0 = 退役——排期权威与逐片验收锚见[总计划 §10](docs/current/01-定位与路线/MoonBit迁移总计划.md)，版本档案见 [docs/current/08-发布档案](docs/current/08-发布档案/0.8.0.md)；已完成：S0.5–S8（S5 0.5.0 / S6 0.6.0 / S7 0.7.0 / S8 0.8.0 均已发布）+ S9 工序①~④（#39 真值源迁移、golden 固化、裁定、删区）
- **退役（已执行）**：Rust 对照区已于 2026-10-05 工序④**整体删除**（档案 = tag `rust-oracle-freeze` + 分支 `frozen-oracle-snapshot` + git 历史；MoonBit 探测阶段 16 份文档在提交 `917251e`，取回方法见总计划 §11）；1.0 的退役对象只剩 Go 防线层与三外援的终局评估（见总计划 §10）
