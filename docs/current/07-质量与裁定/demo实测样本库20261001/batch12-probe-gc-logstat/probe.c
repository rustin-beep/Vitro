/* probe.c —— C 类型 / 浮点 / 位模式探测工具
 *
 * 编译: gcc -Wall -O2 -o probe probe.c -lm
 * 运行: ./probe
 *
 * 本段覆盖前面几段没碰过的:
 *   limits.h 所有边界宏
 *   float.h  所有浮点属性
 *   stdint.h 全部定宽类型 + printf 宏
 *   stddef.h offsetof / ptrdiff_t / size_t / NULL
 *   errno.h  EDOM / ERANGE / EINVAL + strerror
 *   stdarg.h va_copy
 *   math.h   tgamma / lgamma / erf / erfc / expm1 / log1p
 *            nextafter / scalbn / frexp / ldexp
 *   time.h   gmtime / asctime / ctime
 *   assert.h 内部不变式
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdint.h>
#include <limits.h>
#include <float.h>
#include <stddef.h>
#include <errno.h>
#include <assert.h>
#include <stdarg.h>
#include <time.h>
#include <stdbool.h>

/* ================================================================
 * 1. limits.h —— 所有整数边界宏
 * ================================================================ */
static void show_int_limits(void)
{
    printf("\n=== 整数边界 (limits.h) ===\n");
    printf("CHAR_BIT   = %d     一个字节的位数\n", CHAR_BIT);
    printf("SCHAR_MIN  = %d\n", SCHAR_MIN);
    printf("SCHAR_MAX  = %d\n", SCHAR_MAX);
    printf("UCHAR_MAX  = %u\n", (unsigned)UCHAR_MAX);
    printf("CHAR_MIN   = %d     （char 是有符号还是无符号，看这里）\n", CHAR_MIN);
    printf("CHAR_MAX   = %d\n", CHAR_MAX);
    printf("SHRT_MIN   = %d\n", SHRT_MIN);
    printf("SHRT_MAX   = %d\n", SHRT_MAX);
    printf("USHRT_MAX  = %u\n", (unsigned)USHRT_MAX);
    printf("INT_MIN    = %d\n", INT_MIN);
    printf("INT_MAX    = %d\n", INT_MAX);
    printf("UINT_MAX   = %u\n", UINT_MAX);
    printf("LONG_MIN   = %ld\n", LONG_MIN);
    printf("LONG_MAX   = %ld\n", LONG_MAX);
    printf("ULONG_MAX  = %lu\n", ULONG_MAX);
    printf("LLONG_MIN  = %lld\n", LLONG_MIN);
    printf("LLONG_MAX  = %lld\n", LLONG_MAX);
    printf("ULLONG_MAX = %llu\n", ULLONG_MAX);
}

/* ================================================================
 * 2. stdint.h —— 定宽类型 + INT*_C 宏
 * ================================================================ */
static void show_stdint_sizes(void)
{
    printf("\n=== 定宽整数类型 (stdint.h) ===\n");

    printf("int8_t   : %zu 字节  范围 [%d, %d]\n",
           sizeof(int8_t), INT8_MIN, INT8_MAX);
    printf("uint8_t  : %zu 字节  最大值 %u\n",
           sizeof(uint8_t), (unsigned)UINT8_MAX);
    printf("int16_t  : %zu 字节  范围 [%d, %d]\n",
           sizeof(int16_t), INT16_MIN, INT16_MAX);
    printf("uint16_t : %zu 字节  最大值 %u\n",
           sizeof(uint16_t), (unsigned)UINT16_MAX);
    printf("int32_t  : %zu 字节  范围 [%d, %d]\n",
           sizeof(int32_t), INT32_MIN, INT32_MAX);
    printf("uint32_t : %zu 字节  最大值 %u\n",
           sizeof(uint32_t), (unsigned)UINT32_MAX);
    printf("int64_t  : %zu 字节  范围 [%lld, %lld]\n",
           sizeof(int64_t), (long long)INT64_MIN, (long long)INT64_MAX);
    printf("uint64_t : %zu 字节  最大值 %llu\n",
           sizeof(uint64_t), (unsigned long long)UINT64_MAX);
    printf("intptr_t : %zu 字节  能装下一个指针\n", sizeof(intptr_t));
    printf("size_t   : %zu 字节\n", sizeof(size_t));
    printf("ptrdiff_t: %zu 字节\n", sizeof(ptrdiff_t));

    /* INT64_C: 保证字面量至少 64 位，跨平台安全 */
    int64_t big = INT64_C(9000000000000000000);
    printf("INT64_C(9000000000000000000) = %lld\n", (long long)big);
}

