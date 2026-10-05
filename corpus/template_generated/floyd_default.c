// @category: baseline
#include <stdio.h>
#define MAXV 4
#define INF 65535

void Floyd(int G[][MAXV], int n) {
    for (int k = 0; k < n; k++) {
        for (int i = 0; i < n; i++) {
            for (int j = 0; j < n; j++) {
                if (G[i][k] + G[k][j] < G[i][j]) {
                    G[i][j] = G[i][k] + G[k][j];
                }
            }
        }
    }
    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
            if (G[i][j] == INF) printf("INF ");
            else printf("%d ", G[i][j]);
        }
        printf("\n");
    }
}

int main() {
    int G[MAXV][MAXV] = {
        {0, 2, 6, INF},
        {INF, 0, 3, INF},
        {INF, INF, 0, 1},
        {INF, INF, INF, 0}
    };
    Floyd(G, MAXV);
    return 0;
}

