#include <stdio.h>
#include <string.h>
#include "unit.h"
#include "calc.h"

static UnitRunner *current_runner = NULL;

static int case_add(void)
{
    ASSERT_EQ_INT(current_runner, calc_add(2, 3), 5);
    ASSERT_EQ_INT(current_runner, calc_add(-4, 4), 0);
    return 0;
}

static int case_sub(void)
{
    ASSERT_EQ_INT(current_runner, calc_sub(10, 4), 6);
    ASSERT_EQ_INT(current_runner, calc_sub(0, 9), -9);
    return 0;
}

static int case_mul(void)
{
    ASSERT_EQ_INT(current_runner, calc_mul(6, 7), 42);
    ASSERT_EQ_INT(current_runner, calc_mul(0, 99), 0);
    return 0;
}

static int case_div(void)
{
    ASSERT_EQ_INT(current_runner, calc_div(20, 4), 5);
    ASSERT_EQ_INT(current_runner, calc_div(20, 0), 0);
    return 0;
}

static int case_safe_div(void)
{
    int result = 0;
    ASSERT_EQ_INT(current_runner, calc_safe_div(9, 3, &result), 0);
    ASSERT_EQ_INT(current_runner, result, 3);
    ASSERT_EQ_INT(current_runner, calc_safe_div(9, 0, &result), -1);
    return 0;
}

static int case_clamp(void)
{
    ASSERT_EQ_INT(current_runner, calc_clamp(5, 0, 10), 5);
    ASSERT_EQ_INT(current_runner, calc_clamp(-5, 0, 10), 0);
    ASSERT_EQ_INT(current_runner, calc_clamp(50, 0, 10), 10);
    return 0;
}

static int case_sum(void)
{
    ASSERT_EQ_INT(current_runner, calc_sum_to(10), 55);
    ASSERT_EQ_INT(current_runner, calc_sum_to(0), 0);
    ASSERT_EQ_INT(current_runner, calc_sum_to(-5), 0);
    return 0;
}

static int case_strings(void)
{
    const char *left = "vitro";
    const char *right = "vitro";
    ASSERT_EQ_STR(current_runner, left, right);
    ASSERT_TRUE(current_runner, strlen(left) == 5);
    return 0;
}

static int case_near(void)
{
    ASSERT_NEAR(current_runner, calc_mul(3, 4), 12, 0);
    ASSERT_NEAR(current_runner, calc_add(1, 2), 3, 0);
    return 0;
}

static int case_broken(void)
{
    ASSERT_EQ_INT(current_runner, calc_add(2, 2), 5);
    return 0;
}

static int case_aborts(void)
{
    ASSERT_EQ_INT(current_runner, calc_mul(2, 3), 6);
    current_runner->aborted = 1;
    printf("      the case returns early like a panic\n");
    return -1;
}

int main(void)
{
    UnitRunner runner;

    unit_init(&runner);
    current_runner = &runner;
    unit_register(&runner, "add", case_add);
    unit_register(&runner, "sub", case_sub);
    unit_register(&runner, "mul", case_mul);
    unit_register(&runner, "div", case_div);
    unit_register(&runner, "safe_div", case_safe_div);
    unit_register(&runner, "clamp", case_clamp);
    unit_register(&runner, "sum_to", case_sum);
    unit_register(&runner, "strings", case_strings);
    unit_register(&runner, "near", case_near);
    unit_register(&runner, "broken_on_purpose", case_broken);
    unit_register(&runner, "aborts_early", case_aborts);

    printf("=== run the cases ===\n");
    unit_run_all(&runner);
    printf("=== report ===\n");
    unit_report(&runner);
    printf("=== the case after the early return still ran ===\n");
    printf("  aborted flag=%d cases=%d\n", runner.aborted, runner.case_count);
    printf("=== done ===\n");
    return 0;
}
