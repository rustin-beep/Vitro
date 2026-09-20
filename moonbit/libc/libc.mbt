///|
/// L5 libc 签名单表（`vitro/engine/libc`）——MoonBit 侧 builtin 函数签名
/// 的**唯一真相源**（总计划 §5"签名真相源单表"；Rust 侧 O6 债为 4 套
/// 独立维护的真相源：头文件存根 / visit_call 硬编码 / bytecode_libc_sig /
/// codegen 两表，已实测互相冲突——勘察 §③-3 O6）。
///
/// **照搬现状口径**（差分对拍期两侧一致优先，照搬不私改）：表内容逐条
/// 提取自 Rust `vitro_typeck/src/builtin/{mod,io,string,math,memory,
/// file}.rs` 的 check_builtin_* 返回类型与实参约束。已知与 C 标准/
/// 头文件存根冲突处**登记不修正**（N3/N4，待 S8 差异台账收编）：
/// - `printf` / `putchar` / `fprintf` 返回 void（C 标准与 stdio.h 存根
///   为 int；`int n = printf("hi");` 现状报 E3004）
/// - `strcpy` 族返回 char*（bytecode_libc_sig 侧为 void）
///
/// 边界登记：本表只承载 **typeck 消费面**（visit_call 62-arm + 特殊臂
/// 的名与签名）；host_func_id 110 路由表 / BYTECODE_LIBC_ALL_FUNCS 88
/// 函数索引（Rust `is_builtin_func` 的并集判据另一半）随 S5/S6 发射与
/// 执行侧片入库——届时以本表为单源回填，消除第四套真相源。
///
/// `max_args = -1` 表示变参（无上限）；实参**类型**期望与格式串解析、
/// 隐式转换插入、逐函数诊断文案属 typeck 包的检查逻辑（照搬自同名
/// check_builtin_*），不入数据表。

///|
/// libc 函数签名（typeck 消费面）。不 derive Eq/Show——`return_type` 的
/// @ast.Type 走显式 `type_eq`（ast 包 S1 设计），结构体只做数据载体。
pub(all) struct LibcSig {
  name : String
  return_type : @ast.Type
  min_args : Int
  max_args : Int // -1 = 变参
}

///|
/// void* 便捷构造（表内多处使用）。
fn void_ptr() -> @ast.Type {
  @ast.Type::Pointer(Void(false), false)
}

///|
/// char* 便捷构造。
fn char_ptr() -> @ast.Type {
  @ast.Type::Pointer(Char(false, false), false)
}

///|
/// int 便捷构造。
fn int_ty() -> @ast.Type {
  Int(false, false)
}

///|
/// double 便捷构造。
fn double_ty() -> @ast.Type {
  Double(false)
}

///|
/// void 便捷构造。
fn void_ty() -> @ast.Type {
  Void(false)
}

///|
/// long long 便捷构造。
fn long_long_ty() -> @ast.Type {
  LongLong(false, false)
}

