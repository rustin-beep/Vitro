/* spill2.c —— 寄存器分配的第二轮：溢出代码生成
 *
 * 编译: gcc -Wall -O2 -std=c11 -o spill2 spill2.c
 * 运行: ./spill2
 *
 * 流程:
 *   1. 三地址码 IR
 *   2. 活跃分析
 *   3. 线性扫描分配
 *   4. 找出溢出变量 → 生成 LOAD/STORE 展开代码
 *   5. 对展开后的代码再跑一遍活跃分析 + 线性扫描
 *   6. 第二轮几乎总能全部装下
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

#define MAX_VREGS   64
#define MAX_INSTRS  256
#define N_REGS      3
#define SPILL_BASE  1000

/* ================================================================
 * 指令
 *
 *   dst、s1、s2 是操作数编号：
 *     0 .. SPILL_BASE-1   普通虚拟寄存器
 *     SPILL_BASE ..       栈槽编号
 *   -1 表示"无此操作数"
 * ================================================================ */
enum {
    OP_ADD, OP_SUB, OP_MUL, OP_MOV,
    OP_PRINT,
    OP_LOAD,    /* dst = mem[s1]  */
    OP_STORE,   /* mem[dst] = s1  */
    OP_HALT
};

typedef struct {
    int op;
    int dst;
    int s1, s2;
    int imm;
} Instr;

static Instr code[MAX_INSTRS];
static int   ncode = 0;

static int emit(int op, int dst, int s1, int s2, int imm) {
    code[ncode].op  = op;
    code[ncode].dst = dst;
    code[ncode].s1  = s1;
    code[ncode].s2  = s2;
    code[ncode].imm = imm;
    return ncode++;
}

/* ================================================================
 * 第一轮 IR
 *
 *   a = 1; b = 2; t1 = a + b
 *   c = 3; d = 4; t2 = c + d
 *   t3 = t1 + t2
 *   e = 5; t4 = t3 + e
 *   t5 = t4 + t1
 *   print t5
 *
 * 变量编号:
 *   a=0 b=1 c=2 d=3 e=4 t1=5 t2=6 t3=7 t4=8 t5=9
 * ================================================================ */
static void build_program(void) {
    ncode = 0;
    emit(OP_MOV,   0, -1, -1, 1);
    emit(OP_MOV,   1, -1, -1, 2);
    emit(OP_ADD,   5, 0, 1, 0);
    emit(OP_MOV,   2, -1, -1, 3);
    emit(OP_MOV,   3, -1, -1, 4);
    emit(OP_ADD,   6, 2, 3, 0);
    emit(OP_ADD,   7, 5, 6, 0);
    emit(OP_MOV,   4, -1, -1, 5);
    emit(OP_ADD,   8, 7, 4, 0);
    emit(OP_ADD,   9, 8, 5, 0);
    emit(OP_PRINT, -1, 9, -1, 0);
    emit(OP_HALT,  -1, -1, -1, 0);
}

/* ================================================================
 * 打印
 * ================================================================ */
static const char *vreg_names[MAX_VREGS] = {
    "a", "b", "c", "d", "e",
    "t1", "t2", "t3", "t4", "t5",
    /* 其余默认 NULL */
};

static void print_operand(int v) {
    if (v < 0) { printf("_"); return; }
    if (v >= SPILL_BASE) {
        printf("slot%d", v - SPILL_BASE);
        return;
    }
    if (v < MAX_VREGS && vreg_names[v])
        printf("%s", vreg_names[v]);
    else
        printf("v%d", v);
}

