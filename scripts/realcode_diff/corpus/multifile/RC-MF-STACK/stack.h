#ifndef STACK_H
#define STACK_H

#define STACK_MAX_CAP 32
#define QUEUE_MAX_CAP 32

#define STACK_OK        0
#define STACK_ERR_FULL (-1)
#define STACK_ERR_EMPTY (-2)
#define STACK_ERR_NULL (-3)

typedef struct {
    int data[STACK_MAX_CAP];
    int top;
    int capacity;
} IntStack;

typedef struct {
    int data[QUEUE_MAX_CAP];
    int head;
    int tail;
    int count;
    int capacity;
} IntQueue;

int stack_init(IntStack *stack, int capacity);
int stack_push(IntStack *stack, int value);
int stack_pop(IntStack *stack, int *out);
int stack_peek(const IntStack *stack, int *out);
int stack_size(const IntStack *stack);

int queue_init(IntQueue *queue, int capacity);
int queue_push(IntQueue *queue, int value);
int queue_pop(IntQueue *queue, int *out);
int queue_peek(const IntQueue *queue, int *out);
int queue_size(const IntQueue *queue);

/* bracket matching over (), [] and {}; returns STACK_OK when balanced, otherwise
 * STACK_ERR_EMPTY and stores the index of the first offending character in bad_pos */
int bracket_match(const char *text, int *bad_pos);

#endif /* STACK_H */
