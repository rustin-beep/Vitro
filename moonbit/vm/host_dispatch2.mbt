///| L7 执行层·VM 域·executor：**CallHost 分发二段**（字符串 / 转数值 /
/// VFS / va_* 族，46 臂——批三号第二段）。
///
/// 剩余 fail loud：printf/scanf 族 10（需 vm 侧 read_cstring + 格式符
/// 计数 + 参数组弹）与 qsort/bsearch/guards×2/STEP 8（`call_user_function`
/// 状态保存恢复）——批三号第三段。
///
/// **两个接线义务本段落位**：
/// - 义务②：strcpy/strcat 的 `StackBufferSpan` 数组由本层展平 call_stack
///   （`stack_buffer_spans`——内层帧优先，与 Rust
///   `check_stack_buffer_capacity` 的 `iter().rev()` 同序）；
/// - 义务③：strtol/strtod 的 `errno_addr` 从符号表解析（`resolve_errno_addr`）。

///|
/// 义务②：展平调用栈的栈缓冲表（内层帧优先——命中即停语义由 host 侧
/// 按「首个包含 dest 的 span」判定，序与 oracle 的 rev 遍历一致）。
fn VitroVM::stack_buffer_spans(self : VitroVM) -> Array[@host.StackBufferSpan] {
  let spans : Array[@host.StackBufferSpan] = []
  for i = self.call_stack.length() - 1; i >= 0; i = i - 1 {
    let frame = self.call_stack[i]
    for buf in frame.local_buffers {
      spans.push(@host.StackBufferSpan::{
        base: frame.locals_base + buf.offset.reinterpret_as_uint(),
        size: buf.size,
        name: buf.name,
      })
    }
  }
  spans
}

///|
/// 义务③：解析 `errno` 符号地址（全局符号表按名查；无则 None——host 侧
/// 跳过 errno 写入，与 oracle「无符号则不写」同口径）。
fn VitroVM::resolve_errno_addr(self : VitroVM) -> UInt? {
  for sym in self.symbols {
    if !sym.is_local && sym.name == "errno" {
      return Some(sym.addr)
    }
  }
  None
}

