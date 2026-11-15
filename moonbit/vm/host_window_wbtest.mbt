// 蓝本注记：文内 Rust 源引用（`*.rs` 路径/行号/符号）均为档案态蓝本——tag rust-oracle-freeze（2026-10-05 删区），现为本仓自主基线。

///| host_window 表锚（批 4′）——穷尽性 + 形态抽验（行为断言形态——
/// HostWindowSig 无 Show，inspect repr 不可用）。

///|
/// 断言 helper：Ready 固定参路由。
fn expect_ready_fixed(
  id : Int32,
  argc_want : Int32,
  ret_is_word : Bool,
  ret_is_f64 : Bool,
  ret_is_i64 : Bool,
  ret_none : Bool,
) -> Bool {
  match host_window_sig(id) {
    Some(s) => {
      if !(s.group is Ready) {
        return false
      }
      if s.argc != Some(argc_want) {
        return false
      }
      match s.ret {
        Some(VkWordI32) => ret_is_word
        Some(VkF64) => ret_is_f64
        Some(VkI64) => ret_is_i64
        None => ret_none
      }
    }
    None => false
  }
}

///|
/// **穷尽锚**：0..200 域内恰好 114 个 id 有签名（host_func_pairs 名表
/// 规模单源——新路由落表即红逼登记；J9：注释掉任一 id 分支行即红）。
test "host_window: 全 id 穷尽（114 名对账）" {
  let mut n = 0
  for id = 0; id < 200; id = id + 1 {
    if host_window_sig(id) is Some(_) {
      n = n + 1
    }
  }
  inspect(n, content="114")
  // 关键路由形态抽验（真源 = 头文件原型 + 臂亲读——表内注释逐条对齐）
  inspect(host_window_sig(15).unwrap().argc, content="None") // printf 变参（AST 侧车）
  inspect(expect_ready_fixed(2, 1, true, false, false, false), content="true") // malloc(size)→word
  inspect(expect_ready_fixed(3, 1, false, false, false, true), content="true") // free→void
  inspect(expect_ready_fixed(118, 2, false, true, false, false), content="true") // strtod→f64
  inspect(expect_ready_fixed(117, 3, false, false, true, false), content="true") // strtol→i64
  inspect(expect_ready_fixed(38, 1, false, false, false, true), content="true") // exit 停机
  // 禁译分组（reason 桶口径）
  inspect(host_window_sig(21).unwrap().group is Stdin, content="true") // scanf
  inspect(host_window_sig(60).unwrap().group is Vfs, content="true") // fopen
  inspect(host_window_sig(52).unwrap().group is Callback, content="true") // qsort
  inspect(host_window_sig(140).unwrap().group is VaList, content="true") // va_start
  inspect(host_window_sig(0).unwrap().group is Observe, content="true") // OUTPUT
  // 表外 id（行为断言——Option<HostWindowSig> 无 Show，inspect repr 不可用）
  inspect(host_window_sig(200) is None, content="true")
  inspect(host_window_sig(-1) is None, content="true")
}

///|
/// **Ready 组 argc 形态**（C 原型参数个数——stdlib.h/string.h 亲读对齐）。
test "host_window: Ready 组 argc 形态" {
  inspect(host_window_sig(56).unwrap().argc, content="Some(3)") // strncpy(d,s,n)
  inspect(host_window_sig(57).unwrap().argc, content="Some(3)") // memcpy(d,s,n)
  inspect(host_window_sig(37).unwrap().argc, content="Some(3)") // memset(p,v,n)
  inspect(host_window_sig(32).unwrap().argc, content="Some(2)") // strcmp(a,b)
  inspect(host_window_sig(73).unwrap().argc, content="Some(2)") // pow(x,y)
  inspect(host_window_sig(35).unwrap().argc, content="Some(0)") // rand()
  inspect(host_window_sig(124).unwrap().argc, content="Some(0)") // clock()
}
