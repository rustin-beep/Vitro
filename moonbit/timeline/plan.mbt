// TimelinePlan v0.1（#470 批一）：帧之上的「每帧动效意图」语义层。
//
// 边界（用户拍板）：
//   - 只做 v0.1 字段面 sw/cap；不塞 StepPayload、不做 v0.2 的 bar/ptr/cam；
//   - 意图非像素：类名表 / 时长 token / 布局几何归宿主执行器；
//   - additive-only，不兼容变更递增 pv；
//   - 场景不按变量名猜（与 @view 同纪律）：交换归属只认 vis_events context
//     点名的真实数组名，归属缺失/歧义一律不产 sw。
//
// 信封（落到渲染数据的 doc.timeline，与 doc.series_decl 同一版本化 doc）：
//   {"pv":1,"steps":[{"sw":{"name":"a","i":0,"j":1},
//                     "cap":{"t":"交换 a[0]↔a[1]","w":2,"dur":1}}]}
//   steps[k] 与选中帧集零基同构（与 frames 等长）；键缺省 = 无，禁空串。
//
// 生成器输入 = 最小帧视图（宿主无关）：
//   code_line / func_name / semantic_label / vis_events / 数组快照（名字+长度）。
//   数组长度是**行为契约的一部分**：旧壳层规则用 `j >= len` 丢弃越界事件
//   （bubble_sort 实测 2 帧 a[4]↔a[5] 越界），不带长度会让交换帧集合与旧路径
//   分叉（56 vs 54）——等价对拍照妖镜。

///|
/// TimelinePlan 协议版本（v0.1）。additive-only；不兼容变更递增。
pub const PLAN_PV : Int32 = 1

///|
/// 一条 vis 事件的最小视图（ty=2 且 context 非空才可能产生 sw）。
pub(all) struct FrameEvent {
  ty : Int32
  e0 : Int32
  e1 : Int32
  e2 : Int32
  context : String
}

///|
/// 最小帧视图（宿主无关）。arrays = 数组快照 (名字, 元素数)，顺序 = 快照序。
pub(all) struct FrameView {
  code_line : Int32
  func_name : String
  semantic_label : String
  vis_events : Array[FrameEvent]
  arrays : Array[(String, Int32)]
}

///|
/// 交换脉冲对：name = vis_events context 点名的真实数组名；i/j = 升序下标对。
pub(all) struct SwapPair {
  name : String
  i : Int32
  j : Int32
}

///|
/// 字幕段（cap）：t = 字幕原文（空标签不产 cap）；w = 量感档（v0.1 只有
/// 1 常规 / 2 交换，3 预留 v0.2 高亮事件）；dur = 持续档（0 快 / 1 标准 /
/// 2 慢——v0.1 由 w 派生，2 预留 v0.2）。
pub(all) struct Cap {
  t : String
  w : Int32
  dur : Int32
}

///|
/// 一帧的动效意图（键缺省 = 无——不产空串占位）。
pub(all) struct Step {
  sw : SwapPair?
  cap : Cap?
}

///|
/// 整片计划：steps[k] ↔ 选中帧[k]（零基同构）。
pub(all) struct Plan {
  pv : Int32
  steps : Array[Step]
}

///|
fn is_word_code(c : Int32) -> Bool {
  (c >= 48 && c <= 57) ||
  (c >= 65 && c <= 90) ||
  (c >= 97 && c <= 122) ||
  c == 95
}

///|
fn is_space_code(c : Int32) -> Bool {
  c == 32 || c == 9 || c == 10 || c == 13
}

///|
/// context 是否点名该数组（形如 `a[j]:a[j + 1]` 的左侧表达式语义，旧壳层
/// 规则同款）：名字前须是串首或非标识符/非成员访问字符（不含 '.'），后须
/// 跳空白接 `[`。`obj.arr[` 与 `barr[` 都不算 `arr[`。
fn context_mentions(ctx : String, name : String) -> Bool {
  let n = name.length()
  let total = ctx.length()
  if n == 0 || n > total {
    return false
  }
  let mut i = 0
  while i + n <= total {
    let mut same = true
    let mut k = 0
    while k < n {
      if ctx[i + k].to_int() != name[k].to_int() {
        same = false
        break
      }
      k += 1
    }
    if same {
      let prev_ok = if i == 0 {
        true
      } else {
        let p = ctx[i - 1].to_int()
        !is_word_code(p) && p != 46
      }
      let mut j = i + n
      while j < total && is_space_code(ctx[j].to_int()) {
        j += 1
      }
      let next_ok = j < total && ctx[j].to_int() == 91
      if prev_ok && next_ok {
        return true
      }
    }
    i += 1
  }
  false
}

