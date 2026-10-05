// @category: baseline
#include <stdio.h>
#include <stdlib.h>

struct Node {
    int data;
    struct Node* next;
};

struct Node* createNode(int data) {
    struct Node* node = (struct Node*)malloc(sizeof(struct Node));
    node->data = data;
    node->next = NULL;
    return node;
}

struct Node* merge(struct Node* L1, struct Node* L2) {
    struct Node dummy;
    struct Node* tail = &dummy;
    dummy.next = NULL;
    while (L1 != NULL && L2 != NULL) {
        if (L1->data <= L2->data) {
            tail->next = L1;
            L1 = L1->next;
        } else {
            tail->next = L2;
            L2 = L2->next;
        }
        tail = tail->next;
    }
    if (L1 != NULL) tail->next = L1;
    if (L2 != NULL) tail->next = L2;
    return dummy.next;
}

void printList(struct Node* head) {
    struct Node* p = head;
    while (p != NULL) {
        printf("%d ", p->data);
        p = p->next;
    }
    printf("\n");
}

int main() {
    struct Node* L1 = createNode(1);
    L1->next = createNode(3);
    L1->next->next = createNode(5);
    struct Node* L2 = createNode(2);
    L2->next = createNode(4);
    L2->next->next = createNode(6);
    struct Node* L3 = merge(L1, L2);
    printList(L3);
    return 0;
}

