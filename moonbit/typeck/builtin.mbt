///|
/// builtin 调用检查分派（照搬 Rust `builtin/{mod,io,string,math,memory,
/// file}.rs`——`visit_call` 逐臂 + 同名检查器；**诊断文案逐字照搬**，E1
/// 对拍面）。**函数式重建形态**：实参数组是引用语义容器（`args[i] = ...`
/// 原地改写 = Rust `&mut Vec`），表达式子树重建由 `insert_implicit_cast`
/// 返回新树；返回类型不入表（libc 单表的 C 面漂移 N3/N4 登记在案，
/// 检查器内照搬 Rust 现状硬编码）。
///
/// `std__move` 臂剔除登记（C++ 语义臂——C AST 不产，S9 C++ 片随批补）；
/// `qsort` 用户重定义优先特判照搬（funcs 命中 → check_user_func——
/// include 存根注入的声明同占此轨）。

///|
/// builtin 调用总入口（Rust `visit_call` 同构：58 臂去 std__move）。
pub fn TypeChecker::visit_call(
  self : TypeChecker,
  name : String,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  match name {
    "malloc" => self.check_builtin_malloc(args, loc)
    "free" => self.check_builtin_free(args, loc)
    "print_int" | "__vitro_output" | "__vitro_step" =>
      self.check_builtin_print_int(args, loc, name)
    "printf" => self.check_builtin_printf(args, loc)
    "scanf" => self.check_builtin_scanf(args, loc)
    "strlen" => self.check_builtin_strlen(args, loc)
    "strcpy" => self.check_builtin_strcpy(args, loc)
    "strcmp" => self.check_builtin_strcmp(args, loc)
    "strdup" => self.check_builtin_strdup(args, loc)
    "getchar" => self.check_builtin_getchar(args, loc)
    "putchar" => self.check_builtin_putchar(args, loc)
    "ungetc" => self.check_builtin_ungetc(args, loc)
    "rand" => self.check_builtin_rand(args, loc)
    "srand" => self.check_builtin_srand(args, loc)
    "memset" => self.check_builtin_memset(args, loc)
    "exit" => self.check_builtin_exit(args, loc)
    "strcat" => self.check_builtin_strcat(args, loc)
    "atoi" => self.check_builtin_atoi(args, loc)
    "fopen" => self.check_builtin_fopen(args, loc)
    "fread" => self.check_builtin_fread(args, loc)
    "fwrite" => self.check_builtin_fwrite(args, loc)
    "fclose" => self.check_builtin_fclose(args, loc)
    "feof" => self.check_builtin_feof(args, loc)
    "fgets" => self.check_builtin_fgets(args, loc)
    "fputs" => self.check_builtin_fputs(args, loc)
    "fprintf" => self.check_builtin_fprintf(args, loc)
    "realloc" => self.check_builtin_realloc(args, loc)
    "qsort" =>
      if self.funcs.contains(name) {
        self.check_user_func(name, args, loc)
      } else {
        self.check_builtin_qsort(args, loc)
      }
    "puts" => self.check_builtin_puts(args, loc)
    "calloc" => self.check_builtin_calloc(args, loc)
    "bsearch" => self.check_builtin_bsearch(args, loc)
    "sprintf" => self.check_builtin_sprintf(args, loc)
    "snprintf" => self.check_builtin_snprintf(args, loc)
    "sscanf" => self.check_builtin_sscanf(args, loc)
    "fgetc" => self.check_builtin_fgetc(args, loc)
    "fputc" => self.check_builtin_fputc(args, loc)
    "fseek" => self.check_builtin_fseek(args, loc)
    "ftell" => self.check_builtin_ftell(args, loc)
    "rewind" => self.check_builtin_rewind(args, loc)
    "strncat" => self.check_builtin_strncat(args, loc)
    "strncmp" => self.check_builtin_strncmp(args, loc)
    "memcmp" => self.check_builtin_memcmp(args, loc)
    "strchr" => self.check_builtin_strchr(args, loc)
    "strrchr" => self.check_builtin_strrchr(args, loc)
    "strstr" => self.check_builtin_strstr(args, loc)
    "memchr" => self.check_builtin_memchr(args, loc)
    "atof" => self.check_builtin_atof(args, loc)
    "atol" => self.check_builtin_atol(args, loc)
    "tan" => self.check_builtin_tan(args, loc)
    "log10" => self.check_builtin_log10(args, loc)
    "fabs" => self.check_builtin_fabs(args, loc)
    "ceil" => self.check_builtin_ceil(args, loc)
    "floor" => self.check_builtin_floor(args, loc)
    "round" => self.check_builtin_round(args, loc)
    "fmod" => self.check_builtin_fmod(args, loc)
    // math.h 函数经头文件存根进 funcs 表——visit_call 兜底臂
    // check_user_func（Rust 同形）
    _ => self.check_user_func(name, args, loc)
  }
}

///|
/// 解析 printf/scanf 格式字符串，返回非 %% 的格式说明符列表
///（元素 (spec_char, length_mod)，如 ('d', "") / ('f', "l")）。
pub fn parse_format_specs(fmt : String) -> Array[(Char, String)] {
  let specs : Array[(Char, String)] = []
  let chars : Array[Char] = []
  for c in fmt {
    chars.push(c)
  }
  let n = chars.length()
  let mut i = 0
  while i < n {
    let ch = chars[i]
    i += 1
    if ch == '%' {
      if i < n && chars[i] == '%' {
        i += 1 // skip %%
        continue
      }
      // skip flags
      while i < n {
        let c = chars[i]
        if c == '-' || c == '+' || c == ' ' || c == '#' || c == '0' {
          i += 1
        } else {
          break
        }
      }
      // skip width
      while i < n {
        let c = chars[i]
        if (c >= '0' && c <= '9') || c == '*' {
          i += 1
        } else {
          break
        }
      }
      // skip precision
      if i < n && chars[i] == '.' {
        i += 1
        while i < n {
          let c = chars[i]
          if (c >= '0' && c <= '9') || c == '*' {
            i += 1
          } else {
            break
          }
        }
      }
      // length modifier
      let mut len_mod = ""
      if i < n {
        let c = chars[i]
        if c == 'l' || c == 'h' || c == 'L' || c == 'z' || c == 'j' || c == 't' {
          i += 1
          len_mod = "\{c}"
          if c == 'l' || c == 'h' {
            if i < n && chars[i] == c {
              i += 1
              len_mod = "\{len_mod}\{c}"
            }
          }
        }
      }
      if i < n {
        let spec = chars[i]
        i += 1
        specs.push((spec, len_mod))
      }
    }
  }
  specs
}

