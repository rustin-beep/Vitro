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
/// 类型字节尺寸（照搬 Rust 包装器——O2 债照搬：每次调用重建 struct/union
/// 定义表；教学符号表小，等价优先，缓存化属优化不改语义）。
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
