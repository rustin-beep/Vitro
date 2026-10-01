/* hm.c —— Hindley-Milner 类型推断
 *
 * 编译: gcc -Wall -O2 -std=c11 -o hm hm.c
 * 运行: ./hm
 *
 * 算法 W:
 *   infer(env, Var(x))    = instantiate(env[x])
 *   infer(env, Lam(x, e)) = let tv = new_var()
 *                           in Fun(tv, infer(extend(env, x, tv), e))
 *   infer(env, App(f, a)) = let tf = infer(env, f), ta = infer(env, a)
 *                               tr = new_var()
 *                           in unify(tf, Fun(ta, tr)); tr
 *   infer(env, Let(x, v, b)) = let tv = infer(env, v)
 *                                  s  = generalize(env, tv)
 *                              in infer(extend(env, x, s), b)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

static char *mystrdup(const char *s) {
    size_t n = strlen(s) + 1;
    char *p = (char *)malloc(n);
    memcpy(p, s, n);
    return p;
}

/* ================================================================
 * 1. 类型
 *
 *   TY_VAR  类型变量，instance 指向绑定目标（NULL = 未绑定）
 *   TY_CON  类型构造子（Int、Bool、...）
 *   TY_FUN  函数类型：a -> b
 * ================================================================ */
typedef struct Type Type;
struct Type {
    enum { TY_VAR, TY_CON, TY_FUN } kind;
    char *name;
    Type *a, *b;
    Type *instance;
};

static int  g_var_counter = 0;
static char g_error[256];

static Type *new_var(void) {
    Type *t = (Type *)calloc(1, sizeof(Type));
    t->kind = TY_VAR;
    char buf[32];
    snprintf(buf, sizeof(buf), "t%d", g_var_counter++);
    t->name = mystrdup(buf);
    return t;
}

static Type *new_con(const char *name) {
    Type *t = (Type *)calloc(1, sizeof(Type));
    t->kind = TY_CON;
    t->name = mystrdup(name);
    return t;
}

static Type *new_fun(Type *from, Type *to) {
    Type *t = (Type *)calloc(1, sizeof(Type));
    t->kind = TY_FUN;
    t->a = from;
    t->b = to;
    return t;
}

/* 沿着绑定链把类型解析到底 */
static Type *prune(Type *t) {
    if (t->kind == TY_VAR && t->instance)
        return t->instance = prune(t->instance);
    return t;
}

/* occurs check：v 是否出现在 t 中 */
static bool occurs(Type *v, Type *t) {
    t = prune(t);
    if (t == v) return true;
    if (t->kind == TY_FUN)
        return occurs(v, t->a) || occurs(v, t->b);
    return false;
}

/* 合一：解方程 t1 = t2 */
static bool unify(Type *a, Type *b) {
    a = prune(a);
    b = prune(b);
    if (a == b) return true;

    if (a->kind == TY_VAR) {
        if (occurs(a, b)) {
            snprintf(g_error, sizeof(g_error),
                     "occurs check 失败: %s 出现在自身", a->name);
            return false;
        }
        a->instance = b;
        return true;
    }
    if (b->kind == TY_VAR) {
        if (occurs(b, a)) {
            snprintf(g_error, sizeof(g_error),
                     "occurs check 失败: %s 出现在自身", b->name);
            return false;
        }
        b->instance = a;
        return true;
    }
    if (a->kind == TY_CON && b->kind == TY_CON)
        return strcmp(a->name, b->name) == 0;
    if (a->kind == TY_FUN && b->kind == TY_FUN)
        return unify(a->a, b->a) && unify(a->b, b->b);

    snprintf(g_error, sizeof(g_error), "类型构造子不匹配");
    return false;
}

