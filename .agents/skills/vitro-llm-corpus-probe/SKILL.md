---
name: vitro-llm-corpus-probe
description: 用本地 LLM 批量生成 C 语料并四裁判对拍，从产物里挖编译器缺陷、定性、最小复现、开 issue 的完整规程（生成→判据→分桶→二分→登记）。**不写入库语料**（入库走 vitro-baseline-corpus-workflow）。Use when generating C corpora with local LLMs, judging them against clang/gcc/vitro dual-arm, finding 误收/误拒, or setting up batch generation tasks on Windows. 触发词：LLM 语料、探针、误收、误拒、四裁判、双端对拍、批量生成、分桶、最小复现、判据冻结、计划任务跑生成。
---

# LLM 语料探针规程

**适用场景**：用本地 LLM 批量产出 C 源码，拿 **clang / gcc / vitro(wasm) / vitro(native)** 四个裁判对拍，从桶分布里挖缺陷并定性、最小复现、登记 issue。

**与 `vitro-baseline-corpus-workflow` 的分工（不要混）**：
| | 本规程（探针路） | baseline-corpus-workflow（入库路） |
|---|---|---|
| 产物 | `tmp/` 下的临时语料 + 结果 JSON | `corpus/` 下的用例 |
| 收尾 | 最小复现 → **开 issue 登记缺陷** | golden + 直拍 + facts 连坐 |
| 判据 | 四裁判**对拍找分歧** | clang 真值 + 防线**判红绿** |
| 定性 | **必须过"定型三问"**（见 references/03） | 无需，用例即事实 |

**同一条铁律（两路共用）**：**双端强制**（wasm + native 各跑一次、一致才可采信，单臂只作线索）——AGENTS.md #14。

## 流水线四段

```
⓪ 摸底   先抽库面真源 → 提示词只落在真实支持的函数面上（长程序尤其必须，见 references/02）
① 生成   本地 LLM（llama-server / Vulkan）→ <PID>_s<N>.c + raw 原文
② 判据   clang / gcc / vitro-wasm / vitro-native —— 见"判据六铁律"
③ 分桶   五桶分类 → 非 no_signal 的逐条走"定型三问" → 最小复现 → issue
```

**断点续跑是刚需**：生成很贵（每例数秒 + 模型换载分钟级），脚本必须能
「已有源码 ⇒ **只重判不重生成**」，且**判据换了整批自动重判**（见"判据冻结"）。

## 判据八铁律（全部是实锤踩出来的）

1. **fail loud，禁止静默降级**
   裁判**启动失败**（rc=-1 / 空 stdout）**绝不能**当成 `REJECT`。未知一律记 `JUDGE_ERROR` 并把 rc / stdout 长度 / stderr 片段带进标签。**否则产出一整批假结果**，而假结果会被当成真发现。
2. **`subprocess` 一律 bytes 模式，禁用 `text=True`**
   ★ 计划任务环境里 `subprocess.run(..., text=True)` **会把 stdout 读成空串**（同一调用去掉 `text=True` 立刻拿到完整帧）。
   这正是 skill 04 C13 条预警的"text=True 依赖 UTF-8 环境变量、**会话外必崩**"。
   **修法**：`capture_output=True`（bytes）+ 自己 `.decode("utf-8", errors="replace")`。
3. **Windows 上 Python 找 exe 用「当前进程 PATH」，不是传入 `env` 的 PATH**
   ⇒ `clang` / `gcc` / `node` / 被测 exe **一律写绝对路径**；`env` 的 PATH 只用于让被调用的壳去找 `node`。
4. **退出码语义先查清再用**
   `vitro` 的 rc 是**编译结果**（0 通过 / 1 有错误 / 3 壳降级），**不是"启动成功与否"**。
   ⇒ 判据必须**无条件解析 stdout 的 JSON 帧**，看帧里有没有 `ok`。
5. **帧有两个 ok，两层都要认**
   ```json
   {"type":"diag","frame":{"id":3,"ok":<命令成功>,"result":{"ok":<编译结果>,"diagnostics":[...]}}}
   ```
   解析要认 **`frame.result.ok`**（含 diagnostics）与 **`frame.ok` / 顶层 `ok`**（无 result 包装）三种形状——只认一种会把另一批误判成 `JUDGE_ERROR`。