///|
/// 签名单表（57 条 = visit_call 58 臂去 `std__move`——C++ 语义臂不入表，
/// S9 C++ 片裁定；print_int/__vitro_output/__vitro_step 三名共享一臂）。
let libc_table : Array[LibcSig] = [
  // —— io（io.rs 提取；printf/putchar/fprintf 的 N3 漂移登记于包注释）——
  { name: "printf", return_type: void_ty(), min_args: 1, max_args: -1, },
  { name: "scanf", return_type: int_ty(), min_args: 2, max_args: -1, },
  { name: "getchar", return_type: int_ty(), min_args: 0, max_args: 0, },
  { name: "putchar", return_type: void_ty(), min_args: 1, max_args: 1, },
  { name: "ungetc", return_type: int_ty(), min_args: 2, max_args: 2, },
  { name: "fprintf", return_type: void_ty(), min_args: 2, max_args: -1, },
  { name: "puts", return_type: int_ty(), min_args: 1, max_args: 1, },
  { name: "sprintf", return_type: int_ty(), min_args: 2, max_args: -1, },
  { name: "snprintf", return_type: int_ty(), min_args: 3, max_args: -1, },
  { name: "sscanf", return_type: int_ty(), min_args: 2, max_args: -1, },
  { name: "print_int", return_type: void_ty(), min_args: 1, max_args: 1, },
  { name: "__vitro_output", return_type: void_ty(), min_args: 1, max_args: 1, },
  { name: "__vitro_step", return_type: void_ty(), min_args: 1, max_args: 1, },
  // —— string（string.rs 提取）——
  { name: "strlen", return_type: int_ty(), min_args: 1, max_args: 1, },
  { name: "strcpy", return_type: char_ptr(), min_args: 2, max_args: 2, },
  { name: "strdup", return_type: char_ptr(), min_args: 1, max_args: 1, },
  { name: "strcmp", return_type: int_ty(), min_args: 2, max_args: 2, },
  { name: "strcat", return_type: char_ptr(), min_args: 2, max_args: 2, },
  { name: "atoi", return_type: int_ty(), min_args: 1, max_args: 1, },
  { name: "strncat", return_type: char_ptr(), min_args: 3, max_args: 3, },
  { name: "strncmp", return_type: int_ty(), min_args: 3, max_args: 3, },
  { name: "memcmp", return_type: int_ty(), min_args: 3, max_args: 3, },
  { name: "strchr", return_type: char_ptr(), min_args: 2, max_args: 2, },
  { name: "strrchr", return_type: char_ptr(), min_args: 2, max_args: 2, },
  { name: "strstr", return_type: char_ptr(), min_args: 2, max_args: 2, },
  { name: "memchr", return_type: void_ptr(), min_args: 3, max_args: 3, },
  { name: "atof", return_type: double_ty(), min_args: 1, max_args: 1, },
  { name: "atol", return_type: long_long_ty(), min_args: 1, max_args: 1, },
  // —— math（math.rs 提取；math.h 其余函数经头文件存根进 funcs 表，
  //    不走 builtin 分派——visit_call 兜底臂 check_user_func）——
  { name: "rand", return_type: int_ty(), min_args: 0, max_args: 0, },
  { name: "srand", return_type: void_ty(), min_args: 1, max_args: 1, },
  { name: "tan", return_type: double_ty(), min_args: 1, max_args: 1, },
  { name: "log10", return_type: double_ty(), min_args: 1, max_args: 1, },
  { name: "fabs", return_type: double_ty(), min_args: 1, max_args: 1, },
  { name: "ceil", return_type: double_ty(), min_args: 1, max_args: 1, },
  { name: "floor", return_type: double_ty(), min_args: 1, max_args: 1, },
  { name: "round", return_type: double_ty(), min_args: 1, max_args: 1, },
  { name: "fmod", return_type: double_ty(), min_args: 2, max_args: 2, },
  // —— memory（memory.rs 提取）——
  { name: "malloc", return_type: void_ptr(), min_args: 1, max_args: 1, },
  { name: "free", return_type: void_ty(), min_args: 1, max_args: 1, },
  { name: "memset", return_type: void_ptr(), min_args: 3, max_args: 3, },
  { name: "exit", return_type: void_ty(), min_args: 1, max_args: 1, },
  { name: "realloc", return_type: void_ptr(), min_args: 2, max_args: 2, },
  { name: "calloc", return_type: void_ptr(), min_args: 2, max_args: 2, },
  // —— file（file.rs 提取；FILE* 表示层 = void*）——
  { name: "fopen", return_type: void_ptr(), min_args: 2, max_args: 2, },
  { name: "fread", return_type: int_ty(), min_args: 4, max_args: 4, },
  { name: "fwrite", return_type: int_ty(), min_args: 4, max_args: 4, },
  { name: "fclose", return_type: int_ty(), min_args: 1, max_args: 1, },
  { name: "feof", return_type: int_ty(), min_args: 1, max_args: 1, },
  { name: "fgets", return_type: char_ptr(), min_args: 3, max_args: 3, },
  { name: "fputs", return_type: int_ty(), min_args: 2, max_args: 2, },
  { name: "fgetc", return_type: int_ty(), min_args: 1, max_args: 1, },
  { name: "fputc", return_type: int_ty(), min_args: 2, max_args: 2, },
  { name: "fseek", return_type: int_ty(), min_args: 3, max_args: 3, },
  { name: "ftell", return_type: int_ty(), min_args: 1, max_args: 1, },
  { name: "rewind", return_type: void_ty(), min_args: 1, max_args: 1, },
  // —— 特殊臂（visit_call 内联；qsort 用户重定义优先——检查逻辑在
  //    typeck 包，签名数据在此）——
  { name: "qsort", return_type: void_ty(), min_args: 4, max_args: 4, },
  { name: "bsearch", return_type: void_ptr(), min_args: 5, max_args: 5, },
]

///|
/// 按名查签名（typeck builtin 分派的数据入口）。
pub fn lookup(name : String) -> LibcSig? {
  for sig in libc_table {
    if sig.name == name {
      return Some(sig)
    }
  }
  None
}

