///|
/// resolve_binary 关键面（promote / 指针算术 / 比较定型 / 逗号右值 /
/// 移位左提升；改判据此锚红）。
test "resolve_binary_key_shapes" {
  let loc = @source.SourceLoc::new(1, 5)
  let tc = TypeChecker::new()
  tc.enter_scope()
  fn lit(v : Int32) -> @ast.Expr {
    @ast.Expr::Literal(v, loc, @ast.Type::int())
  }
  fn flit(v : Double) -> @ast.Expr {
    @ast.Expr::FloatLiteral(v, loc, @ast.Type::double())
  }
  // int + double → double
  let (ty, e) = tc.resolve_binary(Add, lit(1), flit(2.0), loc)
  assert_true(ty is Double(_))
  match e {
    Binary(Add, _, _, _, t) => assert_true(t is Double(_))
    _ => fail("Binary 重建形态")
  }
  // int + int → int
  let (ty2, _) = tc.resolve_binary(Mul, lit(3), lit(4), loc)
  assert_true(ty2 is Int(_, _))
  // 指针 + 整数 → 指针；数组 + 整数 → decay 到元素指针
  tc.declare_var(
    "p",
    @ast.Type::pointer_to(@ast.Type::int()),
    is_global=false,
    is_extern=false,
    is_static=false,
  )
  tc.declare_var(
    "arr",
    @ast.Type::array_of(@ast.Type::int(), [4]),
    is_global=false,
    is_extern=false,
    is_static=false,
  )
  let pid = @ast.Expr::Identifier("p", loc, @ast.Type::void_type())
  let (ty3, _) = tc.resolve_binary(Add, pid, lit(2), loc)
  match ty3 {
    Pointer(pointee, _) => assert_true(pointee is Int(_, _))
    _ => fail("指针+整数应保持指针")
  }
  let aid = @ast.Expr::Identifier("arr", loc, @ast.Type::void_type())
  let (ty3b, _) = tc.resolve_binary(Add, aid, lit(2), loc)
  match ty3b {
    Pointer(pointee, _) => assert_true(pointee is Int(_, _))
    _ => fail("数组+整数应 decay 到元素指针")
  }
  // 比较 → int
  let (ty4, _) = tc.resolve_binary(Lt, lit(1), lit(2), loc)
  assert_true(ty4 is Int(_, _))
  // 逗号 → 右值类型
  let (ty5, _) = tc.resolve_binary(Comma, lit(1), flit(2.0), loc)
  assert_true(ty5 is Double(_))
  // 移位：char 左操作数提升 int
  let (ty6, _) = tc.resolve_binary(
    Shl,
    @ast.Expr::Literal(1, loc, @ast.Type::char()),
    lit(1),
    loc,
  )
  assert_true(ty6 is Int(_, _))
  assert_eq(tc.errors.length(), 0)
}

///|
/// 三目 decay（`" "` 与 `""` 统一 char*——勘察 §6 语境的防线）与分支
/// 不匹配 E3004。
test "resolve_ternary_decay" {
  let loc = @source.SourceLoc::new(2, 3)
  let tc = TypeChecker::new()
  let s1 = @ast.Expr::StringLiteral(" ", loc, @ast.Type::void_type())
  let s2 = @ast.Expr::StringLiteral("", loc, @ast.Type::void_type())
  let cond = @ast.Expr::Literal(1, loc, @ast.Type::int())
  let (ty, _) = tc.resolve_ternary(cond, s1, s2, loc)
  match ty {
    Pointer(pointee, _) => assert_true(pointee is Char(_, _))
    _ => fail("两 char 数组三目应 decay 统一 char*")
  }
  assert_eq(tc.errors.length(), 0)
  // issue #9 翻转（2026-10-06）：int vs double 算术分支做 usual
  // arithmetic conversions 统一为 double（零错——旧严格同型 E3004 系
  // 两侧同病照搬，Clang `x ? 2 : 3.5` 合法）
  let lit = @ast.Expr::Literal(1, loc, @ast.Type::int())
  let flit = @ast.Expr::FloatLiteral(2.0, loc, @ast.Type::double())
  let (uty, _) = tc.resolve_ternary(cond, lit, flit, loc)
  assert_eq(tc.errors.length(), 0, msg="混合数值三目统一非报错")
  assert_true(uty.kind() is TK_Double, msg="统一结果为 double")
  // 真不匹配形态：char* vs int（指针与算术不统一）→ E3004 仍在
  let _ = tc.resolve_ternary(cond, s1, lit, loc)
  assert_eq(tc.errors.length(), 1)
  assert_true(tc.errors[0].code == 3004)
}

