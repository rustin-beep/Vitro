#include "stack.h"
#include <string.h>

int stack_init(IntStack *stack, int capacity)
{
    if (stack == NULL) {
        return STACK_ERR_NULL;
    }
    if (capacity <= 0 || capacity > STACK_MAX_CAP) {
        return STACK_ERR_FULL;
    }
    stack->top = 0;
    stack->capacity = capacity;
    return STACK_OK;
}

int stack_push(IntStack *stack, int value)
{
    if (stack == NULL) {
        return STACK_ERR_NULL;
    }
    if (stack->top >= stack->capacity) {
        return STACK_ERR_FULL;
    }
    stack->data[stack->top] = value;
    stack->top++;
    return STACK_OK;
}

int stack_pop(IntStack *stack, int *out)
{
    if (stack == NULL || out == NULL) {
        return STACK_ERR_NULL;
    }
    if (stack->top <= 0) {
        return STACK_ERR_EMPTY;
    }
    stack->top--;
    *out = stack->data[stack->top];
    return STACK_OK;
}

int stack_peek(const IntStack *stack, int *out)
{
    if (stack == NULL || out == NULL) {
        return STACK_ERR_NULL;
    }
    if (stack->top <= 0) {
        return STACK_ERR_EMPTY;
    }
    *out = stack->data[stack->top - 1];
    return STACK_OK;
}

int stack_size(const IntStack *stack)
{
    if (stack == NULL) {
        return STACK_ERR_NULL;
    }
    return stack->top;
}

int queue_init(IntQueue *queue, int capacity)
{
    if (queue == NULL) {
        return STACK_ERR_NULL;
    }
    if (capacity <= 0 || capacity > QUEUE_MAX_CAP) {
        return STACK_ERR_FULL;
    }
    queue->head = 0;
    queue->tail = 0;
    queue->count = 0;
    queue->capacity = capacity;
    return STACK_OK;
}

int queue_push(IntQueue *queue, int value)
{
    if (queue == NULL) {
        return STACK_ERR_NULL;
    }
    if (queue->count >= queue->capacity) {
        return STACK_ERR_FULL;
    }
    queue->data[queue->tail] = value;
    queue->tail = (queue->tail + 1) % queue->capacity;
    queue->count++;
    return STACK_OK;
}

int queue_pop(IntQueue *queue, int *out)
{
    if (queue == NULL || out == NULL) {
        return STACK_ERR_NULL;
    }
    if (queue->count <= 0) {
        return STACK_ERR_EMPTY;
    }
    *out = queue->data[queue->head];
    queue->head = (queue->head + 1) % queue->capacity;
    queue->count--;
    return STACK_OK;
}

int queue_peek(const IntQueue *queue, int *out)
{
    if (queue == NULL || out == NULL) {
        return STACK_ERR_NULL;
    }
    if (queue->count <= 0) {
        return STACK_ERR_EMPTY;
    }
    *out = queue->data[queue->head];
    return STACK_OK;
}

int queue_size(const IntQueue *queue)
{
    if (queue == NULL) {
        return STACK_ERR_NULL;
    }
    return queue->count;
}

static int bracket_close_of(char open)
{
    if (open == '(') {
        return ')';
    }
    if (open == '[') {
        return ']';
    }
    if (open == '{') {
        return '}';
    }
    return 0;
}

static int bracket_is_open(char c)
{
    return (c == '(' || c == '[' || c == '{') ? 1 : 0;
}

static int bracket_is_close(char c)
{
    return (c == ')' || c == ']' || c == '}') ? 1 : 0;
}

int bracket_match(const char *text, int *bad_pos)
{
    char stack[STACK_MAX_CAP];
    int top;
    int i;

    if (bad_pos != NULL) {
        *bad_pos = -1;
    }
    if (text == NULL) {
        return STACK_ERR_NULL;
    }
    top = 0;
    i = 0;
    for (; text[i] != '\0'; i++) {
        char c = text[i];
        if (bracket_is_open(c)) {
            if (top >= STACK_MAX_CAP) {
                if (bad_pos != NULL) {
                    *bad_pos = i;
                }
                return STACK_ERR_FULL;
            }
            stack[top] = c;
            top++;
        } else if (bracket_is_close(c)) {
            if (top == 0) {
                if (bad_pos != NULL) {
                    *bad_pos = i;
                }
                return STACK_ERR_EMPTY;
            }
            if (bracket_close_of(stack[top - 1]) != c) {
                if (bad_pos != NULL) {
                    *bad_pos = i;
                }
                return STACK_ERR_EMPTY;
            }
            top--;
        }
    }
    if (top != 0) {
        if (bad_pos != NULL) {
            *bad_pos = (int)strlen(text) - 1;
        }
        return STACK_ERR_EMPTY;
    }
    return STACK_OK;
}
