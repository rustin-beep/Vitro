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
pub fn TypeChecker::declare_var(
  self : TypeChecker,
  name : String,
  ty : @ast.Type,
  is_global~ : Bool,
  is_extern~ : Bool,
  is_static~ : Bool,
) -> Unit {
  if self.scopes.length() == 0 {
    self.scopes.push(Map([]))
  }
  let scope = self.scopes[self.scopes.length() - 1]
  match scope.get(name) {
    Some(existing) => {
      if is_extern {
        // extern 声明与既有符号共存
        return
      }
      // 非 extern 定义可替换 extern 声明
      if existing.is_extern {
        scope.set(name, { ty, _is_global: is_global, is_extern, is_static, })
        return
      }
      // 不同文件的同名 static 全局（内部链接）——保留最新，使用点检查
      if existing.is_static && is_static && is_global {
        scope.set(name, { ty, _is_global: is_global, is_extern, is_static, })
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
      scope.set(name, { ty, _is_global: is_global, is_extern, is_static, })
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
) -> Int {
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