/* ================================================================
 * 3. 位模式转储：union 类型双关
 * ================================================================ */
static void dump_bits(const void *data, size_t n)
{
    const uint8_t *p = (const uint8_t *)data;
    for (size_t i = 0; i < n; i++) {
        printf("    [%zu] 0x%02X = ", i, p[i]);
        for (int b = 7; b >= 0; b--)
            putchar((p[i] >> b) & 1 ? '1' : '0');
        putchar('\n');
    }
}

static void show_bit_patterns(void)
{
    printf("\n=== IEEE 754 位模式 ===\n");

    union { float    f; uint32_t u; } fu;
    union { double   d; uint64_t u; } du;

    fu.f = 3.14f;
    printf("\nfloat 3.14f   →  0x%08X\n", fu.u);
    dump_bits(&fu, sizeof(fu));

    du.d = 3.14;
    printf("\ndouble 3.14   →  0x%016llX\n",
           (unsigned long long)du.u);
    dump_bits(&du, sizeof(du));

    /* -0.0 的位模式：只是符号位不同 */
    du.d = -0.0;
    printf("\ndouble -0.0   →  0x%016llX （只有最高位不同）\n",
           (unsigned long long)du.u);
}

/* ================================================================
 * 4. float.h —— 浮点属性全表
 * ================================================================ */
static void show_float_limits(void)
{
    printf("\n=== 浮点边界 (float.h) ===\n");
    printf("FLT_RADIX       = %d     指数基数\n", FLT_RADIX);
    printf("FLT_MANT_DIG    = %d      float 有效位数\n", FLT_MANT_DIG);
    printf("DBL_MANT_DIG    = %d      double 有效位数\n", DBL_MANT_DIG);
    printf("FLT_DIG         = %d      float 十进制有效位\n", FLT_DIG);
    printf("DBL_DIG         = %d      double 十进制有效位\n", DBL_DIG);
    printf("FLT_EPSILON     = %e\n", FLT_EPSILON);
    printf("DBL_EPSILON     = %e\n", DBL_EPSILON);
    printf("FLT_MIN         = %e      最小正规格化 float\n", FLT_MIN);
    printf("FLT_MAX         = %e\n", FLT_MAX);
    printf("DBL_MIN         = %e\n", DBL_MIN);
    printf("DBL_MAX         = %e\n", DBL_MAX);
    printf("FLT_MIN_EXP     = %d\n", FLT_MIN_EXP);
    printf("FLT_MAX_EXP     = %d\n", FLT_MAX_EXP);
    printf("FLT_MIN_10_EXP  = %d\n", FLT_MIN_10_EXP);
    printf("FLT_MAX_10_EXP  = %d\n", FLT_MAX_10_EXP);
    printf("DBL_MIN_10_EXP  = %d\n", DBL_MIN_10_EXP);
    printf("DBL_MAX_10_EXP  = %d\n", DBL_MAX_10_EXP);
}

/* ================================================================
 * 5. 拆解一个 double：frexp/ldexp + 手动位提取
 * ================================================================ */
static void decompose_double(double x)
{
    int exp;
    double mant = frexp(x, &exp);

    union { double d; uint64_t u; } du;
    du.d = x;
    uint64_t sign     = (du.u >> 63) & 1;
    int      raw_exp  = (int)((du.u >> 52) & 0x7FF);
    uint64_t raw_mant = du.u & 0xFFFFFFFFFFFFFULL;

    printf("  x           = %.17g\n", x);
    printf("  符号位      = %llu\n", (unsigned long long)sign);
    printf("  原始指数    = %d （减偏置 1023 → %d）\n",
           raw_exp, raw_exp - 1023);
    printf("  原始尾数    = 0x%013llX\n", (unsigned long long)raw_mant);
    printf("  frexp       = mant=%.17g, exp=%d\n", mant, exp);
    printf("  ldexp 还原  = %.17g\n", ldexp(mant, exp));
    printf("  nextafter(↑) = %.17g\n", nextafter(x, INFINITY));
    printf("  nextafter(↓) = %.17g\n", nextafter(x, -INFINITY));
    printf("  scalbn(x, 3) = %.17g （= x × 2³）\n", scalbn(x, 3));
}

