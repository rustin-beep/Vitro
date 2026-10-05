#include <stdio.h>
#include <stdlib.h>

struct ListNode {
    int val;
    struct ListNode* next;
};

struct ListNode* addTwoNumbers(struct ListNode* l1, struct ListNode* l2) {
    struct ListNode dummy;
    struct ListNode* tail = &dummy;
    dummy.next = NULL;
    int carry = 0;
    while (l1 != NULL || l2 != NULL || carry != 0) {
        int sum = carry;
        if (l1 != NULL) {
            sum += l1->val;
            l1 = l1->next;
        }
        if (l2 != NULL) {
            sum += l2->val;
            l2 = l2->next;
        }
        struct ListNode* node = (struct ListNode*)malloc(sizeof(struct ListNode));
        node->val = sum % 10;
        node->next = NULL;
        tail->next = node;
        tail = node;
        carry = sum / 10;
    }
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
    struct ListNode* a1 = make_node(2);
    a1->next = make_node(4);
    a1->next->next = make_node(3);

    struct ListNode* b1 = make_node(5);
    b1->next = make_node(6);
    b1->next->next = make_node(4);

    struct ListNode* r1 = addTwoNumbers(a1, b1);
    print_list(r1);
    free_list(a1);
    free_list(b1);
    free_list(r1);

    struct ListNode* a2 = make_node(0);
    struct ListNode* b2 = make_node(0);
    struct ListNode* r2 = addTwoNumbers(a2, b2);
    print_list(r2);
    free_list(a2);
    free_list(b2);
    free_list(r2);

    struct ListNode* a3 = make_node(9);
    a3->next = make_node(9);
    a3->next->next = make_node(9);
    a3->next->next->next = make_node(9);
    a3->next->next->next->next = make_node(9);
    a3->next->next->next->next->next = make_node(9);
    a3->next->next->next->next->next->next = make_node(9);

    struct ListNode* b3 = make_node(9);
    b3->next = make_node(9);
    b3->next->next = make_node(9);
    b3->next->next->next = make_node(9);

    struct ListNode* r3 = addTwoNumbers(a3, b3);
    print_list(r3);
    free_list(a3);
    free_list(b3);
    free_list(r3);

    return 0;
}
