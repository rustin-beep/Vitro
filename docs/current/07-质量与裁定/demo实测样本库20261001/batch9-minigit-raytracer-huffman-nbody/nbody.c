/* nbody.c —— N 体引力模拟
 *
 * 编译: gcc -Wall -O2 -o nbody nbody.c -lm
 * 运行: ./nbody [场景] [步数]
 *
 * 场景:
 *   solar     太阳系（默认）
 *   binary    双星系统 + 环绕行星
 *   chaos     三体混沌（Poincaré 的经典例子）
 *   cluster   随机星团坍缩
 *
 * 物理:
 *   - 万有引力 F = G·m1·m2 / r²
 *   - 速度 Verlet 积分（辛积分，长期能量守恒）
 *   - 软化参数避免近距离奇点
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>

/* ================================================================
 * 常量
 * ================================================================ */
#define G         0.5        /* 引力常数，调小让速度看起来舒服 */
#define SOFTENING 0.5        /* 距离软化，防止 r→0 时爆炸 */
#define NMAX      16

#define WIDTH     90
#define HEIGHT    40
#define ASPECT    ((double)WIDTH / (HEIGHT * 2.0))  /* 字符高宽比修正 */

/* ================================================================
 * 天体
 * ================================================================ */
typedef struct {
    double x, y;         /* 位置 */
    double vx, vy;       /* 速度 */
    double m;            /* 质量 */
    int    color;        /* ANSI 颜色码 */
    const char *label;   /* 显示字符 */
} Body;

static Body  g_bodies[NMAX];
static int   g_n;
static int   g_trail_len = 6;

/* 每个天体最近几帧的位置，用于画尾迹 */
static double g_trail[NMAX][64][2];
static int    g_trail_pos[NMAX];

/* ================================================================
 * 物理核心
 * ================================================================ */
static void compute_accel(const Body *b, int n, double *ax, double *ay)
{
    for (int i = 0; i < n; i++) { ax[i] = 0; ay[i] = 0; }

    for (int i = 0; i < n; i++) {
        for (int j = i + 1; j < n; j++) {
            double dx = b[j].x - b[i].x;
            double dy = b[j].y - b[i].y;
            double r2 = dx*dx + dy*dy + SOFTENING*SOFTENING;
            double inv_r3 = 1.0 / (r2 * sqrt(r2));

            double f = G * inv_r3;
            ax[i] += f * b[j].m * dx;
            ay[i] += f * b[j].m * dy;
            ax[j] -= f * b[i].m * dx;
            ay[j] -= f * b[i].m * dy;
        }
    }
}

/* 速度 Verlet：比欧拉法稳定得多，长期模拟不会"能量爆炸" */
static void step(double dt)
{
    double ax[NMAX], ay[NMAX];
    compute_accel(g_bodies, g_n, ax, ay);

    for (int i = 0; i < g_n; i++) {
        g_bodies[i].x += g_bodies[i].vx * dt + 0.5 * ax[i] * dt * dt;
        g_bodies[i].y += g_bodies[i].vy * dt + 0.5 * ay[i] * dt * dt;
        /* 半更新速度 */
        g_bodies[i].vx += 0.5 * ax[i] * dt;
        g_bodies[i].vy += 0.5 * ay[i] * dt;
    }

    compute_accel(g_bodies, g_n, ax, ay);

    for (int i = 0; i < g_n; i++) {
        g_bodies[i].vx += 0.5 * ax[i] * dt;
        g_bodies[i].vy += 0.5 * ay[i] * dt;
    }
}

/* ================================================================
 * 坐标变换：世界坐标 → 屏幕坐标
 *
 *   自动计算所有天体的包围盒，让整个系统始终适配屏幕。
 * ================================================================ */
