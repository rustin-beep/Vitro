---
name: vitro-realcode-diff-workflow
description: Vitro 实机代码对拍审阅与外部 C 仓库勘探的完整工作流——三方对拍(Clang 真值/Vitro/oracle 同病)、已知缺陷指纹归类、剥壳勘探、分层遮蔽实验、批量对比脚本。Use when 用户分发实际 C 代码要求与 Vitro/Clang 对比、开立新缺陷 issue、处理 demo 实测报错、或对外部 C 仓库跑批量勘探。触发词：实际代码、对拍、E 码归类、剥壳、勘探、TheAlgorithms、mismatch。
metadata:
  as_of: 2026-10-01
  演化日志: |
    - 2026-10-01 初版：蒸馏 batch11~22 实机审阅（31 份样本、#11~#21 开立）+ TheAlgorithms/C 全量勘探
      （407 份、67 份全管线 match、#21 遮蔽缺陷）。后续修复批（#3~#21）落地时须连坐更新本文
      「指纹表指向」与「剥壳变换」（缺陷清零后剥壳场景消失）。
---

# Vitro 实机代码对拍工作流

> 定位：单份实机代码三方对拍（教学/实测场景）与外部仓库批量勘探（回归/盲区度量场景）的操作手册。
> 真值数字不进本文——缺陷指纹指向 issue 台账，勘探统计指向当次 report。

## 一、单份代码七步流程

