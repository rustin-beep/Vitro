// @category: baseline
#include <stdio.h>

int graph[5][5] = {
    {0, 1, 1, 0, 0},
    {1, 0, 0, 1, 1},
    {1, 0, 0, 0, 0},
    {0, 1, 0, 0, 0},
    {0, 1, 0, 0, 0}
};
int visited[5] = {0, 0, 0, 0, 0};

void dfs(int u, int n) {
    visited[u] = 1;
    printf("%d ", u);
    for (int v = 0; v < n; v++) {
        if (graph[u][v] == 1 && visited[v] == 0) {
            dfs(v, n);
        }
    }
}

int main() {
    int n = 5;
    dfs(0, n);
    printf("\n");
    return 0;
}

