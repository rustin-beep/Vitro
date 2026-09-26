///| L7 执行层·VM 域·executor：**CallHost 分发三段**（printf/scanf/字符 IO
/// 族 10 + qsort/bsearch + guards×2/STEP——批三号第三段收官，CallHost
/// 110 臂全接线）。
///
/// **`call_user_function`**（qsort/bsearch 比较器的机制底座，照搬 Rust
/// `state.rs:384-509`）：完整状态保存/恢复（ip/call_stack/栈顶/值栈/
/// error/finished/step_event_hit/current_line/vis_event_queue/breakpoints）
/// + U2#13 参数形状教学诊断（非 4 字节参数 trap+None）+ **哨兵帧**
/// （`return_ip : None`——批二段二的 Ret 哨兵分支对接）+ 逐 step 执行至
/// Finished（max_steps 预算）/Trap/WaitingInput。
///
/// **scanf/getchar 的 Batch/Interactive 双模式**：Batch（判分）输入耗尽
/// 即 EOF 粘滞（`InputState::set_eof`——批三号三段上提 pub）；Interactive
/// 置 `waiting_input` + **参数回推**（ip 回退由 CallHost 臂统一处理）。

///|
/// 受检 C 字符串读（vm 侧单点——host 包 read_cstring 是包私有；同算法
/// 直用 memory 单入口，NUL 直抵内存尾时最后一次越界读自然 fault）。
fn VitroVM::read_cstring_checked(
  self : VitroVM,
  addr : UInt,
) -> Result[Bytes, @memory.MemFault] {
  let buf : Array[Byte] = []
  let mut i = 0
  while true {
    match self.memory.load_i8(self.mem_map, addr + i.reinterpret_as_uint()) {
      Ok(b) => {
        if b == 0 {
          return Ok(Bytes::from_array(buf))
        }
        buf.push(b.to_byte())
        i = i + 1
      }
      Err(f) => return Err(f)
    }
  }
  Ok(Bytes::from_array(buf))
}

///|
/// 逐字节 lossy 展开（格式解析的码元序列；与 host 包 lossy_codes 同口径
/// ——String 码元直转 Int）。
fn codes_of(bytes : Bytes) -> Array[Int] {
  let out : Array[Int] = []
  for i = 0; i < bytes.length(); i = i + 1 {
    out.push(bytes[i].to_int())
  }
  out
}

///|
fn concat_shapes(arr : Array[String]) -> String {
  let mut out = ""
  for i, x in arr {
    if i > 0 {
      out = out + ", "
    }
    out = out + x
  }
  out
}

