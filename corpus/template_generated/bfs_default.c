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
int queue[5];
int front = 0, rear = 0;

void bfs(int start, int n) {
    visited[start] = 1;
    queue[rear++] = start;
    while (front < rear) {
        int u = queue[front++];
        printf("%d ", u);
        for (int v = 0; v < n; v++) {
            if (graph[u][v] == 1 && visited[v] == 0) {
                visited[v] = 1;
                queue[rear++] = v;
            }
        }
    }
}

int main() {
    int n = 5;
    bfs(0, n);
    printf("\n");
    return 0;
}

