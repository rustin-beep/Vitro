// 帧数据层：StepPayload（16 字段）→ 紧凑 Frame；关键帧判据与预算抽稀
// （v1 keyframes.mjs 逐条照搬——权重 0 丢弃 / 1 行变化 / 2 栈·交换 / 3
// 数组·事件·首末·根因）；frames_summary / annotations 索引；frames_query
// 投影（默认 {i,l,f,s}，fields 显式扩 r/v/c/e/a/h）。
// 紧凑键与 v1 render.mjs 消费形态逐字对齐（render 钩子入参即此形态）。

///|
pub struct VisEv {
  ty : Int32
  line : Int32
  e0 : Int32
  e1 : Int32
  e2 : Int32
  ctx : String
}

///|
pub struct Frame {
  i : Int32
  l : Int32
  f : String
  s : String
  /// algorithm_step (phase, description)
  a : (String, String)?
  /// local_vars (name, ty_name, value)
  v : Array[(String, String, String)]
  /// call_stack 函数名
  c : Array[String]
  e : Array[VisEv]
  /// 数组快照 name → elements（全量；聚焦过滤在消费点）
  r : Map[String, Array[String]]
  /// root_cause_hint 原样（Null = 无）
  h : Json
}

///|
fn frame_of_payload(p : Json) -> Frame {
  let a = match jget(p, "algorithm_step") {
    Object(_) as st =>
      Some(
        (jstr_or(jget(st, "phase"), ""), jstr_or(jget(st, "description"), "")),
      )
    _ => None
  }
  let v : Array[(String, String, String)] = []
  for x in jarr(jget(p, "local_vars")) {
    v.push(
      (
        jstr_or(jget(x, "name"), ""),
        jstr_or(jget(x, "ty_name"), ""),
        jstr_or(jget(x, "value"), ""),
      ),
    )
  }
  let c : Array[String] = []
  for x in jarr(jget(p, "call_stack")) {
    c.push(jstr_or(jget(x, "func_name"), ""))
  }
  let e : Array[VisEv] = []
  for x in jarr(jget(p, "vis_events")) {
    e.push({
      ty: jint_or(jget(x, "ty"), 0),
      line: jint_or(jget(x, "line"), 0),
      e0: jint_or(jget(x, "extra0"), 0),
      e1: jint_or(jget(x, "extra1"), 0),
      e2: jint_or(jget(x, "extra2"), 0),
      ctx: jstr_or(jget(x, "context"), ""),
    })
  }
  let r : Map[String, Array[String]] = Map([])
  for x in jarr(jget(p, "array_snapshots")) {
    let name = jstr_or(jget(x, "name"), "")
    let els : Array[String] = []
    for el in jarr(jget(x, "elements")) {
      els.push(
        match el {
          String(s) => s
          other => other.stringify()
        },
      )
    }
    r.set(name, els)
  }
  {
    i: jint_or(jget(p, "step_index"), 0),
    l: jint_or(jget(p, "code_line"), 0),
    f: jstr_or(jget(p, "func_name"), ""),
    s: jstr_or(jget(p, "semantic_label"), ""),
    a,
    v,
    c,
    e,
    r,
    h: match jget(p, "root_cause_hint") {
      Object(_) as hint => hint
      _ => Json::null()
    },
  }
}

///|
fn vis_kind(ty : Int32) -> String {
  match ty {
    2 => "swap"
    1 => "compare"
    _ => "event"
  }
}

///|
/// 聚焦数组选择（v1 pickFocusArrays：显式优先；auto = 出现频次降序前 4）。
fn pick_focus_arrays(
  frames : Array[Frame],
  explicit : Array[String],
) -> Array[String] {
  if explicit.length() > 0 {
    return explicit
  }
  let counts : Map[String, Int32] = Map([])
  for fr in frames {
    for name, _ in fr.r {
      counts.set(name, counts.get(name).unwrap_or(0) + 1)
    }
  }
  let pairs : Array[(String, Int32)] = []
  for name, n in counts {
    pairs.push((name, n))
  }
  // 频次降序；同频保插入序（稳定）
  pairs.sort_by((x, y) => y.1 - x.1)
  let out : Array[String] = []
  for p in pairs {
    if out.length() < 4 {
      out.push(p.0)
    }
  }
  out
}

