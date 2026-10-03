// SessionConfig 值对象（S7 批二号，2026-09-27）——总计划 §4 L8 行
// 「session(SessionConfig 值对象)」的目标架构落形。
// Rust 侧此物不存在（配置散在 VitroVM 字段 + Session::set_* 两方法），
// 事故链：setup_vm 硬编码覆盖 → config() 不回显 → capi 静默丢弃
// （session_config_test.rs 头注三段复盘）。本侧收拢为单一真相源：
// serve 批的 config.get/set 与回显都走本对象；Session::set_* 是唯一
// 写入口（写后立即 apply 到 VM），reset 保留由 vm/state.mbt 的
// 「装载通道不得设置」纪律承担（双保险）。

///|
/// 会话级配置（跨 run 存活；reset 保留）。
pub(all) struct SessionConfig {
  /// 步数保险丝（会话级）——全速运行的总步数上限。
  mut max_steps : Int
  /// 调用深度保险丝（会话级）——栈帧深度上限。
  mut call_depth_limit : Int
  /// 确定性模式（时钟恒 0 / LCG 固定种子——教学可回放前提）。
  mut deterministic : Bool
} derive(Debug)

///|
/// 默认值 = VitroVM::new 的默认（1000 万步 / MAX_STACK_DEPTH /
/// deterministic **关**）。deterministic 对齐 oracle：Rust 侧唯一宿主
/// RuntimeState 是 #[derive(Default)] ⇒ false（CLI 手册同口径），Rust
/// VitroVM 无此字段；原注释"对齐 Rust deterministic 开"系同义反复
/// 自证——2026-10-02 审阅 P1 销分叉（此前 time/clock 恒 0 + config 帧
/// 两侧恒差）。教学确定性走显式 config.set。
pub fn SessionConfig::default() -> SessionConfig {
  {
    max_steps: @vm.DEFAULT_MAX_STEPS,
    call_depth_limit: @vm.MAX_STACK_DEPTH,
    deterministic: false,
  }
}

///|
/// 应用到 VM（单一写入口的下半段——Session::set_* 调用）。
pub fn SessionConfig::apply_to_vm(
  self : SessionConfig,
  vm : @vm.VitroVM,
) -> Unit {
  // mut 字段跨包只读——经 vm 侧 setter（pub 面已有，语义同注释）
  vm.set_max_steps(self.max_steps)
  vm.set_call_depth_limit(self.call_depth_limit)
  vm.set_deterministic(self.deterministic)
}

///|
/// 从 VM 现值投影（装载已有 VM 时的初始化通道）。
pub fn SessionConfig::from_vm(vm : @vm.VitroVM) -> SessionConfig {
  {
    max_steps: vm.max_steps,
    call_depth_limit: vm.call_depth_limit,
    deterministic: vm.deterministic,
  }
}
