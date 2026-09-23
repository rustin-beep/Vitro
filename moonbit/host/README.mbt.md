# vitro/engine/host — 宿主函数域（110 路由消费侧）

C 教学引擎的宿主函数实现层：**约 100 个 VM 无耦合 handler**——内存族（malloc/calloc/realloc/free，带 E3060/E3061/E3027/E3070 教学诊断）、ctype / math / 字符串 / 转数值 / printf-scanf 格式引擎 / VFS 虚拟文件系统 / rand-time-va_*。handler 一律**不碰值栈**：显式参数进、`HostMemReply{value?, note?, trap?}` 结构化三件出，内存语义可脱离 VM 单独锚定；输出走 **Bytes 字节保真**通道（`putchar(200)` 落 1 字节 `0xC8`）。

## 安装

```bash
moon add vitro/engine/host
```

## 两个场景

### 1. 内存族：分配 → 双重释放的教学文案

```mbt check
///|
test {
  let map = @memory.MemoryMap::new()
  let mem = @memory.Memory::new()
  // malloc(8)：成功返回地址、失败返回 NULL + 教学附注（C 标准语义，不 trap）
  let r = @host.host_malloc(map, 8, 1)
  let p = r.value.unwrap().to_uint()
  assert_eq(r.trap, None)
  // free 一次平安；再 free：trap 字段携带 E3061 逐字教学文案
  @host.host_free(map, p, 2, 2) |> ignore
  let d = @host.host_free(map, p, 3, 3)
  guard d.trap is Some(t) else { fail("双重释放必须给 trap") }
  assert_true(t.contains("E3061"))
}
```

### 2. printf 与输出通道（三通道分流，Bytes 承载）

```mbt check
///|
test {
  let map = @memory.MemoryMap::new()
  let mem = @memory.Memory::new()
  // 格式串先行写入内存（%d 消费一个 u64 位模式实参）
  let fmt = map.allocate_raw(32U, @bytecode.MEM_SIZE).unwrap()
  mem.write_bytes(map, fmt, b"n=%d\n") |> ignore
  let log = @host.OutputLog::new()
  @host.host_printf_n(map, mem, log, fmt, [(42).to_uint64()]) |> ignore
  // stdout 通道是 Shadow 比对的唯一合法来源；note 通道独立不混流
  assert_eq(log.join(@host.OutputKind::Stdout), b"n=42\n")
}
```

## 契约要点

- **受检访问单入口**：handler 的一切内存读写经 `vitro/engine/memory` 的受检原语；`strlen(NULL)` 这类裸读形状在受检口径下是教学 trap（oracle 的静默绕检已逐条登记）。
- **strcpy/strcat 为何在 Host**：路由表（`vitro/engine/bytecode` 的 `is_host_rerouted`）把这两个名字从预编译 libc **改判回 Host**，因为 Host 版带 E3070 缓冲区溢出校验——堆块容量 + 栈缓冲容量双重检查。
- **handler 与执行器解耦**：压栈、trap、等待输入由 VM 执行器消费 `HostMemReply` / `InputOutcome` 完成；本包全部行为可在不起 VM 的前提下测试。
- **VFS 数据在 VM 堆**：文件内容存进内存区域（区域名 `vfs:<名>`），前端内存画布可直接可视化；文本模式 `\r\n` 伸缩照 C 语义。