///|
/// 一元（取址/解引用互逆 + 宽度保留 + 自增 const 检查 E3049）。
test "resolve_unary_shapes" {
  let loc = @source.SourceLoc::new(1, 1)
  let tc = TypeChecker::new()
  tc.enter_scope()
  tc.declare_var(
    "n",
    @ast.Type::int(),
    is_global=false,
    is_extern=false,
    is_static=false,
  )
  // 取址 → int*；再解引用 → int（互逆）
  let id = @ast.Expr::Identifier("n", loc, @ast.Type::void_type())
  let (pty, _) = tc.resolve_unary(Addr, id, loc)
  match pty {
    Pointer(pointee, _) => assert_true(pointee is Int(_, _))
    _ => fail("取址应得指针")
  }
  let id2 = @ast.Expr::Identifier("n", loc, @ast.Type::void_type())
  let (dty, _) = tc.resolve_unary(
    Deref,
    @ast.Expr::Unary(Addr, id2, loc, pty),
    loc,
  )
  assert_true(dty is Int(_, _))
  // 取负宽度保留：double → double；long long → long long
  let flit = @ast.Expr::FloatLiteral(2.0, loc, @ast.Type::double())
  let (nt, _) = tc.resolve_unary(Neg, flit, loc)
  assert_true(nt is Double(_))
  let llit = @ast.Expr::LongLiteral(2L, loc, @ast.Type::long_long())
  let (nt2, _) = tc.resolve_unary(Neg, llit, loc)
  assert_true(nt2 is LongLong(_, _))
  // 自增 const：E3049
  tc.declare_var(
    "c",
    @ast.Type::int().set_const(true),
    is_global=false,
    is_extern=false,
    is_static=false,
  )
  let cid = @ast.Expr::Identifier("c", loc, @ast.Type::void_type())
  let _ = tc.resolve_unary(PostInc, cid, loc)
  assert_eq(tc.errors.length(), 1)
  assert_true(tc.errors[0].code == 3049)
}

///|
/// 赋值（左值判定 E3043 / check_assignable E3044 / **Cast 插入 lowering**
/// / 指针复合赋值特判）。
test "resolve_assign_shapes" {
  let loc = @source.SourceLoc::new(3, 1)
  let tc = TypeChecker::new()
  tc.enter_scope()
  tc.declare_var(
    "d",
    @ast.Type::double(),
    is_global=false,
    is_extern=false,
    is_static=false,
  )
  tc.declare_var(
    "i",
    @ast.Type::int(),
    is_global=false,
    is_extern=false,
    is_static=false,
  )
  // d = 1（int→double）：insert_implicit_cast → Cast 包裹（lowering 锚）
  let lhs = @ast.Expr::Identifier("d", loc, @ast.Type::void_type())
  let rhs = @ast.Expr::Literal(1, loc, @ast.Type::int())
  let (ty, e) = tc.resolve_assign(Assign, lhs, rhs, loc)
  assert_true(ty is Double(_))
  match e {
    Assign(Assign, _, right, _, _) =>
      match right {
        Cast(_, target, _, t) => {
          assert_true(target is Double(_))
          assert_true(t is Double(_))
        }
        _ => fail("int→double 赋值右值应包 Cast")
      }
    _ => fail("Assign 重建形态")
  }
  assert_eq(tc.errors.length(), 0)
  // 类型不匹配：int 左值 = double 右值会插 Cast（可赋值）——用字符串测
  // E3044：int = char 数组不可赋值
  let lhs2 = @ast.Expr::Identifier("i", loc, @ast.Type::void_type())
  let rhs2 = @ast.Expr::StringLiteral("x", loc, @ast.Type::void_type())
  let _ = tc.resolve_assign(Assign, lhs2, rhs2, loc)
  assert_eq(tc.errors.length(), 1)
  assert_true(tc.errors[0].code == 3044)
  // 非左值：字面量左值 E3043
  let lit = @ast.Expr::Literal(1, loc, @ast.Type::int())
  let _ = tc.resolve_assign(Assign, lit, lit, loc)
  assert_eq(tc.errors.length(), 2)
  assert_true(tc.errors[1].code == 3043)
  // 指针 += 整数：跳过兼容检查（合法，无新错）
  tc.declare_var(
    "p",
    @ast.Type::pointer_to(@ast.Type::int()),
    is_global=false,
    is_extern=false,
    is_static=false,
  )
  let plhs = @ast.Expr::Identifier("p", loc, @ast.Type::void_type())
  let _ = tc.resolve_assign(
    AddAssign,
    plhs,
    @ast.Expr::Literal(2, loc, @ast.Type::int()),
    loc,
  )
  assert_eq(tc.errors.length(), 2)
}

