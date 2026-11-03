// B6 批（#429）红锚：json_parse 孤代理拒绝 + 大指数 O(1)。
//
// 形态一（M38 A2 / M06 A1）：\uXXXX 分支 `unsafe_to_char` 无孤立代理校验
// ——parse 接受 `\uD800`，String 携带孤立代理码元，下游 utf8_len /
// utf8_bytes（@utf8.encode 薄包）panic "invalid surrogate pair"（abort，
// try/catch 不可恢复；M38b 探针两次证红）。gateway wasm 是浏览器不受信
// 输入面，一条 `"\uD800"` 报文即可打崩 serve 会话。修复口径 = serde_json
// （RFC 8259 §8.2 互操作性建议）：高代理后必须紧跟 \uDC00-\uDFFF 转义，
// 否则拒绝；孤立低代理同理拒绝。#419（lexer 源码侧 lone surrogate abort）
// 是同族另一面，归 W4 尾件批——本锚只锁 json_parse 入口。
//
// 形态二（M38 A1）：accumulate_double 指数应用循环（逐乘/逐除）无上限，
// `1e99999999999` 的 exp Int32 累积 wrap 后 12 亿次循环实测 ~2.9s（js 臂）
// ——11 字节换 3 秒 CPU 的线性 DoS。修复 = exp 饱和累积（防 wrap）+ 域
// 边界 break（v 到 inf/0 后继续乘除是空转）。1e4294967297（2^32+1）在
// 修前 wrap 成 exp=1 ⇒ 值 10.0（静默错值），修后饱和 ⇒ inf——值断言红锚。

///|
/// parse 成功与否的探针形态（拒绝 → None）。
fn b6_parse_opt(s : String) -> Json? {
  let v = json_parse(s) catch { _ => return None }
  Some(v)
}

///|
/// 数字值提取（非 Number 形态给 None）。
fn b6_number_value(s : String) -> Double? {
  match b6_parse_opt(s) {
    Some(Json::Number(n, repr~)) => {
      ignore(repr)
      Some(n)
    }
    _ => None
  }
}

///|
test "json_parse_rejects_lone_high_surrogate_b6" {
  // 修前红：parse 接受孤立高代理（M38b 探针实录 String.length()==1）
  inspect(b6_parse_opt("\"\\uD800\"") is None, content="true")
  inspect(b6_parse_opt("\"\\uDBFF\"") is None, content="true")
  // 高代理后跟普通字符（非 \u 转义）——serde_json 同拒
  inspect(b6_parse_opt("\"\\uD800A\"") is None, content="true")
  // 高代理后跟 \u 转义但非低代理段
  inspect(b6_parse_opt("\"\\uD800\\u0041\"") is None, content="true")
  inspect(b6_parse_opt("\"\\uD800\\uD800\"") is None, content="true")
}

///|
test "json_parse_rejects_lone_low_surrogate_b6" {
  // 孤立低代理（前无高代理）——serde_json 同拒
  inspect(b6_parse_opt("\"\\uDC00\"") is None, content="true")
  inspect(b6_parse_opt("\"\\uDFFF\"") is None, content="true")
  // 低代理出现在普通字符之后
  inspect(b6_parse_opt("\"A\\uDC00\"") is None, content="true")
}

///|
test "json_parse_surrogate_pair_accepted_b6" {
  // 合法代理对：\uD800\uDC00 = U+10000（String 两码元；for-in 迭代出
  // 单码点）——修复保持透传拼接形态（合法路径行为不变）
  match b6_parse_opt("\"\\uD800\\uDC00\"") {
    Some(Json::String(s)) => {
      inspect(s.length(), content="2")
      let mut first_cp = -1
      for c in s {
        first_cp = Char::to_int(c)
        break
      }
      inspect(first_cp, content="65536")
    }
    _ => fail("合法代理对应解析为字符串")
  }
  // BMP 内普通 \uXXXX 不回归（含 Latin-1 段——B6 字节口径承载的消费面）
  match b6_parse_opt("\"\\u00E4\"") {
    Some(Json::String(s)) => inspect(s.length(), content="1")
    _ => fail("BMP \\u00E4 应解析成功")
  }
}

///|
test "json_parse_big_exponent_saturates_b6" {
  // 修前红：exp=4294967297（2^32+1）Int32 累积 wrap 成 1 ⇒ 值 10.0
  // 静默错值；修复后饱和 ⇒ 数学值 10^4294967297 超域 → inf
  match b6_number_value("1e4294967297") {
    Some(n) => inspect(n.is_inf(), content="true")
    None => fail("1e4294967297 是合法 RFC 8259 数字，须解析成功")
  }
  // 负向 wrap：修前 exp wrap 成 -1 ⇒ 值 0.1；修复后饱和 ⇒ 下溢 0
  match b6_number_value("1e-4294967297") {
    Some(n) => inspect(n == 0.0, content="true")
    None => fail("1e-4294967297 须解析成功")
  }
}

///|
test "json_parse_big_exponent_value_and_repr_b6" {
  // DoS 载荷族（值锚——M38 A1 实测修前单次 parse js 臂 ~2.9s；本锚锁
  // 修复后语义不回归：值域 O(1) 直达，repr 恒原文保真）
  match b6_number_value("1e2147483647") {
    Some(n) => inspect(n.is_inf(), content="true")
    None => fail("1e2147483647 须解析成功")
  }
  match b6_number_value("1e99999999999") {
    Some(n) => inspect(n.is_inf(), content="true")
    None => fail("1e99999999999 须解析成功")
  }
  match b6_number_value("2e3000000000") {
    // exp 真 30 亿（正）：修前 wrap 成负值 -1294967296 ⇒ 13 亿次除法
    // ⇒ 静默错值 0.0（wrap 缺陷形态）；修复后饱和正值 ⇒ 2×10^30亿
    // 超域 → inf（数学正确），且循环 O(1)
    Some(n) => inspect(n.is_inf(), content="true")
    None => fail("2e3000000000 须解析成功")
  }
  // repr 保真不受 exp 处理影响
  match b6_parse_opt("1e4294967297") {
    Some(Json::Number(_, repr~)) =>
      inspect(repr.unwrap_or("<none>"), content="1e4294967297")
    _ => fail("repr 提取失败")
  }
  // 域内指数行为不变（回归锚）
  match b6_number_value("1e2") {
    Some(n) => inspect(n, content="100")
    None => fail("1e2 须解析成功")
  }
  match b6_number_value("1.5e-3") {
    Some(n) => inspect(n, content="0.0015")
    None => fail("1.5e-3 须解析成功")
  }
}