/* 打印：把未绑定的变量按遍历顺序命名 a, b, c, ... */
static void type_print_rec(Type *t, char **names, int *nn, bool paren) {
    t = prune(t);
    if (t->kind == TY_VAR) {
        for (int i = 0; i < *nn; i++) {
            if (strcmp(names[i], t->name) == 0) {
                if (i < 26) putchar('a' + i);
                else        printf("t%d", i);
                return;
            }
        }
        names[*nn] = t->name;
        if (*nn < 26) putchar('a' + *nn);
        else          printf("t%d", *nn);
        (*nn)++;
        return;
    }
    if (t->kind == TY_CON) { printf("%s", t->name); return; }

    /* 函数类型：左边是函数时加括号（右结合） */
    if (paren) putchar('(');
    type_print_rec(t->a, names, nn, true);
    printf(" -> ");
    type_print_rec(t->b, names, nn, false);
    if (paren) putchar(')');
}

static void type_print(Type *t) {
    char *names[64];
    int   nn = 0;
    type_print_rec(t, names, &nn, false);
}

/* ================================================================
 * 2. Scheme（带 ∀ 量化的类型）
 *
 *   Scheme { vars: [a, b], type: a -> b -> a }
 *   表示 ∀a b. a -> b -> a
 * ================================================================ */
typedef struct {
    char **vars;
    int    nvars;
    Type  *type;
} Scheme;

typedef struct {
    const char **names;
    Type       **vals;
    int          n;
} Subst;

static Type *subst_apply(Type *t, Subst *s) {
    t = prune(t);
    if (t->kind == TY_VAR) {
        for (int i = 0; i < s->n; i++)
            if (strcmp(t->name, s->names[i]) == 0) return s->vals[i];
        return t;
    }
    if (t->kind == TY_FUN)
        return new_fun(subst_apply(t->a, s), subst_apply(t->b, s));
    return t;
}

/* 实例化：把量化的变量换成全新的类型变量 */
static Type *instantiate(Scheme *s) {
    Type *vals[64];
    const char *names[64];
    for (int i = 0; i < s->nvars; i++) {
        vals[i]  = new_var();
        names[i] = s->vars[i];
    }
    Subst sub = { names, vals, s->nvars };
    return subst_apply(s->type, &sub);
}

static void collect_fv(Type *t, char **out, int *n) {
    t = prune(t);
    if (t->kind == TY_VAR) {
        for (int i = 0; i < *n; i++)
            if (strcmp(out[i], t->name) == 0) return;
        out[(*n)++] = t->name;
        return;
    }
    if (t->kind == TY_FUN) {
        collect_fv(t->a, out, n);
        collect_fv(t->b, out, n);
    }
}

/* ================================================================
 * 3. 环境
 * ================================================================ */
typedef struct Bind Bind;
struct Bind {
    char   *name;
    Scheme *scheme;
    Bind   *next;
};

static Bind *env_extend(Bind *env, const char *name, Scheme *s) {
    Bind *b = (Bind *)malloc(sizeof(Bind));
    b->name   = mystrdup(name);
    b->scheme = s;
    b->next   = env;
    return b;
}

static Scheme *env_lookup(Bind *env, const char *name) {
    for (Bind *b = env; b; b = b->next)
        if (strcmp(b->name, name) == 0) return b->scheme;
    return NULL;
}

static void env_fv(Bind *env, char **out, int *n) {
    for (Bind *b = env; b; b = b->next)
        collect_fv(b->scheme->type, out, n);
}

/* ================================================================
 * 4. 泛化：把类型中不在环境里自由的变量量化
 * ================================================================ */
static Scheme *scheme_mono(Type *t) {
    Scheme *s = (Scheme *)calloc(1, sizeof(Scheme));
    s->type = t;
    return s;
}

