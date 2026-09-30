/* regex.c —— 迷你正则表达式引擎（NFA）
 *
 * 支持: 字面字符 . * + ? | ( )
 * 不支持: 字符类 [ ]、锚点 ^ $、转义 \、计数 {n,m}
 *
 * 编译: gcc -Wall -O2 -o regex regex.c
 * 运行: ./regex
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ================================================================
 * 1. 语法树
 * ================================================================ */
enum NodeType { T_CHAR, T_ANY, T_CONCAT, T_ALT, T_STAR, T_PLUS, T_QMARK };

typedef struct Node {
    enum NodeType type;
    char          ch;
    struct Node  *l, *r;
} Node;

static Node *node_new(enum NodeType t, char ch, Node *l, Node *r)
{
    Node *n = (Node *)malloc(sizeof(Node));
    if (!n) { perror("malloc"); exit(1); }
    n->type = t;
    n->ch   = ch;
    n->l    = l;
    n->r    = r;
    return n;
}

/* ================================================================
 * 2. NFA 状态
 *    S_EPS     : ε 分支，两条出边都走
 *    S_CHAR    : 匹配一个指定字符
 *    S_ANY     : 匹配任意字符
 *    S_ACCEPT  : 接受状态
 * ================================================================ */
enum { S_EPS, S_CHAR, S_ANY, S_ACCEPT };

typedef struct State {
    int           type;
    char          ch;
    struct State *out1, *out2;
} State;

#define MAX_STATES 1024
static State g_states[MAX_STATES];
static int   g_nstates;

static State *state_new(int type, char ch, State *o1, State *o2)
{
    if (g_nstates >= MAX_STATES) {
        fprintf(stderr, "NFA 状态数超出上限\n");
        exit(1);
    }
    State *s = &g_states[g_nstates++];
    s->type = type;
    s->ch   = ch;
    s->out1 = o1;
    s->out2 = o2;
    return s;
}

/* ================================================================
 * 3. 递归下降解析器
 *
 *    表达式 -> 项 ('|' 项)*
 *    项     -> 因子+
 *    因子   -> 原子 ('*' | '+' | '?')*
 *    原子   -> 字符 | '.' | '(' 表达式 ')'
 * ================================================================ */
static const char *g_pat;
static int         g_err;

static Node *parse_expr(void);
static Node *parse_term(void);
static Node *parse_factor(void);
static Node *parse_atom(void);

static Node *parse_atom(void)
{
    char c = *g_pat;

    if (c == '(') {
        g_pat++;
        Node *n = parse_expr();
        if (*g_pat != ')') { g_err = 1; return NULL; }
        g_pat++;
        return n;
    }
    if (c == '.') {
        g_pat++;
        return node_new(T_ANY, 0, NULL, NULL);
    }
    if (c == '\0' || strchr("|)*+?", c)) {
        g_err = 1;
        return NULL;
    }
    g_pat++;
    return node_new(T_CHAR, c, NULL, NULL);
}

static Node *parse_factor(void)
{
    Node *n = parse_atom();
    if (!n) return NULL;

    for (;;) {
        char c = *g_pat;
        if      (c == '*') { g_pat++; n = node_new(T_STAR,  0, n, NULL); }
        else if (c == '+') { g_pat++; n = node_new(T_PLUS,  0, n, NULL); }
        else if (c == '?') { g_pat++; n = node_new(T_QMARK, 0, n, NULL); }
        else break;
    }
    return n;
}

static Node *parse_term(void)
{
    Node *left = parse_factor();
    if (!left) return NULL;

    while (*g_pat != '\0' && *g_pat != '|' && *g_pat != ')') {
        Node *right = parse_factor();
        if (!right) return left;
        left = node_new(T_CONCAT, 0, left, right);
    }
    return left;
}

static Node *parse_expr(void)
{
    Node *left = parse_term();
    if (!left) return NULL;

    while (*g_pat == '|') {
        g_pat++;
        Node *right = parse_term();
        if (!right) return left;
        left = node_new(T_ALT, 0, left, right);
    }
    return left;
}

/* ================================================================
 * 4. 编译 AST → NFA
 *
 *    compile(n, next) 返回一个 NFA 片段，其"出口"连接到 next。
 *    这是 Thompson 构造法最简洁的写法——用函数返回值当"线"，
 *    把整个 NFA 串起来。
 * ================================================================ */
static State *compile(Node *n, State *next)
{
    if (!n) return next;

    switch (n->type) {
    case T_CHAR:
        return state_new(S_CHAR, n->ch, next, NULL);

    case T_ANY:
        return state_new(S_ANY, 0, next, NULL);

    case T_CONCAT:
        /* ab: 先编译 b 拿到"从 b 出发到 next 的片段"，
         * 再让 a 的出口连到 b 的入口 */
        return compile(n->l, compile(n->r, next));

    case T_ALT: {
        /* a|b: 一个 ε 分支，两条路都连到 next */
        State *sa = compile(n->l, next);
        State *sb = compile(n->r, next);
        return state_new(S_EPS, 0, sa, sb);
    }

    case T_STAR: {
        /* a*: ε 分支 s：一条进 a，一条跳过直接到 next
         *      a 的出口连回 s，形成环 */
        State *s    = state_new(S_EPS, 0, NULL, next);
        State *body = compile(n->l, s);
        s->out1 = body;
        return s;
    }

    case T_PLUS: {
        /* a+: 先走一次 a，a 的出口再分支：回 a 或到 next */
        State *s    = state_new(S_EPS, 0, NULL, next);
        State *body = compile(n->l, s);
        s->out1 = body;
        return body;
    }

    case T_QMARK: {
        /* a?: ε 分支：走 a 或跳过 */
        State *sa = compile(n->l, next);
        return state_new(S_EPS, 0, sa, next);
    }
    }
    return next;
}

