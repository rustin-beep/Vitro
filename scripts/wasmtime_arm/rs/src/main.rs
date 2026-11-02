// W4 第四臂跑器：同一 wasm-gc 产物 × wasmtime（Cranelift）——宿主手工供给
// `wasm:js-string` 内建与 `_` 字符串常量，NDJSON 请求流逐行 invoke、响应
// 逐行写出，与 node/V8 侧跑器（../host_node.mts）同形，供对比器逐位对拍。
//
// 来源：R3b 探针 v4（D:/tmp/vitro-downstream-gui/probes/wasmtime_rs，决定性
// 探针——证明 Rust 原生 API 可供给 GC 引用宿主值面，C API 家族不行）。固化时
// 相对探针的三处改动：
//   ① 供给层语义对齐 js-string-builtins 提案 Overview.md（2026-11-02 拉取）：
//      charCodeAt/codePointAt 越界 trap（探针回 0）、equals 允 null（探针
//      panic）、fromCodePoint 代理项码点保真单 code unit（探针 U+FFFD 替换）、
//      fromCharCodeArray 越界 trap（探针钳制）、全部 index/count 参数按
//      unsigned 解释；并补齐产物可能 import 的其余内建（substring/compare/
//      codePointAt/fromCharCode/intoCharCodeArray/cast/test）——按产物 import
//      段按需定义，出现规范外名字 fail loud。
//   ② 宿主字符串读取改借用（探针每次 clone 整串——charCodeAt 逐字符调用下
//      O(n²)）；仅 concat/intoCharCodeArray 等必须跨 &mut 边界处做一次拷贝。
//   ③ 主循环每行 RootScope 包裹（探针在 store 根作用域累积 Rooted 不释放）；
//      invoke 返回 Err（wasm trap / 宿主 trap）时写 `{"__host_trap__":…}`
//      行并重建 Store+Instance——trap 后 MoonBit 运行时内部状态不可信，
//      两侧跑器同策略保证公平。
//
// 宿主字符串表示（W4 性能批 2026-11-02 定型，三形态可切作对照）：
//   - **默认 Poly**：externref = `extern.convert_any` 包装的 wasm-gc `(array i16)`，
//     六内建由内嵌 WAT polyfill 以纯 wasm 指令实现并 link 给主模块——import 调用
//     是 wasm→wasm 直接调用，零 host trampoline（V8 把这六个内建当编译器内建
//     内联；wasmtime 不认识该提案，走 host call 每次 51–105ns——实测引擎 VM
//     热路径每步 ~90 次字符串调用，corpus 全量 2.2 亿次，host 形态即 7–20×
//     慢；Poly 形态收到 1.2–3×）。宿主只在 invoke 边界经 wrap/unwrap 桥接数组。
//   - `W4_STRINGS=host`：externref 包 `Vec<u16>` 宿主数据，`Func::new` 动态
//     host call（R3b 探针原形态）；`+W4_TYPED=1` 高频五函数换 `Func::wrap`
//     静态形态（2×）。
//   输出一律 UTF-8（lone surrogate → U+FFFD，与 node Buffer.from 同口径）。
//
// 用法：wasmtime_arm <wasm.wasm> <requests.ndjson> <responses.ndjson>
// 环境旋钮：W4_STRINGS=host | W4_TYPED=1 | W4_INLINE=0 | W4_COUNT=1（host-call
// 计数）| W4_MAX_WASM_STACK=<bytes> | W4_INSPECT=1（打印导出/导入类型后退出）
// 退出码：0 正常（含 trap 行）；2 用法错；1 装载/编译/IO 失败。

use std::io::{BufRead, BufWriter, Write};
use std::time::Instant;
use wasmtime::{
    AnyRef, ArrayRef, AsContext, AsContextMut, Caller, Engine, ExternRef, Func, FuncType,
    Instance, Linker, Module, RootScope, Rooted, Store, StoreContext, Val,
};

type Host = GcProbe;

/// Store 数据：GC 堆增长观测（W4_GCLOG=1 时每次增长打印 current→desired；
/// 计数恒开，开销仅增长时一次）。
#[derive(Default)]
struct GcProbe {
    grows: u32,
    log: bool,
}

impl wasmtime::ResourceLimiter for GcProbe {
    fn memory_growing(&mut self, current: usize, desired: usize, _max: Option<usize>) -> wasmtime::Result<bool> {
        self.grows += 1;
        if self.log {
            eprintln!("[gc-heap grow #{}] {} -> {} bytes", self.grows, current, desired);
        }
        Ok(true)
    }
    fn table_growing(&mut self, _c: usize, _d: usize, _m: Option<usize>) -> wasmtime::Result<bool> {
        Ok(true)
    }
}

