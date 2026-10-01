/* sccp.c —— SSA + 稀疏条件常量传播
 *
 * 编译: gcc -Wall -O2 -std=c11 -o sccp sccp.c
 * 运行: ./sccp
 *
 * 格:
 *         ⊤ (UNDEF)    还没信息
 *         |
 *      常量 c         已知是常量 c
 *         |
 *         ⊥ (NAC)     不是常量
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_BLOCKS 16
#define MAX_VALS   64

/* ================================================================
 * IR
 * ================================================================ */
enum {
    V_CONST,
    V_ADD, V_SUB, V_MUL,
    V_LT,  V_LE,  V_EQ,
    V_COPY,
    V_PHI
};

typedef struct {
    int op;
    int imm;
    int a, b;
    int phi_n;
    int phi_v[4];
    int phi_b[4];
    const char *name;
} Value;

typedef struct {
    int first_val;
    int n_val;
    int br_val;
    int succ_t;
    int succ_f;
    const char *label;
} Block;

typedef struct {
    Value  vals[MAX_VALS];
    int    nvals;
    Block  blocks[MAX_BLOCKS];
    int    nblocks;
} Prog;

/* ================================================================
 * 格状态
 * ================================================================ */
enum { ST_UNDEF, ST_CONST, ST_NAC };

typedef struct {
    int  state[MAX_VALS];
    long cval[MAX_VALS];
    int  reachable[MAX_BLOCKS];
    int  edge[MAX_BLOCKS][2];
    int  niter;
} Result;

/* ================================================================
 * 构造辅助
 * ================================================================ */
static int new_val(Prog *p, int op, const char *name) {
    int i = p->nvals++;
    Value *v = &p->vals[i];
    v->op = op;
    v->imm = 0;
    v->a = v->b = -1;
    v->phi_n = 0;
    v->name = name;
    return i;
}

static int new_const(Prog *p, const char *name, int imm) {
    int i = new_val(p, V_CONST, name);
    p->vals[i].imm = imm;
    return i;
}

static int new_binop(Prog *p, int op, const char *name, int a, int b) {
    int i = new_val(p, op, name);
    p->vals[i].a = a;
    p->vals[i].b = b;
    return i;
}

static int new_phi(Prog *p, const char *name) {
    return new_val(p, V_PHI, name);
}

static void phi_add(Prog *p, int phi, int val, int block) {
    Value *v = &p->vals[phi];
    v->phi_v[v->phi_n] = val;
    v->phi_b[v->phi_n] = block;
    v->phi_n++;
}

static void block_init(Prog *p, int bi, const char *label) {
    p->blocks[bi].first_val = p->nvals;
    p->blocks[bi].n_val = 0;
    p->blocks[bi].br_val = -1;
    p->blocks[bi].succ_t = -1;
    p->blocks[bi].succ_f = -1;
    p->blocks[bi].label = label;
    if (bi >= p->nblocks) p->nblocks = bi + 1;
}

static void block_end(Prog *p, int bi) {
    p->blocks[bi].n_val = p->nvals - p->blocks[bi].first_val;
}

static void block_br(Prog *p, int bi, int val, int t, int f) {
    p->blocks[bi].br_val = val;
    p->blocks[bi].succ_t = t;
    p->blocks[bi].succ_f = f;
}

static void block_jmp(Prog *p, int bi, int t) {
    p->blocks[bi].br_val = -1;
    p->blocks[bi].succ_t = t;
}

/* ================================================================
 * 求值
 * ================================================================ */
static long eval_binop(int op, long a, long b) {
    switch (op) {
    case V_ADD: return a + b;
    case V_SUB: return a - b;
    case V_MUL: return a * b;
    case V_LT:  return a <  b;
    case V_LE:  return a <= b;
    case V_EQ:  return a == b;
    }
    return 0;
}