static Scheme *generalize(Bind *env, Type *t) {
    char *env_vars[256];
    int   nenv = 0;
    env_fv(env, env_vars, &nenv);

    char *t_vars[256];
    int   ntv = 0;
    collect_fv(t, t_vars, &ntv);

    char *q[256];
    int   nq = 0;
    for (int i = 0; i < ntv; i++) {
        bool in_env = false;
        for (int j = 0; j < nenv; j++)
            if (strcmp(t_vars[i], env_vars[j]) == 0) { in_env = true; break; }
        if (!in_env) q[nq++] = mystrdup(t_vars[i]);
    }

    Scheme *s = (Scheme *)calloc(1, sizeof(Scheme));
    s->vars  = (char **)malloc(sizeof(char *) * nq);
    for (int i = 0; i < nq; i++) s->vars[i] = q[i];
    s->nvars = nq;
    s->type  = t;
    return s;
}

/* ================================================================
 * 5. 表达式
 * ================================================================ */
typedef struct Expr Expr;
struct Expr {
    enum { E_VAR, E_LAM, E_APP, E_LET, E_LIT } kind;
    char *name;
    Expr *a, *b;
    int   lit;
};

static Expr *e_var(const char *n) {
    Expr *e = (Expr *)calloc(1, sizeof(Expr));
    e->kind = E_VAR; e->name = mystrdup(n); return e;
}
static Expr *e_lam(const char *p, Expr *b) {
    Expr *e = (Expr *)calloc(1, sizeof(Expr));
    e->kind = E_LAM; e->name = mystrdup(p); e->a = b; return e;
}
static Expr *e_app(Expr *f, Expr *x) {
    Expr *e = (Expr *)calloc(1, sizeof(Expr));
    e->kind = E_APP; e->a = f; e->b = x; return e;
}
static Expr *e_let(const char *n, Expr *v, Expr *b) {
    Expr *e = (Expr *)calloc(1, sizeof(Expr));
    e->kind = E_LET; e->name = mystrdup(n); e->a = v; e->b = b; return e;
}
static Expr *e_lit(int v) {
    Expr *e = (Expr *)calloc(1, sizeof(Expr));
    e->kind = E_LIT; e->lit = v; return e;
}

/* ================================================================
 * 6. 推断
 * ================================================================ */
static bool infer(Bind *env, Expr *e, Type **out) {
    switch (e->kind) {
    case E_VAR: {
        Scheme *s = env_lookup(env, e->name);
        if (!s) {
            snprintf(g_error, sizeof(g_error), "未绑定变量 %s", e->name);
            return false;
        }
        *out = instantiate(s);
        return true;
    }
    case E_LIT:
        *out = new_con("Int");
        return true;

    case E_LAM: {
        Type *tv = new_var();
        Bind *env2 = env_extend(env, e->name, scheme_mono(tv));
        Type *tb;
        if (!infer(env2, e->a, &tb)) return false;
        *out = new_fun(tv, tb);
        return true;
    }
    case E_APP: {
        Type *tf, *tx;
        if (!infer(env, e->a, &tf)) return false;
        if (!infer(env, e->b, &tx)) return false;
        Type *tr = new_var();
        if (!unify(tf, new_fun(tx, tr))) return false;
        *out = tr;
        return true;
    }
    case E_LET: {
        Type *tv;
        if (!infer(env, e->a, &tv)) return false;
        Scheme *s = generalize(env, tv);
        Bind *env2 = env_extend(env, e->name, s);
        return infer(env2, e->b, out);
    }
    }
    return false;
}

/* ================================================================
 * 7. 表达式打印
 * ================================================================ */
static void expr_print(Expr *e) {
    switch (e->kind) {
    case E_VAR: printf("%s", e->name); break;
    case E_LIT: printf("%d", e->lit);  break;
    case E_LAM: printf("(λ%s. ", e->name); expr_print(e->a); printf(")"); break;
    case E_APP: printf("("); expr_print(e->a);
                printf(" "); expr_print(e->b); printf(")"); break;
    case E_LET: printf("(let %s = ", e->name); expr_print(e->a);
                printf(" in "); expr_print(e->b); printf(")"); break;
    }
}

/* ================================================================
 * 8. 测试
 * ================================================================ */
