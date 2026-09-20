///|
/// 隐式转换判据与可赋值性（照搬 Rust `convert.rs`——C 子集）。
///
/// **C++ 分支剔除登记**（C AST 不产对应节点，分支不命中即等价；S9 裁定
/// 批随 C++ 片补回）：Reference/RValueRef 绑定分支（check_assignable 前段）、
/// `is_upcast` 单继承链回溯（classes 表不存在，恒 false）、RValueRef 隐式
/// 移动构造。其余逐字照搬。
///
/// **函数式重建**：Rust 的 `insert_implicit_cast(&mut expr, target)` 就地
/// 改写，本包为 `insert_implicit_cast(expr, target) -> Expr` 返回新树
///（Cast 包裹或 FloatLiteral 重定型）——E4 面保证等价。

///|
/// (from, to) 类型对 → 是否允许隐式转换及转换后目标类型（12 臂判据表，
/// B6 白盒锚的来源——Rust `implicit_cast_target` 同构；引用类型不参与
/// 隐式标量转换）。
pub fn implicit_cast_target(from : @ast.Type, to : @ast.Type) -> @ast.Type? {
  let fk = from.kind()
  let tk = to.kind()
  if fk is TK_Reference ||
    fk is TK_RValueRef ||
    tk is TK_Reference ||
    tk is TK_RValueRef {
    return None
  }
  match (fk, tk) {
    (TK_Int, TK_Double)
    | (TK_Char, TK_Double)
    | (TK_Float, TK_Double)
    | (TK_LongLong, TK_Double) => Some(Double(false))
    (TK_Double, TK_Int) => Some(Int(to.is_unsigned(), false))
    (TK_Double, TK_Char) => Some(Char(false, false))
    (TK_Double, TK_Float) => Some(Float(false))
    (TK_Double, TK_LongLong) => Some(LongLong(to.is_unsigned(), false))
    (TK_Int, TK_Float) | (TK_Char, TK_Float) | (TK_LongLong, TK_Float) =>
      Some(Float(false))
    (TK_Float, TK_Int) => Some(Int(to.is_unsigned(), false))
    (TK_Float, TK_Char) => Some(Char(false, false))
    (TK_Float, TK_LongLong) => Some(LongLong(to.is_unsigned(), false))
    (TK_Int, TK_LongLong) | (TK_Char, TK_LongLong) =>
      Some(LongLong(to.is_unsigned(), false))
    (TK_LongLong, TK_Int) => Some(Int(to.is_unsigned(), false))
    (TK_LongLong, TK_Char) => Some(Char(false, false))
    _ => None
  }
}

///|
/// 插入隐式转换（函数式重建）：FloatLiteral→double 特例不插 Cast 只
/// 重定型字面量类型；其余命中转换表的包 Cast 节点。
pub fn insert_implicit_cast(expr : @ast.Expr, target : @ast.Type) -> @ast.Expr {
  let current_ty = expr.ty()
  if target.kind() is TK_Double {
    match expr {
      FloatLiteral(v, loc, _) => return FloatLiteral(v, loc, Double(false))
      _ => ()
    }
  }
  match implicit_cast_target(current_ty, target) {
    Some(target_ty) => Cast(expr, target_ty, expr.loc(), target_ty)
    None => expr
  }
}

///|
/// 可变参数实参默认提升（C 标准：float→double、char→int）。
pub fn apply_default_argument_promotions(expr : @ast.Expr) -> @ast.Expr {
  let tk = expr.ty().kind()
  if tk is TK_Float {
    insert_implicit_cast(expr, Double(false))
  } else if tk is TK_Char {
    insert_implicit_cast(expr, Int(false, false))
  } else {
    expr
  }
}

///|
pub fn TypeChecker::is_int(self : TypeChecker, t : @ast.Type) -> Bool {
  ignore(self)
  t.kind() is TK_Int || t.kind() is TK_Char
}

///|
pub fn TypeChecker::is_scalar(self : TypeChecker, t : @ast.Type) -> Bool {
  ignore(self)
  let k = t.kind()
  k is TK_Int ||
  k is TK_Char ||
  k is TK_Float ||
  k is TK_Double ||
  k is TK_LongLong
}

///|
pub fn TypeChecker::is_comparable(
  self : TypeChecker,
  a : @ast.Type,
  b : @ast.Type,
) -> Bool {
  ignore(self)
  let ak = a.kind()
  let bk = b.kind()
  let a_num = ak is TK_Int || ak is TK_Char || ak is TK_Float || ak is TK_Double
  let b_num = bk is TK_Int || bk is TK_Char || bk is TK_Float || bk is TK_Double
  if a_num && b_num {
    return true
  }
  if ak is TK_Pointer && bk is TK_Pointer {
    return true
  }
  if ak is TK_Pointer && bk is TK_Array {
    return true
  }
  if ak is TK_Array && bk is TK_Pointer {
    return true
  }
  if ak is TK_Pointer && bk is TK_Int {
    return true
  }
  if ak is TK_Int && bk is TK_Pointer {
    return true
  }
  false
}

