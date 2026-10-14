// S7 批三号三段：serve 交互 IO 方法族——input.feed（增量喂入续跑）+
// output.delta（输出通道增量，E-P1-5 四通道游标）。
// 历史出处：native/src/bin/vitro_cli.rs 的 input.feed/output.delta 臂 +
// native/src/session_api.rs 的 input_feed/output_delta_on（已随 2026-10-05
// 删区消失，tag rust-oracle-freeze 可回溯；后续演化为本仓自主基线）。
//
// **input.feed 语义**（下游需求清单 A2）：run 返回 waiting_input 后追加
// stdin 文本（可含多行，split_stdin 同口径切行）并续跑到 finished /
// trapped / 下一次 waiting_input。状态机：
//   waiting_input --input.feed--> running --> waiting_input | finished | trap
// feed 在非等待态也可调用：文本追加后正常跑（execute_run 非 resume 分支
// 会 reset + setup 从头重跑——会话语义 = 喂入后重新执行全程；Rust 同形，
// 出处同上 tag 可回溯）。
//
// **output.delta 分叉登记**（三条；①③ 于 2026-10-06 #49 统一 CLI 批修订）：
// ① **delta 编码形态按通道分域**：Rust 输出通道是 UTF-8 String
//    （putchar(200) 被重编码为两字节——DIFF-LIB-PUTCHAR-01）；MoonBit
//    OutputLog 是 Bytes 保真（单字节 0xC8）。**Stdout/Stderr** 通道 delta
//    按 Latin-1 逐字节折回 String（cmd/run stdout 通道同口径——消费方在
//    字节域归一）；**Note** 通道是引擎文本域（push_note_str UTF-8 编码
//    入通道），delta 以 `@util.utf8_text_partial` 解码回原文（修复前统一
//    Latin-1 折回致中文 mojibake——CLI note 消费先例同款修正）；display
//    混合域投影维持 Latin-1（note 部分差异并入本条）。
// ② **cursor 无 UTF-8 字符边界前移**：历史对照（Rust `while !all.
//    is_char_boundary(start) { start += 1 }` 使「cursor 落在多字节
//    字符中间」时空转下个边界，delta 恒合法 UTF-8）；本侧字节域无
//    边界概念，中段 cursor 直接切字节（探针实测：`printf("中")`
//    cursor=1 → Rust delta=""〔前移到 3〕/ 本侧 delta=2 尾字节——
//    对照形态随删区退役，tag rust-oracle-freeze 可回溯）。
//    **消费方契约**：cursor 只用响应里的 `total` 回填推进，永不自算
//    中段游标；自算中段游标（如按显示宽度截取）才会踩到字节残段。
//    **批五 D 桶审视裁定（2026-10-09，refs #47）：维持现状**——字节域
//    通道语义自洽（实现 UTF-8 边界前移会使 cursor 增量与 total 不一致，
//    反而破坏字节域消费方契约）。锚 `serve_output_delta_cursor_mid_utf8_byte`
//    锁现状。

///|
/// input.feed 方法帧（Rust input_feed 照搬 + #86/#88 扩展）：params.text
/// 缺省 "" 等价「续推进一步」；text 非空追加（非覆盖，游标保留 + EOF 粘滞
/// 清除）；params.eof=true 置 InputState EOF 粘滞（#88——交互模式 EOF 口，
/// scanf 族返回 -1，while(scanf!=EOF) 可收尾；set_eof 单源：游标推底 +
/// 粘滞）；出口与 run 同构六字段。**#86**：步进会话活跃（step.begin 后）
/// 时改走 engine 通道续跑（run_batch 循环到终态——帧进 engine.frames，
/// 续跑指令不丢帧、帧流 step_index 连续；旧走 vm.run() 全速绕过 engine，
/// 续跑段零帧 + 尾帧越界跳号）。
fn serve_input_feed_frame(
  s : @session.Session,
  id : Json,
  params : Json,
) -> (String, Bool) {
  if !s.compile.compiled {
    return (serve_ok(id, not_compiled_json()).stringify(), false)
  }
  let text = match json_field(params, "text").as_string() {
    Some(t) => t
    None => ""
  }
  if !text.is_empty() {
    // 切行单源 host::from_stdin_text（serve/run/-i 三消费者）——追加只
    // 取行数组（模式与 EOF 清除由 push_lines 承担）
    s.vm.input.push_lines(@host.InputState::from_stdin_text(text, true).lines)
  }
  // #88：EOF 口——置位后本次续跑内 scanf 族读输入即 -1
  match json_field(params, "eof").as_bool() {
    Some(true) => s.vm.input.set_eof()
    _ => ()
  }
  // #86：步进会话活跃走 engine 通道（帧流连续）；否则原 run 通道
  guard s.unified is Some(engine) else {
    // resume 语义：waiting_input 由 serve_execute_run 的 is_resume 承担
    // （参数回推 + ip 回退已就位；二段锚 serve_run_waiting_then_input_resumes
    // 已锁行为——本帧是同一机制的独立方法入口）
    return (serve_ok(id, serve_execute_run(s)).stringify(), false)
  }
  (serve_ok(id, serve_execute_run_via_engine(s, engine)).stringify(), false)
}

