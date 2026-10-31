/* abort_probe 桩专用假 moonbit.h（#391 审阅 P1-2/P2-1，2026-10-31）：
 * 本目录无 moon runtime 头——stub 的 #include "moonbit.h"（引号形式）先搜
 * 本目录即命中此件。只须让 stdout_stub.c 编译通过：MOONBIT_FFI_EXPORT 展开为
 * 空（桩不做符号导出面）、moonbit_bytes_t 假型 + Moonbit_array_length 恒 0
 * （桩不调 write_stdout——main 直接 printf 进 CRT 缓冲模拟「panic 前缓冲
 * 有货」）。锚的真实对象 = ensure_binary_mode 挂的 SIGABRT handler（真源
 * 编入桩，单源锁——stub 漂移即锚红）。 */
#ifndef VITRO_ABORT_PROBE_MOONBIT_H
#define VITRO_ABORT_PROBE_MOONBIT_H
#define MOONBIT_FFI_EXPORT
typedef void *moonbit_bytes_t;
#define Moonbit_array_length(b) ((int32_t)0)
#endif
