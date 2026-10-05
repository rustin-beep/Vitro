#include <stdio.h>
#include <stdlib.h>

struct ListNode {
    int val;
    struct ListNode* next;
};

struct ListNode* mergeTwoLists(struct ListNode* list1, struct ListNode* list2) {
    struct ListNode dummy;
    struct ListNode* tail = &dummy;
    dummy.next = NULL;
    while (list1 != NULL && list2 != NULL) {
        if (list1->val < list2->val) {
            tail->next = list1;
            list1 = list1->next;
        } else {
            tail->next = list2;
            list2 = list2->next;
        }
        tail = tail->next;
    }
    tail->next = list1 != NULL ? list1 : list2;
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
    int a1[] = {1, 2, 4};
    int a2[] = {1, 3, 4};
    struct ListNode* l1 = makeList(a1, 3);
    struct ListNode* l2 = makeList(a2, 3);
    struct ListNode* r = mergeTwoLists(l1, l2);
    printList(r);
    freeList(r);

    struct ListNode* r2 = mergeTwoLists(NULL, NULL);
    printList(r2);

    int a3[] = {0};
    struct ListNode* l3 = makeList(a3, 1);
    struct ListNode* r3 = mergeTwoLists(NULL, l3);
    printList(r3);
    freeList(r3);

    return 0;
}