///|
/// printf 格式-参数类型匹配（E3032 数量 / E3062 类型；start = 格式串
/// 之后的首参下标——printf 1 / fprintf 2）。实参解析定型原地写回。
pub fn TypeChecker::check_printf_format(
  self : TypeChecker,
  fmt : String,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
  start : Int,
) -> Unit {
  let specs = parse_format_specs(fmt)
  let arg_count = args.length() - start
  if specs.length() != arg_count {
    self.report_error(
      "printf 格式说明符数量（\{specs.length()}）与参数数量（\{arg_count}）不匹配",
      loc,
      E3032_PrintfArgType,
    )
  }
  let check_count = if specs.length() < arg_count {
    specs.length()
  } else {
    arg_count
  }
  for j in 0..<check_count {
    let (spec, len_mod) = specs[j]
    let (arg_type, new_arg) = self.resolve_expr_type(args[start + j])
    args[start + j] = new_arg
    let ak = arg_type.kind()
    // Rust 组合臂逐条：(""/"l"/"ll" × spec 族)——('F',"") 并入 ("f" 族,"l")
    // 臂的 Double|Float，("ll"+f 族) 落 unknown 放行
    let ok : Bool = match len_mod {
      "" =>
        match spec {
          'd' | 'i' | 'u' | 'x' | 'X' | 'o' | 'n' =>
            ak is TK_Int || ak is TK_Char
          'f' | 'e' | 'g' | 'E' | 'G' => ak is TK_Float || ak is TK_Double
          'F' => ak is TK_Double || ak is TK_Float
          'c' => ak is TK_Int || ak is TK_Char
          's' | 'p' => ak is TK_Pointer || arg_type.is_array()
          _ => true // unknown spec, be permissive
        }
      "l" =>
        match spec {
          'd' | 'i' | 'u' | 'x' | 'X' | 'o' => ak is TK_LongLong || ak is TK_Int
          'f' | 'e' | 'g' | 'E' | 'G' => ak is TK_Double || ak is TK_Float
          _ => true
        }
      "ll" =>
        match spec {
          'd' | 'i' | 'u' | 'x' | 'X' | 'o' => ak is TK_LongLong || ak is TK_Int
          _ => true
        }
      _ => true
    }
    if !ok {
      self.report_error(
        "printf 格式 '%\{spec}' 与第 \{start + j + 2} 个参数类型 '\{arg_type.to_c_string()}' 不匹配",
        loc,
        E3062_PrintfFormatMismatch,
      )
    }
  }
}

///|
/// scanf 格式-参数类型匹配（E3035 数量 / E3063 类型；实参必须是指针，
/// 按 pointee 检查）。
pub fn TypeChecker::check_scanf_format(
  self : TypeChecker,
  fmt : String,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
  start : Int,
) -> Unit {
  let specs = parse_format_specs(fmt)
  let arg_count = args.length() - start
  if specs.length() != arg_count {
    self.report_error(
      "scanf 格式说明符数量（\{specs.length()}）与参数数量（\{arg_count}）不匹配",
      loc,
      E3035_ScanfArgType,
    )
  }
  let check_count = if specs.length() < arg_count {
    specs.length()
  } else {
    arg_count
  }
  for j in 0..<check_count {
    let (spec, len_mod) = specs[j]
    let (arg_type, new_arg) = self.resolve_expr_type(args[start + j])
    args[start + j] = new_arg
    // scanf args must be pointers——pointee 类型判定经闭包传入（None 恒 false）
    let pointee : @ast.Type? = match arg_type {
      Pointer(p, _) => Some(p)
      Array(element, _, _, _, _, _) => Some(element)
      _ => None
    }
    fn pointee_is(p : @ast.Type?, is_ok : (@ast.TypeKind) -> Bool) -> Bool {
      match p {
        Some(t) => is_ok(t.kind())
        None => false
      }
    }
    let ok : Bool = match len_mod {
      "" =>
        match spec {
          'd' | 'i' | 'u' | 'x' | 'X' | 'o' | 'n' =>
            pointee_is(pointee, k => k is TK_Int || k is TK_Char)
          'f' | 'e' | 'g' | 'E' | 'G' =>
            pointee_is(pointee, k => k is TK_Float || k is TK_Int)
          'F' =>
            pointee_is(pointee, k => {
              k is TK_Double || k is TK_Float || k is TK_Int
            })
          'c' => pointee_is(pointee, k => k is TK_Char || k is TK_Int)
          's' | 'p' => arg_type.kind() is TK_Pointer || arg_type.is_array()
          _ => true
        }
      "l" =>
        match spec {
          'd' | 'i' | 'u' | 'x' | 'X' | 'o' =>
            pointee_is(pointee, k => k is TK_LongLong || k is TK_Int)
          'f' | 'e' | 'g' | 'E' | 'G' =>
            pointee_is(pointee, k => {
              k is TK_Double || k is TK_Float || k is TK_Int
            })
          _ => true
        }
      "ll" =>
        match spec {
          'd' | 'i' | 'u' | 'x' | 'X' | 'o' =>
            pointee_is(pointee, k => k is TK_LongLong || k is TK_Int)
          _ => true
        }
      _ => true
    }
    if !ok {
      self.report_error(
        "scanf 格式 '%\{spec}' 与第 \{start + j + 2} 个参数类型 '\{arg_type.to_c_string()}' 不匹配",
        loc,
        E3063_ScanfFormatMismatch,
      )
    }
  }
}

// ---------- 内建函数检查器辅助方法 ----------

