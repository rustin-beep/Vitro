// TimelinePlan v0.2（#470 批四）：帧之上的「每帧动效意图」语义层。
//
// 边界（用户拍板）：
//   - additive-only：v0.1 的 sw/cap 字段语义不变；v0.2 新增 ch/bar/cam/enter；
//     不兼容变更递增 pv（本批 pv = 2）。
//   - 意图非像素：类名表 / 时长 token / 布局几何 / 像素下限归宿主执行器；
//     bar 只下发归一比例（0..1），cam 只下发相机拟合提示，宿主决定焦距/时长。
//   - 场景不按变量名猜（与 @view 同纪律）：交换归属只认 vis_events context
//     点名的真实数组名，归属缺失/歧义一律不产 sw。
//   - 帧集语义：ch（差分）基准 = **输入帧集内前一帧**（选中帧集语义，与抽稀
//     边界一致）；cam/enter 的「变化」同样相对帧集内前一帧。
//
// 信封（落到渲染数据的 doc.timeline，与 doc.series_decl 同一版本化 doc）：
//   {"pv":2,"steps":[{"sw":{...},"cap":{...},"ch":{"a":[3]},"bar":{"a":[0.62]},
//                     "cam":{"fit":"calltree","func":"f","depth":2},
//                     "enter":"func:f"}]}
//   steps[k] 与选中帧集零基同构（与 frames 等长）；键缺省 = 无，禁空串。
//
// 生成器输入 = 最小帧视图（宿主无关）：
//   code_line / func_name / semantic_label / vis_events / 数组快照（名字+元素+
//   元素类型）/ 调用栈函数名 / root_cause_hint.category。
//   数组长度是**行为契约的一部分**：旧壳层规则用 `j >= len` 丢弃越界事件
//   （bubble_sort 实测 2 帧 a[4]↔a[5] 越界），不带长度会让交换帧集合与旧路径
//   分叉（56 vs 54）——等价对拍照妖镜。

///|
/// TimelinePlan 协议版本（v0.2）。additive-only；不兼容变更递增。
pub const PLAN_PV : Int32 = 2

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
/// 数组快照最小视图：elements = 显示字符串序列（与协议 elements 同源），
/// element_ty = 引擎元素类型（"char" / "int" / "double" …；未知 = "?"）。
pub(all) struct ArraySnap {
  name : String
  elements : Array[String]
  element_ty : String
}

///|
/// 最小帧视图（宿主无关）。arrays 顺序 = 快照序（同名后写覆盖）。
pub(all) struct FrameView {
  code_line : Int32
  func_name : String
  semantic_label : String
  vis_events : Array[FrameEvent]
  arrays : Array[ArraySnap]
  /// 调用栈函数名（栈底 → 栈顶）；cam/enter 的进场判据。
  call_stack : Array[String]
  /// root_cause_hint.category（空串 = 无）；enter 的 diag 进场判据。
  root_category : String
}

///|
/// 交换脉冲对：name = vis_events context 点名的真实数组名；i/j = 升序下标对。
pub(all) struct SwapPair {
  name : String
  i : Int32
  j : Int32
}

///|
/// 字幕段（cap）：t = 字幕原文（空标签不产 cap）；w = 量感档（1 常规 /
/// 2 交换 / 3 高亮事件预留）；dur = 持续档（v0.1 由 w 派生 = w - 1）。
pub(all) struct Cap {
  t : String
  w : Int32
  dur : Int32
}

///|
/// 相机关键帧（v0.2）：fit = 拟合目标类别（当前只有 "calltree"）；
/// func = 栈顶函数名；depth = 调用栈深度。宿主按自身树把 func/depth 映射到
/// 节点几何（引擎不持有宿主树）。
pub(all) struct Cam {
  fit : String
  func : String
  depth : Int32
}

