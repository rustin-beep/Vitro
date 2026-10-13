/* 病 74 锚伴拥文件：与 p2d_parser_preproc_batch.c 同目录的同名本地头——
 * quote include 本地优先（2026-10-13 修复）须命中本文件（GUARD_P2D 宏）
 * 而非标准库存根 stddef.h（旧存根优先致本文件被静默遮蔽）。
 * 注意：本文件是**测试夹具**，与 corpus 的 clang_direct 扫描面共存——
 * 差分驱动按 .c 清单跑，.h 只被 include 解析不单独入账。 */
#define GUARD_P2D 1
