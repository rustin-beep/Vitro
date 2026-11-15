///| 风格包白盒锚（数据面由 scripts/gen_style 生成；本文件锁契约面与 CSS 形态）。

///|
test "style_packs_theme_order" {
  let ps = style_packs()
  assert_eq(ps.length(), 5, msg="五主题")
  assert_eq(ps[0].id, "ice")
  assert_eq(ps[1].id, "rose")
  assert_eq(ps[2].id, "soft")
  assert_eq(ps[3].id, "paper")
  assert_eq(ps[4].id, "blueprint")
  assert_eq(ps[2].scheme, "dark", msg="soft 为夜侧")
  assert_eq(ps[4].scheme, "dark", msg="blueprint 为夜侧")
  assert_eq(ps[3].scheme, "light", msg="paper 为日侧")
}

///|
test "slot_paper_keys" {
  match pack("paper") {
    None => assert_true(false, msg="paper 包缺失")
    Some(p) => {
      // 历史名 --vr-amber 在 paper = 棕橙；在 ice = 蓝 #1d4ed8（名字与语义
      // 脱钩的实证，别名层另批，本批只锁值不变）。
      match slot(p, "--vr-bg") {
        Some(v) => assert_eq(v, "#efe7d8", msg="--vr-bg")
        None => assert_true(false, msg="--vr-bg 缺失")
      }
      match slot(p, "--vr-amber") {
        Some(v) => assert_eq(v, "#96520a", msg="--vr-amber")
        None => assert_true(false, msg="--vr-amber 缺失")
      }
      match slot(p, "--vr-swap") {
        Some(v) => assert_eq(v, "#2a6b74", msg="--vr-swap")
        None => assert_true(false, msg="--vr-swap 缺失")
      }
      match slot(p, "--vr-kw") {
        Some(v) => assert_eq(v, "#9b3a2a", msg="--vr-kw")
        None => assert_true(false, msg="--vr-kw 缺失")
      }
    }
  }
}

///|
test "pack_unknown_fails_loud" {
  assert_true(pack("nope") is None, msg="未知名不回落默认包")
  assert_true(pack("") is None, msg="空名不回落默认包")
  assert_true(pack("paper") is Some(_), msg="合法名可命中")
}

///|
test "base_and_sizes_shape" {
  assert_eq(style_base().length(), 13, msg="基座 13 个 token")
  let sizes = style_sizes()
  assert_eq(sizes.length(), 3, msg="三档字号")
  assert_eq(sizes[0].0, "13", msg="数值升序首档")
  assert_eq(sizes[2].0, "16")
}

///|
test "css_text_blocks" {
  let css = css_text()
  assert_true(css.contains(":root {\n"), msg="基座块")
  assert_true(
    css.contains("  color-scheme: dark;\n"),
    msg="夜侧主题带 color-scheme",
  )
  assert_true(
    css.contains(":root[data-theme=\"paper\"] {\n"),
    msg="主题选择器",
  )
  assert_true(
    css.contains(":root[data-size=\"13\"] {\n"),
    msg="字号档选择器",
  )
  assert_true(
    css.contains("  --vr-bg: #efe7d8;\n"),
    msg="paper 基色落到 CSS",
  )
  assert_true(css.contains("  --vr-mono: ui-monospace"), msg="字体栈原样")
}

///|
test "css_block_single_pack" {
  match pack("blueprint") {
    None => assert_true(false, msg="blueprint 缺失")
    Some(p) => {
      let blk = css_block(p, ":root[data-theme=\"blueprint\"]")
      assert_true(
        blk.contains("  color-scheme: dark;\n"),
        msg="单包块带 scheme",
      )
      assert_true(
        blk.contains(":root[data-theme=\"blueprint\"] {\n"),
        msg="选择器原样",
      )
    }
  }
}

///|
test "digest_shape" {
  let d = style_digest()
  assert_eq(d.length(), 7 + 64, msg="sha256: + 64 hex")
  assert_true(d.contains("sha256:"), msg="前缀")
}
