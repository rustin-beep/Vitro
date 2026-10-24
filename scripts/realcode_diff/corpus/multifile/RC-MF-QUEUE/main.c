#include <stdio.h>
#include <string.h>
#include "pq.h"

static const char *NAMES[8] = {
    "alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel"
};
static const int PRIORITIES[8] = { 3, 8, 1, 6, 5, 2, 9, 4 };
static const int DUE_STEPS[8] = { 5, 12, 3, 20, 8, 15, 7, 30 };

static void copy_name(char *dst, const char *src)
{
    size_t n = strlen(src);
    if (n > PQ_NAME_LEN - 1) {
        n = PQ_NAME_LEN - 1;
    }
    memcpy(dst, src, n);
    dst[n] = '\0';
}

int main(void)
{
    PrioQueue queue;
    Task task;
    char popped[16][PQ_NAME_LEN];
    char expected[16][PQ_NAME_LEN];
    int alive[8];
    int i;
    int rc;
    int matches;

    pq_init(&queue);
    for (i = 0; i < 8; i++) {
        alive[i] = 1;
    }

    printf("=== insert 8 tasks ===\n");
    for (i = 0; i < 8; i++) {
        rc = pq_push(&queue, PRIORITIES[i], NAMES[i], DUE_STEPS[i]);
        if (pq_peek(&queue, &task) == PQ_OK) {
            printf("push %-8s prio=%d rc=%2d top=%-8s size=%d\n",
                   NAMES[i], PRIORITIES[i], rc, task.name, pq_size(&queue));
        } else {
            printf("push %-8s prio=%d rc=%2d size=%d\n", NAMES[i], PRIORITIES[i], rc, pq_size(&queue));
        }
    }

    printf("=== tick 5 ===\n");
    rc = pq_tick(&queue, 5);
    printf("tick(5) expired=%d tick_count=%d size=%d\n", rc, queue.tick_count, pq_size(&queue));
    rc = pq_tick(&queue, 5);
    printf("tick(5) expired=%d tick_count=%d size=%d\n", rc, queue.tick_count, pq_size(&queue));

    printf("=== remove delta ===\n");
    rc = pq_remove(&queue, "delta");
    printf("remove delta rc=%2d size=%d\n", rc, pq_size(&queue));
    pq_peek(&queue, &task);
    printf("top after remove = %s\n", task.name);
    alive[3] = 0;

    printf("=== pop all ===\n");
    for (i = 0; i < 16; i++) {
        rc = pq_pop(&queue, &task);
        if (rc != PQ_OK) {
            break;
        }
        copy_name(popped[i], task.name);        printf("pop %-8s prio=%d due=%d size=%d\n", task.name, task.priority, task.due_step, pq_size(&queue));
    }

    printf("=== expected order (priority desc) ===\n");
    {
        int used[8];
        for (i = 0; i < 8; i++) {
            used[i] = 0;
        }
        for (i = 0; i < 8; i++) {
            int best = -1;
            int k;
            for (k = 0; k < 8; k++) {
                if (!alive[k] || used[k]) {
                    continue;
                }
                if (best < 0 || PRIORITIES[k] > PRIORITIES[best]) {
                    best = k;
                }
            }
            if (best < 0) {
                break;
            }
            used[best] = 1;
            copy_name(expected[i], NAMES[best]);
            printf("  expected[%d] = %s\n", i, expected[i]);
        }
    }

    printf("=== compare ===\n");
    matches = 1;
    for (i = 0; i < 8; i++) {
        printf("  popped[%d]=%-8s expected=%-8s same=%s\n", i, popped[i], expected[i],
               strcmp(popped[i], expected[i]) == 0 ? "yes" : "no");
        if (strcmp(popped[i], expected[i]) != 0) {
            matches = 0;
        }
    }
    printf("order_matches_expected = %s\n", matches ? "yes" : "no");
    printf("pop_count=%d size=%d expired=%d\n",
           pq_pop_count(&queue), pq_size(&queue), pq_expired_count(&queue));
    return 0;
}