/// host-call 计数（W4_COUNT=1 时启用并随统计打印）——js-string 供给层开销
/// 定性用：把「调用次数 × 单次开销」与纯 Cranelift 差距分离。
const BUILTIN_NAMES: [&str; 13] = [
    "length", "charCodeAt", "codePointAt", "equals", "compare", "concat", "substring",
    "fromCharCode", "fromCodePoint", "fromCharCodeArray", "intoCharCodeArray", "cast", "test",
];
static CALLS: [std::sync::atomic::AtomicU64; 13] = [const { std::sync::atomic::AtomicU64::new(0) }; 13];
static COUNT_ON: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

fn builtin_id(name: &str) -> usize {
    BUILTIN_NAMES.iter().position(|n| *n == name).unwrap_or(BUILTIN_NAMES.len() - 1)
}

#[inline]
fn count_call(id: usize) {
    // 开关读 Relaxed 原子（~1ns），禁在热路径查环境变量
    if COUNT_ON.load(std::sync::atomic::Ordering::Relaxed) {
        CALLS[id].fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    }
}

fn utf16(s: &str) -> Vec<u16> {
    s.encode_utf16().collect()
}

/// 宿主字符串借用读取：null / 非宿主字符串 → Err（供给层 trap）。
fn str_ref<'a>(cx: StoreContext<'a, Host>, v: &Val, who: &str) -> wasmtime::Result<&'a Vec<u16>> {
    let rooted = match v {
        Val::ExternRef(Some(r)) => r,
        Val::ExternRef(None) => wasmtime::bail!("js-string {who}: null string"),
        other => wasmtime::bail!("js-string {who}: expected externref, got {other:?}"),
    };
    let any = rooted
        .data(cx)?
        .ok_or_else(|| wasmtime::format_err!("js-string {who}: externref without host data"))?;
    any.downcast_ref::<Vec<u16>>()
        .ok_or_else(|| wasmtime::format_err!("js-string {who}: externref is not a host string"))
}

fn i32_param(v: &Val, who: &str) -> wasmtime::Result<u32> {
    match v {
        // 规范：index/count 参数经 `>>> 0` 按 unsigned 解释
        Val::I32(i) => Ok(*i as u32),
        other => wasmtime::bail!("js-string {who}: expected i32, got {other:?}"),
    }
}

fn array_param(
    cx: StoreContext<'_, Host>,
    v: &Val,
    who: &str,
) -> wasmtime::Result<Rooted<ArrayRef>> {
    let any: &AnyRef = match v {
        Val::AnyRef(Some(r)) => r,
        Val::AnyRef(None) => wasmtime::bail!("js-string {who}: null array"),
        other => wasmtime::bail!("js-string {who}: expected anyref, got {other:?}"),
    };
    any.as_array(cx)?
        .ok_or_else(|| wasmtime::format_err!("js-string {who}: anyref is not an array"))
}

fn new_str(cx: impl AsContextMut<Data = Host>, s: Vec<u16>) -> wasmtime::Result<Val> {
    Ok(Val::ExternRef(Some(ExternRef::new(cx, s)?)))
}

