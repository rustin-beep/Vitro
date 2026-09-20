///|
/// 初始化器形状检查（照搬 Rust `init.rs` + `expr/literal.rs` 的
/// resolve_compound_literal；**函数式重建**：InitList 的 elements 数组
/// 引用语义原地改写元素值，节点类型/尺寸推断经返回值回传——包括
/// CompoundLiteral 节点内 target_type 的推断回写，E4 面对齐）。
///
/// 尺寸推断口径（U1#12）：仅"未指定尺寸"（哨兵 -1 / array_size<=0）可由
/// 初始化器推断；多维路径的 `total_elems` 在 dims 改写**前**取值——
/// Rust 同序照搬（现状口径，非修正项）。

///|
/// struct 初始化器检查：designators（.field）与位置初始化两轨 +
/// 嵌套 struct/数组字段递归。返回改写后的 init（元素插 Cast）。
pub fn TypeChecker::check_struct_initializer(
  self : TypeChecker,
  struct_type : @ast.Type,
  init : @ast.Expr,
  loc : @source.SourceLoc,
) -> @ast.Expr {
  // 复合字面量 (struct S){...} 等价于其初始化列表
  match init {
    CompoundLiteral(target_type, inner, cl_loc, cl_ty) => {
      if !@ast.type_eq(target_type, struct_type) {
        self.report_error(
          "复合字面量类型 '\{target_type.to_c_string()}' 与目标结构体类型 '\{struct_type.to_c_string()}' 不匹配",
          loc,
          E3006_ArrayInitTypeMismatch,
        )
        return init
      }
      let new_inner = self.check_struct_initializer(struct_type, inner, loc)
      CompoundLiteral(target_type, new_inner, cl_loc, cl_ty)
    }
    InitList(elements, iloc, ity) => {
      let fields : Array[(@ast.Type, String)] = match
        self.structs.get(struct_type.name()) {
        Some(s) => s.fields
        None => {
          self.report_error(
            "未知的结构体类型 '\{struct_type.name()}'",
            loc,
            E3004_TypeMismatch,
          )
          return init
        }
      }
      let has_designators = elements.exists(e => e.designators.length() > 0)
      if has_designators {
        for i in 0..<elements.length() {
          let elem = elements[i]
          if elem.designators.length() == 0 {
            self.report_error(
              "初始化列表中不能混合使用指定初始化和非指定初始化",
              loc,
              E3005_ArrayInitTooMany,
            )
            continue
          }
          if elem.designators.length() != 1 {
            self.report_error(
              "暂不支持多级 designated initializer",
              loc,
              E3005_ArrayInitTooMany,
            )
            continue
          }
          match elem.designators[0] {
            Field(field_name) => {
              let field_idx = find_field(fields, field_name)
              match field_idx {
                Some(idx) => {
                  let field_ty = fields[idx].0
                  let new_value = self.check_field_value(
                    field_ty,
                    field_name,
                    elem.value,
                    loc,
                  )
                  elements[i] = { ..elem, value: new_value, }
                }
                None =>
                  self.report_error(
                    "结构体 '\{struct_type.name()}' 没有字段 '\{field_name}'",
                    loc,
                    E3042_UnknownMember,
                  )
              }
            }
            _ =>
              self.report_error(
                "结构体初始化只能使用 .field 形式的 designator",
                loc,
                E3005_ArrayInitTooMany,
              )
          }
        }
        return init
      }
      if elements.length() > fields.length() {
        self.report_error(
          "初始化列表元素数量超过结构体字段数",
          loc,
          E3005_ArrayInitTooMany,
        )
      }
      for i in 0..<elements.length() {
        if i >= fields.length() {
          break
        }
        let elem = elements[i]
        let new_value = self.check_field_value(
          fields[i].0,
          fields[i].1,
          elem.value,
          loc,
        )
        elements[i] = { ..elem, value: new_value, }
      }
      InitList(elements, iloc, ity)
    }
    _ => {
      // 非 InitList：按整体赋值检查
      let (init_type, new_init) = self.resolve_expr_type(init)
      if !self.check_assignable(struct_type, init_type, loc) {
        self.report_error(
          "类型不匹配：无法将 '\{init_type.to_c_string()}' 赋值给 '\{struct_type.to_c_string()}'",
          loc,
          E3004_TypeMismatch,
        )
      }
      new_init
    }
  }
}

