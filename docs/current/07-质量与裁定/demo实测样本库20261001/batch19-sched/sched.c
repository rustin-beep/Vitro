/* sched.c —— 指令调度：填充延迟槽
 *
 * 编译: gcc -Wall -O2 -std=c11 -o sched sched.c
 * 运行: ./sched
 *
 * 模型:
 *   单发射、流水线执行、结果有延迟
 *   ALU 延迟 1, MUL 延迟 3, LOAD 延迟 4, STORE 延迟 1
 *
 * 问题:
 *   未调度时, LOAD 的结果 4 个周期后才能用,
 *   后面的 ADD 只能干等 —— 出现"空泡"
 *
 * 解决:
 *   列表调度（list scheduling）: 把不相关的指令提到前面填坑
 *   优先级 = 从该指令到程序末尾的最长延迟路径
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

#define MAX_INSN 64
#define N_REGS   16

/* ================================================================
 * 指令
 * ================================================================ */
typedef enum {
    OP_NOP, OP_ADD, OP_SUB, OP_MUL, OP_LOAD, OP_STORE
} Op;

static const char *op_name(Op op) {
    switch (op) {
    case OP_NOP:   return "NOP";
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
    case OP_ADD:
    case OP_SUB:
    case OP_STORE:
    case OP_NOP:   return 1;
    case OP_MUL:   return 3;
    case OP_LOAD:  return 4;
    }
    return 1;
}

typedef struct {
    Op   op;
    int  dst, src1, src2;
    int  imm;
    char text[40];

    int  dep1, dep2;       /* 依赖的指令索引, -1 表示无 */
    int  priority;         /* 到末尾的最长路径 */
    int  issue_cycle;
    int  done_cycle;
} Insn;

typedef struct {
    Insn insns[MAX_INSN];
    int  n;
} Program;

static void emit(Program *p, Op op, int dst, int src1, int src2, int imm,
                 const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    Insn *ins = &p->insns[p->n++];
    ins->op   = op;
    ins->dst  = dst;
    ins->src1 = src1;
    ins->src2 = src2;
    ins->imm  = imm;
    ins->dep1 = ins->dep2 = -1;
    ins->priority = 0;
    ins->issue_cycle = ins->done_cycle = 0;
    vsnprintf(ins->text, sizeof(ins->text), fmt, ap);
    va_end(ap);
}

#include <stdarg.h>

/* ================================================================
 * 打印
 * ================================================================ */
static void print_program(Program *p, const char *title) {
    printf("\n  \033[1;36m%s\033[0m\n", title);
    for (int i = 0; i < p->n; i++) {
        Insn *ins = &p->insns[i];
        printf("    %2d  %-6s  %-24s  发射=%2d  完成=%2d\n",
               i, op_name(ins->op), ins->text,
               ins->issue_cycle, ins->done_cycle);
    }
}

/* ================================================================
 * 构建依赖图
 *
 *   对每条指令 i:
 *     dep1 = 最近一次写 src1 的指令（在 i 之前）
 *     dep2 = 最近一次写 src2 的指令
 * ================================================================ */
static void build_deps(Program *p) {
    int last_writer[N_REGS];
    for (int i = 0; i < N_REGS; i++) last_writer[i] = -1;

    for (int i = 0; i < p->n; i++) {
        Insn *ins = &p->insns[i];
        ins->dep1 = ins->dep2 = -1;

        if (ins->src1 >= 0 && ins->src1 < N_REGS)
            ins->dep1 = last_writer[ins->src1];
        if (ins->src2 >= 0 && ins->src2 < N_REGS)
            ins->dep2 = last_writer[ins->src2];

        if (ins->dst >= 0 && ins->dst < N_REGS)
            last_writer[ins->dst] = i;
    }
}

/* ================================================================
 * 关键路径优先级
 *
 *   priority[i] = max over all successors j of (latency[i] + priority[j])
 *   基例: 没有后继的指令 priority = latency
 *   逆序计算即可（依赖只从 i 指向 j>i）
 * ================================================================ */
static void compute_priority(Program *p) {
    for (int i = p->n - 1; i >= 0; i--) {
        Insn *ins = &p->insns[i];
        int pri = op_latency(ins->op);
        for (int j = i + 1; j < p->n; j++) {
            if (p->insns[j].dep1 == i || p->insns[j].dep2 == i) {
                int cand = op_latency(ins->op) + p->insns[j].priority;
                if (cand > pri) pri = cand;
            }
        }
        ins->priority = pri;
    }
}

