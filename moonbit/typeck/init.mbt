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

///|
/// #157（2026-10-18）：柔性数组成员判定——首维未知的数组成员
///（`int d[]`，dims[0] == -1 哨兵；array_prepend_dim 总落位至少一维，
/// dims 空数组形态不出现于声明符解释产物）。
fn is_flexible_array_member(ty : @ast.Type) -> Bool {
  match ty {
    Array(_, _, dims, _, _, _) => dims.length() > 0 && dims[0] == -1
    _ => false
  }
}

///|
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
      // issue #19 连带（2026-10-06）：union 变量的 InitList 初始化接入
      //（字段表按类型分派——union 用 unions 表；旧只接 struct 致
      // `union U g = {0};` 走整体赋值检查报 void 赋 union）
      let fields : Array[(@ast.Type, String)] = match
        self.structs.get(struct_type.name()) {
        Some(s) => s.fields
        None =>
          match self.unions.get(struct_type.name()) {
            Some(s) => s.fields
            None => {
              self.report_error(
                "未知的结构体或联合体类型 '\{struct_type.name()}'",
                loc,
                E3004_TypeMismatch,
              )
              return init
            }
          }
      }
      let has_designators = elements.exists(e => e.designators.length() > 0)
      if has_designators {
        // P2-3（审阅批 2026-10-23，C11 6.7.9p20 混合合法）：designator
        // 后的裸项按 cursor 续位（clang/GNU 均接受 `{.a=1, 2}`——2 落
        // a 的下一位 b；codegen 病 121 批已实现同款续位语义）——旧全量
        // W3005 误报且裸项跳检；现按续位走正常 check_field_value
        let mut cursor = 0
        for i in 0..<elements.length() {
          let elem = elements[i]
          if elem.designators.length() == 0 {
            if cursor >= fields.length() {
              self.report_warning(
                "初始化列表元素数量超过结构体字段数",
                loc,
                W3005_ArrayInitTooMany,
              )
              continue
            }
            let cur = cursor
            cursor = cur + 1
            let new_value = self.check_field_value(
              fields[cur].0,
              fields[cur].1,
              elem.value,
              loc,
            )
            elements[i] = { ..elem, value: new_value, }
            continue
          }
          if elem.designators.length() != 1 {
            self.report_warning(
              "暂不支持多级 designated initializer",
              loc,
              W3005_ArrayInitTooMany,
            )
            continue
          }
          match elem.designators[0] {
            Field(field_name) => {
              let field_idx = find_field(fields, field_name)
              match field_idx {
                Some(idx) => {
                  cursor = idx + 1
                  // #157：designated 指名柔性成员同报（位置路径对称面）
                  if is_flexible_array_member(fields[idx].0) {
                    self.report_error(
                      "柔性数组成员 '\{field_name}' 不可初始化（C23 约束——该成员只能通过运行时分配/写入使用）",
                      loc,
                      E3079_FlexibleArrayInit,
                    )
                    continue
                  }
                  let field_ty = fields[idx].0
                  let new_value = self.check_field_value(
                    field_ty,
                    field_name,
                    elem.value,
                    loc,
                  )
                  elements[i] = { ..elem, value: new_value, }
                }
                None => {
                  // #266（2026-10-22，C11 6.7.2.1p13）：designator 指名
                  // 匿名成员的内部成员（`s = {.a = 2}` 的 a 在匿名 union
                  // 内）——直查 miss 时穿透匿名聚合查找（成员访问面
                  // #7 销案同款语义）；仍 miss 才报 E3042
                  let promoted = self.find_anonymous_member(
                    struct_type.name(),
                    struct_type.kind() is TK_Union,
                    field_name,
                    0,
                  )
                  match promoted {
                    Some(ft) => {
                      let new_value = self.check_field_value(
                        ft,
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
              }
            }
            _ =>
              self.report_warning(
                "结构体初始化只能使用 .field 形式的 designator",
                loc,
                W3005_ArrayInitTooMany,
              )
          }
        }
        return init
      }
      if elements.length() > fields.length() {
        self.report_warning(
          "初始化列表元素数量超过结构体字段数",
          loc,
          W3005_ArrayInitTooMany,
        )
      }
      // #180（2026-10-18 探针第七批，C99 §6.7.9p20 brace elision）：
      // 纯标量扁平流（无子 InitList / 无 designator / 无字符串字面量）且
      // 存在聚合字段时，按字段序重组——标量字段吃 1 个、聚合字段按
      // 「叶标量总数」吃满（包成子 InitList 交既有嵌套校验路径）。
      // clang/gcc 均接受 `struct M{int d[2][3];} m = {1,2,3,4,5,6};`
      // （LLM 产出高频简洁写法）；旧按位置逐字段比对报 E3006+W3005
      // 误拒。字符串字面量不进（char[] 成员的 {"Hi"} 形态走 #75 既有
      // 路径）；带子列表/设计器不进（既有嵌套语义不受扰）。
      // 启用面（对抗批虫 β 放宽，2026-10-18）：元素 **resolve 定型后
      // 非聚合**即可组——字面量/变量/算术式（`{c,d,0,c,0,0}` 填
      // char u[2][3] 的 LLM 高频形态）；聚合值元素（#143 锚的
      // `{my_rect.tl, my_rect.br}`）仍排除。resolve 幂等且顺带回写
      // 定型（重组组内用回写后节点）。
      let can_elide = !has_designators &&
        !elements.exists(e => {
          e.value is InitList(_, _, _) ||
          e.value is StringLiteral(_, _, _) ||
          !self.is_scalar_init_expr(e.value)
        }) &&
        fields.exists(f => f.0.is_array() || f.0.kind() is TK_Struct)
      if can_elide && elements.length() > 1 {
        // 顺带回写：组内元素用 resolve 后的定型节点
        for i = 0; i < elements.length(); i = i + 1 {
          let (_, nv) = self.resolve_expr_type(elements[i].value)
          elements[i] = { ..elements[i], value: nv, }
        }
        let rebuilt : Array[@ast.InitElement] = []
        let mut pos = 0
        for f in fields {
          if pos >= elements.length() {
            break
          }
          let need = self.agg_scalar_leaf_count(f.0)
          let remaining = elements.length() - pos
          // C99 流式消耗：吃满或流尽（部分填充余下零填）——
          // min(need, 剩余)
          let take = if need > 0 && need < remaining { need } else { remaining }
          let is_aggregate = f.0.is_array() || f.0.kind() is TK_Struct
          if !is_aggregate {
            // 标量字段原样（包 InitList 会被 else 臂按 void 误报）
            rebuilt.push(elements[pos])
            pos += 1
          } else {
            let group : Array[@ast.InitElement] = []
            for k = 0; k < take; k = k + 1 {
              group.push(elements[pos + k])
            }
            pos += take
            rebuilt.push({
              designators: [],
              value: @ast.Expr::InitList(group, loc, f.0),
            })
          }
        }
        if pos < elements.length() {
          // 字段吃满后仍有剩余——保留原序（下方既有数量/逐字段检查
          // 会按超量报 W3005；重组位不吞超量形态）
          while pos < elements.length() {
            rebuilt.push(elements[pos])
            pos += 1
          }
        }
        for i = 0; i < rebuilt.length(); i = i + 1 {
          elements[i] = rebuilt[i]
        }
        let drop_n = elements.length() - rebuilt.length()
        for k = 0; k < drop_n; k = k + 1 {
          ignore(elements.pop())
        }
      }
      // #157（2026-10-18，C23 §6.7.2.1p23）：柔性数组成员不可初始化
      //（clang "initialization of flexible array member" / gcc "non-
      // static initialization…"；仅初始化固定成员合法——柔性成员缺省）。
      // **已知分叉登记（2026-10-18 审阅批 P2-3）**：clang 22.1.4 默认
      // **接受**该形态（GNU 扩展 -Wgnu-flexible-array-initializer 默认
      // warning 级，-pedantic-errors 才 error）；vitro 教学口径从严恒
      // error——降 W 放行须先补柔性成员初始化的运行语义（额外空间
      // 分配 + 越界写面），独立批处理，分叉在 #157 登记在案
      let flex_idx : Int32 = if fields.length() > 0 &&
        is_flexible_array_member(fields[fields.length() - 1].0) {
        fields.length() - 1
      } else {
        -1
      }
      for i in 0..<elements.length() {
        if i >= fields.length() {
          break
        }
        if i == flex_idx {
          self.report_error(
            "柔性数组成员 '\{fields[i].1}' 不可初始化（C23 约束——该成员只能通过运行时分配/写入使用）",
            loc,
            E3079_FlexibleArrayInit,
          )
          break
        }
        let elem = elements[i]
        // #266（2026-10-22，C11 6.7.2.1p13 匿名成员位置初始化）：匿名
        // 聚合成员收标量值时透传——包单元素 InitList 走该成员的递归
        // 初始化检查（匿名 union 由第一成员承接、匿名 struct 由首字段
        // 承接——brace elision 的匿名面）；旧按字段整体比对报
        // E3006「期望 union 实际 int」误拒
        let is_anon_agg = fields[i].1 == "" &&
          (fields[i].0.kind() is TK_Struct || fields[i].0.kind() is TK_Union)
        let new_value = if is_anon_agg {
          let inner = if elem.value is InitList(_, _, _) {
            elem.value
          } else {
            InitList(
              [{ designators: [], value: elem.value, }],
              loc,
              fields[i].0,
            )
          }
          self.check_struct_initializer(fields[i].0, inner, loc)
        } else {
          self.check_field_value(fields[i].0, fields[i].1, elem.value, loc)
        }
        elements[i] = { ..elem, value: new_value, }
      }
      InitList(elements, iloc, ity)
    }
    _ => {
      // 非 InitList：按整体赋值检查
      let (init_type, new_init) = self.resolve_expr_type(init)
      if !self.check_assignable(
          struct_type,
          init_type,
          loc,
          value_expr=new_init,
        ) {
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
  if (field_ty.kind() is TK_Struct || field_ty.kind() is TK_Union) &&
    value is InitList(_, _, _) {
    self.check_struct_initializer(field_ty, value, loc)
  } else if field_ty.is_array() && value is InitList(_, _, _) {
    // sub_ty 的尺寸推断结果随节点类型走（调用方存根类型不更新——
    // Rust `let mut sub_ty = field_ty.clone()` 局部可变，同语义）
    let (_, new_value) = self.check_array_initializer(field_ty, value, loc)
    new_value
  } else if field_ty.is_array() &&
    field_ty.base_element_type().kind() is TK_Char &&
    value is StringLiteral(_, _, _) {
    // #75 缺口 3（2026-10-12，C11 6.7.9p14）：char[] 成员的字符串字面量
    // 初始化——`struct S { char s[64]; } a = {"Hi"}` 合法；此前落 else
    // 兜底把 "Hi" 定型 char[3] 去比 char[64] 误报 E3006。复用顶层
    // char[] 的 check_array_initializer 同款路径（长度校验/W3008/无尺寸
    // 回写语义单源）。非 char 数组不进此臂（后面仍拒）。
    let (_, new_value) = self.check_array_initializer(field_ty, value, loc)
    new_value
  } else {
    // 深挖批（2026-10-18，C11 6.7.9p11）：标量字段的括号包裹解包
    //（`struct S{int n;} s = {{7}}`——{7} ≡ 7；H_049 对抗形态的
    // `{M,K}` 给标量 n 取首 M + excess W）
    let value = match self.unwrap_scalar_braces(value, loc) {
      Some(u) => u
      None => value
    }
    let (e_type, new_value) = self.resolve_expr_type(value)
    if !self.check_assignable(field_ty, e_type, loc, value_expr=new_value) {
      // issue #19 销案（2026-10-06）：C11 §6.7.9 花括号省略/零初始化——
      // 常量 0 可初始化任意聚合成员（`struct S g = {0};` 惯用法——标量 0
      // 递归作用于首个标量子成员，数组成员收 0 即首元素零、其余默认零填
      // 由 codegen 零填路径承接）。非 0 标量对聚合仍报
      // 审阅 P3-7 扩（2026-10-07）：零值常量全家桶——0/0u/0L 等字面
      // 量与括号包裹（(0)）均属 C11 惯用清零形态（Clang 全接受）
      let is_zero_literal = match value {
        Literal(0, _, _) => true
        LongLiteral(0L, _, _) => true
        Cast(inner, _, _, _) =>
          match inner {
            Literal(0, _, _) => true
            _ => false
          }
        _ => false
      }
      let aggregate_field = field_ty.kind() is TK_Struct ||
        field_ty.kind() is TK_Union ||
        field_ty.is_array()
      if is_zero_literal && aggregate_field {
        // 放行：保持 0 字面量（codegen 聚合 init 对该字段按零填处理）
        new_value
      } else {
        self.report_error(
          "结构体初始化类型不匹配：字段 '\{field_name}' 期望 '\{field_ty.to_c_string()}'，实际 '\{e_type.to_c_string()}'",
          loc,
          E3006_ArrayInitTypeMismatch,
        )
        new_value
      }
    } else {
      insert_implicit_cast(new_value, field_ty)
    }
  }
}

///|
/// 按字段名查位置。
fn find_field(fields : Array[(@ast.Type, String)], name : String) -> Int32? {
  for i in 0..<fields.length() {
    if fields[i].1 == name {
      return Some(i)
    }
  }
  None
}

///|
/// 初始化器元素是否标量表达式（#180 elision 启用面判定，对抗批虫 β
/// 2026-10-18）：resolve 定型后非 struct/union/array 即可参与扁平流
/// 重组——覆盖变量/算术式（LLM 高频 `{c,d,0,...}` 形态）；聚合值元素
/// （#143 锚的 struct Member）返回 false 排除。resolve 幂等可重复调。
fn TypeChecker::is_scalar_init_expr(self : TypeChecker, e : @ast.Expr) -> Bool {
  let (ety, _) = self.resolve_expr_type(e)
  !(ety.kind() is TK_Struct) && !(ety.kind() is TK_Union) && !ety.is_array()
}

///|
/// 标量初始化器的大括号解包（深挖批 2026-10-18，C11 §6.7.9p11：
/// 「标量的初始化器应为可选大括号包裹的表达式」——`int x = {5}` ≡
/// `int x = 5`；多余元素对齐 clang `-Wexcess`（warning + 取首元素，
/// `int y = {9,10}` → 9）。**仅初始化器语境接线**（赋值表达式不吃
/// brace——C 赋值无此形态）；空 `{}` 不解包（C11 空初始化器只给聚合，
/// 维持原路径报错）。返回 Some(解包表达式) / None(非包裹形态)。
fn TypeChecker::unwrap_scalar_braces(
  self : TypeChecker,
  init : @ast.Expr,
  loc : @source.SourceLoc,
) -> @ast.Expr? {
  match init {
    InitList(elems, _, _) =>
      if elems.length() == 0 {
        None
      } else {
        if elems.length() > 1 {
          self.report_warning(
            "标量初始化器多余元素已忽略（取首元素——C11 6.7.9p11 包裹形态）",
            loc,
            W3005_ArrayInitTooMany,
          )
        }
        Some(elems[0].value)
      }
    _ => None
  }
}

///|
/// 聚合类型的「叶标量总数」（#180 brace elision 重组的消耗计量）：
/// 标量 1；数组 = 全维积（total_elements 已是 base 叶数）；struct =
/// 递归各字段之和；union 取 1（C 语义 union 初始化只填第一成员——
/// 教学近似）；其余（函数/void 等）按 1 计。
fn TypeChecker::agg_scalar_leaf_count(
  self : TypeChecker,
  ty : @ast.Type,
) -> Int32 {
  if ty.is_array() {
    let n = ty.total_elements()
    if n > 0 {
      n
    } else {
      1
    }
  } else if ty.kind() is TK_Struct {
    match self.structs.get(ty.name()) {
      Some(sym) => {
        let mut total = 0
        for pair in sym.fields {
          total += self.agg_scalar_leaf_count(pair.0)
        }
        if total > 0 {
          total
        } else {
          1
        }
      }
      None => 1
    }
  } else {
    1
  }
}

///|
/// 多维数组嵌套初始化列表校验（括号省略放行 + 扁平标量按行主序填充；
/// 返回 (是否合法, 改写后 init)）。
fn TypeChecker::validate_nested_init_list(
  self : TypeChecker,
  dims : Array[Int32],
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
    if !self.check_assignable(element_type, e_type, loc, value_expr=new_init) {
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
        let expected_count : Int32 = if dims[0] > 0 {
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
          self.report_warning(
            "初始化列表元素数量超过数组维度大小",
            loc,
            W3005_ArrayInitTooMany,
          )
        }
        let sub_dims : Array[Int32] = dims[1:].to_owned()
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
      StringLiteral(value, _, _) =>
        // #137 缺陷 1（2026-10-17，C11 §6.7.9p14）：char[N] 子数组的
        // 字符串字面量初始化——`char t[][8] = {"Alice","Bob"}` 每行
        // 逐字节拷入 + '\0' + 零填充。旧落 _ 臂按 char* 对 char[8] 判
        // assignable 失败报 E3009 误拒（四模型 8/8 命中，clang/gcc 均
        // ACCEPT）。越界对齐一维轨 W3008 警告（截断语义 clang 同）；
        // 非 char 子数组层（罕见）维持 E3009（clang 同判 error）。
        // 剩余维臂内自算（sub_dims 是 InitList 臂内局部量）。
        // 注意本臂的 dims 参数已是本子数组层维度（InitList 臂递归时
        // 已剥过外层）——char[N] 层即 dims=[N] 本身
        if dims.length() == 1 && element_type.kind() is TK_Char {
          // ds 批 2026-10-31：UTF-8 口径（与 cstring_bytes 同源）——
          // \xff 计 2，W3008 判定与实际装载需求一致
          let str_len = @util.utf8_len(value)
          if str_len + 1 > dims[0] {
            self.report_warning(
              "字符串字面量长度超过数组大小",
              loc,
              W3008_StringTooLong,
            )
          }
          (true, init)
        } else {
          self.report_error(
            "多维数组初始化需要嵌套初始化列表",
            loc,
            E3009_InvalidArrayInit,
          )
          (false, init)
        }
      _ => {
        // C/C++ 允许括号省略：标量可用于初始化当前子数组的第一个元素，
        // 其余零填充。例如 int a[5][5] = {0}; int b[2][3] = {1, 2};
        let (e_type, new_init) = self.resolve_expr_type(init)
        if self.check_assignable(element_type, e_type, loc, value_expr=new_init) {
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
        // 对抗批虫 α（2026-10-18）：`struct MD{char d[2][4];} v = {"ab"}`
        // ——字符串字面量初始化多维 char 数组的**当前子对象**（首行，
        // C11 §6.7.9p14——clang 零警告接受 `[ab][]`）；旧一律按「非嵌套
        // 列表」拒。codegen gen_nested_init 的 #137 char[N] 直写臂 +
        // 行步长分派已承接，typeck 放行即可（非 char 基类型不进此路径
        //——#75 臂已限定）。
        if init is StringLiteral(_, _, _) && elem_type.kind() is TK_Char {
          return (arr_type, new_init)
        }
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
      // #196B（2026-10-21，C11 §6.7.9p11 括号包裹 + p14 字符串初始化）：
      // `char s[N] = {"abc"}` ≡ 裸字符串——单元素花括号字符串且基类型
      // char 时递归走 StringLiteral 同款路径（长度校验/W3008/无尺寸回写
      // 语义单源），不再按元素循环把 "abc" 定型 char[4] 误报 E3006。
      // 多元素/带 designator/非 char 基类型不进此臂（既有语义不变）。
      if elements.length() == 1 &&
        elements[0].designators.length() == 0 &&
        elements[0].value is StringLiteral(_, _, _) &&
        elem_type.kind() is TK_Char {
        return self.check_array_initializer(arr_type, elements[0].value, loc)
      }
      let has_designators = elements.exists(e => e.designators.length() > 0)
      if has_designators {
        for i in 0..<elements.length() {
          let elem = elements[i]
          if elem.designators.length() == 0 {
            // 审阅 P2（2026-10-14）：C11 §6.7.9p17 明确允许混合
            //（designator 定位后无标记元素按 prev+1 续位——codegen
            // flatten_designated_global 已实现续位；块作用域病 121
            // 修复时连坐撤）。旧警告+错码 W3005_ArrayInitTooMany
            //（fix_suggestion 张冠李戴讲"元素过多"）双假阳性。
            continue
          }
          if elem.designators.length() != 1 {
            self.report_warning(
              "暂不支持多级 designated initializer",
              loc,
              W3005_ArrayInitTooMany,
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
              let ok = self.check_assignable(
                elem_type,
                e_type,
                loc,
                value_expr=new_value,
              )
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
              self.report_warning(
                "数组初始化只能使用 [index] 形式的 designator",
                loc,
                W3005_ArrayInitTooMany,
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
        self.report_warning(
          "初始化列表元素数量超过数组大小",
          loc,
          W3005_ArrayInitTooMany,
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
      // ds 批 2026-10-31：UTF-8 口径（与 cstring_bytes 同源，#66 连坐完）
      // ——旧 Latin-1 计长使 char g[] 定型少 1、NUL 被挤 ⇒ 越界读
      let str_len = @util.utf8_len(value)
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
        self.report_warning(
          "字符串字面量长度超过数组大小",
          loc,
          W3008_StringTooLong,
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
  // 病 55（2026-10-13）：union 元素的 InitList 接入——check_struct_initializer
  // 已 union-aware（#19 批 unions 表分派），本臂漏扩致 union 数组元素
  // `union U us[2] = {{1},{2}}` 落 else 定型 void → E3006 假阳性。
  if (elem_type.kind() is TK_Struct || elem_type.kind() is TK_Union) &&
    value is InitList(_, _, _) {
    self.check_struct_initializer(elem_type, value, loc)
  } else if elem_type.is_array() && value is InitList(_, _, _) {
    let (_, new_value) = self.check_array_initializer(elem_type, value, loc)
    new_value
  } else {
    // 深挖批（2026-10-18，C11 6.7.9p11）：数组标量元素的括号包裹解包
    //（`int a[3] = {1,{2},3}`——`{2}` ≡ 2）
    let value = match self.unwrap_scalar_braces(value, loc) {
      Some(u) => u
      None => value
    }
    let (e_type, new_value) = self.resolve_expr_type(value)
    // W0-4：char 元素的字符常量/值域内整常量初始化是 C 惯用写法，豁免窄化警告
    let suppress = elem_type.kind() is TK_Char &&
      is_char_safe_initializer(new_value)
    if suppress {
      self.char_narrow_suppress = true
    }
    let ok = self.check_assignable(elem_type, e_type, loc, value_expr=new_value)
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
            if !self.check_assignable(
                target_type,
                e_type,
                loc,
                value_expr=new_value,
              ) {
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
