///|
/// bytecode libc 签名表（Rust `vitro_runtime::bytecode_libc_sig` 逐条
/// 照搬）——typeck `check_user_func` 第四级回退的消费面：名字既不在
/// 用户 funcs 也不在 static 表时，按此表做参数数量/类型检查并放行。
///
/// **与 `libc_table` 的关系（O6 四套真相源现状照搬）**：本表与签名单表
/// 是 Rust 侧两张**独立维护且互相冲突**的表（N4 漂移：strcpy 族此处
/// void、单表 char*）——差分对拍期照搬不私改，单源收编随 S5/S6 回填
/// 义务（见 libc.mbt 包注释边界登记）。
///
/// C 面活跃条目：ctype 11 名 / abs / atoi / srand / rand / strlen /
/// strcmp / strcpy / strcat / strncpy / memcpy / memmove（头文件存根
/// 未声明时的隐式调用防线）；其余为 C++ 容器 mangled 名——判据语义
/// 照搬（C 模式不活跃，收录不引入 C++ 依赖）。

///|
/// 便捷构造（int/void/char/float 与对应指针——表内多处使用）。
fn i_ty() -> @ast.Type {
  Int(false, false)
}

///|
fn v_ty() -> @ast.Type {
  Void(false)
}

///|
fn c_ty() -> @ast.Type {
  Char(false, false)
}

///|
fn f_ty() -> @ast.Type {
  Float(false)
}

///|
fn i_ptr() -> @ast.Type {
  Pointer(Int(false, false), false)
}

///|
fn f_ptr() -> @ast.Type {
  Pointer(Float(false), false)
}

///|
fn c_ptr() -> @ast.Type {
  Pointer(Char(false, false), false)
}

///|
fn v_ptr() -> @ast.Type {
  Pointer(Void(false), false)
}

///|
/// 返回 bytecode libc 函数签名 (return_type, param_types)；未知名 None。
pub fn bytecode_libc_sig(name : String) -> (@ast.Type, Array[@ast.Type])? {
  match name {
    // list<int>（Stage 2b mangled 方法名）
    "vitro_list_int__push_back" | "vitro_list_int__push_front" =>
      Some((v_ty(), [i_ptr(), i_ty()]))
    "vitro_list_int__pop_back"
    | "vitro_list_int__pop_front"
    | "vitro_list_int__clear"
    | "__dtor__vitro_list_int" => Some((v_ty(), [i_ptr()]))
    "vitro_list_int__size" | "vitro_list_int__front" | "vitro_list_int__back" =>
      Some((i_ty(), [i_ptr()]))
    "vitro_list_int__get" => Some((i_ty(), [i_ptr(), i_ty()]))
    // sort
    "vitro_sort_int_swap" => Some((v_ty(), [i_ptr(), i_ptr()]))
    "vitro_sort_int_qsort" => Some((v_ty(), [i_ptr(), i_ty(), i_ty()]))
    "vitro_sort_int" => Some((v_ty(), [i_ptr(), i_ty()]))
    // string（Stage 2b mangled 方法名；pop_back/front/back 取元素 char，
    // pop_front/clear/dtor 为 void——逐条照搬）
    "vitro_string__push_back" => Some((v_ty(), [v_ptr(), c_ty()]))
    "vitro_string__pop_back" | "vitro_string__front" | "vitro_string__back" =>
      Some((c_ty(), [v_ptr()]))
    "vitro_string__pop_front"
    | "vitro_string__clear"
    | "__dtor__vitro_string" => Some((v_ty(), [v_ptr()]))
    "vitro_string__size" | "vitro_string__capacity" => Some((i_ty(), [v_ptr()]))
    "vitro_string__get" => Some((c_ty(), [v_ptr(), i_ty()]))
    "vitro_string__c_str" => Some((c_ptr(), [v_ptr()]))
    // vec<char>（Stage 2b mangled 方法名）
    "vitro_vec_char__push_back" => Some((v_ty(), [c_ptr(), c_ty()]))
    "vitro_vec_char__pop_back"
    | "vitro_vec_char__front"
    | "vitro_vec_char__back" => Some((c_ty(), [c_ptr()]))
    "vitro_vec_char__pop_front"
    | "vitro_vec_char__clear"
    | "__dtor__vitro_vec_char" => Some((v_ty(), [c_ptr()]))
    "vitro_vec_char__size" | "vitro_vec_char__capacity" =>
      Some((i_ty(), [c_ptr()]))
    "vitro_vec_char__get" => Some((c_ty(), [c_ptr(), i_ty()]))
    // vec<float>（Stage 2b mangled 方法名）
    "vitro_vec_float__push_back" => Some((v_ty(), [f_ptr(), f_ty()]))
    "vitro_vec_float__pop_back"
    | "vitro_vec_float__front"
    | "vitro_vec_float__back" => Some((f_ty(), [f_ptr()]))
    "vitro_vec_float__pop_front"
    | "vitro_vec_float__clear"
    | "__dtor__vitro_vec_float" => Some((v_ty(), [f_ptr()]))
    "vitro_vec_float__size" | "vitro_vec_float__capacity" =>
      Some((i_ty(), [f_ptr()]))
    "vitro_vec_float__get" => Some((f_ty(), [f_ptr(), i_ty()]))
    // vec<int>（Stage 2b mangled 方法名）
    "vitro_vec_int__push_back" => Some((v_ty(), [i_ptr(), i_ty()]))
    "vitro_vec_int__pop_back"
    | "vitro_vec_int__front"
    | "vitro_vec_int__back" => Some((i_ty(), [i_ptr()]))
    "vitro_vec_int__pop_front"
    | "vitro_vec_int__clear"
    | "__dtor__vitro_vec_int" => Some((v_ty(), [i_ptr()]))
    "vitro_vec_int__size" | "vitro_vec_int__capacity" =>
      Some((i_ty(), [i_ptr()]))
    "vitro_vec_int__get" => Some((i_ty(), [i_ptr(), i_ty()]))
    // ctype
    "isdigit"
    | "isalpha"
    | "islower"
    | "isupper"
    | "isspace"
    | "isalnum"
    | "isprint"
    | "iscntrl"
    | "isxdigit"
    | "tolower"
    | "toupper" => Some((i_ty(), [i_ty()]))
    // misc
    "abs" => Some((i_ty(), [i_ty()]))
    "atoi" => Some((i_ty(), [c_ptr()]))
    "srand" => Some((v_ty(), [i_ty()]))
    "rand" => Some((i_ty(), []))
    "strlen" => Some((i_ty(), [c_ptr()]))
    "strcmp" => Some((i_ty(), [c_ptr(), c_ptr()]))
    "strcpy" | "strcat" => Some((v_ty(), [c_ptr(), c_ptr()]))
    "strncpy" => Some((v_ty(), [c_ptr(), c_ptr(), i_ty()]))
    "memcpy" | "memmove" => Some((v_ty(), [v_ptr(), v_ptr(), i_ty()]))
    _ => None
  }
}
