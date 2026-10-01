/* vliw.c —— 完整 VLIW 调度器
 *
 * 编译: gcc -Wall -O2 -std=c11 -o vliw vliw.c
 * 运行: ./vliw
 *
 * 同时包含:
 *   1. 多发射 (4 宽)
 *   2. 循环展开
 *   3. 软件流水 (调度器自动重叠迭代)
 *   4. 寄存器压力感知
 *   5. VLIW 打包
 *   6. 真实流水线模型 (发射 / 执行 / 写回)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdarg.h>

#define MAX_INSN    64
#define N_REGS      32
#define WIDTH       4
#define MAX_CYCLES  64
#define PRESSURE_TH 8
#define UNROLL      3

/* ================================================================
 * 指令与功能单元
 * ================================================================ */
typedef enum { OP_ADD, OP_SUB, OP_MUL, OP_LOAD, OP_STORE } Op;

#define FU_ALU0 0
#define FU_ALU1 1
#define FU_MUL  2
#define FU_MEM  3

static const char *op_name(Op op) {
    switch (op) {
    case OP_ADD:   return "ADD";
    case OP_SUB:   return "SUB";
    case OP_MUL:   return "MUL";
    case OP_LOAD:  return "LOAD";
    case OP_STORE: return "STORE";
    }
    return "?";
}

static int op_latency(Op op) {
    switch (op) {
    case OP_ADD:   return 1;
    case OP_SUB:   return 1;
    case OP_MUL:   return 3;
    case OP_LOAD:  return 4;
    case OP_STORE: return 1;
    }
    return 1;
}

static bool op_can_use_fu(Op op, int fu) {
    switch (op) {
    case OP_ADD:
    case OP_SUB:   return fu == FU_ALU0 || fu == FU_ALU1;
    case OP_MUL:   return fu == FU_MUL;
    case OP_LOAD:
    case OP_STORE: return fu == FU_MEM;
    }
    return false;
}

static const char *fu_name(int fu) {
    static const char *names[] = {"ALU0", "ALU1", "MUL", "MEM"};
    return (fu >= 0 && fu < 4) ? names[fu] : "???";
}

/* ================================================================
 * 指令
 * ================================================================ */
typedef struct {
    Op   op;
    int  dst, src1, src2;
    char text[80];

    int  dep1, dep2;       /* 依赖指令索引 */
    int  priority;         /* 关键路径长度 */
    int  n_users;          /* 使用 dst 的次数 */

    int  issue_cycle;
    int  fu_used;
    int  done_cycle;
    bool done;
} Insn;

typedef struct {
    Insn insns[MAX_INSN];
    int  n;
    int  n_vregs;
} Program;

/* ================================================================
 * 构建展开的循环
 *
 * 原始:
 *   for i: a[i] = b[i] + c[i] * d[i]
 * ================================================================ */
static int emit(Program *p, Op op, int dst, int src1, int src2,
                const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    Insn *ins = &p->insns[p->n];
    memset(ins, 0, sizeof(*ins));
    ins->op   = op;
    ins->dst  = dst;
    ins->src1 = src1;
    ins->src2 = src2;
    ins->dep1 = ins->dep2 = -1;
    ins->issue_cycle = -1;
    ins->fu_used = -1;
    ins->done_cycle = -1;
    vsnprintf(ins->text, sizeof(ins->text), fmt, ap);
    va_end(ap);
    return p->n++;
}

static void build_program(Program *p) {
    memset(p, 0, sizeof(*p));
    int next = 0;

    for (int u = 0; u < UNROLL; u++) {
        int rb = next++;    /* b[i] */
        int rc = next++;    /* c[i] */
        int rd = next++;    /* d[i] */
        int rt = next++;    /* c*d */
        int rs = next++;    /* b + c*d */

        emit(p, OP_LOAD, rb, -1, -1,
             "r%-2d=mem[B%+d]", rb, u*4);
        emit(p, OP_LOAD, rc, -1, -1,
             "r%-2d=mem[B%+d]", rc, u*4+4);
        emit(p, OP_LOAD, rd, -1, -1,
             "r%-2d=mem[B%+d]", rd, u*4+8);
        emit(p, OP_MUL, rt, rc, rd,
             "r%-2d=r%d*r%d", rt, rc, rd);
        emit(p, OP_ADD, rs, rb, rt,
             "r%-2d=r%d+r%d", rs, rb, rt);
        emit(p, OP_STORE, -1, rs, -1,
             "mem[A%+d]=r%d", u*4, rs);
    }
    p->n_vregs = next;
}

