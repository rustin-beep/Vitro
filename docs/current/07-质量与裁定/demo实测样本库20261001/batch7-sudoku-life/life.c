/* life.c —— 康威生命游戏（不依赖 <signal.h>）
 *
 * 编译: gcc -Wall -O2 -o life life.c
 * 运行: ./life [图案] [延迟ms]
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* ================================================================
 * 替代 <signal.h>
 *
 *   signal() 是 libc 里的函数，只是头文件没收录。
 *   我们只需要它的原型 + 两个信号编号常量。
 *   SIGINT=2、SIGTERM=15 在几乎所有 POSIX 系统上都是固定值，
 *   Linux / macOS / BSD 通用。
 * ================================================================ */
typedef void (*SignalHandler)(int);

extern SignalHandler signal(int signum, SignalHandler handler);

#define SIGINT   2    /* Ctrl+C */
#define SIGTERM 15    /* kill 默认信号 */

/* ================================================================
 * 游戏本体
 * ================================================================ */
#define W 80
#define H 30

static char g_cur[H][W];
static char g_nxt[H][W];
static int  g_age[H][W];

static void msleep(int ms)
{
    struct timespec ts;
    ts.tv_sec  = ms / 1000;
    ts.tv_nsec = (ms % 1000) * 1000000L;
    nanosleep(&ts, NULL);
}

static int neighbors(int x, int y)
{
    int n = 0;
    for (int dy = -1; dy <= 1; dy++)
        for (int dx = -1; dx <= 1; dx++) {
            if (!dx && !dy) continue;
            n += g_cur[(y + dy + H) % H][(x + dx + W) % W];
        }
    return n;
}

static void step(void)
{
    for (int y = 0; y < H; y++)
        for (int x = 0; x < W; x++) {
            int n = neighbors(x, y);
            int a = g_cur[y][x];
            int s = a ? (n == 2 || n == 3) : (n == 3);

            g_nxt[y][x] = (char)s;
            g_age[y][x] = s ? (a ? g_age[y][x] + 1 : 0) : 0;
        }
    memcpy(g_cur, g_nxt, sizeof(g_cur));
}

static void draw(void)
{
    static char buf[H * (W * 20 + 16)];
    char *p = buf;
    p += sprintf(p, "\033[H");

    const char *last_color = NULL;

    for (int y = 0; y < H; y++) {
        for (int x = 0; x < W; x++) {
            if (g_cur[y][x]) {
                int a = g_age[y][x];
                const char *color;
                if      (a <  2) color = "\033[1;32m";
                else if (a <  8) color = "\033[1;36m";
                else if (a < 20) color = "\033[1;34m";
                else             color = "\033[1;35m";

                if (color != last_color) {
                    p += sprintf(p, "%s", color);
                    last_color = color;
                }
                *p++ = 'O';
            } else {
                if (last_color) {
                    p += sprintf(p, "\033[0m");
                    last_color = NULL;
                }
                *p++ = ' ';
            }
        }
        *p++ = '\n';
    }
    p += sprintf(p, "\033[0m");

    fwrite(buf, 1, (size_t)(p - buf), stdout);
    fflush(stdout);
}

/* ---------------- 图案库 ---------------- */
static void put(int x, int y)
{
    if (x >= 0 && x < W && y >= 0 && y < H)
        g_cur[y][x] = 1;
}

static void pat_glider(int x, int y)
{
    put(x + 1, y);
    put(x + 2, y + 1);
    put(x,     y + 2);
    put(x + 1, y + 2);
    put(x + 2, y + 2);
}

static void pat_pulsar(int x, int y)
{
    static const int p[][2] = {
        {2,0},{3,0},{4,0},{8,0},{9,0},{10,0},
        {0,2},{5,2},{7,2},{12,2},
        {0,3},{5,3},{7,3},{12,3},
        {0,4},{5,4},{7,4},{12,4},
        {2,5},{3,5},{4,5},{8,5},{9,5},{10,5},
        {2,7},{3,7},{4,7},{8,7},{9,7},{10,7},
        {0,8},{5,8},{7,8},{12,8},
        {0,9},{5,9},{7,9},{12,9},
        {0,10},{5,10},{7,10},{12,10},
        {2,12},{3,12},{4,12},{8,12},{9,12},{10,12},
    };
    for (size_t i = 0; i < sizeof(p)/sizeof(p[0]); i++)
        put(x + p[i][0], y + p[i][1]);
}

static void pat_gun(int x, int y)
{
    static const int p[][2] = {
        {24,0},
        {22,1},{24,1},
        {12,2},{13,2},{20,2},{21,2},{34,2},{35,2},
        {11,3},{15,3},{20,3},{21,3},{34,3},{35,3},
        { 0,4},{ 1,4},{10,4},{16,4},{20,4},{21,4},
        { 0,5},{ 1,5},{10,5},{14,5},{16,5},{17,5},{22,5},{24,5},
        {10,6},{16,6},{24,6},
        {11,7},{15,7},
        {12,8},{13,8},
    };
    for (size_t i = 0; i < sizeof(p)/sizeof(p[0]); i++)
        put(x + p[i][0], y + p[i][1]);
}

static void pat_rpent(int x, int y)
{
    put(x + 1, y);
    put(x + 2, y);
    put(x,     y + 1);
    put(x + 1, y + 1);
    put(x + 1, y + 2);
}

/* ---------------- 信号处理 ---------------- */
static void on_sig(int s)
{
    (void)s;
    /* 恢复光标、重置颜色，再退出 */
    printf("\033[?25h\033[0m\n");
    fflush(stdout);
    _Exit(0);   /* 用 _Exit 避免再次触发 atexit/信号 */
}

/* ---------------- main ---------------- */
int main(int argc, char **argv)
{
    const char *pat = argc > 1 ? argv[1] : "gun";
    int delay       = argc > 2 ? atoi(argv[2]) : 80;

    memset(g_cur, 0, sizeof(g_cur));

    if      (!strcmp(pat, "glider")) pat_glider(W/2 - 1, H/2 - 1);
    else if (!strcmp(pat, "pulsar")) pat_pulsar(W/2 - 6, H/2 - 6);
    else if (!strcmp(pat, "gun"))    pat_gun(W/2 - 18, 2);
    else if (!strcmp(pat, "rpent"))  pat_rpent(W/2, H/2);
    else {
        srand((unsigned)time(NULL));
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++)
                g_cur[y][x] = (rand() % 100) < 30;
    }

    /* 原来这两行依赖 <signal.h>，现在用自己声明的接口 */
    signal(SIGINT,  on_sig);
    signal(SIGTERM, on_sig);

    printf("\033[2J\033[?25l");
    fflush(stdout);

    for (long gen = 0; ; gen++) {
        draw();
        step();
        msleep(delay);
    }
    return 0;
}
