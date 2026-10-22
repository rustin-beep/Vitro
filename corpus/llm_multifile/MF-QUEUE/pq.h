#ifndef PQ_H
#define PQ_H

#define PQ_MAX_TASKS 64
#define PQ_NAME_LEN 16

#define PQ_OK          0
#define PQ_ERR_NULL  (-1)
#define PQ_ERR_FULL  (-2)
#define PQ_ERR_EMPTY (-3)
#define PQ_ERR_NOMEM (-4)

typedef struct {
    int priority;
    char name[PQ_NAME_LEN];
    int due_step;
    int alive;
} Task;

typedef struct {
    Task items[PQ_MAX_TASKS];
    int heap[PQ_MAX_TASKS];
    int item_count;
    int size;
    int tick_count;
    int pop_count;
} PrioQueue;

int pq_init(PrioQueue *queue);
int pq_push(PrioQueue *queue, int priority, const char *name, int due_step);
int pq_pop(PrioQueue *queue, Task *out);
int pq_peek(const PrioQueue *queue, Task *out);
int pq_tick(PrioQueue *queue, int steps);
int pq_remove(PrioQueue *queue, const char *name);
int pq_size(const PrioQueue *queue);
int pq_expired_count(const PrioQueue *queue);
int pq_pop_count(const PrioQueue *queue);

#endif /* PQ_H */
