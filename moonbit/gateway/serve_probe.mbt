// S8 diagnostics 批段三（2026-10-02）：diagnostics_probe——dump 族第四
// 方法（认知链最小导出，U1 对拍锚面）。照搬源：native/src/session_api.rs
// 的 diagnostics_probe（303-500 行）八段输出。
//
// **只读语义（dump 族 2026-09-29 契约拍板）**：独立跑编译管线取诊断，
// 不碰调用方会话态——oracle 侧 run_multi_file_pipeline 写 session 的
// 副作用不照搬（与 ast/typeck/symbols.dump 同拍板，差异台账在案）。
// 实现形态 = 一次性 `@session.Session::new()` 承载管线后即弃。
//
// 分叉登记（本方法，已入已知限制与差异.md 条目 2——段四 2026-10-02）：
// ① intents 段恒 `[]`——**已裁定不照搬（2026-10-04 owner 拍板，issue
//    #32）**：oracle intent/cfg/data_flow 系 Phase 23 半成品孤儿域
//    （data_flow 从未接线、intent 仅 diagnostics_probe 一出口且被
//    teaching 43 族覆盖），退役后按目标架构重新设计——对烂尾楼照搬
//    会把烂尾刻进新楼；段四对拍此段走豁免白名单；
// ② params.completion 键存在即 fail loud（M15 无 MoonBit 实现——不支持
//    而非静默假空；显式 null 亦算键存在，与 oracle params.get 对
//    Some(Null) 走 error 帧同形；无键时两侧同 `[]`）；
// ③ confidence 文本已对齐（2026-10-02 审阅 P1 销案）：oracle json! 走
//    Value 路径，f32 先提升 f64 ⇒ wire = f64 最短文本；值面经
//    round_to_f32（=oracle `as f32`）、文本面经 @ast.double_to_json_text
//    （f64 ryu-pretty 单源，1.0 形态防 to_string 退化）。

