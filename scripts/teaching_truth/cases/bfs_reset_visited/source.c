#include <stdio.h>

/* BFS 带 visited 重置循环（M34b A3 红例载体）：`visited[i] = 0;` 重置行
   命中宽判据 contains("visited") && contains("=")，变量 u 取不到时哨兵 -1
   直拼进文案「标记节点 -1 为已访问」。真值：该行下标 = i 的当前值。 */
int graph[5][5] = {
    {0, 1, 1, 0, 0},
    {1, 0, 0, 1, 1},
    {1, 0, 0, 0, 0},
    {0, 1, 0, 0, 0},
    {0, 1, 0, 0, 0}
};
int visited[5];
int queue[5];
int front = 0, rear = 0;

void bfs(int start, int n) {
    for (int i = 0; i < n; i++) {
        visited[i] = 0;
    }
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