/* ================================================================
 * 依赖
 * ================================================================ */
static void build_deps(Program *p) {
    int last_writer[N_REGS];
    for (int i = 0; i < N_REGS; i++) last_writer[i] = -1;

    for (int i = 0; i < p->n; i++) {
        Insn *ins = &p->insns[i];

        if (ins->src1 >= 0) {
            ins->dep1 = last_writer[ins->src1];
            if (ins->dep1 >= 0) p->insns[ins->dep1].n_users++;
        }
        if (ins->src2 >= 0) {
            ins->dep2 = last_writer[ins->src2];
            if (ins->dep2 >= 0) p->insns[ins->dep2].n_users++;
        }
        if (ins->dst >= 0) last_writer[ins->dst] = i;
    }
}

/* ================================================================
 * 关键路径优先级
 * ================================================================ */
static void compute_priority(Program *p) {
    for (int i = p->n - 1; i >= 0; i--) {
        int pri = op_latency(p->insns[i].op);
        for (int j = i + 1; j < p->n; j++) {
            Insn *succ = &p->insns[j];
            if (succ->dep1 == i || succ->dep2 == i) {
                int cand = op_latency(p->insns[i].op) + succ->priority;
                if (cand > pri) pri = cand;
            }
        }
        p->insns[i].priority = pri;
    }
}

/* ================================================================
 * VLIW 调度
 * ================================================================ */
typedef struct {
    int slots[WIDTH];       /* 每个 FU 槽位对应的指令索引，-1 表示空 */
} Bundle;

static Bundle g_bundles[MAX_CYCLES];
static int    g_reg_ready[N_REGS];

/* 尝试在 cycle 发射: 尽量填满 4 个功能单元 */
static void issue_at(Program *p, int cycle,
                     int *pressure, int *remaining,
                     int *n_done) {
    for (int fu = 0; fu < WIDTH; fu++) {
        if (g_bundles[cycle].slots[fu] != -1) continue;

        int best = -1, best_pri = -1;
        for (int i = 0; i < p->n; i++) {
            Insn *ins = &p->insns[i];
            if (ins->done) continue;
            if (!op_can_use_fu(ins->op, fu)) continue;

            /* 依赖必须已发射 */
            if (ins->dep1 >= 0 && !p->insns[ins->dep1].done) continue;
            if (ins->dep2 >= 0 && !p->insns[ins->dep2].done) continue;

            /* 源操作数必须已就绪 */
            if (ins->src1 >= 0 && g_reg_ready[ins->src1] > cycle) continue;
            if (ins->src2 >= 0 && g_reg_ready[ins->src2] > cycle) continue;

            /* 压力检查: 发射后若超过阈值则跳过 */
            int delta = 0;
            if (ins->dst >= 0) delta += 1;
            if (ins->src1 >= 0 && remaining[ins->src1] == 1) delta -= 1;
            if (ins->src2 >= 0 && remaining[ins->src2] == 1) delta -= 1;
            if (*pressure + delta > PRESSURE_TH) continue;

            if (ins->priority > best_pri) {
                best_pri = ins->priority;
                best = i;
            }
        }

        if (best < 0) continue;

        Insn *ins = &p->insns[best];
        ins->issue_cycle = cycle;
        ins->fu_used     = fu;
        ins->done_cycle  = cycle + op_latency(ins->op);
        ins->done        = true;
        (*n_done)++;

        if (ins->dst >= 0) {
            (*pressure)++;
            g_reg_ready[ins->dst] = ins->done_cycle;
        }
        if (ins->src1 >= 0) {
            remaining[ins->src1]--;
            if (remaining[ins->src1] == 0) (*pressure)--;
        }
        if (ins->src2 >= 0) {
            remaining[ins->src2]--;
            if (remaining[ins->src2] == 0) (*pressure)--;
        }

        g_bundles[cycle].slots[fu] = best;
    }
}

