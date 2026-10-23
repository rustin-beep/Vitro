#include <stdio.h>
#include "graph.h"

static void print_order(const char *label, const int *order, int count)
{
    int i;

    printf("  %s:", label);
    for (i = 0; i < count; i++) {
        printf(" %d", order[i]);
    }
    printf("\n");
}

static void print_path(const char *label, const int *previous, int node)
{
    int path[GRAPH_NODES];
    int count = 0;
    int current = node;
    int i;

    while (current >= 0 && count < GRAPH_NODES) {
        path[count++] = current;
        current = previous[current];
    }
    printf("  %s:", label);
    for (i = count - 1; i >= 0; i--) {
        printf(" %d", path[i]);
    }
    printf("\n");
}

static void demo_dag(void)
{
    Graph graph;
    int order[GRAPH_NODES];
    int distance[GRAPH_NODES];
    int discovery[GRAPH_NODES];
    int previous[GRAPH_NODES];
    int cycle[GRAPH_NODES];
    int component[GRAPH_NODES];
    int members[GRAPH_NODES];
    int count;
    int i;

    graph_init(&graph);
    graph_add_edge(&graph, 0, 1);
    graph_add_edge(&graph, 0, 2);
    graph_add_edge(&graph, 1, 3);
    graph_add_edge(&graph, 2, 3);
    graph_add_edge(&graph, 3, 4);
    graph_add_edge(&graph, 4, 5);

    printf("=== acyclic graph ===\n");
    printf("  nodes=%d edges=%d degrees=%d,%d,%d,%d,%d,%d\n", graph.node_count, graph.edges,
           graph.degree[0], graph.degree[1], graph.degree[2], graph.degree[3],
           graph.degree[4], graph.degree[5]);

    count = graph_bfs(&graph, 0, order, distance, discovery);
    print_order("bfs order", order, count);
    printf("  bfs distance:");
    for (i = 0; i < graph.node_count; i++) {
        printf(" %d:%d", i, distance[i]);
    }
    printf("\n  bfs discovery time:");
    for (i = 0; i < graph.node_count; i++) {
        printf(" %d:%d", i, discovery[i]);
    }
    printf("\n");

    count = graph_dfs(&graph, 0, order, discovery);
    print_order("dfs order", order, count);
    printf("  dfs discovery time:");
    for (i = 0; i < graph.node_count; i++) {
        printf(" %d:%d", i, discovery[i]);
    }
    printf("\n");

    graph_dijkstra(&graph, 0, distance, previous);
    printf("  dijkstra distance from 0:");
    for (i = 0; i < graph.node_count; i++) {
        printf(" %d:%d", i, distance[i]);
    }
    printf("\n");
    print_path("path to 5", previous, 5);
    print_path("path to 3", previous, 3);

    count = graph_toposort(&graph, order, cycle);
    print_order("topological order", order, count);
    printf("  has_cycle=%d\n", graph_has_cycle(&graph, cycle));

    count = graph_connected_components(&graph, component, members, GRAPH_NODES);
    printf("  connected components=%d members=%d\n", count, count);
}

static void demo_cyclic(void)
{
    Graph graph;
    int order[GRAPH_NODES];
    int cycle[GRAPH_NODES];
    int component[GRAPH_NODES];
    int members[GRAPH_NODES];
    int count;
    int i;

    graph_init(&graph);
    graph_add_edge(&graph, 0, 1);
    graph_add_edge(&graph, 1, 2);
    graph_add_edge(&graph, 2, 3);
    graph_add_edge(&graph, 3, 1);
    graph_add_edge(&graph, 3, 4);
    graph_add_edge(&graph, 4, 5);

    printf("=== graph with a cycle ===\n");
    printf("  nodes=%d edges=%d\n", graph.node_count, graph.edges);
    count = graph_toposort(&graph, order, cycle);
    if (count < 0) {
        printf("  CYCLE detected with %d nodes:", -count);
        for (i = 0; i < -count; i++) {
            printf(" %d", cycle[i]);
        }
        printf("\n");
    } else {
        print_order("topological order", order, count);
    }
    printf("  has_cycle=%d\n", graph_has_cycle(&graph, cycle));
    count = graph_connected_components(&graph, component, members, GRAPH_NODES);
    printf("  connected components=%d\n", count);
    for (i = 0; i < count; i++) {
        int k;
        printf("    component %d:", i);
        for (k = 0; k < count; k++) {
            if (component[members[k]] == i) {
                printf(" %d", members[k]);
            }
        }
        printf("\n");
    }
}

int main(void)
{
    demo_dag();
    demo_cyclic();
    printf("=== done ===\n");
    return 0;
}
