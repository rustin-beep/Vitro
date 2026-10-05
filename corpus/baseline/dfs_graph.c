// @category: baseline
int graph[5][5] = {{0,1,1,0,0},{1,0,0,1,1},{1,0,0,0,0},{0,1,0,0,0},{0,1,0,0,0}}; int visited[5] = {0,0,0,0,0}; void dfs(int u, int n) { visited[u] = 1; printf("%d ", u); for (int v = 0; v < n; v++) if (graph[u][v] == 1 && visited[v] == 0) dfs(v, n); } int main() { dfs(0, 5); return 0; }