6. **clang golden 必须 `-O0`，禁用 `-O2`**
   ★ 2026-10-18 实锤：`-O2` 常量折叠走 **MPFR 精确中间值**（`x*x-2.0` 折叠得 `2.73432e-16`），
   运行时 SSE2 与 vitre 一致得 `4.44089e-16` ⇒ **`-O2` 制造的假 `run_mismatch` 以方向级规模出现**
   （BIN 方向 6/8 RUNDIF 中 5 条，-O0 重判全 MATCH）。vitro 是解释执行，golden 必须同样是运行时计算。
7. **运行轨三噪声，比对前先归一**（2026-10-17/18 两批实锤）
   ① **地址行**：模型爱打印 `%p` / 指针强转整数，跨实现地址必然不同 ⇒ 两侧 `0x…` / `0000…` 样式统一掩码为 `<ADDR>`，提示词也要显式禁打印地址；
   ② **非 ASCII 输出**：`output.delta` 逐字节 Latin-1 折回是**已知通道行为**（#112）⇒ clang golden 侧 stdout 必须同样按 `latin-1` decode，两侧同空间才可比（否则任何含中文的程序必判 RUNDIF）；
   ③ **CRLF**：Windows clang 输出 CRLF，norm 时 rstrip。
8. **会话外运行必须自己把 traceback 写进日志**
   计划任务**丢弃 stderr** ⇒ 未捕获异常的唯一表现是「**日志停在半路 + 任务结果码 1 + 无任何报错文本**」。
   ⇒ 每个编排脚本末尾必须有顶层 `try/except` + `traceback` **逐行 `log()`**；**别指望 stderr，它不会到你这儿**。
   同理：**数据与模板路径必须先离线跑通**（把全部提示词 `.format()` 跑一遍）再花模型时间——否则一个 `KeyError` 就白等一整轮（实锤：模板键写成 `template` 而脚本要 `template_p`，两次启动都死在这行且日志全无）。

## 判据冻结（否则结果不可解释）

**问题实锤**：跑判据的过程中，工作区里的被测 exe 被**另一会话重建**（`vitro.exe` mtime 变了），判据基线漂移 ⇒ 结果无法解释。

**规程**：判据**不用工作区里那个**，而是**复制一份自足快照**：

```
<judge_dir>/
  vitro.exe                                                        ← native 臂（导入仅系统 DLL，自足，任意 cwd 可跑）
  moonbit/_build/js/release/build/cmd/vitro_wasm/vitro_wasm.js      ← wasm 壳（main.js 退役批后为 MoonBit 胶水）
  moonbit/_build/wasm-gc/release/build/gateway/wasm/wasm.wasm      ← gateway wasm-gc 引擎（壳经编译期注入 URL 定位）
  judge_fingerprint.json    ← 各产物 sha256 + repo_head + dirty 计数
```

- 每条结果写 **`judge_id`**（`vitro.exe` sha256 前 12 位）；**`judge_id` 变了整批重判**。
- 换基线 = 换快照目录（`_judge_v2/`…），**不要就地覆盖**，否则历史结果失去归属。

## 提示词设计四条

1. **口径写 C23**：本仓锚定 **ISO C23**（`__STDC_VERSION__ = 202311L`，真源 `结构重构与C23锚定决议.md` §2「C23 锚定决议（替代 C99）」），属「**C23 教学子集**」。写 "C99" 会让模型绕开真正的考察面。
2. **显式排除文档化不支持面**：`bitfield` / `restrict` / `_Static_assert` / `_Alignas` / `_Complex` / 自定义变参 —— 撞上只会产出"暂不支持该特性"噪音，**不是缺陷**。
3. **P:N ≈ 4:1，且必须含"回归锚"**：已闭环的旧缺口形状留在提示词里当**红→绿回归锚**；方向族按 `C语言子集规范.md` 的形状族铺开。
4. **体量**：短例（十几行）只能撞到**单一**形状；**200~300 行的真实规模程序会把「难自然触发的形状」变成「必然触发」**。
   实锤：`E3047`（枚举常量当 `case` 标签）在短例里只 1 条，长程序里**一条就撞 6~8 次**——因为状态机/虚拟机天然拿 `enum` 当 `case`；
   `const` **数组元素**赋值不被拦（新误收根）也是**只有长程序才写得出来**。
   ⇒ **找新形状优先上长程序**；短例用来做「方向广度 + 跨模型对照」。体量细节见 `references/02`。

