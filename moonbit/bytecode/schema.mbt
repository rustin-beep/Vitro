///|
/// 产物 schema（S5，L6）——Rust `vitro_codegen::CompileOutput` 13 字段 +
/// FuncMeta/LocalBuffer/Symbol 的 1:1 照搬。字段名/顺序是 A 级产物对拍
/// （dump-compile JSON）的契约面：Rust 侧 serde derive 是唯一 emitter，
/// 本包 `emitter.mbt` 与其逐字段同构（B 级锚"两侧显式 emitter"纪律）。
///
/// 判等注意：`@ast.Type` 无 derive(Eq)（判等单源是 `@ast.type_eq`——
/// Typeof 自反 false / Array 忽略 vla_dims 的 Rust PartialEq 全语义），
/// 故携带 Type 的结构只 derive(Debug)；需要判等时逐字段 + type_eq 自组。

///|
/// 局部缓冲区描述（V-P1-6 栈缓冲区溢出检测用）：
/// 编译期登记的栈上数组（如 `char buf[4]`），offset 相对帧 locals_base。
pub(all) struct LocalBuffer {
  /// 相对 locals_base 的字节偏移。
  offset : Int
  /// 缓冲区总字节数。
  size : Int
  /// 变量名（教学诊断用）。
  name : String
} derive(Debug)

///|
/// 函数元数据（Rust `vitro_runtime::FuncMeta` 照搬，字段序一致）。
/// ip/arg_count/param_count/local_count/param_sizes/is_variadic 为 mut——
/// codegen 两阶段回填（Pass 2 建骨架、enter_function 回填 param_sizes、
/// exit_function 回填 local_count/计数），消费侧（dump/VM）只读。
pub(all) struct FuncMeta {
  mut ip : Int
  /// 参数总 word 数（以 4-byte words 计），供 Call 指令弹栈使用。
  mut arg_count : Int
  /// 参数个数（供 call_user_function 使用，与总 word 数不同）。
  mut param_count : Int
  mut local_count : Int
  mut param_sizes : Array[Int]
  /// 函数返回类型（codegen 使用；session/vm 中保持默认 Void 即可）。
  return_type : @ast.Type
  /// 是否为变参函数。
  mut is_variadic : Bool
  /// 栈上局部数组缓冲区表（V-P1-6）：strcpy/strcat/scanf("%s") 等宿主函数
  /// 据此对栈缓冲区做容量校验（此前只查堆 region，栈上 `char buf[4]`
  /// 被静默覆写）。
  local_buffers : Array[LocalBuffer]
} derive(Debug)

///|
/// 符号表条目（Rust `vitro_runtime::Symbol` 照搬，字段序一致）。
pub(all) struct Symbol {
  name : String
  addr : UInt
  is_local : Bool
  ty : @ast.Type
  scope_depth : Int
  func_name : String
  /// 声明处的源码行号（0 = 未知/不适用）。
  ///
  /// 用途：VM `get_variable_snapshot` 据此判定"该符号在当前执行点是否已进入
  /// 作用域"。`scope_depth` 在所有构造点都是常量（1 = 局部 / 0 = 静态），
  /// 不表达嵌套深度。
  decl_line : Int
} derive(Debug)

///|
/// codegen 对外全部契约（Rust `vitro_codegen::CompileOutput` 13 字段照搬，
/// 字段序一致）。前 8 项进 dump-compile 产物对拍面；source_map/symbols/
/// struct_defs/union_defs/global_data_end 五项是 export 不导出、仅进程内
/// 契约的部分（S5 起 dump-compile 全量对拍）。
pub(all) struct CompileOutput {
  code : Array[@opcode.Instruction]
  globals_init_32 : Array[(UInt, Int)]
  globals_init_64 : Array[(UInt, UInt64)]
  func_table : Map[String, FuncMeta]
  func_index : Map[String, Int]
  string_data : Array[(UInt, String)]
  source_map : Array[(UInt, @source.SourceLoc)]
  symbols : Array[Symbol]
  struct_defs : Map[String, Array[@ast.StructField]]
  union_defs : Map[String, Array[@ast.StructField]]
  f64_constants : Array[Double]
  i64_constants : Array[Int64]
  /// 全局数据区末端的**绝对地址**（R1：`GLOBAL_START + align4(
  /// next_global_offset)`，含 Bytecode Libc 预留段）。运行层据此计算动态
  /// 堆起点 `max(HEAP_START, align4(global_data_end))`。
  global_data_end : UInt
} derive(Debug)