///|
/// _Generic 选择（decay 匹配 char* 关联；无匹配无 default → E3004；
/// default 兜底）。
test "resolve_generic_selection" {
  let loc = @source.SourceLoc::new(1, 1)
  let tc = TypeChecker::new()
  // 控制表达式 char 数组 → decay char* → 命中 char* 关联
  let ctrl = @ast.Expr::StringLiteral("x", loc, @ast.Type::void_type())
  let assoc_int = @ast.Expr::Literal(1, loc, @ast.Type::int())
  let assoc_charp = @ast.Expr::Literal(2, loc, @ast.Type::int())
  let (ty, _) = tc.resolve_generic(
    ctrl,
    [
      (@ast.Type::int(), assoc_int),
      (@ast.Type::pointer_to(@ast.Type::char()), assoc_charp),
    ],
    None,
    loc,
  )
  assert_true(ty is Int(_, _))
  assert_eq(tc.errors.length(), 0)
  // 无匹配无 default → E3004
  let ctrl2 = @ast.Expr::StringLiteral("x", loc, @ast.Type::void_type())
  let _ = tc.resolve_generic(
    ctrl2,
    [(@ast.Type::int(), @ast.Expr::Literal(1, loc, @ast.Type::int()))],
    None,
    loc,
  )
  assert_eq(tc.errors.length(), 1)
  assert_true(tc.errors[0].code == 3004)
  // default 兜底
  let ctrl3 = @ast.Expr::StringLiteral("x", loc, @ast.Type::void_type())
  let (ty3, _) = tc.resolve_generic(
    ctrl3,
    [(@ast.Type::int(), @ast.Expr::Literal(1, loc, @ast.Type::int()))],
    Some(@ast.Expr::FloatLiteral(1.0, loc, @ast.Type::double())),
    loc,
  )
  assert_true(ty3 is Double(_))
  assert_eq(tc.errors.length(), 1) // 无新错
}

///|
/// 病 3 锚（#47，2026-10-09）：`char*` → `const char*` 是 C11 §6.5.16.1
/// 的安全方向（目标指向类型的限定符不弱于源即合法），零 W3067；旧实现
/// type_eq 严格等不认 pointee 顶层 const 增强，假阳性（文案还渲染成两侧
/// 同型 "char*" 自相矛盾）。两条负锚锁不放松面：base 类型不同、多级指针
/// const 增强（char** → const char**，C 标准判非法）均维持 W3067。
test "assign_const_gain_pointer_no_w3067" {
  let loc = @source.SourceLoc::new(1, 1)
  // char* a; const char* b = a;
  let tc = TypeChecker::new()
  let ok = tc.check_assignable(
    @ast.Type::Pointer(@ast.Type::Char(false, true), false),
    @ast.Type::Pointer(@ast.Type::Char(false, false), false),
    loc,
  )
  assert_true(ok, msg="const 增强方向须可赋值")
  assert_eq(tc.warnings.length(), 0, msg="const 增强方向不得产警告")
  // 负锚 1：int* → char*（base 不同）照报
  let tc2 = TypeChecker::new()
  ignore(
    tc2.check_assignable(
      @ast.Type::Pointer(@ast.Type::Char(false, false), false),
      @ast.Type::Pointer(@ast.Type::Int(false, false), false),
      loc,
    ),
  )
  assert_eq(
    tc2.errors.length(),
    1,
    msg="base 类型不同须维持 E3067（#50 批②升级）",
  )
  // 负锚 2：char** → const char**（多级指针 const 增强，C 判非法）照报
  let tc3 = TypeChecker::new()
  ignore(
    tc3.check_assignable(
      @ast.Type::Pointer(
        @ast.Type::Pointer(@ast.Type::Char(false, true), false),
        false,
      ),
      @ast.Type::Pointer(
        @ast.Type::Pointer(@ast.Type::Char(false, false), false),
        false,
      ),
      loc,
    ),
  )
  assert_eq(
    tc3.errors.length(),
    1,
    msg="多级 const 增强维持 E3067（C 标准；#50 批②升级）",
  )
}

