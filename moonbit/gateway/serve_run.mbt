// S7 批三号二段：serve run 方法——全速运行 + 六字段出口。
// 照搬源：native/src/bin/vitro_cli.rs 的 run 臂 + native/src/
// session_api.rs::run + native/src/engine/session_ops.rs::execute_run
// （非 resume 五步：reset_runtime 等价 → setup → 动态堆起点 → vfs 预设
// → vm.run）。
// 三段重构：execute_run 公共段抽出（serve_execute_run）——input.feed 帧
// （serve_io.mbt）与 run 帧共用（Rust input_feed 尾调 run(session) 同构）。
//
// **「2000 步真停」端到端锚**（总计划 S7 行登记的会话批遗留义务）：
// Rust 事故形态 = `config.set {"max_steps": 2000}` 写在 compile 之前，
// vm Option 形态下配置静默丢弃、程序跑满默认 1000 万步。本侧 vm 非
// Option + setup_from_output 内部 reset「装载通道不得设置」纪律（保留
// max_steps）——结构上不可丢弃；锚锁行为（serve_run_wbtest）。
//
// 登记分叉（本段不搬，诚实记录）：
// ① ~~运行完成附注的 leak report~~ **已销案（2026-10-04 analysis 片）**：
//    append_leak_report 已接线（session_ops.rs 逐字照搬，note 通道，
//    锚 serve_run_leak_report_note_channel）；「程序运行完成，返回
//    值：N」note 已照搬（E-P1-5 note 通道）；
// ② Rust execute_run 的 catch_unwind 保护（B47）不搬——MoonBit 无 panic
//    捕获通道，vm.run 内部 fail loud 即错误面。

///|
/// not_compiled 错误帧体（Rust session_api::run 的未编译出口——run 与
/// input.feed 两帧同构消费）。
fn not_compiled_json() -> Json {
  let m : Map[String, Json] = Map([])
  m.set("ok", Json::boolean(false))
  m.set("status", Json::string("not_compiled"))
  m.set("return_value", Json::number(0))
  m.set("trap", Json::string("程序尚未编译。请先编译代码。"))
  m.set("waiting_input", Json::boolean(false))
  m.set("steps_executed", Json::number(0))
  Json::object(m)
}

///|
/// execute_run 等价公共段（run / input.feed 共用）：is_resume 判定 →
/// 非 resume 五步（输出清 + vfs 重建 + setup + 动态堆起点 + 预设注入）
/// → vm.run → 六字段出口。
fn serve_execute_run(s : @session.Session) -> Json {
  let is_resume = s.vm.waiting_input
  s.vm.clear_waiting_input()
  if !is_resume {
    // reset_runtime 等价：输出清 + vfs 重建（内存/堆游标由 setup 内部
    // reset 承担——vm reset 不碰 output/vfs/input，跨 run 存活的输入
    // 语义与 Rust reset_runtime 不碰输入一致）
    s.vm.output.clear()
    s.vm.reset_vfs()
    let output = match s.compile.output {
      Some(o) => o
      None => return not_compiled_json()
    }
    let argc = s.runtime_argv.length()
    // issue #29 #4：vis 行随装配灌入（与 step.begin 同一投影，两通道统一）
    s.vm.setup_from_output(
      output,
      argc,
      s.runtime_argv,
      project_vis_lines(s.compile.algorithm_matches),
    )
    // R1 ① 动态堆起点（须在 setup 之后——其内部 reset 重建 mem_map 回
    // 默认；cmd/run 同款注释）
    let global_data_end = output.global_data_end
    s.vm.mem_map.set_heap_base(
      @bytecode.compute_heap_base(global_data_end, argc, s.runtime_argv),
    )
    // vfs 预设注入（Rust execute_run 无条件注入——教学演示通道）
    ignore(
      s.vm.vfs.inject_preset_file(
        s.vm.mem_map,
        s.vm.memory,
        "test.txt",
        b"hello\nworld\n",
      ),
    )
    ignore(
      s.vm.vfs.inject_preset_file(
        s.vm.mem_map,
        s.vm.memory,
        "numbers.txt",
        b"1 2 3 4 5\n",
      ),
    )
  } else {
    // resume 分支：参数回推 + ip 回退已就位（CallHost 臂统一处理），
    // 直接再 run 即续跑；无 input 时重跑会立刻再 waiting（同 Rust）
    ()
  }
  let ret = s.vm.run()
  let trap = s.vm.error
  let waiting = s.vm.waiting_input
  if trap.is_empty() && !waiting {
    // E-P1-5：运行完成提示是引擎附注（note 通道）；堆教学附注同通道
    //（oracle session_ops.rs:152-153 同序：完成提示 → 泄漏报告）
    s.vm.output.push_note_str("程序运行完成，返回值：\{ret}\n")
    append_leak_report(s.vm)
  }
  let status = if !trap.is_empty() {
    "trap"
  } else if waiting {
    "waiting_input"
  } else {
    "finished"
  }
  let m : Map[String, Json] = Map([])
  m.set("ok", trap.is_empty().to_json())
  m.set("status", Json::string(status))
  m.set("return_value", ret.to_json())
  m.set("trap", Json::string(trap))
  m.set("waiting_input", waiting.to_json())
  m.set("steps_executed", s.vm.step_count.to_json())
  Json::object(m)
}

