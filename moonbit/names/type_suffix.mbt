///|
/// 类型 → mangled 名后缀片段（**单源**；照搬 Rust `type_mangle_suffix`
/// ——typeck cpp/methods.rs:96-130，D1 修复 2026-09-12，语义冻结）。
///
/// 此前成员函数 mangled 名只带参数个数（`{Class}__{method}__{arity}`），
/// 同参数个数仅类型不同的重载会撞名——定义处后写覆盖先写、调用点静默
/// 派发到错误实现，最终运行时"栈下溢" trap（勘察 §⑥-4 事故）。把每个
/// 参数类型编码进名字，保证不同签名 → 不同符号。
///
/// 编码（ASCII、稳定、可读）：`v`空/`i`int/`u`unsigned int/`l`long long/
/// `c`char/`f`float/`d`double/`P`+pointee/`R`+base/`S`+类名/`A`+元素/
/// `F`+返回+参数/`T`+模板/`a`auto/`y`typeof。const 不参与（顶层 const
/// 不影响重载决议，与 C++ 一致）。
///
/// 与 ast 包 `Type::mangle_name`（E5 黄金串）是**两套独立编码**：本编码
/// 服务重载决议（短码），mangle_name 服务实例化名（可读长码）——Rust
/// 侧即两处独立实现，照搬不合并（勘察 §⑤-5：Typeof 在本编码落 `y`
/// 而非打印表达式，正是 mangle_name 的 `{:?}` 缺陷被规避的正面路径）。
pub fn type_mangle_suffix(ty : @ast.Type) -> String {
  match ty {
    Void(_) => "v"
    Int(is_unsigned, _) => if is_unsigned { "u" } else { "i" }
    Char(_, _) => "c"
    Float(_) => "f"
    Double(_) => "d"
    LongLong(_, _) => "l"
    Pointer(pointee, _) => "P\{type_mangle_suffix(pointee)}"
    Reference(base, _) => "R\{type_mangle_suffix(base)}"
    RValueRef(base) => "R\{type_mangle_suffix(base)}"
    Array(element, _, _, _, _, _) => "A\{type_mangle_suffix(element)}"
    Struct(name, _) => "S\{name}"
    Union(name, _) => "S\{name}"
    Class(name, _) => "S\{name}"
    Function(return_type, param_types, _, _) => {
      let ps = StringBuilder()
      for pt in param_types {
        ps.write_string(type_mangle_suffix(pt))
      }
      "F\{type_mangle_suffix(return_type)}\{ps.to_string()}"
    }
    TemplateId(base, args, _) => {
      let as_ = StringBuilder()
      for a in args {
        match a {
          TArg(t) => as_.write_string(type_mangle_suffix(t))
          TInt(n) => as_.write_string("I\{n}")
          TExpr(_) => as_.write_string("E")
        }
      }
      "T\{base}\{as_.to_string()}"
    }
    Auto => "a"
    Typeof(_, _, _) => "y"
  }
}

///|
/// 成员函数 mangled 名单源（照搬 Rust `method_mangled_name`，cpp/methods.rs
/// 138-149）：`{Class}__{method}` 单签名 / `{Class}__{method}__{类型编码}`
/// 多签名。
///
/// `has_overloads`：该 method 名下是否有多于一个签名（决定是否带类型
/// 后缀——单签名短名兼容已落库字节码/回放基线；**沿革风险登记**：
/// 名字依赖"是否有重载"这一上下文，加重载会改全类方法名——Rust 现状
/// 口径照搬，内容派生（永远带后缀）的改造随 S9 C++ 裁定，勘察 §⑤-5）。
fn method_mangled_name(
  class_name : String,
  method_name : String,
  param_types : Array[@ast.Type],
  has_overloads : Bool,
) -> String {
  if !has_overloads {
    return "\{class_name}__\{method_name}"
  }
  let suffix = StringBuilder()
  for t in param_types {
    suffix.write_string(type_mangle_suffix(t))
  }
  "\{class_name}__\{method_name}__\{suffix.to_string()}"
}
