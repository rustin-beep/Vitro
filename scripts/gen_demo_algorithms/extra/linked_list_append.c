#include <stdio.h>
#include <stdlib.h>

struct Node {
    int data;
    struct Node* next;
};

struct Node* appendNode(struct Node* head, int data) {
    struct Node* n = (struct Node*)malloc(sizeof(struct Node));
    n->data = data;
    n->next = NULL;
    if (head == NULL) return n;
    struct Node* p = head;
    while (p->next != NULL) p = p->next;
    p->next = n;
    return head;
}

int main() {
    struct Node* h = NULL;
    h = appendNode(h, 1);
    h = appendNode(h, 2);
    h = appendNode(h, 3);
    printf("%d %d %d\n", h->data, h->next->data, h->next->next->data);
    return 0;
}