/// 规范 Overview.md「JS String Builtin API」节逐函数复刻。
fn builtin(
    name: &str,
    mut caller: Caller<'_, Host>,
    params: &[Val],
    results: &mut [Val],
) -> wasmtime::Result<()> {
    match name {
        "length" => {
            let s = str_ref(caller.as_context(), &params[0], name)?;
            results[0] = Val::I32(s.len() as i32);
        }
        "charCodeAt" => {
            let i = i32_param(&params[1], name)? as usize;
            let s = str_ref(caller.as_context(), &params[0], name)?;
            if i >= s.len() {
                wasmtime::bail!("js-string charCodeAt: index {i} >= length {}", s.len());
            }
            results[0] = Val::I32(s[i] as i32);
        }
        "codePointAt" => {
            let i = i32_param(&params[1], name)? as usize;
            let s = str_ref(caller.as_context(), &params[0], name)?;
            if i >= s.len() {
                wasmtime::bail!("js-string codePointAt: index {i} >= length {}", s.len());
            }
            let hi = s[i] as u32;
            let cp = if (0xD800..0xDC00).contains(&hi) && i + 1 < s.len() {
                let lo = s[i + 1] as u32;
                if (0xDC00..0xE000).contains(&lo) {
                    0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00)
                } else {
                    hi
                }
            } else {
                hi
            };
            results[0] = Val::I32(cp as i32);
        }
        "equals" => {
            // 规范：null 允许且有意义——null==null 为 1；null vs string 为 0
            let eq = match (&params[0], &params[1]) {
                (Val::ExternRef(None), Val::ExternRef(None)) => true,
                (Val::ExternRef(None), _) | (_, Val::ExternRef(None)) => false,
                (a, b) => {
                    let sa = str_ref(caller.as_context(), a, name)?;
                    let sb = str_ref(caller.as_context(), b, name)?;
                    sa == sb
                }
            };
            results[0] = Val::I32(if eq { 1 } else { 0 });
        }
        "compare" => {
            // JS `<` 对字符串 = UTF-16 code unit 字典序 = Vec<u16> 的 Ord
            let sa = str_ref(caller.as_context(), &params[0], name)?;
            let sb = str_ref(caller.as_context(), &params[1], name)?;
            results[0] = Val::I32(match sa.cmp(sb) {
                std::cmp::Ordering::Less => -1,
                std::cmp::Ordering::Equal => 0,
                std::cmp::Ordering::Greater => 1,
            });
        }
        "concat" => {
            let joined = {
                let a = str_ref(caller.as_context(), &params[0], name)?;
                let b = str_ref(caller.as_context(), &params[1], name)?;
                let mut v = Vec::with_capacity(a.len() + b.len());
                v.extend_from_slice(a);
                v.extend_from_slice(b);
                v
            };
            results[0] = new_str(&mut caller, joined)?;
        }
        "substring" => {
            let start = i32_param(&params[1], name)? as usize;
            let end = i32_param(&params[2], name)? as usize;
            let out = {
                let s = str_ref(caller.as_context(), &params[0], name)?;
                if start > end || start > s.len() {
                    Vec::new()
                } else {
                    s[start..end.min(s.len())].to_vec()
                }
            };
            results[0] = new_str(&mut caller, out)?;
        }
        "fromCharCode" => {
            let c = i32_param(&params[0], name)?;
            results[0] = new_str(&mut caller, vec![(c & 0xFFFF) as u16])?;
        }
        "fromCodePoint" => {
            let cp = i32_param(&params[0], name)?;
            if cp > 0x10FFFF {
                wasmtime::bail!("js-string fromCodePoint: code point {cp:#x} > 0x10FFFF");
            }
            // String.fromCodePoint：BMP（含代理项码点）单 code unit；补充平面代理对
            let v = if cp < 0x10000 {
                vec![cp as u16]
            } else {
                let c = cp - 0x10000;
                vec![(0xD800 + (c >> 10)) as u16, (0xDC00 + (c & 0x3FF)) as u16]
            };
            results[0] = new_str(&mut caller, v)?;
        }
        "fromCharCodeArray" => {
            let start = i32_param(&params[1], name)?;
            let end = i32_param(&params[2], name)?;
            let arr = array_param(caller.as_context(), &params[0], name)?;
            let len = arr.len(caller.as_context())?;
            if start > end || end > len {
                wasmtime::bail!(
                    "js-string fromCharCodeArray: range [{start}, {end}) out of bounds (len {len})"
                );
            }
            let mut v = Vec::with_capacity((end - start) as usize);
            for i in start..end {
                match arr.get(&mut caller, i)? {
                    Val::I32(x) => v.push((x & 0xFFFF) as u16),
                    other => wasmtime::bail!("js-string fromCharCodeArray: non-i32 elem {other:?}"),
                }
            }
            results[0] = new_str(&mut caller, v)?;
        }
        "intoCharCodeArray" => {
            let start = i32_param(&params[2], name)?;
            // 先拷贝字符串（后续 set 需 &mut，不能并存借用）
            let s: Vec<u16> = str_ref(caller.as_context(), &params[0], name)?.clone();
            let arr = array_param(caller.as_context(), &params[1], name)?;
            let len = arr.len(caller.as_context())?;
            if (start as u64) + (s.len() as u64) > len as u64 {
                wasmtime::bail!(
                    "js-string intoCharCodeArray: start {start} + len {} > array len {len}",
                    s.len()
                );
            }
            for (k, cu) in s.iter().enumerate() {
                arr.set(&mut caller, start + k as u32, Val::I32(*cu as i32))?;
            }
            results[0] = Val::I32(s.len() as i32);
        }
        "cast" => {
            // 非 null 宿主字符串原样返回；否则 trap
            let _ = str_ref(caller.as_context(), &params[0], name)?;
            results[0] = params[0].clone();
        }
        "test" => {
            let ok = str_ref(caller.as_context(), &params[0], name).is_ok();
            results[0] = Val::I32(if ok { 1 } else { 0 });
        }
        other => wasmtime::bail!("js-string: builtin '{other}' not in provider table (spec-unknown)"),
    }
    Ok(())
}

struct Runtime {
    store: Store<Host>,
    invoke: Func,
    strings: Strings,
}

