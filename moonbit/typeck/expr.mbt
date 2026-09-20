///|
/// 表达式类型解析 + lowering（照搬 Rust `expr/{mod,var,literal,cast}.rs`
/// 的 C 部分；**函数式重建**：visitor 值进值出 `resolve_expr_type(Expr)
/// -> (Type, Expr)`——返回定型类型与改写后子树，父节点重建携带）。
///
/// 本批接线面：Offsetof 前置 lowering（改写为 Literal(offset)）/
/// Identifier（含 static 可见性 E3059 + 函数名→函数指针 + __func__）/
/// Index / Member / Literal 族（含 string 的 P4 字节长度）/ InitList /
/// Sizeof（含数组退化 W3052）/ Alignof / Cast（W3064）。
/// 未接线变体直通登记（typed_ast 原样、不检查）：Binary/Ternary/Unary/
/// Assign（ops.rs 随下批——promote_type 判据已备）、Call/CallPtr（call.rs
/// 下批）、Generic（ops.rs）、CompoundLiteral（依赖 init.rs 检查器，T5-c）、
/// C++ 五变体（This/MemberCall/New/Delete/Move/Lambda，S9）。
/// 剔除登记（C++ 分支，C AST 不产即等价）：identifier 的隐式 this->field
/// 改写、Reference/RValueRef 脱糖、member 的 class 字段与访问控制。

///|
/// C usual arithmetic conversions：两个标量提升到公共类型（rank：
/// double 4 / float 3 / long long 2 / int 1 / char 0；unsigned 传播；
/// char 提升为 int——Rust `promote_type` 同构）。
pub fn promote_type(a : @ast.Type, b : @ast.Type) -> @ast.Type {
  fn rank(t : @ast.Type) -> Int {
    match t.kind() {
      TK_Double => 4
      TK_Float => 3
      TK_LongLong => 2
      TK_Int => 1
      TK_Char => 0
      _ => -1
    }
  }
  let ra = rank(a)
  let rb = rank(b)
  let higher : @ast.Type = if ra >= rb { a } else { b }
  let lower : @ast.Type = if ra >= rb { b } else { a }
  let is_unsigned = higher.is_unsigned() || lower.is_unsigned()
  match higher.kind() {
    TK_Double => @ast.Type::double()
    TK_Float => @ast.Type::float()
    TK_LongLong => LongLong(is_unsigned, false)
    TK_Int => Int(is_unsigned, false)
    TK_Char => Int(false, false)
    _ => @ast.Type::int()
  }
}

///|
/// 总入口（C 子集分派）。**Offsetof 前置 lowering**：改写为
/// Literal(offset)（struct 字段偏移累计 / union 恒 0；E3042/E3004）。
pub fn TypeChecker::resolve_expr_type(
  self : TypeChecker,
  expr : @ast.Expr,
) -> (@ast.Type, @ast.Expr) {
  match expr {
    Offsetof(target_type, field, loc, _) => {
      let type_name = target_type.name()
      let mut offset = 0
      let mut found = false
      match self.structs.get(type_name) {
        Some(struct_sym) => {
          for pair in struct_sym.fields {
            if pair.1 == field {
              found = true
              break
            }
            offset += self.compute_type_size(pair.0)
          }
          if !found {
            self.report_error(
              "结构体 '\{type_name}' 没有字段 '\{field}'",
              loc,
              E3042_UnknownMember,
            )
          }
        }
        None =>
          match self.unions.get(type_name) {
            Some(union_sym) => {
              // union：所有字段偏移 0
              let mut hit = false
              for pair in union_sym.fields {
                if pair.1 == field {
                  hit = true
                  break
                }
              }
              if !hit {
                self.report_error(
                  "联合体 '\{type_name}' 没有字段 '\{field}'",
                  loc,
                  E3042_UnknownMember,
                )
              }
              offset = 0
            }
            None =>
              self.report_error(
                "未知的结构体/联合体类型 '\{type_name}'",
                loc,
                E3004_TypeMismatch,
              )
          }
      }
      let ty = @ast.Type::int()
      (ty, Literal(offset, loc, ty))
    }
    Identifier(name, loc, _) => self.resolve_identifier(name, loc)
    Index(array, index, loc, _) => self.resolve_index(array, index, loc)
    Member(object, member_name, loc, _) =>
      self.resolve_member(object, member_name, loc)
    Literal(_, _, ty) => (self.resolve_literal_ty(ty), expr)
    FloatLiteral(_, _, ty) => (self.resolve_float_literal_ty(ty), expr)
    LongLiteral(_, _, _) => (@ast.Type::long_long(), expr)
    StringLiteral(value, loc, _) => self.resolve_string_literal(value, loc)
    InitList(elements, loc, _) => self.resolve_init_list(elements, loc)
    Sizeof(target_type, operand, loc, _) =>
      self.resolve_sizeof(target_type, operand, loc)
    Alignof(target_type, operand, loc, _) =>
      self.resolve_alignof(target_type, operand, loc)
    Cast(inner, target_type, loc, _) =>
      self.resolve_cast(inner, target_type, loc)
    Binary(op, left, right, loc, _) => self.resolve_binary(op, left, right, loc)
    Ternary(cond, then_branch, else_branch, loc, _) =>
      self.resolve_ternary(cond, then_branch, else_branch, loc)
    Unary(op, operand, loc, _) => self.resolve_unary(op, operand, loc)
    Assign(op, left, right, loc, _) => self.resolve_assign(op, left, right, loc)
    Generic(control, associations, default, loc, _) =>
      self.resolve_generic(control, associations, default, loc)
    // —— 未接线变体直通（登记见文件头；红面覆盖，call 批收敛）——
    _ => (expr.ty(), expr)
  }
}

