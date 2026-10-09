/* 控制台数字时钟大作业 —— v0 教材原味版（Windows 风格）
 * 基础① 实时时间显示（24/12 小时制 AM/PM，时:分:秒）
 * 基础② 500ms 刷新
 * 基础③ 闹钟设置（小时+分钟）
 * 进阶① 闹钟提醒    进阶② 文件持久化    进阶③b 多闹钟管理
 */
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <windows.h>    /* Sleep() / system("cls") —— Windows 教材标配 */

#define ALARM_MAX 10
#define REFRESH_MS 500

typedef struct {
    int hour;
    int minute;
} Alarm;

Alarm alarms[ALARM_MAX];
int alarm_count = 0;

/* ---------- 点阵字形（3x5） ---------- */
const char *DIGITS[10][5] = {
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
    int h, m;
    while (alarm_count < ALARM_MAX && fscanf(fp, "%d %d", &h, &m) == 2) {
        alarms[alarm_count].hour = h;
        alarms[alarm_count].minute = m;
        alarm_count++;
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
void draw_frame(int h24, int min, int sec, int mode12) {
    int h = h24;
    const char *ampm = "";
    if (mode12 == 12) {
        ampm = (h24 >= 12) ? "PM" : "AM";
        h = h24 % 12;
        if (h == 0) h = 12;
    }
    system("cls");   /* Windows 清屏 */
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
        if (scanf("%d %d", &alarms[alarm_count].hour, &alarms[alarm_count].minute) == 2)
            alarm_count++;
    }
    save_alarms();   /* 进阶②：设置即保存 */

    /* 演示跑 3 帧便于验收；作业实际提交为 while(1) 常驻刷新 */
    for (int frame = 0; frame < 3; frame++) {
        time_t now = time(NULL);
        struct tm *t = localtime(&now);   /* 标准取本地时间 */
        if (t == NULL) break;
        int h24 = t->tm_hour, min = t->tm_min, sec = t->tm_sec;

        draw_frame(h24, min, sec, mode12);

        if (check_alarm(h24, min))
            printf(">>> ALARM! It is %02d:%02d now! <<<\n", h24, min);

        Sleep(REFRESH_MS);   /* 基础②：500ms 刷新 */
    }
    printf("demo done\n");
    return 0;
}