/// 宿主字符串表示两形态：
/// - `Host`：externref 包 `Vec<u16>` 宿主数据，六内建走 host call（Func::new /
///   Func::wrap）——每次 charCodeAt 都是 wasm→Rust trampoline（51–105 ns）。
/// - `Poly`（W4_POLY=1）：externref = `extern.convert_any` 包装的 wasm-gc
///   `(array (mut i16))`，六内建由内嵌 WAT polyfill 模块以纯 wasm 指令实现并
///   link 给主模块——import 调用变 wasm→wasm 直接调用（Cranelift 编译，零
///   host trampoline）；宿主只在 invoke 边界经 wrap/unwrap 构造与读取数组。
///   产物与引擎零改动，这是「不动 js-string 产物、在 wasmtime 侧想办法」的解。
enum Strings {
    Host,
    Poly { pre: wasmtime::ArrayRefPre, wrap: Func, unwrap: Func },
}

/// js-string 六内建的 wasm-gc 实现（语义逐条对齐提案 Overview.md；越界/null/
/// 超域经 `unreachable` 或 array 指令自身 trap——与规范 trap 一致）。
const POLY_WAT: &str = r#"
(module
  (type $a (array (mut i16)))
  (func $u (param $s externref) (result (ref $a))
    (ref.cast (ref $a) (any.convert_extern (local.get $s))))
  (func $wrap (export "wrap") (param $arr (ref null $a)) (result externref)
    (extern.convert_any (local.get $arr)))
  (func $unwrap (export "unwrap") (param $s externref) (result (ref null $a))
    (ref.cast (ref null $a) (any.convert_extern (local.get $s))))
  (func $length (export "length") (param $s externref) (result i32)
    (array.len (call $u (local.get $s))))
  (func $charCodeAt (export "charCodeAt") (param $s externref) (param $i i32) (result i32)
    (array.get_u $a (call $u (local.get $s)) (local.get $i)))
  (func $equals (export "equals") (param $p externref) (param $q externref) (result i32)
    (local $x (ref $a)) (local $y (ref $a)) (local $n i32) (local $i i32)
    (if (ref.is_null (local.get $p)) (then (return (ref.is_null (local.get $q)))))
    (if (ref.is_null (local.get $q)) (then (return (i32.const 0))))
    (local.set $x (call $u (local.get $p)))
    (local.set $y (call $u (local.get $q)))
    (local.set $n (array.len (local.get $x)))
    (if (i32.ne (local.get $n) (array.len (local.get $y))) (then (return (i32.const 0))))
    (block $done
      (loop $l
        (br_if $done (i32.eq (local.get $i) (local.get $n)))
        (if (i32.ne (array.get_u $a (local.get $x) (local.get $i))
                    (array.get_u $a (local.get $y) (local.get $i)))
          (then (return (i32.const 0))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $l)))
    (i32.const 1))
  (func $concat (export "concat") (param $p externref) (param $q externref) (result (ref extern))
    (local $x (ref $a)) (local $y (ref $a)) (local $r (ref $a)) (local $la i32) (local $lb i32)
    (local.set $x (call $u (local.get $p)))
    (local.set $y (call $u (local.get $q)))
    (local.set $la (array.len (local.get $x)))
    (local.set $lb (array.len (local.get $y)))
    (local.set $r (array.new_default $a (i32.add (local.get $la) (local.get $lb))))
    (array.copy $a $a (local.get $r) (i32.const 0) (local.get $x) (i32.const 0) (local.get $la))
    (array.copy $a $a (local.get $r) (local.get $la) (local.get $y) (i32.const 0) (local.get $lb))
    (extern.convert_any (local.get $r)))
  (func $fromCodePoint (export "fromCodePoint") (param $cp i32) (result (ref extern))
    (local $r (ref null $a)) (local $c i32)
    (if (i32.gt_u (local.get $cp) (i32.const 0x10FFFF)) (then (unreachable)))
    (if (i32.lt_u (local.get $cp) (i32.const 0x10000))
      (then
        (local.set $r (array.new_default $a (i32.const 1)))
        (array.set $a (local.get $r) (i32.const 0) (local.get $cp)))
      (else
        (local.set $c (i32.sub (local.get $cp) (i32.const 0x10000)))
        (local.set $r (array.new_default $a (i32.const 2)))
        (array.set $a (local.get $r) (i32.const 0)
          (i32.add (i32.const 0xD800) (i32.shr_u (local.get $c) (i32.const 10))))
        (array.set $a (local.get $r) (i32.const 1)
          (i32.add (i32.const 0xDC00) (i32.and (local.get $c) (i32.const 0x3FF))))))
    (extern.convert_any (ref.as_non_null (local.get $r))))
  (func $fromCharCodeArray (export "fromCharCodeArray")
        (param $arr (ref null $a)) (param $s i32) (param $e i32) (result (ref extern))
    (local $r (ref $a)) (local $n i32)
    (if (ref.is_null (local.get $arr)) (then (unreachable)))
    (if (i32.gt_u (local.get $s) (local.get $e)) (then (unreachable)))
    (if (i32.gt_u (local.get $e) (array.len (local.get $arr))) (then (unreachable)))
    (local.set $n (i32.sub (local.get $e) (local.get $s)))
    (local.set $r (array.new_default $a (local.get $n)))
    (array.copy $a $a (local.get $r) (i32.const 0)
                      (ref.as_non_null (local.get $arr)) (local.get $s) (local.get $n))
    (extern.convert_any (local.get $r)))
)
"#;

impl Strings {
    /// 宿主字符串 → externref（Host：Vec<u16> 宿主数据；Poly：数组 + wrap）。
    fn make(&self, mut cx: impl AsContextMut<Data = Host>, s: Vec<u16>) -> wasmtime::Result<Val> {
        match self {
            Strings::Host => Ok(Val::ExternRef(Some(ExternRef::new(&mut cx, s)?))),
            Strings::Poly { pre, wrap, .. } => {
                let vals: Vec<Val> = s.into_iter().map(|c| Val::I32(c as i32)).collect();
                let arr = ArrayRef::new_fixed(&mut cx, pre, &vals)?;
                let mut out = [Val::I32(0)];
                wrap.call(&mut cx, &[Val::from(arr)], &mut out)?;
                Ok(out[0].clone())
            }
        }
    }

    /// externref → 宿主 String（invoke 返回值读取）。
    fn read(&self, mut cx: impl AsContextMut<Data = Host>, v: &Val) -> wasmtime::Result<String> {
        match self {
            Strings::Host => {
                let u = str_ref(cx.as_context(), v, "invoke-result")?;
                Ok(String::from_utf16_lossy(u))
            }
            Strings::Poly { unwrap, .. } => {
                let mut out = [Val::I32(0)];
                unwrap.call(&mut cx, &[v.clone()], &mut out)?;
                let arr = match &out[0] {
                    Val::AnyRef(Some(a)) => a
                        .as_array(cx.as_context())?
                        .ok_or_else(|| wasmtime::format_err!("invoke-result: not an array"))?,
                    _ => wasmtime::bail!("invoke-result: unwrap gave non-anyref"),
                };
                let u: Vec<u16> = arr
                    .elems(&mut cx)?
                    .map(|e| match e {
                        Val::I32(x) => (x & 0xFFFF) as u16,
                        _ => 0xFFFD,
                    })
                    .collect();
                Ok(String::from_utf16_lossy(&u))
            }
        }
    }
}

/// typed 读取（Func::wrap 形态的参数是 `Option<Rooted<ExternRef>>` 而非 `Val`）。
fn sref<'a>(
    cx: StoreContext<'a, Host>,
    v: &Option<Rooted<ExternRef>>,
    who: &str,
) -> wasmtime::Result<&'a Vec<u16>> {
    let r = v
        .as_ref()
        .ok_or_else(|| wasmtime::format_err!("js-string {who}: null string"))?;
    let any = r
        .data(cx)?
        .ok_or_else(|| wasmtime::format_err!("js-string {who}: externref without host data"))?;
    any.downcast_ref::<Vec<u16>>()
        .ok_or_else(|| wasmtime::format_err!("js-string {who}: externref is not a host string"))
}