> **写提示词前的第 0 步是「库面摸底」**（抽 `scripts/moonbit/libc_src/include/` 的真实函数面）——长程序尤其必须，否则产出全是「未声明标识符」噪音。表与抽法见 `references/02` ⓪ 节。

## 分桶五类

| 桶 | 含义 | 严重度 |
|---|---|---|
| `vitro_accept_clang_reject` | **误收**——非法程序被接受 | 最高 |
| `arm_divergence` | wasm ≠ native | **最高（独立桶）** |
| `crash` / `judge_error` | 崩 / 判据本身失败 | 高（judge_error 是**自身故障**，先修自己） |
| `vitro_reject_clang_accept` | **误拒**——合法 C 被拒 | 高 |
| `diag_mismatch` / `no_signal` | 诊断级别错 / 四方一致 | 低 / 无 |

## issue 的两条硬要求（2026-10-13 实锤）

1. **正文必须同时含「最小复现」与「触发文件全文」** —— 只给手缩的最小复现，是把**证据降级成示意**。
   最小复现给人看**形状**，全文给人**复现与判定**。全文取探针实际产出（`gen50/<model>/<PID>_s<N>.c`），**不要凭记忆重写**（重写会漏掉真正触发的那一维）。
2. **重要信息补进原 issue 正文，不新开评论** —— 仓库惯例：正文可迭代、保时间线。补完必须校验 **`new.startswith(orig)`**（原文未被覆盖）与**追加生效**。

## 定型三问（非 no_signal 的条**必须逐条过**，否则会把设计当缺陷）

1. **是文档化边界吗？** 查 `docs/current/03-语言子集/C语言子集规范.md` §3.1 排除清单 与差异清单。
   **实锤反例**：文件作用域指定初始化器 → `E0`。它**不是"误拒合法 C"**，规范 §828 明写"全局/静态变量 designated init **暂不支持**"。**可修的只是"报了 `E0` 无分类码"**（同为不支持的 bitfield/restrict 都报"暂不支持该特性"，口径不一致）。
2. **是保留名冲突吗？** 查 `moonbit/typeck/builtin.mbt` 的内置名表。
   **实锤反例**：`print_int` 是**保留内置名**（`"print_int" | "__vitro_output" | "__vitro_step"` → `check_builtin_print_int`，单 `int` 参）。用户定义 `void print_int(int *p)` 时调用点按内置签名放行 ⇒ `print_int(42)` 的 `int→int*` 零诊断通过。**定性是"保留名冲突致静默放行"，不是"误收非法程序"**。
3. **基线是否已变？** 先 `git rev-parse HEAD` + `git log -1`，再 `git log -- <相关路径>` 找有没有"已修"提交。
   **实锤反例**：某批 5 条缺口在**上一轮之后已被提交闭环**（提交标题就写着「#76 两缺口」），我却按旧基线解读了一整轮。

**三问都过不了才登记为缺陷**，并附最小复现（见 references/04）。

## 相关规程

- `vitro-baseline-corpus-workflow` —— 探针挖出的缺陷**修完并加用例**后走它入库
- `vitro-workspace-review` —— 被测代码本身的审阅
- **剥壳勘探**（首层错把更深层挡住时）：工具 `assets/peel_shell.py`，规则见 `vitro-realcode-diff-workflow` §二；量化口径见 issue #20 评论
- `vitro-facts-reconciliation` —— 若结果要进 `reports/facts.json` 的判读

## 本 skill 的 references 与资产

