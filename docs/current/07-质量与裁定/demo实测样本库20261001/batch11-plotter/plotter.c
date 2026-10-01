/* plotter.c —— 数学表达式解析 + 终端绘图
 *
 * 编译: gcc -Wall -O2 -o plotter plotter.c -lm
 * 用法: ./plotter "<表达式>" [xmin] [xmax] [宽度]
 *
 * 示例:
 *   ./plotter "sin(x)" -6.28 6.28
 *   ./plotter "x^2 - 3*x + 1" -5 5 100
 *   ./plotter "exp(-x^2/2)/sqrt(2*pi)" -4 4
 *
 * 支持:
 *   数字:    3.14, -2.5, 1e3
 *   变量:    x
 *   常量:    pi, e
 *   运算符:  + - * / ^   （^ 右结合，-x^2 = -(x^2)）
 *   函数:    sin cos tan asin acos atan
 *            sqrt cbrt abs exp log log2 log10
 *            floor ceil round sinh cosh tanh
 *   括号:    ( )
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <ctype.h>
#include <stdarg.h>
#include <limits.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <time.h>
#include <assert.h>
#include <errno.h>
#include <float.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif
#ifndef M_E
#define M_E  2.7182818284590452354
#endif

/* ================================================================
 * 日志：演示 stdarg.h
 * ================================================================ */
static void log_info(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    fputs("\033[1;36m[info]\033[0m ", stdout);
    vfprintf(stdout, fmt, ap);
    va_end(ap);
}

static void log_err(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    fputs("\033[1;31m[err ]\033[0m ", stderr);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
}

/* ================================================================
 * 词法分析器
 * ================================================================ */
typedef enum {
    T_EOF, T_NUM, T_VAR, T_FUNC,
    T_LPAREN, T_RPAREN,
    T_PLUS, T_MINUS, T_STAR, T_SLASH, T_CARET,
    T_ERROR
} TokType;

typedef struct {
    TokType type;
    double  num;
    char    name[16];
} Token;

static const char *g_src;
static Token       g_tok;

static const char *tok_name(TokType t)
{
    static const char *names[] = {
        "EOF", "数字", "变量", "函数",
        "(", ")", "+", "-", "*", "/", "^", "错误"
    };
    return names[t];
}

static bool is_func_name(const char *s)
{
    static const char *funcs[] = {
        "sin","cos","tan","asin","acos","atan",
        "sqrt","cbrt","abs","exp","log","log2","log10",
        "floor","ceil","round","sinh","cosh","tanh",
        NULL
    };
    for (size_t i = 0; funcs[i]; i++)
        if (!strcmp(s, funcs[i])) return true;
    return false;
}

static void next_token(void)
{
    while (isspace((unsigned char)*g_src)) g_src++;

    if (*g_src == '\0') { g_tok.type = T_EOF; return; }

    char c = *g_src;

    /* 数字（用 strtod 解析，支持科学计数法） */
    if (isdigit((unsigned char)c) || c == '.') {
        char *end = NULL;
        errno = 0;
        double v = strtod(g_src, &end);
        if (errno == ERANGE) {
            log_err("数字溢出: %s\n", g_src);
            g_tok.type = T_ERROR;
            return;
        }
        g_tok.num  = v;
        g_tok.type = T_NUM;
        g_src = end;
        return;
    }

    /* 标识符：变量 / 常量 / 函数名 */
    if (isalpha((unsigned char)c) || c == '_') {
        size_t n = 0;
        while ((isalnum((unsigned char)*g_src) || *g_src == '_') &&
               n < sizeof(g_tok.name) - 1)
            g_tok.name[n++] = *g_src++;
        g_tok.name[n] = '\0';

        if (!strcmp(g_tok.name, "x"))  { g_tok.type = T_VAR; return; }
        if (!strcmp(g_tok.name, "pi")) { g_tok.type = T_NUM; g_tok.num = M_PI; return; }
        if (!strcmp(g_tok.name, "e"))  { g_tok.type = T_NUM; g_tok.num = M_E;  return; }
        if (is_func_name(g_tok.name))  { g_tok.type = T_FUNC; return; }

        log_err("未知标识符: %s\n", g_tok.name);
        g_tok.type = T_ERROR;
        return;
    }

    /* 单字符符号 */
    g_src++;
    switch (c) {
    case '+': g_tok.type = T_PLUS;   return;
    case '-': g_tok.type = T_MINUS;  return;
    case '*': g_tok.type = T_STAR;   return;
    case '/': g_tok.type = T_SLASH;  return;
    case '^': g_tok.type = T_CARET;  return;
    case '(': g_tok.type = T_LPAREN; return;
    case ')': g_tok.type = T_RPAREN; return;
    default:
        log_err("非法字符: '%c'\n", c);
        g_tok.type = T_ERROR;
        return;
    }
}