///|
/// struct 字段值检查（designated 与位置路径共用：嵌套 struct/数组字段
/// 递归，标量字段 resolve + 可赋值检查 + 隐式转换插入；E3006 文案带
/// 字段名——两路径同文案照搬）。
fn TypeChecker::check_field_value(
  self : TypeChecker,
  field_ty : @ast.Type,
  field_name : String,
  value : @ast.Expr,
  loc : @source.SourceLoc,
) -> @ast.Expr {
  if field_ty.kind() is TK_Struct && value is InitList(_, _, _) {
    self.check_struct_initializer(field_ty, value, loc)
  } else if field_ty.is_array() && value is InitList(_, _, _) {
    // sub_ty 的尺寸推断结果随节点类型走（调用方存根类型不更新——
    // Rust `let mut sub_ty = field_ty.clone()` 局部可变，同语义）
    let (_, new_value) = self.check_array_initializer(field_ty, value, loc)
    new_value
  } else {
    let (e_type, new_value) = self.resolve_expr_type(value)
    if !self.check_assignable(field_ty, e_type, loc) {
      self.report_error(
        "结构体初始化类型不匹配：字段 '\{field_name}' 期望 '\{field_ty.to_c_string()}'，实际 '\{e_type.to_c_string()}'",
        loc,
        E3006_ArrayInitTypeMismatch,
      )
      new_value
    } else {
      insert_implicit_cast(new_value, field_ty)
    }
  }
}

///|
/// 按字段名查位置。
fn find_field(fields : Array[(@ast.Type, String)], name : String) -> Int? {
  for i in 0..<fields.length() {
    if fields[i].1 == name {
      return Some(i)
    }
  }
  None
}

///|
/// 多维数组嵌套初始化列表校验（括号省略放行 + 扁平标量按行主序填充；
/// 返回 (是否合法, 改写后 init)）。
fn TypeChecker::validate_nested_init_list(
  self : TypeChecker,
  dims : Array[Int],
  init : @ast.Expr,
  loc : @source.SourceLoc,
  element_type : @ast.Type,
) -> (Bool, @ast.Expr) {
  if dims.length() == 0 {
    if element_type.kind() is TK_Struct && init is InitList(_, _, _) {
      let new_init = self.check_struct_initializer(element_type, init, loc)
      return (true, new_init)
    }
    if element_type.is_array() && init is InitList(_, _, _) {
      let (_, new_init) = self.check_array_initializer(element_type, init, loc)
      return (true, new_init)
    }
    let (e_type, new_init) = self.resolve_expr_type(init)
    if !self.check_assignable(element_type, e_type, loc) {
      self.report_error(
        "数组初始化元素类型不匹配：期望 '\{element_type.to_c_string()}'，实际 '\{e_type.to_c_string()}'",
        loc,
        E3006_ArrayInitTypeMismatch,
      )
      return (false, new_init)
    }
    (true, insert_implicit_cast(new_init, element_type))
  } else {
    match init {
      InitList(elements, iloc, ity) => {
        // 若当前层级遇到纯扁平标量列表（如 int a[2][3] = {1,2,3,4,5,6}），
        // 允许元素数量达到当前子数组最深层元素总数，按行主序填充
        let is_flat_scalar = !elements.exists(e => e.value is InitList(_, _, _))
        let expected_count : Int = if dims[0] > 0 {
          if is_flat_scalar && dims.length() > 1 {
            let mut product = 1
            for d in dims {
              product *= d
            }
            product
          } else {
            dims[0]
          }
        } else {
          elements.length()
        }
        if elements.length() > expected_count {
          self.report_error(
            "初始化列表元素数量超过数组维度大小",
            loc,
            E3005_ArrayInitTooMany,
          )
        }
        let sub_dims : Array[Int] = dims[1:].to_owned()
        for i in 0..<elements.length() {
          let elem = elements[i]
          let (ok, new_value) = self.validate_nested_init_list(
            sub_dims,
            elem.value,
            loc,
            element_type,
          )
          elements[i] = { ..elem, value: new_value, }
          if !ok {
            return (false, InitList(elements, iloc, ity))
          }
        }
        (true, InitList(elements, iloc, ity))
      }
      _ => {
        // C/C++ 允许括号省略：标量可用于初始化当前子数组的第一个元素，
        // 其余零填充。例如 int a[5][5] = {0}; int b[2][3] = {1, 2};
        let (e_type, new_init) = self.resolve_expr_type(init)
        if self.check_assignable(element_type, e_type, loc) {
          return (true, insert_implicit_cast(new_init, element_type))
        }
        self.report_error(
          "多维数组初始化需要嵌套初始化列表",
          loc,
          E3009_InvalidArrayInit,
        )
        (false, new_init)
      }
    }
  }
}

