name = "vitro/desktop"

version = "0.1.0"

import {
  "moonbitlang/async@0.22.5",
  "moonbit-community/proton@0.6.0",
  "moonbit-community/proton_contract@0.6.0",
  "vitro/engine@0.9.1",
}

license = "MIT"

description = "Vitro 桌面壳（proton 捉虫/测试）——独立下游 module，非发包面：引擎发布物走 mooncakes vitro/engine，本工程零进入 publish"

options(
  warn_list: "",
  preferred_target: "native",
  supported_targets: "+native",
)