///|
/// 比较器执行（`call_user_function`；返回 None = 函数未知/形状违约 trap/
/// trap/步数超限——qsort/bsearch 按「比较失败 = 相等」处理，照搬 oracle）。
fn VitroVM::call_user_function(
  self : VitroVM,
  func_idx : Int,
  args : Array[Int],
  max_steps : Int,
) -> Int? {
  let meta = match self.func_table.get(func_idx) {
    Some(Some(m)) => m
    _ => return None
  }
  if meta.ip == 0 {
    return None
  }
  // U2#13：非 4 字节参数教学诊断（状态保存**之前**——零状态污染）
  for sz in meta.param_sizes {
    if sz != 1 {
      let shapes : Array[String] = []
      for s in meta.param_sizes {
        shapes.push(s.to_string())
      }
      self.trap(
        "比较函数的参数必须是 4 字节指针（当前参数形状 [" +
        concat_shapes(shapes) +
        "]）：qsort/bsearch 的比较函数签名应为 int (*)(const void*, const void*)。",
        0,
        0,
      )
      return None
    }
  }
  let frame_size = meta.local_count.reinterpret_as_uint()
  if frame_size > self.mem_stack_top ||
    self.mem_stack_top < @bytecode.NULL_TRAP_SIZE + frame_size {
    return None
  }
  // ── 状态保存（11 件套照搬）──
  let saved_ip = self.ip
  let saved_call_stack : Array[CallFrame] = []
  for f in self.call_stack {
    let buffers : Array[@bytecode.LocalBuffer] = []
    for b in f.local_buffers {
      buffers.push(@bytecode.LocalBuffer::{
        offset: b.offset,
        size: b.size,
        name: b.name,
      })
    }
    saved_call_stack.push(CallFrame::{
      return_ip: f.return_ip,
      locals_base: f.locals_base,
      local_count: f.local_count,
      func_name: f.func_name,
      original_stack_top: f.original_stack_top,
      caller_line: f.caller_line,
      local_buffers: buffers,
    })
  }
  let saved_mem_stack_top = self.mem_stack_top
  let saved_stack : Array[UInt64] = []
  for v in self.stack {
    saved_stack.push(v)
  }
  let saved_error = self.error
  let saved_finished = self.finished
  let saved_step_event_hit = self.step_event_hit
  let saved_current_line = self.current_line
  let saved_vis : Array[VisEventData] = []
  for e in self.vis_event_queue {
    saved_vis.push(e)
  }
  let saved_bps : Array[Int] = []
  for bp in self.breakpoints {
    saved_bps.push(bp)
  }
  let start_step = self.step_count
  // ── 建帧（哨兵 return_ip = None）──
  let original_stack_top = self.mem_stack_top
  self.mem_stack_top = self.mem_stack_top - frame_size
  let locals_base = self.mem_stack_top
  // args[0] = 首参数 → locals_base + 0（VM Call 约定）
  for i = 0; i < meta.param_count; i = i + 1 {
    let arg = if i < args.length() { args[i] } else { 0 }
    self.vm_store_u32(
      locals_base + i.reinterpret_as_uint() * 4U,
      arg.reinterpret_as_uint(),
      0,
      0,
    )
  }
  let arg_bytes = meta.param_count.reinterpret_as_uint() * 4U
  let mut za = locals_base + arg_bytes
  let zero_end = locals_base + meta.local_count.reinterpret_as_uint()
  while za < zero_end {
    self.vm_store_i8(za, 0, 0, 0)
    za = za + 1U
  }
  let buffers : Array[@bytecode.LocalBuffer] = []
  for b in meta.local_buffers {
    buffers.push(@bytecode.LocalBuffer::{
      offset: b.offset,
      size: b.size,
      name: b.name,
    })
  }
  self.call_stack.push(CallFrame::{
    return_ip: None, // 宿主回调哨兵
    locals_base,
    local_count: meta.local_count,
    func_name: match self.func_names.get(func_idx) {
      Some(Some(n)) => n
      _ => "func_" + func_idx.to_string()
    },
    original_stack_top,
    caller_line: self.current_line,
    local_buffers: buffers,
  })
  self.ip = meta.ip
  // ── 逐 step 执行至收尾 ──
  let mut result : Int? = None
  while true {
    if self.step_count - start_step >= max_steps {
      break
    }
    match self.step() {
      Finished => {
        match self.stack.pop() {
          Some(v) => result = Some(v.to_uint().reinterpret_as_int())
          None => result = None
        }
        break
      }
      Trap => break // result 保持 None
      Paused => self.paused = false
      WaitingInput => break
      Ok => continue
    }
  }
  // ── 状态恢复 ──
  self.ip = saved_ip
  self.call_stack.clear()
  for f in saved_call_stack {
    self.call_stack.push(f)
  }
  self.mem_stack_top = saved_mem_stack_top
  self.stack.clear()
  for v in saved_stack {
    self.stack.push(v)
  }
  self.error = saved_error
  self.finished = saved_finished
  self.step_event_hit = saved_step_event_hit
  self.current_line = saved_current_line
  self.vis_event_queue.clear()
  for e in saved_vis {
    self.vis_event_queue.push(e)
  }
  self.breakpoints.clear()
  for bp in saved_bps {
    self.breakpoints.add(bp)
  }
  result
}

///|
/// qsort 深度上限（照搬 Rust MAX_QSORT_DEPTH；递归比较器防护）。
const MAX_QSORT_DEPTH : Int = 64

///|
/// 比较步数预算（单次 sort 内 call_user_function 总步数上限——照搬
/// Rust MAX_COMPARE_STEPS）。
const MAX_COMPARE_STEPS : Int = 1000

///|
/// 受检段读（临时缓冲——qsort 重排的搬运前置）。
fn VitroVM::read_block(self : VitroVM, addr : UInt, len : Int) -> Array[Byte]? {
  match self.mem_map.check_access(addr, len.reinterpret_as_uint(), Read) {
    Err(_) => return None
    Ok(_) => ()
  }
  let out : Array[Byte] = Array(capacity=len)
  for i = 0; i < len; i = i + 1 {
    match self.memory.load_i8(self.mem_map, addr + i.reinterpret_as_uint()) {
      Ok(b) => out.push(b.to_byte())
      Err(_) => return None
    }
  }
  Some(out)
}

