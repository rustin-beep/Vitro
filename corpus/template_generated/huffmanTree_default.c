// @category: baseline
#include <stdio.h>
#define N 5
#define M 9

typedef struct {
    int weight;
    int parent;
    int lchild;
    int rchild;
} HTNode;

void Select(HTNode HT[], int n, int* s1, int* s2) {
    int min1 = 100000, min2 = 100000;
    *s1 = *s2 = -1;
    for (int i = 0; i < n; i++) {
        if (HT[i].parent == -1 && HT[i].weight < min1) {
            min2 = min1;
            *s2 = *s1;
            min1 = HT[i].weight;
            *s1 = i;
        } else if (HT[i].parent == -1 && HT[i].weight < min2) {
            min2 = HT[i].weight;
            *s2 = i;
        }
    }
}

void CreateHuffmanTree(HTNode HT[], int w[], int n) {
    int m = 2 * n - 1;
    for (int i = 0; i < m; i++) {
        HT[i].lchild = HT[i].rchild = HT[i].parent = -1;
    }
    for (int i = 0; i < n; i++) HT[i].weight = w[i];
    for (int i = n; i < m; i++) {
        int s1, s2;
        Select(HT, i, &s1, &s2);
        HT[s1].parent = i;
        HT[s2].parent = i;
        HT[i].lchild = s1;
        HT[i].rchild = s2;
        HT[i].weight = HT[s1].weight + HT[s2].weight;
    }
}

int main() {
    int w[N] = {5, 29, 7, 8, 14};
    HTNode ht[M];
    CreateHuffmanTree(ht, w, N);
    printf("root weight=%d\n", ht[M-1].weight);
    return 0;
}

