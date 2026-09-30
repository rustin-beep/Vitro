# Demo 实测样本库（2026-10-01，issue #3~#9）

> **性质**：demo 前端随机实测的**用户真实 C 代码原样归档**（逐字保留，含全部注释/中文文案/ANSI 转义）——每份都做过三方对拍：Clang 绿（代码合法）/ Vitro 引擎报编译错误 / Rust oracle 同病（存量缺陷、非 MoonBit 迁移引入）。
>
> **纪律**：本目录**暂不入测试体系**——位于语料扫描域（`native/tests/cases/`）之外，不参与 golden / e2e / shadow / facts 防线。**转正条件** = 对应 issue 修复（挂 Rust 退役后 MoonBit 单侧执行批）→ 用例转绿 → 按「vitro-baseline-corpus-workflow」义务链补 golden 转正。
>
> 各 issue 的最小化探针（定位过程中的中间产物）不入本库，留存于 `.shadow_tmp/`（gitignore 域，git 历史可回溯至 commit 3640ce0 的首次归档尝试）；定位证据链见各 issue 正文。
>
> as_of 2026-10-01。

## 缺陷总档（全部两侧同病存量，修复挂 Rust 退役后）

| issue | 缺陷 | 根因位置（MoonBit ↔ Rust） |
|---|---|---|
| #3 | `const char*` ← 数组/字面量全灭（decay 后 qualifier 加宽缺失；visit_call 专用臂/funcs 存根/bytecode 表三轨路由致时红时绿） | `typeck/convert.mbt:130` ↔ `vitro_typeck/convert.rs:112` |
| #4 | 初始化列表尾逗号报 E2003/E2006（C89 合法语法） | `parser/expr.mbt:665` ↔ `vitro_parser/postfix.rs:273` |
| #5 | static 函数名作值误报 E3023（裸名解析漏 static_func_sigs） | `typeck/expr.mbt:172` ↔ `vitro_typeck/var.rs:29` |
| #6 | (unsigned) long long 比较与指针算术全灭（is_comparable/is_int 漏 TK_LongLong） | `typeck/convert.mbt:79/96` ↔ `convert.rs:77/88` |
| #7 | union 内联 body（匿名联合体）E2005（Struct 分支有 LBrace 臂、Union 缺） | `parser/type_.mbt:94 vs 121` ↔ `type_.rs:92/94` |
| #8 | E3036「未定义的函数」不可达，误报 E3023+E3066 双错（诊断码误导） | `typeck/expr.mbt:197`+`call.mbt` ↔ `var.rs:70` |
| #9 | 三目分支不做类型统一（usual arithmetic conversions 全缺，`1 ? 1.5 : 2` 即红；含指针 vs NULL 变体） | `typeck/ops.mbt:177` ↔ `ops.rs:154` |

## 样本 → 命中 issue 映射