///|
/// 数组初始化器检查（一维/多维两轨 + designators([index]) + 字符串
/// 字面量轨）。返回 (推断尺寸后的类型, 改写后 init)。
pub fn TypeChecker::check_array_initializer(
  self : TypeChecker,
  arr_type : @ast.Type,
  init : @ast.Expr,
  loc : @source.SourceLoc,
) -> (@ast.Type, @ast.Expr) {
  // 复合字面量 (T[]){...} 等价于其初始化列表；target_type（节点内字段）
  // 随递归推断回写重建
  match init {
    CompoundLiteral(target_type, inner, cl_loc, cl_ty) => {
      if !target_type.is_array() {
        self.report_error(
          "复合字面量类型 '\{target_type.to_c_string()}' 不是数组类型",
          loc,
          E3006_ArrayInitTypeMismatch,
        )
        return (arr_type, init)
      }
      // 先递归检查内部初始化列表，让未指定大小的数组（如 int[]）推断出长度
      let (new_target, new_inner) = self.check_array_initializer(
        target_type, inner, loc,
      )
      let new_cl = @ast.Expr::CompoundLiteral(
        new_target, new_inner, cl_loc, cl_ty,
      )
      if !@ast.type_eq(new_target, arr_type) {
        self.report_error(
          "复合字面量类型 '\{new_target.to_c_string()}' 与目标数组类型 '\{arr_type.to_c_string()}' 不匹配",
          loc,
          E3006_ArrayInitTypeMismatch,
        )
        return (arr_type, new_cl)
      }
      return (arr_type, new_cl)
    }
    _ => ()
  }
  let elem_type = arr_type.base_element_type()
  let dims = arr_type.dims()
  // 多维数组
  if dims.length() > 1 {
    match init {
      InitList(elements, _, _) => {
        let has_designators = elements.exists(e => e.designators.length() > 0)
        if has_designators {
          self.report_error(
            "多维数组暂不支持 designated initializer",
            loc,
            E3009_InvalidArrayInit,
          )
          return (arr_type, init)
        }
        let total_elems = arr_type.total_elements()
        // U1#12：仅"未指定尺寸"（哨兵 -1）可由初始化器推断——显式 0/负
        // 尺寸由 check_array_dims_legality 报错，这里不兜底吞掉
        match arr_type {
          Array(element, _, a_dims, is_const, is_vla, vla_dims) => {
            let new_dims = a_dims.copy()
            if new_dims[0] == -1 {
              new_dims[0] = elements.length()
            }
            let new_ty = @ast.Type::Array(
              element, total_elems, new_dims, is_const, is_vla, vla_dims,
            )
            let (_, new_init) = self.validate_nested_init_list(
              new_dims, init, loc, elem_type,
            )
            return (new_ty, new_init)
          }
          _ => ()
        }
      }
      _ => {
        let (init_type, new_init) = self.resolve_expr_type(init)
        self.report_error(
          "多维数组初始化必须使用嵌套初始化列表，不能是 '\{init_type.to_c_string()}'",
          loc,
          E3009_InvalidArrayInit,
        )
        return (arr_type, new_init)
      }
    }
    return (arr_type, init)
  }
  // 一维
  match init {
    InitList(elements, iloc, ity) => {
      let has_designators = elements.exists(e => e.designators.length() > 0)
      if has_designators {
        for i in 0..<elements.length() {
          let elem = elements[i]
          if elem.designators.length() == 0 {
            self.report_error(
              "初始化列表中不能混合使用指定初始化和非指定初始化",
              loc,
              E3005_ArrayInitTooMany,
            )
            continue
          }
          if elem.designators.length() != 1 {
            self.report_error(
              "暂不支持多级 designated initializer",
              loc,
              E3005_ArrayInitTooMany,
            )
            continue
          }
          match elem.designators[0] {
            Index(idx_expr) => {
              let (_, new_idx) = self.resolve_expr_type(idx_expr)
              let idx_ty = new_idx.ty()
              if !self.is_int(idx_ty) {
                self.report_error(
                  "数组索引必须是 int 类型",
                  loc,
                  E3039_ArrayIndexType,
                )
              }
              let (e_type, new_value) = self.resolve_expr_type(elem.value)
              // W0-4：同普通列表路径的 char 窄化豁免
              let suppress = elem_type.kind() is TK_Char &&
                is_char_safe_initializer(new_value)
              if suppress {
                self.char_narrow_suppress = true
              }
              let ok = self.check_assignable(elem_type, e_type, loc)
              if suppress {
                self.char_narrow_suppress = false
              }
              if !ok {
                self.report_error(
                  "数组初始化元素类型不匹配：期望 '\{elem_type.to_c_string()}'，实际 '\{e_type.to_c_string()}'",
                  loc,
                  E3006_ArrayInitTypeMismatch,
                )
                elements[i] = { ..elem, value: new_value, }
              } else {
                elements[i] = {
                  ..elem,
                  value: insert_implicit_cast(new_value, elem_type),
                }
              }
            }
            _ =>
              self.report_error(
                "数组初始化只能使用 [index] 形式的 designator",
                loc,
                E3005_ArrayInitTooMany,
              )
          }
        }
        return (arr_type, InitList(elements, iloc, ity))
      }
      // 尺寸推断（哨兵 -1 / 非正 array_size → 元素数）
      let mut expected_size = arr_type.array_size()
      let new_ty : @ast.Type = if expected_size <= 0 {
        expected_size = elements.length()
        match arr_type {
          Array(element, _, a_dims, is_const, is_vla, vla_dims) => {
            let new_dims = a_dims.copy()
            if new_dims.length() > 0 {
              new_dims[0] = expected_size
            }
            Array(element, expected_size, new_dims, is_const, is_vla, vla_dims)
          }
          _ => arr_type
        }
      } else {
        arr_type
      }
      if elements.length() > expected_size {
        self.report_error(
          "初始化列表元素数量超过数组大小",
          loc,
          E3005_ArrayInitTooMany,
        )
      }
      for i in 0..<elements.length() {
        let elem = elements[i]
        let new_value = self.check_array_elem_value(elem_type, elem.value, loc)
        elements[i] = { ..elem, value: new_value, }
      }
      (new_ty, InitList(elements, iloc, ity))
    }
    StringLiteral(value, sloc, sty) => {
      if !(elem_type.kind() is TK_Char) {
        self.report_error(
          "字符串字面量只能用于初始化 char 数组",
          loc,
          E3007_StringInitNonCharArray,
        )
        return (arr_type, init)
      }
      // P4：C 语义字节长度（\xHH >= 0x80 转义单字节）
      let str_len = c_string_len(value)
      if arr_type.array_size() <= 0 {
        // 仅回写 array_size（Rust 同形——dims 不动）
        match arr_type {
          Array(element, _, a_dims, is_const, is_vla, vla_dims) =>
            (
              @ast.Type::Array(
                element,
                str_len + 1,
                a_dims,
                is_const,
                is_vla,
                vla_dims,
              ),
              StringLiteral(value, sloc, sty),
            )
          _ => (arr_type, init)
        }
      } else if str_len + 1 > arr_type.array_size() {
        self.report_error(
          "字符串字面量长度超过数组大小",
          loc,
          E3008_StringTooLong,
        )
        (arr_type, init)
      } else {
        (arr_type, init)
      }
    }
    _ => {
      let (init_type, new_init) = self.resolve_expr_type(init)
      self.report_error(
        "数组初始化必须使用初始化列表或字符串字面量，不能是 '\{init_type.to_c_string()}'",
        loc,
        E3009_InvalidArrayInit,
      )
      (arr_type, new_init)
    }
  }
}

