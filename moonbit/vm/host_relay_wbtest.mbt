// 蓝本注记：文内 Rust 源引用（`*.rs` 路径/行号/符号）均为档案态蓝本——tag rust-oracle-freeze（2026-10-05 删区），现为本仓自主基线。

///| host_relay 锚（批 4′）——窗口回接的引擎单源分发行为验。

///|
/// 中继装载 + putchar 分发 + stdout 增量 + 返回值三态。
test "host_relay: setup + putchar 回接" {
  let image : FixedArray[Byte] = FixedArray::make(1048576, b'\x00')
  let relay = HostRelay::setup(0x5000U, 0, [], image)
  // putchar('A')——1 参、返回 'A'
  relay.push_arg(65UL)
  let (outcome, delta, waiting) = relay.call(34)
  inspect(waiting, content="false")
  inspect(delta.to_array().length(), content="1")
  inspect(delta[0].to_int(), content="65")
  match outcome {
    Value(v, has) => {
      inspect(v, content="65")
      inspect(has, content="true")
    }
    _ => fail("putchar 应返回值")
  }
  // 二次调用：stdout 增量只含新输出（游标切分）
  relay.push_arg(66UL)
  let (_, delta2, _) = relay.call(34)
  inspect(delta2.to_array().length(), content="1")
  inspect(delta2[0].to_int(), content="66")
}

///|
/// exit 停机三态（Halt 出口 + exit_code）。
test "host_relay: exit 停机" {
  let image : FixedArray[Byte] = FixedArray::make(1048576, b'\x00')
  let relay = HostRelay::setup(0x5000U, 0, [], image)
  relay.push_arg(7UL)
  let (outcome, _, _) = relay.call(38)
  match outcome {
    Halt(rc) => inspect(rc, content="7")
    _ => fail("exit 应停机态")
  }
}

///|
/// 非法 free（NULL 区）→ Trap 三态（结构化码通道——trap 首错语义）。
test "host_relay: trap 通道" {
  let image : FixedArray[Byte] = FixedArray::make(1048576, b'\x00')
  let relay = HostRelay::setup(0x5000U, 0, [], image)
  relay.push_arg(0x20000UL) // free(未分配地址)——非 NULL 的非法释放
  let (outcome, _, _) = relay.call(3)
  match outcome {
    Trap(code, _) => inspect(code != "", content="true")
    _ =>
      fail("free(未分配指针) 应 trap（教学语义——invalid free）")
  }
}

///|
/// 内存同步往返：restore → host 写（malloc）→ memory_raw 回读。
test "host_relay: 双 1MB 同步" {
  let image : FixedArray[Byte] = FixedArray::make(1048576, b'\x00')
  let relay = HostRelay::setup(0x5000U, 0, [], image)
  relay.push_arg(16UL) // malloc(16)
  let (outcome, _, _) = relay.call(2)
  match outcome {
    Value(addr, true) => {
      // 堆基 0x5000——首分配地址 = heap_base（无 argv/data_end 偏移）
      inspect(addr, content="20480") // 0x5000
      // 引擎镜像回读：MemoryMap 分配登记在 mem_map（镜像本身无写）
      let raw = relay.memory_raw()
      inspect(raw.length(), content="1048576")
    }
    _ => fail("malloc 应返回地址")
  }
}