static void world_to_screen(double wx, double wy,
                            double *sx, double *sy,
                            double xmin, double xmax,
                            double ymin, double ymax)
{
    double xr = xmax - xmin; if (xr < 0.1) xr = 0.1;
    double yr = ymax - ymin; if (yr < 0.1) yr = 0.1;

    double scale = (xr / ASPECT > yr) ? (WIDTH / xr) : ((HEIGHT * 2.0) / yr);

    double cx = (xmin + xmax) / 2;
    double cy = (ymin + ymax) / 2;

    *sx = WIDTH  / 2.0 + (wx - cx) * scale;
    *sy = HEIGHT / 2.0 - (wy - cy) * scale * 0.5;   /* 字符高约为宽的两倍 */
}

/* ================================================================
 * 渲染
 * ================================================================ */
static void draw(void)
{
    static char grid[HEIGHT][WIDTH];
    static int  color[HEIGHT][WIDTH];
    memset(grid, ' ', sizeof(grid));
    memset(color, 0, sizeof(color));

    /* 计算包围盒 */
    double xmin = 1e9, xmax = -1e9, ymin = 1e9, ymax = -1e9;
    for (int i = 0; i < g_n; i++) {
        if (g_bodies[i].x < xmin) xmin = g_bodies[i].x;
        if (g_bodies[i].x > xmax) xmax = g_bodies[i].x;
        if (g_bodies[i].y < ymin) ymin = g_bodies[i].y;
        if (g_bodies[i].y > ymax) ymax = g_bodies[i].y;
    }
    double pad = 0.5 * ((xmax - xmin) + (ymax - ymin)) * 0.1 + 1.0;
    xmin -= pad; xmax += pad;
    ymin -= pad; ymax += pad;

    /* 画尾迹（较暗的颜色） */
    for (int i = 0; i < g_n; i++) {
        for (int t = 0; t < g_trail_len; t++) {
            int idx = (g_trail_pos[i] - 1 - t + 64) % 64;
            if (idx < 0) continue;
            double tx = g_trail[i][idx][0];
            double ty = g_trail[i][idx][1];
            if (tx == 0 && ty == 0) continue;

            double sx, sy;
            world_to_screen(tx, ty, &sx, &sy, xmin, xmax, ymin, ymax);
            int ix = (int)sx, iy = (int)sy;
            if (ix < 0 || ix >= WIDTH || iy < 0 || iy >= HEIGHT) continue;

            char c = (t < 2) ? '.' : (t < 4 ? ',' : '`');
            grid[iy][ix] = c;
            if (color[iy][ix] == 0) color[iy][ix] = g_bodies[i].color + 8;
        }
    }

    /* 画天体本体 */
    for (int i = 0; i < g_n; i++) {
        double sx, sy;
        world_to_screen(g_bodies[i].x, g_bodies[i].y,
                        &sx, &sy, xmin, xmax, ymin, ymax);
        int ix = (int)sx, iy = (int)sy;
        if (ix < 0 || ix >= WIDTH || iy < 0 || iy >= HEIGHT) continue;
        grid[iy][ix]  = g_bodies[i].label[0];
        color[iy][ix] = g_bodies[i].color;
    }

    /* 一次性输出整帧 */
    static char buf[HEIGHT * (WIDTH * 24 + 8) + 64];
    char *p = buf;
    p += sprintf(p, "\033[H");

    int last_color = -1;
    for (int y = 0; y < HEIGHT; y++) {
        for (int x = 0; x < WIDTH; x++) {
            int col = color[y][x];
            if (col != last_color) {
                if (col == 0) p += sprintf(p, "\033[0m");
                else          p += sprintf(p, "\033[1;%dm", col);
                last_color = col;
            }
            *p++ = grid[y][x];
        }
        *p++ = '\n';
    }
    p += sprintf(p, "\033[0m");

    fwrite(buf, 1, (size_t)(p - buf), stdout);
    fflush(stdout);
}

/* ================================================================
 * 场景
 * ================================================================ */
