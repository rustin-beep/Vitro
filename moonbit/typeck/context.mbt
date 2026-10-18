///|
/// 作用域管理 + 符号表桥接（照搬 Rust `context.rs`——declare_var 的
/// extern/static 覆盖语义与 E3001 零位置报错（O3 登记债）逐字照搬）。

///|
pub fn TypeChecker::enter_scope(self : TypeChecker) -> Unit {
  self.scopes.push(Map([]))
}

///|
pub fn TypeChecker::exit_scope(self : TypeChecker) -> Unit {
  let _ = self.scopes.pop()
}

///|
/// 声明变量（同名语义四层：extern 声明共存 / 非 extern 覆盖 extern /
/// 双 static 全局允许（内部链接，取最新）/ 其余报 E3001）。
/// #150（2026-10-18）：extern 再声明与「非 extern 定义替换 extern 声明」
/// 两分支加**类型判等**（顶层 const 剥离后 type_eq）——不等报 E3001
/// （clang "redeclaration of 'x' with a different type"）。loc 可选参
/// 数默认零位置（O3 登记债同族；带位置的调用点渐进传入）。
pub fn TypeChecker::declare_var(
  self : TypeChecker,
  name : String,
  ty : @ast.Type,
  is_global~ : Bool,
  is_extern~ : Bool,
  is_static~ : Bool,
  predeclared~ : Bool = false,
  is_register~ : Bool = false,
  loc~ : @source.SourceLoc = @source.SourceLoc::new(0, 0),
) -> Unit {
  // #150 对抗补（2026-10-18）：extern 族类型判等——type_eq 之外加
  // **不完整数组兼容**（C11 §6.2.7p2：`extern int arr[];` 与 `extern
  // int arr[10];` / 后续定义兼容——第一维未知即兼容，其余维须等；
  // asize 由 dims 派生随之）。type_eq 全域严格比维度，不动它——本特
  // 判仅 extern 声明语境（对抗探针 adv_d 三误报根因）。
  fn extern_type_compat(a : @ast.Type, b : @ast.Type) -> Bool {
    if @ast.type_eq(strip_top_const(a), strip_top_const(b)) {
      return true
    }
    match (a, b) {
      (Array(ae, _, adims, _, _, _), Array(be, _, bdims, _, _, _)) => {
        // 维度兼容：维数等 + 逐维「相等或一方 -1（不完整）」
        if adims.length() != bdims.length() {
          return false
        }
        for i in 0..<adims.length() {
          let x = adims[i]
          let y = bdims[i]
          if x != y && x != -1 && y != -1 {
            return false // 互斥维度——不兼容
          }
        }
        extern_type_compat(ae, be)
      }
      (Pointer(ap, _), Pointer(bp, _)) => extern_type_compat(ap, bp)
      _ => false
    }
  }
  // 维度更完整侧判定：新声明带实际维度而已有是不完整数组 → 采用新
  fn more_complete(existing : @ast.Type, incoming : @ast.Type) -> @ast.Type {
    match (existing, incoming) {
      (Array(ee, es, _ed, ec, ev, ea), Array(_, _, bd, _, _, _)) =>
        if es == -1 && bd.length() > 0 && bd[0] != -1 {
          // 用 incoming 的维度重建元素类型一致的完整形态
          Array(ee, if bd[0] > 0 { bd[0] } else { es }, bd, ec, ev, ea)
        } else {
          existing
        }
      _ => existing
    }
  }
  // #150：extern 族两分支的类型冲突报错（兼容判等 + 不完整数组升级）。
  // 不兼容时返回 new_ty——报错后登记新声明类型（clang error recovery
  // 口径 + 旧代码行为；返回 existing 会把 y 钉死在旧类型，wbtest
  // declare_var_semantics 的 `sym.ty is Double` 锚实测抓出）
  fn mismatch_report(
    tc : TypeChecker,
    existing_ty : @ast.Type,
    new_ty : @ast.Type,
    vname : String,
    vloc : @source.SourceLoc,
  ) -> @ast.Type {
    if extern_type_compat(existing_ty, new_ty) {
      return more_complete(existing_ty, new_ty)
    }
    tc.report_error(
      "变量 '\{vname}' 的声明类型与之前的声明不一致（'\{existing_ty.to_c_string()}' vs '\{new_ty.to_c_string()}'）",
      vloc,
      E3001_VarRedeclared,
    )
    new_ty
  }
  if self.scopes.length() == 0 {
    self.scopes.push(Map([]))
  }
  let scope = self.scopes[self.scopes.length() - 1]
  match scope.get(name) {
    Some(existing) => {
      if is_extern {
        // extern 声明与既有符号共存——类型须兼容（#150 + 不完整数组
        // 升级：`extern int a[]; extern int a[10];` 后 sizeof 取完整侧）
        let effective = mismatch_report(self, existing.ty, ty, name, loc)
        if !@ast.type_eq(effective, existing.ty) {
          scope.set(name, {
            ty: effective,
            _is_global: existing._is_global,
            is_extern: existing.is_extern,
            is_static: existing.is_static,
            predeclared: existing.predeclared,
            is_register: existing.is_register,
          })
        }
        return
      }
      // 非 extern 定义可替换 extern 声明——类型须兼容（#150）
      if existing.is_extern {
        let effective = mismatch_report(self, existing.ty, ty, name, loc)
        scope.set(name, {
          ty: effective,
          _is_global: is_global,
          is_extern,
          is_static,
          predeclared,
          is_register,
        })
        return
      }
      // #75 缺口 2（2026-10-12）：**声明完成覆盖**——同批 VarDecl 的
      // 前置登记（标量声明供初始化器引用自身，`sizeof *p` 惯用法）由
      // 处理路径以 predeclared 预声明标记走 declare_var(~predeclared=
      // true)；同名二次登记=同声明的 final 覆盖（类型定稿），非重声明。
      if existing.predeclared && !is_extern {
        scope.set(name, {
          ty,
          _is_global: is_global,
          is_extern,
          is_static,
          predeclared: false,
          is_register,
        })
        return
      }
      // 不同文件的同名 static 全局（内部链接）——保留最新，使用点检查
      if existing.is_static && is_static && is_global {
        scope.set(name, {
          ty,
          _is_global: is_global,
          is_extern,
          is_static,
          predeclared,
          is_register,
        })
        return
      }
      // O3 登记债照搬：重复声明诊断位置写死零
      self.report_error(
        "变量 '\{name}' 已在此作用域中声明",
        @source.SourceLoc::new(0, 0),
        E3001_VarRedeclared,
      )
    }
    None =>
      scope.set(name, {
        ty,
        _is_global: is_global,
        is_extern,
        is_static,
        predeclared,
        is_register,
      })
  }
}

