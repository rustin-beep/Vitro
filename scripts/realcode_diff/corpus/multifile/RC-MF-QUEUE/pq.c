#include "pq.h"
#include <string.h>

int pq_init(PrioQueue *queue)
{
    if (queue == NULL) {
        return PQ_ERR_NULL;
    }
    memset(queue, 0, sizeof(PrioQueue));
    queue->item_count = 0;
    queue->size = 0;
    queue->tick_count = 0;
    queue->pop_count = 0;
    return PQ_OK;
}

static int pq_higher(const PrioQueue *queue, int heap_a, int heap_b)
{
    return queue->items[queue->heap[heap_a]].priority > queue->items[queue->heap[heap_b]].priority;
}

static void pq_swap(PrioQueue *queue, int a, int b)
{
    int tmp = queue->heap[a];
    queue->heap[a] = queue->heap[b];
    queue->heap[b] = tmp;
}

static void pq_sift_up(PrioQueue *queue, int index)
{
    while (index > 0) {
        int parent = (index - 1) / 2;
        if (!pq_higher(queue, index, parent)) {
            break;
        }
        pq_swap(queue, index, parent);
        index = parent;
    }
}

static void pq_sift_down(PrioQueue *queue, int index)
{
    for (;;) {
        int left = 2 * index + 1;
        int right = 2 * index + 2;
        int largest = index;

        if (left < queue->size && pq_higher(queue, left, largest)) {
            largest = left;
        }
        if (right < queue->size && pq_higher(queue, right, largest)) {
            largest = right;
        }
        if (largest == index) {
            break;
        }
        pq_swap(queue, index, largest);
        index = largest;
    }
}

int pq_push(PrioQueue *queue, int priority, const char *name, int due_step)
{
    int slot;
    Task *task;

    if (queue == NULL || name == NULL) {
        return PQ_ERR_NULL;
    }
    if (queue->item_count >= PQ_MAX_TASKS || queue->size >= PQ_MAX_TASKS) {
        return PQ_ERR_FULL;
    }
    slot = queue->item_count;
    task = &queue->items[slot];
    task->priority = priority;
    {
        size_t n = strlen(name);
        if (n > PQ_NAME_LEN - 1) {
            n = PQ_NAME_LEN - 1;
        }
        memcpy(task->name, name, n);
        task->name[n] = '\0';
    }
    task->due_step = due_step;
    task->alive = 1;
    queue->item_count++;
    queue->heap[queue->size] = slot;
    pq_sift_up(queue, queue->size);
    queue->size++;
    return PQ_OK;
}

int pq_pop(PrioQueue *queue, Task *out)
{
    int slot;

    if (queue == NULL || out == NULL) {
        return PQ_ERR_NULL;
    }
    if (queue->size <= 0) {
        return PQ_ERR_EMPTY;
    }
    slot = queue->heap[0];
    *out = queue->items[slot];
    queue->items[slot].alive = 0;
    queue->size--;
    if (queue->size > 0) {
        queue->heap[0] = queue->heap[queue->size];
        pq_sift_down(queue, 0);
    }
    queue->pop_count++;
    return PQ_OK;
}

int pq_peek(const PrioQueue *queue, Task *out)
{
    if (queue == NULL || out == NULL) {
        return PQ_ERR_NULL;
    }
    if (queue->size <= 0) {
        return PQ_ERR_EMPTY;
    }
    *out = queue->items[queue->heap[0]];
    return PQ_OK;
}

int pq_tick(PrioQueue *queue, int steps)
{
    if (queue == NULL) {
        return PQ_ERR_NULL;
    }
    if (steps < 0) {
        return PQ_ERR_NULL;
    }
    queue->tick_count += steps;
    return pq_expired_count(queue);
}

int pq_remove(PrioQueue *queue, const char *name)
{
    int i;
    int found = 0;

    if (queue == NULL || name == NULL) {
        return PQ_ERR_NULL;
    }
    for (i = 0; i < queue->item_count; i++) {
        if (queue->items[i].alive && strcmp(queue->items[i].name, name) == 0) {
            queue->items[i].alive = 0;
            found = 1;
            break;
        }
    }
    if (!found) {
        return PQ_ERR_EMPTY;
    }
    queue->size = 0;
    for (i = 0; i < queue->item_count; i++) {
        if (queue->items[i].alive) {
            queue->heap[queue->size] = i;
            pq_sift_up(queue, queue->size);
            queue->size++;
        }
    }
    return PQ_OK;
}

int pq_size(const PrioQueue *queue)
{
    if (queue == NULL) {
        return PQ_ERR_NULL;
    }
    return queue->size;
}

int pq_expired_count(const PrioQueue *queue)
{
    int count = 0;
    int i;

    if (queue == NULL) {
        return PQ_ERR_NULL;
    }
    for (i = 0; i < queue->item_count; i++) {
        if (queue->items[i].alive && queue->items[i].due_step <= queue->tick_count) {
            count++;
        }
    }
    return count;
}

int pq_pop_count(const PrioQueue *queue)
{
    if (queue == NULL) {
        return PQ_ERR_NULL;
    }
    return queue->pop_count;
}