/* ================================================================
 * 6. stddef.h —— offsetof / ptrdiff_t / NULL
 * ================================================================ */
struct Sample {
    char   a;
    int    b;
    double c;
    char   d[16];
};

static void show_layout(void)
{
    printf("\n=== 结构体布局 (stddef.h) ===\n");
    printf("sizeof(struct Sample) = %zu\n", sizeof(struct Sample));
    printf("offsetof(a) = %zu\n", offsetof(struct Sample, a));
    printf("offsetof(b) = %zu\n", offsetof(struct Sample, b));
    printf("offsetof(c) = %zu\n", offsetof(struct Sample, c));
    printf("offsetof(d) = %zu\n", offsetof(struct Sample, d));
    printf("（间隙就是编译器插入的对齐填充）\n");

    /* ptrdiff_t: 两个指针相减的类型 */
    int arr[10];
    ptrdiff_t diff = &arr[8] - &arr[2];
    printf("\n&arr[8] - &arr[2] = %td （ptrdiff_t）\n", diff);

    /* NULL 来自 stddef.h */
    void *np = NULL;
    printf("NULL = %p\n", np);
}

/* ================================================================
 * 7. errno.h —— 主动触发各种错误
 * ================================================================ */
static void show_errno(void)
{
    printf("\n=== errno 触发 (errno.h) ===\n");

    /* EDOM: 数学函数定义域错误 */
    errno = 0;
    double r1 = sqrt(-1.0);
    printf("sqrt(-1.0)  = %.0f   errno=%d (%s)\n",
           r1, errno, errno == EDOM ? "EDOM" : "?");

    errno = 0;
    double r2 = log(-1.0);
    printf("log(-1.0)   = %.0f   errno=%d (%s)\n",
           r2, errno, errno == EDOM ? "EDOM" : "?");

    /* ERANGE: 结果超出范围 */
    errno = 0;
    double r3 = exp(1000.0);
    printf("exp(1000)   = %g   errno=%d (%s)\n",
           r3, errno, errno == ERANGE ? "ERANGE" : "?");

    /* strtol 溢出 */
    errno = 0;
    long v = strtol("99999999999999999999999", NULL, 10);
    printf("strtol(巨大) = %ld   errno=%d (%s)\n",
           v, errno, errno == ERANGE ? "ERANGE" : "?");

    printf("\n常见 errno 值:\n");
    printf("  EDOM   = %d  (%s)\n", EDOM,   strerror(EDOM));
    printf("  ERANGE = %d  (%s)\n", ERANGE, strerror(ERANGE));
    printf("  EINVAL = %d  (%s)\n", EINVAL, strerror(EINVAL));
}

/* ================================================================
 * 8. stdarg.h —— va_copy
 * ================================================================ */
static void sum_and_count(int *out_nonzero, double *out_sum, int n, ...)
{
    va_list ap, ap2;
    va_start(ap, n);
    va_copy(ap2, ap);   /* 复制一份，两个指针能独立走 */

    double sum = 0;
    for (int i = 0; i < n; i++)
        sum += va_arg(ap, double);

    int nz = 0;
    for (int i = 0; i < n; i++)
        if (va_arg(ap2, double) != 0) nz++;

    va_end(ap);
    va_end(ap2);

    *out_nonzero = nz;
    *out_sum     = sum;
}

static void show_va_copy(void)
{
    printf("\n=== va_copy ===\n");
    int    nz;
    double sum;
    sum_and_count(&nz, &sum, 5, 1.5, 0.0, 2.5, 0.0, 3.0);
    printf("传入: 1.5, 0, 2.5, 0, 3.0\n");
    printf("非零个数 = %d   总和 = %.4f\n", nz, sum);
}

/* ================================================================
 * 9. math.h —— 前面没用过的特殊函数
 * ================================================================ */