///|
/// #145（2026-10-18）：值形态类型完整性检查——struct/union 仅有前向
/// 声明（在册 is_complete=false）时，声明该类型变量 / sizeof / 函数
/// 定义签名 / 值成员是约束违反（C11 §6.7.2.2p7），报 E3076。**查无
/// 定义（None）不报**——匿名内联 union 与 typedef 形态在表内的缺席
/// 是合法通道（对抗复跑实锤收窄）。数组下钻到
/// base_element_type（`struct S arr[3]` 同报——元素必须完整）；指针
/// 不受限（`struct Opq *p` 前向即可，C 链表/不透明指针惯用法）。
fn TypeChecker::check_type_complete(
  self : TypeChecker,
  ty : @ast.Type,
  loc : @source.SourceLoc,
) -> Unit {
  let value_ty = if ty.is_array() { ty.base_element_type() } else { ty }
  let kind = value_ty.kind()
  if kind is TK_Struct {
    match self.structs.get(value_ty.name()) {
      Some(sym) =>
        if !sym.is_complete {
          self.report_error(
            "使用了不完整类型 'struct \{value_ty.name()}'（只有前向声明，缺少字段定义）——声明该类型的变量或取 sizeof 前必须给出完整定义",
            loc,
            E3076_IncompleteType,
          )
        }
      None => ()
    }
  } else if kind is TK_Union {
    match self.unions.get(value_ty.name()) {
      Some(sym) =>
        if !sym.is_complete {
          self.report_error(
            "使用了不完整类型 'union \{value_ty.name()}'（只有前向声明，缺少字段定义）",
            loc,
            E3076_IncompleteType,
          )
        }
      None => ()
    }
  }
}