///|
/// 聚焦数组相等（v1 arrEq：键集与逐元素）。
fn arrays_eq(a : Frame, b : Frame, focus : Array[String]) -> Bool {
  for name in focus {
    match (a.r.get(name), b.r.get(name)) {
      (None, None) => ()
      (Some(x), Some(y)) => {
        if x.length() != y.length() {
          return false
        }
        for i = 0; i < x.length(); i = i + 1 {
          if x[i] != y[i] {
            return false
          }
        }
      }
      _ => return false
    }
  }
  true
}

///|
/// 关键帧权重（v1 keyWeight 逐条照搬）。
fn key_weight(
  prev : Frame?,
  cur : Frame,
  is_edge : Bool,
  focus : Array[String],
) -> Int32 {
  let mut w = 0
  if prev is None || is_edge {
    w = 3
  }
  if cur.e.length() > 0 {
    w = max_int(w, 3)
  }
  match prev {
    Some(p) => {
      if !arrays_eq(cur, p, focus) {
        w = max_int(w, 3)
      }
      if cur.c.length() != p.c.length() {
        w = max_int(w, 2)
      }
      if cur.l != p.l && cur.l > 0 {
        w = max_int(w, 1)
      }
    }
    None => ()
  }
  if !jis_null(cur.h) {
    w = max_int(w, 3)
  }
  if cur.s.has_prefix("交换") ||
    cur.s.has_prefix("swap") ||
    cur.s.has_prefix("Swap") {
    w = max_int(w, 2)
  }
  w
}

///|
/// 关键帧抽取 + 预算抽稀（v1 extractKeyframes 逐条照搬）。返回原始帧下标集。
fn extract_keyframes(
  frames : Array[Frame],
  focus : Array[String],
  budget : Int32,
) -> (Array[Int32], Bool) {
  let out : Array[Int32] = []
  let w : Array[Int32] = []
  let mut prev : Frame? = None
  for k = 0; k < frames.length(); k = k + 1 {
    let weight = key_weight(prev, frames[k], k == frames.length() - 1, focus)
    if weight > 0 {
      out.push(k)
      w.push(weight)
      prev = Some(frames[k])
    }
  }
  if out.length() <= budget {
    return (out, false)
  }
  let hi : Array[Int32] = []
  let lo : Array[Int32] = []
  for i = 0; i < out.length(); i = i + 1 {
    if w[i] >= 2 {
      hi.push(i)
    } else {
      lo.push(i)
    }
  }
  let keep : Map[Int32, Bool] = Map([])
  for i in hi {
    keep.set(i, true)
  }
  let room = max_int(0, budget - hi.length())
  if room > 0 && lo.length() > 0 {
    let step = lo.length().to_double() / room.to_double()
    for j = 0; j < room; j = j + 1 {
      keep.set(lo[(j.to_double() * step).to_int()], true)
    }
  } else if room == 0 && hi.length() > budget {
    keep.clear()
    let step = hi.length().to_double() / budget.to_double()
    for j = 0; j < budget; j = j + 1 {
      keep.set(hi[(j.to_double() * step).to_int()], true)
    }
    keep.set(hi[hi.length() - 1], true)
  }
  keep.set(0, true)
  keep.set(out.length() - 1, true)
  let idx : Array[Int32] = []
  for i, _ in keep {
    idx.push(i)
  }
  idx.sort()
  let res : Array[Int32] = []
  for i in idx {
    res.push(out[i])
  }
  (res, true)
}

