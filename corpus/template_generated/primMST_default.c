// @category: baseline
#include <stdio.h>
#define MAXV 5
#define INF 65535

void Prim(int G[][MAXV], int n) {
    int lowcost[MAXV];
    int adjvex[MAXV];
    lowcost[0] = 0;
    adjvex[0] = 0;
    for (int i = 1; i < n; i++) {
        lowcost[i] = G[0][i];
        adjvex[i] = 0;
    }
    for (int i = 1; i < n; i++) {
        int min = INF;
        int k = 0;
        for (int j = 1; j < n; j++) {
            if (lowcost[j] != 0 && lowcost[j] < min) {
                min = lowcost[j];
                k = j;
            }
        }
        printf("(%d,%d)=%d\n", adjvex[k], k, min);
        lowcost[k] = 0;
        for (int j = 1; j < n; j++) {
            if (lowcost[j] != 0 && G[k][j] < lowcost[j]) {
                lowcost[j] = G[k][j];
                adjvex[j] = k;
            }
        }
    }
}

int main() {
    int G[MAXV][MAXV] = {
        {0, 2, INF, 6, INF},
        {2, 0, 3, 8, 5},
        {INF, 3, 0, INF, 7},
        {6, 8, INF, 0, 9},
        {INF, 5, 7, 9, 0}
    };
    Prim(G, MAXV);
    return 0;
}

