// 会话池：每会话一个 Entry（独立 @session.Session + 帧缓冲 + 推进状态机），
// 池 = Map[String, Entry]（Server 直持；池逻辑为自由函数）。
// LRU 上限 8（满则逐出最久未用）；空闲过期 5 分钟（惰性判定——每次
// handle_line 入口扫一遍，过期即逐出；sessions() 可见剩余寿命）。
// Phase 用 Int 常量而非枚举：pub struct（Server 对外面）字段类型禁止依赖
// 包私有类型（错误 4046），常量零级联。

///|
/// 编译失败（L1 工具只能看诊断/出诊断卡，不能推进）。
const PHASE_COMPILE_FAILED : Int32 = 0

///|
/// 已编译未运行。
const PHASE_OPENED : Int32 = 1

///|
/// run+step.begin 后（可推进；含暂停中）。
const PHASE_STARTED : Int32 = 2

///|
/// 终态：正常结束。
const PHASE_FINISHED : Int32 = 3

///|
/// 终态：trap。
const PHASE_TRAPPED : Int32 = 4

///|
/// 终态：等待 stdin 输入。
const PHASE_WAITING_INPUT : Int32 = 5

///|
/// 终态：达到采集上限。
const PHASE_CAPPED : Int32 = 6

///|
fn phase_is_terminal(p : Int32) -> Bool {
  p == PHASE_COMPILE_FAILED ||
  p == PHASE_FINISHED ||
  p == PHASE_TRAPPED ||
  p == PHASE_WAITING_INPUT ||
  p == PHASE_CAPPED
}

///|
const CAP_FRAMES : Int32 = 20000

///|
const POOL_CAP : Int32 = 8

///|
const POOL_TTL_MS : Double = 300000.0

///|
pub struct Entry {
  id : String
  session : @session.Session
  /// 引擎帧 id 序列（invoke 请求自增）
  mut seq : Int32
  title : String
  source : String
  argv : Array[String]
  mut compile_result : Json
  frames : Array[Frame]
  mut phase : Int32
  mut run_result : Json
  mut stdout : String
  mut stderr : String
  /// 断点暂停所在行（0 = 未暂停）
  mut paused_at : Int32
  mut trap_message : String
  /// step_next 的关键帧参照（上一关键帧在 frames 的下标；-1 = 尚无）
  mut last_key : Int32
  opened_at : Double
  mut last_used : Double
}

///|
/// 停止原因文案（sessions / frames_summary / run_to 共用口径）。
fn Entry::stopped(self : Entry) -> String {
  match self.phase {
    PHASE_COMPILE_FAILED => "compile_failed"
    PHASE_OPENED => ""
    PHASE_STARTED =>
      if self.paused_at > 0 {
        "paused@\{self.paused_at}"
      } else {
        ""
      }
    PHASE_FINISHED => "finished"
    PHASE_TRAPPED => "trapped: \{self.trap_message}"
    PHASE_WAITING_INPUT => "waiting_input"
    PHASE_CAPPED => "capped@\{CAP_FRAMES}"
    _ => ""
  }
}

///|
/// 过期逐出（返回被逐出的 id 列表）。
fn pool_evict_expired(
  entries : Map[String, Entry],
  now : Double,
) -> Array[String] {
  let gone : Array[String] = []
  for id, e in entries {
    if now - e.last_used > POOL_TTL_MS {
      gone.push(id)
    }
  }
  for id in gone {
    entries.remove(id)
  }
  gone
}

///|
/// 插入（满则 LRU 逐出最久未用；返回被逐出的 id）。
fn pool_insert(entries : Map[String, Entry], e : Entry) -> Array[String] {
  let gone : Array[String] = []
  while entries.length() >= POOL_CAP {
    let mut oldest : String? = None
    let mut oldest_t = 0.0
    for id, x in entries {
      match oldest {
        None => {
          oldest = Some(id)
          oldest_t = x.last_used
        }
        Some(_) =>
          if x.last_used < oldest_t {
            oldest = Some(id)
            oldest_t = x.last_used
          }
      }
    }
    match oldest {
      Some(id) => {
        entries.remove(id)
        gone.push(id)
      }
      None => break
    }
  }
  entries.set(e.id, e)
  gone
}

///|
/// 取会话并刷新 last_used。
fn pool_touch(
  entries : Map[String, Entry],
  id : String,
  now : Double,
) -> Entry? {
  match entries.get(id) {
    Some(e) => {
      e.last_used = now
      Some(e)
    }
    None => None
  }
}

///|
fn pool_most_recent(entries : Map[String, Entry]) -> String? {
  let mut best : String? = None
  let mut best_t = -1.0
  for id, e in entries {
    if e.last_used > best_t {
      best = Some(id)
      best_t = e.last_used
    }
  }
  best
}

///|
/// sessions() 列表发射。
fn pool_list_json(entries : Map[String, Entry], now : Double) -> Json {
  let arr : Array[Json] = []
  for id, e in entries {
    let remain = (e.last_used + POOL_TTL_MS - now) / 1000.0
    arr.push(
      ob()
      .s("session_id", id)
      .s("title", e.title)
      .s("source_head", source_head(e.source))
      .b("compile_ok", e.phase != PHASE_COMPILE_FAILED)
      .n("frames_collected", e.frames.length())
      .s("stopped", e.stopped())
      .d("opened_at_ms", e.opened_at)
      .n("expires_in_s", if remain < 0.0 { 0 } else { remain.to_int() })
      .done(),
    )
  }
  Json::array(arr)
}