///|
/// 实参数量检查（E3028）。
fn TypeChecker::builtin_check_count(
  self : TypeChecker,
  args : Array[@ast.Expr],
  expected : Int,
  name : String,
  loc : @source.SourceLoc,
) -> Bool {
  if args.length() != expected {
    self.report_error(
      "\{name} 需要\{expected}个参数",
      loc,
      E3028_BuiltInArgCount,
    )
    false
  } else {
    true
  }
}

///|
/// 第 idx 实参必须是指针或数组（E3029；解析定型原地写回）。
fn TypeChecker::builtin_check_pointer(
  self : TypeChecker,
  args : Array[@ast.Expr],
  idx : Int,
  name : String,
  loc : @source.SourceLoc,
) -> Unit {
  let (arg_type, new_arg) = self.resolve_expr_type(args[idx])
  args[idx] = new_arg
  if !(arg_type.kind() is TK_Pointer) && !arg_type.is_array() {
    self.report_error(
      "\{name} 的第 \{idx + 1} 个参数必须是指针或数组",
      loc,
      E3029_BuiltInArgType,
    )
  }
}

///|
/// 第 idx 实参必须是 int（E3029；可赋值即放行 + 隐式转换插入）。
fn TypeChecker::builtin_check_int(
  self : TypeChecker,
  args : Array[@ast.Expr],
  idx : Int,
  name : String,
  loc : @source.SourceLoc,
) -> Unit {
  let expected = @ast.Type::int()
  let (arg_type, new_arg) = self.resolve_expr_type(args[idx])
  if !self.check_assignable(expected, arg_type, loc) {
    self.report_error(
      "\{name} 的第 \{idx + 1} 个参数必须是 int",
      loc,
      E3029_BuiltInArgType,
    )
  } else {
    args[idx] = insert_implicit_cast(new_arg, expected)
  }
}

// ---------- 内建函数检查器 ----------

///|
/// qsort（四参：base 指针数组 / 1..2 int / compar 函数指针）。
fn TypeChecker::check_builtin_qsort(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if args.length() != 4 {
    self.report_error("qsort 需要四个参数", loc, E3028_BuiltInArgCount)
  } else {
    let (base_type, new_a0) = self.resolve_expr_type(args[0])
    args[0] = new_a0
    if !(base_type.kind() is TK_Pointer) && !base_type.is_array() {
      self.report_error(
        "qsort 第一个参数必须是指针或数组",
        loc,
        E3029_BuiltInArgType,
      )
    }
    for i in [1, 2] {
      let (t, new_arg) = self.resolve_expr_type(args[i])
      if !self.check_assignable(@ast.Type::int(), t, loc) {
        self.report_error(
          "qsort 第 \{i + 1} 个参数必须是 int",
          loc,
          E3029_BuiltInArgType,
        )
      } else {
        args[i] = insert_implicit_cast(new_arg, @ast.Type::int())
      }
    }
    let (compar_type, new_a3) = self.resolve_expr_type(args[3])
    args[3] = new_a3
    if !(compar_type.kind() is TK_Int) && !(compar_type.kind() is TK_Pointer) {
      self.report_error(
        "qsort 第四个参数必须是函数指针",
        loc,
        E3029_BuiltInArgType,
      )
    }
  }
  @ast.Type::void_type()
}

///|
/// bsearch（五参：key/base 指针数组 / 2..3 int / compar 函数指针）。
fn TypeChecker::check_builtin_bsearch(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if args.length() != 5 {
    self.report_error("bsearch 需要五个参数", loc, E3028_BuiltInArgCount)
  } else {
    let (key_type, new_a0) = self.resolve_expr_type(args[0])
    args[0] = new_a0
    if !(key_type.kind() is TK_Pointer) && !key_type.is_array() {
      self.report_error(
        "bsearch 第一个参数必须是指针或数组",
        loc,
        E3029_BuiltInArgType,
      )
    }
    let (base_type, new_a1) = self.resolve_expr_type(args[1])
    args[1] = new_a1
    if !(base_type.kind() is TK_Pointer) && !base_type.is_array() {
      self.report_error(
        "bsearch 第二个参数必须是指针或数组",
        loc,
        E3029_BuiltInArgType,
      )
    }
    for i in [2, 3] {
      self.builtin_check_int(args, i, "bsearch", loc)
    }
    let (compar_type, new_a4) = self.resolve_expr_type(args[4])
    args[4] = new_a4
    if !(compar_type.kind() is TK_Int) && !(compar_type.kind() is TK_Pointer) {
      self.report_error(
        "bsearch 第五个参数必须是函数指针",
        loc,
        E3029_BuiltInArgType,
      )
    }
  }
  @ast.Type::pointer_to(@ast.Type::void_type())
}

// ---------- io（Rust builtin/io.rs）----------

///|
/// print_int/__vitro_output/__vitro_step（单 int 参）。
fn TypeChecker::check_builtin_print_int(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
  name : String,
) -> @ast.Type {
  if args.length() != 1 {
    self.report_error("\{name} 需要一个参数", loc, E3028_BuiltInArgCount)
  } else {
    let expected = @ast.Type::int()
    let (arg_type, new_arg) = self.resolve_expr_type(args[0])
    if !self.check_assignable(expected, arg_type, loc) {
      self.report_error(
        "\{name} 参数必须是 int",
        loc,
        E3029_BuiltInArgType,
      )
    } else {
      args[0] = insert_implicit_cast(new_arg, expected)
    }
  }
  @ast.Type::void_type()
}

///|
/// printf（E3030 空参 / E3031 首参字符串；字面量格式串走格式-参数
/// 匹配，非字面量粗检 E3032）。返回 void 是 N3 漂移登记（C 标准 int）。
fn TypeChecker::check_builtin_printf(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if args.length() == 0 {
    self.report_error(
      "printf 至少需要 1 个参数（格式字符串）",
      loc,
      E3030_PrintfArgCount,
    )
  } else {
    let (fmt_type, new_a0) = self.resolve_expr_type(args[0])
    args[0] = new_a0
    if !(fmt_type.kind() is TK_Pointer) && !fmt_type.is_array() {
      self.report_error(
        "printf 的第一个参数必须是字符串",
        loc,
        E3031_PrintfFirstArg,
      )
    }
    match new_a0 {
      StringLiteral(value, _, _) =>
        self.check_printf_format(value, args, loc, 1)
      _ =>
        // 非字面量格式字符串，只做粗略检查
        for i in 1..<args.length() {
          let (arg_type, new_arg) = self.resolve_expr_type(args[i])
          args[i] = new_arg
          if !self.is_scalar(arg_type) &&
            !(arg_type.kind() is TK_Pointer) &&
            !arg_type.is_array() {
            self.report_error(
              "printf 的第 \{i + 1} 个参数必须是 int、float、char 或指针",
              loc,
              E3032_PrintfArgType,
            )
          }
        }
    }
  }
  @ast.Type::void_type()
}