///|
/// builtin 放行名全集（175 名 = Rust `is_builtin_func` 判据逐名照搬：
/// host_func_id 109 路由名 ∪ BYTECODE_LIBC_ALL_FUNCS 88 名，重叠 22）。
/// 含 C++ 容器 mangled 名（vitro_*__* / __ctor__vitro_* 等 ~64 名）——
/// **判据语义照搬**（C 模式下不活跃，收录不引入 C++ 依赖；剔除反而
/// 会在 S9 C++ 片补漏）。`print_int` 不在此集（Rust host_func_id 无此
/// 名——它只在 visit_call 检查臂；调用放行靠 funcs 表等其他判据）。
let builtin_all : Set[String] = Set([
  "__ctor__vitro_list_int", "__ctor__vitro_list_int__move", "__ctor__vitro_list_node__int__move",
  "__ctor__vitro_string", "__ctor__vitro_string__move", "__ctor__vitro_vec_char",
  "__ctor__vitro_vec_char__move", "__ctor__vitro_vec_float", "__ctor__vitro_vec_float__move",
  "__ctor__vitro_vec_int", "__ctor__vitro_vec_int__move", "__dtor__vitro_list_int",
  "__dtor__vitro_string", "__dtor__vitro_vec_char", "__dtor__vitro_vec_float", "__dtor__vitro_vec_int",
  "__vitro_assert_fail", "__vitro_force_instantiate_vitro_sort_int", "__vitro_output",
  "__vitro_step", "__vitro_va_arg", "__vitro_va_copy", "__vitro_va_end", "__vitro_va_start",
  "abort", "abs", "acos", "asin", "atan", "atan2", "atof", "atoi", "atol", "bsearch",
  "calloc", "ceil", "clearerr", "clock", "cos", "cosh", "exit", "exp", "fabs", "fclose",
  "feof", "fflush", "fgetc", "fgets", "floor", "fmod", "fopen", "fprintf", "fputc",
  "fputs", "fread", "free", "fseek", "ftell", "fwrite", "getchar", "isalnum", "isalpha",
  "isblank", "iscntrl", "isdigit", "isgraph", "islower", "isprint", "ispunct", "isspace",
  "isupper", "isxdigit", "labs", "llabs", "log", "log10", "malloc", "memchr", "memcmp",
  "memcpy", "memmove", "memset", "perror", "pow", "printf", "putchar", "puts", "qsort",
  "rand", "realloc", "remove", "rename", "rewind", "round", "scanf", "sin", "sinh",
  "snprintf", "sprintf", "sqrt", "srand", "sscanf", "strcat", "strchr", "strcmp",
  "strcpy", "strcspn", "strdup", "strerror", "strlen", "strncat", "strncmp", "strncpy",
  "strpbrk", "strrchr", "strspn", "strstr", "strtod", "strtol", "tan", "tanh", "time",
  "tolower", "toupper", "ungetc", "unreachable", "vitro_list_int__back", "vitro_list_int__clear",
  "vitro_list_int__front", "vitro_list_int__get", "vitro_list_int__pop_back", "vitro_list_int__pop_front",
  "vitro_list_int__push_back", "vitro_list_int__push_front", "vitro_list_int__size",
  "vitro_sort_int__int", "vitro_sort_int_qsort__int", "vitro_sort_int_swap__int",
  "vitro_string__back", "vitro_string__c_str", "vitro_string__capacity", "vitro_string__clear",
  "vitro_string__front", "vitro_string__get", "vitro_string__pop_back", "vitro_string__pop_front",
  "vitro_string__push_back", "vitro_string__size", "vitro_vec_char__back", "vitro_vec_char__capacity",
  "vitro_vec_char__clear", "vitro_vec_char__front", "vitro_vec_char__get", "vitro_vec_char__pop_back",
  "vitro_vec_char__pop_front", "vitro_vec_char__push_back", "vitro_vec_char__size",
  "vitro_vec_float__back", "vitro_vec_float__capacity", "vitro_vec_float__clear",
  "vitro_vec_float__front", "vitro_vec_float__get", "vitro_vec_float__pop_back",
  "vitro_vec_float__pop_front", "vitro_vec_float__push_back", "vitro_vec_float__size",
  "vitro_vec_int__back", "vitro_vec_int__capacity", "vitro_vec_int__clear", "vitro_vec_int__front",
  "vitro_vec_int__get", "vitro_vec_int__pop_back", "vitro_vec_int__pop_front", "vitro_vec_int__push_back",
  "vitro_vec_int__size",
])

///|
/// 是否 builtin 函数（**调用放行判据**——Rust `is_builtin_func` 同构，
/// typeck expr/call.rs:49 的四判据之一："这个名字是已知可调用"。
/// **S4 归属**（审阅 F2 修正：原登记"随 S5/S6"错误——消费点是 typeck
/// 自身的调用解析，缺口的纯 C 名 sqrt/pow/memcpy/ctype 族等 54 个会在
/// 无头文件存根路径下误拒）。
pub fn is_libc_func(name : String) -> Bool {
  builtin_all.contains(name)
}
