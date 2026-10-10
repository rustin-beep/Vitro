///|
test "stdlib_headers_catalog" {
  // P1 锚：清单规模/首尾（Rust match 序冻结——重排即红）/后缀/去重。
  // 与目录、stubs 产物的集合对账在 Go 侧 gen_stubs（fail loud），本锚防
  // 手抖删条目与顺序漂移。
  let hs = headers()
  inspect(hs.length(), content="14")
  inspect(hs[0], content="stdio.h")
  inspect(hs[hs.length() - 1], content="float.h")
  for h in hs {
    if !h.has_suffix(".h") {
      fail("头文件名须 .h 后缀: " + h)
    }
  }
  let dedup : Set[String] = Set([])
  for h in hs {
    if dedup.contains(h) {
      fail("清单重复条目: " + h)
    }
    dedup.add(h)
  }
  inspect(dedup.length(), content="14")
}
