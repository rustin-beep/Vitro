// @category: baseline
#include <stdio.h>

void init(int parent[], int n) {
    for (int i = 0; i < n; i++) parent[i] = -1;
}

int Find(int parent[], int x) {
    if (parent[x] < 0) return x;
    return parent[x] = Find(parent, parent[x]);
}

void Union(int parent[], int x, int y) {
    int root1 = Find(parent, x);
    int root2 = Find(parent, y);
    if (root1 != root2) {
        if (parent[root1] < parent[root2]) {
            parent[root1] += parent[root2];
            parent[root2] = root1;
        } else {
            parent[root2] += parent[root1];
            parent[root1] = root2;
        }
    }
}

int main() {
    int parent[10];
    init(parent, 5);
    Union(parent, 0, 1);
    Union(parent, 2, 3);
    Union(parent, 1, 2);
    printf("%d\n", Find(parent, 3));
    return 0;
}

