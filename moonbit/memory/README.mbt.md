# vitro/engine/memory — 1MB 线性内存与堆状态机

教学 C 引擎的执行层内存子系统：**1MB 线性内存载体**（脏页位图追踪）+ **堆状态机**（bump 分配 + 256KB 有界隔离 FIFO + first-fit 复用）+ **单一受检访问入口**（NULL 陷阱区 → 越界 → Use-After-Free 三重判定）。字节载体不外泄——包外拿不到裸字节，一切读写都过受检判定，"绕过检查写内存"这类缺陷在结构上不可能发生。

## 安装

```bash
moon add vitro/engine/memory
```

## 两个场景

### 1. 分配与受检读写

```mbt check
///|
test {
  let map = @memory.MemoryMap::new()
  let mem = @memory.Memory::new()
  // 分配 64 字节（内部按 4 对齐；None = 堆耗尽，容量常量单源在 bytecode 包）
  let p = map.allocate_raw(64U, @bytecode.MEM_SIZE).unwrap()
  // 分配两步契约：取地址 + 登记区域（名称/归属行入堆元数据，供诊断渲染）
  map.register_alloc(p, 64, 1, "demo", true)
  // 段级受检写：整段一次判定 + 载体原生填充
  mem.fill(map, p, 8, b'A') |> ignore
  // 受检读（i8 符号扩展；u32/u64 读变体另有 load_u32/load_u64）
  assert_eq(mem.load_i8(map, p), Ok(65))
  // 释放走唯一出口：条目置 freed + 登记 UAF 窗口 + 进 FIFO 隔离区，三步原子
  assert_true(map.release(p, 7, 1) is Some(_))
}
```

### 2. Use-After-Free 探测（教学核心）

```mbt check
///|
test {
  let map = @memory.MemoryMap::new()
  let mem = @memory.Memory::new()
  let p = map.allocate_raw(64U, @bytecode.MEM_SIZE).unwrap()
  map.register_alloc(p, 64, 1, "demo", true)
  ignore(map.release(p, 7, 1)) // 第 7 行释放、第 1 步
  // 释放后再写：结构化 UAF 故障——载荷自带分配/释放行号步号与访问类别，
  // 教学文案由上层（host/vm）按故障类别渲染
  guard mem.store_i8(map, p, 66) is Err(@memory.MemFault::UseAfterFree(_, _)) else {
    fail("释放后写入必须报 UAF")
  }
  // 未释放的合法地址不受影响
  let q = map.allocate_raw(16U, @bytecode.MEM_SIZE).unwrap()
  assert_eq(mem.load_i8(map, q), Ok(0))
}
```

## 契约要点

- **字节载体私有**：`Memory` 的字节与脏页位图不对外暴露；一切访问经 `load_*` / `store_*` / `fill` / `copy` / `write_bytes`，判定统一走 `MemoryMap::check_access`。
- **释放唯一出口**：`MemoryMap::release` 同时完成置 freed、登记 freed_logs、进隔离区——三条释放路径（free / realloc(p,0) / 内部回收）不允许各写一遍。
- **freed_logs 有序结构**：区间查询靠"地址有序 + 二分"，普通哈希表会静默漏检 UAF（不是慢，是错）。
- **地址布局常量不双写**：`MEM_SIZE` / `HEAP_START` / 对齐等单源在 `vitro/engine/bytecode`，本包只消费。
