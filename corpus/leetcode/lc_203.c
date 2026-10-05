#include <stdio.h>
#include <stdlib.h>

struct ListNode {
    int val;
    struct ListNode* next;
};

struct ListNode* removeElements(struct ListNode* head, int val) {
    struct ListNode dummy;
    dummy.next = head;
    struct ListNode* curr = &dummy;
    while (curr->next != NULL) {
        if (curr->next->val == val) {
            struct ListNode* tmp = curr->next;
            curr->next = curr->next->next;
            free(tmp);
        } else {
            curr = curr->next;
        }
    }
    return dummy.next;
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

struct ListNode* makeList(int* vals, int n) {
    struct ListNode dummy;
    struct ListNode* tail = &dummy;
    dummy.next = NULL;
    for (int i = 0; i < n; i++) {
        struct ListNode* node = (struct ListNode*)malloc(sizeof(struct ListNode));
        node->val = vals[i];
        node->next = NULL;
        tail->next = node;
        tail = node;
    }
    return dummy.next;
}

int main() {
    int a1[] = {1, 2, 6, 3, 4, 5, 6};
    struct ListNode* l1 = makeList(a1, 7);
    struct ListNode* r1 = removeElements(l1, 6);
    printList(r1);
    freeList(r1);

    int a2[] = {};
    struct ListNode* l2 = makeList(a2, 0);
    struct ListNode* r2 = removeElements(l2, 1);
    printList(r2);

    int a3[] = {7, 7, 7, 7};
    struct ListNode* l3 = makeList(a3, 4);
    struct ListNode* r3 = removeElements(l3, 7);
    printList(r3);

    return 0;
}
