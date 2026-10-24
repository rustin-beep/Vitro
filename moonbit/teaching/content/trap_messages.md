<!--
teaching/content·trap 教学文案模板（45 条）【真源】（#125 批 A，2026-10-15）。

管线（替代 #60 双出口：.json.mbt 真源 + jsonmbt 再生教师面 .json）：
  本文件（人写）→ moonbit/teaching/tools/content_parser.c（vitro 编译运行，
  自己吃自己狗粮）→ moonbit/teaching/assets/trap_messages_gen.mbt
  （@generated 禁手改）→ 引擎 import 面不变。

写作规则（解析器按**纯文本**切段，本文件不进渲染链；markdown 语法不生效）：
- 一节一码位：`## <码位_形态>`（与 host_memory 装配点键一致）；
  **键名规则（#261，2026-10-24）**：键带 `E####_` 前缀 ⇔ 渲染文案首段带
  同码 `(E####)`（bounds/div_zero 族立码 E3086/E3087/E3088 起统一）；
  无码文案（资源墙/附注/提示段）键名不带 E 前缀——键名即码位可信来源；
- `placeholders:` 可选，逗号分隔；须与正文 `{name}` 占位符集双向相等
  （contract_wbtest 锚——写坏即红）；
- `ends_with_newline: <1|2>` 可选 = 模板尾部补几个换行（缺省 0；正文后**不留**
  空行——空行只作节间分隔，故换行数必须显式记数，勿靠空行暗示）；
- 节正文 = 模板原样（`{name}` 占位符保留）；空行 = 文案里的空行（即 \n\n）；
- 未知头部字段 / 正文后多于 1 行空行 = 生成器 fail loud。
-->

## E3061_double_free

placeholders: freed_line, alloc_line

[double-free] Double-Free (E3061)：你正在 free 一块已经在第 {freed_line} 行被释放过的内存（由第 {alloc_line} 行的 malloc/realloc 分配）。

[cause] 原因：同一块内存被释放了两次，这通常是因为 free(p) 后没有将 p 置为 NULL，或者两个指针指向同一块内存且都被释放了。
[fix] 解决方法：每次 free(p) 后立刻写 p = NULL;。对 NULL 指针重复 free 是安全的。

## E3027_free_interior

placeholders: addr, alloc_line, base, size

[deny] 无效 free (E3027)：free 的地址 0x{addr} 是第 {alloc_line} 行 malloc 块（起始 0x{base}，{size} 字节）的内部地址，不是起始地址。

[cause] 原因：free 只能释放 malloc/calloc/realloc 返回的原始指针。
[fix] 解决方法：保存分配返回的原始指针用于 free；需要偏移访问时使用单独的指针变量，不要 free 偏移后的指针。

## E3061_free_freed_interior

placeholders: addr, freed_line, log_base

[double-free] 无效 free (E3061)：地址 0x{addr} 位于第 {freed_line} 行已释放块（起始 0x{log_base}）的内部。free 只能释放 malloc 返回的原始指针。

## E3027_free_unknown

placeholders: addr

[deny] 无效 free (E3027)：free 的地址 0x{addr} 不指向任何 malloc/calloc/realloc 分配的内存块起始地址（可能是栈地址、全局变量地址或未初始化指针的垃圾值）。

[cause] 原因：只有 malloc 系列函数返回的指针才能被 free。
[fix] 解决方法：检查该指针是否来自 malloc 分配，且未经过指针算术运算。

## E3027_realloc_interior

placeholders: addr, alloc_line, base, size

[deny] 无效 realloc (E3027)：realloc 的地址 0x{addr} 是第 {alloc_line} 行 malloc 块（起始 0x{base}，{size} 字节）的内部地址，不是起始地址。

[cause] 原因：realloc 只接受 malloc/calloc/realloc 返回的原始指针，或 NULL（等价 malloc）。
[fix] 解决方法：保存分配返回的原始指针用于 realloc；需要偏移访问时使用单独的指针变量，不要 realloc 偏移后的指针。

## E3061_realloc_freed_interior

placeholders: addr, freed_line, log_base

[double-free] 无效 realloc (E3061)：地址 0x{addr} 位于第 {freed_line} 行已释放块（起始 0x{log_base}）的内部。realloc 只接受 malloc/calloc/realloc 返回的原始指针。

## E3061_realloc_freed_exact

placeholders: freed_line, alloc_line