static int eval_value(Prog *p, Result *r, int vi) {
    Value *v = &p->vals[vi];
    int  old_state = r->state[vi];
    long old_cval  = r->cval[vi];

    if (v->op == V_CONST) {
        r->state[vi] = ST_CONST;
        r->cval[vi]  = v->imm;
    }
    else if (v->op == V_PHI) {
        int  any_nac   = 0;
        int  has_const = 0;
        long cval      = 0;
        int  has_undef = 0;

        for (int i = 0; i < v->phi_n; i++) {
            if (!r->reachable[v->phi_b[i]]) continue;
            int pv = v->phi_v[i];
            if (r->state[pv] == ST_NAC) {
                any_nac = 1;
                break;
            } else if (r->state[pv] == ST_UNDEF) {
                has_undef = 1;
            } else {
                if (!has_const) { cval = r->cval[pv]; has_const = 1; }
                else if (r->cval[pv] != cval) { any_nac = 1; break; }
            }
        }

        if (any_nac)
            r->state[vi] = ST_NAC;
        else if (has_const && !has_undef) {
            r->state[vi] = ST_CONST;
            r->cval[vi]  = cval;
        }
    }
    else if (v->op == V_COPY) {
        r->state[vi] = r->state[v->a];
        r->cval[vi]  = r->cval[v->a];
    }
    else {
        int sa = r->state[v->a];
        int sb = r->state[v->b];
        if (sa == ST_NAC || sb == ST_NAC) {
            r->state[vi] = ST_NAC;
        } else if (sa == ST_CONST && sb == ST_CONST) {
            r->state[vi] = ST_CONST;
            r->cval[vi]  = eval_binop(v->op, r->cval[v->a], r->cval[v->b]);
        }
    }

    return (r->state[vi] != old_state ||
            (r->state[vi] == ST_CONST && r->cval[vi] != old_cval));
}

/* ================================================================
 * SCCP 主循环
 * ================================================================ */
static void sccp(Prog *p, Result *r) {
    memset(r, 0, sizeof(*r));
    r->reachable[0] = 1;

    int changed = 1;
    r->niter = 0;

    while (changed) {
        changed = 0;
        r->niter++;
        if (r->niter > 200) break;

        for (int bi = 0; bi < p->nblocks; bi++) {
            if (!r->reachable[bi]) continue;
            Block *b = &p->blocks[bi];

            for (int k = 0; k < b->n_val; k++) {
                int vi = b->first_val + k;
                if (eval_value(p, r, vi)) changed = 1;
            }

            if (b->br_val < 0) {
                if (!r->edge[bi][0]) {
                    r->edge[bi][0] = 1;
                    if (!r->reachable[b->succ_t]) {
                        r->reachable[b->succ_t] = 1;
                        changed = 1;
                    }
                }
            } else {
                int st = r->state[b->br_val];
                if (st == ST_CONST) {
                    int t = (r->cval[b->br_val] != 0);
                    int target = t ? b->succ_t : b->succ_f;
                    int idx    = t ? 0 : 1;
                    if (!r->edge[bi][idx]) {
                        r->edge[bi][idx] = 1;
                        if (!r->reachable[target]) {
                            r->reachable[target] = 1;
                            changed = 1;
                        }
                    }
                } else if (st == ST_NAC) {
                    for (int e = 0; e < 2; e++) {
                        int target = e ? b->succ_f : b->succ_t;
                        if (!r->edge[bi][e]) {
                            r->edge[bi][e] = 1;
                            if (!r->reachable[target]) {
                                r->reachable[target] = 1;
                                changed = 1;
                            }
                        }
                    }
                }
            }
        }
    }
}

/* ================================================================
 * 打印
 * ================================================================ */
static const char *op_sym(int op) {
    switch (op) {
    case V_ADD: return "+";
    case V_SUB: return "-";
    case V_MUL: return "*";
    case V_LT:  return "<";
    case V_LE:  return "<=";
    case V_EQ:  return "==";
    }
    return "?";
}

static void print_program(const Prog *p) {
    printf("\n\033[1;36m[原始 SSA 程序]\033[0m\n");
    for (int bi = 0; bi < p->nblocks; bi++) {
        const Block *b = &p->blocks[bi];
        printf("  \033[1;33mB%-2d\033[0m \033[90m(%s)\033[0m:\n", bi, b->label);

        for (int k = 0; k < b->n_val; k++) {
            const Value *v = &p->vals[b->first_val + k];
            printf("      %-6s = ", v->name);
            switch (v->op) {
            case V_CONST:
                printf("const %d", v->imm);
                break;
            case V_COPY:
                printf("%s", p->vals[v->a].name);
                break;
            case V_PHI: {
                printf("phi(");
                for (int i = 0; i < v->phi_n; i++) {
                    if (i) printf(", ");
                    printf("%s:B%d",
                           p->vals[v->phi_v[i]].name, v->phi_b[i]);
                }
                printf(")");
                break;
            }
            default:
                printf("%s %s %s",
                       p->vals[v->a].name, op_sym(v->op),
                       p->vals[v->b].name);
            }
            printf("\n");
        }

        if (b->br_val < 0)
            printf("      \033[35mgoto B%d\033[0m\n", b->succ_t);
        else
            printf("      \033[35mif %s goto B%d else B%d\033[0m\n",
                   p->vals[b->br_val].name, b->succ_t, b->succ_f);
    }
}