static int schedule(Program *p) {
    for (int c = 0; c < MAX_CYCLES; c++)
        for (int f = 0; f < WIDTH; f++)
            g_bundles[c].slots[f] = -1;
    memset(g_reg_ready, 0, sizeof(g_reg_ready));

    int remaining[N_REGS] = {0};
    for (int i = 0; i < p->n; i++) {
        if (p->insns[i].src1 >= 0) remaining[p->insns[i].src1]++;
        if (p->insns[i].src2 >= 0) remaining[p->insns[i].src2]++;
    }

    int pressure = 0;
    int n_done   = 0;
    int max_used = 0;

    for (int cycle = 0; cycle < MAX_CYCLES && n_done < p->n; cycle++) {
        issue_at(p, cycle, &pressure, remaining, &n_done);
        bool used = false;
        for (int f = 0; f < WIDTH; f++)
            if (g_bundles[cycle].slots[f] >= 0) used = true;
        if (used) max_used = cycle + 1;
    }
    return max_used;
}

/* ================================================================
 * 打印
 * ================================================================ */
static void print_program(Program *p) {
    printf("\n  \033[1;36m[展开后 IR: %d 条指令]\033[0m\n", p->n);
    for (int i = 0; i < p->n; i++) {
        Insn *ins = &p->insns[i];
        printf("    %2d  %-5s  %-16s  pri=%-2d  dep=",
               i, op_name(ins->op), ins->text, ins->priority);
        if (ins->dep1 < 0 && ins->dep2 < 0) printf("—");
        else {
            if (ins->dep1 >= 0) printf("#%d", ins->dep1);
            if (ins->dep2 >= 0) printf(",#%d", ins->dep2);
        }
        printf("\n");
    }
}

static void print_bundles(Program *p, int max_cycle) {
    printf("\n  \033[1;36m[VLIW 包: 每周期最多 %d 条]\033[0m\n", WIDTH);
    printf("    周期 | ALU0            | ALU1            | MUL             | MEM\n");
    printf("    ─────┼─────────────────┼─────────────────┼─────────────────┼─────────────────\n");

    for (int c = 0; c < max_cycle; c++) {
        printf("    %3d  |", c);
        for (int f = 0; f < WIDTH; f++) {
            int idx = g_bundles[c].slots[f];
            if (idx < 0) printf(" \033[90m%-15s\033[0m |", "·");
            else         printf(" \033[1;32m%-15.15s\033[0m |", p->insns[idx].text);
        }
        printf("\n");
    }
}

static void print_timeline(Program *p, int max_cycle) {
    printf("\n  \033[1;36m[流水线时序: I=发射 E=执行 W=写回]\033[0m\n");
    printf("     ");
    for (int c = 0; c < max_cycle + 1; c++)
        printf("%-2d", c % 10);
    printf("\n");

    for (int i = 0; i < p->n; i++) {
        Insn *ins = &p->insns[i];
        printf("  %2d ", i);
        for (int c = 0; c < max_cycle + 1; c++) {
            if (c == ins->issue_cycle)
                printf("\033[1;33mI \033[0m");
            else if (c > ins->issue_cycle && c < ins->done_cycle)
                printf("\033[90mE \033[0m");
            else if (c == ins->done_cycle)
                printf("\033[1;32mW \033[0m");
            else
                printf("· ");
        }
        printf("  \033[90m%s\033[0m\n", ins->text);
    }
}

/* ================================================================
 * 与串行对比
 * ================================================================ */
static int serial_cycles(Program *p) {
    int total = 0;
    for (int i = 0; i < p->n; i++)
        total += op_latency(p->insns[i].op);
    return total;
}

/* 单发射基准: 每周期最多 1 条 */
static int single_issue_cycles(Program *p) {
    Program tmp = *p;
    for (int i = 0; i < tmp.n; i++) {
        tmp.insns[i].done = false;
        tmp.insns[i].issue_cycle = -1;
        tmp.insns[i].done_cycle = -1;
    }

    int reg_ready[N_REGS] = {0};
    int n_done = 0;
    int cycle  = 0;

    while (n_done < tmp.n && cycle < MAX_CYCLES) {
        /* 只找一个 */
        int best = -1, best_pri = -1;
        for (int i = 0; i < tmp.n; i++) {
            Insn *ins = &tmp.insns[i];
            if (ins->done) continue;
            if (ins->dep1 >= 0 && !tmp.insns[ins->dep1].done) continue;
            if (ins->dep2 >= 0 && !tmp.insns[ins->dep2].done) continue;
            if (ins->src1 >= 0 && reg_ready[ins->src1] > cycle) continue;
            if (ins->src2 >= 0 && reg_ready[ins->src2] > cycle) continue;
            if (ins->priority > best_pri) {
                best_pri = ins->priority;
                best = i;
            }
        }
        if (best < 0) { cycle++; continue; }

        Insn *ins = &tmp.insns[best];
        ins->done = true;
        ins->done_cycle = cycle + op_latency(ins->op);
        if (ins->dst >= 0) reg_ready[ins->dst] = ins->done_cycle;
        n_done++;
        cycle++;
    }
    return cycle;
}

