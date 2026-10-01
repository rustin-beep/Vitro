/* logstat.c —— 日志分析器 + 环境信息工具
 *
 * 编译: gcc -Wall -O2 -o logstat logstat.c -lm
 * 用法:
 *   ./logstat <日志文件> [报告文件]    分析
 *   ./logstat -i                       交互模式
 *
 * 本段专为覆盖 csvq.c 尚未演示的标准库函数而写
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <ctype.h>
#include <time.h>
#include <errno.h>
#include <limits.h>
#include <assert.h>
#include <stdarg.h>
#include <stdbool.h>

#define MAX_MSG   256
#define MAX_LEVEL  16
#define MAX_CMD    64

/* ================================================================
 * 数据结构
 * ================================================================ */
typedef struct {
    time_t ts;
    char   level[MAX_LEVEL];
    char   message[MAX_MSG];
} Entry;

typedef struct {
    Entry *items;
    int    n, cap;
} List;

/* ================================================================
 * 工具函数
 * ================================================================ */
static void info(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    fputs("\033[1;36m[info]\033[0m ", stdout);
    vfprintf(stdout, fmt, ap);
    va_end(ap);
}

static void die(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    fputs("\033[1;31m[fail]\033[0m ", stderr);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
    exit(EXIT_FAILURE);
}

/* abort 的自然用法：内存分配失败无法继续 */
static void *xmalloc(size_t n) {
    void *p = malloc(n);
    if (!p) {
        fprintf(stderr, "内存分配失败 (%zu 字节)\n", n);
        abort();
    }
    return p;
}

static void list_push(List *L, const Entry *e) {
    if (L->n >= L->cap) {
        L->cap = L->cap ? L->cap * 2 : 64;
        L->items = (Entry *)realloc(L->items, (size_t)L->cap * sizeof(Entry));
        if (!L->items) die("realloc: %s", strerror(errno));
    }
    L->items[L->n++] = *e;
}

/* trim —— strspn / strcspn / memmove */
static char *trim(char *s) {
    if (!s || !*s) return s;
    size_t lead = strspn(s, " \t\r\n");
    size_t len  = strcspn(s + lead, "\r\n");
    memmove(s, s + lead, len);
    s[len] = '\0';
    return s;
}

/* extract_command —— strpbrk 找第一个分隔符 */
static void extract_command(const char *msg, char *out, size_t n) {
    const char *sep = strpbrk(msg, " \t:;,=");
    size_t len = sep ? (size_t)(sep - msg) : strlen(msg);
    if (len >= n) len = n - 1;
    memcpy(out, msg, len);
    out[len] = '\0';
}

/* path_join —— strncat / strncmp / strrchr */
static int path_join(char *out, size_t cap, const char *dir, const char *file) {
    /* strncmp 检查前缀 */
    if (strncmp(file, "/", 1) == 0) {
        /* 绝对路径，直接用 */
        strncpy(out, file, cap - 1);
        out[cap - 1] = '\0';
        return 0;
    }
    /* strrchr 找扩展名 */
    const char *ext = strrchr(file, '.');
    if (ext && !strcmp(ext, ".tmp")) {
        return -1;   /* 拒绝 .tmp 文件 */
    }

    strncpy(out, dir, cap - 1);
    out[cap - 1] = '\0';
    size_t used = strlen(out);
    strncat(out, "/",  cap - used - 1);
    used = strlen(out);
    strncat(out, file, cap - used - 1);
    return 0;
}

/* ================================================================
 * 时间：localtime / strftime / mktime / difftime
 * ================================================================ */
static void fmt_time(time_t t, char *out, size_t n) {
    struct tm *tm = localtime(&t);
    if (!tm) { snprintf(out, n, "(invalid)"); return; }
    strftime(out, n, "%Y-%m-%d %H:%M:%S %a", tm);
}

static time_t parse_ts(const char *s) {
    struct tm tm;
    memset(&tm, 0, sizeof(tm));
    int Y, M, D, h, m, sec;
    if (sscanf(s, "%d-%d-%d %d:%d:%d", &Y, &M, &D, &h, &m, &sec) != 6)
        return (time_t)-1;
    tm.tm_year = Y - 1900;
    tm.tm_mon  = M - 1;
    tm.tm_mday = D;
    tm.tm_hour = h;
    tm.tm_min  = m;
    tm.tm_sec  = sec;
    tm.tm_isdst = -1;
    return mktime(&tm);
}

