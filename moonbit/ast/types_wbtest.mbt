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