///|
/// scanf（E3033 少参 / E3034 首参字符串；字面量走 scanf 格式匹配，
/// 非字面量逐参指针粗检 E3035）。C11 7.21.6.2 返回匹配项数——int。
fn TypeChecker::check_builtin_scanf(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if args.length() < 2 {
    self.report_error(
      "scanf 至少需要 2 个参数（格式字符串和地址）",
      loc,
      E3033_ScanfArgCount,
    )
  } else {
    let (fmt_type, new_a0) = self.resolve_expr_type(args[0])
    args[0] = new_a0
    if !(fmt_type.kind() is TK_Pointer) && !fmt_type.is_array() {
      self.report_error(
        "scanf 的第一个参数必须是字符串",
        loc,
        E3034_ScanfFirstArg,
      )
    }
    match new_a0 {
      StringLiteral(value, _, _) => self.check_scanf_format(value, args, loc, 1)
      _ =>
        for i in 1..<args.length() {
          let (arg_type, new_arg) = self.resolve_expr_type(args[i])
          args[i] = new_arg
          if !(arg_type.kind() is TK_Pointer) && !arg_type.is_array() {
            self.report_error(
              "scanf 的第 \{i + 1} 个参数必须是指针",
              loc,
              E3035_ScanfArgType,
            )
          }
        }
    }
  }
  @ast.Type::int()
}

///|
/// getchar（零参）。
fn TypeChecker::check_builtin_getchar(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  let _ = self.builtin_check_count(args, 0, "getchar", loc)
  @ast.Type::int()
}

///|
/// ungetc（两 int 参）。
fn TypeChecker::check_builtin_ungetc(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if self.builtin_check_count(args, 2, "ungetc", loc) {
    self.builtin_check_int(args, 0, "ungetc", loc)
    self.builtin_check_int(args, 1, "ungetc", loc)
  }
  @ast.Type::int()
}

///|
/// putchar（单 int 参；返回 void 是 N3 漂移登记——C 标准 int）。
fn TypeChecker::check_builtin_putchar(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if self.builtin_check_count(args, 1, "putchar", loc) {
    self.builtin_check_int(args, 0, "putchar", loc)
  }
  @ast.Type::void_type()
}

///|
/// fprintf（≥2 参：文件指针或整数 + 格式串 + 变参粗检）。
fn TypeChecker::check_builtin_fprintf(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if args.length() < 2 {
    self.report_error(
      "fprintf 至少需要 2 个参数（文件指针和格式字符串）",
      loc,
      E3030_PrintfArgCount,
    )
  } else {
    let (stream_type, new_a0) = self.resolve_expr_type(args[0])
    args[0] = new_a0
    if !(stream_type.kind() is TK_Pointer) && !(stream_type.kind() is TK_Int) {
      self.report_error(
        "fprintf 的第一个参数必须是文件指针或整数",
        loc,
        E3029_BuiltInArgType,
      )
    }
    let (fmt_type, new_a1) = self.resolve_expr_type(args[1])
    args[1] = new_a1
    if !(fmt_type.kind() is TK_Pointer) && !fmt_type.is_array() {
      self.report_error(
        "fprintf 的第二个参数必须是字符串",
        loc,
        E3031_PrintfFirstArg,
      )
    }
    for i in 2..<args.length() {
      let (arg_type, new_arg) = self.resolve_expr_type(args[i])
      args[i] = new_arg
      if !self.is_scalar(arg_type) &&
        !(arg_type.kind() is TK_Pointer) &&
        !arg_type.is_array() {
        self.report_error(
          "fprintf 的第 \{i + 1} 个参数必须是 int、float、char 或指针",
          loc,
          E3032_PrintfArgType,
        )
      }
    }
  }
  @ast.Type::void_type()
}

///|
/// puts（单指针参）。
fn TypeChecker::check_builtin_puts(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if self.builtin_check_count(args, 1, "puts", loc) {
    self.builtin_check_pointer(args, 0, "puts", loc)
  }
  @ast.Type::int()
}

///|
/// sprintf（≥2 参：buf 指针 + fmt 指针）。
fn TypeChecker::check_builtin_sprintf(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if args.length() < 2 {
    self.report_error(
      "sprintf 至少需要两个参数",
      loc,
      E3028_BuiltInArgCount,
    )
  } else {
    self.builtin_check_pointer(args, 0, "sprintf", loc)
    self.builtin_check_pointer(args, 1, "sprintf", loc)
  }
  @ast.Type::int()
}

///|
/// snprintf（≥3 参：buf 指针 + size int + fmt 指针）。
fn TypeChecker::check_builtin_snprintf(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if args.length() < 3 {
    self.report_error(
      "snprintf 至少需要三个参数",
      loc,
      E3028_BuiltInArgCount,
    )
  } else {
    self.builtin_check_pointer(args, 0, "snprintf", loc)
    self.builtin_check_int(args, 1, "snprintf", loc)
    self.builtin_check_pointer(args, 2, "snprintf", loc)
  }
  @ast.Type::int()
}

///|
/// sscanf（≥2 参：str 指针 + fmt 指针）。
fn TypeChecker::check_builtin_sscanf(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if args.length() < 2 {
    self.report_error(
      "sscanf 至少需要两个参数",
      loc,
      E3028_BuiltInArgCount,
    )
  } else {
    self.builtin_check_pointer(args, 0, "sscanf", loc)
    self.builtin_check_pointer(args, 1, "sscanf", loc)
  }
  @ast.Type::int()
}

