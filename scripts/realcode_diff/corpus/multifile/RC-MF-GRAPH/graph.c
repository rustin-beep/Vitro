#include "graph.h"
#include <string.h>

void graph_init(Graph *graph)
{
    memset(graph, 0, sizeof(Graph));
    graph->node_count = GRAPH_NODES;
}

int graph_has_edge(const Graph *graph, int from, int to)
{
    if (from < 0 || from >= graph->node_count || to < 0 || to >= graph->node_count) {
        return 0;
    }
    return graph->matrix[from][to];
}

int graph_add_edge(Graph *graph, int from, int to)
{
    int i;

    if (from < 0 || from >= graph->node_count || to < 0 || to >= graph->node_count) {
        return -1;
    }
    if (from == to) {
        return -2;
    }
    if (graph->matrix[from][to]) {
        return 0;
    }
    graph->matrix[from][to] = 1;
    graph->list[from][graph->degree[from]] = to;
    graph->degree[from]++;
    graph->edges++;
    for (i = 0; i < graph->node_count; i++) {
        if (i == to) {
            graph->matrix[i][from] = 1;
        }
    }
    return 1;
}

int graph_bfs(const Graph *graph, int start, int *order, int *distance, int *discovery)
{
    int queue[GRAPH_NODES];
    int visited[GRAPH_NODES];
    int head = 0;
    int tail = 0;
    int count = 0;
    int clock = 0;
    int i;

    if (start < 0 || start >= graph->node_count) {
        return -1;
    }
    for (i = 0; i < graph->node_count; i++) {
        visited[i] = 0;
        distance[i] = -1;
        discovery[i] = -1;
    }
    visited[start] = 1;
    distance[start] = 0;
    discovery[start] = clock++;
    queue[tail++] = start;
    while (head < tail) {
        int current = queue[head++];
        int neighbour;
        order[count++] = current;
        for (neighbour = 0; neighbour < graph->node_count; neighbour++) {
            if (!graph->matrix[current][neighbour] || visited[neighbour]) {
                continue;
            }
            visited[neighbour] = 1;
            distance[neighbour] = distance[current] + 1;
            discovery[neighbour] = clock++;
            queue[tail++] = neighbour;
        }
    }
    return count;
}

int graph_dfs(const Graph *graph, int start, int *order, int *discovery)
{
    int visited[GRAPH_NODES];
    int stack[GRAPH_NODES];
    int top = 0;
    int count = 0;
    int clock = 0;
    int i;

    if (start < 0 || start >= graph->node_count) {
        return -1;
    }
    for (i = 0; i < graph->node_count; i++) {
        visited[i] = 0;
        discovery[i] = -1;
    }
    stack[top++] = start;
    while (top > 0) {
        int current = stack[--top];
        int neighbour;
        if (visited[current]) {
            continue;
        }
        visited[current] = 1;
        discovery[current] = clock++;
        order[count++] = current;
        for (neighbour = graph->node_count - 1; neighbour >= 0; neighbour--) {
            if (graph->matrix[current][neighbour] && !visited[neighbour]) {
                stack[top++] = neighbour;
            }
        }
    }
    return count;
}

int graph_dijkstra(const Graph *graph, int start, int *distance, int *previous)
{
    int used[GRAPH_NODES];
    int i;
    int step;

    if (start < 0 || start >= graph->node_count) {
        return -1;
    }
    for (i = 0; i < graph->node_count; i++) {
        distance[i] = -1;
        previous[i] = -1;
        used[i] = 0;
    }
    distance[start] = 0;
    for (step = 0; step < graph->node_count; step++) {
        int best = -1;
        int best_distance = 0;
        for (i = 0; i < graph->node_count; i++) {
            if (used[i] || distance[i] < 0) {
                continue;
            }
            if (best < 0 || distance[i] < best_distance) {
                best = i;
                best_distance = distance[i];
            }
        }
        if (best < 0) {
            break;
        }
        used[best] = 1;
        for (i = 0; i < graph->node_count; i++) {
            int weight;
            if (used[i] || !graph->matrix[best][i]) {
                continue;
            }
            weight = 1;
            if (distance[best] + weight < distance[i] || distance[i] < 0) {
                distance[i] = distance[best] + weight;
                previous[i] = best;
            }
        }
    }
    return graph->node_count;
}

int graph_has_cycle(const Graph *graph, int *cycle)
{
    int order[GRAPH_NODES];
    int cycle_nodes[GRAPH_NODES];
    int count = graph_toposort(graph, order, cycle_nodes);
    int i;

    if (count < 0) {
        if (cycle != NULL) {
            for (i = 0; i < GRAPH_NODES; i++) {
                cycle[i] = cycle_nodes[i];
            }
        }
        return 1;
    }
    return 0;
}

int graph_toposort(const Graph *graph, int *order, int *cycle)
{
    int in_degree[GRAPH_NODES];
    int ready[GRAPH_NODES];
    int ready_count = 0;
    int count = 0;
    int i;
    int j;

    for (i = 0; i < graph->node_count; i++) {
        in_degree[i] = 0;
    }
    for (i = 0; i < graph->node_count; i++) {
        for (j = 0; j < graph->node_count; j++) {
            if (graph->matrix[i][j]) {
                in_degree[j]++;
            }
        }
    }
    for (i = 0; i < graph->node_count; i++) {
        if (in_degree[i] == 0) {
            ready[ready_count++] = i;
        }
    }
    while (ready_count > 0) {
        int current = ready[0];
        ready_count--;
        for (i = 1; i < ready_count; i++) {
            ready[i - 1] = ready[i];
        }
        order[count++] = current;
        for (j = 0; j < graph->node_count; j++) {
            if (!graph->matrix[current][j]) {
                continue;
            }
            in_degree[j]--;
            if (in_degree[j] == 0) {
                ready[ready_count++] = j;
            }
        }
    }
    if (count < graph->node_count) {
        int cycle_count = 0;
        for (i = 0; i < graph->node_count; i++) {
            if (in_degree[i] > 0) {
                cycle[cycle_count++] = i;
            }
        }
        return -cycle_count;
    }
    return count;
}

int graph_connected_components(const Graph *graph, int *component, int *members, int max_members)
{
    int visited[GRAPH_NODES];
    int component_count = 0;
    int member_count = 0;
    int i;
    int j;

    for (i = 0; i < graph->node_count; i++) {
        visited[i] = 0;
        component[i] = -1;
    }
    for (i = 0; i < graph->node_count; i++) {
        int queue[GRAPH_NODES];
        int head = 0;
        int tail = 0;
        if (visited[i]) {
            continue;
        }
        component_count++;
        visited[i] = 1;
        component[i] = component_count - 1;
        queue[tail++] = i;
        while (head < tail) {
            int current = queue[head++];
            if (member_count < max_members) {
                members[member_count++] = current;
            }
            for (j = 0; j < graph->node_count; j++) {
                if (graph->matrix[current][j] && !visited[j]) {
                    visited[j] = 1;
                    component[j] = component_count - 1;
                    queue[tail++] = j;
                }
            }
        }
    }
    return component_count;
}
