/* 接入模板：示例采用简单贪心，仅演示合法动作，不是作业算法答案。 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { int r, c; } Point;
typedef struct {
    int role, rows, cols, completed_rounds, max_rounds, seed, request_id, depth;
    char map[8][9];                 /* .空地、#障碍、E出口 */
    Point A, B, T;                  /* 行列坐标均从1开始 */
} State;
static const int dr[5] = {-1, 1, 0, 0, 0};
static const int dc[5] = {0, 0, -1, 1, 0};
static int equal(Point a, Point b) { return a.r == b.r && a.c == b.c; }
static int dist(Point a, Point b) { return abs(a.r - b.r) + abs(a.c - b.c); }
static Point moved(Point p, int x) { Point q = {p.r + dr[x], p.c + dc[x]}; return q; }
static int legal(Point p, const State *s) {
    return p.r >= 1 && p.r <= s->rows && p.c >= 1 && p.c <= s->cols && s->map[p.r-1][p.c-1] != '#';
}
static int min(int x, int y) { return x < y ? x : y; }

/* 只需修改此策略函数，下面的通信代码保持原样。
 * s提供角色、地图、三个位置、已完成轮数、轮数上限和随机种子等信息。
 * role=0：输出A、B的联合动作；role=1：输出目标动作，out2固定-1。
 * 动作编码：0上、1下、2左、3右、4停；通过*out1、*out2返回动作。
 */
static void choose_action(const State *s, int *out1, int *out2) {
    int role = s->role, rows = s->rows, cols = s->cols;
    Point a = s->A, b = s->B, t = s->T;
    int best = -1000000000;
    *out1 = 4; *out2 = role == 0 ? 4 : -1;
    for (int x = 0; x < 5; ++x) {
        if (role == 0) {
            Point na = moved(a, x);
            if (!legal(na,s)) continue;
            for (int y = 0; y < 5; ++y) {
                Point nb = moved(b, y);
                if (!legal(nb,s) || equal(na, nb) || (equal(na, b) && equal(nb, a))) continue;
                int score = equal(na, t) || equal(nb, t) ? 100000 : -dist(na, t) - dist(nb, t);
                if (score > best) { best = score; *out1 = x; *out2 = y; }
            }
        } else {
            Point nt = moved(t, x);
            if (!legal(nt,s)) continue;
            int ed = 100000;
            for (int r = 1; r <= rows; ++r) for (int c = 1; c <= cols; ++c) {
                if (s->map[r-1][c-1] == 'E') { Point e = {r,c}; ed = min(ed, dist(nt,e)); }
            }
            int score = equal(nt,a) || equal(nt,b) ? -100000 :
                s->map[nt.r-1][nt.c-1] == 'E' ? 100000 : 10 * min(dist(nt,a),dist(nt,b)) - ed;
            if (score > best) { best = score; *out1 = x; *out2 = -1; }
        }
    }
}

/* 以下为通信代码，请保持原样。 */
int main(void) {
    char tag[16];
    puts("READY 1"); fflush(stdout);
    while (scanf("%15s", tag) == 1) {
        if (strcmp(tag,"STOP") == 0) return 0;
        int ver;
        State s = {0};
        if (strcmp(tag,"STATE") != 0 || scanf("%d%d%d%d%d%d%d", &ver,&s.request_id,&s.role,&s.completed_rounds,&s.max_rounds,&s.depth,&s.seed) != 7 || ver != 1) return 2;
        if (scanf("%d%d", &s.rows,&s.cols) != 2 || s.rows != 8 || s.cols != 8) return 2;
        for (int r = 0; r < s.rows; ++r) if (scanf("%8s", s.map[r]) != 1 || (int)strlen(s.map[r]) != s.cols) return 2;
        if (scanf("%d%d%d%d%d%d", &s.A.r,&s.A.c,&s.B.r,&s.B.c,&s.T.r,&s.T.c) != 6) return 2;
        if (scanf("%15s", tag) != 1 || strcmp(tag,"END") != 0) return 2;
        int x,y; choose_action(&s,&x,&y);
        printf("%d %d %d\n",s.request_id,x,y); fflush(stdout);
    }
    return 0;
}
