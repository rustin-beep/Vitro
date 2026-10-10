// util·render（issue #60 批二，2026-10-10）：教学文案模板渲染器——零语义
// 机械件（`{key}` 占位符替换，G-1 纪律）。消费面 = teaching/assets 的
// trap_messages 模板与各装配点（trap/host_memory 的文案函数）。
//
// 失败形态（教学引擎口径）：占位符缺参/写坏时**保留 `{key}` 原文**——
// 可见可诊断（学生看到字面 {freed_line} 即知引擎装配漏参），不 abort
// 不静默；多传参数忽略（模板是契约面，多传不破坏渲染）。实现为段级
// 切片（String 索引是 UInt16 码元——陷阱 #24——不逐字符处理，段
// [a:b] 切片 + to_owned 取拥有串）。

///|
/// 模板渲染：`tpl` 中所有 `{key}` 以 `params` 中同名项替换。
/// 缺参的占位符保留原文（可见失败信号）；不支持转义（教学文案面
/// 无字面花括号——各模板入资产前审计）。
pub fn render_template(
  tpl : String,
  params : Array[(String, String)],
) -> String {
  let buf = StringBuilder()
  let n = tpl.length()
  let mut seg = 0 // 上一段起点（未写入位置）
  let mut i = 0
  while i < n {
    if tpl[i] == 123 {
      // '{'：找闭合 '}'（占位符名 = (i, j) 切片）
      let mut j = i + 1
      let mut closed = false
      while j < n {
        if tpl[j] == 125 {
          closed = true
          break
        }
        j = j + 1
      }
      if closed && j > i + 1 && is_placeholder_name(tpl[i + 1:j].to_owned()) {
        let name = tpl[i + 1:j].to_owned()
        let mut hit : String? = None
        for pair in params {
          if pair.0 == name {
            hit = Some(pair.1)
            break
          }
        }
        match hit {
          // 命中：写前段 + 参数值
          Some(v) => {
            buf.write_string(tpl[seg:i].to_owned())
            buf.write_string(v)
            seg = j + 1
          }
          // 缺参：保留原文（含花括号）——可见失败信号；不推进 seg
          None => ()
        }
        i = j + 1
      } else {
        // 未闭合 / 空 name：按普通字符跳过（段会在下次命中或收尾时带上）
        i = i + 1
      }
    } else {
      i = i + 1
    }
  }
  // 收尾段（含全部未命中占位符与普通文本）
  buf.write_string(tpl[seg:n].to_owned())
  buf.to_string()
}

///|
/// 占位符名合法性（#60 批二）：仅标识符字符（字母/数字/下划线，且首
/// 字符非数字）才算占位符——教学文案中的字面花括号段（C 代码示例
/// 「if (b != 0) {」）含空白/标点/换行，不构成占位符，原样透传。
fn is_placeholder_name(view : String) -> Bool {
  let n = view.length()
  if n == 0 {
    return false
  }
  let first = view[0]
  if !((first >= 97 && first <= 122) ||
    (first >= 65 && first <= 90) ||
    first == 95) {
    return false
  }
  for k in 1..<n {
    let c = view[k]
    let idc = (c >= 97 && c <= 122) ||
      (c >= 65 && c <= 90) ||
      (c >= 48 && c <= 57) ||
      c == 95
    if !idc {
      return false
    }
  }
  true
}
