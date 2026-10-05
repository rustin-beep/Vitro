#include <stdio.h>

typedef struct {
    int* in;
    int* out;
    int inTop;
    int outTop;
} Queue;

int main() {
    int in_arr[4] = {10, 20, 30, 40};
    int out_arr[4] = {0, 0, 0, 0};
    Queue q;
    Queue* p = &q;
    p->in = in_arr;
    p->out = out_arr;
    p->inTop = 2;
    p->outTop = -1;

    p->out[++p->outTop] = p->in[p->inTop--];

    printf("%d %d %d %d\n", p->outTop, p->out[0], p->inTop, p->in[2]);
    return 0;
}