///|
/// fgets（三参：buf 指针数组 / int / 文件指针）。
fn TypeChecker::check_builtin_fgets(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if self.builtin_check_count(args, 3, "fgets", loc) {
    let (buf_type, new_a0) = self.resolve_expr_type(args[0])
    args[0] = new_a0
    if !(buf_type.kind() is TK_Pointer) && !buf_type.is_array() {
      self.report_error(
        "fgets 第一个参数必须是指针或数组",
        loc,
        E3029_BuiltInArgType,
      )
    }
    let (n_type, new_a1) = self.resolve_expr_type(args[1])
    args[1] = new_a1
    if !self.check_assignable(@ast.Type::int(), n_type, loc) {
      self.report_error(
        "fgets 第二个参数必须是 int",
        loc,
        E3029_BuiltInArgType,
      )
    } else {
      args[1] = insert_implicit_cast(new_a1, @ast.Type::int())
    }
    let (stream_type, new_a2) = self.resolve_expr_type(args[2])
    args[2] = new_a2
    if !(stream_type.kind() is TK_Pointer) && !(stream_type.kind() is TK_Int) {
      self.report_error(
        "fgets 第三个参数必须是文件指针",
        loc,
        E3029_BuiltInArgType,
      )
    }
  }
  @ast.Type::pointer_to(@ast.Type::char())
}

///|
/// fputs（两参：字符串 + 文件指针）。
fn TypeChecker::check_builtin_fputs(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if self.builtin_check_count(args, 2, "fputs", loc) {
    let (s_type, new_a0) = self.resolve_expr_type(args[0])
    args[0] = new_a0
    if !(s_type.kind() is TK_Pointer) && !s_type.is_array() {
      self.report_error(
        "fputs 第一个参数必须是字符串",
        loc,
        E3029_BuiltInArgType,
      )
    }
    let (stream_type, new_a1) = self.resolve_expr_type(args[1])
    args[1] = new_a1
    if !(stream_type.kind() is TK_Pointer) && !(stream_type.kind() is TK_Int) {
      self.report_error(
        "fputs 第二个参数必须是文件指针",
        loc,
        E3029_BuiltInArgType,
      )
    }
  }
  @ast.Type::int()
}

// ---------- string（Rust builtin/string.rs）----------

///|
/// strlen（单指针参）。
fn TypeChecker::check_builtin_strlen(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if self.builtin_check_count(args, 1, "strlen", loc) {
    self.builtin_check_pointer(args, 0, "strlen", loc)
  }
  @ast.Type::int()
}

///|
/// strcpy（两指针参；返回 char* 是 N4 漂移登记——bytecode 侧 void）。
fn TypeChecker::check_builtin_strcpy(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if self.builtin_check_count(args, 2, "strcpy", loc) {
    self.builtin_check_pointer(args, 0, "strcpy", loc)
    self.builtin_check_pointer(args, 1, "strcpy", loc)
  }
  @ast.Type::pointer_to(@ast.Type::char())
}

///|
/// strdup（单指针参）。
fn TypeChecker::check_builtin_strdup(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if self.builtin_check_count(args, 1, "strdup", loc) {
    self.builtin_check_pointer(args, 0, "strdup", loc)
  }
  @ast.Type::pointer_to(@ast.Type::char())
}

///|
/// strcmp（两指针参）。
fn TypeChecker::check_builtin_strcmp(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if self.builtin_check_count(args, 2, "strcmp", loc) {
    self.builtin_check_pointer(args, 0, "strcmp", loc)
    self.builtin_check_pointer(args, 1, "strcmp", loc)
  }
  @ast.Type::int()
}

///|
/// strcat（两指针参；char* 同 N4 漂移登记）。
fn TypeChecker::check_builtin_strcat(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if self.builtin_check_count(args, 2, "strcat", loc) {
    self.builtin_check_pointer(args, 0, "strcat", loc)
    self.builtin_check_pointer(args, 1, "strcat", loc)
  }
  @ast.Type::pointer_to(@ast.Type::char())
}

///|
/// atoi（单指针参）。
fn TypeChecker::check_builtin_atoi(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if self.builtin_check_count(args, 1, "atoi", loc) {
    self.builtin_check_pointer(args, 0, "atoi", loc)
  }
  @ast.Type::int()
}

///|
/// strncat（三参：两指针 + int；char* 同 N4）。
fn TypeChecker::check_builtin_strncat(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if args.length() != 3 {
    self.report_error("strncat 需要三个参数", loc, E3028_BuiltInArgCount)
  } else {
    self.builtin_check_pointer(args, 0, "strncat", loc)
    self.builtin_check_pointer(args, 1, "strncat", loc)
    self.builtin_check_int(args, 2, "strncat", loc)
  }
  @ast.Type::pointer_to(@ast.Type::char())
}

///|
/// strncmp（三参：两指针 + int）。
fn TypeChecker::check_builtin_strncmp(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if args.length() != 3 {
    self.report_error("strncmp 需要三个参数", loc, E3028_BuiltInArgCount)
  } else {
    self.builtin_check_pointer(args, 0, "strncmp", loc)
    self.builtin_check_pointer(args, 1, "strncmp", loc)
    self.builtin_check_int(args, 2, "strncmp", loc)
  }
  @ast.Type::int()
}

///|
/// memcmp（三参：两指针 + int）。
fn TypeChecker::check_builtin_memcmp(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if args.length() != 3 {
    self.report_error("memcmp 需要三个参数", loc, E3028_BuiltInArgCount)
  } else {
    self.builtin_check_pointer(args, 0, "memcmp", loc)
    self.builtin_check_pointer(args, 1, "memcmp", loc)
    self.builtin_check_int(args, 2, "memcmp", loc)
  }
  @ast.Type::int()
}

///|
/// strchr（两参：指针 + int）。
fn TypeChecker::check_builtin_strchr(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if args.length() != 2 {
    self.report_error("strchr 需要两个参数", loc, E3028_BuiltInArgCount)
  } else {
    self.builtin_check_pointer(args, 0, "strchr", loc)
    self.builtin_check_int(args, 1, "strchr", loc)
  }
  @ast.Type::pointer_to(@ast.Type::char())
}

