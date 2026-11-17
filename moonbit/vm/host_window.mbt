// 蓝本注记：文内 Rust 源引用（`*.rs` 路径/行号/符号）均为档案态蓝本——tag rust-oracle-freeze（2026-10-05 删区），现为本仓自主基线。

///| L7 执行层·VM 域·**REHOST 批 4′：CallHost 窗口回接路由表**——
/// 114 host id → 窗口分发能力分组 + 返回值形态 + 固定参数个数。
///
/// **真源与派生**（三源对账形态）：
/// - 分组（Ready/Stdin/Vfs/Callback/VaList/Observe）= 各臂的运行期依赖
///   亲读定型（host_dispatch{,2,3}.mbt——waiting_input / VFS 句柄 /
///   CallPtr 回调 / va_list 游标 / 观测通道）；
/// - 返回值形态 = C 原型（`scripts/moonbit/libc_src/include/*.h`）经
///   `@wasmenc.WValKind` 三态投影：int/指针/size_t → VkWordI32、
///   double → VkF64、long long → VkI64、void → None；
/// - 参数个数（固定参路由）= C 原型参数个数 == 各臂弹参数（亲读对账；
///   **弹参序刻意不进表**——蓝本弹参序逐函数不一致〔pow 先弹 x、
///   memset 先弹 ptr vs calloc 先弹 size——对拍面契约〕，窗口协议按
///   「值栈序透传」天然免疫：wasm 弹写窗口 = 栈顶序、宿主读窗口
///   push 回 VM = 底序，臂内弹参照常——序不在本表管辖域）。
///
/// **Ready 组的运行期前提**：宿主中继（`cmd/host_relay`——批 4′）持有
/// VitroVM 实例（值栈残留/MemoryMap 堆态/rand 状态跨调用保持——与引擎臂
/// 一次完整跑同构）；停机族（exit/abort/assert_fail/unreachable）经协议层
/// 「停机标记」表达（V8 侧 import 回调 throw——wasm 无 ip 回退/停机原语）。
///
/// **变参路由**（argc = None）：printf/sprintf/snprintf/sscanf 四条——
/// 实参个数编译期在 AST（codegen 按 AST 实参压栈）、运行期在 fmt 解析
/// （VM 臂弹 need 个）——窗口侧静态个数走 **AST 侧车**（dump_wasm 管线
/// 供给 `variadic_host_argc`），运行期弹差（printf("%d",1,2) 多余实参
/// 残留值栈）两侧同构不干预。

///|
/// 窗口回接能力分组（禁译桶细分口径——dispatchdiff baseline 连坐）。
#derive(Debug, Eq)
pub(all) enum HostWindowGroup {
  /// 窗口可回接（纯计算 / 内存 / stdout / 停机协议）
  Ready
  /// 交互输入族（waiting_input——wasm 无 ip 回退语义，禁译）
  Stdin
  /// VFS 文件族（FILE* 句柄态在引擎 VFS 表——中继未建，禁译）
  Vfs
  /// 控制流回调族（qsort/bsearch——CallPtr 已禁译，双禁）
  Callback
  /// va_list 游标族（VM va 状态机——禁译）
  VaList
  /// 观测通道（OUTPUT/STEP/数组守卫——教学观测域，禁译）
  Observe
}

///|
pub extend HostWindowGroup with Debug::{to_repr}

///|
pub extend HostWindowGroup with Eq::{not_equal, equal}

///|
/// 单路由窗口签名。
#derive(Debug, Eq)
pub(all) struct HostWindowSig {
  /// 能力分组（Ready = 可组装；其余 = 禁译桶 reason 细分）
  group : HostWindowGroup
  /// 固定参数个数（Ready 组固定参路由；变参路由 None = AST 侧车供给）
  argc : Int32?
  /// 返回值形态（None = void / 停机族——CallHost 组装不压返回值）
  ret : @wasmenc.WValKind?
}

///|
pub extend HostWindowSig with Debug::{to_repr}

///|
pub extend HostWindowSig with Eq::{not_equal, equal}

