/* tomasulo.c —— Tomasulo 乱序执行算法
 *
 * 编译: gcc -Wall -O2 -std=c11 -o tomasulo tomasulo.c
 * 运行: ./tomasulo
 *
 * 核心思想:
 *   1. 寄存器重命名 —— 用保留站编号代替寄存器号, 消除假依赖
 *   2. 保留站 —— 缓存操作数和生产者标签, 等数据就绪
 *   3. CDB(公共数据总线) —— 结果广播到所有等待者
 *   4. 乱序执行 —— 操作数就绪就能开始, 不必等前面的指令
 *
 * 三张表:
 *   保留站表        —— 每条已发射指令的状态
 *   寄存器状态表    —— 每个寄存器的最新值由哪个保留站产生
 *   指令队列        —— 按顺序发射
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdarg.h>

/* ================================================================
 * 常量
 * ================================================================ */
#define MAX_INSNS  32
#define N_REGS     8
#define N_MEM      16
#define MAX_CYCLES 80
#define RS_MAX     4

/* ================================================================
 * 指令与功能单元
 * ================================================================ */
typedef enum { OP_ADD, OP_SUB, OP_MUL, OP_LOAD, OP_STORE } Op;
typedef enum { FU_ADD, FU_MUL, FU_MEM, FU_COUNT } FUType;

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
    case OP_ADD:   return 2;
    case OP_SUB:   return 2;
    case OP_MUL:   return 5;
    case OP_LOAD:  return 3;
    case OP_STORE: return 3;
    }
    return 1;
}

static FUType op_fu(Op op) {
    switch (op) {
    case OP_ADD:
    case OP_SUB:   return FU_ADD;
    case OP_MUL:   return FU_MUL;
    case OP_LOAD:
    case OP_STORE: return FU_MEM;
    }
    return FU_ADD;
}

/* ================================================================
 * 指令
 * ================================================================ */
typedef struct {
    Op   op;
    int  dst;
    int  src1, src2;
    int  imm;
    char text[48];
    bool issued;
} Insn;

/* ================================================================
 * 保留站
 *
 *   Qj, Qk = -1 表示操作数已就绪 (放在 Vj/Vk)
 *   Qj, Qk != -1 表示正在等 tag 对应的指令写结果
 * ================================================================ */
typedef struct {
    int  tag;
    bool busy;
    Op   op;
    int  Qj, Qk;
    int  Vj, Vk;
    int  imm;
    int  dst;
    int  inst_id;
    int  cycles_left;     /* -1 = 未开始，0 = 待广播，>0 = 执行中 */
    bool started;
} RS;

typedef struct {
    const char *name;
    int         n_slots;
    RS          slots[RS_MAX];
} FU;

/* ================================================================
 * 寄存器状态表
 * ================================================================ */
typedef struct {
    int producer;         /* 哪个 tag 会写这个寄存器，-1 = 无 */
    int value;
} RegStatus;

/* ================================================================
 * 全局
 * ================================================================ */
static Insn      g_prog[MAX_INSNS];
static int       g_nprog = 0;
static int       g_next_issue = 0;
static int       g_cycle = 0;

static FU        g_fus[FU_COUNT];
static RegStatus g_regs[N_REGS];
static int       g_mem[N_MEM];

/* ================================================================
 * 工具
 * ================================================================ */
static int tag_fu(int tag)  { return (tag - 1) / RS_MAX; }
static int tag_idx(int tag) { return (tag - 1) % RS_MAX; }

/* ================================================================
 * 初始化
 * ================================================================ */
static void add_insn(Op op, int dst, int s1, int s2, int imm,
                     const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    Insn *ins = &g_prog[g_nprog++];
    ins->op = op;
    ins->dst = dst;
    ins->src1 = s1;
    ins->src2 = s2;
    ins->imm = imm;
    ins->issued = false;
    vsnprintf(ins->text, sizeof(ins->text), fmt, ap);
    va_end(ap);
}

static void init_machine(void) {
    memset(g_fus, 0, sizeof(g_fus));

    g_fus[FU_ADD].name = "ADD"; g_fus[FU_ADD].n_slots = 3;
    g_fus[FU_MUL].name = "MUL"; g_fus[FU_MUL].n_slots = 2;
    g_fus[FU_MEM].name = "MEM"; g_fus[FU_MEM].n_slots = 2;

    int tag = 1;
    for (int f = 0; f < FU_COUNT; f++) {
        for (int i = 0; i < g_fus[f].n_slots; i++) {
            RS *rs = &g_fus[f].slots[i];
            rs->tag = tag++;
            rs->busy = false;
            rs->Qj = rs->Qk = -1;
            rs->Vj = rs->Vk = 0;
            rs->dst = -1;
            rs->cycles_left = -1;
            rs->started = false;
        }
    }

    for (int i = 0; i < N_REGS; i++) {
        g_regs[i].producer = -1;
        g_regs[i].value = i;   /* R0..R7 初始值 = 下标 */
    }

    for (int i = 0; i < N_MEM; i++) g_mem[i] = 100 + i;
}

