#include "task.h"
#include <stdio.h>
#include <string.h>

static void task_copy(char *dst, size_t cap, const char *src)
{
    size_t n;

    if (dst == NULL || src == NULL || cap == 0) {
        return;
    }
    n = strlen(src);
    if (n > cap - 1) {
        n = cap - 1;
    }
    memcpy(dst, src, n);
    dst[n] = '\0';
}

const char *task_status_name(TaskStatus status)
{
    switch (status) {
        case TASK_PENDING:
            return "PENDING";
        case TASK_RUNNING:
            return "RUNNING";
        case TASK_SUCCESS:
            return "SUCCESS";
        case TASK_FAILED:
            return "FAILED";
        case TASK_SKIPPED:
            return "SKIPPED";
        default:
            return "UNKNOWN";
    }
}

void task_init(TaskRunner *runner)
{
    memset(runner, 0, sizeof(TaskRunner));
}

int task_add(TaskRunner *runner, const char *name, unsigned int dependencies,
             int dependency_count, TaskFunction function, void *context)
{
    Task *task;

    if (runner->count >= TASK_MAX) {
        return -1;
    }
    task = &runner->tasks[runner->count];
    memset(task, 0, sizeof(Task));
    task->id = runner->count;
    task_copy(task->name, TASK_NAME_LEN, name);
    task->dependencies = dependencies;
    task->dependency_count = dependency_count;
    task->function = function;
    task->context = context;
    task->status = TASK_PENDING;
    task->error_code = 0;
    task->executed_order = -1;
    runner->count++;
    return task->id;
}

static int task_dependencies_ready(const TaskRunner *runner, const Task *task)
{
    int i;

    for (i = 0; i < task->dependency_count; i++) {
        int dep = (int)((task->dependencies >> i) & 1u);
        if (dep && i < runner->count) {
            if (runner->tasks[i].status != TASK_SUCCESS) {
                return 0;
            }
        }
    }
    return 1;
}

static int task_dependencies_failed(const TaskRunner *runner, const Task *task)
{
    int i;

    for (i = 0; i < task->dependency_count; i++) {
        int dep = (int)((task->dependencies >> i) & 1u);
        if (dep && i < runner->count) {
            if (runner->tasks[i].status == TASK_FAILED ||
                runner->tasks[i].status == TASK_SKIPPED) {
                return 1;
            }
        }
    }
    return 0;
}

int task_run_all(TaskRunner *runner)
{
    int progress = 1;
    int guard = 0;

    runner->order_length = 0;
    runner->successes = 0;
    runner->failures = 0;
    runner->skipped = 0;
    while (progress && guard < TASK_MAX * TASK_MAX) {
        int i;
        progress = 0;
        guard++;
        for (i = 0; i < runner->count; i++) {
            Task *task = &runner->tasks[i];
            if (task->status != TASK_PENDING) {
                continue;
            }
            if (!task_dependencies_ready(runner, task)) {
                if (task_dependencies_failed(runner, task)) {
                    task->status = TASK_SKIPPED;
                    task->error_code = 99;
                    runner->skipped++;
                    runner->order[runner->order_length++] = i;
                    progress = 1;
                }
                continue;
            }
            task->status = TASK_RUNNING;
            task->error_code = (task->function != NULL)
                                   ? task->function(task->id, task->name, task->context)
                                   : 0;
            if (task->error_code == 0) {
                task->status = TASK_SUCCESS;
                runner->successes++;
            } else {
                task->status = TASK_FAILED;
                runner->failures++;
            }
            task->executed_order = runner->order_length;
            runner->order[runner->order_length++] = i;
            progress = 1;
        }
    }
    for (progress = 0; progress < runner->count; progress++) {
        if (runner->tasks[progress].status == TASK_PENDING) {
            runner->tasks[progress].status = TASK_SKIPPED;
            runner->tasks[progress].error_code = 98;
            runner->skipped++;
        }
    }
    return runner->order_length;
}

int task_status(const TaskRunner *runner, int id)
{
    if (runner == NULL || id < 0 || id >= runner->count) {
        return -1;
    }
    return (int)runner->tasks[id].status;
}

void task_reset(TaskRunner *runner)
{
    int i;

    for (i = 0; i < runner->count; i++) {
        runner->tasks[i].status = TASK_PENDING;
        runner->tasks[i].error_code = 0;
        runner->tasks[i].executed_order = -1;
    }
    runner->order_length = 0;
    runner->successes = 0;
    runner->failures = 0;
    runner->skipped = 0;
}

void task_print_status(const TaskRunner *runner)
{
    int i;

    for (i = 0; i < runner->count; i++) {
        const Task *task = &runner->tasks[i];
        printf("    %d %-16s status=%-8s error=%-4d order=%d\n", task->id, task->name,
               task_status_name(task->status), task->error_code, task->executed_order);
    }
}