///|
/// #56 锚：空指针常量（C11 §6.3.2.3）转指针是定义良好语义，零 W3054——
/// parser 把 NULL 折为 Literal(0, void*)，与字面量 0 同形，`v == 0` 一并
/// 覆盖（实机样本 batch24 `time(NULL)` 全族曾误报、Clang -Wall -Wextra
/// 干净）。负锚锁教学警示面：非零常量、标识符（非常量）、无表达式句柄
/// （builtin 参数面等保守路径）照旧 W3054。
test "assign_null_pointer_constant_no_w3054" {
  let loc = @source.SourceLoc::new(1, 1)
  let char_ptr = @ast.Type::Pointer(@ast.Type::Char(false, false), false)
  // char* p = NULL（parser 折 Literal(0, void*)）
  let tc = TypeChecker::new()
  let ok = tc.check_assignable(
    char_ptr,
    @ast.Type::int(),
    loc,
    value_expr=@ast.Expr::Literal(
      0,
      loc,
      @ast.Type::pointer_to(@ast.Type::void_type()),
    ),
  )
  assert_true(ok, msg="NULL 赋指针须可赋值")
  assert_eq(tc.warnings.length(), 0, msg="NULL 不得产 W3054")
  // char* p = 0（字面量 0）
  let tc2 = TypeChecker::new()
  ignore(
    tc2.check_assignable(
      char_ptr,
      @ast.Type::int(),
      loc,
      value_expr=@ast.Expr::Literal(0, loc, @ast.Type::int()),
    ),
  )
  assert_eq(tc2.warnings.length(), 0, msg="字面量 0 不得产 W3054")
  // 负锚 1：非零常量照报
  let tc3 = TypeChecker::new()
  ignore(
    tc3.check_assignable(
      char_ptr,
      @ast.Type::int(),
      loc,
      value_expr=@ast.Expr::Literal(5, loc, @ast.Type::int()),
    ),
  )
  assert_eq(
    tc3.errors.length(),
    1,
    msg="非零整数常量须维持 E3054（#50 批②升级）",
  )
  // 负锚 2：标识符（非常量整数表达式）照报
  let tc4 = TypeChecker::new()
  ignore(
    tc4.check_assignable(
      char_ptr,
      @ast.Type::int(),
      loc,
      value_expr=@ast.Expr::Identifier("x", loc, @ast.Type::int()),
    ),
  )
  assert_eq(
    tc4.errors.length(),
    1,
    msg="非常量整数表达式须维持 E3054（#50 批②升级）",
  )
  // 负锚 3：无表达式句柄（builtin 参数面等）保守照报
  let tc5 = TypeChecker::new()
  ignore(tc5.check_assignable(char_ptr, @ast.Type::int(), loc))
  assert_eq(
    tc5.errors.length(),
    1,
    msg="无表达式句柄时保守维持 E3054（#50 批②升级）",
  )
}

