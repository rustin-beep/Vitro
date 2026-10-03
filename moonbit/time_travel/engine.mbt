///| L9 time_travel·**UnifiedEngine 状态定形**（S8 批一号二段，2026-10-01；
/// 照搬蓝本 native/src/unified/engine.rs:13-32 十一字段，**按目标架构收拢
/// 与裁剪**——总计划 §5「直接按目标架构实现」清单）：
///
/// **字段收拢 11 → 6**：
/// - `frame_cache` + `frame_cache_start_step` + `frame_cache_window_size` +
///   `frame_cache_trim_ratio` 四字段 → **一个 `FrameWindow`**（窗口三参数
///   与起点内聚，O4：Rust 侧 pub 字段 + 测试直改的不变量暴露在本侧结构
///   消除）；
/// - **`pre_step_snap` 不迁**（⑤-5.1：Trap 回退改「检查点+正向重放」，
///   每步 1MB 全量快照容器消亡——Rust 侧每步 `snapshot_into` 的 100GB
///   memcpy 流量/十万步形态不继承；重放落位随批一号三段 run_batch）。
///
/// **照搬字段**：max_steps（默认 100_000，⑤-5.3 参数逐字保留——协议
/// §4 表格锚定）/ is_paused / is_cancelled / is_finished（坑 ⑥-6 粘性终态：
/// Finished 不得重放末帧——"每真实步恰投递一次"）。
///
/// run_batch / seek_to 随批一号三段接线（collector 依赖批二号）；本段
/// 只定形状态与生命周期（new/pause/resume/cancel/reset）。

///|
/// 统一模式（时间旅行）引擎状态机。
pub struct UnifiedEngine {
  /// 检查点管理器（同包——智能判据与快照策略一体）。
  pub checkpoints : CheckpointManager
  /// 帧窗口（frame_cache 四字段的内聚形态——写入口唯一 FrameWindow::push，
  /// 窗口不变量由类型保证）。
  pub frames : FrameWindow
  /// 最大步数预算（默认 100_000——防无限循环耗尽资源；协议锚定值）。
  mut max_steps : Int
  /// 暂停（断点/单步停——resume 复位）。
  mut is_paused : Bool
  /// 取消（长程序中断——粘性，reset 才清）。
  mut is_cancelled : Bool
  /// 终结粘性（坑 ⑥-6：VM Finished 后不得重放末帧；reset 才清）。
  mut is_finished : Bool
  /// trap 终态粘性（issue #29：trap 后不得重执行 trap 指令——此前每批
  /// rollback→重执行→再 Trap，step 流无限循环；reset/seek 才清）。
  mut is_trapped : Bool
  /// trap 死因留存（终态批照报——消费方任意批次可见死因）。
  mut last_trap_message : String?
  /// 算法步骤推断上下文（批四号接线——matches 编排层 compile 时注入，
  /// 三状态随帧演化；跨包只读，写经 set_algorithm_matches）。
  pub algo : AlgoInferCtx
}

///|
pub fn UnifiedEngine::new() -> UnifiedEngine {
  UnifiedEngine::with_max_steps(100_000)
}

///|
/// 自定义步数预算创建（教学长程序放宽入口——Rust with_max_steps 同名同义）。
pub fn UnifiedEngine::with_max_steps(max_steps : Int) -> UnifiedEngine {
  guard max_steps > 0 else {
    abort(
      "UnifiedEngine::with_max_steps: max_steps 须 > 0，得到 \{max_steps}",
    )
  }
  {
    checkpoints: CheckpointManager::new(20),
    frames: FrameWindow::new(),
    max_steps,
    is_paused: false,
    is_cancelled: false,
    is_finished: false,
    is_trapped: false,
    last_trap_message: None,
    algo: AlgoInferCtx::new(),
  }
}

///|
/// 注入算法检测产物（批四号接线——serve compile 后编排层调用；新匹配集
/// 伴随新程序，行入口三状态一并复位。Rust 侧三状态在 session 上跨
/// engine 生命周期存活，reset 不动它们——本侧同语义）。
pub fn UnifiedEngine::set_algorithm_matches(
  self : UnifiedEngine,
  matches : Array[@protocol.AlgorithmMatch],
) -> Unit {
  self.algo.matches = matches
  self.algo.last_line = 0
  self.algo.row_entry_vars = []
  self.algo.last_frame_vars = []
}

