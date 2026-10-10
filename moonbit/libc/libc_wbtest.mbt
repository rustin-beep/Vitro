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
  // N3 销案锚（批四 2026-10-07）：printf/putchar/fprintf 返回 int
  //（C 标准 + stdio.h 存根口径；旧锚 Void 系照搬登记形态，已翻转）
  let printf = lookup("printf").unwrap()
  assert_true(printf.return_type is Int(_, _))
  assert_eq(printf.min_args, 1)
  assert_eq(printf.max_args, -1)
  assert_true(lookup("putchar").unwrap().return_type is Int(_, _))
  assert_true(lookup("fprintf").unwrap().return_type is Int(_, _))
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

///|
/// N4 销案锚（批四 2026-10-07）：bytecode_libc_sig 的 C 面条目与
/// 头文件存根/C 标准对齐——strcpy/strcat/strncpy 返回 char*、
/// memcpy/memmove 返回 void*（旧表 void 系 Rust 期表间漂移，第四级
/// 回退放行无存根调用时返回类型错了；strcpy/strcat 臂被 libc_table
/// 先拦不可达，对齐是死臂清理）。
test "bytecode_libc_sig_c_face_returns" {
  let (r_strcpy, _) = bytecode_libc_sig("strcpy").unwrap()
  assert_true(r_strcpy is Pointer(Char(_, _), _))
  let (r_strcat, _) = bytecode_libc_sig("strcat").unwrap()
  assert_true(r_strcat is Pointer(Char(_, _), _))
  let (r_strncpy, p_strncpy) = bytecode_libc_sig("strncpy").unwrap()
  assert_true(r_strncpy is Pointer(Char(_, _), _))
  assert_eq(p_strncpy.length(), 3)
  let (r_memcpy, _) = bytecode_libc_sig("memcpy").unwrap()
  assert_true(r_memcpy is Pointer(_, _))
  let (r_memmove, _) = bytecode_libc_sig("memmove").unwrap()
  assert_true(r_memmove is Pointer(_, _))
  // 旧形态锚定边界：srand 维持 void（C 标准本就 void）
  let (r_srand, _) = bytecode_libc_sig("srand").unwrap()
  assert_true(r_srand is Void(_))
}

///|
/// 表完整性静态锚（审阅处置批二 2026-10-10 P0-②）：libc_table 的
/// param_kinds 字符集必须 ⊆ {P, I, D}——在**表加载层**就红，早于任何
/// 语料跑（typeck 的运行时 abort 是第二层纵深；786e8102 的 "PX" 手误
/// 曾同时引爆 vm_diff/typeck_diff/codegen_diff/clang_direct 四道防线
/// 而单测全绿——本锚把这类手误的检出点从差分防线前移到包内单测）。
/// 码元直比（UInt16——String 索引陷阱 #24，与 check_builtin_table 同式）。
test "libc_table_param_kinds_charset" {
  for entry in libc_table {
    for i = 0; i < entry.param_kinds.length(); i = i + 1 {
      let k = entry.param_kinds[i]
      assert_true(
        k == 80 || k == 73 || k == 68,
        msg="\{entry.name} 的 param_kinds 第 \{i + 1} 位码元 \{k} 非法（合法集 P/I/D）",
      )
    }
  }
}