///|
/// 一维数组元素值检查（struct/数组元素递归，标量 W0-4 + E3006/插 Cast）。
fn TypeChecker::check_array_elem_value(
  self : TypeChecker,
  elem_type : @ast.Type,
  value : @ast.Expr,
  loc : @source.SourceLoc,
) -> @ast.Expr {
  if elem_type.kind() is TK_Struct && value is InitList(_, _, _) {
    self.check_struct_initializer(elem_type, value, loc)
  } else if elem_type.is_array() && value is InitList(_, _, _) {
    let (_, new_value) = self.check_array_initializer(elem_type, value, loc)
    new_value
  } else {
    let (e_type, new_value) = self.resolve_expr_type(value)
    // W0-4：char 元素的字符常量/值域内整常量初始化是 C 惯用写法，豁免窄化警告
    let suppress = elem_type.kind() is TK_Char &&
      is_char_safe_initializer(new_value)
    if suppress {
      self.char_narrow_suppress = true
    }
    let ok = self.check_assignable(elem_type, e_type, loc)
    if suppress {
      self.char_narrow_suppress = false
    }
    if !ok {
      self.report_error(
        "数组初始化元素类型不匹配：期望 '\{elem_type.to_c_string()}'，实际 '\{e_type.to_c_string()}'",
        loc,
        E3006_ArrayInitTypeMismatch,
      )
      new_value
    } else {
      insert_implicit_cast(new_value, elem_type)
    }
  }
}