/* ================================================================
 * AST
 * ================================================================ */
typedef enum { N_NUM, N_VAR, N_BINOP, N_FUNC, N_NEG } NodeType;

typedef struct Node {
    NodeType type;
    union {
        double num;
        char   var;
        struct { char op; struct Node *l, *r; } bin;
        struct { char name[16]; struct Node *arg; } fn;
        struct Node *neg;
    } u;
} Node;

static Node *ast_num(double v)
{
    Node *n = (Node *)calloc(1, sizeof(Node));
    if (!n) { perror("calloc"); exit(1); }
    n->type = N_NUM;
    n->u.num = v;
    return n;
}

static Node *ast_var(char c)
{
    Node *n = (Node *)calloc(1, sizeof(Node));
    n->type = N_VAR;
    n->u.var = c;
    return n;
}

static Node *ast_bin(char op, Node *l, Node *r)
{
    Node *n = (Node *)calloc(1, sizeof(Node));
    n->type = N_BINOP;
    n->u.bin.op = op;
    n->u.bin.l  = l;
    n->u.bin.r  = r;
    return n;
}

static Node *ast_func(const char *name, Node *arg)
{
    Node *n = (Node *)calloc(1, sizeof(Node));
    n->type = N_FUNC;
    strncpy(n->u.fn.name, name, sizeof(n->u.fn.name) - 1);
    n->u.fn.name[sizeof(n->u.fn.name) - 1] = '\0';
    n->u.fn.arg = arg;
    return n;
}

static Node *ast_neg(Node *x)
{
    Node *n = (Node *)calloc(1, sizeof(Node));
    n->type = N_NEG;
    n->u.neg = x;
    return n;
}

static void ast_free(Node *n)
{
    if (!n) return;
    switch (n->type) {
    case N_BINOP: ast_free(n->u.bin.l); ast_free(n->u.bin.r); break;
    case N_FUNC:  ast_free(n->u.fn.arg); break;
    case N_NEG:   ast_free(n->u.neg);    break;
    default: break;
    }
    free(n);
}

/* ================================================================
 * 递归下降解析器
 *
 *   expr   → term (('+' | '-') term)*
 *   term   → factor (('*' | '/') factor)*
 *   factor → '-' factor | atom ('^' factor)?
 *   atom   → NUM | VAR | FUNC '(' expr ')' | '(' expr ')'
 * ================================================================ */
static bool  g_parse_ok = true;

static bool expect(TokType t, const char *what)
{
    if (g_tok.type != t) {
        log_err("语法错误: 期望 %s，实际 %s\n", what, tok_name(g_tok.type));
        g_parse_ok = false;
        return false;
    }
    next_token();
    return true;
}

static Node *parse_expr(void);
static Node *parse_term(void);
static Node *parse_factor(void);

static Node *parse_atom(void)
{
    if (!g_parse_ok) return NULL;

    if (g_tok.type == T_NUM) {
        Node *n = ast_num(g_tok.num);
        next_token();
        return n;
    }
    if (g_tok.type == T_VAR) {
        Node *n = ast_var(g_tok.name[0]);
        next_token();
        return n;
    }
    if (g_tok.type == T_FUNC) {
        char name[16];
        strcpy(name, g_tok.name);
        next_token();
        if (!expect(T_LPAREN, "'('")) return NULL;
        Node *arg = parse_expr();
        if (!expect(T_RPAREN, "')'")) return NULL;
        return ast_func(name, arg);
    }
    if (g_tok.type == T_LPAREN) {
        next_token();
        Node *n = parse_expr();
        if (!expect(T_RPAREN, "')'")) return NULL;
        return n;
    }

    log_err("语法错误: 意外的 %s\n", tok_name(g_tok.type));
    g_parse_ok = false;
    return NULL;
}