///|
/// builtin 释义文案外置等价锚（#60 批三段二，2026-10-10）：A/B 类臂
/// count 释义句与参数位句——改造前逐字节基线（错误串取 tc.errors[0]）。
/// #130 批③a 起 builtin_notes 拆 content_data（wbtest 不可跨包 import
/// ——fixture-install 技法：装载内联载荷后断言，测试自此与烘焙数据
/// 解耦且更 hermetic）。测尾回装空表（lean 初始态，不污染同包后续）。
test "builtin_notes_migration_snapshot_before" {
  let fixture = Json::object({
    "suggestions": Json::object({}),
    "builtin_notes": Json::object({
      "fread": Json::object({
        "count_note": Json::string(
          "fread 需要四个参数（缓冲区、元素大小、元素数量、文件指针）",
        ),
        "param_notes": Json::array([]),
      }),
      "fseek": Json::object({
        "count_note": Json::string(""),
        "param_notes": Json::array([
          Json::string("fseek 第一个参数必须是文件指针"),
        ]),
      }),
      "rewind": Json::object({
        "count_note": Json::string(""),
        "param_notes": Json::array([
          Json::string("rewind 参数必须是文件指针"),
        ]),
      }),
    }),
    // trap_messages 段缺席（二轮审阅 P2 起在场段须与烘焙表键集全等——
    // 本 fixture 只装 builtin 两键，trap 不碰）
  })
  @assets.install_texts(fixture.stringify()) catch {
    _ => fail("fixture 装载失败")
  }
  let loc = @source.SourceLoc::new(1, 1)
  // fread：count 释义（0 参触发）
  let tc = TypeChecker::new()
  ignore(tc.check_builtin_fread([], loc))
  assert_true(tc.errors.length() > 0, msg="fread 0 参须报错")
  assert_eq(
    tc.errors[0].message,
    "fread 需要四个参数（缓冲区、元素大小、元素数量、文件指针）",
  )
  // fseek：第一个参数 int（非 FILE*）触发参数位句
  let tc2 = TypeChecker::new()
  let dlit = @ast.Expr::FloatLiteral(2.0, loc, @ast.Type::double())
  let ilot = @ast.Expr::Literal(1, loc, @ast.Type::int())
  ignore(tc2.check_builtin_fseek([dlit, ilot, ilot], loc))
  assert_true(tc2.errors.length() > 0, msg="fseek int 实参须报错")
  assert_eq(tc2.errors[0].message, "fseek 第一个参数必须是文件指针")
  // rewind：单参特判句
  let tc3 = TypeChecker::new()
  ignore(tc3.check_builtin_rewind([dlit], loc))
  assert_true(tc3.errors.length() > 0, msg="rewind int 实参须报错")
  assert_eq(tc3.errors[0].message, "rewind 参数必须是文件指针")
  // 回装空表（lean 初始态）
  @assets.install_texts(
    "{\"suggestions\":{},\"builtin_notes\":{},\"trap_messages\":{}}",
  ) catch {
    _ => ()
  }
}

///|
/// #50 审阅 P1-1 锚：case 常量性判据按语义不绑节点形态——`case -1:`/
/// `case 1+2:` 是 Unary/Binary 包 Literal（原 Literal 单形态判据假阳性拒
/// 合法 C，avlTree 模板 6 处 case -1: 三闸连坐红）；变量 case 仍拒。
test "case_const_expr_forms_pass" {
  // 结构判据直测：负/取反/二元算术全放行
  let loc = @source.SourceLoc::new(1, 1)
  assert_true(
    is_int_constant_expr(@ast.Expr::Literal(1, loc, @ast.Type::int())),
    msg="字面量",
  )
  assert_true(
    is_int_constant_expr(
      @ast.Expr::Unary(
        @ast.UnaryOp::Neg,
        @ast.Expr::Literal(1, loc, @ast.Type::int()),
        loc,
        @ast.Type::int(),
      ),
    ),
    msg="一元负（case -1: 形态）",
  )
  assert_true(
    is_int_constant_expr(
      @ast.Expr::Binary(
        @ast.BinaryOp::Add,
        @ast.Expr::Literal(1, loc, @ast.Type::int()),
        @ast.Expr::Literal(2, loc, @ast.Type::int()),
        loc,
        @ast.Type::int(),
      ),
    ),
    msg="二元算术（case 1+2: 形态）",
  )
  assert_false(
    is_int_constant_expr(@ast.Expr::Identifier("n", loc, @ast.Type::int())),
    msg="变量 case 须拒",
  )
  // 求值域：Neg 折叠（P2-3 死臂激活）
  assert_eq(
    const_int_value(
      @ast.Expr::Unary(
        @ast.UnaryOp::Neg,
        @ast.Expr::Literal(1, loc, @ast.Type::int()),
        loc,
        @ast.Type::int(),
      ),
    ),
    Some(-1),
    msg="a[-1] 的 -1 须可求值（W3051 负值臂）",
  )
}

///|
/// W3067→E3067 文案 const 附注锚（#61 遗留 5 轻项，2026-10-10）：name()
/// 是照搬的核心名渲染（不含限定符），`const char* ← int*` 场景学生看不出
/// 差异点——文案须渲出目标 const。
test "assign_mismatch_copy_renders_const" {
  let loc = @source.SourceLoc::new(1, 1)
  let tc = TypeChecker::new()
  ignore(
    tc.check_assignable(
      @ast.Type::Pointer(@ast.Type::Char(false, true), false),
      @ast.Type::Pointer(@ast.Type::Int(false, false), false),
      loc,
    ),
  )
  assert_eq(tc.errors.length(), 1)
  assert_true(
    tc.errors[0].message.contains("const char*"),
    msg="目标 pointee 带 const 须渲出（差异点可见）",
  )
}