///|
/// 数组/指针赋值兼容（多维数组 decay、元素类型一致、dims 前缀兼容——
/// 仅 target 正数维须相等）。
fn TypeChecker::check_array_pointer_assignable(
  self : TypeChecker,
  target : @ast.Type,
  value : @ast.Type,
) -> Bool {
  ignore(self)
  match (target, value) {
    (Pointer(t_pointee, _), Array(v_element, _, _, _, _, _)) => {
      if @ast.type_eq(t_pointee, v_element) {
        return true
      }
      // 多维数组 decay：int arr[3][3] -> int (*)[3]
      if @ast.type_eq(t_pointee, value.subscript_type()) {
        return true
      }
      false
    }
    (Array(t_element, _, _, _, _, _), Pointer(v_pointee, _)) =>
      @ast.type_eq(t_element, v_pointee)
    (Array(t_element, _, t_dims, _, _, _), Array(v_element, _, v_dims, _, _, _)) => {
      if !@ast.type_eq(t_element, v_element) {
        return false
      }
      let check_count = if t_dims.length() < v_dims.length() {
        t_dims.length()
      } else {
        v_dims.length()
      }
      let mut dims_compatible = true
      for i in 0..<check_count {
        if t_dims[i] > 0 && t_dims[i] != v_dims[i] {
          dims_compatible = false
          break
        }
      }
      dims_compatible
    }
    _ => false
  }
}

///|
/// 函数指针赋值兼容（签名逐参+返回值判等；不完全匹配放行但报 W3053；
/// 通用指针↔函数指针互转放行——void* 桥接 + W3055 提示）。
fn TypeChecker::check_function_pointer_assignable(
  self : TypeChecker,
  target : @ast.Type,
  value : @ast.Type,
  loc : @source.SourceLoc,
) -> Bool {
  let t_fp = is_function_pointer(target)
  let v_fp = is_function_pointer(value)
  if t_fp && v_fp {
    let exact = match (target, value) {
      (Pointer(t_pointee, _), Pointer(v_pointee, _)) =>
        match (t_pointee, v_pointee) {
          (Function(t_ret, t_params, _, _), Function(v_ret, v_params, _, _)) => {
            let mut ok = t_params.length() == v_params.length()
            if ok {
              for i in 0..<t_params.length() {
                if !@ast.type_eq(t_params[i], v_params[i]) {
                  ok = false
                  break
                }
              }
            }
            ok && @ast.type_eq(t_ret, v_ret)
          }
          _ => false
        }
      _ => false
    }
    if exact {
      return true
    }
    self.report_warning(
      "函数指针类型不完全匹配，赋值可能存在风险",
      loc,
      W3053_ImplicitScalarConversion,
    )
    return true
  }
  if target.kind() is TK_Pointer && v_fp {
    return true
  }
  if t_fp && value.kind() is TK_Pointer {
    self.report_warning(
      "将通用指针赋值给函数指针，建议显式转换",
      loc,
      W3055_VoidPointerCast,
    )
    return true
  }
  false
}

///|
/// 标量赋值兼容（5 类标量互转放行；窄化报 W3053、提升报 H3057——
/// W0-4 char 窄化的调用方豁免走 char_narrow_suppress 显式上下文）。
fn TypeChecker::check_scalar_assignable(
  self : TypeChecker,
  target : @ast.Type,
  value : @ast.Type,
  loc : @source.SourceLoc,
) -> Bool {
  let tk = target.kind()
  let vk = value.kind()
  let t_scalar = tk is TK_Int ||
    tk is TK_Char ||
    tk is TK_Float ||
    tk is TK_Double ||
    tk is TK_LongLong
  if !t_scalar {
    return false
  }
  let v_scalar = vk is TK_Int ||
    vk is TK_Char ||
    vk is TK_Float ||
    vk is TK_Double ||
    vk is TK_LongLong
  if !v_scalar {
    return false
  }
  // 窄化警告（可能丢失精度）
  if tk is TK_Char &&
    (vk is TK_Int || vk is TK_Float || vk is TK_Double || vk is TK_LongLong) {
    // W0-4：初始化器路径的 char 窄化由调用方判定无损时豁免
    //（char_narrow_suppress 显式上下文——§⑤-8 形态）
    if !self.char_narrow_suppress {
      self.report_warning(
        "被隐式转换为 char，可能会丢失精度。",
        loc,
        W3053_ImplicitScalarConversion,
      )
    }
  }
  if tk is TK_Int && (vk is TK_Float || vk is TK_Double || vk is TK_LongLong) {
    // 此处 value.to_c_string() 的 Typeof 分叉（ast 渲染 "typeof(<expr>)"
    // vs Rust Display 的 "typeof({:?})"）当前**不可达**：前置守卫已排除
    // 非 5 标量 kind（Typeof→TK_Auto）；若未来新增消费者到达 Typeof，
    // 须先修 ast 渲染形态（审阅 F8③ 登记）
    self.report_warning(
      "\{value.to_c_string()} 被隐式转换为 int，可能会丢失精度。",
      loc,
      W3053_ImplicitScalarConversion,
    )
  }
  if tk is TK_Float && (vk is TK_Double || vk is TK_LongLong) {
    self.report_warning(
      "double 被隐式转换为 float，可能会丢失精度。",
      loc,
      W3053_ImplicitScalarConversion,
    )
  }
  // 安全提升提示
  if tk is TK_Int && vk is TK_Char {
    self.report_hint(
      "char 被隐式提升为 int。",
      loc,
      H3057_ImplicitConversionHint,
    )
  }
  if tk is TK_Float && (vk is TK_Int || vk is TK_Char) {
    let src = if vk is TK_Char { "char" } else { "int" }
    self.report_hint(
      "\{src} 被隐式提升为 float。",
      loc,
      H3057_ImplicitConversionHint,
    )
  }
  if tk is TK_Double &&
    (vk is TK_Int || vk is TK_Char || vk is TK_Float || vk is TK_LongLong) {
    let src = match vk {
      TK_Char => "char"
      TK_Float => "float"
      TK_LongLong => "long long"
      _ => "int"
    }
    self.report_hint(
      "\{src} 被隐式提升为 double。",
      loc,
      H3057_ImplicitConversionHint,
    )
  }
  true
}