/// W4_TYPED=1：产物实际 import 的六内建改 `Func::wrap` 静态类型形态（wasmtime 的
/// typed host call 路径——免 `Val` 装箱与运行时分派；`Func::new` 是最慢的动态形态）。
/// 语义与 `builtin()` 逐条相同。返回 false = 该名字不在 typed 表，回落动态形态。
fn define_typed(
    store: &mut Store<Host>,
    linker: &mut Linker<Host>,
    name: &str,
) -> wasmtime::Result<bool> {
    let f = match name {
        "length" => Func::wrap(
            &mut *store,
            |caller: Caller<'_, Host>, s: Option<Rooted<ExternRef>>| -> wasmtime::Result<i32> {
                count_call(0);
                Ok(sref(caller.as_context(), &s, "length")?.len() as i32)
            },
        ),
        "charCodeAt" => Func::wrap(
            &mut *store,
            |caller: Caller<'_, Host>, s: Option<Rooted<ExternRef>>, i: i32| -> wasmtime::Result<i32> {
                count_call(1);
                let i = i as u32 as usize;
                let v = sref(caller.as_context(), &s, "charCodeAt")?;
                if i >= v.len() {
                    wasmtime::bail!("js-string charCodeAt: index {i} >= length {}", v.len());
                }
                Ok(v[i] as i32)
            },
        ),
        "equals" => Func::wrap(
            &mut *store,
            |caller: Caller<'_, Host>,
             a: Option<Rooted<ExternRef>>,
             b: Option<Rooted<ExternRef>>|
             -> wasmtime::Result<i32> {
                count_call(3);
                let eq = match (&a, &b) {
                    (None, None) => true,
                    (None, _) | (_, None) => false,
                    _ => sref(caller.as_context(), &a, "equals")? == sref(caller.as_context(), &b, "equals")?,
                };
                Ok(if eq { 1 } else { 0 })
            },
        ),
        "concat" => Func::wrap(
            &mut *store,
            |mut caller: Caller<'_, Host>,
             a: Option<Rooted<ExternRef>>,
             b: Option<Rooted<ExternRef>>|
             -> wasmtime::Result<Rooted<ExternRef>> {
                count_call(5);
                let joined = {
                    let x = sref(caller.as_context(), &a, "concat")?;
                    let y = sref(caller.as_context(), &b, "concat")?;
                    [x.as_slice(), y.as_slice()].concat()
                };
                ExternRef::new(&mut caller, joined)
            },
        ),
        "fromCodePoint" => Func::wrap(
            &mut *store,
            |mut caller: Caller<'_, Host>, cp: i32| -> wasmtime::Result<Rooted<ExternRef>> {
                count_call(8);
                let cp = cp as u32;
                if cp > 0x10FFFF {
                    wasmtime::bail!("js-string fromCodePoint: code point {cp:#x} > 0x10FFFF");
                }
                let v = if cp < 0x10000 {
                    vec![cp as u16]
                } else {
                    let c = cp - 0x10000;
                    vec![(0xD800 + (c >> 10)) as u16, (0xDC00 + (c & 0x3FF)) as u16]
                };
                ExternRef::new(&mut caller, v)
            },
        ),
        // fromCharCodeArray 不进 typed 表：import 参数是具体数组类型
        // `(ref null array(engine N))`，Func::wrap 只能给泛 `(ref null array)`，
        // linker 精确匹配拒绝（实测）；且其调用量低两个数量级（12 万 vs 1 亿），
        // 回落 Func::new 动态形态无性能意义。
        _ => return Ok(false),
    };
    linker.define(&mut *store, "wasm:js-string", name, f)?;
    Ok(true)
}