///|
/// strrchr（两参：指针 + int）。
fn TypeChecker::check_builtin_strrchr(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if args.length() != 2 {
    self.report_error("strrchr 需要两个参数", loc, E3028_BuiltInArgCount)
  } else {
    self.builtin_check_pointer(args, 0, "strrchr", loc)
    self.builtin_check_int(args, 1, "strrchr", loc)
  }
  @ast.Type::pointer_to(@ast.Type::char())
}

///|
/// strstr（两指针参）。
fn TypeChecker::check_builtin_strstr(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if args.length() != 2 {
    self.report_error("strstr 需要两个参数", loc, E3028_BuiltInArgCount)
  } else {
    self.builtin_check_pointer(args, 0, "strstr", loc)
    self.builtin_check_pointer(args, 1, "strstr", loc)
  }
  @ast.Type::pointer_to(@ast.Type::char())
}

///|
/// memchr（三参：指针 + 两 int）。
fn TypeChecker::check_builtin_memchr(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if args.length() != 3 {
    self.report_error("memchr 需要三个参数", loc, E3028_BuiltInArgCount)
  } else {
    self.builtin_check_pointer(args, 0, "memchr", loc)
    self.builtin_check_int(args, 1, "memchr", loc)
    self.builtin_check_int(args, 2, "memchr", loc)
  }
  @ast.Type::pointer_to(@ast.Type::void_type())
}

///|
/// atof（单指针参）。
fn TypeChecker::check_builtin_atof(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if self.builtin_check_count(args, 1, "atof", loc) {
    self.builtin_check_pointer(args, 0, "atof", loc)
  }
  @ast.Type::double()
}

///|
/// atol（单指针参）。
fn TypeChecker::check_builtin_atol(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if self.builtin_check_count(args, 1, "atol", loc) {
    self.builtin_check_pointer(args, 0, "atol", loc)
  }
  @ast.Type::long_long()
}

// ---------- math（Rust builtin/math.rs）----------

///|
/// rand（零参）。
fn TypeChecker::check_builtin_rand(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  let _ = self.builtin_check_count(args, 0, "rand", loc)
  @ast.Type::int()
}

///|
/// srand（单 int 参）。
fn TypeChecker::check_builtin_srand(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if self.builtin_check_count(args, 1, "srand", loc) {
    self.builtin_check_int(args, 0, "srand", loc)
  }
  @ast.Type::void_type()
}

///|
/// tan（单 double 参——可赋值即放行 + 隐式转换）。
fn TypeChecker::check_builtin_tan(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if self.builtin_check_count(args, 1, "tan", loc) {
    let (t, new_arg) = self.resolve_expr_type(args[0])
    if !self.check_assignable(@ast.Type::double(), t, loc) {
      self.report_error("tan 参数必须是 double", loc, E3029_BuiltInArgType)
    } else {
      args[0] = insert_implicit_cast(new_arg, @ast.Type::double())
    }
  }
  @ast.Type::double()
}

///|
/// log10（单 double 参）。
fn TypeChecker::check_builtin_log10(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if self.builtin_check_count(args, 1, "log10", loc) {
    let (t, new_arg) = self.resolve_expr_type(args[0])
    if !self.check_assignable(@ast.Type::double(), t, loc) {
      self.report_error(
        "log10 参数必须是 double",
        loc,
        E3029_BuiltInArgType,
      )
    } else {
      args[0] = insert_implicit_cast(new_arg, @ast.Type::double())
    }
  }
  @ast.Type::double()
}

///|
/// fabs（单 double 参）。
fn TypeChecker::check_builtin_fabs(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if self.builtin_check_count(args, 1, "fabs", loc) {
    let (t, new_arg) = self.resolve_expr_type(args[0])
    if !self.check_assignable(@ast.Type::double(), t, loc) {
      self.report_error(
        "fabs 参数必须是 double",
        loc,
        E3029_BuiltInArgType,
      )
    } else {
      args[0] = insert_implicit_cast(new_arg, @ast.Type::double())
    }
  }
  @ast.Type::double()
}

///|
/// ceil（单 double 参）。
fn TypeChecker::check_builtin_ceil(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if self.builtin_check_count(args, 1, "ceil", loc) {
    let (t, new_arg) = self.resolve_expr_type(args[0])
    if !self.check_assignable(@ast.Type::double(), t, loc) {
      self.report_error(
        "ceil 参数必须是 double",
        loc,
        E3029_BuiltInArgType,
      )
    } else {
      args[0] = insert_implicit_cast(new_arg, @ast.Type::double())
    }
  }
  @ast.Type::double()
}

///|
/// floor（单 double 参）。
fn TypeChecker::check_builtin_floor(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if self.builtin_check_count(args, 1, "floor", loc) {
    let (t, new_arg) = self.resolve_expr_type(args[0])
    if !self.check_assignable(@ast.Type::double(), t, loc) {
      self.report_error(
        "floor 参数必须是 double",
        loc,
        E3029_BuiltInArgType,
      )
    } else {
      args[0] = insert_implicit_cast(new_arg, @ast.Type::double())
    }
  }
  @ast.Type::double()
}

///|
/// round（单 double 参）。
fn TypeChecker::check_builtin_round(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if self.builtin_check_count(args, 1, "round", loc) {
    let (t, new_arg) = self.resolve_expr_type(args[0])
    if !self.check_assignable(@ast.Type::double(), t, loc) {
      self.report_error(
        "round 参数必须是 double",
        loc,
        E3029_BuiltInArgType,
      )
    } else {
      args[0] = insert_implicit_cast(new_arg, @ast.Type::double())
    }
  }
  @ast.Type::double()
}

///|
/// fmod（两 double 参）。
fn TypeChecker::check_builtin_fmod(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if args.length() != 2 {
    self.report_error("fmod 需要两个参数", loc, E3028_BuiltInArgCount)
  } else {
    for i in 0..<2 {
      let (t, new_arg) = self.resolve_expr_type(args[i])
      if !self.check_assignable(@ast.Type::double(), t, loc) {
        self.report_error(
          "fmod 第 \{i + 1} 个参数必须是 double",
          loc,
          E3029_BuiltInArgType,
        )
      } else {
        args[i] = insert_implicit_cast(new_arg, @ast.Type::double())
      }
    }
  }
  @ast.Type::double()
}

