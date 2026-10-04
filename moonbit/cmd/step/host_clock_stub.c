// 墙钟 stub（2026-10-02 deterministic 分叉销案接线）——**cmd/serve 与
// cmd/run 两份同源复制，改动连坐**（moon 的 native-stub 禁 ../ 路径）。
// 返回通道用两个 int（MoonBit FFI 数值返回实测仅 32 位通道可靠——
// json_parse 批实锤 Double/UInt64 双宽度返回为垃圾值；fs 包 fseek/is_null
// 的 int 返回为活先例），MoonBit 侧组 millis = secs*1000 + frac。
// oracle 对应物：vitro_vm 的 current_time_millis（墙钟毫秒）。
#include <stdint.h>
#include <stdio.h>
#ifdef _WIN32
#include <windows.h>
#else
#include <time.h>
#endif

int moonbit_vitro_clock_secs(void) {
#ifdef _WIN32
  FILETIME ft;
  ULARGE_INTEGER u;
  GetSystemTimeAsFileTime(&ft);
  u.LowPart = ft.dwLowDateTime;
  u.HighPart = ft.dwHighDateTime;
  // Windows epoch 1601-01-01 → Unix epoch 差 11644473600 秒；100ns 单位
  return (int)(u.QuadPart / 10000000ULL - 11644473600ULL);
#else
  struct timespec ts;
  clock_gettime(CLOCK_REALTIME, &ts);
  return (int)ts.tv_sec;
#endif
}

int moonbit_vitro_clock_millis_frac(void) {
#ifdef _WIN32
  FILETIME ft;
  ULARGE_INTEGER u;
  GetSystemTimeAsFileTime(&ft);
  u.LowPart = ft.dwLowDateTime;
  u.HighPart = ft.dwHighDateTime;
  return (int)((u.QuadPart / 10000ULL) % 1000ULL);
#else
  struct timespec ts;
  clock_gettime(CLOCK_REALTIME, &ts);
  return (int)(ts.tv_nsec / 1000000);
#endif
}

// stdin 全量读取（#37 批③ `-` 源码通道）——UTF-8 原始字节进 Bytes
//（moonbit_bytes_t 自带 length，MoonBit 侧 b.length() 取——**无出参**：
// MoonBit FFI 传 Int 按值，C 侧 int* 出参签名不匹配会解引用崩，实测
// 实锤）。UTF-8→String 解码在 MoonBit 侧 lib 完成（纯逻辑可 wbtest）。
// 与 cmd/vitro 的 host_clock_stub.c 同源复制连坐（native-stub 禁 ../）。
#include "moonbit.h"
MOONBIT_FFI_EXPORT moonbit_bytes_t moonbit_vitro_read_stdin_bytes(void) {
  size_t cap = 4096, len = 0;
  char* buf = (char*)malloc(cap);
  if (!buf) {
    return moonbit_make_bytes(0, 0);
  }
  int c;
  while ((c = getchar()) != EOF) {
    if (len + 1 >= cap) {
      cap *= 2;
      buf = (char*)realloc(buf, cap);
      if (!buf) {
        return moonbit_make_bytes(0, 0);
      }
    }
    buf[len++] = (char)c;
  }
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)len, 0);
  uint8_t* dst = (uint8_t*)out;
  for (size_t i = 0; i < len; i++) {
    dst[i] = (uint8_t)buf[i];
  }
  free(buf);
  return out;
}