/// 新建 Store + 供给 import 面 + 实例化（首次与每次 trap 后重建共用）。
fn instantiate(engine: &Engine, module: &Module) -> wasmtime::Result<Runtime> {
    let typed = std::env::var_os("W4_TYPED").is_some();
    // 默认 Poly 形态（W4_STRINGS=host 回退宿主 Vec<u16> 形态作对照）
    let poly = std::env::var("W4_STRINGS").map(|v| v != "host").unwrap_or(true);
    let mut store = Store::new(
        engine,
        GcProbe { grows: 0, log: std::env::var_os("W4_GCLOG").is_some() },
    );
    store.limiter(|h| h);
    let mut linker: Linker<Host> = Linker::new(engine);

    // Poly 形态：先在同一 Store 实例化 WAT polyfill（同一 GC 堆，对象可跨实例传递）
    let mut poly_funcs: std::collections::HashMap<String, Func> = std::collections::HashMap::new();
    let strings = if poly {
        let pm = Module::new(engine, POLY_WAT)?;
        let pi = Instance::new(&mut store, &pm, &[])?;
        for name in ["length", "charCodeAt", "equals", "concat", "fromCodePoint", "fromCharCodeArray"] {
            let f = pi
                .get_func(&mut store, name)
                .ok_or_else(|| wasmtime::format_err!("polyfill export '{name}' missing"))?;
            poly_funcs.insert(name.to_string(), f);
        }
        let wrap = pi.get_func(&mut store, "wrap").expect("polyfill wrap");
        let unwrap = pi.get_func(&mut store, "unwrap").expect("polyfill unwrap");
        // 宿主数组类型直接取自 polyfill 的 wrap 参数类型——与 $a 同一 canonical 类型
        let wrap_ty = wrap.ty(&store);
        let param0 = wrap_ty
            .params()
            .next()
            .ok_or_else(|| wasmtime::format_err!("polyfill wrap: no param"))?;
        let array_ty = match param0 {
            wasmtime::ValType::Ref(rt) => rt.heap_type().unwrap_concrete_array().clone(),
            other => wasmtime::bail!("polyfill wrap: param0 not a ref: {other:?}"),
        };
        let pre = wasmtime::ArrayRefPre::new(&mut store, array_ty);
        Strings::Poly { pre, wrap, unwrap }
    } else {
        Strings::Host
    };

    let mut seen = std::collections::HashSet::new();
    for imp in module.imports() {
        match imp.module() {
            "_" => {
                // 字符串常量：import 名即常量值（与 scripts/wasm_load.mts 同约定）
                let name = imp.name().to_string();
                if !seen.insert(name.clone()) {
                    continue;
                }
                let v = strings.make(&mut store, utf16(&name))?;
                let ty = imp
                    .ty()
                    .global()
                    .ok_or_else(|| wasmtime::format_err!("'_' import {name} is not a global"))?
                    .clone();
                let g = wasmtime::Global::new(&mut store, ty, v)?;
                linker.define(&mut store, "_", &name, g)?;
            }
            "wasm:js-string" => {
                let name = imp.name().to_string();
                if let Some(f) = poly_funcs.get(&name) {
                    // wasm→wasm：polyfill 导出直接作为 import（零 host trampoline）
                    linker.define(&mut store, "wasm:js-string", &name, *f)?;
                    continue;
                }
                if poly {
                    wasmtime::bail!("polyfill 未覆盖 js-string 内建 '{name}'（产物 import 面超出六函数）");
                }
                if typed && define_typed(&mut store, &mut linker, &name)? {
                    continue;
                }
                let ft: FuncType = imp
                    .ty()
                    .func()
                    .ok_or_else(|| wasmtime::format_err!("js-string import {name} is not a func"))?
                    .clone();
                let n = name.clone();
                let id = builtin_id(&name);
                let f = Func::new(&mut store, ft, move |caller, params, results| {
                    count_call(id);
                    builtin(&n, caller, params, results)
                });
                linker.define(&mut store, "wasm:js-string", &name, f)?;
            }
            other => wasmtime::bail!("unexpected import module '{other}' / '{}'", imp.name()),
        }
    }
    let instance: Instance = linker.instantiate(&mut store, module)?;
    let invoke = instance
        .get_func(&mut store, "invoke")
        .ok_or_else(|| wasmtime::format_err!("export 'invoke' missing"))?;
    Ok(Runtime { store, invoke, strings })
}