/* ================================================================
 * 5. NFA 模拟
 *
 *    核心思想：同一时刻"我可能处在的所有状态"构成一个集合。
 *    每读一个字符，就集体转移一次；末尾若集合含 accept 即成功。
 *    ε 闭包用递归展开，靠 visited 时间戳防环。
 * ================================================================ */
static int g_visited[MAX_STATES];
static int g_visit_id = 0;

static void add_state(State *s, State **list, int *n)
{
    if (!s) return;

    int idx = (int)(s - g_states);
    if (g_visited[idx] == g_visit_id) return;
    g_visited[idx] = g_visit_id;

    if (s->type == S_EPS) {
        add_state(s->out1, list, n);
        add_state(s->out2, list, n);
    } else {
        list[(*n)++] = s;
    }
}

/* 返回 1 匹配 / 0 不匹配 / -1 语法错误 */
int regex_match(const char *pattern, const char *text)
{
    g_nstates = 0;
    g_pat     = pattern;
    g_err     = 0;

    Node *ast = parse_expr();
    if (g_err || *g_pat != '\0') return -1;

    State *start = compile(ast, state_new(S_ACCEPT, 0, NULL, NULL));

    State *cur[MAX_STATES], *next[MAX_STATES];
    int    ncur = 0;

    g_visit_id++;
    add_state(start, cur, &ncur);

    for (const char *p = text; ; p++) {
        if (*p == '\0') {
            for (int i = 0; i < ncur; i++)
                if (cur[i]->type == S_ACCEPT) return 1;
            return 0;
        }

        int nnext = 0;
        g_visit_id++;
        for (int i = 0; i < ncur; i++) {
            State *s = cur[i];
            if ((s->type == S_CHAR && s->ch == *p) || s->type == S_ANY)
                add_state(s->out1, next, &nnext);
        }

        memcpy(cur, next, (size_t)nnext * sizeof(State *));
        ncur = nnext;
    }
}

/* ================================================================
 * 6. 演示
 * ================================================================ */
static void test(const char *pattern, const char *text)
{
    int r = regex_match(pattern, text);
    const char *verdict =
        (r ==  1) ? "✓ 匹配" :
        (r ==  0) ? "✗ 不匹配" : "⚠ 语法错误";

    printf("  /%-12s/  vs  \"%-14s\"  →  %s\n", pattern, text, verdict);
}

int main(void)
{
    printf("=== 迷你正则引擎（Thompson NFA） ===\n\n");

    printf("[ 字面字符 ]\n");
    test("abc", "abc");
    test("abc", "abd");
    test("abc", "ab");

    printf("\n[ . 任意字符 ]\n");
    test("a.c", "abc");
    test("a.c", "a c");
    test("a.c", "ac");

    printf("\n[ * 零次或多次 ]\n");
    test("ab*c", "ac");
    test("ab*c", "abc");
    test("ab*c", "abbbbc");
    test("ab*c", "abd");

    printf("\n[ + 一次或多次 ]\n");
    test("ab+c", "ac");
    test("ab+c", "abc");
    test("ab+c", "abbbc");

    printf("\n[ ? 零次或一次 ]\n");
    test("ab?c", "ac");
    test("ab?c", "abc");
    test("ab?c", "abbc");

    printf("\n[ | 交替 ]\n");
    test("cat|dog", "cat");
    test("cat|dog", "dog");
    test("cat|dog", "bird");

    printf("\n[ () 分组 ]\n");
    test("(ab)+", "ab");
    test("(ab)+", "ababab");
    test("(ab)+", "aba");
    test("a(b|c)d", "abd");
    test("a(b|c)d", "acd");
    test("a(b|c)d", "aad");

    printf("\n[ 组合 ]\n");
    test("(a|b)*c", "c");
    test("(a|b)*c", "abc");
    test("(a|b)*c", "bbac");
    test("(a|b)*c", "abd");
    test("h.*o",   "hello");
    test("h.*o",   "hi");
    test("(0|1)+", "0101");
    test("(0|1)+", "012");

    printf("\n[ 边界 ]\n");
    test("a*",     "");
    test("a*",     "aaa");
    test(".*",     "");
    test(".*",     "随便什么内容");
    test("a",      "");

    printf("\n[ 语法错误 ]\n");
    test("*a",     "abc");
    test("a(b",    "ab");
    test("a|",     "a");

    return 0;
}