/* ================================================================
 * 解析一行：sscanf / strtok_r / strchr
 * ================================================================ */
static int parse_line(const char *line, Entry *e) {
    if (*line != '[') return 0;
    const char *close = strchr(line, ']');
    if (!close) return 0;

    char ts_buf[32];
    size_t tl = (size_t)(close - line - 1);
    if (tl >= sizeof(ts_buf)) return 0;
    memcpy(ts_buf, line + 1, tl);
    ts_buf[tl] = '\0';

    e->ts = parse_ts(ts_buf);
    if (e->ts == (time_t)-1) return 0;

    char rest[512];
    strncpy(rest, close + 1, sizeof(rest) - 1);
    rest[sizeof(rest) - 1] = '\0';
    trim(rest);

    char *save = NULL;
    char *lv = strtok_r(rest, " \t", &save);
    if (!lv) return 0;
    strncpy(e->level, lv, MAX_LEVEL - 1);
    e->level[MAX_LEVEL - 1] = '\0';

    strncpy(e->message, save ? save : "", MAX_MSG - 1);
    e->message[MAX_MSG - 1] = '\0';
    trim(e->message);
    return 1;
}

/* ================================================================
 * 字符统计：全套 ctype
 * ================================================================ */
static void char_stats(const char *s, int *lo, int *up, int *pu, int *di,
                       int *sp, int *hx, int *pr, int *gr, int *ct) {
    *lo = *up = *pu = *di = *sp = *hx = *pr = *gr = *ct = 0;
    for (const unsigned char *p = (const unsigned char *)s; *p; p++) {
        if (islower(*p))   (*lo)++;
        if (isupper(*p))   (*up)++;
        if (ispunct(*p))   (*pu)++;
        if (isdigit(*p))   (*di)++;
        if (isspace(*p))   (*sp)++;
        if (isxdigit(*p))  (*hx)++;
        if (isprint(*p))   (*pr)++;
        if (isgraph(*p))   (*gr)++;
        if (iscntrl(*p))   (*ct)++;
    }
}

/* ================================================================
 * 数学：log2 / hypot / frexp / ldexp / modf / trunc
 *                copysign / fmax / fmin / atan2 / fmod
 * ================================================================ */
static double shannon_entropy(const int *counts, int n) {
    int total = 0;
    for (int i = 0; i < n; i++) total += counts[i];
    if (total == 0) return 0.0;

    double h = 0;
    for (int i = 0; i < n; i++) {
        if (counts[i] == 0) continue;
        double p = (double)counts[i] / total;
        h -= p * log2(p);
    }
    /* hypot 计算 √(h² + 0²) */
    double mag = hypot(h, 0.0);
    /* frexp / ldexp 归一化 */
    int e;
    double frac = frexp(mag, &e);
    return ldexp(frac, e);
}

static void demo_math(int total, int errors) {
    double ratio = (total > 0) ? (double)errors / total : 0;

    double ip;
    double fp = modf(ratio * 100.0, &ip);   /* modf：拆整数/小数 */
    double tr = trunc(ratio * 100.0);        /* trunc：截断 */

    double s = copysign(1.0, ratio);         /* copysign：带符号转移 */
    double a = fmax(ratio, 0.0);             /* fmax / fmin */
    double b = fmin(ratio, 1.0);
    double ang = atan2(ratio, 1.0 - ratio) * 180.0 / M_PI;
    double r = fmod((double)total, 10.0);    /* fmod：浮点取余 */

    printf("\n--- 数学分析 ---\n");
    printf("错误率:      %.4f%%\n", ratio * 100.0);
    printf("整数部分:    %.0f\n", ip);
    printf("小数部分:    %.6f\n", fp);
    printf("截断值:      %.0f\n", tr);
    printf("符号:        %+.0f\n", s);
    printf("上限 [0,1]:  %.6f\n", a);
    printf("下限 [0,1]:  %.6f\n", b);
    printf("极角:        %.2f°\n", ang);
    printf("总数 mod 10: %.0f\n", r);
}

/* ================================================================
 * 文件读取
 *   fread / fseek / ftell / rewind / fgetpos / fsetpos / ungetc / setvbuf
 * ================================================================ */
