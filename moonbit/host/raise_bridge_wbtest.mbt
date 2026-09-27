// G-3 raise 桥保真锚（2026-09-27）：桥必须原样传递 MemFault 类型——
// 丢类型（J9 实证：固定 OutOfBounds 注入下 host 白盒与 vm_diff/clang_direct
// 双防线全绿）= 全防线盲区，学生将看到错误诊断（UAF 被报成越界）。
// fault 类型是 trap 文案单点（vm 渲染按变体分派）的输入面，锚锁之。

///|
test "raise_bridge_fault_type_fidelity_uaf" {
  let map = @memory.MemoryMap::new()
  let mem = @memory.Memory::new()
  let r = host_malloc(map, 16, 1)
  let addr = match r.value {
    Some(a) => a.to_uint()
    None => fail("malloc 应成功")
  }
  let fr = host_free(map, addr, 2, 2)
  assert_true(fr.trap is None, msg="free 应成功")
  // UAF 读：read_cstring 必须以 UseAfterFree 形态 raise（经桥原样传递）
  let outcome : Result[Bytes, AccessFault] = Ok(
    read_cstring_raise(mem, map, addr),
  ) catch {
    e => Err(e)
  }
  match outcome {
    Ok(_) => fail("UAF 读必须故障")
    Err(AccessFault::Fault(f~)) =>
      assert_true(
        f is @memory.MemFault::UseAfterFree(_),
        msg="桥丢类型：UAF 被替换成别的 MemFault 变体——诊断错乱",
      )
  }
}

///|
/// 用户审阅五轮 P2② 补锚：handler 层 catch 短路语义（trap 路径）——
/// 既有 host 测试全用合法地址（审阅突变实证：H1/H2/H3 三处 catch 短路
/// 吞 trap 全绿 108/108），桥类型保真有锚而短路无锚。以下三锚分别锁
/// 中间绑定（fopen path 读）/ 尾位置语句（va_start 写）/ read_fd 链
/// （fread）的「非法地址 → 必须 trap 且文案正确」。
test "handler_trap_fopen_illegal_path" {
  let map = @memory.MemoryMap::new()
  let mem = @memory.Memory::new()
  let vfs = VirtualFileSystem::new()
  // path 越界 + mode 合法（零页空串——防「顺路第二故障」救绿锚：
  // 审阅 H1 注入下 path 被吞成空串 → vfs.fopen() 失败 → null_silent
  // → trap 缺失 → 本锚红；若 mode 也非法，mode 读的 trap 会顶替命中）
  let r = host_fopen(map, mem, vfs, 0x200000U, 0x1000U, 1)
  match r.trap {
    Some(t) =>
      assert_true(
        t.contains("越界") || t.contains("NULL"),
        msg="fopen 非法 path 必须 trap（实得：\{t}）",
      )
    None =>
      fail(
        "fopen 非法 path 被吞：trap 缺失（catch 短路语义回退）",
      )
  }
}

///|
test "handler_trap_va_start_illegal_ap" {
  let map = @memory.MemoryMap::new()
  let mem = @memory.Memory::new()
  // ap 指针越界——尾位置 store_u32_raise 的 catch 必须转 trap
  let r = host_va_start(mem, map, 0x200000U, 0, 4)
  match r.trap {
    Some(t) =>
      assert_true(
        t.contains("越界"),
        msg="va_start 非法 ap 必须 trap（实得：\{t}）",
      )
    None =>
      fail("va_start 非法 ap 被吞：尾位置 catch 短路语义回退")
  }
}

///|
test "handler_trap_fread_illegal_stream" {
  let map = @memory.MemoryMap::new()
  let mem = @memory.Memory::new()
  let vfs = VirtualFileSystem::new()
  // stream 指针越界——read_fd_raise 链必须短路成 trap
  let r = host_fread(map, mem, vfs, 0x1000U, 1, 1, 0x200000U)
  match r.trap {
    Some(t) =>
      assert_true(
        t.contains("越界"),
        msg="fread 非法 stream 必须 trap（实得：\{t}）",
      )
    None => fail("fread 非法 stream 被吞：read_fd 链 catch 短路回退")
  }
}
