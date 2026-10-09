# Demo 实测样本库（2026-10-01，issue #3~#9）

> **性质**：demo 前端随机实测的**用户真实 C 代码原样归档**（逐字保留，含全部注释/中文文案/ANSI 转义）——每份都做过三方对拍：Clang 绿（代码合法）/ Vitro 引擎报编译错误 / Rust oracle 同病（存量缺陷、非 MoonBit 迁移引入）。
>
> **纪律**：本目录**暂不入测试体系**——位于语料扫描域（`corpus/`，原 `native/tests/cases/` 已随 2026-10-05 删区迁入）之外，不参与 golden / e2e / facts 防线。**转正条件** = 对应 issue 修复 → 用例转绿 → 按「vitro-baseline-corpus-workflow」义务链补 golden 转正。
>
> **状态回灌（2026-10-07）**：三方对拍中的 Rust oracle 臂已随删区退役（对拍叙事为 2026-10-01 时点事实）；**对应缺陷 #3~#9 已全部随 S9 修复批销案关闭**（批一~批三，2026-10-05~06）——转正条件中的「issue 修复」已满足，转正动作（补 clang golden + 进 corpus + 双防线接入）待语料批按义务链逐份执行，本库原样归档留作勘探史与对拍证据。
>
> 各 issue 的最小化探针（定位过程中的中间产物）不入本库，留存于 `.shadow_tmp/`（gitignore 域，git 历史可回溯至 commit 3640ce0 的首次归档尝试）；定位证据链见各 issue 正文。
>
> as_of 2026-10-01。

> **口径注（2026-10-02 勘误，对应提交 6aa0718）**：该提交信息中「19 份用户真实 C 代码」未注明口径——本批实测新增 **25 个 .c 文件** = 新增原码 19 份 + 双拒错误路径样本 5 份（arc/sccp/memmodel/sched/concurrency，代码自身真错两侧均正确拒绝）+ 修复副本 1 份（sccp_e1001fixed，与原版同库成对）。历史叙述中另有「十批 19 份」（1fe0e5f）与「batch11~22 累计 31 份」两个口径并存；**引用本库规模一律以下方「样本 → 命中 issue 映射」表逐行点数为准**，勿沿用提交信息或叙述句中的整数。

## 缺陷总档（两侧同病存量——**2026-10-07 起 #3~#9 已随修复批全部销案**，转正待义务链执行）

