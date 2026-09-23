///| VFS 文件族 17 个 handler（Rust `host/file.rs` 照搬，勘察 §1.7 族 D）。
///
/// **FILE\* 协议**：`fopen` 在堆上分配 4 字节存 fd（区域名 `FILE:<path>`），
/// 返回该地址；其余 handler 经 [`read_fd`] 从该地址取 fd。**哨兵流**（0/1/2）
/// 的取数照搬 oracle 等价形态：oracle 裸读 1–4 号地址（NULL 区恒零）得
/// fd 0，此处前置分支直接给 0——可观测行为一致且不触发 NULL trap。
///
/// **登记分叉**：① `fclose` 释放 FILE\* 块走 memory `release` 单出口（进
/// UAF 窗口；oracle `free_region` 不写 freed_logs——缺口 ②）；② fopen 的
/// append 建文件已修复（坑 13，oracle 死分支）；③ VFS 内部数据读写的
/// 受检化（oracle `read_memory_to` 不查 UAF）。`fprintf` 到自定义 FILE*
/// 不落盘是 oracle 既有偏差（fprintf handler 在批二号——按 stream!=2 全走
/// stdout 通道；VFS 落盘属后续裁定，登记）。

///|
/// 从 FILE\* 取 fd：哨兵（0/1/2）恒 0（oracle 裸读 NULL 区零值的等价形态）；
/// 其余受检读 4 字节。
fn read_fd(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  stream : UInt,
) -> Result[UInt, @memory.MemFault] {
  if stream <= 2U {
    return Ok(0U)
  }
  mem.load_u32(map, stream)
}

///|
/// `fopen(path, mode)` → `FILE*`（oracle `file.rs:4-61`）——fd 成功时在堆上
/// 分配 4 字节存之，返回该地址；失败压 NULL。
pub fn host_fopen(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  vfs : VirtualFileSystem,
  path_addr : UInt,
  mode_addr : UInt,
  alloc_line : Int,
) -> HostMemReply {
  let path = match read_cstring(mem, map, path_addr) {
    Ok(b) => @utf8.decode_lossy(b)
    Err(f) => return fault_reply(f)
  }
  let mode = match read_cstring(mem, map, mode_addr) {
    Ok(b) => @utf8.decode_lossy(b)
    Err(f) => return fault_reply(f)
  }
  let fd = vfs.fopen(map, path, mode)
  if fd == 0U {
    return null_silent()
  }
  // FILE* 4 字节结构体（分配 → 清 freed_logs → 登记 → 命名 → 写 fd）
  let addr = match map.allocate_raw(4U, @bytecode.MEM_SIZE) {
    Some(a) => a
    None => return null_silent()
  }
  map.freed_logs_remove_overlapping(addr, addr + 4U)
  map.register_alloc(addr, 4, alloc_line, "fopen", false)
  rename_region(map, addr, "FILE:\{path}")
  match mem.store_u32(map, addr, fd) {
    Ok(_) => value_only(addr.to_uint64())
    Err(f) => fault_reply(f)
  }
}

///|
/// `fread(buf, size, nmemb, stream)` → 元素数。
pub fn host_fread(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  vfs : VirtualFileSystem,
  buf : UInt,
  size : Int,
  nmemb : Int,
  stream : UInt,
) -> HostMemReply {
  let fd = match read_fd(mem, map, stream) {
    Ok(v) => v
    Err(f) => return fault_reply(f)
  }
  value_only(vfs.fread(mem, map, fd, buf, size, nmemb).to_uint64())
}

///|
/// `fwrite(buf, size, nmemb, stream)` → 元素数。
pub fn host_fwrite(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  vfs : VirtualFileSystem,
  buf : UInt,
  size : Int,
  nmemb : Int,
  stream : UInt,
) -> HostMemReply {
  let fd = match read_fd(mem, map, stream) {
    Ok(v) => v
    Err(f) => return fault_reply(f)
  }
  value_only(vfs.fwrite(mem, map, fd, buf, size, nmemb).to_uint64())
}

///|
/// `fclose(stream)` → 0/-1——关描述符 + 释放 FILE\* 块（oracle 对非堆
/// stream 的 free 失败安全忽略——同）。
pub fn host_fclose(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  vfs : VirtualFileSystem,
  stream : UInt,
  freed_line : Int,
  freed_step : Int,
) -> HostMemReply {
  let fd = match read_fd(mem, map, stream) {
    Ok(v) => v
    Err(f) => return fault_reply(f)
  }
  let ret = vfs.fclose(fd)
  ignore(map.release(stream, freed_line, freed_step))
  value_only(ret.to_uint64())
}

///|
/// `feof(stream)` → 1/0。
pub fn host_feof(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  vfs : VirtualFileSystem,
  stream : UInt,
) -> HostMemReply {
  let fd = match read_fd(mem, map, stream) {
    Ok(v) => v
    Err(f) => return fault_reply(f)
  }
  value_only(vfs.feof(fd).to_uint64())
}

///|
/// `fgets(buf, n, stream)` → buf 或 NULL。
pub fn host_fgets(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  vfs : VirtualFileSystem,
  buf : UInt,
  n : Int,
  stream : UInt,
) -> HostMemReply {
  let fd = match read_fd(mem, map, stream) {
    Ok(v) => v
    Err(f) => return fault_reply(f)
  }
  value_only(vfs.fgets(mem, map, fd, buf, n).to_uint64())
}