static void print_result(const Prog *p, const Result *r) {
    printf("\n\033[1;36m[SCCP 结果]\033[0m\n");

    for (int bi = 0; bi < p->nblocks; bi++) {
        const Block *b = &p->blocks[bi];
        const char *bstat = r->reachable[bi]
            ? "\033[1;32m可达\033[0m"
            : "\033[1;31m不可达\033[0m";
        printf("  \033[1;33mB%-2d\033[0m  %s\n", bi, bstat);
        if (!r->reachable[bi]) continue;

        for (int k = 0; k < b->n_val; k++) {
            int vi = b->first_val + k;
            const Value *v = &p->vals[vi];

            printf("      %-6s = ", v->name);

            if (r->state[vi] == ST_CONST)
                printf("\033[1;32m常量 %ld\033[0m", r->cval[vi]);
            else if (r->state[vi] == ST_NAC)
                printf("\033[1;33mNAC（非常量）\033[0m");
            else
                printf("\033[90mUNDEF\033[0m");

            printf("   \033[90m[");
            switch (v->op) {
            case V_CONST: printf("const %d", v->imm); break;
            case V_COPY:  printf("%s", p->vals[v->a].name); break;
            case V_PHI: {
                printf("phi(");
                for (int i = 0; i < v->phi_n; i++) {
                    if (i) printf(",");
                    printf("%s:B%d", p->vals[v->phi_v[i]].name, v->phi_b[i]);
                }
                printf(")");
                break;
            }
            default:
                printf("%s %s %s",
                       p->vals[v->a].name, op_sym(v->op),
                       p->vals[v->b].name);
            }
            printf("]\033[0m\n");
        }

        if (b->br_val < 0) {
            printf("      \033[35mgoto B%d\033[0m", b->succ_t);
            if (r->edge[bi][0]) printf("  \033[1;32m[保留]\033[0m");
            printf("\n");
        } else {
            int st = r->state[b->br_val];
            if (st == ST_CONST) {
                int t = (r->cval[b->br_val] != 0);
                printf("      \033[35mif %s goto B%d else B%d\033[0m"
                       "  \033[1;32m[条件恒为 %s，另一条边被删]\033[0m\n",
                       p->vals[b->br_val].name, b->succ_t, b->succ_f,
                       t ? "真" : "假");
            } else if (st == ST_NAC) {
                printf("      \033[35mif %s goto B%d else B%d\033[0m"
                       "  \033[90m[两条边都保留]\033[0m\n",
                       p->vals[b->br_val].name, b->succ_t, b->succ_f);
            } else {
                printf("      \033[35mif %s goto B%d else B%d\033[0m"
                       "  \033[90m[条件未知]\033[0m\n",
                       p->vals[b->br_val].name, b->succ_t, b->succ_f);
            }
        }
    }
}

/* ================================================================
 * 三个演示
 * ================================================================ */
static void demo1_constant_folding(void) {
    printf("\n\033[1;35m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n");
    printf("\033[1;35m  演示 1：常量折叠\033[0m\n");
    printf("\033[1;35m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n");
    printf("  x = 5; y = 3; z = x + y; w = z * 2;\n");

    Prog p;
    memset(&p, 0, sizeof(p));
    block_init(&p, 0, "entry");

    int x = new_const(&p, "x", 5);
    int y = new_const(&p, "y", 3);
    int z = new_binop(&p, V_ADD, "z", x, y);
    int two = new_const(&p, "two", 2);
    int w = new_binop(&p, V_MUL, "w", z, two);
    int r = new_val(&p, V_COPY, "ret");
    p.vals[r].a = w;

    block_end(&p, 0);
    block_jmp(&p, 0, 0);

    print_program(&p);
    Result res;
    sccp(&p, &res);
    print_result(&p, &res);

    printf("\n  \033[1;32m分析结论:\033[0m z 恒为 8，w 恒为 16\n");
}