static void show_math_special(void)
{
    printf("\n=== 特殊数学函数 ===\n");

    /* Γ 函数：阶乘的解析延拓 */
    printf("Gamma 函数（tgamma）:\n");
    for (int i = 1; i <= 6; i++)
        printf("  tgamma(%d) = %10.5f   （= %d!）\n",
               i, tgamma((double)i), i - 1);
    printf("  lgamma(10) = %10.5f   （= ln(9!)）\n", lgamma(10.0));

    /* 误差函数：正态分布的核心 */
    printf("\n误差函数:\n");
    printf("  erf(1.0)  = %.10f\n", erf(1.0));
    printf("  erfc(1.0) = %.10f   （erfc = 1 - erf）\n", erfc(1.0));
    printf("  erf(0.5)  = %.10f\n", erf(0.5));

    /* expm1 / log1p：小量时更精确 */
    double x = 1e-12;
    printf("\n小量时的精度（x = %g）:\n", x);
    printf("  exp(x) - 1  = %.20e\n", exp(x) - 1);
    printf("  expm1(x)    = %.20e   ← 更精确\n", expm1(x));
    printf("  log(1 + x)  = %.20e\n", log(1 + x));
    printf("  log1p(x)    = %.20e   ← 更精确\n", log1p(x));

    /* nextafter / scalbn */
    double y = 1.0;
    double nxt = nextafter(y, 2.0);
    printf("\n浮点邻居:\n");
    printf("  nextafter(1.0, 2.0)       = %.20e\n", nxt);
    printf("  nextafter(1.0, 2.0) - 1.0 = %.20e\n", nxt - 1.0);
    printf("  DBL_EPSILON               = %.20e   ← 相等\n", DBL_EPSILON);

    printf("\nscalbn(1.5, 10) = %g  （= 1.5 × 2¹⁰）\n", scalbn(1.5, 10));
}

/* ================================================================
 * 10. time.h —— gmtime / asctime / ctime
 * ================================================================ */
static void show_time_extra(void)
{
    printf("\n=== 时间 (gmtime / asctime / ctime) ===\n");

    time_t now = time(NULL);

    /* gmtime: time_t → UTC 的 struct tm */
    struct tm *utc = gmtime(&now);
    char buf[64];
    strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S UTC", utc);
    printf("UTC:        %s\n", buf);

    /* asctime: struct tm → 固定格式字符串（自带 \n） */
    printf("asctime:    %s", asctime(utc));

    /* ctime: time_t → 本地时间字符串（自带 \n） */
    printf("ctime:      %s", ctime(&now));

    /* 有趣的时刻 */
    time_t epoch = 0;
    printf("Unix 纪元:  %s", ctime(&epoch));

    /* 2038 问题：32 位 time_t 的临界值 */
    time_t y2038 = (time_t)2147483647L;
    printf("2038 临界:  %s", ctime(&y2038));
}

/* ================================================================
 * 11. assert.h —— 内部不变式
 * ================================================================ */
static int is_power_of_two(uint32_t x)
{
    /* 内部合同：调用者必须传正数 */
    assert(x > 0);

    /* 2 的幂：二进制里只有一个 1 */
    return (x & (x - 1)) == 0;
}

static void show_assert(void)
{
    printf("\n=== assert（内部不变式） ===\n");
    uint32_t cases[] = { 1, 2, 4, 8, 16, 32, 64, 128 };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++)
        printf("  is_power_of_two(%3u) = %s\n",
               cases[i], is_power_of_two(cases[i]) ? "是" : "否");

    printf("（assert 用 -DNDEBUG 编译时会被完全移除，零开销）\n");
}

/* ================================================================
 * main
 * ================================================================ */
int main(void)
{
    printf("\033[1;36m");
    printf("╔══════════════════════════════════════════════════╗\n");
    printf("║     C 类型 / 浮点 / 位模式 探测工具              ║\n");
    printf("╚══════════════════════════════════════════════════╝\n");
    printf("\033[0m");

    show_int_limits();
    show_stdint_sizes();
    show_bit_patterns();
    show_float_limits();

    printf("\n=== IEEE 754 分解 ===\n");
    decompose_double(1.0);
    putchar('\n');
    decompose_double(-3.75);
    putchar('\n');
    decompose_double(0.1);   /* 不能精确表示 */

    show_layout();
    show_errno();
    show_va_copy();
    show_math_special();
    show_time_extra();
    show_assert();

    printf("\n完成。\n");
    return EXIT_SUCCESS;
}