static void print_program(const char *title) {
    printf("\n  \033[1;36m%s\033[0m\n", title);
    for (int i = 0; i < ncode; i++) {
        Instr *ins = &code[i];
        printf("    %2d: ", i);
        switch (ins->op) {
        case OP_ADD:
            print_operand(ins->dst); printf(" = ");
            print_operand(ins->s1);  printf(" + ");
            print_operand(ins->s2);  break;
        case OP_SUB:
            print_operand(ins->dst); printf(" = ");
            print_operand(ins->s1);  printf(" - ");
            print_operand(ins->s2);  break;
        case OP_MUL:
            print_operand(ins->dst); printf(" = ");
            print_operand(ins->s1);  printf(" * ");
            print_operand(ins->s2);  break;
        case OP_MOV:
            print_operand(ins->dst);
            printf(" = %d", ins->imm); break;
        case OP_PRINT:
            printf("print "); print_operand(ins->s1); break;
        case OP_LOAD:
            print_operand(ins->dst);
            printf(" = load ");
            print_operand(ins->s1);  break;
        case OP_STORE:
            printf("store ");
            print_operand(ins->dst);
            printf(" ← ");
            print_operand(ins->s1);  break;
        case OP_HALT:
            printf("halt"); break;
        }
        printf("\n");
    }
}

/* ================================================================
 * 活跃分析
 * ================================================================ */
static int g_first_def[MAX_VREGS];
static int g_last_use[MAX_VREGS];
static int g_nvregs = 0;

static void liveness(void) {
    memset(g_first_def, -1, sizeof(g_first_def));
    memset(g_last_use,  -1, sizeof(g_last_use));

    for (int i = 0; i < ncode; i++) {
        Instr *ins = &code[i];
        if (ins->dst >= 0 && ins->dst < SPILL_BASE) {
            if (g_first_def[ins->dst] < 0) g_first_def[ins->dst] = i;
        }
        if (ins->s1 >= 0 && ins->s1 < SPILL_BASE)
            g_last_use[ins->s1] = i;
        if (ins->s2 >= 0 && ins->s2 < SPILL_BASE)
            g_last_use[ins->s2] = i;
    }

    g_nvregs = 0;
    for (int v = 0; v < MAX_VREGS; v++) {
        if (g_first_def[v] < 0 && g_last_use[v] < 0) continue;
        if (g_first_def[v] < 0) g_first_def[v] = 0;
        if (g_last_use[v]  < 0) g_last_use[v]  = g_first_def[v];
        if (v >= g_nvregs) g_nvregs = v + 1;
    }
}

/* ================================================================
 * 线性扫描分配
 * ================================================================ */
typedef struct {
    int vreg;
    int start, end;
    int reg;
    int spilled;
} Interval;

static int cmp_iv(const void *a, const void *b) {
    const Interval *ia = (const Interval *)a;
    const Interval *ib = (const Interval *)b;
    if (ia->start != ib->start) return ia->start - ib->start;
    return ia->end - ib->end;
}

static void linear_scan(Interval *ivs, int nivs, int nregs,
                        int *reg_of, int *spilled_of) {
    for (int v = 0; v < MAX_VREGS; v++) {
        reg_of[v] = -1;
        spilled_of[v] = 0;
    }

    qsort(ivs, nivs, sizeof(Interval), cmp_iv);

    int  active[MAX_VREGS];
    int  nactive = 0;
    bool used[MAX_VREGS] = {false};

    for (int i = 0; i < nivs; i++) {
        Interval *cur = &ivs[i];

        /* 1. 回收已经过期的区间 */
        for (int j = 0; j < nactive; ) {
            Interval *act = &ivs[active[j]];
            if (act->end < cur->start) {
                if (act->reg >= 0) used[act->reg] = false;
                for (int k = j; k < nactive - 1; k++)
                    active[k] = active[k + 1];
                nactive--;
            } else {
                j++;
            }
        }

        /* 2. 找一个空闲寄存器 */
        int r = -1;
        for (int k = 0; k < nregs; k++) {
            if (!used[k]) { r = k; break; }
        }

        if (r >= 0) {
            cur->reg = r;
            used[r]  = true;
            active[nactive++] = i;
        } else {
            /* 3. 没空闲寄存器，挑一个牺牲品 */
            int max_end = -1, max_j = -1;
            for (int j = 0; j < nactive; j++) {
                if (ivs[active[j]].end > max_end) {
                    max_end = ivs[active[j]].end;
                    max_j   = j;
                }
            }
            if (max_end > cur->end) {
                /* 牺牲 active 里结束更晚的，把寄存器让给当前 */
                Interval *victim = &ivs[active[max_j]];
                int vr = victim->reg;
                victim->reg = -1;
                victim->spilled = 1;
                used[vr] = false;

                for (int k = max_j; k < nactive - 1; k++)
                    active[k] = active[k + 1];
                nactive--;

                cur->reg = vr;
                used[vr] = true;
                active[nactive++] = i;
            } else {
                /* 当前区间就是牺牲品 */
                cur->spilled = 1;
            }
        }
    }

    for (int i = 0; i < nivs; i++) {
        reg_of[ivs[i].vreg]     = ivs[i].reg;
        spilled_of[ivs[i].vreg] = ivs[i].spilled;
    }
}

