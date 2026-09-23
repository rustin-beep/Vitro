///|
/// R1 内存布局纯函数与常量（S5）——Rust `vitro_runtime::memory_state` 中
/// codegen 侧消费面的照搬（布局载体/堆状态机属 S6 `vitro/engine/memory`，
/// 本文件只含"编译期布局口径"：地址常量 + 对齐 + argv 占用 + 动态堆起点）。
///
/// **字节量纲纪律（F2）**：argv 字符串占用的字节长度一律按 UTF-8 字节数计
/// （`@utf8.encode(s).length()`）——与 Rust `String::len()`（UTF-8 字节）同
/// 口径；MoonBit `String::length()` 是 UTF-16 码元数，禁止参与本文件的任何
/// 字节数计算（非 ASCII argv 下会静默少算）。

///|
/// 总内存空间（1MB）。S6 起由 `vitro/engine/memory` 消费（载体尺寸/上界检查）；
/// `STACK_START` 由 vm（栈顶初值）、`compute_heap_base`/`argv_region_footprint`
/// 由 vm setup（动态堆起点）消费——0.6.0 起面扩张为 pub（minor）。
pub const MEM_SIZE : UInt = 1024 * 1024

///|
/// NULL 陷阱区大小。
pub const NULL_TRAP_SIZE : UInt = 0x1000

///|
/// 全局区起始地址。
pub const GLOBAL_START : UInt = 0x1000

///|
/// 堆区默认起始地址（全局数据未越过时的堆起点下限）。
pub const HEAP_START : UInt = 0x5000

///|
/// 全局数据区（全局变量/静态变量/vtable/字符串字面量）的编译期硬上限，
/// 绝对地址。
///
/// R1 ② 判据单源化：所有"全局区还能不能长"的判断统一以本常量为界
/// （取代 codegen 与 VM 的两套魔数）；取值与旧字符串字面量判据
/// （MEM_SIZE / 16 = 64KB）一致，不收紧存量行为。
pub const GLOBAL_REGION_LIMIT : UInt = MEM_SIZE / 16

///|
/// 栈区起始地址（从高地址向低地址增长）。vm 的 `mem_stack_top` 初值。
pub const STACK_START : UInt = MEM_SIZE

///|
/// 4 字节对齐掩码（= !3 的 UInt 形态）。
pub const ALIGN4_MASK : UInt = 0xFFFFFFFC

///|
/// 4 字节向上对齐。
pub fn align4(x : UInt) -> UInt {
  (x + 3) & ALIGN4_MASK
}

///|
/// argv 区域占用字节数（指针数组 + 字符串数据，4 字节对齐）。
///
/// R1 ③：argv 自 `GLOBAL_REGION_LIMIT` 向下分配，本函数是占用的唯一计算
/// 口径（VM `setup_argv` 的编址与 `compute_heap_base` 的堆起点都从它推导）。
pub fn argv_region_footprint(argc : Int, argv : Array[String]) -> UInt {
  if argc <= 0 {
    return 0
  }
  // 指针数组按 argc 开槽（未填满的槽为零），字符串数据只按实际存在的
  // min(argc, argv.len()) 条计数（每条 +NUL）。
  let count = if argc < argv.length() { argc } else { argv.length() }
  let mut strings : UInt64 = 0
  for i in 0..<count {
    strings += @utf8.encode(argv[i]).length().to_uint64() + 1
  }
  align4((argc.to_uint64() * 4 + strings).to_uint())
}

///|
/// R1 ① 动态堆起点：`max(HEAP_START, align4(global_data_end))`；存在 argv
/// 时还必须越过 argv 顶界（`GLOBAL_REGION_LIMIT`），否则堆 bump 会覆盖
/// 参数区。
///
/// `global_data_end` 为全局数据区末端的**绝对地址**（codegen 导出，含
/// Bytecode Libc 预留段），未编译时传 0 即退化为静态 `HEAP_START`。
pub fn compute_heap_base(
  global_data_end : UInt,
  argc : Int,
  argv : Array[String],
) -> UInt {
  let aligned = align4(global_data_end)
  let mut base = if HEAP_START > aligned { HEAP_START } else { aligned }
  if argc > 0 && argv.length() > 0 {
    if GLOBAL_REGION_LIMIT > base {
      base = GLOBAL_REGION_LIMIT
    }
  }
  base
}
