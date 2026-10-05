#include <stdio.h>
#include <stdlib.h>

struct ListNode {
    int val;
    struct ListNode* next;
};

struct ListNode* reverse(struct ListNode* head) {
    struct ListNode* prev = NULL;
    struct ListNode* curr = head;
    while (curr != NULL) {
        struct ListNode* next = curr->next;
        curr->next = prev;
        prev = curr;
        curr = next;
    }
    return prev;
}

int isPalindrome(struct ListNode* head) {
    if (head == NULL || head->next == NULL) return 1;
    struct ListNode* slow = head;
    struct ListNode* fast = head;
    while (fast->next != NULL && fast->next->next != NULL) {
        slow = slow->next;
        fast = fast->next->next;
    }
    struct ListNode* second = reverse(slow->next);
    struct ListNode* p1 = head;
    struct ListNode* p2 = second;
    int result = 1;
    while (p2 != NULL) {
        if (p1->val != p2->val) {
            result = 0;
            break;
        }
        p1 = p1->next;
        p2 = p2->next;
    }
    slow->next = reverse(second);
    return result;
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
    int a1[] = {1, 2, 2, 1};
    struct ListNode* l1 = makeList(a1, 4);
    printf("%d\n", isPalindrome(l1));
    freeList(l1);

    int a2[] = {1, 2};
    struct ListNode* l2 = makeList(a2, 2);
    printf("%d\n", isPalindrome(l2));
    freeList(l2);

    int a3[] = {1, 2, 3, 2, 1};
    struct ListNode* l3 = makeList(a3, 5);
    printf("%d\n", isPalindrome(l3));
    freeList(l3);

    return 0;
}
