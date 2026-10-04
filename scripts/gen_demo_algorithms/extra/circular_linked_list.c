#include <stdio.h>
#include <stdlib.h>

struct Node {
    int data;
    struct Node* next;
};

struct Node* insertCircularList(struct Node* tail, int data) {
    struct Node* n = (struct Node*)malloc(sizeof(struct Node));
    n->data = data;
    if (tail == NULL) {
        n->next = n;
        return n;
    }
    n->next = tail->next;
    tail->next = n;
    return n;
}

void printCircularList(struct Node* tail) {
    if (tail == NULL) return;
    struct Node* p = tail->next;
    do {
        printf("%d ", p->data);
        p = p->next;
    } while (p != tail->next);
    printf("\n");
}

int main() {
    struct Node* tail = NULL;
    tail = insertCircularList(tail, 1);
    tail = insertCircularList(tail, 2);
    tail = insertCircularList(tail, 3);
    printCircularList(tail);
    return 0;
}