static void try_expr(const char *desc, Expr *e) {
    printf("  \033[1;36m●\033[0m %s\n", desc);
    printf("    ");
    expr_print(e);
    printf("\n");

    g_var_counter = 0;
    Type *t = NULL;
    Bind *env = NULL;

    if (infer(env, e, &t)) {
        printf("    \033[1;32m=>\033[0m ");
        type_print(t);
        printf("\n\n");
    } else {
        printf("    \033[1;31m=> %s\033[0m\n\n", g_error);
    }
}

int main(void) {
    printf("\033[1;36m");
    printf("╔══════════════════════════════════════════════════╗\n");
    printf("║      Hindley-Milner 类型推断                    ║\n");
    printf("╚══════════════════════════════════════════════════╝\n");
    printf("\033[0m\n");

    /* ---- 基础 ---- */
    printf("\033[1;33m[基础]\033[0m\n");
    try_expr("恒等函数",
        e_lam("x", e_var("x")));

    try_expr("K 组合子",
        e_lam("x", e_lam("y", e_var("x"))));

    try_expr("反 K 组合子",
        e_lam("x", e_lam("y", e_var("y"))));

    try_expr("函数应用",
        e_lam("f", e_lam("x", e_app(e_var("f"), e_var("x")))));

    /* ---- 组合子 ---- */
    printf("\033[1;33m[经典组合子]\033[0m\n");
    try_expr("twice = λf. λx. f (f x)",
        e_lam("f", e_lam("x",
            e_app(e_var("f"), e_app(e_var("f"), e_var("x"))))));

    try_expr("compose = λf. λg. λx. f (g x)",
        e_lam("f", e_lam("g", e_lam("x",
            e_app(e_var("f"), e_app(e_var("g"), e_var("x")))))));

    try_expr("B 组合子 = λx. λy. λz. x (y z)",
        e_lam("x", e_lam("y", e_lam("z",
            e_app(e_var("x"), e_app(e_var("y"), e_var("z")))))));

    try_expr("S 组合子 = λf. λg. λx. f x (g x)",
        e_lam("f", e_lam("g", e_lam("x",
            e_app(e_app(e_var("f"), e_var("x")),
                  e_app(e_var("g"), e_var("x")))))));

    /* ---- let 多态 ---- */
    printf("\033[1;33m[let 多态]\033[0m\n");
    try_expr("let id = λx. x in id id",
        e_let("id",
              e_lam("x", e_var("x")),
              e_app(e_var("id"), e_var("id"))));

    try_expr("let f = λx. x in f f",
        e_let("f",
              e_lam("x", e_var("x")),
              e_app(e_var("f"), e_var("f"))));

    try_expr("let f = λx. x in λg. g (f 1) (f 2)",
        e_let("f",
              e_lam("x", e_var("x")),
              e_lam("g",
                  e_app(e_app(e_var("g"), e_app(e_var("f"), e_lit(1))),
                        e_app(e_var("f"), e_lit(2))))));

    /* ---- 类型错误 ---- */
    printf("\033[1;33m[类型错误 / 无类型]\033[0m\n");
    try_expr("λx. x x  （自应用 → 无限类型）",
        e_lam("x", e_app(e_var("x"), e_var("x"))));

    try_expr("1 1  （把整数当函数）",
        e_app(e_lit(1), e_lit(1)));

    try_expr("(λx. x) 1 2  （返回 Int 又当函数用）",
        e_app(e_app(e_lam("x", e_var("x")), e_lit(1)), e_lit(2)));

    /* ---- 说明 ---- */
    printf("\033[1;36m关键结论:\033[0m\n");
    printf("  · 每个表达式都推出最一般类型（principal type）\n");
    printf("  · let 引入多态: 同一个名字可实例化成多份独立类型\n");
    printf("  · λ 的参数是单态: λx. x x 因此无法推断\n");
    printf("  · occurs check 拦住无限类型: 拒绝 t = t -> u\n");
    printf("  · 全部机制 = 合一 + 泛化 + 实例化\n\n");

    return 0;
}