///|
/// 紧凑帧 JSON（v1 compactFrame 全量形态；r 按 focus 过滤——focus 为空则全量）。
fn frame_json_full(fr : Frame, focus : Array[String]) -> Json {
  let o = ob().n("i", fr.i).n("l", fr.l).s("f", fr.f).s("s", fr.s)
  ignore(o.j("a", frame_algo_json(fr)))
  ignore(o.j("v", frame_vars_json(fr)))
  ignore(o.sa("c", fr.c))
  ignore(o.j("e", frame_events_json(fr)))
  ignore(o.j("r", frame_arrays_json(fr, focus)))
  ignore(o.j("h", frame_hint_json(fr)))
  o.done()
}

///|
/// 投影帧 JSON：默认 {i,l,f,s}，fields 中出现的键追加。
fn frame_json_proj(fr : Frame, fields : Array[String]) -> Json {
  let o = ob().n("i", fr.i).n("l", fr.l).s("f", fr.f).s("s", fr.s)
  for key in fields {
    match key {
      "r" => ignore(o.j("r", frame_arrays_json(fr, [])))
      "v" => ignore(o.j("v", frame_vars_json(fr)))
      "c" => ignore(o.sa("c", fr.c))
      "e" => ignore(o.j("e", frame_events_json(fr)))
      "a" => ignore(o.j("a", frame_algo_json(fr)))
      "h" => ignore(o.j("h", frame_hint_json(fr)))
      _ => ()
    }
  }
  o.done()
}

///|
fn frame_algo_json(fr : Frame) -> Json {
  match fr.a {
    Some((p, d)) => ob().s("p", p).s("d", d).done()
    None => Json::null()
  }
}

///|
fn frame_vars_json(fr : Frame) -> Json {
  let arr : Array[Json] = []
  for t in fr.v {
    arr.push(jstrs([t.0, t.1, t.2]))
  }
  Json::array(arr)
}

///|
fn frame_events_json(fr : Frame) -> Json {
  let arr : Array[Json] = []
  for ev in fr.e {
    arr.push(
      Json::array([
        Json::number(ev.ty.to_double()),
        Json::number(ev.line.to_double()),
        Json::number(ev.e0.to_double()),
        Json::number(ev.e1.to_double()),
        Json::number(ev.e2.to_double()),
        Json::string(ev.ctx),
      ]),
    )
  }
  Json::array(arr)
}

///|
fn frame_arrays_json(fr : Frame, focus : Array[String]) -> Json {
  let m : Map[String, Json] = Map([])
  for name, els in fr.r {
    if focus.length() == 0 || focus.contains(name) {
      m.set(name, jstrs(els))
    }
  }
  Json::object(m)
}

///|
fn frame_hint_json(fr : Frame) -> Json {
  match fr.h {
    Object(_) as h =>
      ob()
      .s("c", jstr_or(jget(h, "category"), ""))
      .s("o", jstr_or(jget(h, "one_liner"), ""))
      .j("ls", jget(h, "related_lines"))
      .j("fx", jget(h, "suggested_fix_desc"))
      .done()
    _ => Json::null()
  }
}

