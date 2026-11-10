# Third-Party Notices（指针页）

本文件只做**指针**，不复制内容——各范围（分区）的第三方声明以所指文件为唯一真相源，避免双真相源漂移。

| 范围 | 声明位置 | 内容 |
|:---|:---|:---|
| MoonBit 引擎 vendored 代码（`moonbit/`） | [moonbit/THIRD_PARTY.md](moonbit/THIRD_PARTY.md) | vendored 代码（moonbitlang/x fs/unicode 子集，Apache-2.0）来源表与本地修改声明（Apache-2.0 §4(b)） |
| 浏览器 demo 前端依赖（`demo/`） | 部署产物 `THIRD-PARTY-NOTICES.txt`（[在线页](https://rustin-beep.github.io/Vitro/)页脚有可见链接） | 打包进产物的第三方包（CodeMirror / Svelte runtime 等，MIT）版权与许可全文；vite 构建期由 **bundle 实际模块表**反查生成（`demo/vite.config.ts` 内联插件 `thirdPartyNotices`），发布面存在性由 `scripts/demo_assemble_check` 判据 ④（`--no-ts`）守 |
| MoonBit 标准库 core（随引擎产物分发） | 部署产物 `ENGINE-NOTICES.txt` | core（Apache-2.0, © IDEA）编译进 wasm.wasm / langpack.js 随 Pages 分发——许可全文 + NOTICE 转载（fdlibm / V8 / Go / musl / FreeBSD 归属，Apache-2.0 §4(a)/(d)）；构建期自**构建该产物的同一工具链**（`~/.moon/lib/core`）现场发射（`demo/vite.config.ts` 内联插件 `engineNotices`），版本随构建自洽，同一判据 ④ 守 |
| 对拍语料（`corpus/`） | [corpus/README.md](corpus/README.md) | 各目录来源与生成方式（自写 / LLM 生成 / chibicc 移植）；`chibicc_port/` 的上游 MIT 义务在其逐文件头注 + 目录内 LICENSE.upstream 全文承接 |

## npm 依赖口径

`demo/package-lock.json` 全量 109 包中 93 个为 devDependencies（vite/svelte-check/oxlint 等构建工具链，不随产物分发、无声明义务）；真正打进产物的第三方包以**构建期模块表反查**为准（上表第二行）——lockfile 的 dev 标记不可作口径（`svelte` 在 devDependencies 但其运行时随编译进产物）。

## MoonBit 工具链与原生运行时层（2026-11-10 本机实证）

工具链（moonc/moon，安装器随附总声明 `~/.moon/CREDITS.md`）捆绑再分发三个第三方件：Binaryen（Apache-2.0）、tcc（LGPL-2.1）、simdutf（MIT）；另携带 why3（LGPL-2.1）。对本仓产物的逐项定性：

| 组件 | 是否进入本仓分发物 | 证据与边界 |
|:---|:---|:---|
| core 标准库（Apache-2.0 + NOTICE） | **是**（wasm/langpack 编译进产物随 Pages 分发） | `ENGINE-NOTICES.txt` 承接（见上表第三行） |
| IDEA 原生运行时（libmoonbitrun / bcheck / bt，Apache-2.0） | 仅原生 exe（本仓 CI 防线自用构建，**不发布原生二进制**） | exe 内 `moonbit`/`backtrace` 痕迹命中（符号对拍实测）；若未来分发原生 exe，须随附 Apache-2.0 全文 + core NOTICE（内容同 `ENGINE-NOTICES.txt`） |
| tcc / libtcc1（LGPL-2.1） | 否 | 仅 tcc 驱动链接（CREDITS「optionally used」）；本仓纪律锁 clang/MSVC 驱动；exe 内 `Bellard`/`__tcc` 痕迹 0 命中 |
| simdutf（MIT） | 否 | exe 内 simdutf 修饰符号（`_ZN7simdutf…`）0 命中——不随 clang 构建的原生产物分发 |
| why3（LGPL-2.1） | 否 | `moon prove` 本地工具，以子进程调用、不随产物再分发 |
| Binaryen / wasm-opt（Apache-2.0） | 否 | 构建期优化器（进程使用，输出无许可义务）；CI 以 pin 版本独立下载，不随产物分发 |

> 口径：符号对拍基于 clang release 构建（纪律 11）的 `cmd/vitro/vitro.exe`（2026-11-10）；原生运行时「不发布」的现行唯一例外 = GitHub Release `perf-cliff-repro-20260926`（内部复现 kit，构建于本节建账之前，已知边界）。
