///| L7 执行层·VM 域·executor：**CallHost 分发**（批三号第一段）。
///
/// Rust `execute_host_func`（`host_funcs.rs:33-147`）每 handler 自管弹参；
/// MoonBit host 包 handler 是**纯函数形态**（Memory/MemoryMap/OutputLog 参数
/// 进出、不碰值栈）——本层每臂协议 = **弹参（按 oracle 弹参序）→ 调
/// handler → 消费 `HostMemReply` 三态 / 压返回值**。
///
/// **弹参序契约（勿改——对拍面）**：pow 先弹 x、atan2 先弹 y（oracle 弹参
/// 序不一致，S6 批一号登记的接线义务①）；calloc 先弹 size 后弹 nmemb；
/// realloc 先弹 ptr；free 弹单地址。
///
/// **本段范围**（46 臂）：ctype 14 + math 22 + 内存族 4 + exit 族 4
/// （exit/abort/assert_fail/unreachable）+ rand/srand + abs/llabs +
/// time/clock + putchar/puts/OUTPUT。其余臂（printf/scanf/字符串/转数值/
/// VFS/va_*/qsort/bsearch/guards/STEP）fail loud 待批三号第二段。
///
/// **time/clock 的非确定性通道登记**：`now_millis` 传 0（deterministic
/// 模式恒 0——与 Rust「完整 step 派生伪时钟留 Phase 3」同口径；真实时钟
/// 属 session 层职责，wasm-gc 无熵源 F5/R12）。

///|
/// `HostMemReply` 三态消费单点：trap → 首错写入（带行号）；note → 输出
/// 附注通道；value → 压栈（None 压 0——分配失败返回 NULL 的 C 语义）。
fn VitroVM::apply_reply(
  self : VitroVM,
  reply : @host.HostMemReply,
  line : Int,
  column : Int,
) -> Unit {
  match reply.trap {
    Some(msg) => self.trap(msg, line, column)
    None => ()
  }
  match reply.note {
    Some(n) => self.output.push_note_str(n)
    None => ()
  }
  self.push(
    match reply.value {
      Some(v) => v
      None => 0UL
    },
  )
}