///|
/// 标识符解析（变量查表 + static 跨文件可见性 + 函数名→函数指针 +
/// __func__ 预定义标识符 + 未声明 E3023）。ty 写入重建节点。
fn TypeChecker::resolve_identifier(
  self : TypeChecker,
  name : String,
  loc : @source.SourceLoc,
) -> (@ast.Type, @ast.Expr) {
  let result : @ast.Type = match self.lookup_var(name) {
    Some(sym) => {
      if sym.is_static && sym._is_global {
        match self.static_global_files.get(name) {
          Some(files) =>
            if !files.contains(self.current_file) {
              self.report_error(
                "static 全局变量 '\{name}' 在其他文件中不可见",
                loc,
                E3059_StaticGlobalAccess,
              )
            }
          None => ()
        }
      }
      // Reference/RValueRef 表达值脱糖（C++——C 符号不产，剔除登记）
      sym.ty
    }
    None =>
      match self.funcs.get(name) {
        Some(sym) =>
          // 函数名作值使用（函数指针）
          @ast.Type::function_pointer(sym.return_type, sym.param_types)
        None =>
          // 隐式 this->field 改写（C++ name hiding——剔除登记，S9）
          if name == "__func__" {
            // C99 __func__（E1 B 档）：按 const char 数组定型（退化语义
            // 同字符串字面量）；值由 codegen 发射当前函数名。名字长度
            // 运行期才定，占位即可
            let n = name.length()
            @ast.Type::Array(Char(false, false), n, [n], true, false, [])
          } else {
            self.report_error(
              "未声明的变量 '\{name}'",
              loc,
              E3023_UndeclaredVar,
            )
            @ast.Type::int()
          }
      }
  }
  (result, Identifier(name, loc, result))
}

///|
/// 索引解析（下标 int 检查 E3039 / 非数组指针 E3040 / array→subscript、
/// pointer→pointee 定型）。
fn TypeChecker::resolve_index(
  self : TypeChecker,
  array : @ast.Expr,
  index : @ast.Expr,
  loc : @source.SourceLoc,
) -> (@ast.Type, @ast.Expr) {
  let (arr_type, new_array) = self.resolve_expr_type(array)
  let (idx_type, new_index) = self.resolve_expr_type(index)
  let ty : @ast.Type = if !self.is_int(idx_type) {
    self.report_error(
      "数组索引必须是 int 类型",
      loc,
      E3039_ArrayIndexType,
    )
    @ast.Type::int()
  } else if !arr_type.is_array() && !(arr_type.kind() is TK_Pointer) {
    self.report_error(
      "不能对非数组/指针类型进行索引",
      loc,
      E3040_IndexNonArray,
    )
    @ast.Type::int()
  } else if arr_type.is_array() {
    arr_type.subscript_type()
  } else {
    match arr_type {
      Pointer(pointee, _) => pointee
      _ => @ast.Type::int()
    }
  }
  (ty, Index(new_array, new_index, loc, ty))
}