///|
/// run 方法帧（Rust vitro_cli.rs run 臂 + session_api::run 照搬）：
/// 可选 input（覆盖式喂入 + 游标重置）/ argv（跨 run 存活）/ batch_input
/// （输入模式）；同帧可带 config.set 字段（serve_apply_config）；返回
/// `{ok, status, return_value, trap, waiting_input, steps_executed}`。
fn serve_run_frame(
  s : @session.Session,
  id : Json,
  params : Json,
) -> (String, Bool) {
  // U1#1 二审 P0-A：run 重置发布缓冲（旧程序的滞留帧作废）
  s.unified_pending = None
  if !s.compile.compiled {
    return (serve_ok(id, not_compiled_json()).stringify(), false)
  }
  // ── 参数域（Rust run 臂顺序）──
  match json_field(params, "input").as_string() {
    Some(input) =>
      s.vm.set_input(@host.InputState::from_stdin_text(input, s.runtime_batch))
    None => ()
  }
  match json_field(params, "argv") {
    Array(argv) => {
      let args : Array[String] = []
      for v in argv {
        match v.as_string() {
          Some(a) => args.push(a)
          None => ()
        }
      }
      s.runtime_argv = args
    }
    _ => ()
  }
  match json_field(params, "batch_input").as_bool() {
    Some(batch) => {
      s.runtime_batch = batch
      // 模式即时应用到输入态（行内容保留——InputState.batch 非 mut，
      // 重建；无 input 参数时的行本体沿用 vm.input 现有引用）
      s.vm.set_input(@host.InputState::new(s.vm.input.lines, batch))
    }
    None => ()
  }
  // 模式对齐：会话缺省 Interactive（Rust InputMode #[default]）与 vm
  // 构造默认 batch=true 的差——首次 run 无任何输入参数时必须落到
  // Interactive（scanf → waiting_input 而非 EOF；探针实锤）。分叉登记：
  // 模式切换经重建 ⇒ 游标归零，Rust input_mode 独立字段保游标（罕见
  // 路径：等待中切模式——零实际消费面）
  if s.vm.input.batch != s.runtime_batch {
    s.vm.set_input(@host.InputState::new(s.vm.input.lines, s.runtime_batch))
  }
  ignore(serve_apply_config(s, params))
  (serve_ok(id, serve_execute_run(s)).stringify(), false)
}

