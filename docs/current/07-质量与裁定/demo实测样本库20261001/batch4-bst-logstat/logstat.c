/* logstat.c —— 迷你日志分析器
 *
 * 用法: ./logstat <日志文件>
 *
 * 分析内容:
 *   1. 各级别日志数量（ERROR/WARN/INFO/DEBUG/TRACE）
 *   2. 按小时分布，找出高峰时段
 *   3. 出现频率最高的 Top N 错误消息
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#define LINE_MAX_LEN 1024
#define MSG_MAX_LEN  128
#define MAX_MSGS     64
#define TOP_N        5

/* 支持的日志级别，按严重程度从高到低 */
static const char *LEVELS[] = { "ERROR", "WARN", "INFO", "DEBUG", "TRACE" };
#define NUM_LEVELS ((int)(sizeof(LEVELS) / sizeof(LEVELS[0])))

/* ---------- 错误消息计数器 ---------- */
typedef struct {
    char msg[MSG_MAX_LEN];
    int  count;
} MsgCount;

static MsgCount g_errs[MAX_MSGS];
static int      g_errs_n = 0;

static void record_error(const char *msg)
{
    /* 去掉首尾空白和常见分隔符 */
    while (*msg && (isspace((unsigned char)*msg) ||
                    *msg == ':' || *msg == '-' || *msg == ']'))
        msg++;

    char buf[MSG_MAX_LEN];
    strncpy(buf, msg, MSG_MAX_LEN - 1);
    buf[MSG_MAX_LEN - 1] = '\0';

    int len = (int)strlen(buf);
    while (len > 0 && isspace((unsigned char)buf[len - 1]))
        buf[--len] = '\0';
    if (len == 0) return;

    /* 线性查找已有记录，够用 */
    for (int i = 0; i < g_errs_n; i++) {
        if (strcmp(g_errs[i].msg, buf) == 0) {
            g_errs[i].count++;
            return;
        }
    }
    if (g_errs_n < MAX_MSGS) {
        strncpy(g_errs[g_errs_n].msg, buf, MSG_MAX_LEN - 1);
        g_errs[g_errs_n].msg[MSG_MAX_LEN - 1] = '\0';
        g_errs[g_errs_n].count = 1;
        g_errs_n++;
    }
}

static int cmp_count_desc(const void *a, const void *b)
{
    const MsgCount *ma = (const MsgCount *)a;
    const MsgCount *mb = (const MsgCount *)b;
    return mb->count - ma->count;
}

/* ---------- 画一个横向条形图 ---------- */
static void bar(const char *label, int count, int max_count)
{
    const int WIDTH = 40;
    int n = (max_count > 0) ? (count * WIDTH / max_count) : 0;

    printf("  %-8s %6d |", label, count);
    for (int i = 0; i < n; i++) putchar('#');
    putchar('\n');
}

/* ---------- 主流程 ---------- */
int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "用法: %s <日志文件>\n", argv[0]);
        return 1;
    }

    FILE *fp = fopen(argv[1], "r");
    if (!fp) {
        perror("打开日志文件失败");
        return 1;
    }

    int  level_counts[NUM_LEVELS] = {0};
    int  hour_counts[24]          = {0};
    long total_lines              = 0;
    long matched_lines            = 0;

    char line[LINE_MAX_LEN];

    while (fgets(line, sizeof(line), fp)) {
        total_lines++;

        /* 判定级别：按严重度优先匹配，避免一行里出现多个关键词时误判 */
        int level = -1;
        for (int i = 0; i < NUM_LEVELS; i++) {
            if (strstr(line, LEVELS[i]) != NULL) {
                level = i;
                break;
            }
        }
        if (level < 0) continue;
        matched_lines++;
        level_counts[level]++;

        /* 提取时间戳中的小时。格式: YYYY-MM-DD HH:MM:SS */
        int y, mo, d, h, mi, s;
        if (sscanf(line, "%d-%d-%d %d:%d:%d", &y, &mo, &d, &h, &mi, &s) == 6) {
            if (h >= 0 && h < 24) hour_counts[h]++;
        }

        /* ERROR 级别：把后面的消息记下来 */
        if (level == 0) {
            const char *p = strstr(line, "ERROR");
            if (p) record_error(p + 5);
        }
    }
    fclose(fp);

    /* ---------- 输出报告 ---------- */
    printf("========== 日志分析报告 ==========\n");
    printf("文件:       %s\n", argv[1]);
    printf("总行数:     %ld\n", total_lines);
    printf("可识别行数: %ld", matched_lines);
    if (total_lines > 0)
        printf("  (%.1f%%)", 100.0 * matched_lines / total_lines);
    printf("\n\n");

    /* 1) 级别统计 */
    printf("---- 按级别 ----\n");
    int max_level = 0;
    for (int i = 0; i < NUM_LEVELS; i++)
        if (level_counts[i] > max_level) max_level = level_counts[i];
    for (int i = 0; i < NUM_LEVELS; i++)
        bar(LEVELS[i], level_counts[i], max_level);

    /* 2) 按小时分布 */
    printf("\n---- 按小时 ----\n");
    int max_hour = 0;
    for (int i = 0; i < 24; i++)
        if (hour_counts[i] > max_hour) max_hour = hour_counts[i];

    int peak_hour = -1;
    for (int i = 0; i < 24; i++) {
        if (hour_counts[i] == 0) continue;
        if (peak_hour < 0 || hour_counts[i] > hour_counts[peak_hour])
            peak_hour = i;
    }

    for (int i = 0; i < 24; i++) {
        if (hour_counts[i] == 0) continue;
        char label[8];
        snprintf(label, sizeof(label), "%02d:00", i);
        bar(label, hour_counts[i], max_hour);
    }
    if (peak_hour >= 0)
        printf("  >>> 高峰时段: %02d:00 (%d 条)\n", peak_hour, hour_counts[peak_hour]);

    /* 3) Top N 错误 */
    printf("\n---- Top %d 错误 ----\n", TOP_N);
    qsort(g_errs, g_errs_n, sizeof(MsgCount), cmp_count_desc);

    int show = (g_errs_n < TOP_N) ? g_errs_n : TOP_N;
    if (show == 0) {
        printf("  (没有 ERROR 级别日志，撒花 🎉)\n");
    } else {
        for (int i = 0; i < show; i++)
            printf("  %4d 次  %s\n", g_errs[i].count, g_errs[i].msg);
    }

    return 0;
}
