// @category: baseline
#include <stdio.h>
#define MAXV 6
#define INF 65535

void CriticalPath(int G[][MAXV], int n) {
    int indegree[MAXV] = {0};
    int queue[MAXV];
    int front = 0, rear = 0;
    int ve[MAXV] = {0};
    int vl[MAXV];
    int topo[MAXV];
    int topoCount = 0;
    for (int i = 0; i < n; i++)
        for (int j = 0; j < n; j++)
            if (G[i][j] != INF && G[i][j] != 0) indegree[j]++;
    for (int i = 0; i < n; i++)
        if (indegree[i] == 0) queue[rear++] = i;
    while (front < rear) {
        int u = queue[front++];
        topo[topoCount++] = u;
        for (int v = 0; v < n; v++) {
            if (G[u][v] != INF && G[u][v] != 0) {
                if (ve[u] + G[u][v] > ve[v]) ve[v] = ve[u] + G[u][v];
                indegree[v]--;
                if (indegree[v] == 0) queue[rear++] = v;
            }
        }
    }
    for (int i = 0; i < n; i++) vl[i] = ve[topo[n - 1]];
    for (int i = n - 1; i >= 0; i--) {
        int u = topo[i];
        for (int v = 0; v < n; v++) {
            if (G[u][v] != INF && G[u][v] != 0) {
                if (vl[v] - G[u][v] < vl[u]) vl[u] = vl[v] - G[u][v];
            }
        }
    }
    for (int u = 0; u < n; u++) {
        for (int v = 0; v < n; v++) {
            if (G[u][v] != INF && G[u][v] != 0) {
                int e = ve[u];
                int l = vl[v] - G[u][v];
                if (e == l) printf("(%d,%d) ", u, v);
            }
        }
    }
    printf("\n");
}

int main() {
    int G[MAXV][MAXV] = {
        {INF, 3, 2, INF, INF, INF},
        {INF, INF, INF, 2, 3, INF},
        {INF, INF, INF, 4, INF, 3},
        {INF, INF, INF, INF, INF, 2},
        {INF, INF, INF, INF, INF, 1},
        {INF, INF, INF, INF, INF, INF}
    };
    CriticalPath(G, MAXV);
    return 0;
}