static void demo2_dead_branch(void) {
    printf("\n\033[1;35m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n");
    printf("\033[1;35m  演示 2：常量条件 → 死分支\033[0m\n");
    printf("\033[1;35m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n");
    printf("  if (1) { y = 100; } else { y = 200; }\n");

    Prog p;
    memset(&p, 0, sizeof(p));

    block_init(&p, 0, "entry");
    int c = new_const(&p, "c", 1);
    block_end(&p, 0);
    block_br(&p, 0, c, 1, 2);

    block_init(&p, 1, "then");
    int y1 = new_const(&p, "y1", 100);
    block_end(&p, 1);
    block_jmp(&p, 1, 3);

    block_init(&p, 2, "else");
    int y2 = new_const(&p, "y2", 200);
    block_end(&p, 2);
    block_jmp(&p, 2, 3);

    block_init(&p, 3, "merge");
    int y = new_phi(&p, "y");
    phi_add(&p, y, y1, 1);
    phi_add(&p, y, y2, 2);
    block_end(&p, 3);
    block_jmp(&p, 3, 3);

    print_program(&p);
    Result res;
    sccp(&p, &res);
    print_result(&p, &res);

    printf("\n  \033[1;32m分析结论:\033[0m B2 不可达；y 被推断为常量 100\n");
}

static void demo3_loop(void) {
    printf("\n\033[1;35m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n");
    printf("\033[1;35m  演示 3：循环 → phi 合并\033[0m\n");
    printf("\033[1;35m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n");
    printf("  i = 0; while (i < 3) { i = i + 1; }\n");

    Prog p;
    memset(&p, 0, sizeof(p));

    block_init(&p, 0, "entry");
    int i0 = new_const(&p, "i0", 0);
    int three = new_const(&p, "three", 3);
    block_end(&p, 0);
    block_jmp(&p, 0, 1);

    block_init(&p, 1, "header");
    int i1 = new_phi(&p, "i");
    phi_add(&p, i1, i0, 0);
    int cmp = new_binop(&p, V_LT, "cmp", i1, three);
    block_end(&p, 1);
    block_br(&p, 1, cmp, 2, 3);

    block_init(&p, 2, "body");
    int one = new_const(&p, "one", 1);
    int i2 = new_binop(&p, V_ADD, "i2", i1, one);
    block_end(&p, 2);
    block_jmp(&p, 2, 1);

    phi_add(&p, i1, i2, 2);

    block_init(&p, 3, "exit");
    int r = new_val(&p, V_COPY, "ret");
    p.vals[r].a = i1;
    block_end(&p, 3);
    block_jmp(&p, 3, 3);

    print_program(&p);
    Result res;
    sccp(&p, &res);
    print_result(&p, &res);

    printf("\n  \033[1;32m分析结论:\033[0m\n");
    printf("    · 第一次进入 header 时 i=0，cmp=0<3=真 → body 可达\n");
    printf("    · body 算出 i2=1，回到 header → phi 看到 {0, 1} → NAC\n");
    printf("    · i 变成 NAC 后 cmp 也 NAC，exit 变可达\n");
    printf("    · SCCP 正确地找到了循环的“不动点”\n");
}

/* ================================================================
 * main
 * ================================================================ */
int main(void) {
    printf("\033[1;36m");
    printf("╔══════════════════════════════════════════════════════╗\n");
    printf("║   SSA + 稀疏条件常量传播（SCCP）                     ║\n");
    printf("╚══════════════════════════════════════════════════════╝\n");
    printf("\033[0m");

    demo1_constant_folding();
    demo2_dead_branch();
    demo3_loop();

    printf("\n\033[1;36m");
    printf("╔══════════════════════════════════════════════════════╗\n");
    printf("║   要点总结                                          ║\n");
    printf("╠══════════════════════════════════════════════════════╣\n");
    printf("║ · 格: UNDEF → CONST → NAC（单向，只会往“更坏”走） ║\n");
    printf("║ · 两条信息同时传播: 常量值 + 可达性                 ║\n");
    printf("║ · 常量分支只保留一条边 → 另一侧的块直接不可达       ║\n");
    printf("║ · phi 只看可达前驱，循环的不动点靠反复迭代到达      ║\n");
    printf("║ · 一遍 SCCP = 常量折叠 + 死代码消除 + 分支化简      ║\n");
    printf("╚══════════════════════════════════════════════════════╝\n");
    printf("\033[0m");

    return 0;
}