///|
/// diagnostics_probe 方法帧：{ok, diagnostics, misconceptions,
/// learning_paths, knowledge_graph, intents, completion, auto_fixes}。
fn serve_diagnostics_probe_frame(
  _s : @session.Session,
  id : Json,
  params : Json,
) -> (String, Bool) {
  guard json_field(params, "source").as_string() is Some(source) else {
    return (
      serve_err(id, "protocol", "diagnostics_probe 需要 params.source").stringify(),
      false,
    )
  }
  // M15 无实现：completion 键存在即 fail loud（头注分叉②）。显式 null
  // 亦算存在——oracle params.get 返 Some(Null) 后 .get("line") 为 None
  // 同走 error 帧；仅缺键放过（json_field 对两者都塌缩 Null，故判键
  // 存在性而非值形态——2026-10-02 审阅 P2 修复，防静默假空）
  guard !(params is Object(m) && m.contains("completion")) else {
    return (
      serve_err(
        id, "protocol", "diagnostics_probe: completion 段随 analysis 批（本侧未实现）",
      ).stringify(),
      false,
    )
  }
  let filename = match json_field(params, "filename").as_string() {
    Some(f) => f
    None => "main.c"
  }
  // 只读通道：一次性会话承载管线（诊断/错误串写入即弃）
  let units : Array[@session.CompileUnit] = [{ filename, source, }]
  let fresh = @session.Session::new()
  let _ = serve_compile_pipeline(fresh, units)
  let diags = fresh.compile.diagnostics
  // 记录参数 → 误区检测 → 路径组装（Rust records 宽松解析同形）
  let records : Array[@diagnostics.CompileRecord] = []
  match json_field(params, "records") {
    Array(arr) =>
      for r in arr {
        let codes : Array[Int] = []
        match json_field(r, "codes") {
          Array(ca) =>
            for c in ca {
              match c.as_int() {
                Some(v) => codes.push(v)
                None => ()
              }
            }
          _ => ()
        }
        records.push(@diagnostics.CompileRecord::{
          timestamp_ms: match json_field(r, "ts").as_int() {
            Some(v) => v.to_int64()
            None => 0L
          },
          success: match json_field(r, "ok").as_bool() {
            Some(v) => v
            None => false
          },
          error_codes: codes,
          trap_message: json_field(r, "trap").as_string(),
        })
      }
    _ => ()
  }
  let detected = @diagnostics.detect_misconceptions(records)
  let paths = @diagnostics.recommend_learning_paths(detected)
  // 知识图谱：error 级码排序去重后逐码激活（Rust 382-408 同形）
  let error_codes : Array[Int] = []
  for d in diags {
    if d.severity == 0 {
      error_codes.push(d.error_code)
    }
  }
  error_codes.sort_by(fn(a, b) { a - b })
  let dedup_codes : Array[Int] = []
  for c in error_codes {
    if dedup_codes.is_empty() || dedup_codes[dedup_codes.length() - 1] != c {
      dedup_codes.push(c)
    }
  }
  let buf = StringBuilder()
  buf.write_string("{\"ok\": ")
  buf.write_string(
    if diags.length() == 0 {
      "true"
    } else {
      let mut all_non_err = true
      for d in diags {
        if d.severity == 0 {
          all_non_err = false
        }
      }
      if all_non_err {
        "true"
      } else {
        "false"
      }
    },
  )
  // ① diagnostics 段
  buf.write_string(", \"diagnostics\": [")
  for i, d in diags {
    if i > 0 {
      buf.write_string(", ")
    }
    buf.write_string(
      "{\"code\": \"\{severity_prefix(d.severity)}\{d.error_code}\", \"severity\": \"\{severity_name(d.severity)}\", \"line\": \{d.line}, \"column\": \{d.column}, \"fix_kind\": \{d.fix_kind}}",
    )
  }
  buf.write_string("]")
  // ② misconceptions 段（confidence 文本 = f64 最短表示——头注分叉③）
  buf.write_string(", \"misconceptions\": [")
  for i, m in detected {
    if i > 0 {
      buf.write_string(", ")
    }
    buf.write_string(
      "{\"pattern_id\": \{dump_json_escape(m.pattern_id)}, \"pattern_name\": \{dump_json_escape(m.pattern_name)}, \"occurrence_count\": \{m.occurrence_count}, \"confidence\": \{@ast.double_to_json_text(m.confidence)}}",
    )
  }
  buf.write_string("]")
  // ③ learning_paths 段
  buf.write_string(", \"learning_paths\": [")
  for i, p in paths {
    if i > 0 {
      buf.write_string(", ")
    }
    buf.write_string(
      "{\"target_misconception_id\": \{dump_json_escape(p.target_misconception_id)}, \"target_misconception_name\": \{dump_json_escape(p.target_misconception_name)}, \"estimated_time_minutes\": \{p.estimated_time_minutes}, \"steps\": [",
    )
    for j, st in p.steps {
      if j > 0 {
        buf.write_string(", ")
      }
      buf.write_string(
        "{\"step_type\": \{dump_json_escape(st.step_type)}, \"title\": \{dump_json_escape(st.title)}, \"target_id\": \{dump_json_escape(st.target_id)}}",
      )
    }
    buf.write_string("]}")
  }
  buf.write_string("]")
  // ④ knowledge_graph 段
  buf.write_string(", \"knowledge_graph\": {\"from_errors\": [")
  let mut first_err = true
  for c in dedup_codes {
    for a in @diagnostics.activate_from_error(c) {
      if !first_err {
        buf.write_string(", ")
      }
      first_err = false
      buf.write_string(
        "{\"concept_id\": \{dump_json_escape(a.node.id)}, \"title\": \{dump_json_escape(a.node.title)}, \"activated_by\": \{dump_json_escape(a.activated_by)}, \"neighbors\": [",
      )
      for j, n in a.neighbors {
        if j > 0 {
          buf.write_string(", ")
        }
        buf.write_string(
          "{\"concept_id\": \{dump_json_escape(n.node.id)}, \"relation\": \{dump_json_escape(n.relation)}}",
        )
      }
      buf.write_string("]}")
    }
  }
  buf.write_string(
    "], \"concepts_total\": \{@diagnostics.concept_nodes().length()}, \"edges_total\": \{@diagnostics.concept_edges().length()}}",
  )
  // ⑤ intents 段（恒空——analysis 批裁定，头注分叉①）
  buf.write_string(", \"intents\": []")
  // ⑥ completion 段（参数已被前置拦截，恒空）
  buf.write_string(", \"completion\": []")
  // ⑦ auto_fixes 段：fix_kind 1..=3 的诊断逐条应用（Rust 475-488 同形）
  buf.write_string(", \"auto_fixes\": [")
  let mut first_fix = true
  for d in diags {
    if d.fix_kind >= 1 && d.fix_kind <= 3 {
      let target = @diagnostics.FixTarget::{
        fix_kind: d.fix_kind,
        replace_start_line: d.replace_start_line,
        replace_start_column: d.replace_start_column,
        replace_end_line: d.replace_end_line,
        replace_end_column: d.replace_end_column,
        replacement_text: d.replacement_text,
      }
      match @diagnostics.apply_fix(source, target) {
        Some(fixed) => {
          if !first_fix {
            buf.write_string(", ")
          }
          first_fix = false
          buf.write_string(
            "{\"line\": \{d.line}, \"column\": \{d.column}, \"fix_kind\": \{d.fix_kind}, \"fixed_source\": \{dump_json_escape(fixed)}}",
          )
        }
        None => ()
      }
    }
  }
  buf.write_string("]}")
  (serve_ok(id, dump_parse_or_abort(buf.to_string())).stringify(), false)
}