static Node *parse_factor(void)
{
    if (!g_parse_ok) return NULL;

    /* 一元负号优先于乘方：-x^2 = -(x^2) */
    if (g_tok.type == T_MINUS) {
        next_token();
        Node *inner = parse_factor();
        return inner ? ast_neg(inner) : NULL;
    }

    Node *base = parse_atom();
    if (!base) return NULL;

    /* 乘方右结合：2^3^2 = 2^(3^2) */
    if (g_tok.type == T_CARET) {
        next_token();
        Node *exp = parse_factor();
        if (!exp) { ast_free(base); return NULL; }
        return ast_bin('^', base, exp);
    }
    return base;
}

static Node *parse_term(void)
{
    if (!g_parse_ok) return NULL;

    Node *left = parse_factor();
    if (!left) return NULL;

    while (g_tok.type == T_STAR || g_tok.type == T_SLASH) {
        char op = (g_tok.type == T_STAR) ? '*' : '/';
        next_token();
        Node *right = parse_factor();
        if (!right) { ast_free(left); return NULL; }
        left = ast_bin(op, left, right);
    }
    return left;
}

static Node *parse_expr(void)
{
    if (!g_parse_ok) return NULL;

    Node *left = parse_term();
    if (!left) return NULL;

    while (g_tok.type == T_PLUS || g_tok.type == T_MINUS) {
        char op = (g_tok.type == T_PLUS) ? '+' : '-';
        next_token();
        Node *right = parse_term();
        if (!right) { ast_free(left); return NULL; }
        left = ast_bin(op, left, right);
    }
    return left;
}

/* ================================================================
 * 求值
 * ================================================================ */
static double eval(const Node *n, double x, bool *ok)
{
    if (!n || !*ok) { *ok = false; return NAN; }

    switch (n->type) {
    case N_NUM:
        return n->u.num;

    case N_VAR:
        assert(n->u.var == 'x');
        return x;

    case N_NEG: {
        double v = eval(n->u.neg, x, ok);
        return -v;
    }

    case N_BINOP: {
        double a = eval(n->u.bin.l, x, ok);
        double b = eval(n->u.bin.r, x, ok);
        if (!*ok) return NAN;

        switch (n->u.bin.op) {
        case '+': return a + b;
        case '-': return a - b;
        case '*': return a * b;
        case '/':
            if (fabs(b) < DBL_EPSILON) { *ok = false; return NAN; }
            return a / b;
        case '^':
            /* 负数开分数次方在实数范围无意义 */
            if (a < 0 && fabs(b - round(b)) > DBL_EPSILON) {
                *ok = false;
                return NAN;
            }
            return pow(a, b);
        }
        return NAN;
    }

    case N_FUNC: {
        double v = eval(n->u.fn.arg, x, ok);
        if (!*ok) return NAN;

        const char *f = n->u.fn.name;
        if (!strcmp(f, "sin"))   return sin(v);
        if (!strcmp(f, "cos"))   return cos(v);
        if (!strcmp(f, "tan"))   return tan(v);
        if (!strcmp(f, "asin"))  return asin(v);
        if (!strcmp(f, "acos"))  return acos(v);
        if (!strcmp(f, "atan"))  return atan(v);
        if (!strcmp(f, "sqrt"))  { if (v < 0) { *ok=false; return NAN; } return sqrt(v); }
        if (!strcmp(f, "cbrt"))  return cbrt(v);
        if (!strcmp(f, "abs"))   return fabs(v);
        if (!strcmp(f, "exp"))   return exp(v);
        if (!strcmp(f, "log"))   { if (v <= 0) { *ok=false; return NAN; } return log(v); }
        if (!strcmp(f, "log2"))  { if (v <= 0) { *ok=false; return NAN; } return log2(v); }
        if (!strcmp(f, "log10")) { if (v <= 0) { *ok=false; return NAN; } return log10(v); }
        if (!strcmp(f, "floor")) return floor(v);
        if (!strcmp(f, "ceil"))  return ceil(v);
        if (!strcmp(f, "round")) return round(v);
        if (!strcmp(f, "sinh"))  return sinh(v);
        if (!strcmp(f, "cosh"))  return cosh(v);
        if (!strcmp(f, "tanh"))  return tanh(v);

        *ok = false;
        return NAN;
    }
    }
    return NAN;
}