// ---------- memory（Rust builtin/memory.rs）----------

///|
/// malloc（单 int 参；E3024/E3025 专属码）。
fn TypeChecker::check_builtin_malloc(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if args.length() != 1 {
    self.report_error("malloc 需要一个参数", loc, E3024_MallocArgCount)
  } else {
    let expected = @ast.Type::int()
    let (arg_type, new_arg) = self.resolve_expr_type(args[0])
    if !self.check_assignable(expected, arg_type, loc) {
      self.report_error("malloc 参数必须是 int", loc, E3025_MallocArgType)
    } else {
      args[0] = insert_implicit_cast(new_arg, expected)
    }
  }
  @ast.Type::pointer_to(@ast.Type::void_type())
}

///|
/// free（单指针参）。
fn TypeChecker::check_builtin_free(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if self.builtin_check_count(args, 1, "free", loc) {
    self.builtin_check_pointer(args, 0, "free", loc)
  }
  @ast.Type::void_type()
}

///|
/// memset（三参：指针 + 两 int）。
fn TypeChecker::check_builtin_memset(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if args.length() != 3 {
    self.report_error("memset 需要三个参数", loc, E3028_BuiltInArgCount)
  } else {
    let (ptr_type, new_a0) = self.resolve_expr_type(args[0])
    args[0] = new_a0
    if !(ptr_type.kind() is TK_Pointer) && !ptr_type.is_array() {
      self.report_error(
        "memset 第一个参数必须是指针",
        loc,
        E3029_BuiltInArgType,
      )
    }
    for i in [1, 2] {
      let expected = @ast.Type::int()
      let (t, new_arg) = self.resolve_expr_type(args[i])
      if !self.check_assignable(expected, t, loc) {
        self.report_error(
          "memset 的第 \{i + 1} 个参数必须是 int",
          loc,
          E3029_BuiltInArgType,
        )
      } else {
        args[i] = insert_implicit_cast(new_arg, expected)
      }
    }
  }
  @ast.Type::pointer_to(@ast.Type::void_type())
}

///|
/// exit（单 int 参）。
fn TypeChecker::check_builtin_exit(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if self.builtin_check_count(args, 1, "exit", loc) {
    self.builtin_check_int(args, 0, "exit", loc)
  }
  @ast.Type::void_type()
}

///|
/// realloc（两参：指针或 int / int）。
fn TypeChecker::check_builtin_realloc(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if args.length() != 2 {
    self.report_error("realloc 需要两个参数", loc, E3028_BuiltInArgCount)
  } else {
    let (ptr_type, new_a0) = self.resolve_expr_type(args[0])
    args[0] = new_a0
    if !(ptr_type.kind() is TK_Pointer) && !(ptr_type.kind() is TK_Int) {
      self.report_error(
        "realloc 第一个参数必须是指针",
        loc,
        E3029_BuiltInArgType,
      )
    }
    let (size_type, new_a1) = self.resolve_expr_type(args[1])
    args[1] = new_a1
    if !self.check_assignable(@ast.Type::int(), size_type, loc) {
      self.report_error(
        "realloc 第二个参数必须是 int",
        loc,
        E3029_BuiltInArgType,
      )
    } else {
      args[1] = insert_implicit_cast(new_a1, @ast.Type::int())
    }
  }
  @ast.Type::pointer_to(@ast.Type::void_type())
}

///|
/// calloc（两 int 参）。
fn TypeChecker::check_builtin_calloc(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if args.length() != 2 {
    self.report_error("calloc 需要两个参数", loc, E3028_BuiltInArgCount)
  } else {
    for i in [0, 1] {
      self.builtin_check_int(args, i, "calloc", loc)
    }
  }
  @ast.Type::pointer_to(@ast.Type::void_type())
}

// ---------- file（Rust builtin/file.rs；FILE* 表示层 = void*）----------

///|
/// fopen（两字符串参）。
fn TypeChecker::check_builtin_fopen(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if args.length() != 2 {
    self.report_error(
      "fopen 需要两个参数（路径和模式）",
      loc,
      E3028_BuiltInArgCount,
    )
  } else {
    for i in [0, 1] {
      let (arg_type, new_arg) = self.resolve_expr_type(args[i])
      args[i] = new_arg
      if !(arg_type.kind() is TK_Pointer) && !arg_type.is_array() {
        self.report_error(
          "fopen 第 \{i + 1} 个参数必须是字符串",
          loc,
          E3029_BuiltInArgType,
        )
      }
    }
  }
  @ast.Type::pointer_to(@ast.Type::void_type())
}

///|
/// fread（四参：buf / 两 int / 文件指针）。
fn TypeChecker::check_builtin_fread(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if args.length() != 4 {
    self.report_error(
      "fread 需要四个参数（缓冲区、元素大小、元素数量、文件指针）",
      loc,
      E3028_BuiltInArgCount,
    )
  } else {
    let (buf_type, new_a0) = self.resolve_expr_type(args[0])
    args[0] = new_a0
    if !(buf_type.kind() is TK_Pointer) && !buf_type.is_array() {
      self.report_error(
        "fread 第一个参数必须是指针或数组",
        loc,
        E3029_BuiltInArgType,
      )
    }
    for i in [1, 2] {
      let (t, new_arg) = self.resolve_expr_type(args[i])
      if !self.check_assignable(@ast.Type::int(), t, loc) {
        self.report_error(
          "fread 第 \{i + 1} 个参数必须是 int",
          loc,
          E3029_BuiltInArgType,
        )
      } else {
        args[i] = insert_implicit_cast(new_arg, @ast.Type::int())
      }
    }
    let (stream_type, new_a3) = self.resolve_expr_type(args[3])
    args[3] = new_a3
    if !(stream_type.kind() is TK_Pointer) && !(stream_type.kind() is TK_Int) {
      self.report_error(
        "fread 第四个参数必须是文件指针",
        loc,
        E3029_BuiltInArgType,
      )
    }
  }
  @ast.Type::int()
}