///|
/// 自定义窗口参数入口（审阅 P1 补：引擎层小窗口越窗 seek 的可达通道——
/// 协议默认 2_000 使小 target 下 finish_replay 分支全不可达，锚族经此
/// 入口放大参数〔缺陷形态 A12 的补锚正解〕；会话级配置语义同
/// FrameWindow::with_limits——教学长程序放宽）。
pub fn UnifiedEngine::with_limits(
  max_steps : Int,
  window_size : Int,
  trim_ratio : Double,
) -> UnifiedEngine {
  guard max_steps > 0 else {
    abort("UnifiedEngine::with_limits: max_steps 须 > 0，得到 \{max_steps}")
  }
  let e = UnifiedEngine::with_max_steps(max_steps)
  { ..e, frames: FrameWindow::with_limits(window_size, trim_ratio), }
}

///|
pub fn UnifiedEngine::pause(self : UnifiedEngine) -> Unit {
  self.is_paused = true
}

///|
/// 恢复执行（清暂停——断点清除断的**双侧复位**之一侧；另一侧 VM paused
/// 由 serve 接线层连坐，坑 ⑥-8 的"两层暂停位"在编排层单一入口处理）。
/// 命名注：Rust 侧名 resume——MoonBit `resume` 系保留字（reserved_keyword
/// 实证 2026-10-01），改 unpause 同义。
pub fn UnifiedEngine::unpause(self : UnifiedEngine) -> Unit {
  self.is_paused = false
}

///|
pub fn UnifiedEngine::cancel(self : UnifiedEngine) -> Unit {
  self.is_cancelled = true
}

///|
pub fn UnifiedEngine::get_max_steps(self : UnifiedEngine) -> Int {
  self.max_steps
}

///|
/// 会话级配置写入口（CheckpointManager::set_smart_mode 同款字段只读纪律——
/// wbtest/上层经此入口）。
pub fn UnifiedEngine::set_max_steps(self : UnifiedEngine, n : Int) -> Unit {
  guard n > 0 else {
    abort("UnifiedEngine::set_max_steps: n 须 > 0，得到 \{n}")
  }
  self.max_steps = n
}

///|
/// 会话复位（照搬 Rust reset：检查点清 + 窗口清起点归零 + 三粘性标志
/// 复位——reset 是终态的唯一清除通道）。
pub fn UnifiedEngine::reset(self : UnifiedEngine) -> Unit {
  self.checkpoints.clear()
  self.frames.clear()
  self.is_paused = false
  self.is_cancelled = false
  self.is_finished = false
  self.is_trapped = false
  self.last_trap_message = None
}

// ─────────────────────────────────────────────────────────────────────
// 三段-c（2026-10-01）：run_batch · seek_to——批一号收官段。
//
// **⑤-5.1「直接按目标架构实现」项（勘察 5.1，最高优先级）**：Trap 回退
// 不再每步拍 1MB 全量快照（Rust engine.rs:169-170 的 pre_step_snap 机制
// 不迁——常态路径每步成本从 O(1MB) 降到 O(1)），改「最近检查点 + 正向
// 重放」：trap 时取 nearest(step) 恢复、重放至 trap 前一步（O(interval=20)
// 且每次运行至多一次），以 step_index = step 收集 trap 帧——语义与
// 「回退到 pre-step 再 collect」精确一致（trap 帧描述 trap 前状态）。
// 重放确定性前置已备：stdin 游标 / rand / eof / heatmap 均在 VMSnapshot
// 全量态内（U2#11 后半）。
//
// 分叉登记：①root_cause_hint 恒 None（TraceAnalyzer 随 analysis 批接线
// ——Rust trap 帧 analyze_trap 覆写不迁）；②trap_message 在回滚**之前**
// 抓取 vm.error（回滚后 error 随快照清空——两侧观察等价）；③vm 内建步数
// 上限（exec_step 的 max_steps trap）与 engine 层预算是两层——serve 接线
// 层须保证 vm.max_steps ≥ engine.max_steps（登记为 serve 接线义务，随
// step 族五方法批）。
// ─────────────────────────────────────────────────────────────────────