[double-free] 无效 realloc (E3061)：你正在 realloc 一块已经在第 {freed_line} 行被释放过的内存（由第 {alloc_line} 行的 malloc/realloc 分配）。

[cause] 原因：realloc 已释放的指针与 double-free 同族。
[fix] 解决方法：每次 free(p) 后立刻写 p = NULL;，对 NULL 做 realloc 等价 malloc 是安全的。

## E3027_realloc_unknown

placeholders: addr

[deny] 无效 realloc (E3027)：realloc 的地址 0x{addr} 不指向任何已分配块的起始位置。

[cause] 原因：可能是栈地址、全局变量地址或未初始化的垃圾值。
[fix] 解决方法：只对 malloc/calloc/realloc 的返回值调用 realloc。

## note_heap_exhausted

placeholders: total_kb, quar_kb
ends_with_newline: 1

[堆] 内存耗尽：malloc/calloc/realloc 返回 NULL（Vitro 堆上限 {total_kb}KB，其中 {quar_kb}KB 为隔离区预算）。常见原因是「只分配不释放」——请确认每条 malloc 路径都有对应的 free。

## note_malloc_zero


[warning] malloc(0) 返回 NULL。在 C 标准中，malloc(0) 的行为是实现定义的，可能返回 NULL 也可能返回一个不可解引用的非空指针。

## E3083_null_deref

placeholders: addr

[null-deref] NULL 指针解引用 (E3083)：访问了 NULL 指针区域（地址 0x{addr}）。NULL 指针不能解引用。请确认指针已被正确初始化。

## E3087_oob_host

placeholders: addr

[oob] 内存访问越界 (E3087)：你访问了地址 0x{addr}，它不属于任何变量、数组或堆块。请检查数组下标或指针运算是否超出分配范围。

## E3060_uaf

placeholders: freed_line, freed_step, action, alloc_line

[uaf] Use-After-Free (E3060)：你正在向一块已经在第 {freed_line} 行（第 {freed_step} 步）被 free 的内存{action}（由第 {alloc_line} 行的 malloc/realloc 分配）。

[cause] 原因：指针在 free 后没有置为 NULL，或者存在别名指针（另一个指针也指向同一块内存）。
[fix] 解决方法：free(p) 后立即写 p = NULL;，并确保不再通过其他指针访问这块内存。

## E3086_bounds_array

placeholders: name, index, count, max_index

[deny] 数组越界 (E3086)：你访问了 {name}[{index}]，但数组 '{name}' 只有 {count} 个元素，有效索引是 0~{max_index}。

[cause] 原因：数组索引超出了合法范围。
[fix] 检查方法：确认索引变量值在 0 到 {max_index} 之间。

## E3087_bounds_generic

placeholders: addr, min, max

[deny] 内存访问越界 (E3087)：你访问了地址 0x{addr}，但合法内存范围是 0x{min} ~ 0x{max}。

[fix] 检查方法：
  • 确认数组索引小于数组大小
  • 确认指针已经指向有效的内存地址
  • 确认没有使用已经 free 的指针

## E3088_div_zero

placeholders: a, zero_section

[divide-zero] 除零错误 (E3088)：你试图用 {a} 除以 0。

{zero_section}[cause] 原因：除数不能为 0。
[fix] 检查你的除法表达式，确保除数在被除之前不是 0。
[note] 示例：如果变量 b 可能为 0，先用 if 判断：
    if (b != 0) {
        result = a / b;
    }

## E3088_div_zero_inspect

placeholders: vars
ends_with_newline: 2

[inspect] 当前作用域内值为 0 的变量：{vars}。请检查除法表达式中是否使用了这些变量。

## E_inf_loop

placeholders: max_steps, stale_section, changed_section

[step-limit] 程序执行步数达到预算上限（{max_steps} 步）被安全截断——这是资源墙，不一定是你程序的错误。

{stale_section}{changed_section}[cause] 两种可能，先分辨你是哪种：
  • 计算量确实大（大循环/大搜索的合法负载——算法作业常见）：预算不够，不是 bug。提高预算再跑：serve/api 用 config.set（preset:"algo" 一键到 20 亿步，或 max_steps 单调），CLI 用 run --max-steps N
  • 真无限循环（预算怎么加都不够）：循环条件永远为真（如 while(1)）、循环变量没有更新（如忘了写 i++）、递归函数没有终止条件
