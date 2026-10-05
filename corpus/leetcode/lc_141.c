#include <stdio.h>
#include <stdlib.h>

struct ListNode {
    int val;
    struct ListNode* next;
};

int hasCycle(struct ListNode* head) {
    if (head == NULL || head->next == NULL) return 0;
    struct ListNode* slow = head;
    struct ListNode* fast = head->next;
    while (fast != NULL && fast->next != NULL) {
        if (slow == fast) return 1;
        slow = slow->next;
        fast = fast->next->next;
    }
    return 0;
}

int main() {
    struct ListNode* n1 = (struct ListNode*)malloc(sizeof(struct ListNode));
    struct ListNode* n2 = (struct ListNode*)malloc(sizeof(struct ListNode));
    struct ListNode* n3 = (struct ListNode*)malloc(sizeof(struct ListNode));
    struct ListNode* n4 = (struct ListNode*)malloc(sizeof(struct ListNode));
    n1->val = 3; n1->next = n2;
    n2->val = 2; n2->next = n3;
    n3->val = 0; n3->next = n4;
    n4->val = -4; n4->next = n2;
    printf("%d\n", hasCycle(n1));
    n4->next = NULL;
    printf("%d\n", hasCycle(n1));

    n1->val = 1; n1->next = n2;
    n2->val = 2; n2->next = n1;
    printf("%d\n", hasCycle(n1));
    n2->next = NULL;

    n1->val = 1; n1->next = NULL;
    printf("%d\n", hasCycle(n1));

    free(n1); free(n2); free(n3); free(n4);
    return 0;
}
