/*
 * @category: array_dim_cast
 * 数组维数含 (int) 强制转换的惯用法（#265 修复锚，2026-10-22）：
 * `(int)(sizeof arr / sizeof arr[0])` 是 C 求数组长度的标准写法，parser
 * const_int_of 无 Cast 臂曾折不出被误判 VLA——局部传参 E3038 / 全局
 * 「不支持 VLA」/ struct 成员运行时 trap 三面连坐。C11 §6.7.6.3p7
 * 形参第一维大小被丢弃，维数取值与类型匹配无关。clang 真值对拍。
 */
#include <stdio.h>

#define N 5
#define STRATS { "aa", "bb", "cc" }
#define CNT ((int)(sizeof STRAT_NAMES / sizeof STRAT_NAMES[0]))

static const char *const STRAT_NAMES[] = STRATS;

/* 形参第一维丢弃（C11 §6.7.6.3p7）——实参维数含 cast 也须兼容 */
static void fill(char out[][N], int rows) {
    for (int i = 0; i < rows; i++) {
        out[i][0] = 'A' + i;
        out[i][1] = 0;
    }
}

struct Table {
    char cells[(int)(1 + 2)][N]; /* struct 成员含 cast */
};

/* 全局含 cast + sizeof 惯用法宏（SCORE_STRATEGY_COUNT 同款） */
static char g_lines[CNT][N];

int main(void) {
    /* 局部第一维含 cast，传参（issue 主形态：E3038 误拒面） */
    char lines[(int)(2 + 1)][N];
    fill(lines, 3);
    printf("loc=%s,%s,%s\n", lines[0], lines[1], lines[2]);

    /* 全局 cast 维数（旧「全局不支持 VLA」面） */
    g_lines[0][0] = 'G';
    g_lines[0][1] = 0;
    printf("glob=%s cnt=%d\n", g_lines[0], CNT);

    /* struct 成员 cast 维数（旧运行时 trap 面） */
    struct Table t;
    t.cells[2][0] = 'T';
    t.cells[2][1] = 0;
    printf("member=%s\n", t.cells[2]);

    /* 无 cast 对照（既有路径回归锚） */
    char plain[2 * 2][N];
    plain[0][0] = 'P';
    plain[0][1] = 0;
    printf("plain=%s\n", plain[0]);

    /* 局部 + sizeof 惯用法宏第一维 + 传参（#265 评论 HUGE-CPM 形态，
     * 与 min5b/z6 同形——两独立模型同宏阻塞的系统性写法） */
    char name_lines[CNT][N];
    fill(name_lines, CNT);
    printf("local=%d %s %s\n", CNT, name_lines[0], name_lines[2]);

    /* (size_t) 强转变体（评论点名确认面；stddef.h 的 typedef 名） */
    char sbuf[(size_t)(1 + 2)][N];
    fill(sbuf, 3);
    printf("szt=%s\n", sbuf[1]);
    return 0;
}
