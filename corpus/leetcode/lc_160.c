#include <stdio.h>
#include <stdlib.h>

struct ListNode {
    int val;
    struct ListNode* next;
};

struct ListNode* getIntersectionNode(struct ListNode* headA, struct ListNode* headB) {
    if (headA == NULL || headB == NULL) return NULL;
    struct ListNode* pA = headA;
    struct ListNode* pB = headB;
    while (pA != pB) {
        pA = (pA == NULL) ? headB : pA->next;
        pB = (pB == NULL) ? headA : pB->next;
    }
    return pA;
}

int main() {
    struct ListNode* a1 = (struct ListNode*)malloc(sizeof(struct ListNode));
    struct ListNode* a2 = (struct ListNode*)malloc(sizeof(struct ListNode));
    struct ListNode* c1 = (struct ListNode*)malloc(sizeof(struct ListNode));
    struct ListNode* c2 = (struct ListNode*)malloc(sizeof(struct ListNode));
    struct ListNode* c3 = (struct ListNode*)malloc(sizeof(struct ListNode));
    struct ListNode* b1 = (struct ListNode*)malloc(sizeof(struct ListNode));
    struct ListNode* b2 = (struct ListNode*)malloc(sizeof(struct ListNode));
    struct ListNode* b3 = (struct ListNode*)malloc(sizeof(struct ListNode));

    a1->val = 4; a1->next = a2;
    a2->val = 1; a2->next = c1;
    c1->val = 8; c1->next = c2;
    c2->val = 4; c2->next = c3;
    c3->val = 5; c3->next = NULL;
    b1->val = 5; b1->next = b2;
    b2->val = 6; b2->next = b3;
    b3->val = 1; b3->next = c1;

    struct ListNode* r = getIntersectionNode(a1, b1);
    printf("%d\n", r != NULL ? r->val : -1);

    b3->next = NULL;
    struct ListNode* r2 = getIntersectionNode(a1, b1);
    printf("%d\n", r2 != NULL ? r2->val : -1);

    free(a1); free(a2); free(c1); free(c2); free(c3); free(b1); free(b2); free(b3);
    return 0;
}
