///| L6 产物层·**C 字符串字节通道单源**（P4 口径照搬——Rust `vitro_shared::cstring`）。
///
/// **B6 批（#429）改「码元=字节」单一口径**：字面量 String 的码元恒为
/// 字节值——hex/八进制转义产码元=字节值（P4 起如此），非转义源字符由
/// 解码层（scanner/string.mbt）按 UTF-8 字节拆装码元（B6 起）——逐码元
/// 直出即 C 字节序列：`\xE4` 单字节 E4、源内「你」三字节 E4 BD A0，
/// 两面同时对齐三方编译器（M22 A-1 / M07 A6 / M09 D1 销案）。
///
/// 口径史（诚实记录）：P4 原版「≤0xFF 单字节、>0xFF UTF-8」双分支——
/// 对转义面对、对源字符面错（源内 ·/×/° 码点 ≤0xFF 落单字节与 clang
/// UTF-8 execution charset 分叉）；#66（2026-10-10）改整串 UTF-8 encode
/// ——源字符面对、转义面错（`\xb7` 落 C2 B7 双字节，sizeof 与 clang 分
/// 叉，注释自认「F2 已知差异面换位」）；两版都是「String 承载不区分
/// 转义字节/源字符」下的单边妥协——B6 解码层拆装治本后无须妥协。
///
/// **argv 通道不走本单源**：argv[i] 是宿主 Unicode 串（码点可 >0xFF，
/// 非解码层产物），字节口径 = UTF-8（`argv_region_footprint` 的
/// `@util.utf8_len` 同口径）——vm `setup_argv` 直接 `@utf8.encode` 写入。
///
/// **单源义务（S6 vm 批一号上提）**：本口径原 priv 在 L6 `codegen/init.mbt`
/// （字符串延迟回填 P2 的私有实现）；跨 L6/L7 复用上提为独立单源——
/// 定义点唯一在本包（L6 产物层，codegen 同层消费、vm 向下消费，
/// 依赖方向合法），两侧禁再私写。
///
/// 值域约定：码元 > 0xFF 的输入（wbtest 手构/未来路径失误）按 Latin-1
/// 低位投影（`& 0xFF`）fail-soft——引擎路径不可达（解码层保证），不设
/// panic 面（装载期 fail loud 属编译器 bug 域，由 verify 层兜）。

///|
/// C 字符串字节序列（不含结尾 NUL）——逐码元直出（码元=字节）。
pub fn cstring_bytes(s : String) -> Array[Byte] {
  let out : Array[Byte] = []
  for i = 0; i < s.length(); i = i + 1 {
    out.push((s[i].to_int() & 0xFF).to_byte())
  }
  out
}

///|
/// C 语义字节长度（不含结尾 NUL）——分配/对齐计算用 = 码元数
/// （与 `cstring_bytes` 产出恒等；与 typeck `resolve_string_literal`
/// 的计长是「同实现两符号」等价约束——改任何一侧须连坐另一侧）。
pub fn cstring_len(s : String) -> Int32 {
  s.length()
}