/* ================================================================
 * 发射
 * ================================================================ */
static RS *find_free_rs(FUType ft) {
    for (int i = 0; i < g_fus[ft].n_slots; i++)
        if (!g_fus[ft].slots[i].busy) return &g_fus[ft].slots[i];
    return NULL;
}

static bool issue_next(void) {
    if (g_next_issue >= g_nprog) return false;

    Insn *ins = &g_prog[g_next_issue];
    FUType ft = op_fu(ins->op);
    RS *rs = find_free_rs(ft);
    if (!rs) return false;    /* 结构冒险: 没有空保留站 */

    rs->busy = true;
    rs->op = ins->op;
    rs->dst = ins->dst;
    rs->imm = ins->imm;
    rs->inst_id = g_next_issue;
    rs->cycles_left = -1;
    rs->started = false;

    /* --- 读操作数 ---
     * 若寄存器状态表里没有生产者, 说明值已就绪
     * 否则记下 tag, 等 CDB 广播时再填 Vj/Vk
     */
    if (ins->src1 >= 0) {
        if (g_regs[ins->src1].producer == -1) {
            rs->Vj = g_regs[ins->src1].value;
            rs->Qj = -1;
        } else {
            rs->Qj = g_regs[ins->src1].producer;
            rs->Vj = 0;
        }
    } else {
        rs->Qj = -1; rs->Vj = 0;
    }

    if (ins->src2 >= 0) {
        if (g_regs[ins->src2].producer == -1) {
            rs->Vk = g_regs[ins->src2].value;
            rs->Qk = -1;
        } else {
            rs->Qk = g_regs[ins->src2].producer;
            rs->Vk = 0;
        }
    } else {
        rs->Qk = -1; rs->Vk = 0;
    }

    /* 重命名: 这个寄存器现在由我负责 */
    if (ins->dst >= 0)
        g_regs[ins->dst].producer = rs->tag;

    ins->issued = true;
    g_next_issue++;
    return true;
}

/* ================================================================
 * 执行
 * ================================================================ */
static void start_execution(void) {
    for (int f = 0; f < FU_COUNT; f++)
        for (int i = 0; i < g_fus[f].n_slots; i++) {
            RS *rs = &g_fus[f].slots[i];
            if (!rs->busy || rs->started) continue;
            if (rs->Qj != -1 || rs->Qk != -1) continue;
            rs->started = true;
            rs->cycles_left = op_latency(rs->op);
        }
}

static void advance_execution(void) {
    for (int f = 0; f < FU_COUNT; f++)
        for (int i = 0; i < g_fus[f].n_slots; i++) {
            RS *rs = &g_fus[f].slots[i];
            if (!rs->busy || !rs->started) continue;
            if (rs->cycles_left > 0) rs->cycles_left--;
        }
}

/* ================================================================
 * CDB 写结果
 *
 *   单 CDB 模型: 每周期最多广播一个结果
 *   多个 RS 同周期完成时, 选最早发射的那条
 * ================================================================ */
static int write_result(void) {
    int best_f = -1, best_i = -1, best_id = 99999;

    for (int f = 0; f < FU_COUNT; f++)
        for (int i = 0; i < g_fus[f].n_slots; i++) {
            RS *rs = &g_fus[f].slots[i];
            if (!rs->busy || !rs->started) continue;
            if (rs->cycles_left != 0) continue;
            if (rs->inst_id < best_id) {
                best_id = rs->inst_id;
                best_f = f;
                best_i = i;
            }
        }

    if (best_f < 0) return -1;

    RS *rs = &g_fus[best_f].slots[best_i];
    int tag = rs->tag;
    int value = 0;

    switch (rs->op) {
    case OP_ADD:   value = rs->Vj + rs->Vk; break;
    case OP_SUB:   value = rs->Vj - rs->Vk; break;
    case OP_MUL:   value = rs->Vj * rs->Vk; break;
    case OP_LOAD:
        value = g_mem[rs->imm % N_MEM];
        break;
    case OP_STORE:
        value = rs->Vj;
        g_mem[rs->imm % N_MEM] = value;
        break;
    }

    /* --- 广播: 所有 Qj/Qk == tag 的 RS 都填上值 --- */
    for (int f = 0; f < FU_COUNT; f++)
        for (int i = 0; i < g_fus[f].n_slots; i++) {
            RS *r = &g_fus[f].slots[i];
            if (!r->busy) continue;
            if (r->Qj == tag) { r->Vj = value; r->Qj = -1; }
            if (r->Qk == tag) { r->Vk = value; r->Qk = -1; }
        }

    /* --- 写寄存器 --- */
    if (rs->dst >= 0) {
        g_regs[rs->dst].value = value;
        if (g_regs[rs->dst].producer == tag)
            g_regs[rs->dst].producer = -1;
    }

    /* --- 释放保留站 --- */
    rs->busy = false;
    rs->started = false;
    rs->cycles_left = -1;

    return tag;
}