/* ================================================================
 * 绘图
 * ================================================================ */
#define PLOT_H_MIN  10
#define PLOT_H_MAX  30
#define PLOT_W_MIN  20
#define PLOT_W_MAX 200

typedef struct {
    double xmin, xmax;
    int    width, height;
} PlotConfig;

static void plot(const Node *root, PlotConfig cfg)
{
    const int W = cfg.width;
    const int H = cfg.height;

    double *ys    = (double *)malloc((size_t)W * sizeof(double));
    bool   *okbuf = (bool   *)malloc((size_t)W * sizeof(bool));
    char   *grid  = (char   *)malloc((size_t)W * H);
    uint8_t *col  = (uint8_t *)malloc((size_t)W * H);

    if (!ys || !okbuf || !grid || !col) {
        log_err("内存分配失败\n");
        free(ys); free(okbuf); free(grid); free(col);
        return;
    }

    memset(grid, ' ', (size_t)W * H);
    memset(col,   0,  (size_t)W * H);

    /* --- 采样 --- */
    clock_t t0 = clock();
    double ymin = DBL_MAX, ymax = -DBL_MAX;
    int valid = 0;

    for (int i = 0; i < W; i++) {
        double x = (W == 1) ? cfg.xmin
                            : cfg.xmin + (cfg.xmax - cfg.xmin) * i / (W - 1);

        bool ok = true;
        double y = eval(root, x, &ok);

        if (ok && !isnan(y) && !isinf(y)) {
            ys[i]    = y;
            okbuf[i] = true;
            if (y < ymin) ymin = y;
            if (y > ymax) ymax = y;
            valid++;
        } else {
            ys[i]    = NAN;
            okbuf[i] = false;
        }
    }

    clock_t t1 = clock();
    double elapsed_ms = 1000.0 * (t1 - t0) / CLOCKS_PER_SEC;

    if (valid == 0) {
        log_err("表达式在所有采样点都无效\n");
        free(ys); free(okbuf); free(grid); free(col);
        return;
    }

    /* --- Y 范围加 5% 余量 --- */
    double range = ymax - ymin;
    if (range < DBL_EPSILON) range = 1.0;
    ymin -= range * 0.05;
    ymax += range * 0.05;

    log_info("采样 %d 点，有效 %d 点，耗时 %.2f ms\n", W, valid, elapsed_ms);
    log_info("y 范围: [%.4f, %.4f]\n", ymin, ymax);

    /* --- 零轴 --- */
    if (ymin <= 0 && ymax >= 0) {
        int zr = (int)round((ymax - 0.0) / (ymax - ymin) * (H - 1));
        if (zr >= 0 && zr < H) {
            for (int i = 0; i < W; i++) {
                grid[zr * W + i] = '-';
                col [zr * W + i] = 8;
            }
        }
    }

    /* --- 曲线点 --- */
    for (int i = 0; i < W; i++) {
        if (!okbuf[i]) continue;

        int r = (int)round((ymax - ys[i]) / (ymax - ymin) * (H - 1));
        if (r < 0)  r = 0;
        if (r >= H) r = H - 1;

        grid[r * W + i] = '*';
        col [r * W + i] = 1;
    }

    /* --- 输出 --- */
    putchar('\n');
    for (int r = 0; r < H; r++) {
        double y_here = ymax - (ymax - ymin) * r / (H - 1);
        printf("\033[2m%9.4f\033[0m │", y_here);

        int last = -1;
        for (int c = 0; c < W; c++) {
            uint8_t cc = col[r * W + c];
            if (cc != last) {
                if      (cc == 0) fputs("\033[0m",    stdout);
                else if (cc == 8) fputs("\033[90m",   stdout);
                else              fputs("\033[1;32m", stdout);
                last = (int)cc;
            }
            putchar(grid[r * W + c]);
        }
        fputs("\033[0m\n", stdout);
    }

    /* --- X 轴底部 --- */
    printf("          └");
    for (int i = 0; i < W; i++) putchar('-');
    putchar('\n');

    printf("           %-*s", W / 2, "");
    printf("%.4f", cfg.xmin);
    int pad = W / 2 - 6;
    if (pad > 0) for (int i = 0; i < pad; i++) putchar(' ');
    printf("%.4f\n", cfg.xmax);

    free(ys); free(okbuf); free(grid); free(col);
}

