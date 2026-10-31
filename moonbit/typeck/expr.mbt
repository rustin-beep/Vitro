///|
/// 表达式类型解析 + lowering（照搬 Rust `expr/{mod,var,literal,cast}.rs`
/// 的 C 部分；**函数式重建**：visitor 值进值出 `resolve_expr_type(Expr)
/// -> (Type, Expr)`——返回定型类型与改写后子树，父节点重建携带）。
///
/// 接线状态（T5-b/c/d 后）：Offsetof 前置 lowering / Identifier / Index /
/// Member / Literal 族 / InitList / Sizeof / Alignof / Cast / 运算符族
///（Binary/Ternary/Unary/Assign/_Generic）/ **Call/CallPtr**（call.mbt）
/// 与 **CompoundLiteral**（init.mbt）已全量。
/// 未接线变体直通（typed_ast 原样、不检查）：C++ 五变体（This/
/// MemberCall/New/Delete/Move/Lambda，S9）。
/// 剔除登记（C++ 分支，C AST 不产即等价）：identifier 的隐式 this->field
/// 改写、Reference/RValueRef 脱糖、member 的 class 字段与访问控制。

///|
/// C usual arithmetic conversions（C11 §6.3.1.8）：两个标量提升到公共
/// 类型（rank：double 4 / float 3 / long long 2 / int 1 / char 0；
/// char 提升为 int——Rust `promote_type` 骨架）。
/// 病 30 修正（#61 第一梯队，2026-10-11）：lower 的 unsigned 只在
/// **同 rank** 时传播——rank 低于 int 的小无符号（unsigned char）先整型
/// 提升为 signed int（int 装得下其全值域），unsigned 位随之消失；
/// signed 高 rank 能表示 unsigned 低 rank 全值域时取 signed（本仓类型面
/// i64 ⊇ u32 恒成立，故 uint vs LL → signed LL）。
fn promote_type(a : @ast.Type, b : @ast.Type) -> @ast.Type {
  fn rank(t : @ast.Type) -> Int32 {
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
  // 同 rank 才看 lower 的 unsigned（char 级提升丢；跨 rank 由 higher 定）
  let is_unsigned = higher.is_unsigned() ||
    (lower.is_unsigned() && rank(lower) == rank(higher))
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
      // 病 67（#71 P2，2026-10-16）：member-designator 点链逐段解析——
      // "inner.name" 先按首段在 struct 字段表定位子类型、再对子类型解析
      // 余段（union 段偏移 0）。下标形态（arr[2].x）parser 侧不支持。
      let segs = field.split(".").collect()
      let first : String = segs[0].to_owned()
      let mut cur_ty : @ast.Type? = None
      match self.structs.get(type_name) {
        Some(struct_sym) => {
          for pair in struct_sym.fields {
            if pair.1 == first {
              found = true
              cur_ty = Some(pair.0)
              break
            }
            offset += self.compute_type_size(pair.0)
          }
          if !found {
            self.report_error(
              "结构体 '\{type_name}' 没有字段 '\{first}'",
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
                if pair.1 == first {
                  hit = true
                  cur_ty = Some(pair.0)
                  break
                }
              }
              if !hit {
                self.report_error(
                  "联合体 '\{type_name}' 没有字段 '\{first}'",
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
      // 余段沿子类型链（struct 段累加偏移、union 段恒 0）
      if found && segs.length() > 1 {
        for k = 1; k < segs.length(); k = k + 1 {
          let seg : String = segs[k].to_owned()
          guard cur_ty is Some(t) else { break }
          let base = t.name()
          let mut seg_found = false
          match self.structs.get(base) {
            Some(st) =>
              for pair in st.fields {
                if pair.1 == seg {
                  seg_found = true
                  cur_ty = Some(pair.0)
                  break
                }
                offset += self.compute_type_size(pair.0)
              }
            None =>
              match self.unions.get(base) {
                Some(un) =>
                  for pair in un.fields {
                    if pair.1 == seg {
                      seg_found = true
                      cur_ty = Some(pair.0)
                      break
                    }
                  }
                None => ()
              }
          }
          if !seg_found {
            self.report_error(
              "offsetof 成员链 '\{field}' 在段 '\{seg}' 处解析失败",
              loc,
              E3042_UnknownMember,
            )
            break
          }
        }
      }
      let ty = @ast.Type::int()
      (ty, Literal(offset, loc, ty))
    }
    Identifier(name, loc, id_ty) => self.resolve_identifier(name, loc, id_ty)
    Index(array, index, loc, _) => self.resolve_index(array, index, loc)
    Member(object, member_name, is_arrow, loc, _) =>
      self.resolve_member(object, member_name, is_arrow, loc)
    Literal(_, _, ty) => (self.resolve_literal_ty(ty), expr)
    FloatLiteral(_, _, ty) => (self.resolve_float_literal_ty(ty), expr)
    // 病 117（≡59）：保留节点自带类型——u 后缀值域定型（uint 域/ULL）的
    // typeck 半边；此前一律重定型有符号 long_long 丢 unsigned 信息。
    LongLiteral(_, _, ty) => (ty, expr)
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
    Call(name, args, loc, _) => {
      let ty = self.resolve_call(name, args, loc)
      (ty, Call(name, args, loc, ty))
    }
    CallPtr(callee, args, loc, _) => {
      let (ty, new_callee) = self.resolve_call_ptr(callee, args, loc)
      (ty, CallPtr(new_callee, args, loc, ty))
    }
    CompoundLiteral(target_type, init, loc, _) =>
      self.resolve_compound_literal(target_type, init, loc)
    // —— 未接线变体直通（C++ 五变体 This/MemberCall/New/Delete/Move/
    // Lambda，S9 裁定批）——
    _ => (expr.ty(), expr)
  }
}

///|
/// 标识符解析（变量查表 + static 跨文件可见性 + 函数名→函数指针 +
/// __func__ 预定义标识符 + 未声明 E3023）。ty 写入重建节点——**除
/// __func__**：Rust var.rs:58-67 该分支提前 return 跳过末尾的 `*ty =
/// result` 写回（节点 ty 保持 parser 占位，E4 面照搬现状；返回值类型
/// 仍供父节点定型）。
fn TypeChecker::resolve_identifier(
  self : TypeChecker,
  name : String,
  loc : @source.SourceLoc,
  orig_ty : @ast.Type,
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
            } else {
              // #50 批①（2026-10-10）：前向序——同文件内使用点早于首次
              // 声明 = 对齐 Clang use-before-declaration（E3058 同款）
              match self.static_global_decl_lines.get(name) {
                Some(dl) =>
                  if loc.line < dl {
                    self.report_error(
                      "static 全局变量 '\{name}' 在声明之前被使用（第 \{dl} 行才声明）",
                      loc,
                      E3059_StaticGlobalAccess,
                    )
                  }
                None => ()
              }
            }
          None => ()
        }
      }
      // #337（2026-10-28）：非 static 全局的函数体前向引用守卫——Pass
      // 2.5 全量登记后 lookup_var 命中后文声明的符号，C11 6.2.1p4 声明
      // 点之前不可见（clang use of undeclared identifier）。仅在
      // static_init_site_idx 为 None 的语境激活（函数体 / auto·typeof
      // 预解析）——文件作用域初始化器语境由 #331 的
      // diagnose_static_init 窄口负责，两守卫分治防双报；static 面走
      // E3059 通道不进此臂；局部符号（非 _is_global）由 scope 栈内层
      // 先行命中天然放行。extern/tentative 先行条目是首值，正常通过。
      if !sym.is_static && sym._is_global && self.static_init_site_idx is None {
        // PR #344 审阅 P2-1（2026-10-28）：(line, column) 文本位置序
        //——行号严格小于在单行程序失效（同行按列判前向）
        match self.global_decl_lines.get(name) {
          Some((dl, dc)) =>
            if loc.line < dl || (loc.line == dl && loc.column < dc) {
              self.report_error(
                "未声明的标识符 '\{name}'（其首次声明位于第 \{dl} 行，在本引用点之后——C 标识符自声明点起才可见）",
                loc,
                E3023_UndeclaredVar,
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
        Some(sym) => {
          // #337（2026-10-28，PR #339 审阅 P3-2 挂账销案）：函数名**作值**
          // 前向引用——`int (*fp)(void) = f;`（f 后文声明）clang 报 use
          // of undeclared identifier（作值面无隐式声明回退）。调用面是
          // W3085 warning（#214 教学口径拍板，Call 的 callee 不走此臂，
          // 不双报）；原型先行则首声明位置（Pass 2 首值）在前放行。
          // PR #344 审阅 P2-1：列级判定（同行形态收口）
          if loc.line < sym.first_decl_line ||
            (loc.line == sym.first_decl_line && loc.column < sym.first_decl_col) {
            self.report_error(
              "未声明的标识符 '\{name}'（函数 '\{name}' 的首次声明位于第 \{sym.first_decl_line} 行，在本引用点之后——请前置原型或调整定义顺序）",
              loc,
              E3023_UndeclaredVar,
            )
          }
          // 函数名作值使用（函数指针）
          @ast.Type::function_pointer(sym.return_type, sym.param_types)
        }
        None =>
          // issue #5 销案（2026-10-06）：static 函数名作值（`int (*fp)(int)
          // = helper;`）——static 注册在 static_func_sigs（funcs miss 后
          // 补查；旧直接 E3023「未声明的变量」）。同文件可见性检查豁免
          //（E3058 检查在声明消费侧，值使用侧不重复）；前向序是 #337
          // 新增维度（#5 销案时不存在），连坐补上——static 函数作值同样
          // 无隐式声明回退
          match self.static_func_sigs.get(name) {
            Some(sym) => {
              // #337：static 函数名作值前向守卫（首声明位置首值 =
              // 原型或定义条目；跨文件可见性仍归调用面 E3058 不在此报；
              // PR #344 审阅 P2-1 列级判定）
              if loc.line < sym.first_decl_line ||
                (
                  loc.line == sym.first_decl_line &&
                  loc.column < sym.first_decl_col
                ) {
                self.report_error(
                  "未声明的标识符 '\{name}'（static 函数 '\{name}' 的首次声明位于第 \{sym.first_decl_line} 行，在本引用点之后——请前置原型或调整定义顺序）",
                  loc,
                  E3023_UndeclaredVar,
                )
              }
              @ast.Type::function_pointer(sym.return_type, sym.param_types)
            }
            None =>
              // 隐式 this->field 改写（C++ name hiding——剔除登记，S9）
              if name == "__func__" {
                // C99 __func__（E1 B 档）：按 const char 数组定型（退化语义
                // 同字符串字面量）；值由 codegen 发射当前函数名。名字长度
                // 运行期才定，占位即可。**ty 不写回**（提前 return 照搬——
                // E4 dump 节点保持占位 Void）
                let n = name.length()
                let arr = @ast.Type::Array(
                  Char(false, false),
                  n,
                  [n],
                  true,
                  false,
                  [],
                )
                return (arr, Identifier(name, loc, orig_ty))
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
  // #156（2026-10-18，gcc/clang 同口径实测）：register 数组的任何下标
  // 使用都隐含数组退化 = 对 register 对象取址（clang 22 / gcc 对
  // `register int a[3]; a[0] = 5;` 一律 error "address of register
  // variable requested"）。隐式退化到指针赋值（q = a）在 convert 层，
  // 登记为已知边界（issue #156 评论）
  match array {
    Identifier(name, iloc, _) =>
      match self.lookup_var(name) {
        Some(sym) =>
          if sym.is_register {
            self.report_error(
              "不能对 register 数组 '\{name}' 使用下标（下标隐含数组退化 = 对 register 对象取地址，C 标准禁止）",
              iloc,
              E3078_RegisterAddrOf,
            )
          }
        None => ()
      }
    _ => ()
  }
  let (arr_type, new_array) = self.resolve_expr_type(array)
  let (idx_type, new_index) = self.resolve_expr_type(index)
  // #75 缺口 1（2026-10-12）：索引整型判定用宽版（C11 6.5.2.1 整数类型
  // 含 LL——旧窄版 is_int 排除 TK_LongLong 致 LL 下标 E3039 假阳性且
  // 多级下标级联 E3040；type_is_int_or_ll 为同包既有宽版单源）
  let ty : @ast.Type = if !type_is_int_or_ll(idx_type) {
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
    // #50 批①（2026-10-10）：常数下标静态越界——对齐 Clang -Warray-bounds
    //（默认启）：常量下标且尺寸已知（array_size ≥ 0 且非 VLA）时判定值域；
    // 负值同报（#50 审阅 P2-3 修复：取值走 const_int_value——`a[-1]` 的
    // -1 是 Unary(Neg, Literal)，原仅匹配 Literal 使负值臂不可达）。
    // 变量下标/不定长数组留运行时检查（E3070 族）；Binary 常量结构
    //（1+2 形态）值域不比（求值面留白除零）
    match arr_type {
      Array(_, n, _, _, is_vla, _) =>
        if !is_vla && n >= 0 {
          match const_int_value(new_index) {
            Some(v) =>
              if v < 0 {
                self.report_warning(
                  "数组下标为负数 \{v}（有效索引从 0 开始）。",
                  loc,
                  W3051_ArrayBoundOffByOne,
                )
              } else if v >= n {
                self.report_warning(
                  "数组下标 \{v} 越界：数组只有 \{n} 个元素，有效索引是 0~\{n - 1}。",
                  loc,
                  W3051_ArrayBoundOffByOne,
                )
              }
            None => ()
          }
        }
      _ => ()
    }
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
/// #134（2026-10-17）：运算符一致性检查——`->` 要求指针左操作数、
/// `.` 要求 struct/union 左操作数；旧两运算符同落 Member 无标记，
/// `r->id`（r 非指针）按 `.` 处理、`p.id`（p 指针）按 `->` 处理，
/// 双向零诊断放行（clang 均 error：member reference type ... is not
/// a pointer / not a structure）。报错后按 int 定型继续（E3041 同构）。
fn TypeChecker::resolve_member(
  self : TypeChecker,
  object : @ast.Expr,
  member_name : String,
  is_arrow : Bool,
  loc : @source.SourceLoc,
) -> (@ast.Type, @ast.Expr) {
  let (obj_type, new_object) = self.resolve_expr_type(object)
  let obj_kind = obj_type.kind()
  // #134 运算符一致性：先于目标判定报（E3041）——is_arrow 与左操作数
  // 指针性必须一致；报错后仍走既有 target 判定降级路径（int 定型续检）
  if is_arrow && !(obj_kind is TK_Pointer) {
    let kind_str = if obj_kind is TK_Struct || obj_kind is TK_Union {
      "结构体/联合体"
    } else {
      "非指针"
    }
    self.report_error(
      "'->' 要求指针左操作数，但左侧是\{kind_str}类型（是否要用 '.'？）",
      loc,
      E3041_MemberNonStruct,
    )
  } else if !is_arrow && obj_kind is TK_Pointer {
    self.report_error(
      "'.' 要求结构体/联合体左操作数，但左侧是指针（是否要用 '->'？）",
      loc,
      E3041_MemberNonStruct,
    )
  }
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
        @ast.Expr::Member(
          new_object,
          member_name,
          is_arrow,
          loc,
          @ast.Type::int(),
        ),
      )
    }
  }
  let field_type = if is_union {
    self.get_union_field_type(type_name, member_name)
  } else {
    self.get_struct_field_type(type_name, member_name)
  }
  // 匿名成员穿透（issue #7 销案，2026-10-06）：C11 匿名 struct/union 成员
  //（字段名空串）的成员可经外层直接访问（s.a）——直查 miss 时递归匿名字段
  let field_type = match field_type {
    Some(_) => field_type
    None => self.find_anonymous_member(type_name, is_union, member_name, 0)
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
  // 审阅 P1-c③（2026-10-14）：const 对象的成员访问继承 const 位
  //（C11 6.5.2.5p5——const struct S s 的 s.m 也是不可修改左值；
  // `const struct S s={1}; s.m=9;` 旧只判成员自身 const 位=漏检）。
  // #194 N-1（2026-10-21）：const 继承补指针形态——`const struct S *p`
  // 的 p->x 同为不可修改左值（clang "cannot assign ... with
  // const-qualified type"）。P1-c③ 当年注「指针形态已在 pointee 位上
  // 天然覆盖」实为无代码的空声明（is_const 查的是指针自身位）——本条
  // 补 pointee 下钻。
  let base_is_const = if obj_type.is_const() {
    true
  } else {
    match obj_type {
      Pointer(pointee, _) => pointee.is_const()
      _ => false
    }
  }
  let ty : @ast.Type = if base_is_const && !ty.is_const() {
    mark_member_const(ty)
  } else {
    ty
  }
  (ty, Member(new_object, member_name, is_arrow, loc, ty))
}

///|
/// 顶层标 const 位（审阅 P1-c③——值域不变只置限定符）。
fn mark_member_const(t : @ast.Type) -> @ast.Type {
  match t {
    Void(_) => Void(true)
    Int(u, _) => Int(u, true)
    Char(u, _) => Char(u, true)
    Float(_) => Float(true)
    Double(_) => Double(true)
    LongLong(u, _) => LongLong(u, true)
    Pointer(p, _) => Pointer(p, true)
    _ => t
  }
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
/// 字符串字面量定型 char 数组（ds 批 2026-10-31：尺寸口径与字节产出层
/// 同源 = 整串 UTF-8（`@util.utf8_len`，#66 连坐完）——旧私有 Latin-1
/// 混合口径（≤0xFF 计 1）与 bytecode 包 cstring_bytes（UTF-8 全编码，
/// \xff 落 C3 BF 双字节）失配，char 数组定型尺寸少 1 ⇒ NUL 终止符被
/// 挤出 ⇒ strlen/printf("%s") 越界读（亲验 len=20 vs clang 9）；+1 NUL）。
/// **等价约束（审阅批 2026-10-31 P3-1）**：本处 `@util.utf8_len` 与
/// bytecode 包的 `cstring_len`（分配/对齐计算用）是「同实现两符号」——
/// 语义上恒等（整串 UTF-8 字节数），typeck 不能 import bytecode
/// （L5→L6 反向依赖），故各自显式调 `@util.utf8_len`；改任何一侧的
/// 口径 = 重新制造两层失配（ds 批修复的就是这个），连带锚：
/// typeck `string_literal_byte_len` / 语料 `string_escape_nul_term.c`。
fn TypeChecker::resolve_string_literal(
  self : TypeChecker,
  value : String,
  loc : @source.SourceLoc,
) -> (@ast.Type, @ast.Expr) {
  ignore(self)
  let array_size = @util.utf8_len(value) + 1
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
/// #145（2026-10-18）：`sizeof(struct S)` 显式类型形态查完整性报
/// E3076（clang "invalid application of 'sizeof' to an incomplete
/// type"）；`sizeof(s)` 表达式形态不查——变量声明处已报（clang
/// error recovery 后不双报，同口径）。
fn TypeChecker::resolve_sizeof(
  self : TypeChecker,
  target_type : @ast.Type?,
  operand : @ast.Expr?,
  loc : @source.SourceLoc,
) -> (@ast.Type, @ast.Expr) {
  match target_type {
    Some(t) => self.check_type_complete(t, loc)
    None => ()
  }
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

///|
/// 匿名成员穿透查找（issue #7）：先查本层匿名字段（name == ""）的聚合
/// 类型内成员，递归深度上限 8（防御循环定义）。返回穿透命中的成员类型。
fn TypeChecker::find_anonymous_member(
  self : TypeChecker,
  type_name : String,
  is_union : Bool,
  member_name : String,
  depth : Int32,
) -> @ast.Type? {
  if depth >= 8 {
    return None
  }
  let table = if is_union { self.unions } else { self.structs }
  match table.get(type_name) {
    Some(sym) => {
      for pair in sym.fields {
        if pair.1 == "" {
          // 匿名字段：在其聚合类型内递归查找（含同名直查与再穿透）
          let inner_ty = pair.0
          let inner_kind = inner_ty.kind()
          if inner_kind is TK_Struct || inner_kind is TK_Union {
            let inner_name = inner_ty.name()
            let hit = if inner_kind is TK_Union {
              match self.get_union_field_type(inner_name, member_name) {
                Some(ft) => Some(ft)
                None =>
                  self.find_anonymous_member(
                    inner_name,
                    true,
                    member_name,
                    depth + 1,
                  )
              }
            } else {
              match self.get_struct_field_type(inner_name, member_name) {
                Some(ft) => Some(ft)
                None =>
                  self.find_anonymous_member(
                    inner_name,
                    false,
                    member_name,
                    depth + 1,
                  )
              }
            }
            match hit {
              Some(ft) => return Some(ft)
              None => ()
            }
          }
        }
      }
      None
    }
    None => None
  }
}
