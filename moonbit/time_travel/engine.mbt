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
  }
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
}