///|
/// engine 通道续跑（#86）：run_batch 循环到终态（waiting/finished/trap）
/// ——帧由 engine 收集（payload.get/seek 后续可取）；六字段出口与
/// serve_execute_run 同构（return_value 经 vm.final_return_value 投影）。
fn serve_execute_run_via_engine(
  s : @session.Session,
  engine : @time_travel.UnifiedEngine,
) -> Json {
  // waiting 旗清位（与 serve_execute_run 的 is_resume 后清位同源——出口
  // 字段只反映本次结果；重执行 CallHost 内部按需重置）
  let was_waiting = s.vm.waiting_input
  ignore(was_waiting)
  s.vm.clear_waiting_input()
  let mut err_msg = ""
  while true {
    match engine.run_batch(s.vm, SessionLines::{ s, }, s.config.max_steps) {
      Err(msg) => {
        err_msg = msg
        break
      }
      Ok(r) => {
        if r.waiting_input || r.finished || r.trapped {
          break
        }
        // 批跑满未终态（预算内继续——batch_size 已是会话 max_steps）
        ()
      }
    }
  }
  let trap = if !err_msg.is_empty() { err_msg } else { s.vm.error }
  let waiting = s.vm.waiting_input
  let ret = if trap.is_empty() && !waiting {
    let v = s.vm.final_return_value()
    s.vm.output.push_note_str("程序运行完成，返回值：\{v}\n")
    append_leak_report(s.vm)
    v
  } else {
    0
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
  // #91：output_truncated 位（serve_execute_run 同款——feed 与 run 出口
  // 字段面同构）
  m.set(
    "output_truncated",
    (s.vm.output.dropped_bytes() > 0 || s.vm.output.note_dropped_bytes() > 0).to_json(),
  )
  Json::object(m)
}

///|
/// output.delta 方法帧（Rust output_delta_on 照搬）：
/// `{delta, cursor, total, stream}`——cursor 起（字节偏移）的增量；
/// cursor 越界按末尾处理；display 视图 = 全通道按写入序拼接。
fn serve_output_delta_frame(
  s : @session.Session,
  id : Json,
  params : Json,
) -> (String, Bool) {
  let cursor = match json_field(params, "cursor").as_int() {
    Some(c) => c
    None => 0
  }
  let view = match json_field(params, "stream").as_string() {
    Some(v) => v
    None => "display"
  }
  // 通道解析复用 OutputKind::parse（trim/lower/note|notes 归一单源；
  // display = 全通道按写入序拼接的投影，由本帧处理；未知退化 display
  // ——Rust 同形，旧值客户端行为不变）
  let kind_opt = @host.OutputKind::parse(view)
  let stream_name = match kind_opt {
    Some(kind) => kind.as_str()
    None => "display"
  }
  let all = match kind_opt {
    Some(kind) => s.vm.output.join(kind)
    None => s.vm.output.join_all()
  }
  let total = all.length()
  let start = if cursor < 0 {
    0
  } else if cursor > total {
    total
  } else {
    cursor
  }
  // delta 构造按通道分域（2026-10-06 #49 统一 CLI 批——note mojibake 修复，
  // 翻转锚 serve_output_delta_stream_channels）：
  // - Stdout/Stderr = C 程序字节流：Latin-1 逐字节折回（既定口径，文件头
  //   分叉登记①——消费方在字节域归一，putchar(200) 单字节保真）
  // - Note = 引擎文本域（push_note_str 以 UTF-8 编码入通道）：delta 解码
  //   回原文（cmd/lib/cli note 消费同款先例——两通道不同源，Latin-1 折回
  //   中文必 mojibake）；cursor/total 保持字节域口径（游标契约不变，中段
  //   cursor 切进多字节序列由前缀止语义消化）
  // - display = 混合域投影：保持 Latin-1 现状（note 部分的 UTF-8 字节仍
  //   逐字节折回——display 无逐通道解码语义，该差异并入分叉登记①）
  let delta : String = match kind_opt {
    Some(@host.OutputKind::Note) =>
      @util.utf8_text_partial(all[start:total].to_owned())
    _ => {
      let buf = StringBuilder()
      for i = start; i < total; i = i + 1 {
        buf.write_char(all[i].to_int().unsafe_to_char())
      }
      buf.to_string()
    }
  }
  let m : Map[String, Json] = Map([])
  m.set("delta", Json::string(delta))
  m.set("cursor", total.to_json())
  m.set("total", total.to_json())
  m.set("stream", Json::string(stream_name))
  // DX ③（#71 工具批，2026-10-11）：环形丢弃显式位——16MB/8MB 预算触顶
  // 丢最旧此前仅截断注记可见（注记本身可被再丢），帧级 dropped 计数
  // 让消费方判「输出不完整」不靠猜。协议面=帧字段追加（只增不改纪律）。
  let dropped = match kind_opt {
    Some(@host.OutputKind::Note) => s.vm.output.note_dropped_bytes()
    Some(_) => s.vm.output.dropped_bytes()
    None => s.vm.output.dropped_bytes() + s.vm.output.note_dropped_bytes()
  }
  m.set("truncated_bytes", dropped.to_json())
  (serve_ok(id, Json::object(m)).stringify(), false)
}