| 文件 | 内容 |
|---|---|
| `references/01-环境与调用面.md` | 计划任务最小正确姿势、从 Bash 调 PowerShell 的坑、直调两臂 vs 走壳、`subprocess` 三坑、llama-server 起停 |
| `references/02-提示词与工作点.md` | 关思考两开关（`enable_thinking` vs `reasoning_effort`）、参数表、模板、C23 口径、方向族、回归锚 |
| `references/03-分桶与定型.md` | 分桶实现 + **定型三问** + 三条实锤反例（文件作用域指定初始化 / `int→pointer` / `print_int` 保留名）+ 误拒稳定族 |
| `references/04-最小复现与二分法.md` | 二分流程、两点验证、`print_int` 二分实例、反模式 |
| `references/05-踩坑清单.md` | P1~P22 症状 → 根因 → 修法（按"会静默产生假结果"排序；P14 0x85 吞输出、P15 GNU 扩展假误拒、P16 变体矩阵、P17 存储期×容器矩阵、P18 brace elision 与 `'\"'`、P19 N 组产出率下降该换靶、P20 四类固定答案、P21 golden 被模型弄脏、P22 二维数组形参 char/int 差异） |
| `assets/gen_corpus_template.py` | 生成 + 四裁判 + 分桶 + 续跑 + 判据冻结的**可直接改用的模板**（五铁律内嵌为注释） |
| `assets/freeze_judge.ps1` | 一键冻判据快照（含自足目录布局与指纹记录） |
| `assets/peel_shell.py` | **剥壳探测器**（§二 的工具）——常量标识符→字面量的机械等价变换 + 复跑。**内置「变换计数为 0 即 NO_TRANSFORM」断言**，防把「没变换」误读成「没有下一层」 |

as_of: 2026-10-19（96 例×9 批实跑蒸馏；判据八铁律——新增 #6 clang golden -O0、#7 运行轨三噪声；判据快照 `_judge_v2` `vitro.exe` sha256[:12]=`aea78efe7c69`；已挂 issue #142-#147/#149-#152、#171-#175、#179-#182、#192-#195；#172 定案——判据第 9 条改写为「NDJSON 禁 splitlines」）

**2026-10-18 第六批补充（判据九铁律候选，待下批固化）**

9. **输出全空先查 `0x85`**：`run=finished` 但 stdout 0 字节 ⇒ 先数源码/输出里的 `0x85` 字节（P14），
   命中即判 #172 同族，**不要**写成「中文输出缺陷」。部分截断（非全空）才是另一案。
10. **`vitro_reject_clang_accept` 先看诊断消息**：若 vitro 拒的是「C 标准禁止、clang/gcc 用 GNU 扩展放行」
   的构造（VLA 初始化、零长数组等），**不计缺陷**（P15）。

**2026-10-19 #172 定案改写（第 9 条根因收编——引擎无罪，探针碎帧）**

9.（改写）**NDJSON 消费只按 `\n` 分行，禁用 `splitlines()`**：引擎 stdout 帧的 `delta` 对
   ≥0x20 字节裸放不转义（RFC 8259 合法），其中 `0x85` 字节经 Latin-1 折回即 U+0085——
   Python `splitlines()` 把它当 Unicode 行界**拆碎帧行** → `json.loads` 失败 → 判据表观
   「stdout 整段消失 + run finished」（#172 全案即此：`putchar(0x85)` 引擎双臂输出字节
   与 clang 逐位一致，`split('\n')` 路径 stdout 帧完好）。自洽面：`0x0b`/`0x0c` 因 <0x20
   被 json_escape 强制转义不触发；UTF-8 序列 `E2 80 A8`（U+2028）折回后是三字符
   不含 U+2028 本身也不触发——**唯一命中 = 原始输出字节含 85**。第 9 条旧文的
   「先数 0x85」判法保留（作为碎帧症状的快速识别），但处置改为**修判据脚本**
   （`split('\n')`），不再当引擎缺陷立案。assets 两处（peel_shell.py / gen_corpus_template.py
   的 parse_vitro/judge）已随批改净；今后新判据脚本一律 `split("\n")`。