///|
/// 成员访问（struct/union 字段查表 + 指针自动解引；E3041/E3042；
/// class 字段与访问控制为 C++ 剔除登记）。
fn TypeChecker::resolve_member(
  self : TypeChecker,
  object : @ast.Expr,
  member_name : String,
  loc : @source.SourceLoc,
) -> (@ast.Type, @ast.Expr) {
  let (obj_type, new_object) = self.resolve_expr_type(object)
  let obj_kind = obj_type.kind()
  // 目标类型名 + struct/union 判定（含指针解引；Reference 解引为 C++ 剔除；
  // E3041 报错后按 int 定型继续——Rust 同构）
  let target : (String, Bool)? = if obj_kind is TK_Struct ||
    obj_kind is TK_Union {
    Some((obj_type.name(), obj_kind is TK_Union))
  } else if obj_kind is TK_Pointer {
    match obj_type {
      Pointer(pointee, _) => {
        let pk = pointee.kind()
        if pk is TK_Struct || pk is TK_Union {
          Some((pointee.name(), pk is TK_Union))
        } else {
          None
        }
      }
      _ => None
    }
  } else {
    None
  }
  let (type_name, is_union) : (String, Bool) = match target {
    Some(v) => v
    None => {
      self.report_error(
        "'.' 和 '->' 只能用于结构体、联合体或类类型",
        loc,
        E3041_MemberNonStruct,
      )
      return (
        @ast.Type::int(),
        @ast.Expr::Member(new_object, member_name, loc, @ast.Type::int()),
      )
    }
  }
  let field_type = if is_union {
    self.get_union_field_type(type_name, member_name)
  } else {
    self.get_struct_field_type(type_name, member_name)
  }
  let ty : @ast.Type = match field_type {
    Some(ft) => ft
    None => {
      let kind_str = if is_union { "联合体" } else { "结构体" }
      self.report_error(
        "\{kind_str} '\{type_name}' 没有成员 '\{member_name}'",
        loc,
        E3042_UnknownMember,
      )
      @ast.Type::int()
    }
  }
  (ty, Member(new_object, member_name, loc, ty))
}

///|
/// 整型字面量（unsigned 保留修饰，否则 int）。
fn TypeChecker::resolve_literal_ty(
  self : TypeChecker,
  ty : @ast.Type,
) -> @ast.Type {
  ignore(self)
  if ty.is_unsigned() {
    ty
  } else {
    @ast.Type::int()
  }
}

///|
/// 浮点字面量（E1：parser 按后缀定型——无后缀 double / f·F 后缀 float；
/// 此前无条件 float 与 codegen 位宽错位，勘察 §6-2）。
fn TypeChecker::resolve_float_literal_ty(
  self : TypeChecker,
  ty : @ast.Type,
) -> @ast.Type {
  ignore(self)
  if ty.kind() is TK_Double {
    @ast.Type::double()
  } else {
    @ast.Type::float()
  }
}

///|
/// 字符串字面量（P4：C 语义字节长度——\xHH ≥ 0x80 单字节 Latin-1 通道，
/// `cstring_len` 照搬；+1 结尾 NUL）定型 char 数组。
fn TypeChecker::resolve_string_literal(
  self : TypeChecker,
  value : String,
  loc : @source.SourceLoc,
) -> (@ast.Type, @ast.Expr) {
  ignore(self)
  let array_size = c_string_len(value) + 1
  let ty = @ast.Type::Array(
    Char(false, false),
    array_size,
    [array_size],
    false,
    false,
    [],
  )
  (ty, StringLiteral(value, loc, ty))
}