///|
/// fwrite（四参：同 fread）。
fn TypeChecker::check_builtin_fwrite(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if args.length() != 4 {
    self.report_error(
      "fwrite 需要四个参数（缓冲区、元素大小、元素数量、文件指针）",
      loc,
      E3028_BuiltInArgCount,
    )
  } else {
    let (buf_type, new_a0) = self.resolve_expr_type(args[0])
    args[0] = new_a0
    if !(buf_type.kind() is TK_Pointer) && !buf_type.is_array() {
      self.report_error(
        "fwrite 第一个参数必须是指针或数组",
        loc,
        E3029_BuiltInArgType,
      )
    }
    for i in [1, 2] {
      let (t, new_arg) = self.resolve_expr_type(args[i])
      if !self.check_assignable(@ast.Type::int(), t, loc) {
        self.report_error(
          "fwrite 第 \{i + 1} 个参数必须是 int",
          loc,
          E3029_BuiltInArgType,
        )
      } else {
        args[i] = insert_implicit_cast(new_arg, @ast.Type::int())
      }
    }
    let (stream_type, new_a3) = self.resolve_expr_type(args[3])
    args[3] = new_a3
    if !(stream_type.kind() is TK_Pointer) && !(stream_type.kind() is TK_Int) {
      self.report_error(
        "fwrite 第四个参数必须是文件指针",
        loc,
        E3029_BuiltInArgType,
      )
    }
  }
  @ast.Type::int()
}

///|
/// fclose（单文件指针参）。
fn TypeChecker::check_builtin_fclose(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if self.builtin_check_count(args, 1, "fclose", loc) {
    let (stream_type, new_a0) = self.resolve_expr_type(args[0])
    args[0] = new_a0
    if !(stream_type.kind() is TK_Pointer) && !(stream_type.kind() is TK_Int) {
      self.report_error(
        "fclose 参数必须是文件指针",
        loc,
        E3029_BuiltInArgType,
      )
    }
  }
  @ast.Type::int()
}

///|
/// feof（单文件指针参）。
fn TypeChecker::check_builtin_feof(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if self.builtin_check_count(args, 1, "feof", loc) {
    let (stream_type, new_a0) = self.resolve_expr_type(args[0])
    args[0] = new_a0
    if !(stream_type.kind() is TK_Pointer) && !(stream_type.kind() is TK_Int) {
      self.report_error(
        "feof 参数必须是文件指针",
        loc,
        E3029_BuiltInArgType,
      )
    }
  }
  @ast.Type::int()
}

///|
/// fgetc（单文件指针参）。
fn TypeChecker::check_builtin_fgetc(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if self.builtin_check_count(args, 1, "fgetc", loc) {
    let (stream_type, new_a0) = self.resolve_expr_type(args[0])
    args[0] = new_a0
    if !(stream_type.kind() is TK_Pointer) && !(stream_type.kind() is TK_Int) {
      self.report_error(
        "fgetc 参数必须是文件指针",
        loc,
        E3029_BuiltInArgType,
      )
    }
  }
  @ast.Type::int()
}

///|
/// fputc（两参：int + 文件指针）。
fn TypeChecker::check_builtin_fputc(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if args.length() != 2 {
    self.report_error(
      "fputc 需要两个参数（字符和文件指针）",
      loc,
      E3028_BuiltInArgCount,
    )
  } else {
    let (c_type, new_a0) = self.resolve_expr_type(args[0])
    args[0] = new_a0
    if !self.check_assignable(@ast.Type::int(), c_type, loc) {
      self.report_error(
        "fputc 第一个参数必须是 int",
        loc,
        E3029_BuiltInArgType,
      )
    } else {
      args[0] = insert_implicit_cast(new_a0, @ast.Type::int())
    }
    let (stream_type, new_a1) = self.resolve_expr_type(args[1])
    args[1] = new_a1
    if !(stream_type.kind() is TK_Pointer) && !(stream_type.kind() is TK_Int) {
      self.report_error(
        "fputc 第二个参数必须是文件指针",
        loc,
        E3029_BuiltInArgType,
      )
    }
  }
  @ast.Type::int()
}

///|
/// fseek（三参：文件指针 + 两 int）。
fn TypeChecker::check_builtin_fseek(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if args.length() != 3 {
    self.report_error(
      "fseek 需要三个参数（文件指针、偏移量、起始位置）",
      loc,
      E3028_BuiltInArgCount,
    )
  } else {
    let (stream_type, new_a0) = self.resolve_expr_type(args[0])
    args[0] = new_a0
    if !(stream_type.kind() is TK_Pointer) && !(stream_type.kind() is TK_Int) {
      self.report_error(
        "fseek 第一个参数必须是文件指针",
        loc,
        E3029_BuiltInArgType,
      )
    }
    for i in [1, 2] {
      let (t, new_arg) = self.resolve_expr_type(args[i])
      if !self.check_assignable(@ast.Type::int(), t, loc) {
        self.report_error(
          "fseek 第 \{i + 1} 个参数必须是 int",
          loc,
          E3029_BuiltInArgType,
        )
      } else {
        args[i] = insert_implicit_cast(new_arg, @ast.Type::int())
      }
    }
  }
  @ast.Type::int()
}

///|
/// ftell（单文件指针参）。
fn TypeChecker::check_builtin_ftell(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if self.builtin_check_count(args, 1, "ftell", loc) {
    let (stream_type, new_a0) = self.resolve_expr_type(args[0])
    args[0] = new_a0
    if !(stream_type.kind() is TK_Pointer) && !(stream_type.kind() is TK_Int) {
      self.report_error(
        "ftell 参数必须是文件指针",
        loc,
        E3029_BuiltInArgType,
      )
    }
  }
  @ast.Type::int()
}

///|
/// rewind（单文件指针参）。
fn TypeChecker::check_builtin_rewind(
  self : TypeChecker,
  args : Array[@ast.Expr],
  loc : @source.SourceLoc,
) -> @ast.Type {
  if self.builtin_check_count(args, 1, "rewind", loc) {
    let (stream_type, new_a0) = self.resolve_expr_type(args[0])
    args[0] = new_a0
    if !(stream_type.kind() is TK_Pointer) && !(stream_type.kind() is TK_Int) {
      self.report_error(
        "rewind 参数必须是文件指针",
        loc,
        E3029_BuiltInArgType,
      )
    }
  }
  @ast.Type::void_type()
}
