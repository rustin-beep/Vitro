# frozen-oracle-snapshot —— Rust oracle 全文产物快照（工序③固化考古分支）

> **这是什么**：工序③固化（2026-10-05）的**全文形态**快照——五驱动（vm/lexer/parser/codegen/typeck）对 603 例四语料（baseline 367 + knr 81 + leetcode 138 + gap 17）+ 病态 12 + 合法深 2 + threshold 23 的 oracle 侧产物全文。master 上只入库聚合 digest 清单（每驱动一份），本分支是 digest 的**内容兜底**——修复批溯源「oracle 当时具体产了什么」时显式拉取：`git fetch origin frozen-oracle-snapshot`（默认 clone 不拉本分支）。

> **生成源**：master 分支 `b9ddadd` 时的 `native/target/release/vitro_cli.exe`（Rust oracle @ tag `rust-oracle-freeze` 冻结区源码构建）。重建路径：`git checkout` 冻结区源码 → `cargo build --release --bin vitro_cli` → 各驱动 `--freeze`。

> **形态注意**：codegen golden 为 **canonicalize 归一后产物**（oracle dump-compile 原文非确定——单文件双跑不一致，Rust 侧迭代序入产物；对拍语义 = 归一后逐字节，见 master 冻结资产清单）。vm_diff golden 每例 JSON 含原始 stdout + 退出码 + 映像 gzip(base64)。

> **目录**：`golden/<driver>/<corpus>/<case>.json`（vm/lexer 为各自产物形态；`_manifest.json` 锚语料源 sha）。