///|
/// frames_summary：结构索引（只读，几百 token 级）。
fn summary_json(frames : Array[Frame], stopped : String) -> Json {
  let labels : Map[String, Int32] = Map([])
  let vis : Map[String, Int32] = Map([])
  let swap_pairs : Array[Json] = []
  let arr_seen : Map[String, Int32] = Map([])
  let arr_mut : Map[String, Int32] = Map([])
  let heat : Map[Int32, Int32] = Map([])
  let mut prev : Frame? = None
  for fr in frames {
    if fr.s.length() > 0 {
      labels.set(fr.s, labels.get(fr.s).unwrap_or(0) + 1)
    }
    for ev in fr.e {
      let k = vis_kind(ev.ty)
      vis.set(k, vis.get(k).unwrap_or(0) + 1)
      if ev.ty == 2 {
        swap_pairs.push(jints([ev.e0, ev.e1]))
      }
    }
    for name, els in fr.r {
      arr_seen.set(name, els.length())
      match prev {
        Some(p) =>
          match p.r.get(name) {
            Some(pe) => {
              let mut diff = pe.length() != els.length()
              if !diff {
                for i = 0; i < els.length(); i = i + 1 {
                  if els[i] != pe[i] {
                    diff = true
                    break
                  }
                }
              }
              if diff {
                arr_mut.set(name, arr_mut.get(name).unwrap_or(0) + 1)
              }
            }
            None => ()
          }
        None => ()
      }
    }
    if fr.l > 0 {
      heat.set(fr.l, heat.get(fr.l).unwrap_or(0) + 1)
    }
    prev = Some(fr)
  }
  // 字幕频次降序前 20
  let lp : Array[(String, Int32)] = []
  for k, n in labels {
    lp.push((k, n))
  }
  lp.sort_by((x, y) => y.1 - x.1)
  let lm : Map[String, Json] = Map([])
  for i = 0; i < min_int(20, lp.length()); i = i + 1 {
    lm.set(lp[i].0, Json::number(lp[i].1.to_double()))
  }
  let vm : Map[String, Json] = Map([])
  for k, n in vis {
    vm.set(k, Json::number(n.to_double()))
  }
  let arrs : Array[Json] = []
  for name, len in arr_seen {
    arrs.push(
      ob()
      .s("name", name)
      .n("len", len)
      .n("mutations", arr_mut.get(name).unwrap_or(0))
      .done(),
    )
  }
  let hp : Array[(Int32, Int32)] = []
  for l, n in heat {
    hp.push((l, n))
  }
  hp.sort_by((x, y) => y.1 - x.1)
  let heat_lines : Array[Json] = []
  for i = 0; i < min_int(10, hp.length()); i = i + 1 {
    heat_lines.push(jints([hp[i].0, hp[i].1]))
  }
  ob()
  .n("total", frames.length())
  .j("labels_freq", Json::object(lm))
  .j("vis_events", Json::object(vm))
  .a("swap_pairs", swap_pairs)
  .a("arrays", arrs)
  .a("heat_lines", heat_lines)
  .s("stopped", stopped)
  .done()
}

///|
/// annotations：语义事件流（swap/compare 来自 vis_events；call/return 来自
/// 调用栈深度变化）。kind 非空则过滤。
fn annotations_json(frames : Array[Frame], kind : String) -> Json {
  let events : Array[Json] = []
  let mut prev_depth = -1
  for fr in frames {
    for ev in fr.e {
      let k = vis_kind(ev.ty)
      if kind.length() == 0 || kind == k {
        let o = ob()
          .n("step", fr.i)
          .n("line", ev.line)
          .s("kind", k)
          .s("context", ev.ctx)
        if ev.ty == 2 {
          ignore(o.j("pair", jints([ev.e0, ev.e1])))
        }
        events.push(o.done())
      }
    }
    let depth = fr.c.length()
    if prev_depth >= 0 && depth != prev_depth {
      let k = if depth > prev_depth { "call" } else { "return" }
      if kind.length() == 0 || kind == k {
        events.push(
          ob()
          .n("step", fr.i)
          .n("line", fr.l)
          .s("kind", k)
          .s("func", fr.f)
          .n("depth", depth)
          .done(),
        )
      }
    }
    prev_depth = depth
  }
  ob().n("total", events.length()).a("events", events).done()
}

///|
/// frames_query 过滤判据。
fn frame_matches(fr : Frame, filter : Json) -> Bool {
  if jis_null(filter) {
    return true
  }
  match jstr(jget(filter, "label_prefix")) {
    Some(p) => if !fr.s.has_prefix(p) { return false }
    None => ()
  }
  match jint(jget(filter, "line")) {
    Some(l) => if fr.l != l { return false }
    None => ()
  }
  match jstr(jget(filter, "func")) {
    Some(f) => if fr.f != f { return false }
    None => ()
  }
  match jbool(jget(filter, "has_vis_event")) {
    Some(true) => if fr.e.length() == 0 { return false }
    _ => ()
  }
  true
}
