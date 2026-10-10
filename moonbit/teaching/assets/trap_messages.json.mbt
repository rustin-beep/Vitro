// teaching/assets·trap 教学文案模板【真源】（issue #60 批二，2026-10-10）。
//
// 契约形态：键 = 码位_形态（E3061_free_freed_interior 之类）；值 = TrapMessage
// { template（{name} 占位符——util.render_template 渲染）, placeholders（声明集）}。
// 契约锚（本包 wbtest）：每条 placeholders 声明集 == template 实际占位符集
// 双向相等——写坏声明/写坏模板即红；装配点（host_memory 三函数）以固定
// 输入的逐字节快照锚锁等价（改造前后文案零漂移）。
//
// 失败形态分级：模板缺参 = 渲染时保留 {name} 原文（学生可见）；装配缺键
// = get().unwrap() panic（引擎 bug，fail loud）。文案正文经审计无字面
// 花括号（与占位符语法无冲突）。

///|
pub struct TrapMessage {
  template : String
  placeholders : Array[String]
}

///|
pub let trap_messages : Map[String, TrapMessage] = {
  "E3061_double_free": TrapMessage::{
    template: "[double-free] Double-Free (E3061)：你正在 free 一块已经在第 {freed_line} 行被释放过的内存（由第 {alloc_line} 行的 malloc/realloc 分配）。\n\n[cause] 原因：同一块内存被释放了两次，这通常是因为 free(p) 后没有将 p 置为 NULL，或者两个指针指向同一块内存且都被释放了。\n[fix] 解决方法：每次 free(p) 后立刻写 p = NULL;。对 NULL 指针重复 free 是安全的。",
    placeholders: ["freed_line", "alloc_line"],
  },
  "E3027_free_interior": TrapMessage::{
    template: "[deny] 无效 free (E3027)：free 的地址 0x{addr} 是第 {alloc_line} 行 malloc 块（起始 0x{base}，{size} 字节）的内部地址，不是起始地址。\n\n[cause] 原因：free 只能释放 malloc/calloc/realloc 返回的原始指针。\n[fix] 解决方法：保存分配返回的原始指针用于 free；需要偏移访问时使用单独的指针变量，不要 free 偏移后的指针。",
    placeholders: ["addr", "alloc_line", "base", "size"],
  },
  "E3061_free_freed_interior": TrapMessage::{
    template: "[double-free] 无效 free (E3061)：地址 0x{addr} 位于第 {freed_line} 行已释放块（起始 0x{log_base}）的内部。free 只能释放 malloc 返回的原始指针。",
    placeholders: ["addr", "freed_line", "log_base"],
  },
  "E3027_free_unknown": TrapMessage::{
    template: "[deny] 无效 free (E3027)：free 的地址 0x{addr} 不指向任何 malloc/calloc/realloc 分配的内存块起始地址（可能是栈地址、全局变量地址或未初始化指针的垃圾值）。\n\n[cause] 原因：只有 malloc 系列函数返回的指针才能被 free。\n[fix] 解决方法：检查该指针是否来自 malloc 分配，且未经过指针算术运算。",
    placeholders: ["addr"],
  },
  "E3027_realloc_interior": TrapMessage::{
    template: "[deny] 无效 realloc (E3027)：realloc 的地址 0x{addr} 是第 {alloc_line} 行 malloc 块（起始 0x{base}，{size} 字节）的内部地址，不是起始地址。\n\n[cause] 原因：realloc 只接受 malloc/calloc/realloc 返回的原始指针，或 NULL（等价 malloc）。\n[fix] 解决方法：保存分配返回的原始指针用于 realloc；需要偏移访问时使用单独的指针变量，不要 realloc 偏移后的指针。",
    placeholders: ["addr", "alloc_line", "base", "size"],
  },
  "E3061_realloc_freed_interior": TrapMessage::{
    template: "[double-free] 无效 realloc (E3061)：地址 0x{addr} 位于第 {freed_line} 行已释放块（起始 0x{log_base}）的内部。realloc 只接受 malloc/calloc/realloc 返回的原始指针。",
    placeholders: ["addr", "freed_line", "log_base"],
  },
  "E3061_realloc_freed_exact": TrapMessage::{
    template: "[double-free] 无效 realloc (E3061)：你正在 realloc 一块已经在第 {freed_line} 行被释放过的内存（由第 {alloc_line} 行的 malloc/realloc 分配）。\n\n[cause] 原因：realloc 已释放的指针与 double-free 同族。\n[fix] 解决方法：每次 free(p) 后立刻写 p = NULL;，对 NULL 做 realloc 等价 malloc 是安全的。",
    placeholders: ["freed_line", "alloc_line"],
  },
  "E3027_realloc_unknown": TrapMessage::{
    template: "[deny] 无效 realloc (E3027)：realloc 的地址 0x{addr} 不指向任何已分配块的起始位置。\n\n[cause] 原因：可能是栈地址、全局变量地址或未初始化的垃圾值。\n[fix] 解决方法：只对 malloc/calloc/realloc 的返回值调用 realloc。",
    placeholders: ["addr"],
  },
  "note_heap_exhausted": TrapMessage::{
    template: "[堆] 内存耗尽：malloc/calloc/realloc 返回 NULL（Vitro 堆上限 {total_kb}KB，其中 {quar_kb}KB 为隔离区预算）。常见原因是「只分配不释放」——请确认每条 malloc 路径都有对应的 free。\n",
    placeholders: ["total_kb", "quar_kb"],
  },
  "note_malloc_zero": TrapMessage::{
    template: "[warning] malloc(0) 返回 NULL。在 C 标准中，malloc(0) 的行为是实现定义的，可能返回 NULL 也可能返回一个不可解引用的非空指针。",
    placeholders: [],
  },
  "E3060_null_deref": TrapMessage::{
    template: "访问了 NULL 指针区域（地址 0x{addr}）。NULL 指针不能解引用。请确认指针已被正确初始化。",
    placeholders: ["addr"],
  },
  "E3060_oob_host": TrapMessage::{
    template: "内存访问越界（地址 0x{addr}）。请检查数组下标或指针运算是否超出分配范围。",
    placeholders: ["addr"],
  },
  "E3060_uaf": TrapMessage::{
    template: "[uaf] Use-After-Free (E3060)：你正在向一块已经在第 {freed_line} 行（第 {freed_step} 步）被 free 的内存{action}（由第 {alloc_line} 行的 malloc/realloc 分配）。\n\n[cause] 原因：指针在 free 后没有置为 NULL，或者存在别名指针（另一个指针也指向同一块内存）。\n[fix] 解决方法：free(p) 后立即写 p = NULL;，并确保不再通过其他指针访问这块内存。",
    placeholders: ["freed_line", "freed_step", "action", "alloc_line"],
  },
  "bounds_array": TrapMessage::{
    template: "[deny] 数组越界：你访问了 {name}[{index}]，但数组 '{name}' 只有 {count} 个元素，有效索引是 0~{max_index}。\n\n[cause] 原因：数组索引超出了合法范围。\n[fix] 检查方法：确认索引变量值在 0 到 {max_index} 之间。",
    placeholders: ["name", "index", "count", "max_index"],
  },
  "bounds_generic": TrapMessage::{
    template: "[deny] 内存访问越界：你访问了地址 0x{addr}，但合法内存范围是 0x{min} ~ 0x{max}。\n\n[fix] 检查方法：\n  • 确认数组索引小于数组大小\n  • 确认指针已经指向有效的内存地址\n  • 确认没有使用已经 free 的指针",
    placeholders: ["addr", "min", "max"],
  },
  "E_div_zero": TrapMessage::{
    template: "[divide-zero] 除零错误：你试图用 {a} 除以 0。\n\n{zero_section}[cause] 原因：除数不能为 0。\n[fix] 检查你的除法表达式，确保除数在被除之前不是 0。\n[note] 示例：如果变量 b 可能为 0，先用 if 判断：\n    if (b != 0) {\n        result = a / b;\n    }",
    placeholders: ["a", "zero_section"],
  },
  "E_div_zero_inspect": TrapMessage::{
    template: "[inspect] 当前作用域内值为 0 的变量：{vars}。请检查除法表达式中是否使用了这些变量。\n\n",
    placeholders: ["vars"],
  },
  "E_inf_loop": TrapMessage::{
    template: "[step-limit] 程序执行步数超过限制（{max_steps} 步），可能包含无限循环。\n\n{stale_section}{changed_section}[cause] 原因：程序执行了太多步数但没有结束。常见原因：\n  • 循环条件永远为真（如 while(1)）\n  • 循环变量没有更新（如忘了写 i++）\n  • 递归函数没有正确的终止条件\n[fix] 检查方法：确认循环体中有改变循环条件的语句。",
    placeholders: ["max_steps", "stale_section", "changed_section"],
  },
  "E_inf_loop_stale": TrapMessage::{
    template: "[inspect] 在最近 {interval} 步内没有变化的变量：{vars}。\n\n",
    placeholders: ["interval", "vars"],
  },
  "E_inf_loop_changed": TrapMessage::{
    template: "[inspect] 发生变化的变量：{vars}。\n\n",
    placeholders: ["vars"],
  },
  "hint_null_base": TrapMessage::{
    template: "试图解引用一个 NULL 指针。NULL 指针不指向任何有效内存。",
    placeholders: [],
  },
  "hint_null_ptrs": TrapMessage::{
    template: " 当前为 NULL 的指针: {ptrs}。请在使用前确保指针已被正确初始化（如通过 malloc 或赋值）。",
    placeholders: ["ptrs"],
  },
  "hint_null_history": TrapMessage::{
    template: " 注意：'{name}' 之前指向过地址 {addr}，后来变成了 NULL。",
    placeholders: ["name", "addr"],
  },
  "hint_uaf": TrapMessage::{
    template: "这块内存在第 {alloc_line} 行被分配，在第 {freed_line} 行被释放，现在又被访问了。free 后请立即将指针置为 NULL，避免继续使用。",
    placeholders: ["alloc_line", "freed_line"],
  },
  "hint_uaf_ptrs": TrapMessage::{
    template: " 相关指针: {ptrs}。",
    placeholders: ["ptrs"],
  },
  "hint_double_free": TrapMessage::{
    template: "同一块内存在第 {freed_line} 行已被释放，现在第 {code_line} 行又 free 了一次。每次 free(p) 后请立刻执行 p = NULL;，因为对 NULL 重复 free 是安全的。",
    placeholders: ["freed_line", "code_line"],
  },
  "hint_div_base": TrapMessage::{
    template: "发生了除零错误。除数变成了 0，这在数学上没有定义。",
    placeholders: [],
  },
  "hint_div_zero_vars": TrapMessage::{
    template: " 当前值为 0 的变量: {vars}。请检查这些变量是否在除法前被正确初始化或保护。",
    placeholders: ["vars"],
  },
  "hint_div_dividend": TrapMessage::{
    template: " 被除数是 {dividend}，但除数变成了 0。请确认除法前检查了除数是否为零。",
    placeholders: ["dividend"],
  },
  "hint_fix_null": TrapMessage::{
    template: "使用指针前检查是否为 NULL",
    placeholders: [],
  },
  "hint_fix_set_null": TrapMessage::{
    template: "free 后执行 p = NULL",
    placeholders: [],
  },
  "hint_fix_div_zero": TrapMessage::{
    template: "除法前检查除数是否为 0",
    placeholders: [],
  },
  "hint_fix_change_le": TrapMessage::{
    template: "将 <= 改为 <",
    placeholders: [],
  },
  "hint_bounds_obe_line": TrapMessage::{
    template: "数组越界是因为第 {line} 行的循环条件使用了 '<='。数组 '{array}' 大小为 {size}，最后一个有效索引是 {last_ok}。建议将 '<=' 改为 '<'。",
    placeholders: ["line", "array", "size", "last_ok"],
  },
  "hint_bounds_obe": TrapMessage::{
    template: "数组越界是因为循环条件使用了 '<='。数组 '{array}' 大小为 {size}，最后一个有效索引是 {last_ok}。建议将 '<=' 改为 '<'。",
    placeholders: ["array", "size", "last_ok"],
  },
  "hint_bounds_wi_line": TrapMessage::{
    template: "数组 '{array}' 访问了越界索引 {index}。循环变量 '{var}' 从 {start_val} 开始，导致最终访问到索引 {index}。建议将第 {line} 行的初始值改为 0。",
    placeholders: ["array", "index", "var", "start_val", "line"],
  },
  "hint_bounds_wi": TrapMessage::{
    template: "数组 '{array}' 访问了越界索引 {index}。循环变量 '{var}' 从 {start_val} 开始，导致最终访问到索引 {index}。建议将初始值改为 0。",
    placeholders: ["array", "index", "var", "start_val"],
  },
  "hint_fix_wi": TrapMessage::{
    template: "将 {var} 的初始值 {start_val} 改为 0",
    placeholders: ["var", "start_val"],
  },
  "hint_bounds_winc_line": TrapMessage::{
    template: "数组 '{array}' 访问了越界索引 {index}。循环变量 '{var}' 的步长是 {step}，导致跳过了边界检查。建议将第 {line} 行的步长改为 1，或调整循环条件。",
    placeholders: ["array", "index", "var", "step", "line"],
  },
  "hint_bounds_winc": TrapMessage::{
    template: "数组 '{array}' 访问了越界索引 {index}。循环变量 '{var}' 的步长是 {step}，导致跳过了边界检查。建议将步长改为 1，或调整循环条件。",
    placeholders: ["array", "index", "var", "step"],
  },
  "hint_fix_winc": TrapMessage::{
    template: "将步长 {step} 改为 1",
    placeholders: ["step"],
  },
  "hint_bounds_ui": TrapMessage::{
    template: "索引变量 '{var}' 的值是 {index}，但执行历史太短，可能是变量未初始化或从外部输入读取了非法值。建议在使用前初始化 '{var}'。",
    placeholders: ["var", "index"],
  },
  "hint_fix_ui": TrapMessage::{
    template: "初始化 '{var}'",
    placeholders: ["var"],
  },
  "hint_bounds_gen_hist": TrapMessage::{
    template: "数组 '{array}' 访问了越界索引 {index}。请检查 '{var}' 的最近变化：{hist}。",
    placeholders: ["array", "index", "var", "hist"],
  },
  "hint_bounds_gen": TrapMessage::{
    template: "数组 '{array}' 访问了越界索引 {index}。请检查循环边界或索引计算。",
    placeholders: ["array", "index"],
  },
}