///|
/// 批量自动执行（engine.rs:113-239 run_batch 照搬 + ⑤-5.1 改造）。
/// 泛型 P = 源码行供给（依赖反转——L9 不依赖 session，编排层注入）。
pub fn[P : SourceLineProvider] UnifiedEngine::run_batch(
  self : UnifiedEngine,
  vm : @vm.VitroVM,
  src : P,
  batch_size : Int,
) -> Result[@protocol.AutoStepResult, String] {
  // 坑 ⑥-6（§6-9）：已终结 → 不再 step/collect（Finished 每次调用都会
  // 重放同一帧，违反"每真实步恰投递一次"）。空 payloads + finished=true。
  if self.is_finished {
    return Ok({
      payloads: [],
      finished: true,
      trapped: false,
      waiting_input: false,
      paused: self.is_paused,
      current_line: vm.get_current_line(),
      trap_message: None,
      cache_start_step: self.frames.start_step(),
    })
  }
  // issue #29 trap 终态：不再 step（重执行必再 Trap——rollback 重放止于
  // trap 前一条，下一批 step() 又是同一条 trap 指令）。空批 + trapped
  // 照报 + 死因留存复报；消费方见 trapped=true 即停
  if self.is_trapped {
    return Ok({
      payloads: [],
      finished: false,
      trapped: true,
      waiting_input: false,
      paused: self.is_paused,
      current_line: vm.get_current_line(),
      trap_message: self.last_trap_message,
      cache_start_step: self.frames.start_step(),
    })
  }
  let payloads : Array[@protocol.StepPayload] = []
  let mut finished = false
  let mut trapped = false
  let mut waiting_input = false
  let mut trap_message : String? = None
  for _ in 0..<batch_size {
    if self.is_paused || self.is_cancelled {
      break
    }
    // step = 执行前已执行步数（帧 step_index 口径——第 0 步执行的帧为 0）
    let step = vm.step_count
    let line = vm.get_current_line()
    let cs_len = vm.call_stack_len()
    let func_name : String = if cs_len > 0 {
      vm.call_stack_at(cs_len - 1).func_name
    } else {
      ""
    }
    // 检查点保存（固定间隔 + 智能边界；R3 语义标签单源——降级形态
    // local_vars=None，行文本由 provider 供给）
    let at_callee_entry = if cs_len > 0 {
      vm.call_stack_at(cs_len - 1).caller_line == line
    } else {
      false
    }
    let sline : String = match src.source_line_at(line) {
      Some(s) => s
      None => ""
    }
    let label = infer_semantic_label(
      line,
      None,
      func_name,
      sline,
      at_callee_entry,
    )
    if self.checkpoints.should_checkpoint(step, label) {
      self.checkpoints.save(step, vm)
    }
    // ⑤-5.1：无每步快照（pre_step_snap 不迁）
    match vm.step() {
      Ok => {
        let l2 = vm.get_current_line()
        payloads.push(
          collect(vm, src, vm.heatmap_count_at(l2), step, self.algo),
        )
      }
      Paused => {
        let l2 = vm.get_current_line()
        payloads.push(
          collect(vm, src, vm.heatmap_count_at(l2), step, self.algo),
        )
        self.is_paused = true
      }
      WaitingInput => {
        let l2 = vm.get_current_line()
        payloads.push(
          collect(vm, src, vm.heatmap_count_at(l2), step, self.algo),
        )
        waiting_input = true
        break
      }
      Finished => {
        let l2 = vm.get_current_line()
        payloads.push(
          collect(vm, src, vm.heatmap_count_at(l2), step, self.algo),
        )
        finished = true
        self.is_finished = true
        break
      }
      Trap => {
        // ⑤-5.1：最近检查点 + 正向重放到 trap 前一步（restore 语义对齐
        // Rust pre_step_snap 回退——trap 帧以 trap 前状态收集）。trap 文案
        // 在回滚前抓取（回滚后 error 随快照清空）。
        let msg = vm.error
        if self.rollback_before_trap(vm, step) {
          payloads.push(
            collect(
              vm,
              src,
              vm.heatmap_count_at(vm.get_current_line()),
              step,
              self.algo,
            ),
          )
        } else {
          // 结构性不可达：首循环 should_checkpoint(0) 恒真 ⇒ step ≥ 1 前
          // 必有检查点 0。防御形态 = 不回退（VM 停留 trap 态）收集。
          payloads.push(collect(vm, src, 0UL, step, self.algo))
        }
        // M14 根因提示（S8 analysis 批，engine.rs:209 同形）：全历史 =
        // 窗口帧 + 本批帧（含刚收集的 trap 帧），对 trap 帧装配 hint。
        // get_line 闭包注入源码查询（Rust session.source_line_at 的
        // Provider 形态——诊断域零 session 依赖）
        let trap_idx = payloads.length() - 1
        if trap_idx >= 0 {
          let history = self.frames.slice(
            self.frames.start_step(),
            self.frames.start_step() + self.frames.length(),
          )
          for p in payloads {
            history.push(p)
          }
          let get_line = fn(line : Int) -> String {
            match src.source_line_at(line) {
              Some(s) => s.trim().to_owned()
              None => ""
            }
          }
          match analyze_trap(history, history.length() - 1, msg, get_line) {
            Some(hint) => {
              let tp = payloads[trap_idx]
              payloads[trap_idx] = { ..tp, root_cause_hint: Some(hint), }
            }
            None => ()
          }
        }
        trapped = true
        trap_message = Some(msg)
        self.is_trapped = true
        self.last_trap_message = Some(msg)
        break
      }
    }
    if step >= self.max_steps {
      // U2#7：早退不得丢帧——已执行步的帧先入窗再报错
      self.frames.push_batch(payloads)
      return Err(
        "执行步数超过限制（\{self.max_steps} 步），可能存在无限循环。",
      )
    }
  }
  self.frames.push_batch(payloads)
  Ok({
    payloads,
    finished,
    trapped,
    waiting_input,
    paused: self.is_paused,
    current_line: vm.get_current_line(),
    trap_message,
    cache_start_step: self.frames.start_step(),
  })
}

