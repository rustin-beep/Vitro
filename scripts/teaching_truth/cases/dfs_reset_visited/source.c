#include <stdio.h>

/* M34b A3 红例（DFS 侧）：visited 重置循环 + 递归 DFS。重置行放 dfsReset
   包装函数（名含 dfs——detect 命中且重置帧分派；只执行一次——重置放
   递归体内会反复清零致无限递归，首版语料实锤 8000 步跑不完）。真值：
   重置行不得产 visit 帧、真标记行节点值须为行下标变量。 */
int graph[5][5] = {
    {0, 1, 1, 0, 0},
    {1, 0, 0, 1, 1},
    {1, 0, 0, 0, 0},
    {0, 1, 0, 0, 0},
    {0, 1, 0, 0, 0}
};
int visited[5];

void dfs(int u, int n) {
    visited[u] = 1;
    printf("%d ", u);
    for (int v = 0; v < n; v++) {
        if (graph[u][v] == 1 && visited[v] == 0) {
            dfs(v, n);
        }
    }
}

void dfsReset(int start, int n) {
    for (int i = 0; i < n; i++) {
        visited[i] = 0;
    }
    dfs(start, n);
}

int main() {
    int n = 5;
    dfsReset(0, n);
    printf("\n");
    return 0;
}
