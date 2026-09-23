///| 调用形态单一路由表的**黑盒契约**（`vitro/engine/bytecode` 的对外面）。
///
/// 黑盒 = 包外消费者视角（`codegen` 编译期选形态 / `host` 执行期分发都用这套面）。
/// 本文件同时承担对外面消费面（喂 `moonbit_surface -check`）——`route.mbt` 的
/// 每个 pub 符号都在这里被点名。
///
/// **三条跨包对账锚**（S4 坑② 的"以 libc 为单源回填"接续）：
/// ① `@bytecode.shadowed_host_names()` 必须恰是勘察 §1.7 点名的 20 个；
/// ② `@bytecode.builtin_name_union()` 与 `vitro/engine/libc` 的放行名全集逐名对齐
///    （差 `print_int` 一个别名）；
/// ③ 每个表内名都有**唯一**形态（`@bytecode.call_route` 恒返回恰一个分支）。

///|
/// 路由表的三个形态分支：固定索引 / Host / 用户函数。
test "call_route_three_ways" {
  // Bytecode Libc：88 名表内且不在改判集
  guard @bytecode.call_route("isdigit")
    is Some(@bytecode.CallRoute::BytecodeLibc(idx)) else {
    fail("isdigit 应走固定索引")
  }
  assert_eq(
    idx,
    BYTECODE_LIBC_BASE_INDEX + 0,
    msg="序 = 88 名表序（isdigit 是首个）",
  )
  guard @bytecode.call_route("abs")
    is Some(@bytecode.CallRoute::BytecodeLibc(i2)) else {
    fail("abs 走固定索引")
  }
  assert_eq(i2, BYTECODE_LIBC_BASE_INDEX + 11)
  // Host：诊断敏感 / 不在 88 名表内
  guard @bytecode.call_route("malloc") is Some(@bytecode.CallRoute::Host(h)) else {
    fail("malloc 应走 Host")
  }
  assert_eq(h, 2, msg="MALLOC = 2（Rust host_func_id.rs 原值）")
  guard @bytecode.call_route("printf") is Some(@bytecode.CallRoute::Host(h2)) else {
    fail("printf 应走 Host")
  }
  assert_eq(h2, 15)
  // 用户函数
  assert_true(@bytecode.call_route("main") is None)
  assert_true(@bytecode.call_route("my_func") is None)
  assert_true(@bytecode.call_route("") is None)
}

///|
/// **改判集**：`strcpy`/`strcat` 虽在 88 名表内，仍路由回 Host（Host 版带
/// E3070 栈缓冲区校验）。
test "host_rerouted_exceptions" {
  assert_true(@bytecode.is_host_rerouted("strcpy"))
  assert_true(@bytecode.is_host_rerouted("strcat"))
  assert_false(@bytecode.is_host_rerouted("strlen"))
  assert_false(@bytecode.is_host_rerouted("memcpy"))
  assert_true(
    @bytecode.call_route("strcpy") is Some(@bytecode.CallRoute::Host(_)),
    msg="strcpy 必须改判回 Host（不以固定索引形态出现）",
  )
  assert_true(
    @bytecode.call_route("strcat") is Some(@bytecode.CallRoute::Host(_)),
  )
  // 同族反例：strncpy 仍在固定索引段（同族分裂是现状，登记在案）
  assert_true(
    @bytecode.call_route("strncpy")
    is Some(@bytecode.CallRoute::BytecodeLibc(_)),
  )
}

