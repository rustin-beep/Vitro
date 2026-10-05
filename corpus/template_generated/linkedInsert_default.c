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

struct Node* insertFront(struct Node* head, int data) {
    struct Node* newNode = createNode(data);
    newNode->next = head;
    return newNode;
}

int main() {
    struct Node* head = NULL;
    head = insertFront(head, 3);
    head = insertFront(head, 2);
    head = insertFront(head, 1);
    printf("Head: %d\n", head->data);
    return 0;
}