/* ================================================================
 * 打印
 * ================================================================ */
static void print_program(void) {
    printf("\n\033[1;36m[程序]\033[0m\n");
    for (int i = 0; i < g_nprog; i++) {
        const char *mark = g_prog[i].issued
            ? "\033[90m✓\033[0m" : " ";
        printf("    %s %2d  %-6s  %s\n",
               mark, i, op_name(g_prog[i].op), g_prog[i].text);
    }
}

static void print_state(void) {
    /* 寄存器状态 */
    printf("  \033[1;36m寄存器:\033[0m ");
    for (int i = 0; i < N_REGS; i++) {
        if (g_regs[i].producer == -1)
            printf("\033[1;32mR%d=%-3d\033[0m ", i, g_regs[i].value);
        else
            printf("\033[1;31mR%d←T%d\033[0m ", i, g_regs[i].producer);
    }
    printf("\n");

    /* 保留站 */
    printf("  \033[1;36m保留站:\033[0m\n");
    bool any = false;
    for (int f = 0; f < FU_COUNT; f++)
        for (int i = 0; i < g_fus[f].n_slots; i++) {
            RS *rs = &g_fus[f].slots[i];
            if (!rs->busy) continue;
            any = true;

            printf("    \033[1;33mT%-2d\033[0m %-3s  %-5s  ",
                   rs->tag, g_fus[f].name, op_name(rs->op));

            printf("Qj=");
            if (rs->Qj == -1) printf("\033[1;32m──\033[0m");
            else              printf("\033[1;31mT%d\033[0m", rs->Qj);
            printf(" Vj=%-4d  ", rs->Vj);

            printf("Qk=");
            if (rs->Qk == -1) printf("\033[1;32m──\033[0m");
            else              printf("\033[1;31mT%d\033[0m", rs->Qk);
            printf(" Vk=%-4d  ", rs->Vk);

            if (rs->cycles_left < 0)
                printf("\033[90m(等操作数)\033[0m");
            else if (rs->cycles_left == 0)
                printf("\033[1;35m(待广播)\033[0m");
            else
                printf("\033[1;36m(剩 %d 周期)\033[0m", rs->cycles_left);

            if (rs->dst >= 0)
                printf("  → R%d", rs->dst);
            printf("\n");
        }
    if (!any) printf("    \033[90m(空)\033[0m\n");
}

static bool all_done(void) {
    if (g_next_issue < g_nprog) return false;
    for (int f = 0; f < FU_COUNT; f++)
        for (int i = 0; i < g_fus[f].n_slots; i++)
            if (g_fus[f].slots[i].busy) return false;
    return true;
}

/* ================================================================
 * 一个周期
 * ================================================================ */
static void tick(void) {
    printf("\n\033[1;33m═══════ 周期 %d ═══════\033[0m\n", g_cycle);

    /* 1. 写结果 (CDB 广播) */
    int tag = write_result();
    if (tag >= 0) {
        int fu = tag_fu(tag);
        printf("  \033[1;35m[CDB]\033[0m T%d (%s) 广播结果\n",
               tag, g_fus[fu].name);
    }

    /* 2. 发射下一条指令 */
    if (issue_next()) {
        printf("  \033[1;32m[发射]\033[0m #%d  %s\n",
               g_next_issue - 1, g_prog[g_next_issue - 1].text);
    } else if (g_next_issue < g_nprog) {
        printf("  \033[1;31m[阻塞]\033[0m 保留站满, 无法发射 #%d\n",
               g_next_issue);
    }

    /* 3. 启动新执行 (操作数就绪的) */
    for (int f = 0; f < FU_COUNT; f++)
        for (int i = 0; i < g_fus[f].n_slots; i++) {
            RS *rs = &g_fus[f].slots[i];
            if (rs->busy && !rs->started &&
                rs->Qj == -1 && rs->Qk == -1) {
                printf("  \033[1;36m[执行]\033[0m T%d 开始执行\n", rs->tag);
            }
        }
    start_execution();

    /* 4. 推进 */
    advance_execution();

    /* 5. 打印状态 */
    print_state();

    g_cycle++;
}

