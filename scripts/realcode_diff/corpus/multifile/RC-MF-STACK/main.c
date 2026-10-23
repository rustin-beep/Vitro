#include <stdio.h>
#include "stack.h"

int main(void)
{
    IntStack stack;
    IntQueue queue;
    int pushes[6];
    int value;
    int rc;
    int bad;
    int i;
    const char *cases[5];

    pushes[0] = 10;
    pushes[1] = 20;
    pushes[2] = 30;
    pushes[3] = 40;
    pushes[4] = 50;
    pushes[5] = 60;

    stack_init(&stack, 8);
    queue_init(&queue, 8);

    printf("=== stack LIFO ===\n");
    for (i = 0; i < 6; i++) {
        rc = stack_push(&stack, pushes[i]);
        printf("push %2d rc=%2d size=%d\n", pushes[i], rc, stack_size(&stack));
    }
    for (i = 0; i < 6; i++) {
        rc = stack_pop(&stack, &value);
        printf("pop  rc=%2d value=%2d size=%d\n", rc, value, stack_size(&stack));
    }

    printf("=== queue FIFO ===\n");
    for (i = 0; i < 6; i++) {
        rc = queue_push(&queue, pushes[i]);
        printf("enq %2d rc=%2d size=%d\n", pushes[i], rc, queue_size(&queue));
    }
    for (i = 0; i < 6; i++) {
        rc = queue_pop(&queue, &value);
        printf("deq  rc=%2d value=%2d size=%d\n", rc, value, queue_size(&queue));
    }

    printf("=== bracket match ===\n");
    cases[0] = "a(b(c))d";
    cases[1] = "x[y{z}]w";
    cases[2] = "([)]";
    cases[3] = "no brackets here";
    cases[4] = "(((";
    for (i = 0; i < 5; i++) {
        bad = -1;
        rc = bracket_match(cases[i], &bad);
        if (rc == STACK_OK) {
            printf("case%d [%s] matched=yes bad_pos=%d\n", i, cases[i], bad);
        } else {
            printf("case%d [%s] matched=no  bad_pos=%d rc=%d\n", i, cases[i], bad, rc);
        }
    }

    printf("=== overflow / underflow ===\n");
    for (i = 0; i < 10; i++) {
        rc = stack_push(&stack, i);
        if (rc != STACK_OK) {
            printf("stack push %2d rc=%d (overflow handled)\n", i, rc);
            break;
        }
    }
    rc = stack_pop(&stack, &value);
    printf("stack pop after overflow rc=%d value=%d\n", rc, value);

    for (i = 0; i < 10; i++) {
        rc = queue_push(&queue, i);
        if (rc != STACK_OK) {
            printf("queue push %2d rc=%d (overflow handled)\n", i, rc);
            break;
        }
    }
    rc = queue_pop(&queue, &value);
    printf("queue pop after overflow rc=%d value=%d\n", rc, value);

    for (i = 0; i < 10; i++) {
        rc = stack_pop(&stack, &value);
        if (rc != STACK_OK) {
            printf("stack underflow rc=%d (handled)\n", rc);
            break;
        }
    }
    for (i = 0; i < 10; i++) {
        rc = queue_pop(&queue, &value);
        if (rc != STACK_OK) {
            printf("queue underflow rc=%d (handled)\n", rc);
            break;
        }
    }
    rc = stack_peek(&stack, &value);
    printf("stack peek empty rc=%d\n", rc);
    rc = queue_peek(&queue, &value);
    printf("queue peek empty rc=%d\n", rc);
    return 0;
}