/* ================================================================
 * 模拟执行：按当前指令顺序发射
 *
 *   每条指令的发射周期:
 *     issue = max(prev_issue + 1, src1_ready, src2_ready)
 *   src_ready 由"最近一次写它的指令"的完成周期决定
 * ================================================================ */
static int simulate(Program *p) {
    int reg_ready[N_REGS];
    for (int i = 0; i < N_REGS; i++) reg_ready[i] = 0;

    int cycle = 0;
    int last_done = 0;
    for (int i = 0; i < p->n; i++) {
        Insn *ins = &p->insns[i];
        int start = cycle;

        if (ins->src1 >= 0 && ins->src1 < N_REGS &&
            reg_ready[ins->src1] > start)
            start = reg_ready[ins->src1];
        if (ins->src2 >= 0 && ins->src2 < N_REGS &&
            reg_ready[ins->src2] > start)
            start = reg_ready[ins->src2];

        ins->issue_cycle = start;
        ins->done_cycle  = start + op_latency(ins->op);
        if (ins->done_cycle > last_done) last_done = ins->done_cycle;

        if (ins->dst >= 0 && ins->dst < N_REGS)
            reg_ready[ins->dst] = ins->done_cycle;

        cycle = start + 1;
    }
    return last_done;
}

/* ================================================================
 * 列表调度
 *
 *   每周期从"依赖已满足"的指令里挑优先级最高的一条
 *   挑不出来的话，cycle++ 空转（等价于硬件插入气泡）
 *   输出顺序就是新的指令顺序
 * ================================================================ */
static void list_schedule(Program *p) {
    int reg_ready[N_REGS];
    for (int i = 0; i < N_REGS; i++) reg_ready[i] = 0;

    bool done[MAX_INSN] = {false};
    Insn out[MAX_INSN];
    int  n_out = 0;
    int  n_done = 0;
    int  cycle  = 0;

    while (n_done < p->n) {
        int best = -1, best_pri = -1;

        for (int i = 0; i < p->n; i++) {
            if (done[i]) continue;
            Insn *ins = &p->insns[i];

            /* 依赖的指令是否都已调度 */
            if (ins->dep1 >= 0 && !done[ins->dep1]) continue;
            if (ins->dep2 >= 0 && !done[ins->dep2]) continue;

            /* 源操作数的就绪周期是否已到 */
            if (ins->src1 >= 0 && ins->src1 < N_REGS &&
                reg_ready[ins->src1] > cycle) continue;
            if (ins->src2 >= 0 && ins->src2 < N_REGS &&
                reg_ready[ins->src2] > cycle) continue;

            if (ins->priority > best_pri) {
                best_pri = ins->priority;
                best = i;
            }
        }

        if (best < 0) { cycle++; continue; }

        Insn *ins = &p->insns[best];
        ins->issue_cycle = cycle;
        ins->done_cycle  = cycle + op_latency(ins->op);
        if (ins->dst >= 0 && ins->dst < N_REGS)
            reg_ready[ins->dst] = ins->done_cycle;

        done[best] = true;
        n_done++;
        out[n_out++] = *ins;
        cycle++;
    }

    memcpy(p->insns, out, sizeof(Insn) * (size_t)n_out);
}

/* ================================================================
 * 时间轴可视化
 * ================================================================ */
static void timeline(Program *p, int total_cycles) {
    int min_c = 0, max_c = total_cycles + 1;

    /* 表头 */
    printf("         ");
    for (int c = min_c; c < max_c; c++) {
        if (c % 5 == 0) printf("\033[1;36m|%-4d\033[0m", c);
        else            printf("     ");
    }
    printf("\n");

    for (int i = 0; i < p->n; i++) {
        Insn *ins = &p->insns[i];
        printf("    %2d   ", i);

        for (int c = 0; c < total_cycles + 1; c++) {
            if (c == ins->issue_cycle) {
                if (ins->op == OP_LOAD)      printf("\033[1;35m[L  \033[0m");
                else if (ins->op == OP_MUL)  printf("\033[1;33m[M  \033[0m");
                else if (ins->op == OP_STORE)printf("\033[1;34m[S  \033[0m");
                else                          printf("\033[1;32m[A  \033[0m");
            } else if (c > ins->issue_cycle && c < ins->done_cycle) {
                printf("\033[90m... \033[0m");
            } else if (c == ins->done_cycle) {
                printf("\033[90m]   \033[0m");
            } else {
                printf("    ");
            }
        }
        printf("  %s\n", ins->text);
    }
    printf("         ");
    for (int c = min_c; c < max_c; c++) {
        if (c % 5 == 0) printf("\033[1;36m|%-4d\033[0m", c);
        else            printf("     ");
    }
    printf("\n");
}