| 文件 | 内容 | 命中 issue | 备注 |
|---|---|---|---|
| `batch1-linked-list/main.c` | 学生链表（增删查排序） | #3（4 条 insert 全红，字面量→const char\*） | 首个实测样本 |
| `batch2-rpn/main.c` | 后缀表达式求值器 | #4（tests\[\] 尾逗号，parser 首报）+ #3（const char\* 形参/初始化） | parser 短路 typeck 实例 |
| `batch3-wordfreq/wordfreq_hash.c` | 词频哈希表 + qsort 排序 | #3（perror/数组实参/赋值路径/拼接字面量）+ #5（cmp_desc 作 qsort 实参） | |
| `batch3-wordfreq/wordfreq_file.c` | 词频统计（FILE\* 流版，**无 main 片段**） | #3（find_or_create(buf) 数组实参） | 引擎对拍时需补壳 |
| `batch3-wordfreq/wordfreq_simple.c` | 词频哈希（lookup 带参版） | #3（perror/数组实参） | |
| `batch4-bst-logstat/bst.c` | BST 增删查（三目字符串字面量） | #3（perror）；三目字面量实参已验绿 | |
| `batch4-bst-logstat/logstat.c` | 日志分析器 | #3（LEVELS 全局数组初始化器/perror/strncpy 存根轨/bar 数组实参）+ #5（cmp_count_desc） | |
| `batch5-mandelbrot-malloc-regex/mandelbrot.c` | 曼德博 BMP 生成器 | #3（out 初始化/perror）+ #5（PaletteFn typedef 函数指针 + static 函数名） | |
| `batch5-mandelbrot-malloc-regex/mini_malloc.c` | 迷你 malloc 分配器 | #6（char\* ± uint64_t 地址运算，E3016） | |
| `batch5-mandelbrot-malloc-regex/regex_nfa.c` | Thompson NFA 正则引擎 | #3（perror/test 字面量实参） | |
| `batch6-json-tinyvm/mini_json.c` | JSON 解析器 + 路径查询 | #7（union 内嵌匿名 struct 群，parser 首报） | |
| `batch6-json-tinyvm/tiny_vm.c` | 迷你编译器 + 栈式 VM | #3（expect 字面量实参/sym_find 数组成员实参/static const char\* names\[\]） | 三轨路由各一例 |
| `batch7-sudoku-life/sudoku.c` | 数独 MRV 求解器 | #3（run 多行字面量拼接实参/perror） | |
| `batch7-sudoku-life/life.c` | 康威生命游戏 | #5（signal(SIGINT, on_sig)）+ #8（\_Exit 误报 E3023+E3066）+ #3（color 赋值路径） | **平台注记**：nanosleep 为 POSIX 专属，Windows Clang 下原码本身不编译（非引擎缺陷）；extern SignalHandler signal 自声明与函数指针形参两侧均正常 |
| `batch8-wav-synth/wav_synth.c` | WAV 合成器《小星星》 | #4（taps[]/TWINKLE[] 两处嵌套初始化器尾逗号，parser 首报）+ #3（perror/names[] 初始化器/三目混合臂 E3004） | 去尾逗号后 typeck 层三类全现 |
| `batch9-minigit-raytracer-huffman-nbody/minigit.c` | 迷你 Git（SHA-1 + 对象存储） | #3（mkdir 字面量/H 初始化/unsigned char 与 struct 级 const 加宽变体） | |
| `batch9-minigit-raytracer-huffman-nbody/raytracer.c` | 光线追踪器 | #9（double vs 嵌套三目 int 臂，E3004） | **平台注记**：直接使用 `M_PI`，Windows MSVC math.h 不定义，Windows Clang 下原码本身不编译（非引擎缺陷）；mandelbrot.c 的 `#ifndef M_PI` 写法可解 |
| `batch9-minigit-raytracer-huffman-nbody/huffman.c` | Huffman 压缩/解压 | #3（build_tree 的 const uint32_t\* ← 数组） | |
| `batch9-minigit-raytracer-huffman-nbody/nbody.c` | N 体引力模拟 | #3（compute_accel 的 const Body\* ← 数组/add_body 字面量实参；嵌套三目字面量已验绿）+ #9 | **平台注记**：使用 `M_PI`，Windows Clang 下原码本身不编译（非引擎缺陷） |
| `batch10-coroutine/coroutine_sim.c` | 纯 C 协程调度器（函数指针 + 状态机） | #5（6 个 static step 函数名作 co_create 实参——函数指针注册场景全灭）+ #9（co_self 的 `Coroutine\*` vs `NULL` 三目，指针/NULL 变体）+ #3（name 赋值路径） | 第十批，收敛期样本：全部命中已知缺陷，无新缺陷 |

## 定向探边清单（后续挖缺陷的方向，2026-10-01 收敛判定后设立）

十批实测收敛后，随机真实代码的边际收益归零（新代码只复验 #3/#5/#4）。九批**未摸到的语法角落**明确存在，继续挖缺陷应从随机改为**定向探边**——每个点一个独立小探针，命中率高于整份随机代码：