/* ================================================================
 * main
 * ================================================================ */
int main(void) {
    printf("\033[1;36m");
    printf("╔══════════════════════════════════════════════════════╗\n");
    printf("║   Tomasulo 乱序执行算法                              ║\n");
    printf("╚══════════════════════════════════════════════════════╝\n");
    printf("\033[0m");

    printf("\n机器模型:\n");
    printf("  功能单元:  3×ADD(延迟2)  2×MUL(延迟5)  2×MEM(延迟3)\n");
    printf("  CDB:       1 条 (每周期最多广播 1 个结果)\n");
    printf("  寄存器:    R0..R7 初始值 = 下标\n");
    printf("  内存:      mem[0..15] 初始值 = 100 + 下标\n");

    /* ---- 程序 ---- */
    add_insn(OP_LOAD,  1, -1, -1, 0, "LOAD  R1, mem[0]");
    add_insn(OP_LOAD,  2, -1, -1, 1, "LOAD  R2, mem[1]");
    add_insn(OP_MUL,   3,  1,  2, 0, "MUL   R3, R1, R2");
    add_insn(OP_ADD,   4,  3,  1, 0, "ADD   R4, R3, R1");
    add_insn(OP_LOAD,  5, -1, -1, 2, "LOAD  R5, mem[2]");
    add_insn(OP_SUB,   6,  5,  4, 0, "SUB   R6, R5, R4");
    add_insn(OP_ADD,   7,  6,  3, 0, "ADD   R7, R6, R3");
    add_insn(OP_STORE,-1,  7, -1, 3, "STORE R7, mem[3]");

    init_machine();
    print_program();

    printf("\n\033[1;36m[依赖分析]\033[0m\n");
    printf("  #2 MUL  需要 R1(#0), R2(#1)   —— 真依赖\n");
    printf("  #3 ADD  需要 R3(#2), R1(#0)   —— 真依赖, 且复用 R1\n");
    printf("  #5 SUB  需要 R5(#4), R4(#3)   —— 真依赖\n");
    printf("  #6 ADD  需要 R6(#5), R3(#2)   —— 真依赖\n");
    printf("  #7 STORE 需要 R7(#6)          —— 真依赖\n");
    printf("\n  R1 被 #0 写、#2 和 #3 读 —— 但 Tomasulo 用 tag 重命名,\n");
    printf("  不存在写后读或写后写的假依赖。\n");

    /* ---- 主循环 ---- */
    while (!all_done() && g_cycle < MAX_CYCLES)
        tick();

    /* ---- 最终结果 ---- */
    printf("\n\033[1;36m");
    printf("╔══════════════════════════════════════════════════════╗\n");
    printf("║   最终结果                                           ║\n");
    printf("╠══════════════════════════════════════════════════════╣\n");
    printf("║   总周期数:  %2d                                       ║\n", g_cycle);

    printf("║   寄存器终值:                                        ║\n");
    for (int i = 0; i < N_REGS; i++)
        printf("║     R%d = %-4d                                       ║\n",
               i, g_regs[i].value);

    printf("║   内存 mem[0..7]:                                    ║\n");
    printf("║     ");
    for (int i = 0; i < 8; i++)
        printf("%4d ", g_mem[i]);
    printf("       ║\n");

    printf("║                                                      ║\n");
    printf("║   说明:                                              ║\n");
    printf("║     LOAD mem[0]=100, mem[1]=101 → R1=100, R2=101    ║\n");
    printf("║     R3 = R1*R2 = 10100                              ║\n");
    printf("║     R4 = R3+R1 = 10200                              ║\n");
    printf("║     R5 = mem[2] = 102                               ║\n");
    printf("║     R6 = R5-R4 = -10098                             ║\n");
    printf("║     R7 = R6+R3 = 2                                  ║\n");
    printf("║     mem[3] = R7 = 2                                 ║\n");
    printf("╚══════════════════════════════════════════════════════╝\n");
    printf("\033[0m");

    return 0;
}