[fix] 先加预算重跑一次：跑完了就是计算量问题；同样位置再撞墙，检查循环体中是否有改变循环条件的语句。

## E_inf_loop_stale

placeholders: interval, vars
ends_with_newline: 2

[inspect] 在最近 {interval} 步内没有变化的变量：{vars}。

## E_inf_loop_changed

placeholders: vars
ends_with_newline: 2

[inspect] 发生变化的变量：{vars}。

## hint_null_base


试图解引用一个 NULL 指针。NULL 指针不指向任何有效内存。

## hint_null_ptrs

placeholders: ptrs

 当前为 NULL 的指针: {ptrs}。请在使用前确保指针已被正确初始化（如通过 malloc 或赋值）。

## hint_null_history

placeholders: name, addr

 注意：'{name}' 之前指向过地址 {addr}，后来变成了 NULL。

## hint_uaf

placeholders: alloc_line, freed_line

这块内存在第 {alloc_line} 行被分配，在第 {freed_line} 行被释放，现在又被访问了。free 后请立即将指针置为 NULL，避免继续使用。

## hint_uaf_ptrs

placeholders: ptrs

 相关指针: {ptrs}。

## hint_double_free

placeholders: freed_line, code_line

同一块内存在第 {freed_line} 行已被释放，现在第 {code_line} 行又 free 了一次。每次 free(p) 后请立刻执行 p = NULL;，因为对 NULL 重复 free 是安全的。

## hint_div_base


发生了除零错误。除数变成了 0，这在数学上没有定义。

## hint_div_zero_vars

placeholders: vars

 当前值为 0 的变量: {vars}。请检查这些变量是否在除法前被正确初始化或保护。

## hint_div_dividend

placeholders: dividend

 被除数是 {dividend}，但除数变成了 0。请确认除法前检查了除数是否为零。

## hint_fix_null


使用指针前检查是否为 NULL

## hint_fix_set_null


free 后执行 p = NULL

## hint_fix_div_zero


除法前检查除数是否为 0

## hint_fix_change_le


将 <= 改为 <

## hint_bounds_obe_line

placeholders: line, array, size, last_ok

数组越界是因为第 {line} 行的循环条件使用了 '<='。数组 '{array}' 大小为 {size}，最后一个有效索引是 {last_ok}。建议将 '<=' 改为 '<'。

## hint_bounds_obe

placeholders: array, size, last_ok

数组越界是因为循环条件使用了 '<='。数组 '{array}' 大小为 {size}，最后一个有效索引是 {last_ok}。建议将 '<=' 改为 '<'。

## hint_bounds_wi_line

placeholders: array, index, var, start_val, line

数组 '{array}' 访问了越界索引 {index}。循环变量 '{var}' 从 {start_val} 开始，导致最终访问到索引 {index}。建议将第 {line} 行的初始值改为 0。

## hint_bounds_wi

placeholders: array, index, var, start_val

数组 '{array}' 访问了越界索引 {index}。循环变量 '{var}' 从 {start_val} 开始，导致最终访问到索引 {index}。建议将初始值改为 0。

## hint_fix_wi

placeholders: var, start_val

将 {var} 的初始值 {start_val} 改为 0

## hint_bounds_winc_line

placeholders: array, index, var, step, line

数组 '{array}' 访问了越界索引 {index}。循环变量 '{var}' 的步长是 {step}，导致跳过了边界检查。建议将第 {line} 行的步长改为 1，或调整循环条件。

## hint_bounds_winc

placeholders: array, index, var, step

数组 '{array}' 访问了越界索引 {index}。循环变量 '{var}' 的步长是 {step}，导致跳过了边界检查。建议将步长改为 1，或调整循环条件。

## hint_fix_winc

placeholders: step

将步长 {step} 改为 1

## hint_bounds_ui

placeholders: var, index

索引变量 '{var}' 的值是 {index}，但执行历史太短，可能是变量未初始化或从外部输入读取了非法值。建议在使用前初始化 '{var}'。

## hint_fix_ui

placeholders: var

初始化 '{var}'

## hint_bounds_gen_hist

placeholders: array, index, var, hist

数组 '{array}' 访问了越界索引 {index}。请检查 '{var}' 的最近变化：{hist}。

## hint_bounds_gen

placeholders: array, index

数组 '{array}' 访问了越界索引 {index}。请检查循环边界或索引计算。
