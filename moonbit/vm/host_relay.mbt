// 蓝本注记：文内 Rust 源引用（`*.rs` 路径/行号/符号）均为档案态蓝本——tag rust-oracle-freeze（2026-10-05 删区），现为本仓自主基线。

///| L7 执行层·VM 域·**REHOST 批 4′：host 窗口中继面**——V8/wasmtime
/// 侧 `env.vitro_host_call` 的**引擎单源回接出口**（host 语义单源在
/// 引擎：`execute_host_func` 110 臂直接复用，零双写）。
///
/// **协议形态**（`cmd/host_relay` js 产物 + dispatchdiff 胶水消费）：
/// - `relay_setup`：中继 VM 装载（堆基 `compute_heap_base` 同源 + argv
///   区〔镜像已含——node 侧 data 铺设含 argv 投影〕+ 1MB 全量镜像
///   `restore_raw`）；
/// - `relay_push_arg`：窗口参数（u64 位模式）按值栈序 push——臂内弹参
///   序〔蓝本逐函数不一致〕透传免疫；
/// - `relay_call`：`execute_host_func(id)` 单源分发；
/// - `relay_reply`：三态出口（返回值位模式 / trap〔码+文案〕/ 停机
///   〔exit 族 exit_code〕）+ stdout 增量 + `waiting_input` 防御标记；
/// - `relay_memory_raw`：1MB 镜像导出（回写 wasm 侧——「双 1MB 内存
///   同步协议」引擎→wasm 方向；wasm→引擎方向 = 每次 `relay_restore_
///   memory` 全量，首版全量拷贝口径）。
///
/// **同构性**：中继 VM 跨调用复用（值栈残留〔printf 多余实参 VM 语义
/// 同款〕/MemoryMap 堆态/free_list/quarantine/rand 状态保持）——与引擎
/// 臂一次完整跑同构；两侧 host 调用序由 wasm/引擎各自执行产生，对拍闸
/// 判终态一致（无循环论证——工程协议只保语义单源）。

///|
/// 中继调用出口（三态 + 通道增量）。
#derive(Debug, Eq)
pub(all) enum RelayOutcome {
  /// 返回值（位模式——void 路由 has_value=false）
  Value(UInt64, Bool)
  /// trap（VM 停机语义——结构化码 + 文案）
  Trap(String, String)
  /// 停机（exit 族——exit_code）
  Halt(Int32)
}

///|
pub extend RelayOutcome with Debug::{to_repr}

///|
pub extend RelayOutcome with Eq::{not_equal, equal}

///|
/// 中继 VM：host 分发专用 VitroVM 实例 + stdout 游标。
pub(all) struct HostRelay {
  /// 分发 VM（code 空——execute_host_func 不取指；memory/mem_map/output/
  /// stack/rand 域消费）
  vm : VitroVM
  /// stdout 已读游标（增量切分——len_of 口径）
  mut stdout_sent : Int32
}

///|
/// 中继装载：堆基同源落位 + 1MB 镜像恢复（node 侧 data 铺设〔含 argv
/// 投影〕已在镜像内——引擎臂 setup 12 步的字节级等价物由镜像整体承载）。
pub fn HostRelay::setup(
  global_data_end : UInt32,
  argc : Int32,
  argv : Array[String],
  image : FixedArray[Byte],
) -> HostRelay {
  let r : HostRelay = { vm: VitroVM::new(), stdout_sent: 0, }
  // R1 ① 堆基（serve_run 同源——compute_heap_base 单源）
  r.vm.mem_map.set_heap_base(
    @bytecode.compute_heap_base(global_data_end, argc, argv),
  )
  r.vm.memory.restore_raw(image)
  r
}

///|
/// wasm → 引擎方向内存同步（首版全量——批 4′ 口径；脏页稀疏化随实测）。
pub fn HostRelay::restore_memory(
  self : HostRelay,
  image : FixedArray[Byte],
) -> Unit {
  self.vm.memory.restore_raw(image)
}

///|
/// 窗口参数入栈（值栈序——p[0] 先入 = 底；臂内弹参照常）。
pub fn HostRelay::push_arg(self : HostRelay, bits : UInt64) -> Unit {
  self.vm.push(bits)
}

///|
/// host 分发（execute_host_func 单源）——三态出口 + stdout 增量 +
/// waiting 防御（白名单路由理论不可达——防御面 fail loud）。
pub fn HostRelay::call(
  self : HostRelay,
  id : Int32,
) -> (RelayOutcome, Bytes, Bool) {
  self.vm.execute_host_func(id, 0, 0)
  // waiting 防御（Stdin 族禁译域——到达即协议破裂标记）
  let waiting = self.vm.waiting_input
  if waiting {
    self.vm.clear_waiting_input()
  }
  // 出口三态（首查停机——exit 族 finished 无返回值；trap 次之；返回值末）
  let outcome : RelayOutcome = if self.vm.finished {
    Halt(self.vm.exit_code)
  } else if self.vm.error != "" {
    Trap(self.vm.trap_code, self.vm.error)
  } else {
    // 返回值：值栈顶（host 臂 value → push；void/no_reply 不压）
    //——白名单 ret 形态表（host_window_sig）与臂 push 通道一致性由
    // 对拍闸背书；此处按「栈上有则取」形态读回（不弹——残留语义与
    // VM 执行流一致，消费侧〔wasm〕已弹参对应侧不重复管理）
    match self.vm.stack.pop() {
      Some(v) => Value(v, true)
      None => Value(0UL, false)
    }
  }
  // stdout 增量（len_of 游标——环形丢最旧时 total 回落，全量重发）
  let now = self.vm.output.len_of(@host.Stdout)
  let all = self.vm.output.join(@host.Stdout)
  let delta : Bytes = if now >= self.stdout_sent {
    let cut = all.length() - (now - self.stdout_sent)
    if cut >= 0 && cut <= all.length() {
      let arr : Array[Byte] = []
      for i = cut; i < all.length(); i = i + 1 {
        arr.push(all[i])
      }
      Bytes::from_array(arr)
    } else {
      all
    }
  } else {
    all
  }
  self.stdout_sent = now
  (outcome, delta, waiting)
}

///|
/// 引擎 → wasm 方向内存同步（1MB 全量导出——`dump_memory_raw` 同通道）。
pub fn HostRelay::memory_raw(self : HostRelay) -> Bytes {
  self.vm.dump_memory_raw()
}

///|
/// trap/停机后中继终态 rc（对拍锚——dispatchdiff 消费：Halt → rc /
/// Trap → trap 态分类）。
pub fn HostRelay::final_rc(self : HostRelay) -> Int32 {
  if self.vm.finished {
    self.vm.exit_code
  } else {
    self.vm.final_return_value()
  }
}
