// 墙钟 stub（2026-10-02 deterministic 分叉销案接线）——**五份副本连坐**
//（2026-10-04 审阅 P2 补全：run/compile/step/vitro 四份逐字节同 + serve
// 为墙钟子集〔无 stdin 段〕单独演化；改动任一须全量同步——机判红线见
// scripts/moonbit/single_source 条目 host_clock_stub_copies）。
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
