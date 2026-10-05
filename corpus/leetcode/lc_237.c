#include <stdio.h>
#include <stdlib.h>

struct ListNode {
    int val;
    struct ListNode* next;
};

void deleteNode(struct ListNode* node) {
    node->val = node->next->val;
    struct ListNode* tmp = node->next;
    node->next = node->next->next;
    free(tmp);
}

void printList(struct ListNode* head) {
    int first = 1;
    while (head != NULL) {
        if (!first) printf(" ");
        printf("%d", head->val);
        first = 0;
        head = head->next;
    }
    printf("\n");
}

void freeList(struct ListNode* head) {
    while (head != NULL) {
        struct ListNode* next = head->next;
        free(head);
        head = next;
    }
}

int main() {
    struct ListNode* n1 = (struct ListNode*)malloc(sizeof(struct ListNode));
    struct ListNode* n2 = (struct ListNode*)malloc(sizeof(struct ListNode));
    struct ListNode* n3 = (struct ListNode*)malloc(sizeof(struct ListNode));
    struct ListNode* n4 = (struct ListNode*)malloc(sizeof(struct ListNode));
    n1->val = 4; n1->next = n2;
    n2->val = 5; n2->next = n3;
    n3->val = 1; n3->next = n4;
    n4->val = 9; n4->next = NULL;
    deleteNode(n2);
    printList(n1);
    freeList(n1);

    struct ListNode* m1 = (struct ListNode*)malloc(sizeof(struct ListNode));
    struct ListNode* m2 = (struct ListNode*)malloc(sizeof(struct ListNode));
    m1->val = 4; m1->next = m2;
    m2->val = 5; m2->next = NULL;
    deleteNode(m1);
    printList(m1);
    freeList(m1);

    return 0;
}