///|
/// CallHost 分发主体。`id` 是 bytecode 路由表单源派生的 host id
/// （`CallRoute::Host(id)`——codegen 发射侧已按名定轨）。
fn VitroVM::execute_host_func(
  self : VitroVM,
  id : Int,
  line : Int,
  column : Int,
) -> Unit {
  match id {
    // ── ctype 14（纯函数：pop int → push int）──
    42 => self.push_i32(@host.host_isdigit(self.pop_i32()))
    43 => self.push_i32(@host.host_isalpha(self.pop_i32()))
    44 => self.push_i32(@host.host_islower(self.pop_i32()))
    45 => self.push_i32(@host.host_isupper(self.pop_i32()))
    46 => self.push_i32(@host.host_tolower(self.pop_i32()))
    47 => self.push_i32(@host.host_toupper(self.pop_i32()))
    48 => self.push_i32(@host.host_isspace(self.pop_i32()))
    49 => self.push_i32(@host.host_isalnum(self.pop_i32()))
    53 => self.push_i32(@host.host_isprint(self.pop_i32()))
    54 => self.push_i32(@host.host_iscntrl(self.pop_i32()))
    55 => self.push_i32(@host.host_isxdigit(self.pop_i32()))
    106 => self.push_i32(@host.host_isgraph(self.pop_i32()))
    107 => self.push_i32(@host.host_ispunct(self.pop_i32()))
    108 => self.push_i32(@host.host_isblank(self.pop_i32()))
    // ── math 22（f64 位模式进出：pop u64 位 → handler → push u64 位）──
    70 => self.push(@host.host_sin(self.pop()))
    71 => self.push(@host.host_cos(self.pop()))
    72 => self.push(@host.host_sqrt(self.pop()))
    73 => {
      // pow：先弹 x 后弹 y（oracle 弹参序——义务①）
      let x = self.pop()
      let y = self.pop()
      self.push(@host.host_pow(x, y))
    }
    74 => self.push(@host.host_atan(self.pop()))
    75 => self.push(@host.host_log(self.pop()))
    76 => self.push(@host.host_exp(self.pop()))
    99 => self.push(@host.host_tan(self.pop()))
    100 => self.push(@host.host_log10(self.pop()))
    101 => self.push(@host.host_fabs(self.pop()))
    102 => self.push(@host.host_ceil(self.pop()))
    103 => self.push(@host.host_floor(self.pop()))
    104 => self.push(@host.host_round(self.pop()))
    105 => {
      let y = self.pop()
      let x = self.pop()
      self.push(@host.host_fmod(x, y))
    }
    109 => self.push(@host.host_asin(self.pop()))
    110 => self.push(@host.host_acos(self.pop()))
    111 => {
      // atan2：先弹 y 后弹 x（oracle 弹参序——义务①）
      let y = self.pop()
      let x = self.pop()
      self.push(@host.host_atan2(y, x))
    }
    112 => self.push(@host.host_sinh(self.pop()))
    113 => self.push(@host.host_cosh(self.pop()))
    114 => self.push(@host.host_tanh(self.pop()))
    // ── 内存族 4（HostMemReply 三态）──
    2 => {
      let size = self.pop_i32()
      let reply = @host.host_malloc(self.mem_map, size, self.current_line)
      self.apply_reply(reply, line, column)
    }
    3 => {
      let addr = self.pop_addr()
      let reply = @host.host_free(
        self.mem_map,
        addr,
        self.current_line,
        self.step_count,
      )
      // free 无返回值（C void）——Reply 只消费 trap/note
      match reply.trap {
        Some(msg) => self.trap(msg, line, column)
        None => ()
      }
      match reply.note {
        Some(n) => self.output.push_note_str(n)
        None => ()
      }
    }
    80 => {
      // calloc：先弹 size 后弹 nmemb（Rust host/memory.rs:314-315 弹序）
      let size = self.pop_i32()
      let nmemb = self.pop_i32()
      let reply = @host.host_calloc(
        self.mem_map,
        self.memory,
        nmemb,
        size,
        self.current_line,
      )
      self.apply_reply(reply, line, column)
    }
    51 => {
      let ptr = self.pop_addr()
      let new_size = self.pop_i32()
      let reply = @host.host_realloc(
        self.mem_map,
        self.memory,
        ptr,
        new_size,
        self.current_line,
        self.current_line,
        self.step_count,
      )
      self.apply_reply(reply, line, column)
    }
    // ── exit 族 4 ──
    38 => {
      // exit(code)：set_finished（Rust state.rs:601-604 两字段形态）
      let code = self.pop_i32()
      self.finished = true
      self.exit_code = code
    }
    116 => {
      // abort：note + set_finished(134)（SIGABRT）
      self.output.push_note_str("[abort] 程序异常终止 (SIGABRT)")
      self.finished = true
      self.exit_code = 134
    }
    125 => {
      // assert_fail：note + set_finished(1)
      self.output.push_note_str("🚫 断言失败 (assertion failed)")
      self.finished = true
      self.exit_code = 1
    }
    144 =>
      // unreachable：教学 trap（文案 host 单源）
      self.trap(@host.host_unreachable(), line, column)
    // ── rand/srand（LCG 状态在 vm）──
    35 => self.push_i32(@host.host_rand(self.rand))
    36 => @host.host_srand(self.rand, self.pop().to_uint())
    // ── abs/llabs ──
    41 => {
      let n = self.pop_i32()
      self.push(@host.host_abs(n))
    }
    115 => {
      let n = self.pop_i64()
      self.push(@host.host_llabs(n))
    }
    // ── time/clock（deterministic 恒 0；非确定性时钟留 session 层）──
    123 => {
      let _tloc = self.pop_addr()
      self.push(@host.host_time(self.deterministic, 0UL))
    }
    124 => self.push(@host.host_clock(self.deterministic, 0UL))
    // ── 输出族 ──
    0 => {
      // __vitro_output：值 + 换行（Rust push_stdout(format!("{}\n", val))）
      let val = self.pop()
      let text = val.to_string() + "\n"
      self.output.push_stdout(@utf8.encode(text))
    }
    34 =>
      // putchar(c)
      @host.host_putchar(self.output, self.pop())
    _ =>
      self.trap(
        "执行器批三号第二段待接线：CallHost id=\{id}（host 侧实现已就绪，弹参协议随第二段落）",
        line,
        column,
      )
  }
}
