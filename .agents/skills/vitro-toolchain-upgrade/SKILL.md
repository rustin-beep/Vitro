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
  - 主包 `https://cli.moonbitlang.com/binaries/latest/moonbit-windows-x86_64.zip`（约 93MB），解压到 `~/.moon`（bin/lib/include/share 四目录覆盖）；
  - core **全 URL = `https://cli.moonbitlang.com/cores/core-latest.zip`**（2026-11-07 实锤：**不带** `binaries/latest/` 前缀——路径拼成 `binaries/latest/cores/…` 拿到的是 S3 `AccessDenied` XML 错误页而非 zip），解压到 `~/.moon/lib`（zip 内自带 `core/` 前缀，先 `rm -rf ~/.moon/lib/core`）。
  - ⚠️ **`curl -C -` 断点续传的污染坑（2026-11-07 实锤）**：目标文件已存在且内容是上次失败的错误页（XML）时，`-C -` 会**把 XML 当前缀续传追加**，得到大小正常但整体偏移错位的 zip（`unzip` 报 `bad zipfile offset (local header sig)`）。断点续传只对「同一次未完成的下载」续；见到 XML/文件名怪异先删文件重下，再 `unzip -t` 校验。
  - 版本别名机制（pin 探测用）：`binaries/0.10.x%2B<hash>/…` 与 `cores/core-0.10.x%2B<hash>.zip` 的 GET 可用（206）；**S3 对 HEAD 一律 403**——探测 URL 存活必须用 GET（`-r 0-99`）不能用 `-I`。`latest` 可能一次跳两版（2026-11-07：用户点名 0.10.19 时 latest 已是 0.10.20；版本化日期 URL `binaries/<0.1.日期>/` 未见公开别名，追新直接用 latest）。

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
node scripts/toolchain_probe/toolchain_probe.mts --update-baseline   # 写新基线（cwd=仓库根）
node scripts/toolchain_probe/toolchain_probe.mts                     # 探针四项须全绿
node scripts/facts/main.mts --run                         # ① 只采集、刷新真值（无子命令 ⇒ 不做对账）
node scripts/facts/main.mts --run check                   # ② 采集 + 对账判红 —— 要"确认无回归"必须带 check 子命令
```

> ⚠️ `scripts/facts/main.mts` 的 `switch cmd`（原 main.go 已随 2026-11 双轨收口删除） 只有 `check` / `report` / `sync` 三个分支、**没有 default**：
> 不带子命令时**不执行任何对账、恒 exit 0**。只想刷新真值用 ①，要判红必须用 ②。
> （CI 的现役完整形态见 `ci.yml`：`facts --strict check`——**flag 写在子命令之前**；删区批已去 `--run`/`--cargo-log`，cargo 族真值源随 Rust 区退役。）

## 假红鉴别：探针的 CRLF 坑
症状：探针打印的基线与实测**一致却仍红** → 查行尾（`git ls-files --eol` 对比 blob 与检出）。Windows checkout 的 autocrlf 会把 LF 基线检出为 CRLF。探针已内置 CRLF 规范化与空行跳过；若仍见此形态，先确认基线文件入库为 LF。判「真漂移」前先分辨是不是行尾假红。

## 升级后 changelog 核对重点
优先核对**切片语义 / 警告默认值**类行为变化。实例（0.10.13→0.10.14）：切片 `a[i:j]` 改为钳制化；`unused_package` / `test_unqualified_package` 警告默认开启。本仓无 deny 级警告配置时通常不阻塞，但要过一遍新增警告，确认没有新缺陷信号混在里面。

**语法升格实例（0.10.18→0.10.20，2026-11-07 实战）**：`derive(...)` 后置语法（`} derive(Traits)` / `struct X(..) derive(Traits)`）由 deprecated 升格为 **error [0027]**，须迁移为前置注解 `#derive(Traits)`（写在类型声明行之前、doc 注释之后）。迁移要点：
- `} derive(T)` 行是**类型体闭合括号与 derive 同行**——机械替换时该行应替换为 `}`，只删 derive 部分，整行删除会把闭合括号一起删掉（解析错误连锁爆 `unexpected token end of file`，报错位置在枚举变体行，误导性强）；
- `#derive` 插入位置 = 最近顶格声明行（`struct/enum/trait/type`）之前；`pub(all) suberror` 声明同样受影响；带尾注释的 derive 行单独手工迁移；
- 本仓 147 处 / 62 文件一次性机械迁移后 `moon test` 1344 全绿——纯语法形态变化，零行为面漂移；
- 警告余额 34 → 63：`unused_value`（0002）/ `method_shadowing`（0050）/ `missing_pattern_arguments`（0021）等 0.10.20 新默认开启，全部提示类（预留 helper / 生成物常量 / 迁移建议），无缺陷信号，未夹带清理。

## 权威源与时效
- `scripts/toolchain_probe/toolchain_probe.mts` 头注（用法与 J9 埋雷记录）
- `moonbit/AGENTS.md` §构建与验证命令
- **相关规程**：`vitro-facts-reconciliation`（升级后刷新真值）、`vitro-release-playbook`（升级与发版的先后关系）
- as_of: 2026-11-07（0.10.18→0.10.20 实战第三轮沉淀：core URL 全形态 / `-C -` 污染坑 / GET-only 探测 / derive 语法升格迁移；2026-10-25 #273 迁移批：facts 命令面切 `node scripts/facts/main.mts`——采集/对账流程不变；具体版本号会过时，流程长期有效）
