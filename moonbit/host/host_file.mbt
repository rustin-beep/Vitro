///| VFS 文件族 17 个 handler（Rust `host/file.rs` 照搬，勘察 §1.7 族 D）。
///
/// **FILE\* 协议**：`fopen` 在堆上分配 4 字节存 fd（区域名 `FILE:<path>`），
/// 返回该地址；其余 handler 经 [`read_fd`] 从该地址取 fd。
///
/// **标准流句柄分流（病 15 批 B，#61，2026-10-10）**：预处理宏
/// stdin/stdout/stderr 展开为裸 int 0/1/2（非 FILE\* 堆地址）——各
/// handler 前置分流：写族（fputc/fwrite）直推 OutputLog 对应通道、
/// 读族（fgetc/fgets/fread）走 InputState 批读原语（与 scanf/getchar
/// 同游标）、状态族（fseek/ftell 返 -1、fclose/fflush 返 0、rewind/
/// clearerr no-op、feof 查 EOF 粘滞位）。旧形态（≤2 一律折叠 fd=0 静默
/// 失败）系 oracle 照搬——`fputc('x', stdout)` 合法 C 全静默丢，在案。
///
/// **登记分叉**：① `fclose` 释放 FILE\* 块走 memory `release` 单出口（进
/// UAF 窗口；oracle `free_region` 不写 freed_logs——缺口 ②）；② fopen 的
/// append 建文件已修复（坑 13，oracle 死分支）；③ VFS 内部数据读写的
/// 受检化（oracle `read_memory_to` 不查 UAF）。`fprintf` 到自定义 FILE*
/// 不落盘是 oracle 既有偏差（fprintf handler 在批二号——按 stream!=2 全走
/// stdout 通道；VFS 落盘属后续裁定，登记）。

///|
/// 从 FILE\* 取 fd：非标准流（>2）受检读 4 字节。
fn read_fd(
  mem : @memory.Memory,
  map : @memory.MemoryMap,
  stream : UInt,
) -> Result[UInt, @memory.MemFault] {
  mem.load_u32(map, stream)
}

///|
/// stdin 批读原语（病 15 批 B）——跨行取 n 字节（ungetc 优先）。
/// **None = 零消费等待**（Interactive 无可用字节——vm 参数回推 + ip 回退
/// 后重试安全，scanf 虚拟流同款判据）；Some = 游标已一次性提交
/// （空 = EOF〔Batch 置粘滞〕；短读 = 剩余拼接不足 n——read(2) 同款）。
pub fn InputState::take_stdin_bytes(self : InputState, n : Int) -> Bytes? {
  if n <= 0 {
    return Some(b"")
  }
  let out : Array[Byte] = []
  match self.ungetc {
    Some(ch) => {
      out.push(ch.to_byte())
      self.ungetc = None
    }
    None => ()
  }
  while out.length() < n && self.index < self.lines.length() {
    let line = self.lines[self.index]
    while self.char_offset < line.length() && out.length() < n {
      out.push(line[self.char_offset])
      self.char_offset = self.char_offset + 1
    }
    if self.char_offset >= line.length() {
      self.index = self.index + 1
      self.char_offset = 0
    }
  }
  if out.length() == 0 {
    if self.batch {
      self.set_eof()
      return Some(b"")
    }
    return None
  }
  Some(Bytes::from_array(out))
}

///|
/// fgets 的 stdin 原语（病 15 批 B）——**单行域**取 min(max, 当前行剩余)
/// 字节（行数据含尾 \n，天然止于行尾；当前行无尾 \n 且未满额时不跨行
/// 续读——与 C 字节流形态的边缘差登记，教学面〔feed 行粒度〕等价）。
pub fn InputState::take_stdin_line(self : InputState, max : Int) -> Bytes? {
  if max <= 0 {
    return Some(b"")
  }
  let out : Array[Byte] = []
  match self.ungetc {
    Some(ch) => {
      out.push(ch.to_byte())
      self.ungetc = None
    }
    None => ()
  }
  if self.index < self.lines.length() {
    let line = self.lines[self.index]
    while self.char_offset < line.length() && out.length() < max {
      out.push(line[self.char_offset])
      self.char_offset = self.char_offset + 1
    }
    if self.char_offset >= line.length() {
      self.index = self.index + 1
      self.char_offset = 0
    }
  }
  if out.length() == 0 {
    if self.batch {
      self.set_eof()
      return Some(b"")
    }
    return None
  }
  Some(Bytes::from_array(out))
}

