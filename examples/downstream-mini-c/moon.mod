// examples/downstream-mini-c：vitro/engine 的**下游消费示例**（独立 MoonBit module，
// 不是本仓 workspace 成员——与 desktop/ 同形：import 已发布包，零仓内相对路径）。
// 定位/运行方式/目标面注意见 README.md。
name = "vitro/downstream-mini-c"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/rustin-beep/Vitro"

license = "MIT"

keywords = [ "vitro", "example", "downstream" ]

// 默认目标 wasm 与 gateway 包（0.9.1 发布面 `+wasm-gc +native +js`）不交——
// cmd/gateway 子包自带 supported_targets 收窄，run 时显式 --target js（见 README）。

preferred_target = "wasm"

description = "vitro/engine 下游接线示例：五步库直连管线 + gateway NDJSON 协议链两形态"

import {
  "vitro/engine@0.9.1",
}
