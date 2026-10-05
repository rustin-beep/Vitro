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

struct Node* append(struct Node* head, int data) {
    struct Node* newNode = createNode(data);
    if (head == NULL) {
        newNode->next = newNode;
        return newNode;
    }
    struct Node* p = head;
    while (p->next != head) p = p->next;
    p->next = newNode;
    newNode->next = head;
    return head;
}

void printList(struct Node* head) {
    if (head == NULL) return;
    struct Node* p = head;
    do {
        printf("%d ", p->data);
        p = p->next;
    } while (p != head);
    printf("\n");
}

int main() {
    struct Node* head = NULL;
    head = append(head, 1);
    append(head, 2);
    append(head, 3);
    printList(head);
    return 0;
}

