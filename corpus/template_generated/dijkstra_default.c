// @category: baseline
#include <stdio.h>
#define MAXV 5
#define INF 65535

void Dijkstra(int G[][MAXV], int n, int v0) {
    int dist[MAXV];
    int visited[MAXV];
    for (int i = 0; i < n; i++) {
        dist[i] = G[v0][i];
        visited[i] = 0;
    }
    visited[v0] = 1;
    for (int i = 1; i < n; i++) {
        int min = INF;
        int u = -1;
        for (int j = 0; j < n; j++) {
            if (!visited[j] && dist[j] < min) {
                min = dist[j];
                u = j;
            }
        }
        if (u == -1) break;
        visited[u] = 1;
        for (int j = 0; j < n; j++) {
            if (!visited[j] && G[u][j] != INF && dist[u] + G[u][j] < dist[j]) {
                dist[j] = dist[u] + G[u][j];
            }
        }
    }
    for (int i = 0; i < n; i++) {
        printf("%d ", dist[i]);
    }
    printf("\n");
}

int main() {
    int G[MAXV][MAXV] = {
        {0, 2, INF, 6, INF},
        {2, 0, 3, 8, 5},
        {INF, 3, 0, INF, 7},
        {6, 8, INF, 0, 9},
        {INF, 5, 7, 9, 0}
    };
    Dijkstra(G, MAXV, 0);
    return 0;
}

