// S7 批三号三段：serve 交互 IO 方法族——input.feed（增量喂入续跑）+
// output.delta（输出通道增量，E-P1-5 四通道游标）。
// 照搬源：native/src/bin/vitro_cli.rs 的 input.feed/output.delta 臂 +
// native/src/session_api.rs 的 input_feed/output_delta_on。
//
// **input.feed 语义**（下游需求清单 A2）：run 返回 waiting_input 后追加
// stdin 文本（可含多行，split_stdin 同口径切行）并续跑到 finished /
// trapped / 下一次 waiting_input。状态机：
//   waiting_input --input.feed--> running --> waiting_input | finished | trap
// feed 在非等待态也可调用：文本追加后正常跑（execute_run 非 resume 分支
// 会 reset + setup 从头重跑——Rust 现状同形，照搬不私改）。
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
// ② **cursor 无 UTF-8 字符边界前移**：Rust 侧 `while !all.
//    is_char_boundary(start) { start += 1 }` 使「cursor 落在多字节
//    字符中间」时空转下个边界（delta 恒合法 UTF-8）；本侧字节域无
//    边界概念，中段 cursor 直接切字节（探针实测：`printf("中")`
//    cursor=1 → oracle delta=""〔前移到 3〕/ 本侧 delta=2 尾字节）。
//    **消费方契约**：cursor 只用响应里的 `total` 回填推进，永不自算
//    中段游标 ⇒ 两侧行为一致；自算中段游标（如按显示宽度截取）才会
//    触发本分叉。锚 `serve_output_delta_cursor_mid_utf8_byte` 锁现状。

///|
/// input.feed 方法帧（Rust input_feed 照搬）：params.text 缺省 "" 等价
/// 「续推进一步」；text 非空追加（非覆盖，游标保留 + EOF 粘滞清除）；
// 出口与 run 同构六字段。
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
  // resume 语义：waiting_input 由 serve_execute_run 的 is_resume 承担
  // （参数回推 + ip 回退已就位；二段锚 serve_run_waiting_then_input_resumes
  // 已锁行为——本帧是同一机制的独立方法入口）
  (serve_ok(id, serve_execute_run(s)).stringify(), false)
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
      @util.utf8_text_partial(all[start:total].to_bytes())
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
  (serve_ok(id, Json::object(m)).stringify(), false)
}
