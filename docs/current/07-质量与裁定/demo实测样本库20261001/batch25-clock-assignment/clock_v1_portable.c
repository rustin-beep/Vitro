/* 控制台数字时钟大作业 —— v1 可移植版（Vitro 沙箱可跑）
 * 基础① 实时时间显示（24/12 小时制 AM/PM）  基础② 刷新（见下注）  基础③ 闹钟设置
 * 进阶① 闹钟提醒  进阶② 文件持久化  进阶③b 多闹钟管理
 *
 * 与 v0 教材原味版的差异（沙箱适配点，真机版可换回）：
 *  - 无 windows.h / Sleep()：沙箱无 sleep 函数、clock() 恒 0 不推进、
 *    忙等延时撞步数护栏——500ms 自动刷新改为固定 3 帧连打演示；
 *    真机版把 DEMO 帧循环换成 while(1) + Sleep(500) + system("cls") 即可
 *  - 无 localtime/struct tm：time(NULL) 秒数 + 东八区偏移手动分解（教学：自己算时分秒）
 *  - stdio 存根无 fscanf：文件解析改 fgets + sscanf
 */
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#define ALARM_MAX 10
#define DEMO_FRAMES 3
#define TZ_OFFSET_SEC (8 * 3600)   /* 东八区：沙箱无 localtime，手动换算 */

typedef struct {
    int hour;
    int minute;
    int second;
} ClockTime;

typedef struct {
    int hour;
    int minute;
} Alarm;

Alarm alarms[ALARM_MAX];
int alarm_count = 0;

/* ---------- 点阵字形（3x5） ---------- */
static const char *DIGITS[10][5] = {
    {"***", "* *", "* *", "* *", "***"}, /* 0 */
    {"  *", "  *", "  *", "  *", "  *"}, /* 1 */
    {"***", "  *", "***", "*  ", "***"}, /* 2 */
    {"***", "  *", "***", "  *", "***"}, /* 3 */
    {"* *", "* *", "***", "  *", "  *"}, /* 4 */
    {"***", "*  ", "***", "  *", "***"}, /* 5 */
    {"***", "*  ", "***", "* *", "***"}, /* 6 */
    {"***", "  *", "  *", "  *", "  *"}, /* 7 */
    {"***", "* *", "***", "* *", "***"}, /* 8 */
    {"***", "* *", "***", "  *", "***"}  /* 9 */
};

/* ---------- time_t -> 东八区 时:分:秒 ---------- */
void to_local(long long raw, ClockTime *out) {
    long long day_sec = (raw + TZ_OFFSET_SEC) % 86400;
    out->hour = (int)(day_sec / 3600);
    out->minute = (int)(day_sec % 3600 / 60);
    out->second = (int)(day_sec % 60);
}

/* ---------- 进阶② 持久化 ---------- */
void save_alarms(void) {
    FILE *fp = fopen("alarms.txt", "w");
    if (fp == NULL) {
        printf("[warn] alarms.txt cannot be written\n");
        return;
    }
    for (int i = 0; i < alarm_count; i++)
        fprintf(fp, "%d %d\n", alarms[i].hour, alarms[i].minute);
    fclose(fp);
}

void load_alarms(void) {
    FILE *fp = fopen("alarms.txt", "r");
    if (fp == NULL) return;
    char line[64];
    while (alarm_count < ALARM_MAX && fgets(line, 64, fp) != NULL) {
        int h = -1, m = -1;
        if (sscanf(line, "%d %d", &h, &m) == 2 && h >= 0 && h < 24 && m >= 0 && m < 60) {
            alarms[alarm_count].hour = h;
            alarms[alarm_count].minute = m;
            alarm_count++;
        }
    }
    fclose(fp);
}

/* ---------- 进阶① 闹钟匹配 ---------- */
int check_alarm(int hour, int minute) {
    for (int i = 0; i < alarm_count; i++)
        if (alarms[i].hour == hour && alarms[i].minute == minute)
            return 1;
    return 0;
}

/* ---------- 点阵渲染 ---------- */
void print_digit(int d, int row) {
    if (d >= 0 && d <= 9)
        printf("%s", DIGITS[d][row]);
    else
        printf("   ");
}

void print_time_row(int h, int m, int s, int row) {
    print_digit(h / 10, row); printf(" ");
    print_digit(h % 10, row); printf("   ");
    print_digit(m / 10, row); printf(" ");
    print_digit(m % 10, row); printf("   ");
    print_digit(s / 10, row); printf(" ");
    print_digit(s % 10, row); printf("\n");
}

/* ---------- 基础① 界面一帧 ---------- */
void draw_frame(int h24, int min, int sec, int mode12, int frame_no) {
    int h = h24;
    const char *ampm = "";
    if (mode12 == 12) {
        ampm = (h24 >= 12) ? "PM" : "AM";
        h = h24 % 12;
        if (h == 0) h = 12;
    }
    printf("\n--- refresh %d ---\n", frame_no + 1);   /* 真机版此处 system("cls") */
    printf("==== Console Digital Clock ====\n");
    for (int row = 0; row < 5; row++)
        print_time_row(h, min, sec, row);
    printf("        %02d:%02d:%02d %s\n", h, min, sec, ampm);
    printf("alarms: %d\n", alarm_count);
    printf("===============================\n");
}

int main(void) {
    load_alarms();   /* 进阶②：启动加载 */

    int mode12 = 0;
    printf("12-hour mode? (1=yes / 0=no): ");
    if (scanf("%d", &mode12) != 1) mode12 = 0;

    int n_new = 0;
    printf("how many alarms to set? ");
    if (scanf("%d", &n_new) != 1) n_new = 0;
    for (int i = 0; i < n_new && alarm_count < ALARM_MAX; i++) {
        printf("alarm %d (hour minute): ", i + 1);
        int h, m;
        if (scanf("%d %d", &h, &m) == 2 && h >= 0 && h < 24 && m >= 0 && m < 60) {
            alarms[alarm_count].hour = h;
            alarms[alarm_count].minute = m;
            alarm_count++;
        }
    }
    save_alarms();   /* 进阶②：设置即保存 */

    /* 基础② 演示：沙箱无延时手段，固定 3 帧连打；真机版 while(1)+Sleep(500) */
    for (int frame = 0; frame < DEMO_FRAMES; frame++) {
        time_t raw;
        time(&raw);
        ClockTime now;
        to_local(raw, &now);

        draw_frame(now.hour, now.minute, now.second, mode12, frame);

        if (check_alarm(now.hour, now.minute))
            printf(">>> ALARM! It is %02d:%02d now! <<<\n", now.hour, now.minute);
    }
    printf("demo done\n");
    return 0;
}