///|
/// 指针赋值兼容（整数→指针 W3054；任意指针/数组→void* H3057；指针间
/// pointee 不一致 W3067（P1-6：向上转型豁免属 C++，C 子集不适用——
/// 剔除登记）；const 丢失 W3053）。
fn TypeChecker::check_pointer_assignable(
  self : TypeChecker,
  target : @ast.Type,
  value : @ast.Type,
  loc : @source.SourceLoc,
) -> Bool {
  let tk = target.kind()
  let vk = value.kind()
  if tk is TK_Pointer && vk is TK_Int {
    self.report_warning(
      "整数被隐式转换为指针。建议确保这是有意义的地址值（如 NULL = 0）。",
      loc,
      W3054_IntToPointerCast,
    )
    return true
  }
  // C 标准：任意指针或数组都可隐式转换为 void*
  if tk is TK_Pointer {
    match target {
      Pointer(pointee, _) =>
        if pointee is Void(_) && (vk is TK_Pointer || vk is TK_Array) {
          self.report_hint(
            "具体指针类型被隐式转换为 void*。",
            loc,
            H3057_ImplicitConversionHint,
          )
          return true
        }
      _ => ()
    }
  }
  if tk is TK_Pointer && vk is TK_Pointer {
    match (target, value) {
      (Pointer(t_pointee, t_const), Pointer(v_pointee, v_const)) => {
        if v_pointee is Void(_) {
          self.report_hint(
            "void* 被隐式转换为具体指针类型。",
            loc,
            H3057_ImplicitConversionHint,
          )
        } else if !@ast.type_eq(t_pointee, v_pointee) {
          // P1-6 向上转型豁免（is_upcast）属 C++ 单继承链——C 子集剔除
          self.report_warning(
            "指针类型不兼容：\{t_pointee.name()}* ← \{v_pointee.name()}*，需要显式转换（向上转型 Derived* → Base* 除外）。",
            loc,
            W3067_PointerTypeMismatch,
          )
        }
        if v_const && !t_const {
          self.report_warning(
            "将 const 指针赋值给非 const 指针，可能通过后者修改 const 数据。",
            loc,
            W3053_ImplicitScalarConversion,
          )
        }
      }
      _ => ()
    }
    return true
  }
  false
}

///|
/// 可赋值性总入口（判等 → 数组/指针 → 函数指针 → 标量 → 指针；
/// Reference/RValueRef 绑定前段为 C++ 分支剔除登记）。
pub fn TypeChecker::check_assignable(
  self : TypeChecker,
  target : @ast.Type,
  value : @ast.Type,
  loc : @source.SourceLoc,
) -> Bool {
  if @ast.type_eq(target, value) {
    return true
  }
  if self.check_array_pointer_assignable(target, value) {
    return true
  }
  if self.check_function_pointer_assignable(target, value, loc) {
    return true
  }
  if self.check_scalar_assignable(target, value, loc) {
    return true
  }
  if self.check_pointer_assignable(target, value, loc) {
    return true
  }
  false
}

///|
/// 是否函数指针形态（Pointer 包 Function）。
fn is_function_pointer(ty : @ast.Type) -> Bool {
  match ty {
    Pointer(pointee, _) => pointee is Function(_, _, _, _)
    _ => false
  }
}

///|
pub fn TypeChecker::get_struct_field_type(
  self : TypeChecker,
  struct_name : String,
  field_name : String,
) -> @ast.Type? {
  match self.structs.get(struct_name) {
    Some(sym) => {
      for pair in sym.fields {
        if pair.1 == field_name {
          return Some(pair.0)
        }
      }
      None
    }
    None => None
  }
}

///|
pub fn TypeChecker::get_union_field_type(
  self : TypeChecker,
  union_name : String,
  field_name : String,
) -> @ast.Type? {
  match self.unions.get(union_name) {
    Some(sym) => {
      for pair in sym.fields {
        if pair.1 == field_name {
          return Some(pair.0)
        }
      }
      None
    }
    None => None
  }
}