///|
/// **遮蔽集显式化**：20 个 host handler 有实现但按名调用到不了。
///
/// 现版这条事实**无处可查**（两张表各自手写、无一处列出交集）。本锚把它钉死：
/// 名单或数量任一漂移即红，且新增例外必须改 `@bytecode.is_host_rerouted` 并在此登记。
test "shadowed_host_names_are_declared" {
  let shadowed = @bytecode.shadowed_host_names()
  assert_eq(shadowed.length(), @bytecode.SHADOWED_HOST_NAME_COUNT)
  assert_eq(@bytecode.SHADOWED_HOST_NAME_COUNT, 20)
  assert_eq(
    shadowed,
    [
      "isdigit", "isalpha", "islower", "isupper", "tolower", "toupper", "isspace",
      "isalnum", "isprint", "iscntrl", "isxdigit", "abs", "atoi", "srand", "rand",
      "strlen", "strcmp", "strncpy", "memcpy", "memmove",
    ],
    msg="遮蔽名单必须与勘察 §1.7 逐字一致",
  )
  // 遮蔽名仍**登记在 host 表**（只是路由不选它）——这正是"隐式覆盖"要显式化的点
  for name in shadowed {
    assert_true(
      @bytecode.is_host_func_name(name),
      msg="遮蔽名仍在 host 表内",
    )
  }
  // 改判集的两个名字**不在**遮蔽清单（它们实际路由到 Host）
  assert_false(shadowed.contains("strcpy"))
  assert_false(shadowed.contains("strcat"))
}

///|
/// **`by_user_name` 带 PURE 短路 ⇒ 不能当成员判定**（route.mbt 的派生前提）。
///
/// 这条锚锁住"为什么需要 `host_func_pairs` 全表"：14 个 PURE 名在
/// `host_func_id_by_user_name` 上一律返回 `None`，但它们**确实在 host 表里**。
test "pure_shortcircuit_blocks_membership_test" {
  assert_true(
    @bytecode.is_host_func_name("isdigit"),
    msg="isdigit 在 host 表内",
  )
  assert_eq(
    host_func_id_by_user_name("isdigit"),
    None,
    msg="但 by_user_name 对 PURE 名短路返回 None",
  )
  assert_true(@bytecode.is_host_func_name("strlen"))
  assert_eq(host_func_id_by_user_name("strlen"), None)
  // 非 PURE 的 host 名两边一致
  assert_true(@bytecode.is_host_func_name("malloc"))
  assert_eq(host_func_id_by_user_name("malloc"), Some(2))
  // 别名：print_int / __vitro_output 同指 OUTPUT
  assert_eq(host_func_id_by_user_name("print_int"), Some(0))
  assert_eq(host_func_id_by_user_name("__vitro_output"), Some(0))
}

///|
/// **跨表对账**：两表并集 = 176，且与 `vitro/engine/libc` 的放行名全集逐名对齐
/// （差 `print_int` 一个别名——S4 坑② 的"以 libc 为单源回填"在此接续）。
test "route_union_matches_libc_allowlist" {
  let u = @bytecode.builtin_name_union()
  assert_eq(
    u.length(),
    @bytecode.HOST_FUNC_NAME_COUNT + BYTECODE_LIBC_FUNC_COUNT - 22,
    msg="并集 = 110 + 88 − 交集 22 = 176",
  )
  assert_true(
    u.contains("print_int"),
    msg="并集含别名 print_int（它不在 libc 放行集内）",
  )
  let mismatched : Array[String] = []
  for name in u {
    if name == "print_int" {
      continue
    }
    if !@libc.is_libc_func(name) {
      mismatched.push(name)
    }
  }
  assert_eq(
    mismatched,
    [],
    msg="并集 − {print_int} 必须全在 libc 放行集内",
  )
  assert_false(
    @libc.is_libc_func("print_int"),
    msg="libc 放行集不含 print_int（别名，非放行名）",
  )
}

///|
/// 每个表内名都必须有**恰好一个**形态（表的"单一来源"性质的直接断言）。
test "every_table_name_has_exactly_one_route" {
  let missing : Array[String] = []
  for name in @bytecode.builtin_name_union() {
    if @bytecode.call_route(name) is None {
      missing.push(name)
    }
  }
  assert_eq(missing, [], msg="并集内每个名字都必须有形态")
  // 反向：非表内名不得有形态
  assert_true(@bytecode.call_route("main") is None)
  assert_true(@bytecode.call_route("__not_a_builtin") is None)
}