/* ================================================================
 * 构建演示程序
 *
 * 计算:
 *   a = mem[0]
 *   b = mem[4]
 *   c = mem[8]
 *   d = a + b
 *   e = d * c
 *   mem[12] = e
 *
 * 变量分配:
 *   r0 = 基址(0)
 *   r1 = a, r2 = b, r3 = c, r4 = d, r5 = e
 * ================================================================ */
static void build_program(Program *p) {
    p->n = 0;
    emit(p, OP_LOAD, 1, 0, -1, 0,     "r1 = mem[r0+0]");
    emit(p, OP_LOAD, 2, 0, -1, 4,     "r2 = mem[r0+4]");
    emit(p, OP_LOAD, 3, 0, -1, 8,     "r3 = mem[r0+8]");
    emit(p, OP_ADD,  4, 1, 2, 0,      "r4 = r1 + r2");
    emit(p, OP_MUL,  5, 4, 3, 0,      "r5 = r4 * r3");
    emit(p, OP_STORE,-1, 5, 0, 12,    "mem[r0+12] = r5");
}

/* ================================================================
 * main
 * ================================================================ */
int main(void) {
    printf("\033[1;36m");
    printf("╔══════════════════════════════════════════════════════╗\n");
    printf("║   指令调度：填充延迟槽                               ║\n");
    printf("╚══════════════════════════════════════════════════════╝\n");
    printf("\033[0m\n");
    printf("延迟: ALU=1  MUL=3  LOAD=4  STORE=1\n");
    printf("模型: 单发射，源操作数就绪后才能发射下一条\n");

    /* ---------------- 未调度 ---------------- */
    Program p1;
    build_program(&p1);

    printf("\n\033[1;35m━━━ 未调度：按程序原始顺序发射 ━━━\033[0m\n");
    int cycles1 = simulate(&p1);
    print_program(&p1, "指令序列:");
    printf("\n    总周期数: \033[1;31m%d\033[0m\n", cycles1);

    printf("\n    \033[1;36m时间轴（每个 ... 表示正在等结果）:\033[0m\n");
    timeline(&p1, cycles1);

    /* ---------------- 已调度 ---------------- */
    Program p2;
    build_program(&p2);

    build_deps(&p2);
    compute_priority(&p2);

    printf("\n\033[1;35m━━━ 依赖图与优先级 ━━━\033[0m\n");
    for (int i = 0; i < p2.n; i++) {
        Insn *ins = &p2.insns[i];
        printf("    %2d  %-6s %-24s pri=%-2d  依赖:",
               i, op_name(ins->op), ins->text, ins->priority);
        if (ins->dep1 < 0 && ins->dep2 < 0) printf(" 无");
        else {
            if (ins->dep1 >= 0) printf(" #%d", ins->dep1);
            if (ins->dep2 >= 0) printf(" #%d", ins->dep2);
        }
        printf("\n");
    }

    list_schedule(&p2);

    printf("\n\033[1;35m━━━ 已调度：列表调度重排后 ━━━\033[0m\n");
    int cycles2 = simulate(&p2);
    print_program(&p2, "新指令序列:");
    printf("\n    总周期数: \033[1;32m%d\033[0m\n", cycles2);

    printf("\n    \033[1;36m时间轴:\033[0m\n");
    timeline(&p2, cycles2);

    /* ---------------- 对比 ---------------- */
    printf("\n\033[1;36m");
    printf("╔══════════════════════════════════════════════════════╗\n");
    printf("║   对比                                               ║\n");
    printf("╠══════════════════════════════════════════════════════╣\n");
    printf("║   未调度:  %2d 周期                                  ║\n", cycles1);
    printf("║   已调度:  %2d 周期                                  ║\n", cycles2);
    printf("║   加速比:  %.2fx                                     ║\n",
           (double)cycles1 / cycles2);
    printf("║   减少:    %d 个周期                                 ║\n",
           cycles1 - cycles2);
    printf("║                                                      ║\n");
    printf("║ 调度做了什么:                                        ║\n");
    printf("║   1. 三条 LOAD 都是独立访存, 并行发射                ║\n");
    printf("║   2. 后两条 LOAD 填了第一条 LOAD 的延迟槽            ║\n");
    printf("║   3. ADD 就绪后立即发射, MUL 就绪后立即发射          ║\n");
    printf("║   4. 指令语义完全不变 —— 只是发射顺序变了            ║\n");
    printf("╚══════════════════════════════════════════════════════╝\n");
    printf("\033[0m");

    return 0;
}