///|
/// 内存泄漏教学报告（oracle engine/session_ops.rs append_leak_report 照搬，
/// 2026-10-04 analysis 片接线——serve_run 头注分叉①销案）：遍历未释放堆区域
/// 按分配行号排序，note 通道追加（push_note 段落语义自动补尾换行，与 Rust
/// push_note 同款）。alloc_by "vfs" 排除（FILE\* 内部分配不算用户泄漏）；
/// 空泄漏静默返回（零报告形态同 Rust）。
///
/// **逐条行封顶**（批五 note 无界治理，2026-10-07，S9 解除照搬）：明细行
/// 最多 `leak_report_max_rows` 行，超出以省略汇总行收口；计数行与总字节数
/// 仍为全量。极端形态（1MB 堆最小 4B 对齐块全泄漏）理论上限约 26 万行
/// 明细——封顶后报告自身有界（~80KB），教学无损（前 1000 行样本 + 全量
/// 计数足以定位泄漏模式）。
pub fn append_leak_report(vm : @vm.VitroVM) -> Unit {
  let leaks : Array[@memory.MemoryRegionData] = []
  let addrs : Array[UInt] = []
  for addr, r in vm.mem_map.regions {
    if r.is_heap && !r.is_freed && r.alloc_by != "vfs" {
      leaks.push(r)
      addrs.push(addr)
    }
  }
  if leaks.length() == 0 {
    return
  }
  // 行号排序（稳定保持配对的 addr——同步重排）
  let n = leaks.length()
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n - 1 - i; j = j + 1 {
      if leaks[j + 1].alloc_line < leaks[j].alloc_line {
        let t = leaks[j]
        leaks[j] = leaks[j + 1]
        leaks[j + 1] = t
        let a = addrs[j]
        addrs[j] = addrs[j + 1]
        addrs[j + 1] = a
      }
    }
  }
  let mut total_leaked = 0
  for r in leaks {
    total_leaked = total_leaked + r.size
  }
  let lines : Array[String] = []
  // 首行前导 \n 与最后一段程序输出分隔（oracle 同款；尾随换行由
  // push_note 段落语义补齐）
  lines.push("\n===== 内存泄漏检测报告 =====")
  lines.push(
    "发现 \{leaks.length()} 处未释放的堆内存，共 \{total_leaked} 字节：",
  )
  let shown = if n > leak_report_max_rows { leak_report_max_rows } else { n }
  for i = 0; i < shown; i = i + 1 {
    let r = leaks[i]
    let by = if r.alloc_by == "" { "malloc" } else { r.alloc_by }
    let hex = uint_to_hex4(addrs[i])
    if r.alloc_line > 0 {
      lines.push(
        "  • 第 \{r.alloc_line} 行的 \{by} 分配了 \{r.size} 字节 (addr=0x\{hex})，未被 free",
      )
    } else {
      lines.push(
        "  • \{by} 分配了 \{r.size} 字节 (addr=0x\{hex})，未被 free",
      )
    }
  }
  if n > shown {
    lines.push("  ... 其余 \{n - shown} 处已省略显示")
  }
  lines.push(
    "[note] 提示：在 C 语言中，malloc 分配的内存需要对应 free 释放，否则会造成内存泄漏。",
  )
  lines.push("==============================")
  for line in lines {
    // E-P1-5：泄漏报告是引擎附注，绝不混入程序 stdout
    vm.output.push_note_str(line)
  }
}

///|
/// 泄漏报告逐条明细行上限（计数与总字节数不受此限——见 `append_leak_report`）。
let leak_report_max_rows : Int = 1000

///|
/// UInt → 大写十六进制，**最少 4 位**（oracle `{:04X}` 语义——不足 4 位
/// 补前导零，超过原样不截不补；审阅 P1 修正 2026-10-04：首版恒 8 位与
/// oracle 不符且被锚锁死）。仓内无 hex 单源，本函数 priv 自持——第二
/// 消费者出现时上提 util 登记机械件。
fn uint_to_hex4(v : UInt) -> String {
  let digits = "0123456789ABCDEF"
  // 最高非零 nibble 位置（0 值给 -1 → 由保底 4 位兜出 "0000"）
  let mut top = -1
  for shift = 28; shift >= 0; shift = shift - 4 {
    if ((v >> shift) & 0xFU) != 0U {
      top = shift
      break
    }
  }
  // 起始 shift = max(最高非零 nibble, 12)——保底 4 位、超长不截
  let start = if top > 12 { top } else { 12 }
  let buf = StringBuilder()
  for shift = start; shift >= 0; shift = shift - 4 {
    buf.write_char(
      digits[((v >> shift) & 0xFU).reinterpret_as_int()].unsafe_to_char(),
    )
  }
  buf.to_string()
}
