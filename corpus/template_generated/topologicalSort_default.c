// @category: baseline
#include <stdio.h>
#define MAXV 6

void TopologicalSort(int G[][MAXV], int n) {
    int indegree[MAXV] = {0};
    int queue[MAXV];
    int front = 0, rear = 0;
    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
            if (G[i][j] != 0) indegree[j]++;
        }
    }
    for (int i = 0; i < n; i++) {
        if (indegree[i] == 0) queue[rear++] = i;
    }
    while (front < rear) {
        int u = queue[front++];
        printf("%d ", u);
        for (int v = 0; v < n; v++) {
            if (G[u][v] != 0) {
                indegree[v]--;
                if (indegree[v] == 0) queue[rear++] = v;
            }
        }
    }
    printf("\n");
}

int main() {
    int G[MAXV][MAXV] = {
        {0, 1, 1, 0, 0, 0},
        {0, 0, 0, 1, 1, 0},
        {0, 0, 0, 1, 0, 0},
        {0, 0, 0, 0, 0, 1},
        {0, 0, 0, 0, 0, 1},
        {0, 0, 0, 0, 0, 0}
    };
    TopologicalSort(G, MAXV);
    return 0;
}

