// W4 第四臂跑器：同一 wasm-gc 产物 × wasmtime（Cranelift）——宿主手工供给
// `wasm:js-string` 内建与 `_` 字符串常量，NDJSON 请求流逐行 invoke、响应
// 逐行写出，与 node/V8 侧跑器（../host_node.mts）同形，供对比器逐位对拍。
//
// 来��：R3b 探针 v4（D:/tmp/vitro-downstream-gui/probes/wasmtime_rs，决定性
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
// 宿主字符串表示 = Vec<u16>（UTF-16 code unit，与 V8 字符串语义对齐）；
// 输出按 UTF-8 写出（lone surrogate → U+FFFD，与 node Buffer.from 同口径）。
//
// 用法：wasmtime_arm <wasm.wasm> <requests.ndjson> <responses.ndjson>
// 退出码：0 正常（含 trap 行）；2 用法错；1 装载/编译/IO 失败。

use std::io::{BufRead, BufWriter, Write};
use std::time::Instant;
use wasmtime::{
    AnyRef, ArrayRef, AsContext, AsContextMut, Caller, Engine, ExternRef, Func, FuncType,
    Instance, Linker, Module, RootScope, Rooted, Store, StoreContext, Val,
};

type Host = ();

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
}

/// 新建 Store + 供给 import 面 + 实例化（首次与每次 trap 后重建共用）。
fn instantiate(engine: &Engine, module: &Module) -> wasmtime::Result<Runtime> {
    let mut store = Store::new(engine, ());
    let mut linker: Linker<Host> = Linker::new(engine);
    let mut seen = std::collections::HashSet::new();
    for imp in module.imports() {
        match imp.module() {
            "_" => {
                // 字符串常量：import 名即常量值（与 scripts/wasm_load.mts 同约定）
                let name = imp.name().to_string();
                if !seen.insert(name.clone()) {
                    continue;
                }
                let ext = ExternRef::new(&mut store, utf16(&name))?;
                let ty = imp
                    .ty()
                    .global()
                    .ok_or_else(|| wasmtime::format_err!("'_' import {name} is not a global"))?
                    .clone();
                let g = wasmtime::Global::new(&mut store, ty, Val::ExternRef(Some(ext)))?;
                linker.define(&mut store, "_", &name, g)?;
            }
            "wasm:js-string" => {
                let name = imp.name().to_string();
                let ft: FuncType = imp
                    .ty()
                    .func()
                    .ok_or_else(|| wasmtime::format_err!("js-string import {name} is not a func"))?
                    .clone();
                let n = name.clone();
                let f = Func::new(&mut store, ft, move |caller, params, results| {
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
    Ok(Runtime { store, invoke })
}

fn read_str(cx: StoreContext<'_, Host>, v: &Val) -> wasmtime::Result<String> {
    let u = str_ref(cx, v, "invoke-result")?;
    Ok(String::from_utf16_lossy(u))
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
    let engine = Engine::new(&cfg)?;
    let module = Module::from_file(&engine, &args[1])?;
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
            let ext = ExternRef::new(&mut scope, utf16(&line))?;
            let mut outv = [Val::I32(0)];
            rt.invoke
                .call(&mut scope, &[Val::ExternRef(Some(ext))], &mut outv)?;
            read_str(scope.as_context(), &outv[0])
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
    }
    out.flush()?;
    timings.sort_by(|a, b| b.1.cmp(&a.1));
    let top: Vec<String> = timings.iter().take(10).map(|(i, ms)| format!("#{i}:{ms}ms")).collect();
    eprintln!(
        "[wasmtime_arm] lines={lines} traps={traps} compile={}ms instantiate={}ms run={}ms wasmtime=50.0.1 top10={}",
        t_compile.as_millis(),
        t_inst.as_millis(),
        t_run.elapsed().as_millis(),
        top.join(","),
    );
    Ok(())
}
