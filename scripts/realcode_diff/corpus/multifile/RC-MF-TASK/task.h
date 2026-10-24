#ifndef TASK_H
#define TASK_H

#define TASK_MAX 16
#define TASK_NAME_LEN 24
#define TASK_MAX_DEPS 8

typedef enum {
    TASK_PENDING = 0,
    TASK_RUNNING = 1,
    TASK_SUCCESS = 2,
    TASK_FAILED = 3,
    TASK_SKIPPED = 4
} TaskStatus;

typedef int (*TaskFunction)(int id, const char *name, void *context);

typedef struct {
    int id;
    char name[TASK_NAME_LEN];
    unsigned int dependencies;
    int dependency_count;
    TaskStatus status;
    int error_code;
    TaskFunction function;
    void *context;
    int executed_order;
} Task;

typedef struct {
    Task tasks[TASK_MAX];
    int count;
    int order[TASK_MAX];
    int order_length;
    int successes;
    int failures;
    int skipped;
} TaskRunner;

void task_init(TaskRunner *runner);
int task_add(TaskRunner *runner, const char *name, unsigned int dependencies,
             int dependency_count, TaskFunction function, void *context);
int task_run_all(TaskRunner *runner);
int task_status(const TaskRunner *runner, int id);
void task_reset(TaskRunner *runner);
void task_print_status(const TaskRunner *runner);
const char *task_status_name(TaskStatus status);

#endif /* TASK_H */
