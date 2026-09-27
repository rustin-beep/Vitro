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