///|
/// #63 红→绿锚（2026-10-10）：const 二维数组形参（`const int g[9][9]` 退化
/// `const int(*)[9]` ← 实参 `int(*)[9]`）——const 在 pointee 数组的
/// **element 层**，病 3 的单层 strip 够不着；限定符加宽须递归方向性判定
///（v 每层 const ⊆ t 才放行；反向剥 const 仍拒）。
test "assign_const_2d_array_param_widening" {
  let loc = @source.SourceLoc::new(1, 1)
  // const int(*)[9] ← int(*)[9]：放行（C11 §6.5.16.1 限定符加宽）
  let tc = TypeChecker::new()
  let ok = tc.check_assignable(
    @ast.Type::Pointer(
      @ast.Type::Array(@ast.Type::Int(false, true), 9, [9], false, false, []),
      false,
    ),
    @ast.Type::Pointer(
      @ast.Type::Array(@ast.Type::Int(false, false), 9, [9], false, false, []),
      false,
    ),
    loc,
  )
  assert_true(ok, msg="const int g[9][9] 形参收 int grid[9][9]")
  assert_eq(tc.errors.length(), 0)
  // 反向（int(*)[9] ← const int(*)[9]）：剥 const 仍拒（写穿风险）
  let tc2 = TypeChecker::new()
  let bad = tc2.check_assignable(
    @ast.Type::Pointer(
      @ast.Type::Array(@ast.Type::Int(false, false), 9, [9], false, false, []),
      false,
    ),
    @ast.Type::Pointer(
      @ast.Type::Array(@ast.Type::Int(false, true), 9, [9], false, false, []),
      false,
    ),
    loc,
  )
  assert_true(
    bad,
    msg="指针赋值路径本身可达（报错在 E3067 臂）",
  )
  assert_eq(tc2.errors.length(), 1, msg="剥 const 方向维持 E3067")
}

///|
/// 病 30 锚（#61 第一梯队，2026-10-11）：C 整型提升（C11 §6.3.1.8）
/// ——rank 低于 int 的小无符号（unsigned char）提升为 **signed int**，
/// unsigned 位不传播进结果；uint vs long long 时 i64 可表示 u32 全值域
/// → signed long long（lower 的 unsigned 只在同 rank 时传播）。
/// 锚先红后修（改判据此锚）。
test "promote_usual_arithmetic_conversions_issue61_b30" {
  let loc = @source.SourceLoc::new(1, 5)
  let tc = TypeChecker::new()
  tc.enter_scope()
  tc.declare_var(
    "uc",
    @ast.Type::Char(true, false),
    is_global=false,
    is_extern=false,
    is_static=false,
  )
  tc.declare_var(
    "u",
    @ast.Type::Int(true, false),
    is_global=false,
    is_extern=false,
    is_static=false,
  )
  fn lit(v : Int32) -> @ast.Expr {
    @ast.Expr::Literal(v, loc, @ast.Type::int())
  }
  // uchar - 1 → int（signed；(uc-1)/2 = 0 而非 2147483647 的定型根）
  let ucid = @ast.Expr::Identifier("uc", loc, @ast.Type::void_type())
  let (t1, _) = tc.resolve_binary(Sub, ucid, lit(1), loc)
  assert_true(t1 is Int(_, _))
  assert_false(t1.is_unsigned(), msg="uchar 提升后 unsigned 位不得传播")
  // uint - 5LL → long long（signed；i64 装得下 u32 全域）
  tc.declare_var(
    "ll",
    @ast.Type::LongLong(false, false),
    is_global=false,
    is_extern=false,
    is_static=false,
  )
  let uid = @ast.Expr::Identifier("u", loc, @ast.Type::void_type())
  let llid = @ast.Expr::Identifier("ll", loc, @ast.Type::void_type())
  let (t2, _) = tc.resolve_binary(Sub, uid, llid, loc)
  assert_true(t2 is LongLong(false, _), msg="uint vs LL 应落 signed LL")
  // 同 rank 双侧：uint vs int → unsigned int（unsigned 正常传播面）
  let (t3, _) = tc.resolve_binary(Sub, uid, lit(1), loc)
  assert_true(t3 is Int(true, _))
  // ULL vs LL → unsigned long long（同 rank 传播 + higher 自身 unsigned）
  let (t4, _) = tc.resolve_binary(
    Sub,
    @ast.Expr::Literal(1, loc, @ast.Type::LongLong(true, false)),
    @ast.Expr::Literal(5, loc, @ast.Type::LongLong(false, false)),
    loc,
  )
  assert_true(t4 is LongLong(true, _))
  assert_eq(tc.errors.length(), 0)
}

