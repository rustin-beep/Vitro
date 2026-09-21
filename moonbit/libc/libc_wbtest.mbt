///|
/// 表完整性：57 条（visit_call 58 臂去 std__move；增删臂必改此锚）+
/// 名唯一性（同名双条会让 lookup 静默取先——Map 同键覆盖同族风险，
/// 勘察 §⑥-4/5）。
test "libc_table_completeness_and_unique" {
  assert_eq(libc_table.length(), 57)
  let seen : Set[String] = Set([])
  for sig in libc_table {
    assert_false(seen.contains(sig.name))
    seen.add(sig.name)
  }
  assert_eq(seen.length(), 57)
}

///|
/// 关键签名抽查（照搬现状口径——Rust builtin/*.rs 逐条提取；漂移
/// 登记 N3/N4 的条目在此锚定，修正须同步本表与差异台账）。
test "libc_sig_spots" {
  // N3 漂移锚：printf 返回 void（C 标准为 int——现状照搬，登记不修正）
  let printf = lookup("printf").unwrap()
  assert_true(printf.return_type is Void(_))
  assert_eq(printf.min_args, 1)
  assert_eq(printf.max_args, -1)
  // scanf 返回 int（条目 3 修复后口径）
  let scanf = lookup("scanf").unwrap()
  assert_true(scanf.return_type is Int(_, _))
  // malloc → void*；strcpy 族 → char*（N4：bytecode_libc_sig 侧为 void）
  assert_true(lookup("malloc").unwrap().return_type is Pointer(_, _))
  assert_true(lookup("strcpy").unwrap().return_type is Pointer(_, _))
  // 变参/定参边界
  assert_eq(lookup("fmod").unwrap().max_args, 2)
  assert_eq(lookup("fprintf").unwrap().max_args, -1)
  assert_eq(lookup("bsearch").unwrap().min_args, 5)
  // 特殊臂入表
  assert_true(is_libc_func("qsort"))
  // std__move 不入表（C++ 语义臂，S9 裁定）
  assert_false(is_libc_func("std__move"))
  // 表外名：sqrt 无签名（lookup None——visit_call 无检查臂，走存根路径）
  // 但**放行**（is_libc_func 在 175 并集内——F2 修复后的判据语义）
  assert_true(is_libc_func("sqrt"))
  assert_true(lookup("sqrt") is None)
  // 纯 C 缺口抽查（F2：无存根路径下的调用放行判据）
  assert_true(is_libc_func("pow"))
  assert_true(is_libc_func("memcpy"))
  assert_true(is_libc_func("toupper"))
  assert_true(is_libc_func("__vitro_va_start"))
  // print_int 在签名表但不在放行并集（Rust host_func_id 无此名——
  // 调用放行靠 funcs 表等判据；判据与签名是两个面）
  assert_true(lookup("print_int") is Some(_))
  assert_false(is_libc_func("print_int"))
}

///|
/// 放行全集计数与结构（175 = 109 host_func_id ∪ 88 bytecode_libc 去
/// 重叠 22；含 C++ 容器名——判据语义照搬，C 模式不活跃）。
test "builtin_all_membership" {
  assert_eq(builtin_all.length(), 175)
  // 签名表 57 名中 56 名 ⊆ 并集（print_int 例外，见上）
  let mut in_union = 0
  for sig in libc_table {
    if builtin_all.contains(sig.name) {
      in_union += 1
    }
  }
  assert_eq(in_union, 56)
}

///|
/// 全表不变式：min ≤ max（max=-1 变参除外）——数据自洽锚。
test "libc_table_invariants" {
  for sig in libc_table {
    if sig.max_args >= 0 {
      assert_true(sig.min_args <= sig.max_args)
    } else {
      assert_eq(sig.max_args, -1)
    }
    assert_true(sig.min_args >= 0)
  }
}