///|
/// `fputs(s, stream)` → 0/-1。**stdout(1)/stderr(2) 直接输出到通道**
/// （E-P1-5：stderr 独立通道）——oracle `file.rs:127-136` 同。
pub fn host_fputs(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  vfs : VirtualFileSystem,
  log : OutputLog,
  s_addr : UInt,
  stream : UInt,
) -> HostMemReply {
  if stream == 1U || stream == 2U {
    let s = match read_cstring(mem, map, s_addr) {
      Ok(b) => b
      Err(f) => return fault_reply(f)
    }
    if stream == 2U {
      log.push_stderr(@utf8.encode(@utf8.decode_lossy(s)))
    } else {
      log.push_stdout(@utf8.encode(@utf8.decode_lossy(s)))
    }
    return value_only(0UL)
  }
  let fd = match read_fd(mem, map, stream) {
    Ok(v) => v
    Err(f) => return fault_reply(f)
  }
  value_only(vfs.fputs(mem, map, fd, s_addr).to_uint64())
}

///|
/// `fgetc(stream)` → 字节或 EOF(-1)。
pub fn host_fgetc(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  vfs : VirtualFileSystem,
  stream : UInt,
) -> HostMemReply {
  let fd = match read_fd(mem, map, stream) {
    Ok(v) => v
    Err(f) => return fault_reply(f)
  }
  value_only(vfs.fgetc(mem, map, fd).to_int64().reinterpret_as_uint64())
}

///|
/// `fputc(c, stream)` → 写入值或 EOF(-1)。
pub fn host_fputc(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  vfs : VirtualFileSystem,
  c : Int,
  stream : UInt,
) -> HostMemReply {
  let fd = match read_fd(mem, map, stream) {
    Ok(v) => v
    Err(f) => return fault_reply(f)
  }
  value_only(vfs.fputc(mem, map, fd, c).to_int64().reinterpret_as_uint64())
}

///|
/// `fseek(stream, offset, whence)` → 0/-1。
pub fn host_fseek(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  vfs : VirtualFileSystem,
  stream : UInt,
  offset : Int,
  whence : Int,
) -> HostMemReply {
  let fd = match read_fd(mem, map, stream) {
    Ok(v) => v
    Err(f) => return fault_reply(f)
  }
  value_only(vfs.fseek(mem, map, fd, offset, whence).to_uint64())
}

///|
/// `ftell(stream)` → 物理游标或 -1。
pub fn host_ftell(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  vfs : VirtualFileSystem,
  stream : UInt,
) -> HostMemReply {
  let fd = match read_fd(mem, map, stream) {
    Ok(v) => v
    Err(f) => return fault_reply(f)
  }
  value_only(vfs.ftell(fd).to_int64().reinterpret_as_uint64())
}

///|
/// `rewind(stream)`——无返回值。
pub fn host_rewind(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  vfs : VirtualFileSystem,
  stream : UInt,
) -> HostMemReply {
  let fd = match read_fd(mem, map, stream) {
    Ok(v) => v
    Err(f) => return fault_reply(f)
  }
  vfs.rewind(fd)
  no_reply()
}

///|
/// `fflush(stream)`——恒 0（内存文件无缓冲）；`fd == 0`（含 NULL/哨兵）
/// 视为刷新全部流，同样成功。
pub fn host_fflush(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  vfs : VirtualFileSystem,
  stream : UInt,
) -> HostMemReply {
  let fd = match read_fd(mem, map, stream) {
    Ok(v) => v
    Err(f) => return fault_reply(f)
  }
  let ret = if fd == 0U { 0 } else { vfs.fflush(fd) }
  value_only(ret.to_uint64())
}

///|
/// `perror(s)` → stderr 通道：空前缀 `"Error\n"`，否则 `"prefix: Error\n"`。
pub fn host_perror(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  log : OutputLog,
  s_addr : UInt,
) -> HostMemReply {
  let prefix = match read_cstring(mem, map, s_addr) {
    Ok(b) => @utf8.decode_lossy(b)
    Err(f) => return fault_reply(f)
  }
  if prefix == "" {
    log.push_stderr(b"Error\n")
  } else {
    log.push_stderr(@utf8.encode("\{prefix}: Error\n"))
  }
  no_reply()
}

///|
/// `clearerr(stream)`——无返回值。
pub fn host_clearerr(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  vfs : VirtualFileSystem,
  stream : UInt,
) -> HostMemReply {
  let fd = match read_fd(mem, map, stream) {
    Ok(v) => v
    Err(f) => return fault_reply(f)
  }
  vfs.clearerr(fd)
  no_reply()
}

///|
/// `remove(path)` → 0/-1。
pub fn host_remove(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  vfs : VirtualFileSystem,
  path_addr : UInt,
) -> HostMemReply {
  let path = match read_cstring(mem, map, path_addr) {
    Ok(b) => @utf8.decode_lossy(b)
    Err(f) => return fault_reply(f)
  }
  value_only(vfs.remove(map, path).to_uint64())
}

///|
/// `rename(old, new)` → 0/-1。
pub fn host_rename(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  vfs : VirtualFileSystem,
  old_addr : UInt,
  new_addr : UInt,
) -> HostMemReply {
  let old_path = match read_cstring(mem, map, old_addr) {
    Ok(b) => @utf8.decode_lossy(b)
    Err(f) => return fault_reply(f)
  }
  let new_path = match read_cstring(mem, map, new_addr) {
    Ok(b) => @utf8.decode_lossy(b)
    Err(f) => return fault_reply(f)
  }
  value_only(vfs.rename(old_path, new_path).to_uint64())
}
