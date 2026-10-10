///|
/// 符号结构（C 子集三个；照搬 Rust `symbols.rs` 的 VarSymbol/FuncSymbol/
/// StructSymbol——MethodSig/ClassSymbol/TemplateSymbol/LambdaInfo 是 C++
/// 专属，随 S9 裁定批）。判等走字段级（Type 用 `@ast.type_eq`——ast 包
/// S1 显式判等设计，结构不 derive）。

///|
/// 变量符号。`is_global` 在 Rust 侧 `#[allow(dead_code)]`（R8 死字段债）
/// ——照搬保留字段（MoonBit 侧未消费字段的警告以 `_` 前缀消音）。
struct VarSymbol {
  ty : @ast.Type
  _is_global : Bool
  is_extern : Bool
  is_static : Bool
}

///|
/// 函数符号（param_defaults：用户参数的默认表达式，C 子集恒空数组——
/// 照搬字段形态）。
///
/// #50 对齐批①（2026-10-10）新增两字段：is_definition（body 非空 =
/// 完整定义；原型声明 false——同签名「原型+定义」合法、「定义+定义」
/// = E3003 重定义，对齐 Clang redefinition error）；first_decl_line（
/// 首次登记行号——static 符号前向序检查：使用点早于任何声明/定义且
/// 无原型 = E3058/E3059，对齐 Clang use-before-declaration）。
struct FuncSymbol {
  return_type : @ast.Type
  param_types : Array[@ast.Type]
  is_variadic : Bool
  param_defaults : Array[@ast.Expr?]
  is_definition : Bool
  first_decl_line : Int
}

///|
/// struct/union 共用符号（只有 fields，无 size/offset——布局在
/// compute_type_size 查表路径）。
struct StructSymbol {
  fields : Array[(@ast.Type, String)]
}
