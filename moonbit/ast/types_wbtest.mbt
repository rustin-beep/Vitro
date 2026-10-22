///|
/// #84（2026-10-13 报 / 2026-10-14 修）：subscript_type 对 VLA 维的派生
/// size 归 0——与声明符侧「最外维 0 → size_prod 恒 0」对齐；旧「0 维按
/// 1 乘」产物 size=1 与声明 pointee（恒 0）type_eq 假阴性，二维 VLA
/// decay 给行指针（int (*dp)[n+2] = t）误拒 E3004。
test "issue84_subscript_type_vla_size_zero" {
  // t: int[3][n+2]（dims=[3,0] VLA）——subscript 应得 int[n+2]（dims=[0]、size=0）
  let t = Type::Array(Type::int(), 0, [3, 0], false, true, [])
  let sub = t.subscript_type()
  match sub {
    Array(_, size, dims, _, is_vla, _) => {
      inspect(size, content="0")
      inspect(dims.length(), content="1")
      inspect(dims[0], content="0")
      inspect(is_vla, content="true")
    }
    _ => fail("subscript 产物应为 VLA 数组")
  }
  // 与声明符产的行指针 pointee（size=0）判等——decay 判定链的核心面
  let pointee = Type::Array(Type::int(), 0, [0], false, true, [])
  assert_true(type_eq(sub, pointee))
  // 反例锚：非 VLA 形态 size 判等不受影响（int[4] ≠ int[5]）
  assert_false(
    type_eq(
      Type::Array(Type::int(), 4, [4], false, false, []),
      Type::Array(Type::int(), 5, [5], false, false, []),
    ),
  )
}

///|
/// #265（2026-10-22）：subscript_type 剥首维后 is_vla 只在剩余维仍含
/// VLA（0 哨兵）时传导——cast 维数误判数组（`char a[(int)3][N]`）与
/// 真 VLA（`char a[n][N]`）decay 出的 pointee 都是定长 char[N]，不再
/// 带 VLA 标记误拒传参 E3038；第二维 VLA（[3,0]→[0]）维持传导（#84 面）。
test "issue265_subscript_vla_flag_clears_when_rest_const" {
  // cast 维数误判形态：dims=[0,40]（第一维误判 VLA）——剥首维 [40] 定长
  let miscast = Type::Array(Type::char(), 0, [0, 40], false, true, [])
  match miscast.subscript_type() {
    Array(_, size, dims, _, is_vla, _) => {
      inspect(size, content="40")
      inspect(dims[0], content="40")
      inspect(is_vla, content="false")
    }
    _ => fail("subscript 产物应为数组")
  }
  // 真 VLA 同款：第一维运行时、内层定长——C99 传 `char out[][N]` 合法
  let true_vla = Type::Array(Type::char(), 0, [0, 40], false, true, [])
  match true_vla.subscript_type() {
    Array(_, _, _, _, is_vla, _) => inspect(is_vla, content="false")
    _ => fail("subscript 产物应为数组")
  }
  // 判等面：decay pointee 与形参 pointee（定长）type_eq 通过
  let param_pointee = Type::Array(Type::char(), 40, [40], false, false, [])
  assert_true(type_eq(miscast.subscript_type(), param_pointee))
}

///|
/// 病 80 锚（#71，2026-10-16）：type_display_name 的 Function 臂字段序
/// 绑定——变体序 (return, params, is_const, is_variadic)。旧形态第三位
/// （is_const）被绑成 is_variadic：const 函数指针显假 "..."、真变参丢。
test "type_display_function_arity_binding_locked" {
  let variadic = Type::Function(Type::int(), [Type::int()], false, true)
  let plain = Type::Function(Type::int(), [Type::int()], false, false)
  let const_fn = Type::Function(Type::int(), [Type::int()], true, false)
  assert_eq(type_display_name(variadic), "int (*)(int, ...)")
  assert_eq(type_display_name(plain), "int (*)(int)")
  // const 位不再被误读为变参（假 "..." 消灭）
  assert_eq(type_display_name(const_fn), "int (*)(int)")
}
