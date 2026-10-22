#include <stdio.h>
#include "task.h"

static int fail_mode = 0;

static int run_task(int id, const char *name, void *context)
{
    (void)context;
    printf("      running task %d %s\n", id, name);
    if (fail_mode && (id == 2 || id == 5)) {
        printf("      task %d fails on purpose\n", id);
        return 10 + id;
    }
    return 0;
}

int main(void)
{
    TaskRunner runner;
    int i;

    task_init(&runner);
    task_add(&runner, "prepare", 0x00, 0, run_task, NULL);
    task_add(&runner, "fetch", 0x01, 1, run_task, NULL);
    task_add(&runner, "broken", 0x00, 0, run_task, NULL);
    task_add(&runner, "transform", 0x04, 1, run_task, NULL);
    task_add(&runner, "cleanup", 0x00, 0, run_task, NULL);
    task_add(&runner, "failing", 0x10, 1, run_task, NULL);
    task_add(&runner, "report", 0x18, 2, run_task, NULL);
    task_add(&runner, "notify", 0x40, 1, run_task, NULL);

    printf("=== first run with two failing tasks ===\n");
    fail_mode = 1;
    task_run_all(&runner);
    task_print_status(&runner);
    printf("  order:");
    for (i = 0; i < runner.order_length; i++) {
        printf(" %d", runner.order[i]);
    }
    printf("\n  successes=%d failures=%d skipped=%d\n",
           runner.successes, runner.failures, runner.skipped);

    printf("=== reset and run again without the failures ===\n");
    task_reset(&runner);
    fail_mode = 0;
    task_run_all(&runner);
    task_print_status(&runner);
    printf("  order:");
    for (i = 0; i < runner.order_length; i++) {
        printf(" %d", runner.order[i]);
    }
    printf("\n  successes=%d failures=%d skipped=%d\n",
           runner.successes, runner.failures, runner.skipped);
    printf("=== done ===\n");
    return 0;
}