| 探边点 | 现状推测 | 关联风险 |
|---|---|---|
| 位域（`unsigned x : 3;`） | 语料/实测均零出现 | parser+codegen+sizeof 全链未验 |
| `goto` / 标签 / `switch` 贯穿归因 | goto 零出现；switch 贯穿有偶发覆盖 | 控制流族 |
| 多文件 extern 工程（多翻译单元链接） | 仅单文件；extern 声明仅自声明 libc | S1 export / 链接语义 |
| 嵌套参数化宏 / `#` `##` 拼接深组合 | 预处理器 E2 有防线但组合深度未探 | 宏展开边界 |
| `_Generic` 泛型选择 | 仅 baseline 一例（已知按精确匹配的偏差登记） | 类型统一判定同源风险（#9 同族） |
| 可变参数宏（`__VA_ARGS__`） | 零出现 | 预处理器 |
| `long double` | 子集未声明支持——验证报错形态是否友好 | 支持面边界（对照 #8） |
| `setjmp`/`jmp_buf` | 零出现（POSIX 系，预期不支持） | 支持面边界 + 报错形态 |
| 复合字面量深组合 / VLA 指针形参交互 | compound_literal 单例覆盖浅 | 类型系统 |
| `static` 函数指针表 / 跳转表数组 | batch10 已探及 #5，修复后需复验 | #5 转正回归 |

探边产出纪律：新缺陷按批次流程（Clang 真值 → 引擎复现 → oracle 同病判定 → issue + 样本库追加）；探边探针本身不入本库（同 #3~#9 纪律）。

## 为什么 601 语料 + shadow 对拍 + LeetCode 真题都没有发现？（方法论复盘）

三道防线（引擎语料 E1–E4 / shadow·clang_direct 与 Clang 逐字节对拍 / LeetCode 真题）全部漏掉 #3~#9，**不是防线失职，而是对拍体系的分布外盲区**——每条防线都严格测了「它拿到的输入」，但输入分布本身有结构性缺口：

1. **语料的生成来源决定形状分布**。baseline/LeetCode 语料几乎都是「能跑通的参考实现」——写语料的人（或模型）与引擎共享同一个舒适区：函数接口用 `char*` 不写 `const`、数组初始化器不带尾逗号、union 用命名类型组合、三目两臂同型。#3~#9 的触发形状恰好全部落在舒适区之外。**语料 601 例逐字节一致是真，但它只在它见过的形状上一致。**
2. **对拍验证「行为一致性」，不度量「形状覆盖度」**。Clang 对拍是「同输入必同输出」的必要条件，不是形状覆盖的充分条件——输入没碰到的形状，对拍强度再高也等于没做。防线体系有 known/skip 白名单管理「撞到的差异」（被动登记），但没有「语法特征 × 语料覆盖数」的主动盲区度量。#3 的三轨路由是最典型证据：标准库调用走专用臂/bytecode 表恰好绕开缺陷轨，601 例零触发，而用户自定义 const 接口一碰即中。
3. **真题（LeetCode/OJ）风格趋同**。真题是「竞赛答案代码」：非 const 接口、int 返回、简单类型、无自定义类型族/回调/位域——它对「工程代码形态」（const 接口、typedef 回调、tagged-union、分配器）的覆盖接近零。而缺陷恰恰聚居在工程形态里。
4. **教学引擎特有的错配：用户的代码分布 ≠ 语料的代码分布**。学生抄 POSIX 签名（顺手写 const char\*）、爱尾逗号、爱匿名 union、爱 static 辅助函数——十批实测证明这个分布与语料分布几乎不相交。引擎要服务的是前者的分布；语料全绿只证明引擎对**语料作者的分布**健康。
5. **错误路径无防线**：#8（E3036 不可达）暴露的是诊断输出的 golden 完全空白——全部防线都只喂合法程序，「写错代码时给学生的诊断是否指向正确」没有任何对拍。

**处方**（防复发三件）：
- **形状覆盖度清单**：把 #3~#9 的触发形状做成「语法特征 × 语料命中数」矩阵，零覆盖形状 = 盲区清单，新增防线用例优先打盲区；
- **差异化采样补语料**：语料补充来源引入「真实用户代码风格」（如本库 19 份在修复后转正，即第一批差异化语料）；
- **错误路径 golden**：对典型错误输入建立诊断文本对拍（错误码 + 文案 + 位置），补上 #8 暴露的空白。

## 转正清单（退役批修复后逐 issue 转绿转正）

建议顺序按依赖：#4（parser，解锁 batch2/batch8 的 typeck 层）→ #3（typeck 主档，解锁面最大）→ #5 → #6 → #7 → #9 → #8（诊断码，期望诊断随修复改写）。一份样本命中多个 issue 时（如 batch2/batch8），按覆盖它的**最后一个** issue 修复后转绿再转正。
