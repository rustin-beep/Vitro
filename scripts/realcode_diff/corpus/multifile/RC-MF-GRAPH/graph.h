#ifndef GRAPH_H
#define GRAPH_H

#define GRAPH_NODES 6

typedef struct {
    int node_count;
    int matrix[GRAPH_NODES][GRAPH_NODES];
    int list[GRAPH_NODES][GRAPH_NODES];
    int degree[GRAPH_NODES];
    int edges;
} Graph;

void graph_init(Graph *graph);
int graph_add_edge(Graph *graph, int from, int to);
int graph_has_edge(const Graph *graph, int from, int to);
int graph_bfs(const Graph *graph, int start, int *order, int *distance, int *discovery);
int graph_dfs(const Graph *graph, int start, int *order, int *discovery);
int graph_dijkstra(const Graph *graph, int start, int *distance, int *previous);
int graph_toposort(const Graph *graph, int *order, int *cycle);
int graph_has_cycle(const Graph *graph, int *cycle);
int graph_connected_components(const Graph *graph, int *component, int *members, int max_members);

#endif /* GRAPH_H */
