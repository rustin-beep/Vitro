# Third-Party Notices（指针页）

本文件只做**指针**，不复制内容——各范围（分区）的第三方声明以所指文件为唯一真相源，避免双真相源漂移。

| 范围 | 声明位置 | 内容 |
|:---|:---|:---|
| MoonBit 引擎（`moonbit/`） | [moonbit/THIRD_PARTY.md](moonbit/THIRD_PARTY.md) | vendored 代码（moonbitlang/x fs/unicode 子集，Apache-2.0）来源表与本地修改声明（Apache-2.0 §4(b)） |
| 浏览器 demo 前端依赖（`demo/`） | 部署产物 `THIRD-PARTY-NOTICES.txt`（[在线页](https://rustin-beep.github.io/Vitro/)页脚有可见链接） | 打包进产物的第三方包（CodeMirror / Svelte runtime 等，MIT）版权与许可全文；vite 构建期由 **bundle 实际模块表**反查生成（`demo/vite.config.ts` 内联插件 `thirdPartyNotices`），发布面存在性由 `scripts/demo_assemble_check` 判据 ④（`--no-ts`）守 |
| 对拍语料（`corpus/`） | [corpus/README.md](corpus/README.md) | 各目录来源与生成方式（自写 / LLM 生成 / chibicc 移植）；`chibicc_port/` 的上游 MIT 义务在其逐文件头注承接 |

## npm 依赖口径

`demo/package-lock.json` 全量 109 包中 93 个为 devDependencies（vite/svelte-check/oxlint 等构建工具链，不随产物分发、无声明义务）；真正打进产物的第三方包以**构建期模块表反查**为准（上表第二行）——lockfile 的 dev 标记不可作口径（`svelte` 在 devDependencies 但其运行时随编译进产物）。