/* ================================================================
 * main
 * ================================================================ */
int main(void) {
    printf("\033[1;36m");
    printf("╔═══════════════════════════════════════════════════════════════╗\n");
    printf("║   VLIW 综合调度器                                              ║\n");
    printf("║   多发射 · 循环展开 · 软件流水 · 压力感知 · 真实流水线        ║\n");
    printf("╚═══════════════════════════════════════════════════════════════╝\n");
    printf("\033[0m\n");

    printf("机器模型:\n");
    printf("  发射宽度:       %d 条/周期\n", WIDTH);
    printf("  功能单元:       2×ALU, 1×MUL, 1×MEM\n");
    printf("  延迟:           ALU=1, MUL=3, LOAD=4, STORE=1\n");
    printf("  流水线:         发射 → 执行 → 写回\n");
    printf("  寄存器压力上限: %d 个活跃虚拟寄存器\n", PRESSURE_TH);

    printf("\n源循环:\n");
    printf("  for i in 0..N-1:\n");
    printf("      a[i] = b[i] + c[i] * d[i]\n");
    printf("\n循环展开 \033[1;33m%d\033[0m 次 —— 让调度器有更多独立指令可填\n", UNROLL);

    Program p;
    build_program(&p);
    build_deps(&p);
    compute_priority(&p);

    print_program(&p);

    int serial = serial_cycles(&p);
    int single = single_issue_cycles(&p);
    int vliw   = schedule(&p);

    print_bundles(&p, vliw);
    print_timeline(&p, vliw);

    /* ---- 统计每周期发射数 ---- */
    int histogram[5] = {0};
    for (int c = 0; c < vliw; c++) {
        int cnt = 0;
        for (int f = 0; f < WIDTH; f++)
            if (g_bundles[c].slots[f] >= 0) cnt++;
        if (cnt > 4) cnt = 4;
        histogram[cnt]++;
    }

    printf("\n  \033[1;36m[每周期发射指令数分布]\033[0m\n");
    for (int k = 0; k <= WIDTH; k++) {
        if (histogram[k] == 0) continue;
        printf("    %d 条/周期: %2d 个周期  ", k, histogram[k]);
        for (int i = 0; i < histogram[k]; i++) printf("\033[1;32m█\033[0m");
        printf("\n");
    }

    printf("\n\033[1;36m");
    printf("╔═══════════════════════════════════════════════════════════════╗\n");
    printf("║   三种执行方式对比                                            ║\n");
    printf("╠═══════════════════════════════════════════════════════════════╣\n");
    printf("║   完全串行 (无重叠):         %3d 周期                        ║\n", serial);
    printf("║   单发射 + 调度:             %3d 周期                        ║\n", single);
    printf("║   4 宽 VLIW + 压力感知:      %3d 周期                        ║\n", vliw);
    printf("║                                                               ║\n");
    printf("║   相比串行加速:              %.2fx                            ║\n",
           (double)serial / vliw);
    printf("║   相比单发射加速:            %.2fx                            ║\n",
           (double)single / vliw);
    printf("║                                                               ║\n");
    printf("║   各项技术贡献:                                               ║\n");
    printf("║     · 循环展开 —— 提供跨迭代的独立指令                        ║\n");
    printf("║     · 软件流水 —— 3 次迭代的 LOAD 重叠，隐藏内存延迟          ║\n");
    printf("║     · 多发射   —— 同周期并行发射最多 4 条                    ║\n");
    printf("║     · 压力感知 —— 防止调度过激导致寄存器溢出                  ║\n");
    printf("║     · VLIW 打包 —— 每周期的指令直接对应硬件槽位              ║\n");
    printf("║                                                               ║\n");
    printf("║   真实世界:                                                   ║\n");
    printf("║     Itanium (安腾) 靠编译器排好一切                           ║\n");
    printf("║     现代 x86/ARM 靠硬件乱序执行，编译器调度只是辅助           ║\n");
    printf("║     GPU / DSP 至今仍是 VLIW 风格 —— 编译器负全责             ║\n");
    printf("╚═══════════════════════════════════════════════════════════════╝\n");
    printf("\033[0m");

    return 0;
}