#include <stdio.h>
#include <stdlib.h>

struct ListNode {
    int val;
    struct ListNode* next;
};

struct ListNode* middleNode(struct ListNode* head) {
    struct ListNode* slow = head;
    struct ListNode* fast = head;
    while (fast != NULL && fast->next != NULL) {
        slow = slow->next;
        fast = fast->next->next;
    }
    return slow;
}

void printFrom(struct ListNode* head) {
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
    int a1[] = {1, 2, 3, 4, 5};
    struct ListNode* l1 = makeList(a1, 5);
    printFrom(middleNode(l1));
    freeList(l1);

    int a2[] = {1, 2, 3, 4, 5, 6};
    struct ListNode* l2 = makeList(a2, 6);
    printFrom(middleNode(l2));
    freeList(l2);

    return 0;
}
