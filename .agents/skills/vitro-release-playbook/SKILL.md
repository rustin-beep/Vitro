---
name: vitro-release-playbook
description: Vitro mooncakes（vitro/engine）发版与彩排手册——版本定性、发布前置、moon publish 机械事实、registry 投放彩排法、验收清单、下载计数异常排查。Use when publishing a new version of vitro/engine to mooncakes, rehearsing a release before publish, or investigating download count anomalies. 触发词：发版、moon publish、mooncakes、彩排、minor、patch、下载计数。
---

# mooncakes 发版与彩排手册

**适用场景**：发布 `vitro/engine` 新版到 mooncakes；publish 前彩排；下载计数异常排查。

## 1. 版本定性（先于一切）
跑接口面 diff（`go run ./scripts/moonbit/moonbit_surface -check` 与 `.mbti` 对比）：
- **新增公共 API / 新增包 → minor**；纯修复 / 文档 → patch；
- 0.x 阶段 minor 可带 breaking（CHANGELOG 明示破坏面）。

## 2. 发布前置
- 防线全绿：CI 两 job + `toolchain_probe`；本地 = `moon check --target all` 干净、`moon test` 全绿、`moon info` 无意外 diff、`gen_diag -check` 绿。
- **连坐面**：`moon.mod` description（模块页直接展示）、CHANGELOG（破坏面置顶）、README 包表与测试数、包图徽标（facts 锚机械派生，改包集/版本必连坐）、`docs/current/02/脚本总清单`。

## 3. moon publish 机械事实（踩过的实锤）
- **module 级打包，无包排除选项**：工作树有什么 zip 就装什么（连 AGENTS.md 都进包）。要「发布不含某包」只能：发布时临时移出包目录 → publish → 移回；移出前先验依赖方向（无人 import 则剩余树自洽编译）。
- zip 内 README 与包集必须一致（README 提到的包 / 测试数改成该版口径），否则发布物自相矛盾。
- `moon.mod` readme 字段须指**根 `README.md`**——`README.mbt.md` 不会被模块页渲染。
- **checksum 入 registry 不可覆盖**：发错无法撤回，修复只能递增版本——因此彩排不可省。
- module 名首段必须等于发布者用户名（`vitro/engine` ↔ 账号 `vitro`），403 User mismatch 即此因。
- 索引同步有数分钟延迟：发布后 `moon add` 暂时 404 属正常节奏，轮询即可。

## 4. 彩排投放法（publish 前唯一可靠路径）
本 module 无本地 path 依赖、`.mooncakes` 手放不满足版本解析——彩排只能走 registry 投放：
1. 自建包 zip 投放 `~/.moon/registry/cache`；
2. `~/.moon/registry/index/user/vitro/engine.index` JSONL **追加一行**（字段对照已发布版本的行补全；**必须带 deps 字段**，否则传递依赖解析失败——此坑只在手工投放出现，真实 publish 会自动上报）；
3. 干净新项目 `moon add vitro/engine@<ver> --no-update`；
4. 验收：`check --target all` 全包编译、wasm 目标 run 消费示例、native 构建、zip 根级文件核对（LICENSE / README.md / README.mbt.md / moon.mod）；
5. **投放物用后删除即复原**（cache zip + index 追加行）。

## 5. 发布与验收
- `cd moonbit && moon publish`，Server 200 OK 后 push，CI 双绿；
- 验收三件：`moon search vitro` 可查 → 全新项目 `moon add` + 跑一段示例 → registry cache zip 根级核对；
- 每次验收自产 +1 下载属正常噪音。

## 6. 下载计数异常排查（如固定 +1/小时）
三成分按序排除：**自指陷阱**（打开模块页渲染可能拉包，每次浏览 +1）> **平台爬虫**（对照同量级包的曲线）> 外部闭源用户。判别 = 24h 不打开页面 + `moon search` 取快照（零污染）。

## 权威源与时效
- `moonbit/AGENTS.md` §发布流程；`docs/current/08-发布档案/` 各版本档案
- **相关规程**：`vitro-facts-reconciliation`（徽标/测试数为 facts 锚，改版本必连坐）、`vitro-generator-contract`（包图由生成器出）、`vitro-toolchain-upgrade`（升级后发版的先后关系）
- as_of: 2026-09-28（0.5.0 / 0.6.0 两轮实战沉淀）