///|
/// 标准流读结果（host → vm，病 15 批 B）：读族的 Interactive 等待语义
/// HostMemReply 表达不了——vm 臂 match 消费（`waiting_input = true`，
/// getchar 臂同款）。
pub enum StdioRead {
  Done(HostMemReply)
  StdioWaiting
}

///|
/// `fgetc` 标准流分流：stdin 复用 getchar 全套（ungetc/EOF 粘滞/等待）；
/// stdout/stderr 读取返 EOF。
fn host_fgetc_stdio(input : InputState, stream : UInt) -> StdioRead {
  if stream != 0U {
    return StdioRead::Done(value_only((-1).to_int64().reinterpret_as_uint64()))
  }
  match host_getchar(input) {
    Value(v) => StdioRead::Done(value_only(v))
    Trap(msg) => StdioRead::Done(trap_only(msg))
    Waiting => StdioRead::StdioWaiting
  }
}

///|
/// `fgetc` 总分发（VFS 文件 + 标准流）。
pub fn host_fgetc_dispatch(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  vfs : VirtualFileSystem,
  input : InputState,
  stream : UInt,
) -> StdioRead {
  if stream <= 2U {
    return host_fgetc_stdio(input, stream)
  }
  StdioRead::Done(host_fgetc(map, mem, vfs, stream))
}

///|
/// `fgets(buf, n, stream)` 标准流分流：stdin 单行读（成功写 buf+NUL 返
/// buf；EOF/等待 返 NULL——等待时 buf 不写）；stdout/stderr 返 NULL。
fn host_fgets_stdio(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  input : InputState,
  buf : UInt,
  n : Int,
) -> StdioRead {
  if n <= 0 {
    return StdioRead::Done(value_only(0UL))
  }
  match input.take_stdin_line(n - 1) {
    None => StdioRead::StdioWaiting
    Some(b) => {
      if b.length() == 0 {
        return StdioRead::Done(value_only(0UL)) // EOF → NULL
      }
      match mem.write_bytes(map, buf, b) {
        Ok(_) =>
          // NUL 终止符（正文后一字节；fault 同口径转 trap）
          match
            mem.write_bytes(
              map,
              buf + b.length().reinterpret_as_uint(),
              b"\x00",
            ) {
            Ok(_) => StdioRead::Done(value_only(buf.to_uint64()))
            Err(f) => StdioRead::Done(fault_reply(f))
          }
        Err(f) => StdioRead::Done(fault_reply(f))
      }
    }
  }
}

///|
/// `fgets` 总分发（VFS 文件 + 标准流）。
pub fn host_fgets_dispatch(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  vfs : VirtualFileSystem,
  input : InputState,
  buf : UInt,
  n : Int,
  stream : UInt,
) -> StdioRead {
  if stream <= 2U {
    if stream == 0U {
      return host_fgets_stdio(map, mem, input, buf, n)
    }
    return StdioRead::Done(value_only(0UL)) // 读 stdout/stderr → NULL
  }
  StdioRead::Done(host_fgets(map, mem, vfs, buf, n, stream))
}