///|
/// 本帧交换归属：按事件序取首个「context 唯一点名一个本帧数组 + 下标合法
/// （0 ≤ i != j < len）」的 ty=2 事件；归属缺失/歧义/越界 → 不猜、看下一
/// 事件，全无则无 sw（旧规则逐数组过滤的引擎侧等价收口）。
fn swap_of(fr : FrameView) -> SwapPair? {
  for ev in fr.vis_events {
    if ev.ty != 2 || ev.context.length() == 0 {
      continue
    }
    let mut matched : String? = None
    let mut hits = 0
    for t in fr.arrays {
      if context_mentions(ev.context, t.0) {
        hits += 1
        matched = Some(t.0)
      }
    }
    if hits != 1 {
      continue
    }
    let name = match matched {
      Some(n) => n
      None => continue
    }
    let i = if ev.e0 <= ev.e1 { ev.e0 } else { ev.e1 }
    let j = if ev.e0 <= ev.e1 { ev.e1 } else { ev.e0 }
    if i < 0 || i == j {
      continue
    }
    let mut len = -1
    for t in fr.arrays {
      if t.0 == name {
        len = t.1
      }
    }
    if len < 0 || j >= len {
      continue
    }
    return Some({ name, i, j, })
  }
  None
}

///|
/// 字幕段：空标签 = 无 cap（禁空串占位）；w/dur 由是否交换帧决定。
fn cap_of(fr : FrameView, has_swap : Bool) -> Cap? {
  if fr.semantic_label.length() == 0 {
    return None
  }
  let w = if has_swap { 2 } else { 1 }
  Some({ t: fr.semantic_label, w, dur: w - 1, })
}

///|
/// 生成计划：逐帧一 step（构造即对齐——错位只能经 validate 检出）。
pub fn plan(frames : Array[FrameView]) -> Plan {
  let steps : Array[Step] = []
  for fr in frames {
    let sw = swap_of(fr)
    let has_swap = match sw {
      Some(_) => true
      None => false
    }
    let cap = cap_of(fr, has_swap)
    steps.push({ sw, cap, })
  }
  { pv: PLAN_PV, steps, }
}

///|
/// 对齐校验（消费点 fail loud 用；J9 锚：steps 与帧数不一致必红）。
pub fn validate(p : Plan, frame_count : Int32) -> Result[Unit, String] {
  if p.pv != PLAN_PV {
    return Err(
      "timeline plan pv 不兼容：\{p.pv}（本消费面只认 \{PLAN_PV}）",
    )
  }
  let n = p.steps.length()
  if n != frame_count {
    return Err(
      "timeline plan 步骤错位：steps=\{n}，frames=\{frame_count}（steps[k] 必须与选中帧零基同构）",
    )
  }
  Ok(())
}

///|
/// 结构化 JSON 出口（键序构造序固化：pv→steps，sw→cap，name→i→j，
/// t→w→dur；缺省键不下发）。字节确定性由白盒锚锁。
pub fn plan_json(p : Plan) -> Json {
  let steps : Array[Json] = []
  for st in p.steps {
    let m : Map[String, Json] = Map([])
    match st.sw {
      Some(sw) => {
        let sm : Map[String, Json] = Map([])
        sm.set("name", Json::string(sw.name))
        sm.set("i", Json::number(sw.i.to_double()))
        sm.set("j", Json::number(sw.j.to_double()))
        m.set("sw", Json::object(sm))
      }
      None => ()
    }
    match st.cap {
      Some(c) => {
        let cm : Map[String, Json] = Map([])
        cm.set("t", Json::string(c.t))
        cm.set("w", Json::number(c.w.to_double()))
        cm.set("dur", Json::number(c.dur.to_double()))
        m.set("cap", Json::object(cm))
      }
      None => ()
    }
    steps.push(Json::object(m))
  }
  let top : Map[String, Json] = Map([])
  top.set("pv", Json::number(p.pv.to_double()))
  top.set("steps", Json::array(steps))
  Json::object(top)
}
