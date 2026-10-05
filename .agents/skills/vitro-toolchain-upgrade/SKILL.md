---
name: vitro-toolchain-upgrade
description: Vitro 项目 MoonBit 工具链漂移处置手册。Use when toolchain_probe reports version drift (A8), after upgrading the moon/moonc toolchain, or when moon test fails with "link-core failed" or exit 1 with zero error output. 触发词：工具链升级、版本漂移、moonc、bundle、--update-baseline。
---

# MoonBit 工具链漂移处置（Vitro 专属）

**适用场景**：`scripts/toolchain_probe` 报红（版本漂移 / registry 索引缺失 / ICE），或升级 moon 工具链后构建链接全挂。

**策略前提**：Vitro 对 moon 工具链执行**追新策略**（用户裁定：不锁版本——锁旧版只会积累升级债）。CI 的 `hygiene` job 里 `toolchain_probe` 红 = 「该走本手册」的记账信号，**不是代码坏**，不阻塞当天推进。

## 处置流程（严格按 1→4，顺序不可换）

### 1. 手动升级本地工具链
- `moon upgrade` 在非交互终端必失败（not a terminal）；PowerShell 一键脚本 `irm … | iex` 在沙箱/受限网络下易卡死。
- 可靠路径 = 手动下载：
  - `https://cli.moonbitlang.com/binaries/latest/moonbit-windows-x86_64.zip`（约 86MB，慢网加 `curl -C -` 断点续传），解压到 `~/.moon`；
  - 再下 `cores/core-latest.zip`，解压到 `~/.moon/lib`。

### 2. ⚠️ 必补 bundle 步（手动安装必漏）
官方 install 脚本会执行「Bundling core」，手动解压不会。**漏掉的症状：所有 `moon test` 报 `moonc link-core failed`（`input …bundle/abort/abort.core missing`）。**

```bash
cd ~/.moon/lib/core
moon bundle --warn-list -a --all
moon bundle --warn-list -a --target wasm-gc --quiet
```

另：旧 `core/_build` 残留配新 moonc 同样链接失败——`rm -rf core` 重装 + bundle 即解。

### 3. 症状判别
- `moon test` exit 1 却**零错误输出** = link-core 全挂（`--verbose` 才能看到 failed 行）。
- `moon check` 0 errors 但测试仍挂 → 优先怀疑工具链安装残缺，不是代码问题。

### 4. 收尾：基线迁移与真值刷新
```bash
go run ./scripts/toolchain_probe --update-baseline   # 写新基线（cwd=仓库根）
go run ./scripts/toolchain_probe                     # 探针四项须全绿
go run ./scripts/facts --run                         # ① 只采集、刷新真值（无子命令 ⇒ 不做对账）
go run ./scripts/facts --run check                   # ② 采集 + 对账判红 —— 要"确认无回归"必须带 check 子命令
```

> ⚠️ `scripts/facts/main.go` 的 `switch cmd` 只有 `check` / `report` / `sync` 三个分支、**没有 default**：
> 不带子命令时**不执行任何对账、恒 exit 0**。只想刷新真值用 ①，要判红必须用 ②。
> （CI 的现役完整形态见 `ci.yml`：`facts --strict check`——**flag 写在子命令之前**；删区批已去 `--run`/`--cargo-log`，cargo 族真值源随 Rust 区退役。）

## 假红鉴别：探针的 CRLF 坑
症状：探针打印的基线与实测**一致却仍红** → 查行尾（`git ls-files --eol` 对比 blob 与检出）。Windows checkout 的 autocrlf 会把 LF 基线检出为 CRLF。探针已内置 CRLF 规范化与空行跳过；若仍见此形态，先确认基线文件入库为 LF。判「真漂移」前先分辨是不是行尾假红。

## 升级后 changelog 核对重点
优先核对**切片语义 / 警告默认值**类行为变化。实例（0.10.13→0.10.14）：切片 `a[i:j]` 改为钳制化；`unused_package` / `test_unqualified_package` 警告默认开启。本仓无 deny 级警告配置时通常不阻塞，但要过一遍新增警告，确认没有新缺陷信号混在里面。

## 权威源与时效
- `scripts/toolchain_probe/toolchain_probe.go` 头注（用法与 J9 埋雷记录）
- `moonbit/AGENTS.md` §构建与验证命令
- **相关规程**：`vitro-facts-reconciliation`（升级后刷新真值）、`vitro-release-playbook`（升级与发版的先后关系）
- as_of: 2026-09-28（0.10.13→0.10.14 实战两轮沉淀；具体版本号会过时，流程长期有效）
