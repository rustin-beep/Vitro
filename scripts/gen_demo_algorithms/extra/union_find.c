#include <stdio.h>

#define MAX 10

int unionFindParent[MAX];

void unionFindInit(int n) {
    for (int i = 0; i < n; i++) unionFindParent[i] = i;
}

int unionFindRoot(int x) {
    while (unionFindParent[x] != x) {
        unionFindParent[x] = unionFindParent[unionFindParent[x]];
        x = unionFindParent[x];
    }
    return x;
}

void unionFindMerge(int a, int b) {
    int ra = unionFindRoot(a);
    int rb = unionFindRoot(b);
    if (ra != rb) unionFindParent[ra] = rb;
}

int unionFindConnected(int a, int b) {
    return unionFindRoot(a) == unionFindRoot(b);
}

int main() {
    unionFindInit(6);
    unionFindMerge(0, 1);
    unionFindMerge(2, 3);
    unionFindMerge(1, 3);
    printf("0 与 3 连通: %s\n", unionFindConnected(0, 3) ? "是" : "否");
    printf("0 与 5 连通: %s\n", unionFindConnected(0, 5) ? "是" : "否");
    return 0;
}
