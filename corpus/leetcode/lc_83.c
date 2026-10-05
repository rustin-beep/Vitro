#include <stdio.h>
#include <stdlib.h>

struct ListNode {
    int val;
    struct ListNode* next;
};

struct ListNode* deleteDuplicates(struct ListNode* head) {
    struct ListNode* cur = head;
    while (cur != NULL && cur->next != NULL) {
        if (cur->val == cur->next->val) {
            struct ListNode* tmp = cur->next;
            cur->next = cur->next->next;
            free(tmp);
        } else {
            cur = cur->next;
        }
    }
    return head;
}

struct ListNode* newNode(int val, struct ListNode* next) {
    struct ListNode* n = (struct ListNode*)malloc(sizeof(struct ListNode));
    n->val = val;
    n->next = next;
    return n;
}

void printList(struct ListNode* head) {
    while (head != NULL) {
        printf("%d ", head->val);
        head = head->next;
    }
    printf("\n");
}

void freeList(struct ListNode* head) {
    while (head != NULL) {
        struct ListNode* tmp = head;
        head = head->next;
        free(tmp);
    }
}

int main(void) {
    struct ListNode* n1 = newNode(1, newNode(1, newNode(2, NULL)));
    n1 = deleteDuplicates(n1);
    printList(n1);
    freeList(n1);

    struct ListNode* n2 = newNode(1, newNode(1, newNode(2, newNode(3, newNode(3, NULL)))));
    n2 = deleteDuplicates(n2);
    printList(n2);
    freeList(n2);

    return 0;
}
