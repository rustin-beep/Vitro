# Vitro Clang 直拍门禁（clang_direct）

> 目的：以 Clang 本尊为真值源直拍 MoonBit 引擎，全量语料逐例对照，"通过 / 非预期差异"分流驱动扩展优先级。
> 最后核对：2026-10-05（S9 工序④删区批——吸收 shadow 防线后建册，取代已归档的《影子验证框架》）
>
> **当前地位**：**CI 硬门禁**（[ci.yml](../../../.github/workflows/ci.yml)）——Clang 缺失即 fail fast（exit 2），
> 存在非预期差异（DIFF）即 exit 1；SAME / DIFF-known（白名单内且 digest 锁定）视为通过。
> 与 `vm_diff`（引擎 vs 冻结 golden 的同构对拍）分工：**oracle 本身错而 Clang 对的形态只有本防线能抓**——
> golden 固化自 Rust oracle 时代产物，本防线直面 Clang 真值兜住固化锚的共同偏差。

<p align="center"><img src="clang-direct-gate-flow.svg" alt="Clang 直拍门禁流水线" width="880"></p>

---

## 一、防线语义

```
真值源   = Clang 本尊（编译运行语料产 golden——golden 唯一来源纪律）
被测物   = MoonBit cmd/run（stdout + 返回码；Latin-1 归一后逐字节比对）
判定     = SAME（含双侧编译失败等价）
         / DIFF-known（known_direct.json 白名单，case+digest 锁定）
         / DIFF（非预期差异 → 红）
```

三个语义要点（继承 shadow 与 vm_diff 的既有口径，删区批口径复核）：

1. **比对的是纯程序 stdout 通道**：引擎附注（"程序运行完成，返回值：N"、内存泄漏报告、教学警告）与 stderr 各有独立通道，不进入比对；驱动侧不做正则清洗。
2. **stdin 注入**：用例可自带同名 `.in` 文件，Clang 与 Vitro 喂同一份字节（缓存 key 纳入真实 stdin）。
3. **Latin-1 归一（本防线特有）**：`cmd/run` 把程序输出按 Latin-1 落 UTF-8 文本（0xC8 → `0xC3 0x88`），与 Clang 原字节比对前折回单字节（U+0080–U+00FF 封闭域，无损可逆）——putchar(≥128) 族差异由此直面真值。

## 二、运行方法

```bash
# 在仓库根目录执行（语料 = corpus/ 六目录全量）
go run ./scripts/clang_direct

# CI 形态：先验白名单新鲜度再跑全量
go run ./scripts/clang_direct --check-known
go run ./scripts/clang_direct
```

| 选项 | 说明 |
|:---|:---|
| `--corpus dir` | 指定单个语料目录（默认 `corpus/` 下 baseline / knr / leetcode / gap / codegen_skeleton / template_generated 六目录全量） |
| `--cases f1.c,...` | 指定具体用例（调试用） |
| `--sample N` | 仅跑前 N 例（调试用） |
| `--jobs N` | Clang 并发数（默认 min(CPU,8)；Vitro 侧始终互斥串行） |
| `--check-known` | 校验 `known_direct.json` 白名单逐条仍复现（digest 锁定；转绿即红逼移除，防白名单腐化） |

**前置条件**：`clang` 在 PATH 中（缺失 fail fast）；`cmd/run` exe 为 `moonbit/_build` 下的预编译产物（新鲜度门禁自动触发构建复核——构建按 [AGENTS.md](../../../AGENTS.md) 第 11 条 `MOON_CC=clang`）。

**提速设施**：Clang Golden 缓存（`.clang_cache_cd/`，schema `cd1`；key = 源码 + stdin + clang 版本 + 参数）+ Clang 并发执行 + per-case 唯一命名（Windows 同名 exe 映像竞态防御）；瞬态异常（超时 / 启动失败 / `0xC0000005`）自动重试且**不落缓存**。

## 三、已知差异白名单（known_direct.json）

`scripts/clang_direct/known_direct.json` 为**活文档**：每条 = 用例名 + 差异 digest 锁定——

- 用例输出漂移 → digest 失配 → **降级红**（防白名单腐化）
- 差异修复转绿 → **即红**（逼移除条目——白名单只减不增的守门形态）
- 新增条目须先证红（红→绿纪律：DIFF 用例登记白名单前必先以非预期差异形态在 CI 露红）

与 shadow 时代的 `KNOWN_FAILURE_CASES` 双向监控同构；删区批（2026-10-05）语料域差量 0（shadow 685 ⊆ clang_direct 698），白名单逐条平移。

## 四、与差分 golden 的关系

| 维度 | clang_direct（本防线） | vm_diff 等五差分闸 |
|------|----------------------|-------------------|
| 对比对象 | Clang 本尊（活真值） | 冻结 golden（工序③固化锚，源自 oracle 时代同构产物） |
| 抓什么 | 引擎与真值的**一切**偏差（含 golden 固化锚本身偏差） | 迁移/演化期对固化基线的**回归** |
| 位置 | 层 2 直拍 | 逐层对拍（token TSV / AST / E1–E4 / 字节码 / 执行轨迹） |

两者互补：差分闸保证「不偏离冻结基线」，本防线保证「冻结基线 + 引擎共同偏差逃不过 Clang」。

## 五、语料与新增用例义务

语料目录 `corpus/`（原 `native/tests/cases/` 于 2026-10-05 删区批迁入）；新增/修改用例的完整义务链（clang golden → e2e → 直拍 → facts → SVG 连坐）见 Agent Skill **vitro-baseline-corpus-workflow**（`.agents/skills/`）。

---

*框架位置：驱动 `scripts/clang_direct/main.go`（Go，零第三方依赖）；语料 `corpus/{baseline,knr,leetcode,gap,codegen_skeleton,template_generated}/`；白名单 `scripts/clang_direct/known_direct.json`；缓存 `.clang_cache_cd/`（gitignore）。
前身《影子验证框架》已归档：[`docs/archive/ARCHIVE_影子验证框架.md`](../../archive/ARCHIVE_影子验证框架.md)（2026-05-17 起的用例演化史与转义历史口径在档）。*
