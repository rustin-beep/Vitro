// @category: baseline
#include <stdio.h>
#define MAXSIZE 10

struct SeqList {
    int data[MAXSIZE];
    int length;
};

void init(struct SeqList* L) {
    L->length = 0;
}

int listInsert(struct SeqList* L, int pos, int x) {
    if (pos < 0 || pos > L->length || L->length >= MAXSIZE) return 0;
    for (int i = L->length; i > pos; i--)
        L->data[i] = L->data[i - 1];
    L->data[pos] = x;
    L->length++;
    return 1;
}

int listDelete(struct SeqList* L, int pos) {
    if (pos < 0 || pos >= L->length) return 0;
    for (int i = pos; i < L->length - 1; i++)
        L->data[i] = L->data[i + 1];
    L->length--;
    return 1;
}

int listFind(struct SeqList* L, int x) {
    for (int i = 0; i < L->length; i++) {
        if (L->data[i] == x) return i;
    }
    return -1;
}

int main() {
    struct SeqList L;
    init(&L);
    listInsert(&L, 0, 5);
    listInsert(&L, 1, 3);
    listInsert(&L, 2, 8);
    listDelete(&L, 1);
    for (int i = 0; i < L.length; i++) {
        printf("%d ", L.data[i]);
    }
    printf("\n");
    return 0;
}

