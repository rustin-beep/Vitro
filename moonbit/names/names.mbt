///|
/// L3 名字单源（`vitro/engine/names`）——**合成名 / mangled 名的唯一产出口**。
///
/// 架构约束（总计划 §4 L3 / typeck 勘察 §⑨-2）：parser / typeck（未来
/// codegen）共依赖本包；任何 `__ctor__` / `__dtor__` 前缀字符串只允许
/// 在本包拼接（U3#6 单源化判据：全仓仅此一处产出，前缀字面量即锚——
/// 收口后 grep 全仓 `__ctor__` 拼接应只命中本包）。
///
/// C only 视角（S4 边界）：构造/析构名全部出自 C++ 语法路径——本包在
/// S4 建骨架并收口 parser 侧既有散拼（等价重构，E1/E2 复跑验证）；
/// typeck 侧 ctor mangling（copy 特判）、单态化 InstKey→InstId 名字
/// 派生、容器名历史短名特例随 S9 C++ 裁定补全（诚实延后登记）。

///|
/// 构造名前缀（判据与产名同源——前缀分派是移植期最易漏判据，勘察
/// §③-2 S8）。
const CTOR_PREFIX : String = "__ctor__"

///|
/// 析构名前缀（与 CTOR_PREFIX 对称——dtor 族同单源）。
const DTOR_PREFIX : String = "__dtor__"

///|
/// 构造函数名（无实参形态）：`__ctor__{Class}`。
/// 覆盖：parser 类内/类外 ctor 定义名 + 零实参构造调用改写 + typeck
/// 空参 ctor 定义名（constructor_mangled_name 的空参分支）。
pub fn ctor_def_name(class : String) -> String {
  CTOR_PREFIX + class
}

///|
/// 构造调用名（带实参个数）：`__ctor__{Class}__{argc}`。
/// parser 声明/表达式上下文的 ctor 调用改写（Rust parser stmt.rs /
/// postfix.rs 现状口径逐字照搬）；与 typeck 非空参 ctor 定义名同构
///（constructor_mangled_name 的 arity 分支）。
pub fn ctor_call_name(class : String, argc : Int) -> String {
  "\{CTOR_PREFIX}\{class}__\{argc}"
}

///|
/// 拷贝构造名：`__ctor__{Class}__copy`（typeck cpp_overload.rs 现状——
/// copy 特判优先于 arity 编码）。
fn ctor_copy_name(class : String) -> String {
  "\{CTOR_PREFIX}\{class}__copy"
}

///|
/// 析构函数名：`__dtor__{Class}`。
fn dtor_name(class : String) -> String {
  DTOR_PREFIX + class
}

///|
/// 是否构造族名（前缀判据收口——typeck `__ctor__` 分派点迁入时改调
/// 本谓词，禁散写 has_prefix 字面量）。
fn is_ctor_name(name : String) -> Bool {
  name.has_prefix(CTOR_PREFIX)
}

///|
/// 是否析构族名。
fn is_dtor_name(name : String) -> Bool {
  name.has_prefix(DTOR_PREFIX)
}