///|
/// #63 尾巴锚（2026-10-13）：E3067 数组指针渲染——pointee 为数组时用
/// C 记法 `int (*)[9]`（clang 同款）；旧 `name()*` 组装压扁成 `int*`
/// 丢全部维度（`char (*)[9] ← int (*)[9]` 曾显示 `char* ← int*`）。
test "e3067_array_pointer_render" {
  let loc = @source.SourceLoc::new(4, 10)
  let tc = TypeChecker::new()
  let t = tc.check_pointer_assignable(
    @ast.Type::pointer_to(@ast.Type::array_of(@ast.Type::char(), [9])),
    @ast.Type::pointer_to(@ast.Type::array_of(@ast.Type::int(), [9])),
    loc,
    None,
  )
  ignore(t)
  assert_eq(tc.errors.length(), 1, msg="不兼容数组指针须报 E3067")
  let msg = tc.errors[0].message
  assert_true(
    msg.contains("char (*)[9]"),
    msg="目标侧应为数组指针记法：\{msg}",
  )
  assert_true(
    msg.contains("int (*)[9]"),
    msg="源侧应为数组指针记法：\{msg}",
  )
  // 标量 pointee 维持旧形态（char* ← int*）
  let tc2 = TypeChecker::new()
  ignore(
    tc2.check_pointer_assignable(
      @ast.Type::pointer_to(@ast.Type::char()),
      @ast.Type::pointer_to(@ast.Type::int()),
      loc,
      None,
    ),
  )
  assert_eq(tc2.errors.length(), 1)
  assert_true(
    tc2.errors[0].message.contains("char* ← int*"),
    msg="标量指针形态不变：\{tc2.errors[0].message}",
  )
}

///|
/// #80（2026-10-13 报 / 2026-10-14 修）：const 限定符**丢弃方向**降警告——
/// `const int[3]` decay 给 `int*`（赋值位 E3044 / 初始化位 E3004）与
/// `const int*` 给 `int*`（pointee 丢弃 E3067），clang/gcc 默认仅警告
/// （-Wincompatible-pointer-types-discards-qualifiers），旧一律 error
/// 误拒合法 C。单层语义（pointee/element 顶层 const 位）；深层 char** 族
/// 不覆盖（登记扩面）。
test "issue80_const_discard_warning" {
  let tc = TypeChecker::new()
  let loc = @source.SourceLoc::new(2, 10)
  let loc2 = @source.SourceLoc::new(3, 10)
  let const_int = @ast.Type::Int(false, true)
  let int_ptr = @ast.Type::Pointer(@ast.Type::int(), false)
  // f2/f3 形态：const int[3] → int*（赋值/初始化同一判定链）
  let const_arr = @ast.Type::Array(const_int, 3, [3], false, false, [])
  assert_true(tc.check_assignable(int_ptr, const_arr, loc))
  // pp 形态：const int* → int*（pointee 顶层 const 丢弃）
  let const_int_ptr = @ast.Type::Pointer(const_int, false)
  assert_true(tc.check_assignable(int_ptr, const_int_ptr, loc2))
  // 核心：零 error + 每形态一条 W3053
  inspect(tc.errors.length(), content="0")
  inspect(tc.warnings.length(), content="2")
  // 反例锚：真不兼容（int* ← double*）维持 E3067
  let tc2 = TypeChecker::new()
  let double_ptr = @ast.Type::Pointer(@ast.Type::double(), false)
  assert_true(tc2.check_assignable(int_ptr, double_ptr, loc))
  inspect(tc2.errors.length(), content="1")
  inspect(tc2.errors[0].code, content="3067")
  // 反例锚：安全加宽方向（int[] → const int*）维持零 error 零警告
  let tc3 = TypeChecker::new()
  let const_int_ptr_t = @ast.Type::Pointer(const_int, false)
  let plain_arr = @ast.Type::Array(@ast.Type::int(), 3, [3], false, false, [])
  assert_true(tc3.check_assignable(const_int_ptr_t, plain_arr, loc))
  inspect(tc3.errors.length(), content="0")
  inspect(tc3.warnings.length(), content="0")
}