/* ================================================================
 * main
 * ================================================================ */
static void usage(const char *prog)
{
    fprintf(stderr,
        "用法: %s \"<表达式>\" [xmin] [xmax] [宽度]\n"
        "示例:\n"
        "  %s \"sin(x)\" -6.28 6.28\n"
        "  %s \"x^2 - 3*x + 1\" -5 5 100\n"
        "  %s \"exp(-x^2/2)/sqrt(2*pi)\" -4 4\n"
        "  %s \"sin(x)/x\" -20 20\n",
        prog, prog, prog, prog, prog);
}

int main(int argc, char **argv)
{
    if (argc < 2) { usage(argv[0]); return 1; }

    const char *expr = argv[1];

    /* 参数解析：用 strtod / strtol 而不是 atof / atoi，能报错 */
    double xmin = -10.0, xmax = 10.0;
    int    width = 70;

    if (argc > 2) {
        char *end = NULL;
        errno = 0;
        xmin = strtod(argv[2], &end);
        if (errno == ERANGE || end == argv[2]) {
            log_err("非法 xmin: %s\n", argv[2]);
            return 1;
        }
    }
    if (argc > 3) {
        char *end = NULL;
        errno = 0;
        xmax = strtod(argv[3], &end);
        if (errno == ERANGE || end == argv[3]) {
            log_err("非法 xmax: %s\n", argv[3]);
            return 1;
        }
    }
    if (argc > 4) {
        char *end = NULL;
        errno = 0;
        long w = strtol(argv[4], &end, 10);
        if (errno == ERANGE || end == argv[4] || w < PLOT_W_MIN || w > PLOT_W_MAX) {
            log_err("宽度必须在 %d ~ %d 之间\n", PLOT_W_MIN, PLOT_W_MAX);
            return 1;
        }
        width = (int)w;
    }

    if (xmin >= xmax) {
        log_err("xmin 必须小于 xmax\n");
        return 1;
    }
    if (!isfinite(xmin) || !isfinite(xmax)) {
        log_err("xmin / xmax 必须是有限数\n");
        return 1;
    }

    /* 高度按 4:1 宽高比 */
    int height = width / 4;
    if (height < PLOT_H_MIN) height = PLOT_H_MIN;
    if (height > PLOT_H_MAX) height = PLOT_H_MAX;

    printf("\033[1;36m");
    printf("┌──────────────────────────────────────────────────┐\n");
    printf("│           数学表达式绘图器  v1.0                  │\n");
    printf("└──────────────────────────────────────────────────┘\n");
    printf("\033[0m\n");

    log_info("表达式: \033[1;33m%s\033[0m\n", expr);
    log_info("范围:   x ∈ [%g, %g]\n", xmin, xmax);
    log_info("画布:   %d × %d\n", width, height);

    /* 解析 */
    g_src = expr;
    g_parse_ok = true;
    next_token();

    Node *root = parse_expr();

    if (!g_parse_ok || g_tok.type != T_EOF) {
        if (g_parse_ok) log_err("表达式后有多余字符\n");
        ast_free(root);
        return 1;
    }
    if (!root) {
        log_err("解析失败\n");
        return 1;
    }

    log_info("解析成功 ✓\n");

    /* 绘制 */
    PlotConfig cfg = { xmin, xmax, width, height };
    plot(root, cfg);

    ast_free(root);
    return 0;
}