fn json_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out
}

fn main() -> wasmtime::Result<()> {
    let args: Vec<String> = std::env::args().collect();
    if args.len() != 4 {
        eprintln!("usage: wasmtime_arm <wasm.wasm> <requests.ndjson> <responses.ndjson>");
        std::process::exit(2);
    }
    // wasmtime 约束：max_wasm_stack 必须小于宿主线程栈（否则 guard page 探测
    // 失效——W4 实测 Windows 主线程 1MB 下配 1MiB+ 跑 struct_nest_3000 直接
    // 进程崩 0x40010004 而非 StackOverflow trap）。跑器主体一律放进 64MB
    // 子线程，使 W4_MAX_WASM_STACK 在 ≤32MiB 内安全可用。
    let handle = std::thread::Builder::new()
        .name("wasmtime_arm".into())
        .stack_size(64 << 20)
        .spawn(move || run(&args))
        .expect("spawn runner thread");
    match handle.join() {
        Ok(r) => r,
        Err(_) => {
            eprintln!("[wasmtime_arm] runner thread panicked");
            std::process::exit(1);
        }
    }
}

fn run(args: &[String]) -> wasmtime::Result<()> {
    if std::env::var_os("W4_COUNT").is_some() {
        COUNT_ON.store(true, std::sync::atomic::Ordering::Relaxed);
    }
    let t0 = Instant::now();
    let mut cfg = wasmtime::Config::new();
    cfg.wasm_gc(true)
        .wasm_function_references(true)
        .wasm_reference_types(true);
    // W4_MAX_WASM_STACK（字节）：wasm 栈预算（wasmtime 默认 512 KiB）——栈溢出类
    // 分叉的定性旋钮：加大后分叉消失 ⇒ 预算差异而非语义差异。连坐
    // async_stack_size（默认 2 MiB，wasmtime 要求 ≥ max_wasm_stack）。
    // W4 实测：2 MiB 时 struct_nest 临界深度 (4000,6000] 与 V8 默认重合。
    if let Some(v) = std::env::var("W4_MAX_WASM_STACK").ok().and_then(|s| s.parse::<usize>().ok()) {
        cfg.max_wasm_stack(v);
        cfg.async_stack_size(v + (1 << 20));
    }
    // 默认开 Cranelift 函数内联（wasmtime 50 默认 Inlining::No；W4_INLINE=0 关）——
    // 模块内小函数内联，实测 -11% 运行 / +85% 编译（≈+350ms 一次性）；跨模块
    // （polyfill import）不可内联。
    if std::env::var("W4_INLINE").map(|v| v != "0").unwrap_or(true) {
        cfg.compiler_inlining(wasmtime::Inlining::Yes);
    }
    // GC 堆初始大小（wasmtime 默认 0——从零按需增长；copying collector 每次
    // 收集/增长整体拷活跃集，大字符串活跃集下抖动：src_500k_many_lines compile
    // 8.7s vs node 0.17s 实锤）。内存惰性提交，调大无实际代价。W4_GC_HEAP_MB 覆盖。
    let gc_mb: u64 = std::env::var("W4_GC_HEAP_MB").ok().and_then(|s| s.parse().ok()).unwrap_or(256);
    cfg.gc_heap_initial_size(gc_mb << 20);
    // W4_COLLECTOR=drc|copying|null（默认 Auto=copying）——收集器对照旋钮
    match std::env::var("W4_COLLECTOR").as_deref() {
        Ok("drc") => { cfg.collector(wasmtime::Collector::DeferredReferenceCounting); }
        Ok("null") => { cfg.collector(wasmtime::Collector::Null); }
        _ => {}
    }
    let engine = Engine::new(&cfg)?;
    let module = Module::from_file(&engine, &args[1])?;
    if std::env::var_os("W4_INSPECT").is_some() {
        for e in module.exports() {
            eprintln!("[inspect] export {} : {:?}", e.name(), e.ty());
        }
        let mut n = 0;
        for i in module.imports() {
            if n < 8 {
                eprintln!("[inspect] import {}::{} : {:?}", i.module(), i.name(), i.ty());
            }
            n += 1;
        }
        eprintln!("[inspect] imports total={n}");
        return Ok(());
    }
    let t_compile = t0.elapsed();

    let mut rt = instantiate(&engine, &module)?;
    let t_inst = t0.elapsed() - t_compile;

    let input = std::io::BufReader::new(std::fs::File::open(&args[2])?);
    let mut out = BufWriter::new(std::fs::File::create(&args[3])?);
    let (mut lines, mut traps) = (0usize, 0usize);
    let mut timings: Vec<(usize, u128)> = Vec::new();
    let t_run = Instant::now();
    for line in input.lines() {
        let line = line?;
        let t_line = Instant::now();
        lines += 1;
        let res: wasmtime::Result<String> = (|| {
            let mut scope = RootScope::new(&mut rt.store);
            let arg = rt.strings.make(&mut scope, utf16(&line))?;
            let mut outv = [Val::I32(0)];
            rt.invoke.call(&mut scope, &[arg], &mut outv)?;
            rt.strings.read(&mut scope, &outv[0])
        })();
        match res {
            Ok(s) => {
                out.write_all(s.as_bytes())?;
                out.write_all(b"\n")?;
            }
            Err(e) => {
                traps += 1;
                // 归因前缀：wasm 层 Trap 枚举可辨（栈溢出/unreachable 等）；其余为
                // 宿主供给层 bail（消息自带 "js-string <fn>:" 前缀）
                let kind = match e.downcast_ref::<wasmtime::Trap>() {
                    Some(t) => format!("wasm-trap {t:?}"),
                    None => "host-err".to_string(),
                };
                let msg = format!("{e:#}");
                out.write_all(
                    format!(
                        "{{\"__host_trap__\":\"{}\",\"kind\":\"{}\"}}\n",
                        json_escape(&msg),
                        json_escape(&kind)
                    )
                    .as_bytes(),
                )?;
                rt = instantiate(&engine, &module)?;
            }
        }
        timings.push((lines - 1, t_line.elapsed().as_millis()));
        // W4_GCTIME=1：每行后强制一次 GC 并计时（单次 GC 成本探针——live set 大小的代理）
        if std::env::var_os("W4_GCTIME").is_some() {
            let tg = Instant::now();
            let _ = rt.store.gc(None);
            eprintln!("[gc-time] after line #{} : {}ms", lines - 1, tg.elapsed().as_millis());
        }
    }
    out.flush()?;
    timings.sort_by(|a, b| b.1.cmp(&a.1));
    eprintln!("[wasmtime_arm] gc-heap grows={}", rt.store.data().grows);
    let top: Vec<String> = timings.iter().take(10).map(|(i, ms)| format!("#{i}:{ms}ms")).collect();
    eprintln!(
        "[wasmtime_arm] lines={lines} traps={traps} compile={}ms instantiate={}ms run={}ms wasmtime=50.0.1 strings={} typed={} inline={} top10={}",
        t_compile.as_millis(),
        t_inst.as_millis(),
        t_run.elapsed().as_millis(),
        if std::env::var("W4_STRINGS").map(|v| v != "host").unwrap_or(true) { "poly" } else { "host" },
        std::env::var_os("W4_TYPED").is_some(),
        std::env::var("W4_INLINE").map(|v| v != "0").unwrap_or(true),
        top.join(","),
    );
    if COUNT_ON.load(std::sync::atomic::Ordering::Relaxed) {
        let mut total = 0u64;
        let parts: Vec<String> = BUILTIN_NAMES
            .iter()
            .enumerate()
            .filter_map(|(i, n)| {
                let c = CALLS[i].load(std::sync::atomic::Ordering::Relaxed);
                total += c;
                if c > 0 { Some(format!("{n}={c}")) } else { None }
            })
            .collect();
        eprintln!("[wasmtime_arm] host-calls total={total} {}", parts.join(" "));
    }
    Ok(())
}
