#include <stdio.h>

#define MAX 8

// 静态链表（游标形态：space[i].cur 指向后继，0 号为备用链表头）
struct StaticNode {
    int data;
    int cur;
};

void staticListInit(struct StaticNode space[]) {
    for (int i = 0; i < MAX - 1; i++) {
        space[i].cur = i + 1;
    }
    space[MAX - 1].cur = 0;
    space[0].data = -1;
}

int staticListMalloc(struct StaticNode space[]) {
    int i = space[0].cur;
    if (space[0].cur) {
        space[0].cur = space[i].cur;
    }
    return i;
}

void staticListFree(struct StaticNode space[], int k) {
    space[k].cur = space[0].cur;
    space[0].cur = k;
}

int main() {
    struct StaticNode space[MAX];
    staticListInit(space);
    int a = staticListMalloc(space);
    int b = staticListMalloc(space);
    space[a].data = 11;
    space[b].data = 22;
    space[a].cur = b;
    space[b].cur = 0;
    printf("首节点 %d -> 次节点 %d\n", space[a].data, space[b].data);
    staticListFree(space, b);
    return 0;
}