| issue | 缺陷 | 根因位置（MoonBit ↔ Rust） |
|---|---|---|
| #3 | `const char*` ← 数组/字面量全灭（decay 后 qualifier 加宽缺失；visit_call 专用臂/funcs 存根/bytecode 表三轨路由致时红时绿） | `typeck/convert.mbt:130` ↔ `vitro_typeck/convert.rs:112` |
| #4 | 初始化列表尾逗号报 E2003/E2006（C89 合法语法） | `parser/expr.mbt:665` ↔ `vitro_parser/postfix.rs:273` |
| #5 | static 函数名作值误报 E3023（裸名解析漏 static_func_sigs） | `typeck/expr.mbt:172` ↔ `vitro_typeck/var.rs:29` |
| #6 | (unsigned) long long 比较与指针算术全灭（is_comparable/is_int 漏 TK_LongLong） | `typeck/convert.mbt:79/96` ↔ `convert.rs:77/88` |
| #7 | union 内联 body（匿名联合体）E2005（Struct 分支有 LBrace 臂、Union 缺） | `parser/type_.mbt:94 vs 121` ↔ `type_.rs:92/94` |
| #8 | E3036「未定义的函数」不可达，误报 E3023+E3066 双错（诊断码误导） | `typeck/expr.mbt:197`+`call.mbt` ↔ `var.rs:70` |
| #9 | 三目分支不做类型统一（usual arithmetic conversions 全缺，`1 ? 1.5 : 2` 即红；含指针 vs NULL 变体） | `typeck/ops.mbt:177` ↔ `ops.rs:154` |
| #11 | `bool` 被注册为关键字（C++ 片预埋未按语言模式隔离）致 stdbool.h 存根 `typedef int bool;` 自爆——include 即 parse 全灭 | `lexer/scanner/keyword.mbt:38` ↔ `vitro_lexer/keyword.rs:67` |
| #12 | 未定义类型名作声明报「预期 ';'」+ 误导建议（Clang 报 use of undeclared identifier 直指真因；诊断码与文案误导） | parser 声明识别回落表达式语句通道 ↔ `vitro_parser` 同构回落 |
| #13 | `_Static_assert` 条件含 `sizeof(struct/union/数组)` 被误判非编译期常量（E1006；sizeof(内置 typedef) 却绿——常量求值 sizeof 只覆盖内置类型） | `typeck` 常量求值 sizeof 臂 ↔ `vitro_typeck` 同构 |
| #14 | 合法 `#include <stdarg.h>` 必触发 W1018「va_arg 重复定义且宏体不同」假警告（va_arg 双源：lexer 内置宏表 ↔ stdarg.h 存根文本漂移——W1018 实为机制性漂移探针；警告行号渲染 -1） | `pp/builtins.mbt:73` ↔ `stubs_gen.mbt` 双源漂移 ↔ `macros.rs`/`include/stdarg.h` 同构 |
| #15 | 匿名 enum 内联 body 两形状全灭：顶层 `enum{...} var` 报「enum 声明后预期 ';'」、成员位置 `struct S{enum{...} k;}` 报「预期标识符名称」（纯匿名声明/typedef enum/命名 tag 正常；#7 同族 enum 版） | `parser/type_.mbt` enum 分支顶层 declarator 连接 + 成员 LBrace 臂缺失 ↔ `type_.rs` 同构 |

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
| `batch11-plotter/plotter.c` | 数学表达式解析 + 终端绘图（递归下降 + union tagged AST + stdarg 日志，664 行） | **#11（stdbool.h 存根自爆，28:13 首报——收敛判定后首条新缺陷）**+ #7（Node 的 union u 内联 body，171:11 级联）+ **#14（W1018 va_arg 假警告，24:0）** | 第十一批；vfprintf/NAN/isnan/isfinite/cbrt/log2（#10 stdio v 族与 math 缺口→#8 形状）与 `static const char \*names[]`/`funcs[]` 初始化器（#3 形状）被 parse 短路遮蔽，修复后需复验 |
| `batch12-probe-gc-logstat/probe.c` | C 类型/浮点/位模式探测工具（limits/float/stdint/stddef/errno/stdarg/math 特殊函数/time 全家桶定向覆盖） | #11（stdbool，30:13）+ #7（union 内联 body 位双关 ×3，108:11 起 171 条级联）+ **#14（W1018 va_arg 假警告，26:0）** | 第十二批；INT8_MIN 族/INT64_C/offsetof/tgamma/lgamma/erf/erfc/expm1/log1p/nextafter/scalbn/frexp/ldexp（#10 缺口）、va_copy、gmtime/asctime/ctime/strftime、`%zu/%lld/%llu/%td/%p` 运行时格式支持全被 parse 短路 |
| `batch12-probe-gc-logstat/gc.c` | 标记-清除垃圾回收器演示（McCarthy 1960 算法，mark/sweep/free-list） | #11（stdbool，20:13）+ #7（union 内联嵌套匿名 struct，38:11） | `(next >= 0) ? &g_heap[next] : NULL`（#9 指针/NULL 变体）与 bool 标记位语义被 parse 短路 |
| `batch12-probe-gc-logstat/logstat.c` | 日志分析器 + 环境工具（strtok_r/strftime/localtime/setvbuf/tmpfile/getenv/system 等定向覆盖） | #11（stdbool，20:13）+ **#12（fpos_t 未定义类型名报「预期 ';'」，268:5）**+ **#14（W1018 va_arg 假警告，17:0）** | **平台注记**：strtok_r（POSIX 专属）+ M_PI（MSVC math.h 不定义）——Windows Clang 下原码本身不编译（非引擎缺陷，同 batch7/batch9 先例）；vfprintf/localtime/mktime/strftime/difftime/setvbuf/fgetpos/fsetpos/tmpfile/getenv/system/labs（#10 缺口）与 struct tm 引用被 parse 短路 |
| `batch13-arc-fs/arc.c` | ARC（自适应替换缓存）vs LRU 命中率对比（双向链表 + 桶哈希 + 幽灵列表，5 万次访问 × 4 场景） | **错误路径对拍样本（样本库首例双拒）**：代码自身 412 行字符串引号未转义（`"记住"` 裸标识符）属真实语法错误——Clang parse 层拒（expected ')'）、引擎词法层拒（无法识别的字符 '记'），**两侧均正确拒绝、非引擎缺陷** | 第十三批；诊断形态差异（引擎 412:35 vs Clang 412:44）不立案；**分层修复实验**（2026-10-01 补）：v1 修引号→#11 stdbool 三连冒出、v2 再绕 stdbool→#3 E3038×4（run_compare 字面量实参，oracle 同病）——修复后无新缺陷；早先备注误将 gc.c 的 `&g_heap[next] : NULL` 三目记为本文件，特此更正 |
| `batch13-arc-fs/fs.c` | 玩具文件系统（超级块/位图/inode 表/硬链接/目录树，512B×1024 块） | **#13（_Static_assert(sizeof(Inode)) 判非编译期常量，64:54/65:60）**+ #11（stdbool，24:13） | `INODES_PER_BLK` 宏含 sizeof(Inode) 但仅运行时上下文展开未触发——缺口限定常量上下文；`ip->size < len ? ip->size : len`（uint16 vs int 三目，#9 变体）被 parse 短路 |
| `batch14-hm/hm.c` | Hindley-Milner 类型推断（算法 W：合一/泛化/实例化/occurs check，let 多态演示） | **#15（匿名 enum 内联 body 两处成员形状，38:10/278:10——用户报「E2005 好几个形状」的另一半）**+ #11（stdbool，20:13） | 第十四批；p_enum 探针收出两个子形状（顶层 body+声明器 / 成员内联 body）与三个绿区（纯匿名/typedef/命名 tag）；E2005 同文件两形状并存=#11 与 #15 各自的三连/级联 |
| `batch15-sccp/sccp.c` | SSA + 稀疏条件常量传播（SCCP：格 / phi 可达前驱 / 常量分支删边） | **错误路径对拍样本（第二例双拒）**：531/552 行字符串引号未转义（"不动点"/"更坏"）属真实语法错误——Clang parse 层拒（2×expected ')'）、引擎/oracle 词法层拒（5×E1001 每字符一条），**两侧均正确拒绝、非引擎缺陷** | 第十五批；E1001（无法识别的字符）全库分布=arc.c+sccp.c 两例、根因同为引号未转义裸中文；parse 前 530 行全过（纯匿名 `enum {…};` 与 #15 成员形状的边界实证） |
| `batch15-sccp/sccp_e1001fixed.c` | 同上样本的 E1001 修复版（引号改全角，用户分层修复实验第一份） | **#3 33 条**：E3014×7（**return 语句=第六条消费路径，新码**——`op_sym` 的 `return "+";`）+ E3038×26（实参路径） | oracle 33 条逐字同病、Clang 全角引号后全绿；同根因六条路径各用不同码（E3004/E3006/E3014/E3038）——修复需六处连通验证；#3 评论已增补 |
| `batch16-wam/wam.c` | Warren Abstract Machine 迷你实现（Prolog append/3 编译 + 堆/环境帧/选择点/trail 回溯执行） | **#3 单根因 10 条命中（单文件密度最高纪录）**：E3006 数组初始化器（61:45 `consts[] = {"[]"}`，g3 同款）+ E3038 函数实参 ×9（字面量 ×7 + `make_int_list` 的 `const int\*` ← `int[]` ×2——非 char 家族再实锤） | 第十六批；oracle 10 条同码同位置、Clang 全绿；复合字面量 `(Cell){TAG_CON, I.a}`、匿名 struct 变量 `static struct {...} functors[]`、纯匿名 enum 全部 parse/typeck 通过（绿区扩展）；#3 评论已增补 |
| `batch17-memmodel/memmodel.c` | 内存模型与 happens-before 分析（HB 5 规则/Warshall 闭包/数据竞争检测/SC-TSO-宽松对比） | **错误路径对拍样本（第三例双拒）**：355/360 行 `"可见性"`/`"我要哪条 HB 规则"` 引号未转义——Clang 2×expected ')'、引擎/oracle 9×E1001，两侧均正确拒绝 | 第十七批；**用户分层修复实验实证引擎 fail-fast 遮蔽链**：v0 仅 E1001×9 → v1 修 E1001 后 #11 stdbool 三连冒出 → v2 再绕 stdbool 后 #3 的 E3038×29 冒出（buf 数组实参×6+字面量×23）——层层暴露的全是已知缺陷，非新 bug；#3 评论已增补 |
| `batch18-spill2/spill2.c` | 寄存器分配第二轮：溢出代码生成（活跃区间/线性扫描/LOAD-STORE 展开/二轮再分配） | **#11（stdbool，17:13）+ #4（尾逗号注释掩护变体：`"t5", /* 其余默认 NULL */`，95:1）**；v1 剥层后 #3×13（E3006 逐元素×10+E3014 return buf+E3038×2）+ **#5×1（qsort 比较器 cmp_iv，202:40）** | 第十八批；p_comment 探针边界：`{1, 2 /* c */}`（无逗号）绿、`{1, 2, /* c */}`（尾逗号）红——词法注释即空白，与 #4 同构；**E3006 同语句逐元素报 10 条无去重**（对照 W3053 有去重——诊断形态观察随 #3 修复批）；编译器教材代码自举场景（qsort 比较器高频再确认）；#3/#5 评论已增补 |
| `batch19-sched/sched.c` | 指令调度：填充延迟槽（依赖图/关键路径优先级/列表调度/时间轴可视化） | **错误路径对拍样本（第四例双拒）**：va_start/va_end 用在 `#include <stdarg.h>` 之前（emit 函数在 96 行 include 前使用，作者笔误）——Clang 拒 2 errors（77/88 行 undeclared va_start/va_end）、引擎拒 E2005×4+W1018；**另 #11（stdbool，21:13）+ #14（W1018 va_arg，89:0）**；v1 剥层（挪正 include+绕 stdbool）后 **#3×15（E3014×7 op_name return 全家 + E3038×8）+ vsnprintf E3023+E3066** | 第十九批；**里程碑：#10 缺口函数（vsnprintf）首次真实命中**（前 18 批全被 parse 短路）——报错形态=#8 双错级联，联动实证；存根交叉观察=引擎 stdio.h 无 va_list（Clang/MSVC 头间接提供）+ 内置宏 va_start 无需 include 即可用（与 Clang 相反），已挂 #10/#14 评论 |
| **剥壳勘探汇总（2026-10-01，探针域不入库）** | plotter/probe/gc/logstat/fs 五份 parse 层样本机械去壳（stdbool→宏、union body 提升为顶层命名、fpos\_t 占位、\_Static\_assert 换内置）后到达 typeck 层 | **产出 [#17](https://github.com/rustin-beep/Vitro/issues/17)（E3044 形参 struct 解引用赋值同名双红，logstat 78:20 首报）+ [#18](https://github.com/rustin-beep/Vitro/issues/18)（E3029 ungetc 第 2 参被当 int 检查）**；**E3036 可达性修正**（labs 报出 E3036——#8「永不可达」收敛为「builtin\_all 放行且无签名时可达」）；#10 缺口函数批量真实命中（E3023×30+E3066×27=#8 形状）+ E3042×7（struct tm 成员）；E3032/E3062 实证 printf 专用臂有格式校验（修正三轨「只查个数」表述） | probe\_sh 变换自身有误（union 前置时 uint32\_t 未定义）留待重做；gc 6 条/fs 58 条/plotter 91 条/logstat 97 条全部收敛已知 issue；剥壳探针存 .shadow\_tmp/\*\_sh.c |
| `batch20-gmp-btree-db-cpu-sims/gmp.c` | Go 调度器 GMP 模型（M/P 绑定、工作窃取、阻塞让出 P、环形队列） | #11（stdbool）挡路；剥壳后 **#3×6**（E3014×5 state_color return + E3038×1） | 第二十批；Clang 绿 |
| `batch20-gmp-btree-db-cpu-sims/btree.c` | B 树全操作（插入/分裂/删除/借位合并/前驱后继/树形打印） | #11 挡路；剥壳后 **#3×9**（E3038 section 字面量实参） | Clang 绿；`g_root ? "否" : "是"` 三目字面量同长已验绿 |
| `batch20-gmp-btree-db-cpu-sims/concurrency.c` | 2PL 与 MVCC 并发控制对比（等待图死锁检测/版本链/快照隔离） | **错误路径对拍样本（第五例双拒）**：va_start/va_end use-before-include（106 行 include 在 twopl_log 后，同 sched 笔误）——Clang 拒 2 errors；剥壳（含 stdarg 挪头）后 #3×1 + vsnprintf E3023+E3066（#10）+ W1018（#14） | Clang 真错 + 引擎额外报 va_list（stdio 存根无，#12 形状同 sched） |
| `batch20-gmp-btree-db-cpu-sims/raft.c` | Raft 共识（选举/日志复制/commitIndex 推进/leader 崩溃恢复） | #11 挡路；剥壳后 **#3×9**（E3014×4 role_name + E3038×5） | Clang 绿 |
| `batch20-gmp-btree-db-cpu-sims/aries.c` | ARIES 数据库恢复（WAL/Analysis/Redo 幂等/Undo CLR） | #11 挡路；剥壳后 **#3×12**（E3014×7 log_type_name + **E3044×3 赋值表达式新码**）+ E3004×1 | Clang 绿；`g_mem[i] = g_disk[i]` 全局数组 struct 赋值已验绿（#17 局限性旁证） |
| `batch20-gmp-btree-db-cpu-sims/tomasulo.c` | Tomasulo 乱序执行（保留站/寄存器重命名/CDB 广播） | #11 挡路 + **#14（stdarg 在文件头仍触发 W1018——include 位置无关实锤）**；剥壳后 **#3×14**（E3014×6 + **E3044×3** + E3038×8）+ vsnprintf E3023+E3066（#10） | Clang 绿 |
| `batch20-gmp-btree-db-cpu-sims/vliw.c` | VLIW 综合调度器（多发射/循环展开/压力感知/VLIW 打包） | #11 挡路 + #14；剥壳后 **#3×16**（E3014×6 + E3006×4 + E3044? + E3038×6）+ vsnprintf（#10） | Clang 绿；#3 五码分布（E3038/E3004/E3006/E3014/E3044）在本批集齐 |
| `batch21-dht-crdt-vclock-paxos/dht.c` | Kademlia DHT（XOR 距离/k-bucket/迭代查找/PUT-GET 副本容错） | #11 挡路；剥壳后 **[#19](https://github.com/rustin-beep/Vitro/issues/19) 首报**（213:5 `NodeList = {0}` 数组成员 struct 清零初始化）+ E3006×9 | 第二十一批；Clang 绿；`uint32_t` 位运算/XOR 排序全绿 |
| `batch21-dht-crdt-vclock-paxos/crdt.c` | CRDT 四件套（G-Counter/PN-Counter/LWW-Register/OR-Set，merge 收敛） | #11 挡路；剥壳后 **#3×14**（E3038 字面量实参）；**`*dst = *src` 非 const 形参版绿——#17 触发条件修正为 const 形参** | Clang 绿；#17 评论已补边界 |
| `batch21-dht-crdt-vclock-paxos/vclock.c` | 向量时钟与因果序（VC 比较/因果矩阵/并发对检测） | #11 挡路 + **#14（include stdarg 未使用仍触发 W1018——「include 即触发」实锤）**；剥壳后 #3×28（E3014×12+E3038×16） | Clang 绿；**struct 按值返回（vc_zero）typeck 层通过**——codegen 层待首航 |
| `batch21-dht-crdt-vclock-paxos/paxos.c` | Paxos 共识（Prepare/Promise/Accept/Accepted 四阶段+安全性场景） | #11 挡路；剥壳后 #3×18（E3038×13+E3006×5）+ **E3032×1**（262 行 `P%d` 漏传参——代码真错，Clang -Wformat 仅警告 EXIT=0、引擎判 error——**警告/错误严重性口径差异**，登记错误路径 golden 处方） | Clang 绿（含警告）；复合字面量 `(PropNum){0,0}` 绿 |
| `batch22-pbft-dag/pbft.c` | PBFT 拜占庭容错（三阶段/quorum 计数/拜占庭节点/视图变更） | #11 挡路；剥壳后 **#3×14**（E3038：strncpy 存根轨 char[16] 数组实参 + broadcast 数组实参 + client_request 字面量） | 第二十二批；Clang 绿；剥壳需补 true/false 宏（引擎内置有、Clang 靠 stdbool.h——剥壳变换教训） |
| `batch22-pbft-dag/dag.c` | DAG 类共识 Tangle 风格（tips/累积权重/拓扑排序） | #11 挡路；剥壳后 **0 条——首份全绿用户代码** | 第二十二批；**全管线首航里程碑**：typeck→codegen→VM 运行全通，输出与 Clang 逐字节一致（rand() 驱动的 40 行选择序列除外——C 标准不规定 rand 算法，属允许的实现差异，运行时对拍 skip 白名单类）；codegen/运行时层首航零缺陷 |
| `batch23-parse-recovery/main-brace.c` | `int main{`（缺参数括号）+ `};` 尾分号——**错误路径诊断形状**首例 | **新 issue（parse 层内恢复缺失）**：首错 E2005 与 Clang 同位同形，其后 7 条级联（级联数 ∝ 首错后 token 数） | 第二十三批（2026-10-05 打开本地文件夹批真机测试用户实测）；Clang 1 error + 1 warning（main 变量 UB 警告）；垃圾 token 变体（`int main{dadadas`，探针 `.shadow_tmp/main_brace_junk.c`）钉死机制=声明起点重试非逐 token 报（首错行内剩余被丢弃——dadadas 两侧均零诊断） |
| `batch24-strawberry-propagation/strawberry-propagation.c` | 草莓繁殖算法优化 Rastrigin（种群进化 + 匍匐茎传播 + rand 驱动，~200 行） | **#10（M_PI 报 E3023「未声明的变量」——math.h 存根 20 个签名零宏，真源 `scripts/moonbit/libc_src/include/math.h`）**+ **新 issue（W3054 NULL→指针空指针常量误报，见下）** | 第二十四批（2026-10-09）；**M_PI 演进注记**：batch9/batch12 的 M_PI 样本均因 Windows MSVC 头不定义而属平台差异挡板，本样本原码自带 `#define _USE_MATH_DEFINES`——Clang 22.1.4（MSVC 头）与 gcc 16.2（mingw-w64 头）**双侧零警告真绿，唯 Vitro 拒**，为 #10 math 数值宏缺口首个实测命中；探针钉死与 `_USE_MATH_DEFINES` 无关（不带该宏同样 E3023）；剥壳（M_PI→字面量）后 compile ok 仅剩 W3054，run 双侧同形收敛 (0,0) 附近（rand 数字按纪律豁免）；**W3054 新形状**：NULL 为 lexer 关键字（`lexer/internal/scanner/keyword.mbt:49`）按整数 0 参与转换检查，`f(NULL)`/`char *p = NULL`/`time(0)` 三变体全误报（比较面不报）——Clang 侧空指针常量（C11 6.3.2.3）零警告，病面=C 最高频惯用法族 |
| `batch25-clock-assignment/clock_v0_windows.c` | 控制台数字钟大作业 **v0 教材原味版**（windows.h/Sleep/system("cls")/localtime/点阵渲染/闹钟/文件持久化，~170 行） | **E1021 windows.h 未收录（include 层短路，#20 遮蔽又一实例）**；剥壳（摘 windows.h）后 9 条：**#10 三缺口**（stdio.h 无 `fscanf`——存根只有 sscanf；time.h 无 `localtime`/`struct tm`——E3036+E3042×3；system/Sleep 无声明=沙箱边界，报错形态健康）+ **#56 同款 W3054×2**（`time(NULL)` 惯用法 + 未定义函数按隐式 int 返回→指针赋值的级联） | 第二十五批（2026-10-09，学生大作业场景：图 1 点阵数字钟+500ms 刷新+闹钟+持久化）；Clang/gcc 双侧绿（clang 仅 MSVC fopen deprecation 教学噪音） |
| `batch25-clock-assignment/clock_v1_portable.c` | 同作业 **v1 可移植版**（无 windows.h；time()+东八区手动分解替代 localtime；fgets+sscanf 替代 fscanf；3 帧连打替代 500ms 刷新；`time(&raw)` 传址形式绕开 #56） | **三方 compile 全通**（Vitro 仅 2 条 H3057 hint——fopen 存根 void* 返回形态副作用，温和不立案）；run 双侧同形（交互/点阵/闹钟管理/退出） | 同上；**时间三件套实证**：`time()` 恒 0（双臂一致=引擎级确定性设计，非壳接线缺口；探针 `.shadow_tmp/probe_time.c`）、`clock()` 恒 0（gcc 正常推进；探针 `.shadow_tmp/probe_clock*.c`）、localtime 不存在——**大作业核心需求①「显示当前系统实时时间」在 Vitro 不可真实现**（v1 三帧全 08:00:00 静态）；**步数护栏预算实测**：10 万次迭代可跑完、100 万次撞护栏（忙等延时不可行的量化锚）；**持久化边界**：gcc 真盘闭环（alarms.txt+二次启动加载 ✓），Vitro CLI run 沙箱 vfs 会话级（二次 run alarms:0——demo workspace/FSA 模式才可真验「重启加载」验收点） |

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

## 为什么引擎语料、shadow 对拍与 LeetCode 真题防线都没有发现？（方法论复盘）

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
