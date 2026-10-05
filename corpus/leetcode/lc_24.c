#include <stdio.h>
#include <stdlib.h>

struct ListNode {
    int val;
    struct ListNode* next;
};

struct ListNode* swapPairs(struct ListNode* head) {
    struct ListNode dummy;
    dummy.next = head;
    struct ListNode* prev = &dummy;
    while (prev->next && prev->next->next) {
        struct ListNode* first = prev->next;
        struct ListNode* second = first->next;
        prev->next = second;
        first->next = second->next;
        second->next = first;
        prev = first;
    }
    return dummy.next;
}

struct ListNode* newNode(int val) {
    struct ListNode* n = (struct ListNode*)malloc(sizeof(struct ListNode));
    n->val = val;
    n->next = 0;
    return n;
}

void printList(struct ListNode* h) {
    while (h) {
        printf("%d", h->val);
        if (h->next) printf("->");
        h = h->next;
    }
    printf("\n");
}

int main() {
    struct ListNode* a = newNode(1);
    a->next = newNode(2);
    a->next->next = newNode(3);
    a->next->next->next = newNode(4);
    struct ListNode* r = swapPairs(a);
    printList(r);
    return 0;
}