///|
/// C 语义字节长度（不含结尾 NUL）——Rust `vitro_shared::cstring_len`
/// 照搬（唯一真相源约定同源：码点 ≤ 0xFF 单字节，> 0xFF 按 UTF-8；
/// 无歧义依据：源按 UTF-8 解码，多字节源字符码点必然 > 0xFF）。
fn c_string_len(s : String) -> Int {
  let mut n = 0
  for c in s {
    let cp = c.to_int()
    if cp <= 0xFF {
      n += 1
    } else if cp <= 0x7FF {
      n += 2
    } else if cp <= 0xFFFF {
      n += 3
    } else {
      n += 4
    }
  }
  n
}

///|
/// 初始化列表（逐元素解析；ty 定型 void——数组/结构体形状检查在
/// init.rs 的 check_array/struct_initializer，T5-c 接线）。
fn TypeChecker::resolve_init_list(
  self : TypeChecker,
  elements : Array[@ast.InitElement],
  loc : @source.SourceLoc,
) -> (@ast.Type, @ast.Expr) {
  for i in 0..<elements.length() {
    let (_, new_val) = self.resolve_expr_type(elements[i].value)
    elements[i] = { ..elements[i], value: new_val, }
  }
  let ty = @ast.Type::void_type()
  (ty, InitList(elements, loc, ty))
}

///|
/// sizeof（操作数解析定型 + int 结果；数组形参退化 W3052——依赖
/// current_func_params 形参名集合）。
fn TypeChecker::resolve_sizeof(
  self : TypeChecker,
  target_type : @ast.Type?,
  operand : @ast.Expr?,
  loc : @source.SourceLoc,
) -> (@ast.Type, @ast.Expr) {
  match operand {
    Some(op) => {
      let (_, new_op) = self.resolve_expr_type(op)
      match new_op {
        Identifier(name, _, _) =>
          if self.current_func_params.contains(name) {
            match self.lookup_var(name) {
              Some(sym) =>
                if sym.ty.kind() is TK_Pointer {
                  self.report_warning(
                    "数组参数已退化为指针，sizeof 结果为指针大小，而非数组总大小。",
                    loc,
                    W3052_ArrayToPointerDecay,
                  )
                }
              None => ()
            }
          }
        _ => ()
      }
      let ty = @ast.Type::int()
      (ty, Sizeof(target_type, Some(new_op), loc, ty))
    }
    None => {
      let ty = @ast.Type::int()
      (ty, Sizeof(target_type, None, loc, ty))
    }
  }
}

///|
/// C23 alignof（结果 int；对齐值由 codegen 的 type_align 计算——typeck
/// 只解析操作数并定型）。
fn TypeChecker::resolve_alignof(
  self : TypeChecker,
  target_type : @ast.Type?,
  operand : @ast.Expr?,
  loc : @source.SourceLoc,
) -> (@ast.Type, @ast.Expr) {
  let new_op = match operand {
    Some(op) => {
      let (_, o) = self.resolve_expr_type(op)
      Some(o)
    }
    None => None
  }
  let ty = @ast.Type::int()
  (ty, Alignof(target_type, new_op, loc, ty))
}

///|
/// 显式转换（ty = 目标类型；指针 ↔ 浮点互转 W3064 实现定义行为警告）。
fn TypeChecker::resolve_cast(
  self : TypeChecker,
  inner : @ast.Expr,
  target_type : @ast.Type,
  loc : @source.SourceLoc,
) -> (@ast.Type, @ast.Expr) {
  let (expr_ty, new_inner) = self.resolve_expr_type(inner)
  let target_is_ptr = target_type.kind() is TK_Pointer
  let expr_is_ptr = expr_ty.kind() is TK_Pointer
  let float_kind = (t : @ast.Type) => {
    t.kind() is TK_Float || t.kind() is TK_Double
  }
  if (target_is_ptr && float_kind(expr_ty)) ||
    (expr_is_ptr && float_kind(target_type)) {
    self.report_warning(
      "将 '\{expr_ty.to_c_string()}' 转换为 '\{target_type.to_c_string()}' 是实现定义的行为，结果可能不可移植",
      loc,
      W3064_DoublePointerCast,
    )
  }
  (target_type, Cast(new_inner, target_type, loc, target_type))
}
