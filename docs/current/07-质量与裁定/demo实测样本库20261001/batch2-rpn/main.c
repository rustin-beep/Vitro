#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include <math.h>

#define STACK_MAX 128

/* ---------- 栈结构 ---------- */
typedef struct {
    double data[STACK_MAX];
    int    top;          /* 栈顶下标，-1 表示空栈 */
} Stack;

static void stack_init(Stack *s)
{
    s->top = -1;
}

static int stack_empty(const Stack *s)
{
    return s->top == -1;
}

static int stack_push(Stack *s, double v)
{
    if (s->top == STACK_MAX - 1)
        return 0;               /* 栈满 */
    s->data[++s->top] = v;
    return 1;
}

static int stack_pop(Stack *s, double *out)
{
    if (stack_empty(s))
        return 0;               /* 栈空 */
    *out = s->data[s->top--];
    return 1;
}

/* ---------- 后缀表达式求值 ---------- */
/* 支持 + - * / 以及 % 求余（整数运算），数字用空格分隔 */
static int eval_rpn(const char *expr, double *result)
{
    Stack  s;
    double a, b;
    stack_init(&s);

    const char *p = expr;

    while (*p != '\0') {

        /* 跳过空白 */
        if (isspace((unsigned char)*p)) {
            p++;
            continue;
        }

        /* 数字：可能带负号或小数点 */
        if (isdigit((unsigned char)*p) ||
            (*p == '-' && isdigit((unsigned char)*(p + 1)))) {

            char *end;
            double v = strtod(p, &end);
            if (end == p)
                return 0;               /* 解析失败 */
            if (!stack_push(&s, v))
                return 0;               /* 栈溢出 */

            p = end;                    /* 指针跳到数字之后 */
            continue;
        }

        /* 运算符：弹出两个操作数 */
        if (!stack_pop(&s, &b) || !stack_pop(&s, &a))
            return 0;                   /* 操作数不足 */

        switch (*p) {
        case '+': stack_push(&s, a + b);          break;
        case '-': stack_push(&s, a - b);          break;
        case '*': stack_push(&s, a * b);          break;
        case '/':
            if (fabs(b) < 1e-12) return 0;        /* 除零 */
            stack_push(&s, a / b);
            break;
        case '%':
            if ((int)b == 0) return 0;
            stack_push(&s, (double)((int)a % (int)b));
            break;
        default:
            return 0;                             /* 非法字符 */
        }
        p++;
    }

    /* 最终栈里应恰好剩一个结果 */
    if (!stack_pop(&s, result) || !stack_empty(&s))
        return 0;

    return 1;
}

/* ---------- 主函数：逐个测试 ---------- */
int main(void)
{
    const char *tests[] = {
        "3 4 +",              /* 7         */
        "5 1 2 + 4 * + 3 -",  /* 14        */
        "10 2 /",             /* 5         */
        "2 3 4 * +",          /* 14        */
        "7 3 %",              /* 1         */
        "8 0 /",              /* 除零，应失败 */
        "1 +",                /* 操作数不足，应失败 */
    };

    int n = (int)(sizeof(tests) / sizeof(tests[0]));

    for (int i = 0; i < n; i++) {
        double r;
        printf("表达式: %-22s -> ", tests[i]);
        if (eval_rpn(tests[i], &r))
            printf("结果 = %g\n", r);
        else
            printf("求值失败（语法错误 / 除零 / 栈溢出）\n");
    }

    return 0;
}
