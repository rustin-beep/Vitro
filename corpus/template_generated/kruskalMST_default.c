// @category: baseline
#include <stdio.h>
#define MAXE 10
#define MAXV 5

typedef struct {
    int u;
    int v;
    int w;
} Edge;

int Find(int parent[], int x) {
    if (parent[x] != x) parent[x] = Find(parent, parent[x]);
    return parent[x];
}

void Union(int parent[], int x, int y) {
    parent[Find(parent, x)] = Find(parent, y);
}

void Kruskal(Edge edges[], int n, int e) {
    int parent[MAXV];
    for (int i = 0; i < n; i++) parent[i] = i;
    for (int i = 0; i < e - 1; i++) {
        int min = i;
        for (int j = i + 1; j < e; j++) {
            if (edges[j].w < edges[min].w) min = j;
        }
        if (min != i) {
            Edge tmp = edges[i];
            edges[i] = edges[min];
            edges[min] = tmp;
        }
    }
    for (int i = 0; i < e; i++) {
        int u = edges[i].u;
        int v = edges[i].v;
        if (Find(parent, u) != Find(parent, v)) {
            printf("(%d,%d)=%d\n", u, v, edges[i].w);
            Union(parent, u, v);
        }
    }
}

int main() {
    Edge edges[MAXE] = {
        {0, 1, 2}, {0, 3, 6}, {1, 2, 3},
        {1, 3, 8}, {1, 4, 5}, {2, 4, 7},
        {3, 4, 9}
    };
    Kruskal(edges, MAXV, 7);
    return 0;
}

