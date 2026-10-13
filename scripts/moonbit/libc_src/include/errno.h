/* Vitro errno.h stub
 * 审阅 P2（2026-10-13）：宏值族对齐 UCRT（对拍基准 clang/UCRT 同值域；
 * 旧自定义连续编号 1/2/3... 与 host 硬写值互不一致——学生
 * if (errno == ERANGE) 永假。UCRT: EINVAL=22 ERANGE=34 EDOM=33
 * ENOENT=2 EACCES=13）
 */
extern int errno;

#define EINVAL 22
#define ERANGE 34
#define EDOM 33
#define ENOENT 2
#define EACCES 13
