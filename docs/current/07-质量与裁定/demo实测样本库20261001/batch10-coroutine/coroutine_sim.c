/* coroutine_sim.c —— 纯 C 模拟协程调度器
 *
 * 编译: gcc -Wall -O2 -o coroutine_sim coroutine_sim.c
 * 运行: ./coroutine_sim
 *
 * 核心思想:
 *   ucontext 版的协程靠"独立栈 + 寄存器切换"实现。
 *   这里不切栈——协程的"挂起点"用一个程序计数器 pc 记住，
 *   调度器每次调用 step() 时，从 pc 指示的位置继续执行。
 *
 *   这就是编译器编译 async/await 的方式：
 *   把"可暂停的函数"翻译成状态机。
 *   你写的代码里没有真正的独立栈，但行为完全等价。
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_COOP 16

/* ================================================================
 * 1. 协程结构
 * ================================================================ */
typedef struct Coroutine Coroutine;

/* step 函数每次被调用，从上次暂停处继续执行到下一个暂停点。
 *   返回 1 = 暂停（下轮调度继续）
 *   返回 0 = 结束 */
typedef int (*StepFn)(Coroutine *);

struct Coroutine {
    int     id;
    int     alive;        /* 1 = 还在跑，0 = 已结束 */
    int     steps;        /* 被调度过几次 */
    StepFn  step;
    void   *locals;       /* 协程私有状态，相当于它的"栈帧" */
};

static Coroutine *g_coops[MAX_COOP];
static int        g_ncoops   = 0;
static int        g_current  = -1;

/* ================================================================
 * 2. 调度器
 *
 *    轮转：每轮把所有还活着的协程各跑一步。
 *    和 ucontext 版完全一样，只是"切换"变成了"函数返回"。
 * ================================================================ */
static void schedule(void)
{
    int alive;
    do {
        alive = 0;
        for (int i = 0; i < g_ncoops; i++) {
            Coroutine *co = g_coops[i];
            if (!co->alive) continue;

            alive = 1;
            g_current = i;
            co->steps++;

            int r = co->step(co);
            if (r == 0) co->alive = 0;

            g_current = -1;
        }
    } while (alive);
}

/* ================================================================
 * 3. 创建 / 清理
 * ================================================================ */
static Coroutine *co_create(StepFn step, void *locals)
{
    if (g_ncoops >= MAX_COOP) return NULL;

    Coroutine *co = (Coroutine *)calloc(1, sizeof(Coroutine));
    co->id     = g_ncoops;
    co->alive  = 1;
    co->steps  = 0;
    co->step   = step;
    co->locals = locals;

    g_coops[g_ncoops++] = co;
    return co;
}

/* 协程可以"知道自己是哪一个"——对应 ucontext 版的 co_self() */
static Coroutine *co_self(void)
{
    return (g_current >= 0) ? g_coops[g_current] : NULL;
}

static void cleanup(void)
{
    for (int i = 0; i < g_ncoops; i++) {
        free(g_coops[i]->locals);
        free(g_coops[i]);
        g_coops[i] = NULL;
    }
    g_ncoops  = 0;
    g_current = -1;
}

/* ================================================================
 * 4. 演示 1：斐波那契 + 字母（轮转）
 *
 *    对比 ucontext 版：
 *      co_yield()  ==>  return 1;
 *      函数结束    ==>  return 0;
 *      局部变量    ==>  放在 locals 结构体里
 * ================================================================ */
typedef struct { int pc; int a, b, i; } FibState;

static int fib_step(Coroutine *co)
{
    FibState *L = (FibState *)co->locals;

    switch (L->pc) {
    case 0:                       /* 首次进入：初始化 */
        L->a = 1;
        L->b = 1;
        L->i = 0;
        L->pc = 1;
        /* 有意贯穿到 case 1 */

    case 1:                       /* 循环体 */
        if (L->i >= 10) return 0;   /* 结束 */

        printf("  [fib ] %2d\n", L->a);
        {
            int t = L->a + L->b;
            L->a = L->b;
            L->b = t;
        }
        L->i++;

        /* co_yield()：保持 pc = 1，返回 1 */
        return 1;
    }
    return 0;
}

typedef struct { int pc; int i; } AlphaState;

static int alpha_step(Coroutine *co)
{
    AlphaState *L = (AlphaState *)co->locals;

    switch (L->pc) {
    case 0:
        L->i  = 0;
        L->pc = 1;
        /* fall through */

    case 1:
        if (L->i >= 8) return 0;
        printf("  [alph] %c\n", 'A' + L->i);
        L->i++;
        return 1;
    }
    return 0;
}

/* ================================================================
 * 5. 演示 2：共享状态
 *
 *    两个协程交叉访问同一个全局变量，
 *    因为每次让出后状态完整保留，交叉计数干净利落。
 * ================================================================ */
static int g_shared_counter = 0;

typedef struct {
    int         pc;
    int         i;
    const char *name;
} CounterState;

static int counter_step(Coroutine *co)
{
    CounterState *L = (CounterState *)co->locals;

    switch (L->pc) {
    case 0:
        L->i  = 0;
        L->pc = 1;
        /* fall through */

    case 1:
        if (L->i >= 6) return 0;
        {
            int v = ++g_shared_counter;
            printf("  [%s] 共享计数 = %d\n", L->name, v);
        }
        L->i++;
        return 1;
    }
    return 0;
}

/* ================================================================
 * 6. 演示 3：协程能"感知"自己
 * ================================================================ */
typedef struct { int pc; } SelfState;

static int self_step(Coroutine *co)
{
    SelfState *L = (SelfState *)co->locals;

    switch (L->pc) {
    case 0:
        printf("  [self] 我是协程 #%d，开始运行\n", co->id);
        L->pc = 1;
        return 1;

    case 1:
        printf("  [self] 我被调度了 %d 次\n", co->steps);
        L->pc = 2;
        return 1;

    case 2:
        printf("  [self] 最后一次运行，准备结束\n");
        return 0;
    }
    return 0;
}

/* ================================================================
 * 7. main
 * ================================================================ */
int main(void)
{
    printf("=== 用户态协程调度器（纯 C 模拟） ===\n");
    printf("（不用 ucontext、不用汇编——用显式状态机模拟）\n\n");

    printf("--- 演示 1：轮转调度 ---\n\n");
    {
        FibState   *fs = (FibState *)calloc(1, sizeof(FibState));
        AlphaState *as = (AlphaState *)calloc(1, sizeof(AlphaState));
        co_create(fib_step,   fs);
        co_create(alpha_step, as);
        schedule();
        cleanup();
    }

    printf("\n--- 演示 2：协程间共享状态 ---\n\n");
    {
        g_shared_counter = 0;

        CounterState *c1 = (CounterState *)calloc(1, sizeof(CounterState));
        CounterState *c2 = (CounterState *)calloc(1, sizeof(CounterState));
        CounterState *c3 = (CounterState *)calloc(1, sizeof(CounterState));
        c1->name = "A";
        c2->name = "B";
        c3->name = "C";

        co_create(counter_step, c1);
        co_create(counter_step, c2);
        co_create(counter_step, c3);
        schedule();
        cleanup();
    }

    printf("\n--- 演示 3：协程能\"知道自己是谁\" ---\n\n");
    {
        SelfState *ss = (SelfState *)calloc(1, sizeof(SelfState));
        co_create(self_step, ss);
        schedule();
        cleanup();
    }

    printf("\n=== 全部完成 ===\n");
    return 0;
}