///|
/// 复合字面量 `(T){...}` 解析（Rust `resolve_compound_literal` 同构：
/// Struct/Array 转初始化器检查；标量五类单元素；其余 E1006）。
/// 返回 (定型类型 = target_type 推断后, 改写后节点)。
fn TypeChecker::resolve_compound_literal(
  self : TypeChecker,
  target_type : @ast.Type,
  init : @ast.Expr,
  loc : @source.SourceLoc,
) -> (@ast.Type, @ast.Expr) {
  match target_type.kind() {
    TK_Struct => {
      let new_init = self.check_struct_initializer(target_type, init, loc)
      (
        target_type,
        @ast.Expr::CompoundLiteral(target_type, new_init, loc, target_type),
      )
    }
    TK_Array => {
      let (t, i) = self.check_array_initializer(target_type, init, loc)
      (t, @ast.Expr::CompoundLiteral(t, i, loc, t))
    }
    TK_Int | TK_Char | TK_Float | TK_Double | TK_LongLong | TK_Pointer => {
      let new_init : @ast.Expr = match init {
        InitList(elements, _, _) =>
          if elements.length() != 1 {
            self.report_error(
              "标量复合字面量初始化列表只能有一个元素",
              loc,
              E3009_InvalidArrayInit,
            )
            init
          } else {
            let elem = elements[0]
            let (e_type, new_value) = self.resolve_expr_type(elem.value)
            if !self.check_assignable(target_type, e_type, loc) {
              self.report_error(
                "标量复合字面量类型不匹配：期望 '\{target_type.to_c_string()}'，实际 '\{e_type.to_c_string()}'",
                loc,
                E3006_ArrayInitTypeMismatch,
              )
              elements[0] = { ..elem, value: new_value, }
              init
            } else {
              elements[0] = {
                ..elem,
                value: insert_implicit_cast(new_value, target_type),
              }
              init
            }
          }
        _ => {
          self.report_error(
            "标量复合字面量必须使用 { value } 形式",
            loc,
            E3009_InvalidArrayInit,
          )
          init
        }
      }
      (
        target_type,
        @ast.Expr::CompoundLiteral(target_type, new_init, loc, target_type),
      )
    }
    _ => {
      self.report_error(
        "复合字面量暂不支持类型 '\{target_type.to_c_string()}'",
        loc,
        E1006_UnsupportedFeature,
      )
      (
        target_type,
        @ast.Expr::CompoundLiteral(target_type, init, loc, target_type),
      )
    }
  }
}