///|
/// 受检段写（qsort 写回）。
fn VitroVM::write_block(
  self : VitroVM,
  addr : UInt,
  data : Array[Byte],
) -> Bool {
  match self.memory.write_bytes(self.mem_map, addr, Bytes::from_array(data)) {
    Ok(_) => true
    Err(_) => false
  }
}

///|
/// 三段分发主体（id 与 Rust host_func_id 常量对齐）。
fn VitroVM::execute_host_func3(
  self : VitroVM,
  id : Int,
  line : Int,
  column : Int,
) -> Unit {
  match id {
    // ── printf/scanf 族 ──
    15 => {
      // printf(fmt, ...)：弹 fmt → 数转换符 → 按数弹参数组
      let fmt_addr = self.pop_addr()
      let fmt = match self.read_cstring_checked(fmt_addr) {
        Ok(b) => b
        Err(f) => {
          self.render_mem_fault(f, 0, 0)
          return
        }
      }
      let specs = @host.format_spec_kinds(codes_of(fmt))
      let args : Array[UInt64] = []
      for i = 0; i < specs.length(); i = i + 1 {
        args.push(self.pop())
      }
      let reply = @host.host_printf_n(
        self.mem_map,
        self.memory,
        self.output,
        fmt_addr,
        args,
      )
      self.apply_reply(reply)
    }
    50 => {
      // fprintf：弹 stream → fmt → 参数组（stderr 分流在 host 层）
      let stream = self.pop_addr()
      let fmt_addr = self.pop_addr()
      let fmt = match self.read_cstring_checked(fmt_addr) {
        Ok(b) => b
        Err(f) => {
          self.render_mem_fault(f, 0, 0)
          return
        }
      }
      let specs = @host.format_spec_kinds(codes_of(fmt))
      let args : Array[UInt64] = []
      for i = 0; i < specs.length(); i = i + 1 {
        args.push(self.pop())
      }
      let reply = @host.host_fprintf_n(
        self.mem_map,
        self.memory,
        self.output,
        stream.to_uint64(),
        fmt_addr,
        args,
      )
      self.apply_reply(reply)
    }
    21 => {
      // scanf(fmt, ...)：弹 fmt → 数指针参 → 弹指针组；双模式 EOF/等待
      let fmt_addr = self.pop_addr()
      let fmt = match self.read_cstring_checked(fmt_addr) {
        Ok(b) => b
        Err(f) => {
          self.render_mem_fault(f, 0, 0)
          return
        }
      }
      let arg_count = @host.scanf_spec_count(codes_of(fmt))
      if self.stack.length() < arg_count {
        self.trap(
          "scanf: 格式字符串要求的参数多于实际提供的参数。",
          0, 0,
        )
        return
      }
      let ptrs : Array[UInt] = []
      for i = 0; i < arg_count; i = i + 1 {
        ptrs.push(self.pop_addr())
      }
      match
        @host.host_scanf_n(
          self.mem_map,
          self.memory,
          self.input,
          self.stack_buffer_spans(),
          fmt_addr,
          ptrs,
        ) {
        Value(v) => self.push(v)
        Trap(msg) => self.trap(msg, 0, 0)
        Waiting => {
          // 参数回推（逆序恢复原栈序）+ fmt 回推——ip 回退由 CallHost 臂统一
          for i = ptrs.length() - 1; i >= 0; i = i - 1 {
            self.push(ptrs[i].to_uint64())
          }
          self.push(fmt_addr.to_uint64())
          self.waiting_input = true
        }
      }
    }
    84 => {
      // sscanf：弹 src → fmt → 指针组（无守卫——坑 17 照搬）
      let src = self.pop_addr()
      let fmt_addr = self.pop_addr()
      let fmt = match self.read_cstring_checked(fmt_addr) {
        Ok(b) => b
        Err(f) => {
          self.render_mem_fault(f, 0, 0)
          return
        }
      }
      let arg_count = @host.scanf_spec_count(codes_of(fmt))
      let ptrs : Array[UInt] = []
      for i = 0; i < arg_count; i = i + 1 {
        ptrs.push(self.pop_addr())
      }
      let reply = @host.host_sscanf(
        self.mem_map,
        self.memory,
        src,
        fmt_addr,
        ptrs,
      )
      self.apply_reply(reply)
    }
    82 => {
      // sprintf：弹 buf → fmt → 参数组
      let buf = self.pop_addr()
      let fmt_addr = self.pop_addr()
      let fmt = match self.read_cstring_checked(fmt_addr) {
        Ok(b) => b
        Err(f) => {
          self.render_mem_fault(f, 0, 0)
          return
        }
      }
      let specs = @host.format_spec_kinds(codes_of(fmt))
      let args : Array[UInt64] = []
      for i = 0; i < specs.length(); i = i + 1 {
        args.push(self.pop())
      }
      let reply = @host.host_sprintf(
        self.mem_map,
        self.memory,
        buf,
        fmt_addr,
        args,
      )
      self.apply_reply(reply)
    }
    83 => {
      // snprintf：弹 buf → size → fmt → 参数组
      let buf = self.pop_addr()
      let size = self.pop().to_uint().reinterpret_as_int()
      let fmt_addr = self.pop_addr()
      let fmt = match self.read_cstring_checked(fmt_addr) {
        Ok(b) => b
        Err(f) => {
          self.render_mem_fault(f, 0, 0)
          return
        }
      }
      let specs = @host.format_spec_kinds(codes_of(fmt))
      let args : Array[UInt64] = []
      for i = 0; i < specs.length(); i = i + 1 {
        args.push(self.pop())
      }
      let reply = @host.host_snprintf(
        self.mem_map,
        self.memory,
        buf,
        size,
        fmt_addr,
        args,
      )
      self.apply_reply(reply)
    }
    33 =>
      // getchar：ungetc 缓存 / EOF 粘滞 / Batch-Interactive 三分支
      match @host.host_getchar(self.input) {
        Value(v) => self.push(v)
        Trap(msg) => self.trap(msg, 0, 0)
        Waiting =>
          if self.input.eof {
            // EOF 粘滞 + Interactive → 等输入（Batch 由 host 侧直返 -1）
            self.waiting_input = true
          } else {
            self.waiting_input = true
          }
      }
    78 => {
      // ungetc(c, stream)：Rust 弹 ch 再弹 stream（stream 忽略）
      let ch = self.pop().to_uint().reinterpret_as_int()
      let _stream = self.pop_addr()
      self.push(@host.host_ungetc(self.input, ch))
    }
    79 => {
      // puts(s)：输出 + 换行，返 1
      let s_addr = self.pop_addr()
      match self.read_cstring_checked(s_addr) {
        Ok(bytes) => {
          let mut text = lossy_string(bytes)
          text = text + "\n"
          self.output.push_stdout(@utf8.encode(text))
          self.push(1UL)
        }
        Err(f) => self.render_mem_fault(f, 0, 0)
      }
    }
    // ── qsort / bsearch ──
    52 => {
      let base = self.pop_addr()
      let nmemb = self.pop()
      let size = self.pop()
      let compar = self.pop_addr()
      self.host_qsort(base, nmemb, size, compar)
    }
    81 => {
      let key = self.pop_addr()
      let base = self.pop_addr()
      let nmemb = self.pop()
      let size = self.pop()
      let compar = self.pop_addr()
      self.host_bsearch(key, base, nmemb, size, compar)
    }
    // ── guards×2（C++ new[] 守卫——C 前端零发射死面，保留对称）──
    131 => {
      // set_array_guard：pop base_addr（本实现无 C++ 守卫机制——直通）
      let _base = self.pop_addr()
    }
    132 =>
      // clear_array_guard：无参直通（C++ 守卫死面）
      ignore(id)
    // ── STEP（教学 trace——trace 通道死路径不搬，只更新 current_line）──
    1 => {
      let l = self.pop().to_uint().reinterpret_as_int()
      self.current_line = l
    }
    _ =>
      self.trap(
        "CallHost 未知 id=" +
        id.to_string() +
        "（110 路由外——产物契约破坏）",
        0,
        0,
      )
  }
  ignore(line)
  ignore(column)
}

