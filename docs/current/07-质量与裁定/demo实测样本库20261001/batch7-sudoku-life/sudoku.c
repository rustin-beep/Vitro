#include <stdio.h>
#include <string.h>

static int g_board[9][9];
static int g_given[9][9];      /* 1=题面数字，0=求解填入 */

static int g_rows[9];          /* 每行已用数字的位掩码，bit(d-1)=1 表示 d 已用 */
static int g_cols[9];
static int g_boxes[9];

static long g_steps;

static int box_id(int r, int c) { return (r / 3) * 3 + c / 3; }

static int popcount(int x)
{
    int c = 0;
    while (x) { c += x & 1; x >>= 1; }
    return c;
}

/* ================================================================
 * 回溯求解
 *
 *   经典回溯 + MRV：不是从头扫第一个空格，而是扫一遍所有空格，
 *   挑候选数最少的那个先填。这会让搜索树小很多。
 * ================================================================ */
static int solve(void)
{
    int best_r = -1, best_c = -1, best_n = 10;

    for (int r = 0; r < 9; r++) {
        for (int c = 0; c < 9; c++) {
            if (g_board[r][c] != 0) continue;

            int used = g_rows[r] | g_cols[c] | g_boxes[box_id(r, c)];
            int n    = 9 - popcount(used);

            if (n < best_n) {
                best_n = n;
                best_r = r;
                best_c = c;
                if (n == 0) return 0;   /* 这个空格无数可填，剪枝 */
            }
        }
    }

    if (best_r == -1) return 1;         /* 所有格都填满了，成功 */

    int r    = best_r, c = best_c;
    int used = g_rows[r] | g_cols[c] | g_boxes[box_id(r, c)];

    for (int d = 1; d <= 9; d++) {
        int bit = 1 << (d - 1);
        if (used & bit) continue;

        /* 做选择 */
        g_board[r][c] = d;
        g_rows[r] |= bit;
        g_cols[c] |= bit;
        g_boxes[box_id(r, c)] |= bit;
        g_steps++;

        if (solve()) return 1;

        /* 撤销选择 */
        g_board[r][c] = 0;
        g_rows[r] &= ~bit;
        g_cols[c] &= ~bit;
        g_boxes[box_id(r, c)] &= ~bit;
    }
    return 0;
}

/* ================================================================
 * 打印
 * ================================================================ */
static void print_board(void)
{
    for (int r = 0; r < 9; r++) {
        if (r % 3 == 0) printf("  +-------+-------+-------+\n");
        for (int c = 0; c < 9; c++) {
            if (c % 3 == 0) printf("  | ");
            int v = g_board[r][c];
            if (g_given[r][c])
                printf("\033[1;37m%d\033[0m ", v);   /* 题面：亮白 */
            else
                printf("\033[1;32m%d\033[0m ", v);   /* 解出：绿色 */
        }
        printf("|\n");
    }
    printf("  +-------+-------+-------+\n");
}

/* ================================================================
 * 载入题面：81 个字符，'.' 表示空格
 * ================================================================ */
static void load(const char *s)
{
    memset(g_board, 0, sizeof(g_board));
    memset(g_given, 0, sizeof(g_given));
    memset(g_rows,  0, sizeof(g_rows));
    memset(g_cols,  0, sizeof(g_cols));
    memset(g_boxes, 0, sizeof(g_boxes));
    g_steps = 0;

    int i = 0;
    for (const char *p = s; *p && i < 81; p++) {
        if (*p != '.' && (*p < '1' || *p > '9')) continue;

        int r = i / 9, c = i % 9;
        if (*p != '.') {
            int d = *p - '0';
            g_board[r][c] = d;
            g_given[r][c] = 1;
            g_rows[r]             |= 1 << (d - 1);
            g_cols[c]             |= 1 << (d - 1);
            g_boxes[box_id(r, c)] |= 1 << (d - 1);
        }
        i++;
    }
}

/* ================================================================
 * 演示：三个难度不同的题
 * ================================================================ */
static void run(const char *title, const char *puzzle)
{
    printf("\n========================================\n");
    printf("  %s\n", title);
    printf("========================================\n\n");

    load(puzzle);

    printf("原始题面：\n");
    print_board();

    if (solve()) {
        printf("\n求解结果（搜索 %ld 步）：\n", g_steps);
        print_board();
    } else {
        printf("\n无解\n");
    }
}

int main(void)
{
    printf("=== 数独求解器（MRV 启发式） ===\n");

    /* 1. 最简单的经典题 */
    run("简单",
        "53..7...."
        "6..195..."
        ".98....6."
        "8...6...3"
        "4..8.3..1"
        "7...2...6"
        ".6....28."
        "...419..5"
        "....8..79");

    /* 2. 中等难度 */
    run("中等",
        "..9748..."
        "7........"
        ".2.1.9..."
        "..7...24."
        ".64.1.59."
        ".98...3.."
        "...8.3.2."
        "........6"
        "...2759..");

    /* 3. 所谓"世界最难数独"之一（2012 年 Arto Inkala 设计的） */
    run("困难",
        "8........"
        "..36....."
        ".7..9.2.."
        ".5...7..."
        "....457.."
        "...1...3."
        "..1....68"
        "..85...1."
        ".9....4..");

    return 0;
}
