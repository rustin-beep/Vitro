// teaching/steps·render（S8 teaching 批一号）：表达式近似文本化——
// 结构比较的稳定键（features.rs:540-644 expr_to_string 照搬；穷尽 27
// 变体无兜底——新增变体编译红）。C++ 六变体照 Rust "<cpp-expr>" 占位。

///|
pub fn expr_to_string(expr : @ast.Expr) -> String {
  match expr {
    Binary(op, left, right, _, _) => {
      let op_str = match op {
        Add => "+"
        Sub => "-"
        Mul => "*"
        Div => "/"
        Mod => "%"
        Eq => "=="
        Ne => "!="
        Lt => "<"
        Le => "<="
        Gt => ">"
        Ge => ">="
        And => "&&"
        Or => "||"
        BitAnd => "&"
        BitOr => "|"
        BitXor => "^"
        Shl => "<<"
        Shr => ">>"
        Comma => ","
      }
      "\{expr_to_string(left)} \{op_str} \{expr_to_string(right)}"
    }
    Unary(op, operand, _, _) => {
      let op_str = match op {
        Neg => "-"
        Not => "!"
        BitNot => "~"
        Addr => "&"
        Deref => "*"
        PreInc => "++"
        PreDec => "--"
        PostInc => "++"
        PostDec => "--"
      }
      "\{op_str}\{expr_to_string(operand)}"
    }
    Literal(value, _, _) => "\{value}"
    FloatLiteral(value, _, _) => "\{value}"
    LongLiteral(value, _, _) => "\{value}"
    StringLiteral(value, _, _) => "\"\{value}\""
    Identifier(name, _, _) => name
    Call(name, args, _, _) => {
      let parts : Array[String] = []
      for a in args {
        parts.push(expr_to_string(a))
      }
      "\{name}(\{str_join(parts, ", ")})"
    }
    CallPtr(_, _, _, _) => "fp(...)"
    Index(array, index, _, _) =>
      "\{expr_to_string(array)}[\{expr_to_string(index)}]"
    Member(object, member, _, _) => "\{expr_to_string(object)}.\{member}"
    Assign(op, left, right, _, _) => {
      let op_str = match op {
        Assign => "="
        AddAssign => "+="
        SubAssign => "-="
        MulAssign => "*="
        DivAssign => "/="
        ModAssign => "%="
        AndAssign => "&="
        OrAssign => "|="
        XorAssign => "^="
        ShlAssign => "<<="
        ShrAssign => ">>="
      }
      "\{expr_to_string(left)} \{op_str} \{expr_to_string(right)}"
    }
    Ternary(cond, then_branch, else_branch, _, _) =>
      "\{expr_to_string(cond)} ? \{expr_to_string(then_branch)} : \{expr_to_string(else_branch)}"
    Sizeof(target_type, operand, _, _) =>
      match target_type {
        Some(t) => "sizeof(\{type_to_string(t)})"
        None =>
          match operand {
            Some(e) => "sizeof(\{expr_to_string(e)})"
            None => "sizeof"
          }
      }
    Alignof(_, _, _, _) => "alignof"
    Cast(e, target_type, _, _) =>
      "(\{type_to_string(target_type)})\{expr_to_string(e)}"
    InitList(elements, _, _) => {
      let parts : Array[String] = []
      for e in elements {
        parts.push(expr_to_string(e.value))
      }
      "{\{str_join(parts, ", ")}}"
    }
    Offsetof(target_type, field, _, _) =>
      "offsetof(\{type_to_string(target_type)}, \{field})"
    Generic(control, associations, default, _, _) => {
      let parts : Array[String] = []
      for pair in associations {
        let (ty, e) = pair
        parts.push("\{type_to_string(ty)}: \{expr_to_string(e)}")
      }
      match default {
        Some(d) => parts.push("default: \{expr_to_string(d)}")
        None => ()
      }
      "_Generic(\{expr_to_string(control)}, \{str_join(parts, ", ")})"
    }
    CompoundLiteral(target_type, init, _, _) =>
      "(\{type_to_string(target_type)})\{expr_to_string(init)}"
    This(_, _) => "this"
    MemberCall(object, method, _, _, _, _, _) =>
      "\{expr_to_string(object)}..\{method}(...)"
    New(elem_type, _, _, _, _) => "new \{type_to_string(elem_type)}"
    Delete(e, is_array, _, _) =>
      if is_array {
        "delete[] \{expr_to_string(e)}"
      } else {
        "delete \{expr_to_string(e)}"
      }
    Lambda(_, _, _, _, _, _) => "<lambda>"
    // C++ std::move 形态（Rust 侧同入 <cpp-expr> 兜底——语义占位）
    Move(_, _, _) => "std::move(...)"
  }
}

///|
/// 类型名近似文本（sizeof/cast 括号内语境——Rust `format!("{}", t)` 的
/// Display 近似：变体名首段即足够作结构比较键）。
fn type_to_string(ty : @ast.Type) -> String {
  match ty {
    Void(is_const) => if is_const { "const void" } else { "void" }
    Int(is_unsigned, is_const) => {
      let base = if is_unsigned { "unsigned int" } else { "int" }
      if is_const {
        "const \{base}"
      } else {
        base
      }
    }
    Char(is_unsigned, is_const) => {
      let base = if is_unsigned { "unsigned char" } else { "char" }
      if is_const {
        "const \{base}"
      } else {
        base
      }
    }
    Float(is_const) => if is_const { "const float" } else { "float" }
    Double(is_const) => if is_const { "const double" } else { "double" }
    LongLong(is_unsigned, is_const) => {
      let base = if is_unsigned { "unsigned long long" } else { "long long" }
      if is_const {
        "const \{base}"
      } else {
        base
      }
    }
    Pointer(pointee, is_const) => "\{type_to_string(pointee)}*"
    Array(element, _, _, is_const, _, _) =>
      if is_const {
        "const \{type_to_string(element)}[]"
      } else {
        "\{type_to_string(element)}[]"
      }
    Function(_, _, _, _) => "fn(...)"
    Struct(name, _) => name
    Union(name, _) => name
    Class(name, _) => name
    Reference(base, _) => "\{type_to_string(base)}&"
    RValueRef(base) => "\{type_to_string(base)}&&"
    Auto => "auto"
    Typeof(_, _, _) => "typeof(...)"
    TemplateId(name, _, _) => name
  }
}

///|
fn str_join(parts : Array[String], sep : String) -> String {
  let buf = StringBuilder()
  for i, p in parts {
    if i > 0 {
      buf.write_string(sep)
    }
    buf.write_string(p)
  }
  buf.to_string()
}
