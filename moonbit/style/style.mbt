///| StylePack 查询与 CSS 发射（手写面；数据面见 style_gen.mbt）。

///|
/// 契约：`css_text()` 的块结构与取值 ≡ `demo/src/tokens.css` 去掉头部两行
/// 注释与空行后的正文（同源同值，真源同一份 `moonbit/style/tokens.json`：
/// CSS 由 scripts/gen_demo_tokens 发射，本包由 scripts/gen_style 生成）。
/// 槽名一律 `--vr-` 前缀（历史名 `--vr-amber` 实为强调色 accent——2026-11-14
/// 批 A 决定先保名字不改值，别名层另批，避免既有 golden/样式契约连坐）。

///|
/// 取风格包；未知名 → None（不静默回落到默认包，fail loud 由调用方决定）。
pub fn pack(id : String) -> StylePack? {
  for p in style_packs() {
    if p.id == id {
      return Some(p)
    }
  }
  None
}

///|
/// 语义槽取值（未登记槽 → None）。
pub fn slot(p : StylePack, name : String) -> String? {
  for kv in p.slots {
    if kv.0 == name {
      return Some(kv.1)
    }
  }
  None
}

///|
/// 写一个 CSS 变量块（与 gen_demo_tokens 的 writeBlock 同形：`sel {\n` +
/// 可选 color-scheme + 逐槽 `name: value;\n` + `}\n`）。
fn write_block(
  b : StringBuilder,
  sel : String,
  scheme : String,
  slots : Array[(String, String)],
) -> Unit {
  b.write_string(sel)
  b.write_string(" {\n")
  if scheme != "" {
    b.write_string("  color-scheme: ")
    b.write_string(scheme)
    b.write_string(";\n")
  }
  for kv in slots {
    b.write_string("  ")
    b.write_string(kv.0)
    b.write_string(": ")
    b.write_string(kv.1)
    b.write_string(";\n")
  }
  b.write_string("}\n")
}

///|
/// 单包块（选择器由调用方给，如 `:root[data-theme="paper"]`）。
pub fn css_block(p : StylePack, sel : String) -> String {
  let b = StringBuilder()
  write_block(b, sel, p.scheme, p.slots)
  b.to_string()
}

///|
/// 基座块（`:root`——字体 / 字号 / 圆角 / 时长 / 缓动）。
pub fn css_base() -> String {
  let b = StringBuilder()
  write_block(b, ":root", "", style_base())
  b.to_string()
}

///|
/// 全量 CSS 正文（基座 → 五主题 → 三字号档，块间空行；≡ tokens.css 正文）。
pub fn css_text() -> String {
  let b = StringBuilder()
  b.write_string(css_base())
  b.write_string("\n")
  for p in style_packs() {
    write_block(b, ":root[data-theme=\"" + p.id + "\"]", p.scheme, p.slots)
    b.write_string("\n")
  }
  let sizes = style_sizes()
  for i, kv in sizes {
    write_block(b, ":root[data-size=\"" + kv.0 + "\"]", "", kv.1)
    if i < sizes.length() - 1 {
      b.write_string("\n")
    }
  }
  b.to_string()
}
