// 墙钟 stub（2026-10-02 deterministic 分叉销案接线）——**cmd/serve 与
// cmd/run 两份同源复制，改动连坐**（moon 的 native-stub 禁 ../ 路径）。
// 返回通道用两个 int（MoonBit FFI 数值返回实测仅 32 位通道可靠——
// json_parse 批实锤 Double/UInt64 双宽度返回为垃圾值；fs 包 fseek/is_null
// 的 int 返回为活先例），MoonBit 侧组 millis = secs*1000 + frac。
// oracle 对应物：vitro_vm 的 current_time_millis（墙钟毫秒）。
#include <stdint.h>
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