///|
/// `fread` 标准流分流：stdin 跨行批读（整元素截断）；stdout/stderr 返
/// 0 元素。
fn host_fread_stdio(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  input : InputState,
  buf : UInt,
  size : Int,
  nmemb : Int,
) -> StdioRead {
  if size <= 0 || nmemb <= 0 {
    return StdioRead::Done(value_only(0UL))
  }
  let total = size * nmemb
  match input.take_stdin_bytes(total) {
    None => StdioRead::StdioWaiting
    Some(b) => {
      if b.length() == 0 {
        return StdioRead::Done(value_only(0UL)) // EOF
      }
      match mem.write_bytes(map, buf, b) {
        Ok(_) => StdioRead::Done(value_only((b.length() / size).to_uint64()))
        Err(f) => StdioRead::Done(fault_reply(f))
      }
    }
  }
}

///|
/// `fread` 总分发（VFS 文件 + 标准流）。
pub fn host_fread_dispatch(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  vfs : VirtualFileSystem,
  input : InputState,
  buf : UInt,
  size : Int,
  nmemb : Int,
  stream : UInt,
) -> StdioRead {
  if stream <= 2U {
    if stream == 0U {
      return host_fread_stdio(map, mem, input, buf, size, nmemb)
    }
    return StdioRead::Done(value_only(0UL))
  }
  StdioRead::Done(host_fread(map, mem, vfs, buf, size, nmemb, stream))
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
  let path = @utf8.decode_lossy(
    read_cstring_raise(mem, map, path_addr) catch {
      AccessFault::Fault(f~) => return fault_reply(f)
    },
  )
  let mode = @utf8.decode_lossy(
    read_cstring_raise(mem, map, mode_addr) catch {
      AccessFault::Fault(f~) => return fault_reply(f)
    },
  )
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
  store_u32_raise(mem, map, addr, fd) catch {
    AccessFault::Fault(f~) => return fault_reply(f)
  }
  value_only(addr.to_uint64())
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
  let fd = read_fd_raise(mem, map, stream) catch {
    AccessFault::Fault(f~) => return fault_reply(f)
  }
  value_only(vfs.fread(mem, map, fd, buf, size, nmemb).to_uint64())
}