1. **落库**：用户原码逐字保留进 `docs/current/07-质量与裁定/demo实测样本库20261001/batchN-主题/`（禁混探针；平台差异代码带注记）。探针只进 `.shadow_tmp/`（gitignore 域）。
2. **Clang 真值**：`clang -std=c11 -Wall -Wextra -fsyntax-only <f>`。Clang 红 = 先甄别三类：平台差异（POSIX 函数/M_PI/MSVC 头）、代码真错（引号未转义/漏参数/UB）、链接需求（无 main）——**前两类才有对拍意义，双侧都拒=双拒样本不立案**（现有五例：arc/sccp/memmodel/sched/concurrency）。
3. **Vitro 对拍**：**必须走 serve/gateway 协议通道**（带 E 码+W 警告；cmd/run 丢弃警告与码——见 [#16](https://github.com/rustin-beep/Vitro/issues/16)）。JSON-lines：`{"id":N,"method":"compile","params":{"source":"..."}}`。
4. **指纹归类**：先读全部 open issue 建指纹表（现 #3~#21），已知形状 → 评论增补实例（只挂实测命中，parse 短路遮蔽的不挂）；新形状 → 第 5 步。
5. **探针收缩**：最小化触发物（逐行删减/等价替换），每步保留探针于 `.shadow_tmp/`。
6. **oracle 同病判定**：`vitro_cli compile <probe>`（tag rust-oracle-freeze 构建）。同病=两侧同修候选挂退役后；不同病=MoonBit 迁移引入（单独处理）。
7. **立案+连坐**：开 issue（bug/enhancement 标签、NOTE 结论块、最小复现表、根因、红→绿锚）+ 样本库 README 两表连坐 + 相关旧 issue 评论增补。

## 二、剥壳勘探（parse 层遮蔽的解锁手段）

引擎 fail-fast 四级短路（lex→parse→typeck→codegen，前级错后级不跑，见 [#20](https://github.com/rustin-beep/Vitro/issues/20)）。剥壳=机械等价变换模拟"继续编译"：

| 变换 | 写法 | 坑 |
|---|---|---|
| stdbool | `#include <stdbool.h>` → `#define bool int` + `#define true 1` + `#define false 0` | **漏 true/false 则 Clang 侧必红**（引擎内置宏有、Clang 靠头文件） |
| union 内联 body（#7） | 提升为顶层命名 union + 成员改 `union Name x;` | 顶层命名 body 引擎绿（探针已证） |
| fpos_t 等未知类型（#12） | 文件头补 `typedef struct { long long __off; } fpos_t;` | 占位即可，语义不需真 |
| _Static_assert sizeof 自定义类型（#13） | 条件换 `sizeof(int) == 4` | 仅常量上下文缺口 |
| stdarg use-before-include | include 挪到文件头 | 同时消 W1018 变异源 |

剥壳后 serve 复跑 → typeck 层诊断 → 按指纹归类。**剥壳版是探针不入样本库**。

分层修复实验（用户侧）：v0 原版 → v1 修词法 → v2 绕 stdbool → v3…，每层实录冒出的诊断——这是 #20 方案的需求素材。

## 三、工具坑清单（全部实测付费学费）

**serve/引擎侧**：
- serve 起在 `D:\code\Vitro` 根（`moon run --target native moonbit/cmd/serve`）；cmd/run 同。cwd 错了报 `failed to resolve path moonbit/cmd/run`——Bash cwd 持久化，先 `cd` 回根。
- serve 无 base_dir：**本地头文件 include 报 E1021 是方法假阳性**（勘探断言须豁免），非引擎缺陷。
- cmd/run 输出经 **Latin-1 字节通道**：文本还原=`bytes(ord(ch) for ch in text if ord(ch)<256)`；或 vm_diff Go 归一器。
- moon run 的 stdout 混**工具链 Warning 块**（`Warning: [NNNN] ╭─[...] ╰───╯`）——冷缓存必现、增量缓存消失；对比前必须过滤。
- serve.exe 残留进程锁 build（LNK1168）→ `taskkill //F //IM serve.exe`。
- serve 响应按 id 回带；scanner buffer 开 64MB（大 source）。
- head 管道 SIGPIPE 杀进程——输出落文件再 grep。
- 运行对比 skip：交互程序（scanf/getchar/fgets→空 stdin 行为分歧）、网络（client_server）、无 main（链接不出）、rand() 驱动（C 标准不规定算法→数字归一后比）、TRAP 步数护栏（1000 万步，重循环 euler 类）与 calloc 大块（全局区上限 65536，超限返 NULL——C 语义内合法，登记边界）。
- UB 样本（缺 return 等）：Clang 碰巧行为 ≠ 标准行为，**记 UB 差异不立案**（但"缺 return 无警告"可作 enhancement）。

**脚本侧（Go 判定型，纪律 8）**：
- `exec.Command` 的 cmd.Dir 相对路径会与 exe 相对路径叠加解析——tmpDir 一律 `filepath.Abs`。
- MSYS 传 `/d/x` 变 `D:/x`（混斜杠）——路径过滤先 `filepath.ToSlash`。
- flag 包 + fail loud + 零依赖；`@generated` 首行。

## 四、批量勘探（外部仓库）

脚本：`D:\code\C\vitro_clang_diff.go`（仓库外，防协议污染）。流程 P1 walk → P2 Clang 真值 → P3 serve 连发（batch 25）→ P4 剥壳重试 → P5 运行对比（Latin-1 还原+归一）→ P6 report.md+result.json。

- 金样本清单：`D:\code\C\_diff_out\gold_signatures.json`（**只存码/数量/运行判定签名，不存源码文本——GPL 红线**）。用途：修复批后重跑，签名只应向绿迁移。
- 2026-10-01 基线：407 份 → Clang 红 122（无 main 35+平台/真错）→ 双绿 155 → Vitro 红 130；运行 match 57+rand 10；mismatch 23 已定性（#21 遮蔽 1 / UB 1 / 护栏+资源上限 4 / 交互 16 / 方法 1）。
- CI 接线（二期，待拍板）：清单固化进 scripts/ + CI pinned-sha clone 外部仓跑断言（形态同 toolchain_probe）。

## 五、已知缺陷指纹（指向单源，勿在此复制数字）

- issue 台账：#3~#21（#3 const 加宽五码族 / #4 尾逗号 / #5 static 函数名 / #6 long long / #7 union body / #8 诊断质量 / #9 三目 / #11 bool 关键字 / #12 未定义类型名 / #13 sizeof 常量 / #14 va_arg W1018 / #15 enum body / #16 cmd/run 通道 / #17 const struct 指针赋值 / #18 ungetc 臂 / #19 {0} 清零 / #20 分层遮蔽 / #21 参数遮蔽函数）
- 样本库：`docs/current/07-质量与裁定/demo实测样本库20261001/README.md`（批次映射+遮蔽清单+转正清单）