///|
/// Bytes → String（lossy：非 UTF-8 序列按码元直转——puts 的输出文本口径）。
fn lossy_string(bytes : Bytes) -> String {
  let codes : Array[Int] = []
  for i = 0; i < bytes.length(); i = i + 1 {
    codes.push(bytes[i].to_int())
  }
  String::from_array(codes.map(fn(c) { c.unsafe_to_char() }))
}

///|
/// qsort（照搬 Rust `host/misc.rs:153-231`：深度限 / 平凡短路 / 尺寸链
/// checked / 默认字节比较 / 比较器经 call_user_function / 临时缓冲重排）。
fn VitroVM::host_qsort(
  self : VitroVM,
  base : UInt,
  nmemb : UInt64,
  size : UInt64,
  compar : UInt,
) -> Unit {
  if self.qsort_depth >= MAX_QSORT_DEPTH {
    self.output.push_note_str(
      "[qsort] 嵌套深度超过限制，防止栈溢出",
    )
    return
  }
  if nmemb <= 1UL || size == 0UL || base == 0U {
    return
  }
  // 尺寸链 checked（坑 9：2^32×2^32 回绕绕过检查 → OOM）
  let total = nmemb.reinterpret_as_int64() * size.reinterpret_as_int64()
  if total <= 0L || base.to_int64() + total > @bytecode.MEM_SIZE.to_int64() {
    return
  }
  let n = nmemb.to_uint().reinterpret_as_int()
  let sz = size.to_uint().reinterpret_as_int()
  self.qsort_depth = self.qsort_depth + 1
  let indices : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    indices.push(i)
  }
  if compar == 0U {
    // 默认：字节序列比较（无比较器）
    let blocks : Array[Array[Byte]?] = []
    for i = 0; i < n; i = i + 1 {
      blocks.push(
        self.read_block(
          base + i.reinterpret_as_uint() * sz.reinterpret_as_uint(),
          sz,
        ),
      )
    }
    indices.sort_by(fn(a, b) {
      match (blocks[a], blocks[b]) {
        (Some(x), Some(y)) => block_cmp(x, y)
        _ => 0
      }
    })
  } else {
    indices.sort_by(fn(a, b) {
      let addr_a = base.to_int() + a * sz
      let addr_b = base.to_int() + b * sz
      match
        self.call_user_function(
          compar.reinterpret_as_int(),
          [addr_a, addr_b],
          MAX_COMPARE_STEPS,
        ) {
        Some(v) => v
        None => 0
      }
    })
  }
  // 重排（临时缓冲）
  let temp : Array[Byte] = Array(capacity=n * sz)
  for new_pos in 0..<n {
    let old_idx = indices[new_pos]
    match
      self.read_block(
        base + old_idx.reinterpret_as_uint() * sz.reinterpret_as_uint(),
        sz,
      ) {
      Some(blk) =>
        for b in blk {
          temp.push(b)
        }
      None => {
        self.qsort_depth = self.qsort_depth - 1
        return
      }
    }
  }
  if !self.write_block(base, temp) {
    self.trap("qsort: write back out of bounds", 0, 0)
  }
  self.qsort_depth = self.qsort_depth - 1
}

