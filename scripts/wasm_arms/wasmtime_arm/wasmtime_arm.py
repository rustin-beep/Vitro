"""wasmtime 臂——五方对拍的 wasmtime 宿主（#199，Python binding 版）。

Go binding（wasmtime-go v33）在本机 Windows 静态链接后桥接读回被解析为
非法 JSON（同产物同桥 wasmtime CLI 直调返回长度正常）——弃用，改
wasmtime-py（自带预编译动态库，零链接配置）。

跑 gateway 零导入风味 wasm-gc 产物（import=0，无宿主函数注册）。invoke
的 String ABI（(ref (array (mut i16)))）不跨边界：走产物自带
bridge_write/bridge_invoke/bridge_read 全 i32 桥（gateway/wasm_nojs
export.mbt），code unit = UTF-16。

用法：python wasmtime_arm.py <wasm> --cases <ndjson> [output]
  stdout 逐行响应（与 wasmoon_arm 同口径，供 duel 对拍）；
  stderr 打 invoke 耗时。
"""

import sys
import time

import wasmtime


def build_engine():
    cfg = wasmtime.Config()
    cfg.wasm_gc = True
    cfg.wasm_function_references = True
    return wasmtime.Engine(cfg)


def main() -> None:
    args = sys.argv[1:]
    if not args:
        print("usage: wasmtime_arm.py <wasm> --cases <ndjson>", file=sys.stderr)
        sys.exit(2)
    wasm_path = args[0]
    requests = []
    if "--cases" in args:
        p = args[args.index("--cases") + 1]
        with open(p, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    requests.append(line)
    else:
        requests = args[1:]

    engine = build_engine()
    module = wasmtime.Module(engine, open(wasm_path, "rb").read())
    store = wasmtime.Store(engine)
    instance = wasmtime.Instance(store, module, [])
    exports = instance.exports(store)
    bridge_write = exports["bridge_write"]
    bridge_invoke = exports["bridge_invoke"]
    bridge_read = exports["bridge_read"]

    for req in requests:
        t0 = time.time()
        for ch in req:
            bridge_write(store, ord(ch))
        n = bridge_invoke(store)
        units = [bridge_read(store, i) for i in range(n)]
        resp = "".join(chr(u) for u in units)
        elapsed = int((time.time() - t0) * 1000)
        print(f"ARM invoke-ms={elapsed}", file=sys.stderr, flush=True)
        print(resp, flush=True)


if __name__ == "__main__":
    main()
