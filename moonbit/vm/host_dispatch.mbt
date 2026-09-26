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
/// **本段范围**（50 臂）：ctype 14 + math 20 + 内存族 4 + exit 族 4
/// （exit/abort/assert_fail/unreachable）+ rand/srand + abs/llabs +
/// time/clock + putchar/puts/OUTPUT。其余臂（printf/scanf/字符串/转数值/
/// VFS/va_*/qsort/bsearch/guards/STEP）fail loud 待批三号第二段。
/// **遮蔽死面登记（14 臂，三轮审阅 P2-2）**：ctype 11（isdigit…isxdigit）
/// + abs + rand + srand——这 14 个名字被 codegen 的 Bytecode Libc 全量
/// 预注册遮蔽（`Call 1000+idx` 先于 `CallHost`，bytecode/route.mbt 遮蔽
/// 集显式清单），按名调用**不可达**；实现保留与 oracle 对称（oracle 的
/// 同名 host handler 同为死面），遮蔽集变更时无需重写。活的 ctype 3：
/// isgraph/ispunct/isblank。
///
/// **time/clock 的非确定性通道登记**：`now_millis` 传 0（deterministic
/// 模式恒 0——与 Rust「完整 step 派生伪时钟留 Phase 3」同口径；真实时钟
/// 属 session 层职责，wasm-gc 无熵源 F5/R12）。

///|
/// `HostMemReply` 三态消费单点：trap → 首错写入（空 loc 回退
/// current_line——host 层 trap 全族对齐 oracle 的 default loc）；note →
/// 输出附注通道（heap_exhausted 去重）；value → 压栈（None 压 0——分配
/// 失败返回 NULL 的 C 语义）。
fn VitroVM::apply_reply(self : VitroVM, reply : @host.HostMemReply) -> Unit {
  match reply.trap {
    // host 层 trap 传空 loc 对齐 oracle（execute_host_func 全族
    // SourceLoc::default() → trap() 回退 current_line——三轮审阅 P3：
    // 指令 loc 更精确但属未登记差异，跨行表达式会渲染不同行号）
    Some(msg) => self.trap(msg, 0, 0)
    None => ()
  }
  match reply.note {
    Some(n) =>
      // 去重照搬 oracle report_heap_exhausted 的范围（只对堆耗尽附注
      // contains 查重；malloc(0) 等 note oracle 每次都推，不去重——
      // HostMemReply.note 契约「调用方负责去重」的三轮审阅 P2-1 落位）
      if n == @host.heap_exhausted_note() &&
        self.output.has_note(normalize_note_bytes(n)) {
        ()
      } else {
        self.output.push_note_str(n)
      }
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
/// note 查询的规范化（与 `push_note` 的存储形态对齐：末尾无 `\n` 补 `\n`——
/// `heap_exhausted_note` 自带 `\n` 不重复追加）。
fn normalize_note_bytes(n : String) -> Bytes {
  if n.length() > 0 && n[n.length() - 1] == '\n' {
    @utf8.encode(n)
  } else {
    @utf8.encode(n + "\n")
  }
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
    // ── math 20（f64 位模式进出：pop u64 位 → handler → push u64 位）──
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
      // fmod：先弹 x 后弹 y（oracle math.rs:77-80——与 pow 同向；atan2 才是
      // 先弹 y。三轮审阅 P1-1：此前写反，fmod(2,7.5) 算成了 fmod(7.5,2)）
      let x = self.pop()
      let y = self.pop()
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
      self.apply_reply(reply)
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
        // host 层 trap 空 loc 对齐 oracle（四轮审阅残留：free/unreachable
        // 与 apply_reply 同口径——SourceLoc::default() → 回退 current_line）
        Some(msg) => self.trap(msg, 0, 0)
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
      self.apply_reply(reply)
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
      self.apply_reply(reply)
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
      // unreachable：教学 trap（文案 host 单源；空 loc 同上）
      self.trap(@host.host_unreachable(), 0, 0)
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
