///|
/// 类型 → C 声明形渲染**单源**（`to_c_string`；对齐 Rust `Display for Type`
/// 语义——MoonBit 侧禁第二轨道（Rust 侧 Display + 散点手拼的双轨教训，
/// 总计划 §5 "渲染单源"））。
///
/// 形态例：
/// - `Pointer(Char)` → `char*`
/// - `Array(Int, dims=[2,3])` → `int[2][3]`；VLA → `int[*]`
/// - `Function(Int, [Int])` → `int (*)(int)`
/// - `Struct("S")` → `struct S`
pub fn Type::to_c_string(self : Type) -> String {
  let buf = StringBuilder()
  self.render_into(buf)
  buf.to_string()
}

///|
fn Type::render_into(self : Type, buf : StringBuilder) -> Unit {
  match self {
    Void(_) => buf.write_string("void")
    // Rust Display 现状：基础类型不显示 unsigned 修饰（信息丢失为已知
    // 现状——mangle 轨道才区分 unsigned_int）。单源照搬现状，不私改。
    Int(_, _) => buf.write_string("int")
    Char(_, _) => buf.write_string("char")
    Float(_) => buf.write_string("float")
    Double(_) => buf.write_string("double")
    LongLong(_, _) => buf.write_string("long long")
    Struct(name, _) => {
      buf.write_string("struct ")
      buf.write_string(name)
    }
    Union(name, _) => {
      buf.write_string("union ")
      buf.write_string(name)
    }
    Pointer(pointee, _) => {
      pointee.render_into(buf)
      buf.write_string("*")
    }
    Array(element, array_size, dims, _, is_vla, _) => {
      element.render_into(buf)
      if is_vla {
        for _ in dims {
          buf.write_string("[*]")
        }
      } else if dims.length() > 0 {
        for d in dims {
          buf.write_string("[\{d}]")
        }
      } else if array_size > 0 {
        buf.write_string("[\{array_size}]")
      } else {
        buf.write_string("[]")
      }
    }
    Function(return_type, param_types, _, _) => {
      return_type.render_into(buf)
      buf.write_string(" (*)(")
      for i, p in param_types {
        if i > 0 {
          buf.write_string(", ")
        }
        p.render_into(buf)
      }
      buf.write_string(")")
    }
    // === C++ 新增 ===
    Class(name, _) => {
      buf.write_string("class ")
      buf.write_string(name)
    }
    Reference(base, is_const) => {
      if is_const {
        buf.write_string("const ")
      }
      base.render_into(buf)
      buf.write_string("&")
    }
    RValueRef(base) => {
      base.render_into(buf)
      buf.write_string("&&")
    }
    Auto => buf.write_string("auto")
    Typeof(_, _, _) => buf.write_string("typeof(<expr>)")
    TemplateId(base, args, _) => {
      buf.write_string(base)
      buf.write_string("<")
      for i, a in args {
        if i > 0 {
          buf.write_string(", ")
        }
        match a {
          TArg(ty) => ty.render_into(buf)
          TInt(v) => buf.write_string("\{v}")
          TExpr(_) => buf.write_string("<expr>")
        }
      }
      buf.write_string(">")
    }
  }
}

///|
/// const 前缀（Rust cst 同形）。
fn cst_prefix(is_const : Bool) -> String {
  if is_const {
    "const "
  } else {
    ""
  }
}

///|
/// Type 的显示名（Rust vitro_runtime/type_utils.rs type_display_name 逐变体
/// 照搬）——人类可读全形态渲染（const/unsigned/指针星号/数组维度/函数签名）。
/// **上提登记（2026-10-01，S8 批一号三段-a 触发）**：原 gateway/serve_memory.mbt
/// 私有实现，首个引擎侧消费者 = vm 观测面 get_variable_snapshot/get_array_snapshots
/// 的 ty/element_ty 渲染；`Type::name` 是去修饰基础名（符号表口径），形态不同不互替。
pub fn type_display_name(ty : Type) -> String {
  match ty {
    Void(is_const) => "\{cst_prefix(is_const)}void"
    Int(is_unsigned, is_const) => {
      let n = if is_unsigned { "unsigned int" } else { "int" }
      "\{cst_prefix(is_const)}\{n}"
    }
    Char(is_unsigned, is_const) => {
      let n = if is_unsigned { "unsigned char" } else { "char" }
      "\{cst_prefix(is_const)}\{n}"
    }
    Float(is_const) => "\{cst_prefix(is_const)}float"
    Double(is_const) => "\{cst_prefix(is_const)}double"
    LongLong(is_unsigned, is_const) => {
      let n = if is_unsigned { "unsigned long long" } else { "long long" }
      "\{cst_prefix(is_const)}\{n}"
    }
    Pointer(pointee, is_const) =>
      if is_const {
        "\{type_display_name(pointee)}* const"
      } else {
        "\{type_display_name(pointee)}*"
      }
    Array(element, array_size, dims, _, is_vla, _) => {
      let base = type_display_name(element)
      let mut all_pos = !dims.is_empty()
      for d in dims {
        if d <= 0 {
          all_pos = false
        }
      }
      if all_pos {
        let buf = StringBuilder()
        buf.write_string(base)
        for d in dims {
          buf.write_string("[\{d}]")
        }
        buf.to_string()
      } else if is_vla || array_size <= 0 {
        "\{base}[]"
      } else {
        "\{base}[\{array_size}]"
      }
    }
    Function(return_type, param_types, is_variadic, _) => {
      let buf = StringBuilder()
      buf.write_string(type_display_name(return_type))
      buf.write_string(" (*)(")
      let mut first = true
      for p in param_types {
        if !first {
          buf.write_string(", ")
        }
        buf.write_string(type_display_name(p))
        first = false
      }
      if is_variadic {
        if !first {
          buf.write_string(", ")
        }
        buf.write_string("...")
      }
      buf.write_string(")")
      buf.to_string()
    }
    Struct(name, is_const) => "\{cst_prefix(is_const)}struct \{name}"
    Union(name, is_const) => "\{cst_prefix(is_const)}union \{name}"
    Class(name, is_const) => "\{cst_prefix(is_const)}\{name}"
    Reference(base, is_const) =>
      "\{cst_prefix(is_const)}\{type_display_name(base)}&"
    RValueRef(base) => "\{type_display_name(base)}&&"
    Auto => "auto"
    // C 子集不可达（names/typeck 的 C 路径零产出）；渲染取基础名——
    // Rust 侧 {:?} Debug 形态在 MoonBit 无同源单点，登记形状差异
    TemplateId(base, _, is_const) => "\{cst_prefix(is_const)}\{base}"
    Typeof(_, is_const, _) => "\{cst_prefix(is_const)}typeof(...)"
  }
}

///|
/// 数组剥壳到元素基础类型（Rust vitro_ast::base_element_type 照搬）：
/// `int a[3][4]` → int；非数组原样返回。get_array_snapshots 的 element_ty
/// 渲染消费点（S8 批一号三段-a）。
pub fn base_element_type(ty : Type) -> Type {
  match ty {
    Array(element, _, _, _, _, _) => base_element_type(element)
    _ => ty
  }
}