///|
/// bsearch（照搬 Rust `host/misc.rs:234-330`：二分 + 比较器经
/// call_user_function；命中返回元素地址，未命中 NULL）。
fn VitroVM::host_bsearch(
  self : VitroVM,
  key : UInt,
  base : UInt,
  nmemb : UInt64,
  size : UInt64,
  compar : UInt,
) -> Unit {
  if nmemb == 0UL || size == 0UL || base == 0U || key == 0U {
    self.push(0UL)
    return
  }
  let total = nmemb.reinterpret_as_int64() * size.reinterpret_as_int64()
  if total <= 0L || base.to_int64() + total > @bytecode.MEM_SIZE.to_int64() {
    self.push(0UL)
    return
  }
  let n = nmemb.to_uint().reinterpret_as_int()
  let sz = size.to_uint().reinterpret_as_int()
  let mut lo = 0
  let mut hi = n
  let mut found : Int? = None
  while lo < hi {
    let mid = (lo + hi) / 2
    let addr = base.to_int() + mid * sz
    match
      self.call_user_function(
        compar.reinterpret_as_int(),
        [key.to_int(), addr],
        MAX_COMPARE_STEPS,
      ) {
      Some(v) =>
        if v < 0 {
          hi = mid
        } else if v > 0 {
          lo = mid + 1
        } else {
          found = Some(mid)
          break
        }
      None => break
    }
  }
  match found {
    Some(idx) =>
      self.push((base.to_int() + idx * sz).reinterpret_as_uint().to_uint64())
    None => self.push(0UL)
  }
}

///|
/// 字节序列比较（qsort 默认比较器；字典序逐字节）。
fn block_cmp(a : Array[Byte], b : Array[Byte]) -> Int {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i = 0; i < n; i = i + 1 {
    let x = a[i].to_int()
    let y = b[i].to_int()
    if x != y {
      return if x < y { -1 } else { 1 }
    }
  }
  if a.length() < b.length() {
    return -1
  } else if a.length() > b.length() {
    return 1
  }
  0
}