///|
/// 二段分发（id 表与 Rust `host_func_id.rs` 常量对齐；弹参序逐臂照搬
/// oracle 同名 handler 的 pop 次序）。
fn VitroVM::execute_host_func2(
  self : VitroVM,
  id : Int,
  line : Int,
  column : Int,
) -> Unit {
  match id {
    // ── 字符串 / 内存族 19（大多：pop 两个地址 [+ n]）──
    30 => {
      let addr = self.pop_addr()
      let reply = @host.host_strlen(self.memory, self.mem_map, addr)
      self.apply_reply(reply)
    }
    31 => {
      let dest = self.pop_addr()
      let src = self.pop_addr()
      let reply = @host.host_strcpy(
        self.mem_map,
        self.memory,
        dest,
        src,
        self.stack_buffer_spans(),
      )
      self.apply_reply(reply)
    }
    32 => {
      let addr1 = self.pop_addr()
      let addr2 = self.pop_addr()
      let reply = @host.host_strcmp(self.memory, self.mem_map, addr1, addr2)
      self.apply_reply(reply)
    }
    37 => {
      let ptr = self.pop_addr()
      let value = self.pop()
      let size = self.pop()
      let reply = @host.host_memset(self.mem_map, self.memory, ptr, value, size)
      self.apply_reply(reply)
    }
    39 => {
      let dest = self.pop_addr()
      let src = self.pop_addr()
      let reply = @host.host_strcat(
        self.mem_map,
        self.memory,
        dest,
        src,
        self.stack_buffer_spans(),
      )
      self.apply_reply(reply)
    }
    56 => {
      let dest = self.pop_addr()
      let src = self.pop_addr()
      let n = self.pop_i32()
      let reply = @host.host_strncpy(self.mem_map, self.memory, dest, src, n)
      self.apply_reply(reply)
    }
    57 => {
      let dest = self.pop_addr()
      let src = self.pop_addr()
      let n = self.pop_i32()
      let reply = @host.host_memcpy(self.mem_map, self.memory, dest, src, n)
      self.apply_reply(reply)
    }
    58 => {
      let dest = self.pop_addr()
      let src = self.pop_addr()
      let n = self.pop_i32()
      let reply = @host.host_memmove(self.mem_map, self.memory, dest, src, n)
      self.apply_reply(reply)
    }
    77 => {
      let src = self.pop_addr()
      let reply = @host.host_strdup(
        self.mem_map,
        self.memory,
        src,
        self.current_line,
      )
      self.apply_reply(reply)
    }
    90 => {
      let dest = self.pop_addr()
      let src = self.pop_addr()
      let n = self.pop()
      let reply = @host.host_strncat(self.mem_map, self.memory, dest, src, n)
      self.apply_reply(reply)
    }
    91 => {
      let addr1 = self.pop_addr()
      let addr2 = self.pop_addr()
      let n = self.pop()
      let reply = @host.host_strncmp(self.memory, self.mem_map, addr1, addr2, n)
      self.apply_reply(reply)
    }
    92 => {
      let addr1 = self.pop_addr()
      let addr2 = self.pop_addr()
      let n = self.pop()
      let reply = @host.host_memcmp(self.memory, self.mem_map, addr1, addr2, n)
      self.apply_reply(reply)
    }
    93 => {
      let addr = self.pop_addr()
      let c = self.pop_i32()
      let reply = @host.host_strchr(self.memory, self.mem_map, addr, c)
      self.apply_reply(reply)
    }
    94 => {
      let addr = self.pop_addr()
      let c = self.pop_i32()
      let reply = @host.host_strrchr(self.memory, self.mem_map, addr, c)
      self.apply_reply(reply)
    }
    95 => {
      let haystack = self.pop_addr()
      let needle = self.pop_addr()
      let reply = @host.host_strstr(self.memory, self.mem_map, haystack, needle)
      self.apply_reply(reply)
    }
    96 => {
      let addr = self.pop_addr()
      let c = self.pop_i32()
      let n = self.pop()
      let reply = @host.host_memchr(self.memory, self.mem_map, addr, c, n)
      self.apply_reply(reply)
    }
    128 => {
      let s1 = self.pop_addr()
      let s2 = self.pop_addr()
      let reply = @host.host_strpbrk(self.memory, self.mem_map, s1, s2)
      self.apply_reply(reply)
    }
    129 => {
      let s = self.pop_addr()
      let accept = self.pop_addr()
      let reply = @host.host_strspn(self.memory, self.mem_map, s, accept)
      self.apply_reply(reply)
    }
    130 => {
      let s = self.pop_addr()
      let reject = self.pop_addr()
      let reply = @host.host_strcspn(self.memory, self.mem_map, s, reject)
      self.apply_reply(reply)
    }
    // ── 转数值族 6（strtol/strtod 带 errno 义务③）──
    40 => {
      let addr = self.pop_addr()
      let reply = @host.host_atoi(self.memory, self.mem_map, addr)
      self.apply_reply(reply)
    }
    97 => {
      let addr = self.pop_addr()
      let reply = @host.host_atof(self.memory, self.mem_map, addr)
      self.apply_reply(reply)
    }
    98 => {
      let addr = self.pop_addr()
      let reply = @host.host_atol(self.memory, self.mem_map, addr)
      self.apply_reply(reply)
    }
    117 => {
      let str_addr = self.pop_addr()
      let endptr_addr = self.pop_addr()
      let base = self.pop_i32()
      let reply = @host.host_strtol(
        self.memory,
        self.mem_map,
        str_addr,
        endptr_addr,
        base,
        self.resolve_errno_addr(),
      )
      self.apply_reply(reply)
    }
    118 => {
      let str_addr = self.pop_addr()
      let endptr_addr = self.pop_addr()
      let reply = @host.host_strtod(
        self.memory,
        self.mem_map,
        str_addr,
        endptr_addr,
        self.resolve_errno_addr(),
      )
      self.apply_reply(reply)
    }
    119 => {
      let errnum = self.pop_i32()
      let reply = @host.host_strerror(
        self.mem_map,
        self.memory,
        errnum,
        self.current_line,
      )
      self.apply_reply(reply)
    }
    // ── VFS 族 17 ──
    60 => {
      let path = self.pop_addr()
      let mode = self.pop_addr()
      let reply = @host.host_fopen(
        self.mem_map,
        self.memory,
        self.vfs,
        path,
        mode,
        self.current_line,
      )
      self.apply_reply(reply)
    }
    61 => {
      let buf = self.pop_addr()
      let size = self.pop_i32()
      let nmemb = self.pop_i32()
      let stream = self.pop_addr()
      let reply = @host.host_fread(
        self.mem_map,
        self.memory,
        self.vfs,
        buf,
        size,
        nmemb,
        stream,
      )
      self.apply_reply(reply)
    }
    62 => {
      let buf = self.pop_addr()
      let size = self.pop_i32()
      let nmemb = self.pop_i32()
      let stream = self.pop_addr()
      let reply = @host.host_fwrite(
        self.mem_map,
        self.memory,
        self.vfs,
        buf,
        size,
        nmemb,
        stream,
      )
      self.apply_reply(reply)
    }
    63 => {
      let stream = self.pop_addr()
      let reply = @host.host_fclose(
        self.mem_map,
        self.memory,
        self.vfs,
        stream,
        self.current_line,
        self.step_count,
      )
      // fclose 无返回值语义差（Rust 返 0/EOF）——Reply 消费同款
      self.apply_reply(reply)
    }
    64 => {
      let stream = self.pop_addr()
      let reply = @host.host_feof(self.mem_map, self.memory, self.vfs, stream)
      self.apply_reply(reply)
    }
    65 => {
      let buf = self.pop_addr()
      let n = self.pop_i32()
      let stream = self.pop_addr()
      let reply = @host.host_fgets(
        self.mem_map,
        self.memory,
        self.vfs,
        buf,
        n,
        stream,
      )
      self.apply_reply(reply)
    }
    66 => {
      let s = self.pop_addr()
      let stream = self.pop_addr()
      let reply = @host.host_fputs(
        self.mem_map,
        self.memory,
        self.vfs,
        self.output,
        s,
        stream,
      )
      self.apply_reply(reply)
    }
    85 => {
      let stream = self.pop_addr()
      let reply = @host.host_fgetc(self.mem_map, self.memory, self.vfs, stream)
      self.apply_reply(reply)
    }
    86 => {
      let c = self.pop_i32()
      let stream = self.pop_addr()
      let reply = @host.host_fputc(
        self.mem_map,
        self.memory,
        self.vfs,
        c,
        stream,
      )
      self.apply_reply(reply)
    }
    87 => {
      let stream = self.pop_addr()
      let offset = self.pop_i32()
      let whence = self.pop_i32()
      let reply = @host.host_fseek(
        self.mem_map,
        self.memory,
        self.vfs,
        stream,
        offset,
        whence,
      )
      self.apply_reply(reply)
    }
    88 => {
      let stream = self.pop_addr()
      let reply = @host.host_ftell(self.mem_map, self.memory, self.vfs, stream)
      self.apply_reply(reply)
    }
    89 => {
      let stream = self.pop_addr()
      let reply = @host.host_rewind(self.mem_map, self.memory, self.vfs, stream)
      self.apply_reply(reply)
    }
    120 => {
      let stream = self.pop_addr()
      let reply = @host.host_fflush(self.mem_map, self.memory, self.vfs, stream)
      self.apply_reply(reply)
    }
    121 => {
      let s = self.pop_addr()
      let reply = @host.host_perror(self.mem_map, self.memory, self.output, s)
      self.apply_reply(reply)
    }
    122 => {
      let stream = self.pop_addr()
      let reply = @host.host_clearerr(
        self.mem_map,
        self.memory,
        self.vfs,
        stream,
      )
      self.apply_reply(reply)
    }
    126 => {
      let path = self.pop_addr()
      let reply = @host.host_remove(self.mem_map, self.memory, self.vfs, path)
      self.apply_reply(reply)
    }
    127 => {
      let old_path = self.pop_addr()
      let new_path = self.pop_addr()
      let reply = @host.host_rename(
        self.mem_map,
        self.memory,
        self.vfs,
        old_path,
        new_path,
      )
      self.apply_reply(reply)
    }
    // ── va_* 4（纯内存操作）──
    140 => {
      // 参数名照 oracle（misc.rs:566-575）：ap/last/last_size——六轮审阅
      // P3：位置与语义已对，改名消除读码歧义
      let ap_addr = self.pop_addr()
      let last_addr = self.pop_i32()
      let last_size = self.pop_i32()
      let reply = @host.host_va_start(
        self.memory,
        self.mem_map,
        ap_addr,
        last_addr,
        last_size,
      )
      self.apply_reply(reply)
    }
    141 => {
      let va_list = self.pop_addr()
      let ty_size = self.pop_i32()
      let reply = @host.host_va_arg(self.memory, self.mem_map, va_list, ty_size)
      self.apply_reply(reply)
    }
    142 => {
      let va_list = self.pop_addr()
      let reply = @host.host_va_end(va_list)
      self.apply_reply(reply)
    }
    143 => {
      let dst = self.pop_addr()
      let src = self.pop_addr()
      let reply = @host.host_va_copy(self.memory, self.mem_map, dst, src)
      self.apply_reply(reply)
    }
    _ => self.execute_host_func3(id, line, column)
  }
}