///|
/// 由内向外查变量。
pub fn TypeChecker::lookup_var(self : TypeChecker, name : String) -> VarSymbol? {
  let mut i = self.scopes.length() - 1
  while i >= 0 {
    match self.scopes[i].get(name) {
      Some(sym) => return Some(sym)
      None => ()
    }
    i -= 1
  }
  None
}

///|
/// P4：尺寸推断后回写符号类型（全局 `char g[] = "str"` 的 array_size 推断
/// 发生在 declare_var 之后——不回写则 sizeof(g) 用推断前快照恒 1）。
pub fn TypeChecker::update_var_type(
  self : TypeChecker,
  name : String,
  ty : @ast.Type,
) -> Unit {
  let mut i = self.scopes.length() - 1
  while i >= 0 {
    match self.scopes[i].get(name) {
      Some(sym) => {
        // Rust 是 `sym.ty = ty` 原地改一字段——值语义下整符号重建，
        // 其余字段照旧保留
        self.scopes[i].set(name, {
          ty,
          _is_global: sym._is_global,
          is_extern: sym.is_extern,
          is_static: sym.is_static,
          predeclared: sym.predeclared,
          is_register: sym.is_register,
        })
        return
      }
      None => ()
    }
    i -= 1
  }
}

///|
/// 类型字节尺寸（照搬 Rust 包装器——每次调用重建 struct/union 定义表）。
///
/// **O2 债裁决（2026-09-22 S5 收尾批：已量测，保留重建，不做缓存化）**：
/// ① 语料规模实测上界——613 个 .c 中 struct/union 定义最多 **2** 个（多文件
///    并列：baseline/e1_c23_alignof.c、baseline/linked_queue.c、knr/kr_6_3.c），
///    单文件成员访问最多 **37** 次（leetcode/lc_2.c）⇒ 每次重建至多 ~10 次
///    map 插入，全文件总成本 ~4×10² 次操作，**不可测**；
/// ② Rust 侧 `vitro_typeck/src/context.rs:8` 同构（同样每次重建 + `class_size_map`），
///    本处保持"照搬"以免制造两侧行为分叉；
/// ③ 两侧不对称是有意的、非遗漏——typeck 阶段 `self.structs` **在增长**
///    （Pass 1 登记，typeck.mbt:114/125），缓存须带失效逻辑；codegen 侧能
///    安全用 `self.struct_defs` 恰因那时表已固定（typeck 之后才跑）；
/// ④ MoonBit `self` 为值语义，加缓存字段会让每次调用复制更大的 struct 头，
///    **净收益方向不确定**（可能为负）。
/// 复评触发：`scripts/perf_budget` 红（语料规模超预算），或 S6 后性能批给出
/// 可测证据。详见 CHANGELOG「O2 债裁决」。
pub fn TypeChecker::compute_type_size(
  self : TypeChecker,
  ty : @ast.Type,
) -> Int32 {
  let struct_defs : Map[String, Array[@ast.StructField]] = Map([])
  for name, sym in self.structs {
    struct_defs.set(name, sym.fields.map(pair => { ty: pair.0, name: pair.1, }))
  }
  let union_defs : Map[String, Array[@ast.StructField]] = Map([])
  for name, sym in self.unions {
    union_defs.set(name, sym.fields.map(pair => { ty: pair.0, name: pair.1, }))
  }
  @ast.compute_type_size(ty, struct_defs, union_defs, Map([]))
}
