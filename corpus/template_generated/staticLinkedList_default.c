// @category: baseline
#include <stdio.h>
#define MAXSIZE 10

struct Component {
    int data;
    int cur;
};

void initSpace(struct Component space[]) {
    for (int i = 0; i < MAXSIZE - 1; i++)
        space[i].cur = i + 1;
    space[MAXSIZE - 1].cur = 0;
}

int mallocNode(struct Component space[]) {
    int i = space[0].cur;
    if (i) space[0].cur = space[i].cur;
    return i;
}

void freeNode(struct Component space[], int k) {
    space[k].cur = space[0].cur;
    space[0].cur = k;
}

int main() {
    struct Component space[MAXSIZE];
    initSpace(space);
    int head = mallocNode(space);
    space[head].data = 10;
    int p = mallocNode(space);
    space[p].data = 20;
    space[head].cur = p;
    space[p].cur = 0;
    printf("%d %d\n", space[head].data, space[space[head].cur].data);
    return 0;
}

