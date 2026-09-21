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
/// void 便捷构造。
fn void_ty() -> @ast.Type {
  Void(false)
}


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
