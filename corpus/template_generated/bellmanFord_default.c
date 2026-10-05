// @category: baseline
#include <stdio.h>
#define MAXV 5
#define INF 65535

struct Edge {
    int u, v, w;
};

void BellmanFord(struct Edge edges[], int e, int n, int v0) {
    int dist[MAXV];
    for (int i = 0; i < n; i++) dist[i] = INF;
    dist[v0] = 0;
    for (int i = 1; i < n; i++) {
        for (int j = 0; j < e; j++) {
            int u = edges[j].u, v = edges[j].v, w = edges[j].w;
            if (dist[u] != INF && dist[u] + w < dist[v])
                dist[v] = dist[u] + w;
        }
    }
    for (int j = 0; j < e; j++) {
        int u = edges[j].u, v = edges[j].v, w = edges[j].w;
        if (dist[u] != INF && dist[u] + w < dist[v]) {
            printf("negative cycle\n");
            return;
        }
    }
    for (int i = 0; i < n; i++) printf("%d ", dist[i]);
    printf("\n");
}

int main() {
    struct Edge edges[] = {
        {0, 1, -1}, {0, 2, 4}, {1, 2, 3}, {1, 3, 2},
        {1, 4, 2}, {3, 2, 5}, {3, 1, 1}, {4, 3, -3}
    };
    BellmanFord(edges, 8, 5, 0);
    return 0;
}

