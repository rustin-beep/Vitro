#include <stdio.h>

int canFinish(int numCourses, int* prerequisites, int prerequisitesSize, int* prerequisitesColSize) {
    int in_degree[100] = {0};
    int adj[100][100];
    int adj_count[100] = {0};

    for (int i = 0; i < prerequisitesSize; i++) {
        int course = prerequisites[i * 2];
        int pre = prerequisites[i * 2 + 1];
        adj[pre][adj_count[pre]++] = course;
        in_degree[course]++;
    }

    int queue[100];
    int front = 0, rear = 0;
    for (int i = 0; i < numCourses; i++) {
        if (in_degree[i] == 0) {
            queue[rear++] = i;
        }
    }

    int visited = 0;
    while (front < rear) {
        int node = queue[front++];
        visited++;
        for (int i = 0; i < adj_count[node]; i++) {
            int next = adj[node][i];
            in_degree[next]--;
            if (in_degree[next] == 0) {
                queue[rear++] = next;
            }
        }
    }

    return visited == numCourses;
}

int main() {
    int p1[] = {1, 0};
    int col1[] = {2};
    printf("%d\n", canFinish(2, p1, 1, col1));

    int p2[] = {1, 0, 0, 1};
    int col2[] = {2};
    printf("%d\n", canFinish(2, p2, 2, col2));

    int p3[] = {1, 4, 2, 4, 3, 1, 3, 2};
    int col3[] = {2};
    printf("%d\n", canFinish(5, p3, 4, col3));

    return 0;
}