static const char *vname(int v) {
    if (v < MAX_VREGS && vreg_names[v]) return vreg_names[v];
    static char buf[16];
    snprintf(buf, sizeof(buf), "v%d", v);
    return buf;
}

static void print_intervals(Interval *ivs, int nivs) {
    printf("    %-6s %-14s %s\n", "变量", "区间", "状态");
    for (int i = 0; i < nivs; i++) {
        printf("    %-6s [%2d, %2d]      ",
               vname(ivs[i].vreg), ivs[i].start, ivs[i].end);
        if (ivs[i].reg >= 0)
            printf("r%d\n", ivs[i].reg);
        else if (ivs[i].spilled)
            printf("\033[1;31m溢出\033[0m\n");
        else
            printf("—\n");
    }
}

/* ================================================================
 * main
 * ================================================================ */
int main(void) {
    printf("\033[1;36m");
    printf("╔══════════════════════════════════════════════════════╗\n");
    printf("║   寄存器分配第二轮：溢出代码生成                     ║\n");
    printf("╚══════════════════════════════════════════════════════╝\n");
    printf("\033[0m");
    printf("物理寄存器数: %d\n", N_REGS);

    /* ============================================================
     * 第一轮
     * ============================================================ */
    build_program();
    print_program("【第一轮 IR】");

    liveness();

    Interval ivs[MAX_VREGS];
    int nivs = 0;
    for (int v = 0; v < g_nvregs; v++) {
        ivs[nivs].vreg    = v;
        ivs[nivs].start   = g_first_def[v];
        ivs[nivs].end     = g_last_use[v];
        ivs[nivs].reg     = -1;
        ivs[nivs].spilled = 0;
        nivs++;
    }

    printf("\n  \033[1;36m【第一轮活跃区间】\033[0m\n");
    print_intervals(ivs, nivs);

    int reg_of[MAX_VREGS];
    int spilled_of[MAX_VREGS];
    linear_scan(ivs, nivs, N_REGS, reg_of, spilled_of);

    printf("\n  \033[1;36m【第一轮分配结果】\033[0m\n");
    int nspilled = 0;
    for (int i = 0; i < nivs; i++) {
        int v = ivs[i].vreg;
        printf("    %-6s → ", vname(v));
        if (reg_of[v] >= 0)
            printf("\033[1;32mr%d\033[0m\n", reg_of[v]);
        else if (spilled_of[v]) {
            printf("\033[1;31m溢出\033[0m\n");
            nspilled++;
        } else {
            printf("—\n");
        }
    }
    printf("    溢出变量数: \033[1;33m%d\033[0m\n", nspilled);

    if (nspilled == 0) {
        printf("\n  \033[1;32m没有溢出，无需第二轮\033[0m\n");
        return 0;
    }

    /* ============================================================
     * 溢出代码生成
     * ============================================================ */
    printf("\n  \033[1;36m【溢出代码生成】\033[0m\n");

    /* 栈槽分配 */
    int slot_of[MAX_VREGS];
    for (int v = 0; v < MAX_VREGS; v++) slot_of[v] = -1;
    int next_slot = 0;
    for (int v = 0; v < g_nvregs; v++) {
        if (spilled_of[v]) {
            slot_of[v] = next_slot++;
            printf("    %-6s → 栈槽 slot%d\n", vname(v), slot_of[v]);
        }
    }

    /* 重写代码 */
    Instr new_code[MAX_INSTRS];
    int nnew = 0;
    int next_new_vreg = 100;   /* 新生成的临时量从 100 起，避免和原变量冲突 */

    for (int i = 0; i < ncode; i++) {
        Instr ins = code[i];

        /* s1 是溢出变量 → 先 LOAD */
        if (ins.s1 >= 0 && ins.s1 < SPILL_BASE && spilled_of[ins.s1]) {
            int nv = next_new_vreg++;
            new_code[nnew++] = (Instr){ OP_LOAD, nv,
                                        SPILL_BASE + slot_of[ins.s1],
                                        -1, 0 };
            ins.s1 = nv;
        }
        /* s2 是溢出变量 → 先 LOAD */
        if (ins.s2 >= 0 && ins.s2 < SPILL_BASE && spilled_of[ins.s2]) {
            int nv = next_new_vreg++;
            new_code[nnew++] = (Instr){ OP_LOAD, nv,
                                        SPILL_BASE + slot_of[ins.s2],
                                        -1, 0 };
            ins.s2 = nv;
        }

        /* dst 是溢出变量 → 换一个新临时量，指令后插 STORE */
        int orig_dst = ins.dst;
        int dst_is_spill = (orig_dst >= 0 && orig_dst < SPILL_BASE
                            && spilled_of[orig_dst]);
        int new_dst_vreg = -1;
        if (dst_is_spill) {
            new_dst_vreg = next_new_vreg++;
            ins.dst = new_dst_vreg;
        }

        /* 发射当前指令 */
        new_code[nnew++] = ins;

        /* 若 dst 是溢出变量，后面跟一条 STORE */
        if (dst_is_spill) {
            new_code[nnew++] = (Instr){ OP_STORE,
                                        SPILL_BASE + slot_of[orig_dst],
                                        new_dst_vreg,
                                        -1, 0 };
        }
    }

    memcpy(code, new_code, sizeof(Instr) * (size_t)nnew);
    ncode = nnew;

    print_program("【第二轮 IR（溢出已展开）】");

    /* ============================================================
     * 第二轮
     * ============================================================ */
    liveness();

    nivs = 0;
    for (int v = 0; v < MAX_VREGS; v++) {
        if (g_first_def[v] < 0 && g_last_use[v] < 0) continue;
        ivs[nivs].vreg    = v;
        ivs[nivs].start   = g_first_def[v];
        ivs[nivs].end     = g_last_use[v];
        ivs[nivs].reg     = -1;
        ivs[nivs].spilled = 0;
        nivs++;
    }

    printf("\n  \033[1;36m【第二轮活跃区间】\033[0m\n");
    print_intervals(ivs, nivs);

    linear_scan(ivs, nivs, N_REGS, reg_of, spilled_of);

    printf("\n  \033[1;36m【第二轮分配结果】\033[0m\n");
    int nspilled2 = 0;
    for (int i = 0; i < nivs; i++) {
        int v = ivs[i].vreg;
        printf("    %-6s → ", vname(v));
        if (reg_of[v] >= 0)
            printf("\033[1;32mr%d\033[0m\n", reg_of[v]);
        else if (spilled_of[v]) {
            printf("\033[1;31m溢出\033[0m\n");
            nspilled2++;
        } else {
            printf("—\n");
        }
    }
    printf("    溢出变量数: \033[1;33m%d\033[0m\n", nspilled2);

    printf("\n\033[1;36m");
    printf("╔══════════════════════════════════════════════════════╗\n");
    printf("║   结论                                               ║\n");
    printf("╠══════════════════════════════════════════════════════╣\n");
    printf("║ · 第一轮溢出变量数: %-3d                              ║\n", nspilled);
    printf("║ · 每个溢出变量的 use 前插 LOAD, def 后插 STORE       ║\n");
    printf("║ · 长活跃区间被拆成多段短区间                          ║\n");
    printf("║ · 第二轮溢出变量数: %-3d                              ║\n", nspilled2);
    printf("║                                                      ║\n");
    printf("║ 为什么第二轮几乎总能成功:                             ║\n");
    printf("║   LOAD 生成的临时量紧跟在 LOAD 之后被用,             ║\n");
    printf("║   活跃区间只有 1~2 个指令; STORE 也一样。            ║\n");
    printf("║   短区间占用寄存器的时间极短, 复用率高得多。         ║\n");
    printf("╚══════════════════════════════════════════════════════╝\n");
    printf("\033[0m");

    return 0;
}