///|
/// `fwrite(buf, size, nmemb, stream)` → 元素数。标准流分流（病 15 批 B）：
/// stdout/stderr 读 buf 直推对应通道返 nmemb；stdin 不可写返 0。
pub fn host_fwrite(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  vfs : VirtualFileSystem,
  log : OutputLog,
  buf : UInt,
  size : Int,
  nmemb : Int,
  stream : UInt,
) -> HostMemReply {
  if stream <= 2U {
    if stream == 0U {
      return value_only(0UL)
    }
    let total = if size > 0 && nmemb > 0 { size * nmemb } else { 0 }
    if total <= 0 {
      return value_only(0UL)
    }
    match read_span(mem, map, buf, total) {
      Ok(data) => {
        if stream == 2U {
          log.push_stderr(Bytes::from_array(data))
        } else {
          log.push_stdout(Bytes::from_array(data))
        }
        return value_only(nmemb.to_uint64())
      }
      Err(f) => return fault_reply(f)
    }
  }
  let fd = read_fd_raise(mem, map, stream) catch {
    AccessFault::Fault(f~) => return fault_reply(f)
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
  if stream <= 2U {
    // 标准流返 0 成功（C 语义合法；伪句柄不真关、流常驻——病 15 批 B 拍板）
    return value_only(0UL)
  }
  let fd = read_fd_raise(mem, map, stream) catch {
    AccessFault::Fault(f~) => return fault_reply(f)
  }
  let ret = vfs.fclose(fd)
  ignore(map.release(stream, freed_line, freed_step))
  value_only(ret.to_uint64())
}

///|
/// `feof(stream)` → 1/0。stdin 查 InputState EOF 粘滞位（病 15 批 B）；
/// stdout/stderr 恒 0。
pub fn host_feof(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  vfs : VirtualFileSystem,
  input : InputState,
  stream : UInt,
) -> HostMemReply {
  if stream <= 2U {
    let v = if stream == 0U && input.eof { 1 } else { 0 }
    return value_only(v.to_uint64())
  }
  let fd = read_fd_raise(mem, map, stream) catch {
    AccessFault::Fault(f~) => return fault_reply(f)
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
  let fd = read_fd_raise(mem, map, stream) catch {
    AccessFault::Fault(f~) => return fault_reply(f)
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
    let s = read_cstring_raise(mem, map, s_addr) catch {
      AccessFault::Fault(f~) => return fault_reply(f)
    }
    // #66：C 串字节直推（旧 lossy 对毁裸 Latin-1 字节）
    if stream == 2U {
      log.push_stderr(s)
    } else {
      log.push_stdout(s)
    }
    return value_only(0UL)
  }
  let fd = read_fd_raise(mem, map, stream) catch {
    AccessFault::Fault(f~) => return fault_reply(f)
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
  let fd = read_fd_raise(mem, map, stream) catch {
    AccessFault::Fault(f~) => return fault_reply(f)
  }
  value_only(vfs.fgetc(mem, map, fd).to_int64().reinterpret_as_uint64())
}

///|
/// `fputc(c, stream)` → 写入值或 EOF(-1)。标准流分流（病 15 批 B）：
/// stdout/stderr 单字节直推通道返 (unsigned char)c；stdin 不可写返 EOF。
pub fn host_fputc(
  map : @memory.MemoryMap,
  mem : @memory.Memory,
  vfs : VirtualFileSystem,
  log : OutputLog,
  c : Int,
  stream : UInt,
) -> HostMemReply {
  if stream <= 2U {
    if stream == 0U {
      return value_only((-1).to_int64().reinterpret_as_uint64())
    }
    let b = Bytes::make(1, (c & 0xFF).to_byte())
    if stream == 2U {
      log.push_stderr(b)
    } else {
      log.push_stdout(b)
    }
    return value_only((c & 0xFF).to_uint64())
  }
  let fd = read_fd_raise(mem, map, stream) catch {
    AccessFault::Fault(f~) => return fault_reply(f)
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
  if stream <= 2U {
    // 标准流非 seekable（C 管道/终端同款失败）
    return value_only(0xFFFFFFFFFFFFFFFFUL)
  }
  let fd = read_fd_raise(mem, map, stream) catch {
    AccessFault::Fault(f~) => return fault_reply(f)
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
  if stream <= 2U {
    return value_only((-1).to_int64().reinterpret_as_uint64())
  }
  let fd = read_fd_raise(mem, map, stream) catch {
    AccessFault::Fault(f~) => return fault_reply(f)
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
  if stream <= 2U {
    return no_reply() // 标准流 no-op
  }
  let fd = read_fd_raise(mem, map, stream) catch {
    AccessFault::Fault(f~) => return fault_reply(f)
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
  if stream <= 2U {
    return value_only(0UL) // 标准流刷新成功
  }
  let fd = read_fd_raise(mem, map, stream) catch {
    AccessFault::Fault(f~) => return fault_reply(f)
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
  let prefix = @utf8.decode_lossy(
    read_cstring_raise(mem, map, s_addr) catch {
      AccessFault::Fault(f~) => return fault_reply(f)
    },
  )
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
  if stream <= 2U {
    return no_reply() // 标准流 no-op（不清 stdin EOF 粘滞——教学价值低，登记）
  }
  let fd = read_fd_raise(mem, map, stream) catch {
    AccessFault::Fault(f~) => return fault_reply(f)
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
  let path = @utf8.decode_lossy(
    read_cstring_raise(mem, map, path_addr) catch {
      AccessFault::Fault(f~) => return fault_reply(f)
    },
  )
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
  let old_path = @utf8.decode_lossy(
    read_cstring_raise(mem, map, old_addr) catch {
      AccessFault::Fault(f~) => return fault_reply(f)
    },
  )
  let new_path = @utf8.decode_lossy(
    read_cstring_raise(mem, map, new_addr) catch {
      AccessFault::Fault(f~) => return fault_reply(f)
    },
  )
  value_only(vfs.rename(old_path, new_path).to_uint64())
}
