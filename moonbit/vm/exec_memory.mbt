///| L7 执行层·VM 域·executor：**内存族**（Rust `executor/memory.rs` 的
/// execute_memory 段照搬）。
///
/// 弹参序（对拍契约，勿改）：LoadMem 弹地址；StoreMem 先弹值再弹地址；
/// Memcpy 弹 dest/src/n；Memset 弹 ptr/value/size。检查失败仍把指针压回
/// （保持栈形态——Rust 同款）。

///|
/// 值栈弹出一个 u32 地址（截断到 32 位——Rust `pop() as u32`）。
fn VitroVM::pop_addr(self : VitroVM) -> UInt {
  self.pop().to_uint()
}

///|
/// 值栈弹出一个 i32（低 32 位符号解释）。
fn VitroVM::pop_i32(self : VitroVM) -> Int {
  self.pop().to_int()
}

///|
/// 值栈弹出一个 i64（位重解释）。
fn VitroVM::pop_i64(self : VitroVM) -> Int64 {
  self.pop().reinterpret_as_int64()
}

///|
fn VitroVM::execute_memory(
  self : VitroVM,
  op : @opcode.OpCode,
  _operand : Int,
  line : Int,
  column : Int,
) -> Unit {
  match op {
    LoadMem => {
      let addr = self.pop_addr()
      let val = self.vm_load_u32(addr, line, column)
      self.push(val.to_uint64())
    }
    StoreMem => {
      let val = self.pop_i32()
      let addr = self.pop_addr()
      self.vm_store_u32(addr, val.reinterpret_as_uint(), line, column)
    }
    LoadMemD | LoadMemQ => {
      let addr = self.pop_addr()
      let val = self.vm_load_u64(addr, line, column)
      self.push(val)
    }
    StoreMemD | StoreMemQ => {
      let val = self.pop()
      let addr = self.pop_addr()
      self.vm_store_u64(addr, val, line, column)
    }
    LoadMemByte => {
      let addr = self.pop_addr()
      let val = self.vm_load_i8(addr, line, column)
      self.push(val.reinterpret_as_uint().to_uint64())
    }
    StoreMemByte => {
      let val = self.pop_i32()
      let addr = self.pop_addr()
      self.vm_store_i8(addr, val, line, column)
    }
    SplitD | SplitQ => {
      let val = self.pop()
      let low = val.to_uint()
      let high = (val >> 32).to_uint()
      self.push(low.to_uint64())
      self.push(high.to_uint64())
    }
    StackAlloc => {
      let size = self.pop_i32()
      if size < 0 {
        self.trap("StackAlloc: 分配的栈空间大小为负数", line, column)
        return
      }
      let aligned_size = ((size + 3) & -4).reinterpret_as_uint()
      if aligned_size > self.mem_stack_top {
        self.trap("StackAlloc: 栈溢出", line, column)
        return
      }
      if self.mem_stack_top - aligned_size < @bytecode.NULL_TRAP_SIZE {
        self.trap("StackAlloc: 栈溢出（触及保留区）", line, column)
        return
      }
      self.mem_stack_top = self.mem_stack_top - aligned_size
      self.push(self.mem_stack_top.to_uint64())
    }
    Memcpy => {
      let dest = self.pop_addr()
      let src = self.pop_addr()
      let n = self.pop_i32()
      let n_u32 = n.reinterpret_as_uint()
      // 检查失败（NULL/上界/UAF 已渲染）仍压回 dest 保持栈形态。
      match self.mem_map.check_access(dest, n_u32, Write) {
        Err(f) => {
          self.render_mem_fault(f, line, column)
          self.push(dest.to_uint64())
          return
        }
        Ok(_) => ()
      }
      match self.mem_map.check_access(src, n_u32, Read) {
        Err(f) => {
          self.render_mem_fault(f, line, column)
          self.push(dest.to_uint64())
          return
        }
        Ok(_) => ()
      }
      // 段级受检 copy（重叠安全：memory.copy 走临时缓冲的 memmove 语义）。
      // n 的软截断照搬（copy_len = min(n, 余量)）——但上界已在 check 拦截，
      // 实际不会触达；保守保留 Result 通道。
      match self.memory.copy(self.mem_map, dest, src, n) {
        Ok(_) => ()
        Err(f) => self.render_mem_fault(f, line, column)
      }
      self.push(dest.to_uint64())
    }
    Memset => {
      let ptr = self.pop_addr()
      let value = self.pop()
      let size = self.pop_i32()
      let size_u32 = size.reinterpret_as_uint()
      match self.mem_map.check_access(ptr, size_u32, Write) {
        Err(f) => {
          self.render_mem_fault(f, line, column)
          self.push(ptr.to_uint64())
          return
        }
        Ok(_) => ()
      }
      let byte_val = (value & 0xFFUL).to_uint().to_byte()
      match self.memory.fill(self.mem_map, ptr, size, byte_val) {
        Ok(_) => ()
        Err(f) => self.render_mem_fault(f, line, column)
      }
      self.push(ptr.to_uint64())
    }
    Strlen =>
      // 零发射死码（总计划 §5 亲证；codegen 从不发射——strlen 走固定索引
      // 1015）。到达即产物契约破坏，fail loud 不静默。
      self.trap(
        "Strlen: 零发射死码被执行——字节码产物契约破坏（strlen 应走 Bytecode Libc 固定索引）",
        line, column,
      )
    _ => ()
  }
}