///|
/// 一帧的动效意图（键缺省 = 无——不产空串/空对象占位）。
pub(all) struct Step {
  sw : SwapPair?
  cap : Cap?
  /// 变化格（v0.2）：name → 升序变化下标集；基准 = 输入帧集内前一帧。
  ch : Map[String, Array[Int32]]?
  /// 量感条归一（v0.2）：name → 逐元素 |v|/max(1, |本帧该数组最大值|)。
  /// 仅整组数值且非 char 数组产；像素下限/高度档归宿主。
  bar : Map[String, Array[Double]]?
  /// 相机关键帧（v0.2）：栈顶/深度相对前帧变化（含首帧）时产。
  cam : Cam?
  /// 进场标识（v0.2）："diag:<category>"（根因首现）或 "func:<name>"（栈顶变化）。
  enter : String?
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
/// 同名快照去重后的名字清单（首见序）——全局数组与数组形参解引用视图可能
/// 同名双发（vm/observe `get_array_snapshots` 不去重；壳层 `r[name]=` 是
/// Map，天然后写覆盖）。重名不是归属歧义。
fn distinct_names(fr : FrameView) -> Array[String] {
  let out : Array[String] = []
  for a in fr.arrays {
    if !out.contains(a.name) {
      out.push(a.name)
    }
  }
  out
}

///|
/// 同名快照：后写覆盖（与壳层 Map 同口径）。
fn snapshot_of(fr : FrameView, name : String) -> ArraySnap? {
  let mut out : ArraySnap? = None
  for a in fr.arrays {
    if a.name == name {
      out = Some(a)
    }
  }
  out
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
    for name in distinct_names(fr) {
      if context_mentions(ev.context, name) {
        hits += 1
        matched = Some(name)
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
    let len = match snapshot_of(fr, name) {
      Some(a) => a.elements.length()
      None => -1
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
/// 变化格（v0.2）：cur 相对 prev（帧集内前一帧）逐元素比较。前帧无该数组
/// 或长度不等的名字不产（首现/结构变化不是「值变了」——与旧宿主差分兜底
/// 同语义）；全部无变化 = 无 ch 键。
fn changed_of(prev : FrameView?, cur : FrameView) -> Map[String, Array[Int32]]? {
  let p = match prev {
    Some(x) => x
    None => return None
  }
  let out : Map[String, Array[Int32]] = Map([])
  for name in distinct_names(cur) {
    let c = snapshot_of(cur, name)
    let q = snapshot_of(p, name)
    match (c, q) {
      (Some(cs), Some(ps)) =>
        if cs.elements.length() == ps.elements.length() {
          let idx : Array[Int32] = []
          for i = 0; i < cs.elements.length(); i = i + 1 {
            if cs.elements[i] != ps.elements[i] {
              idx.push(i)
            }
          }
          if idx.length() > 0 {
            out.set(name, idx)
          }
        }
      _ => ()
    }
  }
  if out.length() == 0 {
    None
  } else {
    Some(out)
  }
}

///|
fn parse_double_opt(s : String) -> Double? {
  let v = @string.parse_double(s) catch { _ => return None }
  if v != v {
    return None
  }
  Some(v)
}

///|
/// 量感条归一（v0.2）：整组元素可解析为数值且非 char 数组才产；
/// ratio = |v| / max(1, max|v|)。像素下限/条高档属宿主执行器。
fn bar_of(cur : FrameView) -> Map[String, Array[Double]]? {
  let out : Map[String, Array[Double]] = Map([])
  for name in distinct_names(cur) {
    let snap = match snapshot_of(cur, name) {
      Some(s) => s
      None => continue
    }
    if snap.element_ty == "char" || snap.elements.length() == 0 {
      continue
    }
    let vals : Array[Double] = []
    let mut ok = true
    for el in snap.elements {
      match parse_double_opt(el) {
        Some(v) => vals.push(v)
        None => {
          ok = false
          break
        }
      }
    }
    if !ok {
      continue
    }
    let mut max_abs = 1.0
    for v in vals {
      if v.abs() > max_abs {
        max_abs = v.abs()
      }
    }
    let ratios : Array[Double] = []
    for v in vals {
      ratios.push(v.abs() / max_abs)
    }
    out.set(name, ratios)
  }
  if out.length() == 0 {
    None
  } else {
    Some(out)
  }
}

///|
fn top_func(fr : FrameView) -> String {
  if fr.call_stack.length() == 0 {
    ""
  } else {
    fr.call_stack[fr.call_stack.length() - 1]
  }
}

///|
/// 相机关键帧（v0.2）：栈顶/深度相对前帧变化（首帧恒产 = 初始镜头）。
fn cam_of(prev : FrameView?, cur : FrameView) -> Cam? {
  let depth = cur.call_stack.length()
  let top = top_func(cur)
  match prev {
    None => Some({ fit: "calltree", func: top, depth, })
    Some(p) =>
      if top_func(p) != top || p.call_stack.length() != depth {
        Some({ fit: "calltree", func: top, depth, })
      } else {
        None
      }
  }
}

///|
/// 进场标识（v0.2）：根因首现优先（教学价值高），否则栈顶函数变化。
/// 首帧不产（初始不是「进场」）。
fn enter_of(prev : FrameView?, cur : FrameView) -> String? {
  let p = match prev {
    Some(x) => x
    None => return None
  }
  if cur.root_category.length() > 0 && cur.root_category != p.root_category {
    return Some("diag:" + cur.root_category)
  }
  if top_func(cur) != top_func(p) {
    return Some("func:" + top_func(cur))
  }
  None
}

///|
/// 生成计划：逐帧一 step（构造即对齐——错位只能经 validate 检出）。
pub fn plan(frames : Array[FrameView]) -> Plan {
  let steps : Array[Step] = []
  let mut prev : FrameView? = None
  for fr in frames {
    let sw = swap_of(fr)
    let has_swap = match sw {
      Some(_) => true
      None => false
    }
    let cap = cap_of(fr, has_swap)
    let ch = changed_of(prev, fr)
    let bar = bar_of(fr)
    let cam = cam_of(prev, fr)
    let enter = enter_of(prev, fr)
    steps.push({ sw, cap, ch, bar, cam, enter, })
    prev = Some(fr)
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
/// 结构化 JSON 出口（键序构造序固化：pv→steps，sw→cap→ch→bar→cam→enter，
/// 缺省键不下发）。字节确定性由白盒锚锁。
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
    match st.ch {
      Some(ch) => {
        let om : Map[String, Json] = Map([])
        for name, idx in ch {
          let arr : Array[Json] = []
          for i in idx {
            arr.push(Json::number(i.to_double()))
          }
          om.set(name, Json::array(arr))
        }
        m.set("ch", Json::object(om))
      }
      None => ()
    }
    match st.bar {
      Some(bar) => {
        let om : Map[String, Json] = Map([])
        for name, ratios in bar {
          let arr : Array[Json] = []
          for r in ratios {
            arr.push(Json::number(r))
          }
          om.set(name, Json::array(arr))
        }
        m.set("bar", Json::object(om))
      }
      None => ()
    }
    match st.cam {
      Some(cam) => {
        let cm : Map[String, Json] = Map([])
        cm.set("fit", Json::string(cam.fit))
        cm.set("func", Json::string(cam.func))
        cm.set("depth", Json::number(cam.depth.to_double()))
        m.set("cam", Json::object(cm))
      }
      None => ()
    }
    match st.enter {
      Some(e) => m.set("enter", Json::string(e))
      None => ()
    }
    steps.push(Json::object(m))
  }
  let top : Map[String, Json] = Map([])
  top.set("pv", Json::number(p.pv.to_double()))
  top.set("steps", Json::array(steps))
  Json::object(top)
}