static char *slurp(const char *path, long *out_size) {
    FILE *fp = fopen(path, "rb");
    if (!fp) { perror(path); return NULL; }

    /* setvbuf：给这个文件独立的缓冲区 */
    static char buf[8192];
    setvbuf(fp, buf, _IOFBF, sizeof(buf));

    /* fseek + ftell 探测大小 */
    if (fseek(fp, 0, SEEK_END) != 0) { perror("fseek"); fclose(fp); return NULL; }
    long size = ftell(fp);
    if (size < 0) { perror("ftell"); fclose(fp); return NULL; }
    rewind(fp);

    /* fgetpos：记录当前偏移（此处为 0） */
    fpos_t pos;
    if (fgetpos(fp, &pos) != 0) { perror("fgetpos"); fclose(fp); return NULL; }

    /* fread 一次性读入 */
    char *text = (char *)xmalloc((size_t)size + 1);
    size_t got = fread(text, 1, (size_t)size, fp);
    text[got] = '\0';

    /* fsetpos + ungetc：回到开头读一个字符再退回去——演示用 */
    if (fsetpos(fp, &pos) == 0) {
        int c = fgetc(fp);
        if (c != EOF) ungetc(c, fp);
    }

    fclose(fp);
    *out_size = (long)got;
    return text;
}

/* ================================================================
 * 报告
 *   tmpfile / fgetc / putc / rename / remove
 * ================================================================ */
static int write_report(const char *final_path, const List *L) {
    /* tmpfile：先写到匿名的临时文件，统计消息总字节数 */
    FILE *tmp = tmpfile();
    if (tmp) {
        for (int i = 0; i < L->n; i++)
            fputs(L->items[i].message, tmp);
        fseek(tmp, 0, SEEK_END);
        long total_msg_bytes = ftell(tmp);
        printf("\n消息总字节: %ld\n", total_msg_bytes);
        fclose(tmp);
    }

    /* 再写到具名临时文件 */
    char tmp_path[256];
    snprintf(tmp_path, sizeof(tmp_path), "%s.tmp", final_path);

    FILE *out = fopen(tmp_path, "w");
    if (!out) { perror(tmp_path); return -1; }

    fprintf(out, "=== 日志分析报告 ===\n");
    fprintf(out, "条目数: %d\n\n", L->n);
    for (int i = 0; i < L->n; i++) {
        char tb[64];
        fmt_time(L->items[i].ts, tb, sizeof(tb));
        fprintf(out, "[%s] %-6s %s\n",
                tb, L->items[i].level, L->items[i].message);
    }
    fflush(out);
    fclose(out);

    /* rename 覆盖正式报告 */
    if (rename(tmp_path, final_path) != 0) {
        perror("rename");
        remove(tmp_path);
        return -1;
    }
    return 0;
}

/* ================================================================
 * 环境信息：getenv / atol / atof / labs
 * ================================================================ */
static void env_info(void) {
    printf("\n--- 环境信息 ---\n");
    const char *keys[] = { "USER", "USERNAME", "HOME", "TERM", NULL };
    for (int i = 0; keys[i]; i++) {
        const char *v = getenv(keys[i]);
        if (v) {
            printf("%-10s = %.60s%s\n", keys[i], v, strlen(v) > 60 ? "..." : "");
        }
    }

    const char *dbg = getenv("DEBUG_LEVEL");
    long lv = dbg ? atol(dbg) : 0;
    printf("DEBUG_LEVEL = %ld (|%ld| = %ld)\n", lv, lv, labs(lv));

    const char *thr = getenv("THRESHOLD");
    double t = thr ? atof(thr) : 0.5;
    printf("THRESHOLD   = %.4f\n", t);
}

/* ================================================================
 * 交互模式：scanf / getchar / puts / fflush / toupper
 * ================================================================ */