static void add_body(double x, double y, double vx, double vy,
                     double m, int color, const char *label)
{
    if (g_n >= NMAX) return;
    Body *b = &g_bodies[g_n];
    b->x = x; b->y = y;
    b->vx = vx; b->vy = vy;
    b->m = m;
    b->color = color;
    b->label = label;
    g_trail_pos[g_n] = 0;
    g_n++;
}

static void scene_solar(void)
{
    /* 恒星（重，几乎不动） */
    add_body(0, 0, 0, 0, 50.0, 33, "O");     /* 黄 */

    /* 三颗行星，用圆轨道速度 v = sqrt(GM/r) */
    double M = 50.0;
    double radii[] = {2.0, 3.5, 5.5};

    for (int i = 0; i < 3; i++) {
        double r  = radii[i];
        double v  = sqrt(G * M / r);
        double ang = i * 2.0 * M_PI / 3.0;
        add_body(r * cos(ang), r * sin(ang),
                -v * sin(ang), v * cos(ang),
                0.3 + i * 0.1,
                i == 0 ? 34 : (i == 1 ? 36 : 35),
                i == 0 ? "o" : (i == 1 ? "O" : "@"));
    }
}

static void scene_binary(void)
{
    /* 两个等质量恒星互绕 */
    double m = 20.0;
    double r = 1.5;
    double v = sqrt(G * m / (4.0 * r));

    add_body(-r, 0, 0,  v, m, 31, "O");   /* 红 */
    add_body( r, 0, 0, -v, m, 36, "O");   /* 青 */

    /* 远处行星绕双星质心转（近似） */
    double R  = 6.0;
    double vp = sqrt(G * 2 * m / R);
    add_body(0, R, -vp, 0, 0.5, 33, "o");
    add_body(0, -R, vp, 0, 0.5, 35, "o");
}

static void scene_chaos(void)
{
    /* 三体问题：三个等质量天体从随机位置出发
     * 这个经典例子会演出"8 字形"或混沌散射 */
    add_body(-1.0,  0.0,  0.3,  0.5, 10.0, 31, "*");
    add_body( 1.0,  0.0,  0.3, -0.5, 10.0, 32, "*");
    add_body( 0.0,  1.0, -0.6,  0.0, 10.0, 36, "*");
}

static void scene_cluster(void)
{
    /* 随机星团：起初静止，引力让它们互相吸引，坍缩后弹开 */
    srand((unsigned)time(NULL));
    for (int i = 0; i < 10; i++) {
        double x = ((double)rand() / RAND_MAX - 0.5) * 8;
        double y = ((double)rand() / RAND_MAX - 0.5) * 8;
        add_body(x, y, 0, 0, 1.0, 31 + (i % 6), "o");
    }
}

/* ================================================================
 * main
 * ================================================================ */
int main(int argc, char **argv)
{
    const char *scene = (argc > 1) ? argv[1] : "solar";
    int steps = (argc > 2) ? atoi(argv[2]) : 3000;

    g_n = 0;

    if      (!strcmp(scene, "solar"))   scene_solar();
    else if (!strcmp(scene, "binary"))  scene_binary();
    else if (!strcmp(scene, "chaos"))   scene_chaos();
    else if (!strcmp(scene, "cluster")) scene_cluster();
    else {
        fprintf(stderr, "未知场景: %s\n", scene);
        fprintf(stderr, "可选: solar / binary / chaos / cluster\n");
        return 1;
    }

    printf("\033[2J\033[?25l");   /* 清屏 + 隐藏光标 */
    fflush(stdout);

    double dt = 0.02;

    for (int s = 0; s < steps; s++) {
        /* 记录尾迹 */
        for (int i = 0; i < g_n; i++) {
            g_trail[i][g_trail_pos[i]][0] = g_bodies[i].x;
            g_trail[i][g_trail_pos[i]][1] = g_bodies[i].y;
            g_trail_pos[i] = (g_trail_pos[i] + 1) % 64;
        }

        if ((s % 2) == 0) draw();
        step(dt);
    }

    printf("\033[?25h\033[0m\n");
    return 0;
}
