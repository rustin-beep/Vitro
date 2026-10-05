#include <stdio.h>
#include <stdlib.h>

struct ListNode {
    int val;
    struct ListNode* next;
};

struct ListNode* removeNthFromEnd(struct ListNode* head, int n) {
    struct ListNode dummy;
    dummy.next = head;
    struct ListNode* fast = &dummy;
    struct ListNode* slow = &dummy;
    for (int i = 0; i <= n; i++) {
        fast = fast->next;
    }
    while (fast != NULL) {
        fast = fast->next;
        slow = slow->next;
    }
    struct ListNode* to_delete = slow->next;
    slow->next = to_delete->next;
    free(to_delete);
    return dummy.next;
}

struct ListNode* make_node(int val) {
    struct ListNode* node = (struct ListNode*)malloc(sizeof(struct ListNode));
    node->val = val;
    node->next = NULL;
    return node;
}

void print_list(struct ListNode* head) {
    while (head != NULL) {
        printf("%d", head->val);
        if (head->next != NULL) {
            printf(" ");
        }
        head = head->next;
    }
    printf("\n");
}

void free_list(struct ListNode* head) {
    while (head != NULL) {
        struct ListNode* next = head->next;
        free(head);
        head = next;
    }
}

int main() {
    struct ListNode* h1 = make_node(1);
    h1->next = make_node(2);
    h1->next->next = make_node(3);
    h1->next->next->next = make_node(4);
    h1->next->next->next->next = make_node(5);
    h1 = removeNthFromEnd(h1, 2);
    print_list(h1);
    free_list(h1);

    struct ListNode* h2 = make_node(1);
    h2 = removeNthFromEnd(h2, 1);
    print_list(h2);
    free_list(h2);

    struct ListNode* h3 = make_node(1);
    h3->next = make_node(2);
    h3 = removeNthFromEnd(h3, 1);
    print_list(h3);
    free_list(h3);

    return 0;
}
