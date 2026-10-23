# 仓内语料批（corpus/<name>/）—— provenance 与使用说明

> 定位：#25「语料扩充双裁定」的**落地侧**——按「许可分流收纳规则」把无毒（MIT/BSD/Apache/PD）语料收进主仓 `scripts/realcode_diff/corpus/<name>/`，供 `scripts/realcode_diff` 做 Vitro vs Clang vs gcc 三方对拍。
>
> 义务链（#25 §2.2 五步）：①许可三级核验 ②落位 + `README.corpus.md` + `LICENSE.upstream` ③探针态=主仓普通 commit ④**入库即验证不进防线扫描域** ⑤金样本 `gold_<corpus>.json` + `_meta.corpora` 登记 + `-check` 多文件扫描。
>
> **协议红线**：本目录语料**只进对拍勘探，不进防线扫描域**（见下「防线隔离」）。勘探产物（report.md / result.json）不入仓——诊断 message 可引用源码 token；仓内只收测量签名（`gold_<corpus>.json`）。

## 语料批清单

| 批 | 类型 | 文件数 | 许可 | 上游 | 金样本 |
|---|---|---|---|---|---|
| `chibicc/` | 单文件 | 41 `.c` + 5 `.h` | MIT | [RunThem/chibicc-repo](https://github.com/RunThem/chibicc-repo) @ `b9c1f031` | `gold_chibicc.json` |
| `multifile/` | 多文件工程 | 36 工程（74 `.c` + 38 `.h`） | MIT（本仓生成） | 本地 LLM 生成（2026-10-21 三批） | `gold_multifile.json` |

登记单源 = [`corpora.json`](./corpora.json)（`-check` 做语料目录 ↔ 登记表 ↔ 金样本三向对账：漏登记 / 悬空 / 僵尸例任一即红）。

## chibicc 批：为什么是 fork 而非上游

上游 [rui314/chibicc](https://github.com/rui314/chibicc) 最后 push 是 **2020-12-07**（commit `90d1f7f`），此后无维护。本批取其活跃 fork **[RunThem/chibicc-repo](https://github.com/RunThem/chibicc-repo)**（libchibicc 前端库化 + 自举增强，2026-10-21 仍在 push）。

实测增量（`compare` API + 逐文件 sha256 比对）：

- **ahead 171 / behind 0**——上游语料**零删除**；
- 22 个 `test/*.c` 被修改，实测**删除 0 行 / 新增 538 行**（纯新增断言）；
- 新增形状面：`_Alignas` / `aligned` 属性（3+5 处）、语句表达式 void 类型、有符号无符号比较语义、**匿名 union 指定初始化器**（直接命中已知缺口 #249 / 新缺陷 #266）、`_Generic`(15) / VLA(8) / `typeof`(8) / `_Atomic`(6) / `long double`(12)。

**许可三级核验**（#25 §1.1 口径）：

| 级 | 结果 |
|---|---|
| 仓库 SPDX | MIT |
| 嵌套许可文件 | 无（`test/` 下无 LICENSE/COPYING/NOTICE） |
| 文件头 | 41 个 `.c` **无独立版权头**（继承根仓 MIT） |
| 根 LICENSE 全文 | MIT License, Copyright (c) 2019 Rui Ueyama → 落位为 `corpus/chibicc/LICENSE.upstream` |

## multifile 批：防线唯一零覆盖的形态

现 `corpus/` 902 文件**全是单文件**，而多文件工程（`.h` + 实现 `.c` + `main.c`）是真实 C 项目的**唯一组织方式**（#237 记的「多文件工程语料没有任何 driver 支持」——7 个 driver 全部假设单文件独立编译）。

本批 36 份工程此前只存在于 `tmp/`（gitignore 域 ⇒ **会丢**），本次入库并在 `scripts/realcode_diff` 加了**工程模式**：`corpus/<name>/` 下的**子目录视为一个工程**，目录内 `.c` + `.h` 作为**一个** compile 请求的 files 数组一次编译（多 translation unit 一起）。

首跑结果（Clang 22.1.4 / gcc(mingw64) 16.2 双裁判 + Vitro）：**双绿 35/36**，唯一红的 `MF-UNIT` 命中已知缺口 [#221](https://github.com/rustin-beep/Vitro/issues/221)（`__FILE__` / `__LINE__` 预定义宏未支持 ⇒ E3023×46 + E3054×23 级联）。

## 防线隔离（义务链第④步的实证）

`corpus/`（防线域）与 `scripts/realcode_diff/corpus/`（对拍域）**物理隔离**——全部 7 个 driver 的语料扫描根是 `corpus/<suite>/`：

| driver | 扫描根 |
|---|---|
| `clang_direct` | `corpus/{baseline,knr,leetcode,gap,codegen_skeleton,template_generated}` |
| `lexer_diff` / `parser_diff` / `typeck_diff` / `codegen_diff` | 同上（`listCFiles(dir)` 逐文件） |
| `vm_diff` | `--corpus <suite>` |
| `corpus_fuzz` | `corpus/<suite>` 抽样变异 |
| `facts` | `corpus/{baseline,leetcode,cpp,...}` |

实测（2026-10-22 入库后）：防线域计数**未变**（baseline 483 / knr 81 / leetcode 138 / gap 20 / codegen_skeleton 13 / template_generated 82），且 `corpus/` 下**无** `chibicc` / `multifile` 目录 ⇒ 零混入。

## 用法

```bash
# 勘探（Clang 真值 + gcc 分桶 + Vitro 三方）
go run ./scripts/realcode_diff/vitro_clang_diff.go -corpus chibicc -out <目录>

# 工程模式（多文件）
go run ./scripts/realcode_diff/vitro_clang_diff.go -corpus multifile -out <目录>

# 剥壳对照（GNU 语句表达式消解 → 识别被 parse 层洪水遮蔽的深层诊断）
go run ./scripts/realcode_diff/vitro_clang_diff.go -corpus chibicc -out <目录> -probe

# 聚合出金样本（-gold-out 指定产物名；-agg-repo 记语料源名）
go run ./scripts/realcode_diff/vitro_clang_diff.go -aggregate <result.json> \
  -gold-out gold_chibicc.json -agg-repo 'chibicc@RunThem/chibicc-repo'

# 合规闸（CI hygiene）：扫全部 gold_*.json + corpora.json 三向对账
go run ./scripts/realcode_diff/vitro_clang_diff.go -check
```

## 探针态：GNU 语句表达式消解

chibicc 语料 41 份中 28 份用 GNU 语句表达式 `ASSERT(x, ({...}))` 写断言（684 处），Vitro 在 parse 层报 E2005 洪水（**4159** 次）——**深层诊断全被遮蔽**。

`-probe` 模式做**语句上下文改写**（保值语义）：

```
原：ASSERT(8, ({ union { int a; } x; sizeof(x); }));
新：{ union { int a; } x; int __vitro_sx0 = sizeof(x); ASSERT(8, __vitro_sx0); }
```

形态困境（实测）：`({...})` 是**表达式**，C 的块 `{...}` 是**语句**——直接替换在表达式位置非法；逗号表达式形态也不行（不能含声明）。故必须做语句上下文改写。

**等价性实测**（两数字两口径，勿混用——审阅 P3）：全部 28 份消解副本的错误**数量**与原始逐份一致（28/28）；其中 Clang **绿**语料错误**集合**逐字节一致（10/10，路径归一后）；Clang 红的 3 份多出一条次生诊断，根因是**语料自身**的 C 语义歧义（`redefinition of 't'` 等），非消解器引入。

**保守边界**：语句体含 `return`/`break`/`continue`/`goto` 不消解；末条若是声明/复合语句不消解。

**效果**（深层信号从洪水里浮出）：

| 文件 | 原始 errs | 消解后 errs | 浮出的码 |
|---|---|---|---|
| `union.c` | 406 | **8** | E3042×5 · E3080×2 |
| `enum.c` | 247 | **11** | E1005×11 |
| `decl.c` | 186 | **4** | E2005×4 |
| `usualconv.c` | 153 | **2** | E3003×1 · E3004×1 |
| `complit.c` | 138 | **2** | E3043×1 · E3003×1 |
| `cast.c` | 352 | **1** | E2005×1 |

⇒ 由此挖出三个真缺陷（均三臂 js/native/wasm 一致验证）：**E3042**（匿名 union 成员未提升，C11 6.7.2.1p13）→ [#266](https://github.com/rustin-beep/Vitro/issues/266)；**E3080**（多匿名成员空名撞车）→ [#249](https://github.com/rustin-beep/Vitro/issues/249) 复现；**E3043**（复合字面量左值，C99 6.5.2.5p3）→ [#267](https://github.com/rustin-beep/Vitro/issues/267)。

## 探针态改动清单

按 #25 义务链第③步「MIT 代码可直接改」，本批的探针态改动**仅存在于 `-probe` 模式的运行期变换**（不改仓内语料文件）：

| 改动 | 范围 | 说明 |
|---|---|---|
| 语句表达式消解 | 28 份 / 678 处 | `-probe` 模式运行时变换，原始语料文件保持原样 |

**仓内语料文件相对上游的改动 = 0**（chibicc 批逐文件 sha256 与 fork `@b9c1f031` 一致；multifile 批为本仓生成，无上游）。

## 实测指纹（as_of 2026-10-22）

仓 HEAD `c3df8005`（rebase 后基座；首采于 a7202d19）；`serve.exe`(native release) sha256[:12]=`7868299BE478`；工具链 clang 22.1.4 / gcc(mingw64) 16.2.0 / moon 0.1.20261012 / node v25.x。