static void interactive_mode(void) {
    puts("\n进入交互模式。命令: help / time / env / date / upper / quit\n");

    char cmd[MAX_CMD];
    for (;;) {
        fputs("\033[1;33mlogstat>\033[0m ", stdout);
        fflush(stdout);

        if (scanf("%63s", cmd) != 1) break;

        /* getchar 丢弃行尾 */
        int c;
        while ((c = getchar()) != '\n' && c != EOF) { }

        if (!strcmp(cmd, "quit") || !strcmp(cmd, "q")) {
            puts("再见。");
            return;
        }
        if (!strcmp(cmd, "help") || !strcmp(cmd, "h")) {
            puts("  help    - 显示帮助");
            puts("  time    - 当前时间");
            puts("  env     - 环境变量");
            puts("  date    - 调用系统 date 命令");
            puts("  upper   - 下一行转大写");
            puts("  quit    - 退出");
            continue;
        }
        if (!strcmp(cmd, "time")) {
            char buf[64];
            fmt_time(time(NULL), buf, sizeof(buf));
            printf("现在: %s\n", buf);
            continue;
        }
        if (!strcmp(cmd, "env")) { env_info(); continue; }
        if (!strcmp(cmd, "date")) {
            /* system 演示 */
            int rc = system("date '+%Y-%m-%d %H:%M:%S %A' 2>/dev/null");
            if (rc != 0) printf("(系统没有 date 命令)\n");
            continue;
        }
        if (!strcmp(cmd, "upper")) {
            /* toupper 演示 */
            char line[128];
            if (fgets(line, sizeof(line), stdin)) {
                for (char *p = line; *p; p++)
                    *p = (char)toupper((unsigned char)*p);
                fputs(line, stdout);
            }
            continue;
        }
        printf("未知命令: %s\n", cmd);
    }
}

/* ================================================================
 * main
 * ================================================================ */
static void usage(const char *prog) {
    fprintf(stderr,
        "用法: %s <日志文件> [报告文件]\n"
        "      %s -i           交互模式\n",
        prog, prog);
}

int main(int argc, char **argv) {
    /* setvbuf：把 stdout 设为行缓冲 */
    static char obuf[4096];
    setvbuf(stdout, obuf, _IOLBF, sizeof(obuf));

    if (argc < 2) { usage(argv[0]); return EXIT_FAILURE; }

    if (!strcmp(argv[1], "-i")) {
        interactive_mode();
        return EXIT_SUCCESS;
    }

    const char *path   = argv[1];
    const char *report = (argc > 2) ? argv[2] : "report.txt";

    long size;
    char *text = slurp(path, &size);
    if (!text) return EXIT_FAILURE;
    info("读入 %ld 字节\n", size);

    /* 解析 */
    List L = {0};
    char *save = NULL;
    for (char *line = strtok_r(text, "\n", &save); line;
         line = strtok_r(NULL, "\n", &save)) {
        Entry e;
        if (parse_line(line, &e))
            list_push(&L, &e);
    }
    info("解析出 %d 条记录\n", L.n);

    if (L.n > 0) {
        time_t t0 = L.items[0].ts, t1 = L.items[0].ts;
        int errs = 0;
        for (int i = 0; i < L.n; i++) {
            if (L.items[i].ts < t0) t0 = L.items[i].ts;
            if (L.items[i].ts > t1) t1 = L.items[i].ts;
            if (!strcmp(L.items[i].level, "ERROR")) errs++;
        }

        char tb[64];
        fmt_time(t0, tb, sizeof(tb));
        printf("起始: %s\n", tb);
        fmt_time(t1, tb, sizeof(tb));
        printf("结束: %s\n", tb);
        printf("跨度: %.0f 秒\n", difftime(t1, t0));
        printf("错误: %d 条\n", errs);

        /* 命令提取演示：strpbrk */
        char cmd[64];
        extract_command(L.items[0].message, cmd, sizeof(cmd));
        printf("第一条消息的命令: %s\n", cmd);

        /* 字符统计 */
        int lo=0, up=0, pu=0, di=0, sp=0, hx=0, pr=0, gr=0, ct=0;
        for (int i = 0; i < L.n; i++)
            char_stats(L.items[i].message, &lo, &up, &pu, &di, &sp,
                       &hx, &pr, &gr, &ct);

        printf("\n--- 消息字符统计 ---\n");
        printf("小写 %d  大写 %d  标点 %d  数字 %d\n", lo, up, pu, di);
        printf("空白 %d  十六进制 %d  可打印 %d  可显示 %d  控制 %d\n",
               sp, hx, pr, gr, ct);

        int counts[] = { lo, up, pu, di, sp };
        printf("\n香农熵: %.4f\n", shannon_entropy(counts, 5));

        demo_math(L.n, errs);

        /* 报告 */
        char full_path[256];
        if (path_join(full_path, sizeof(full_path), ".", report) == 0)
            printf("\n报告路径: %s\n", full_path);
        if (write_report(full_path, &L) == 0)
            printf("报告已写入: %s\n", full_path);
    }

    free(L.items);
    free(text);
    return EXIT_SUCCESS;
}