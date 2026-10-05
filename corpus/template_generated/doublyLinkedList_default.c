// @category: baseline
#include <stdio.h>
#include <stdlib.h>

struct DNode {
    int data;
    struct DNode* prev;
    struct DNode* next;
};

struct DNode* createNode(int data) {
    struct DNode* node = (struct DNode*)malloc(sizeof(struct DNode));
    node->data = data;
    node->prev = NULL;
    node->next = NULL;
    return node;
}

struct DNode* append(struct DNode* head, int data) {
    struct DNode* newNode = createNode(data);
    if (head == NULL) return newNode;
    struct DNode* p = head;
    while (p->next != NULL) p = p->next;
    p->next = newNode;
    newNode->prev = p;
    return head;
}

void printForward(struct DNode* head) {
    struct DNode* p = head;
    while (p != NULL) {
        printf("%d ", p->data);
        p = p->next;
    }
    printf("\n");
}

int main() {
    struct DNode* head = NULL;
    head = append(head, 1);
    head = append(head, 2);
    head = append(head, 3);
    printForward(head);
    return 0;
}