///|
/// 窗口白名单 + 形态表（id → 签名；表外 id 不存在——host_func_pairs
/// 对账锚见 wbtest）。**增删路由连坐**：本表穷尽 114 id（穷尽性锚
/// `test "host_window 全 id 穷尽"`），新路由（gen_host_route 再生成）
/// 落表即红逼登记。
fn host_window_sig(id : Int32) -> HostWindowSig? {
  // 局部构造（紧凑——表体 114 行穷尽）
  fn fixed(argc : Int32, ret : @wasmenc.WValKind?) -> HostWindowSig {
    { group: Ready, argc: Some(argc), ret, }
  }
  fn variadic(ret : @wasmenc.WValKind?) -> HostWindowSig {
    { group: Ready, argc: None, ret, }
  }
  fn deny(group : HostWindowGroup, argc : Int32) -> HostWindowSig {
    { group, argc: Some(argc), ret: None, }
  }
  match id {
    // ── printf 族（变参——AST 侧车；fprintf/vprintf/vfprintf/vsnprintf
    //    走 VFS/VaList 桶）──
    15 | 82 | 83 | 84 => Some(variadic(Some(@wasmenc.VkWordI32))) // printf/sprintf/snprintf/sscanf
    // ── 内存族（malloc/free/realloc/calloc）──
    2 => Some(fixed(1, Some(@wasmenc.VkWordI32))) // malloc(size)
    3 => Some(fixed(1, None)) // free(ptr)——void
    51 => Some(fixed(2, Some(@wasmenc.VkWordI32))) // realloc(ptr,size)
    80 => Some(fixed(2, Some(@wasmenc.VkWordI32))) // calloc(nmemb,size)
    // ── mem 族 ──
    37 => Some(fixed(3, Some(@wasmenc.VkWordI32))) // memset(ptr,val,n)
    57 | 58 => Some(fixed(3, Some(@wasmenc.VkWordI32))) // memcpy/memmove(d,s,n)
    92 => Some(fixed(3, Some(@wasmenc.VkWordI32))) // memcmp(a,b,n)
    96 => Some(fixed(3, Some(@wasmenc.VkWordI32))) // memchr(s,c,n)
    // ── 字符串族 ──
    30 => Some(fixed(1, Some(@wasmenc.VkWordI32))) // strlen(s)
    31 => Some(fixed(2, Some(@wasmenc.VkWordI32))) // strcpy(d,s)
    56 => Some(fixed(3, Some(@wasmenc.VkWordI32))) // strncpy(d,s,n)
    39 => Some(fixed(2, Some(@wasmenc.VkWordI32))) // strcat(d,s)
    90 => Some(fixed(3, Some(@wasmenc.VkWordI32))) // strncat(d,s,n)
    32 => Some(fixed(2, Some(@wasmenc.VkWordI32))) // strcmp(a,b)
    91 => Some(fixed(3, Some(@wasmenc.VkWordI32))) // strncmp(a,b,n)
    93 | 94 => Some(fixed(2, Some(@wasmenc.VkWordI32))) // strchr/strrchr(s,c)
    95 | 128 => Some(fixed(2, Some(@wasmenc.VkWordI32))) // strstr/strpbrk(hay,needle)
    129 | 130 => Some(fixed(2, Some(@wasmenc.VkWordI32))) // strspn/strcspn(s,accept)
    77 => Some(fixed(1, Some(@wasmenc.VkWordI32))) // strdup(s)
    119 => Some(fixed(1, Some(@wasmenc.VkWordI32))) // strerror(errnum)
    // ── 转数值族 ──
    40 => Some(fixed(1, Some(@wasmenc.VkWordI32))) // atoi(s)
    97 => Some(fixed(1, Some(@wasmenc.VkF64))) // atof(s)
    98 => Some(fixed(1, Some(@wasmenc.VkI64))) // atol(s)
    117 => Some(fixed(3, Some(@wasmenc.VkI64))) // strtol(s,endptr,base)
    118 => Some(fixed(2, Some(@wasmenc.VkF64))) // strtod(s,endptr)
    // ── 字符 IO / puts ──
    34 => Some(fixed(1, Some(@wasmenc.VkWordI32))) // putchar(c)
    79 => Some(fixed(1, Some(@wasmenc.VkWordI32))) // puts(s)
    // ── ctype（14——遮蔽域 11 按名不可达，CallPtr 通道可达照收）──
    42 | 43 | 44 | 45 | 46 | 47 | 48 | 49 | 53 | 54 | 55 | 106 | 107 | 108 =>
      Some(fixed(1, Some(@wasmenc.VkWordI32)))
    // ── math 22 + abs/llabs/rand/srand（f64 位模式进出；pop 数按原型）──
    70
    | 71
    | 72
    | 74
    | 75
    | 76
    | 99
    | 100
    | 101
    | 102
    | 103
    | 104
    | 109
    | 110
    | 112
    | 113
    | 114 => Some(fixed(1, Some(@wasmenc.VkF64))) // sin/cos/sqrt/atan/log/exp/tan/log10/fabs/ceil/floor/round/asin/acos/sinh/cosh/tanh
    73 | 105 | 111 => Some(fixed(2, Some(@wasmenc.VkF64))) // pow/fmod/atan2
    41 => Some(fixed(1, Some(@wasmenc.VkWordI32))) // abs(n)
    115 => Some(fixed(1, Some(@wasmenc.VkI64))) // llabs(n)
    35 => Some(fixed(0, Some(@wasmenc.VkWordI32))) // rand()
    36 => Some(fixed(1, None)) // srand(seed)——void
    145 => Some(fixed(2, Some(@wasmenc.VkF64))) // difftime(t1,t0)
    // ── time/clock（clock_source 注入；确定性档恒 0——tloc 写回走内存同步）──
    123 => Some(fixed(1, Some(@wasmenc.VkWordI32))) // time(tloc)
    124 => Some(fixed(0, Some(@wasmenc.VkWordI32))) // clock()
    // ── 停机族（协议层停机标记——无返回值）──
    38 => Some(fixed(1, None)) // exit(code)
    116 => Some(fixed(0, None)) // abort()
    125 => Some(fixed(0, None)) // assert_fail()（可变 loc 形参按 0 计——CallHost 通道无 loc 实参）
    144 => Some(fixed(0, None)) // unreachable()
    // ── Stdin 族（waiting_input——禁译桶）──
    21 | 33 | 65 | 78 | 85 => Some(deny(Stdin, 1))
    // ── VFS 族（FILE* 句柄态——禁译桶；fprintf/vfprintf/vsnprintf 双属
    //    （VFS+变参/va）归 Vfs）──
    50
    | 60
    | 61
    | 62
    | 63
    | 64
    | 66
    | 86
    | 87
    | 88
    | 89
    | 120
    | 121
    | 122
    | 126
    | 127
    | 147
    | 148 => Some(deny(Vfs, 1))
    // ── 回调族 ──
    52 | 81 => Some(deny(Callback, 1))
    // ── va_list 族 ──
    140 | 141 | 142 | 143 | 146 => Some(deny(VaList, 1))
    // ── 观测通道 ──
    0 | 1 | 131 | 132 => Some(deny(Observe, 1))
    _ => None // 表外 id 不存在（穷尽锚对账）
  }
}
