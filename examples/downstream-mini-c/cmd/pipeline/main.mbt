// 形态 A：五步库直连管线——喂 C 源码字符串 → 各阶段诊断 + 程序 stdout + 退出码。
//
// 只凭 `moon add vitro/engine` 后 .mooncakes/vitro/engine/<pkg>/pkg.generated.mbti
// 推断出的接线（下游视角，不读仓内源码）。每个「光看签名猜不到」的参数在
// 调用处注明语义（审阅 v2 R3 P2-4 清单：vis_lines / batch / cpp_mode）。
//
// 运行（本目录）：
//   moon run cmd/pipeline                   # 默认 wasm 目标（moonrun）
//   moon run --target js cmd/pipeline       # node
//   MOON_CC=clang moon run --target native cmd/pipeline   # Windows 下 native 直连目标
//                                           # 须 MOON_CC=clang-cl（见 README「目标面」）
// 三目标输出逐字一致（R3 实测 + B3 复验）。

///|
fn main {
  // 教学卡片装载门：lean 产物默认空表、引擎不兜底——不调用则 ec.catalog()
  // 恒 None（README「快速上手」明示的唯一前置）。
  @content_data.install_baked()
  let good = "#include <stdio.h>\nint main(void) {\n  int a = 6;\n  int b = 7;\n  printf(\"hello from vitro! %d\\n\", a * b);\n  return 0;\n}\n"
  let bad = "int main(void) {\n  int x = \"hello\";\n  return x;\n}\n"
  let interactive = "#include <stdio.h>\nint main(void) {\n  int n;\n  scanf(\"%d\", &n);\n  printf(\"got %d, doubled=%d\\n\", n, n * 2);\n  return 0;\n}\n"
  println("=== 案例 1：正常程序（printf + 算术）===")
  run_c(good, None)
  println("")
  println(
    "=== 案例 2：类型错误程序（int 收字符串字面量）+ 教学卡片联动 ===",
  )
  run_c(bad, None)
  println("")
  println("=== 案例 3：交互程序（scanf 读预给定 stdin）===")
  run_c(interactive, Some("21\n"))
}

///|
/// 五步：tokenize → parse → TypeChecker.check → codegen.compile → VitroVM。
/// 任一层出错即止并打印该层诊断（与引擎 compile_pipeline「任一层失败即止」
/// 同语义）。
fn run_c(src : String, stdin_text : String?) -> Unit {
  // 阶段 1：词法（含预处理 pass）。`cpp_mode~` 缺省 false = C 域；C++ 子集
  // 语法（class/模板）需显式 cpp_mode=true——本示例全部 C 域。
  let lex = @lexer.tokenize(src)
  if lex.errors.length() > 0 {
    for e in lex.errors {
      println(
        "[lex] \{e.code.display_code()} 行\{e.loc.line} 列\{e.loc.column}: \{e.message}",
      )
    }
    return
  }
  // 阶段 2：语法。`program` 为 None = 无 AST 可用；Some + errors 非空 = 带占位
  // 的部分 AST（引擎照跑 typeck 以多报一层诊断——这里按「任一层错即止」收口）。
  let parse = @parser.parse(lex.tokens)
  let program = match parse.program {
    None => {
      for e in parse.errors {
        println("[parse] 行\{e.line} 列\{e.column}: \{e.message}")
      }
      return
    }
    Some(p) => {
      if parse.errors.length() > 0 {
        for e in parse.errors {
          println("[parse] 行\{e.line} 列\{e.column}: \{e.message}")
        }
        return
      }
      p
    }
  }
  // 阶段 3：类型检查 + lowering。四元组 = (降级后的新树, errors, warnings,
  // hints)——`check` 是函数式重建（值进值出），后续 codegen 必须喂返回的
  // lowered 树而非原 program；hints 是教学提示（非错非警），本示例不消费。
  let tc = @typeck.TypeChecker::new()
  let (lowered, terrs, twarns, _hints) = tc.check(program)
  for w in twarns {
    println("[typeck/warn] 行\{w.line} 列\{w.column}: \{w.message}")
  }
  if terrs.length() > 0 {
    for e in terrs {
      println("[typeck/error] 行\{e.line} 列\{e.column}: \{e.message}")
      // 错误码 → 教学卡片：from_code 收 Int（诊断的 code 字段），catalog()
      // 在 install_baked 之后才非 None。
      match @diag.ErrorCode::from_code(e.code) {
        Some(ec) =>
          match ec.catalog() {
            Some(card) => {
              println(
                "  ┌─ 教学卡片 [\{ec.display_code()}] \{card.title}",
              )
              println("  │ \{card.explanation}")
              if card.common_causes.length() > 0 {
                println("  │ 常见原因: \{card.common_causes.join("; ")}")
              }
              println("  └─")
            }
            None => println("  （错误码 \{e.code} 无教学卡片）")
          }
        None => println("  （错误码 \{e.code} 不在 ErrorCode 表中）")
      }
    }
    return
  }
  // 阶段 4：字节码生成。二元组 = (CompileOutput?, 生成错误)；None 即无产物。
  let (output, gerrs) = @codegen.compile(lowered)
  for e in gerrs {
    println("[codegen] 行\{e.line} 列\{e.column}: \{e.message}")
  }
  guard output is Some(o) else {
    println("[codegen] 无产物，终止")
    return
  }
  // 阶段 5：VM。setup_from_output(产物, argc, argv, vis_lines)——
  //   argc/argv：程序命令行（argv[0] 习惯填程序名；空数组时 argc 填 0）；
  //   vis_lines：教学可视化事件投影 (line, ty, ctx) 三元组，来自
  //     compile 响应的 algorithm_matches.vis_events——库直连不做算法
  //     标注时传空数组即可（gateway 通道会自动填）。
  let vm = @vm.VitroVM::new()
  vm.setup_from_output(o, 0, [], [])
  // stdin 预给定：from_stdin_text(text, batch)——
  //   batch=true  = 批模式：流耗尽即 EOF（scanf 返回 -1），headless 正解；
  //   batch=false = 交互模式：流耗尽回退等待（Waiting），要宿主续喂
  //     input.feed——那是 gateway 会话语义，库直连无 feed 通道勿用。
  match stdin_text {
    Some(t) => vm.set_input(@host.InputState::from_stdin_text(t, true))
    None => ()
  }
  let code = vm.run()
  // 输出面是 Bytes（字节保真：putchar(200) 落 1 字节 0xC8 不经编码）；
  // 文本化走引擎自带的 UTF-8 解码器（非法序列折 U+FFFD、截断尾部宽容），
  // 不必自写 bytes→String。
  let stdout_text = @util.utf8_text_partial(
    vm.output.join(@host.OutputKind::Stdout),
  )
  let stderr_text = @util.utf8_text_partial(
    vm.output.join(@host.OutputKind::Stderr),
  )
  println("---- stdout ----")
  println(strip_one_trailing_newline(stdout_text))
  if stderr_text != "" {
    println("---- stderr ----")
    println(strip_one_trailing_newline(stderr_text))
  }
  println(
    "---- run() 返回: \{code} / 程序 return 值: \{vm.final_return_value()} ----",
  )
}

///|
/// MoonBit 只有 println（恒补尾换行）——程序输出自带尾换行时剥一个，避免
/// 演示输出多一空行；非 ASCII 安全（只看末尾码元）。
fn strip_one_trailing_newline(s : String) -> String {
  if s.has_suffix("\n") {
    s[:s.length() - 1].to_owned()
  } else {
    s
  }
}