///|
/// Trap 回退（⑤-5.1 核心）：nearest(step) 恢复 + 正向重放至 executed_steps
/// == step（trap 指令本身不重执行——重放区间止于其前一条，同状态同指令
/// 序列不会重现 trap）。重放步**不 collect 不入窗**（对齐 restore 语义——
/// 帧序列不受回退扰动）。false = 无可用检查点（结构性不可达防御）。
fn UnifiedEngine::rollback_before_trap(
  self : UnifiedEngine,
  vm : @vm.VitroVM,
  step : Int,
) -> Bool {
  guard self.checkpoints.nearest(step) is Some((_, snap)) else { return false }
  vm.restore(snap)
  // 重放屏蔽副作用：Paused 同 Ok 续走（断点在重放态不拦——seek_to 同款
  // Ok|Paused 合并）；WaitingInput 结构不可达（首跑未等待 ⇒ 区间同样
  // 不等待）；Trap/Finished 不可达（区间止于 trap/终结指令之前）。任一
  // 出现即环境漂移，返回 false 走防御分支。
  while vm.step_count < step {
    match vm.step() {
      Ok | Paused => continue
      WaitingInput | Finished | Trap => return false
    }
  }
  true
}

///|
/// Seek 到指定步（engine.rs:267-407 seek_to 照搬——越窗五步契约见协议
/// STEP_PAYLOAD_SCHEMA §4.2）。
pub fn[P : SourceLineProvider] UnifiedEngine::seek_to(
  self : UnifiedEngine,
  target : Int,
  vm : @vm.VitroVM,
  src : P,
) -> @protocol.SeekResult {
  // 坑 ⑥-6：seek = 回到过去——终结标志复位（重放路径若真到终结态会
  // 再次置位），否则 seek 回中段后 step.next 静默返回 finished 空帧。
  // trap 终态同款（issue #29）：seek 回 trap 前即离开终态可续跑
  self.is_finished = false
  self.is_trapped = false
  self.last_trap_message = None
  // 前置：目标已在当前窗口 → 直返（协议 §4.2 之前的快路径）
  match self.frames.frame_at(target) {
    Some(p) => return { success: true, payload: Some(p), error: None, }
    None =>
      // 第 1 步：取最近检查点（增量快照在此重建为全量）；无 → 失败
      match self.checkpoints.nearest(target) {
        None =>
          return {
            success: false,
            payload: None,
            error: Some("没有可用的检查点"),
          }
        Some((cp, snap)) => {
          // 第 2 步：恢复 VM 到该检查点
          vm.restore(snap)
          // 第 3 步前置：越窗重放前重置帧窗口到检查点步（否则 target <
          // 旧窗口起点时 push_or_replace_at 的防御分支吞帧——坑 2 的
          // 63.6GB 形态）
          self.frames.reset_to(cp)
          // 第 3 步：正向重放至目标步（含 target——重放区间排他会把
          // 目标步本身留在窗口外，随后 frame_at(target) 落空，S3 A15
          // 实测形态）
          for step in cp..<=target {
            if self.is_cancelled {
              return {
                success: false,
                payload: None,
                error: Some("执行已取消"),
              }
            }
            // 重放途中动态保存检查点（加速后续 seek；step > cp 判定
            // 避免覆盖恢复源）
            if step > cp && step % self.checkpoints.get_interval() == 0 {
              self.checkpoints.save(step, vm)
            }
            // U2#11 前半：重放步数同受引擎预算约束
            if vm.step_count >= self.max_steps {
              return {
                success: false,
                payload: None,
                error: Some(
                  "重放步数超过限制（\{self.max_steps} 步），可能存在无限循环。",
                ),
              }
            }
            let pre_step = vm.step_count
            match vm.step() {
              Ok | Paused => {
                let l2 = vm.get_current_line()
                self.frames.push_or_replace_at(
                  pre_step,
                  collect(vm, src, vm.heatmap_count_at(l2), pre_step, self.algo),
                )
                // U2#1：push 自带 trim（FrameWindow 类型保证——Rust 侧
                // push 后立即 trim 的修复形态结构化）
              }
              WaitingInput | Finished => {
                // 协议 §4.2 第 4 步：以该步为终点返回 success
                let l2 = vm.get_current_line()
                let payload = collect(
                  vm,
                  src,
                  vm.heatmap_count_at(l2),
                  pre_step,
                  self.algo,
                )
                self.frames.push_or_replace_at(pre_step, payload)
                self.frames.finish_replay(target)
                return { success: true, payload: Some(payload), error: None, }
              }
              Trap => {
                // 协议 §4.2 第 4 步：重放遇 trap → 失败。终态连坐（issue
                // #29）：seek 失败也须记 trap 粘性——否则后续 step.next
                // 在 trap 态 VM 上重执行
                self.is_trapped = true
                self.last_trap_message = Some(vm.error)
                return {
                  success: false,
                  payload: None,
                  error: Some("运行时错误：\{vm.error}"),
                }
              }
            }
          }
          // 第 5 步：窗口重置——只保留目标步及其之前 window_size-1 帧
          self.frames.finish_replay(target)
          match self.frames.frame_at(target) {
            Some(p) => return { success: true, payload: Some(p), error: None, }
            None =>
              return {
                success: false,
                payload: None,
                error: Some("无法获取目标步的 payload"),
              }
          }
        }
      }
  }
}

///|
/// 获取指定范围的帧（engine.rs:493-505 get_payloads——payload.get 引擎侧
/// 形态；钳位在 FrameWindow::slice）。
pub fn UnifiedEngine::get_payloads(
  self : UnifiedEngine,
  start : Int,
  end : Int,
) -> Array[@protocol.StepPayload] {
  self.frames.slice(start, end)
}

///|
/// 当前窗口已收集的最大步数（engine.rs:509-515——空窗口返回 start-1）。
pub fn UnifiedEngine::max_collected_step(self : UnifiedEngine) -> Int {
  let len = self.frames.length()
  if len == 0 {
    self.frames.start_step() - 1
  } else {
    self.frames.start_step() + len - 1
  }
}
