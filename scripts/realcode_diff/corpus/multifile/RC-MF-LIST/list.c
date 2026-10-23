#include "list.h"
#include <stdio.h>
#include <stdlib.h>

int list_freed_count = 0;

static ListNode *node_create(void *data)
{
    ListNode *node = (ListNode *)malloc(sizeof(ListNode));
    if (node == NULL) {
        return NULL;
    }
    node->data = data;
    node->prev = NULL;
    node->next = NULL;
    return node;
}

List *list_create(void)
{
    List *list = (List *)malloc(sizeof(List));
    if (list == NULL) {
        return NULL;
    }
    list->head = NULL;
    list->tail = NULL;
    list->size = 0;
    return list;
}

void list_destroy(List *list)
{
    ListNode *cur;

    if (list == NULL) {
        return;
    }
    cur = list->head;
    while (cur != NULL) {
        ListNode *next = cur->next;
        free(cur);
        list_freed_count++;
        cur = next;
    }
    free(list);
}

int list_push_back(List *list, void *data)
{
    ListNode *node;

    if (list == NULL) {
        return LIST_ERR_NULL;
    }
    node = node_create(data);
    if (node == NULL) {
        return LIST_ERR_ALLOC;
    }
    node->prev = list->tail;
    if (list->tail != NULL) {
        list->tail->next = node;
    } else {
        list->head = node;
    }
    list->tail = node;
    list->size++;
    return LIST_OK;
}

int list_push_front(List *list, void *data)
{
    ListNode *node;

    if (list == NULL) {
        return LIST_ERR_NULL;
    }
    node = node_create(data);
    if (node == NULL) {
        return LIST_ERR_ALLOC;
    }
    node->next = list->head;
    if (list->head != NULL) {
        list->head->prev = node;
    } else {
        list->tail = node;
    }
    list->head = node;
    list->size++;
    return LIST_OK;
}

int list_insert_at(List *list, int index, void *data)
{
    ListNode *node;
    ListNode *cur;
    int i;

    if (list == NULL) {
        return LIST_ERR_NULL;
    }
    if (index < 0 || index > list->size) {
        return LIST_ERR_INDEX;
    }
    if (index == 0) {
        return list_push_front(list, data);
    }
    if (index == list->size) {
        return list_push_back(list, data);
    }
    node = node_create(data);
    if (node == NULL) {
        return LIST_ERR_ALLOC;
    }
    cur = list->head;
    for (i = 0; i < index - 1; i++) {
        cur = cur->next;
    }
    node->prev = cur;
    node->next = cur->next;
    cur->next->prev = node;
    cur->next = node;
    list->size++;
    return LIST_OK;
}

int list_remove_at(List *list, int index)
{
    ListNode *cur;
    int i;

    if (list == NULL) {
        return LIST_ERR_NULL;
    }
    if (index < 0 || index >= list->size) {
        return LIST_ERR_INDEX;
    }
    cur = list->head;
    for (i = 0; i < index; i++) {
        cur = cur->next;
    }
    if (cur->prev != NULL) {
        cur->prev->next = cur->next;
    } else {
        list->head = cur->next;
    }
    if (cur->next != NULL) {
        cur->next->prev = cur->prev;
    } else {
        list->tail = cur->prev;
    }
    free(cur);
    list_freed_count++;
    list->size--;
    return LIST_OK;
}

ListNode *list_find(List *list, const void *key, ListCmp cmp)
{
    ListNode *cur;

    if (list == NULL || cmp == NULL) {
        return NULL;
    }
    cur = list->head;
    while (cur != NULL) {
        if (cmp(cur->data, key) == 0) {
            return cur;
        }
        cur = cur->next;
    }
    return NULL;
}

void list_reverse(List *list)
{
    ListNode *cur;

    if (list == NULL) {
        return;
    }
    cur = list->head;
    while (cur != NULL) {
        ListNode *tmp = cur->next;
        cur->next = cur->prev;
        cur->prev = tmp;
        cur = tmp;
    }
    {
        ListNode *new_head = list->tail;
        ListNode *new_tail = list->head;
        list->head = new_head;
        list->tail = new_tail;
    }
}

static ListNode *list_split(ListNode *head)
{
    ListNode *slow = head;
    ListNode *fast = head->next;

    while (fast != NULL && fast->next != NULL) {
        slow = slow->next;
        fast = fast->next->next;
    }
    {
        ListNode *second = slow->next;
        slow->next = NULL;
        return second;
    }
}

static ListNode *list_merge(ListNode *a, ListNode *b, ListCmp cmp)
{
    ListNode dummy;
    ListNode *tail;

    dummy.data = NULL;
    dummy.prev = NULL;
    dummy.next = NULL;
    tail = &dummy;
    while (a != NULL && b != NULL) {
        if (cmp(a->data, b->data) <= 0) {
            tail->next = a;
            a = a->next;
        } else {
            tail->next = b;
            b = b->next;
        }
        tail = tail->next;
    }
    tail->next = (a != NULL) ? a : b;
    return dummy.next;
}

static ListNode *list_msort(ListNode *head, ListCmp cmp)
{
    ListNode *mid;
    ListNode *left;
    ListNode *right;

    if (head == NULL || head->next == NULL) {
        return head;
    }
    mid = list_split(head);
    left = list_msort(head, cmp);
    right = list_msort(mid, cmp);
    return list_merge(left, right, cmp);
}

void list_sort(List *list, ListCmp cmp)
{
    ListNode *prev;
    ListNode *cur;

    if (list == NULL || cmp == NULL) {
        return;
    }
    if (list->head == NULL || list->size < 2) {
        return;
    }
    list->head = list_msort(list->head, cmp);
    prev = NULL;
    cur = list->head;
    while (cur != NULL) {
        cur->prev = prev;
        prev = cur;
        cur = cur->next;
    }
    list->tail = prev;
}

int list_size(const List *list)
{
    if (list == NULL) {
        return LIST_ERR_NULL;
    }
    return list->size;
}

void list_print(const List *list, ListPrint printer)
{
    const ListNode *cur;
    int i;

    if (list == NULL) {
        return;
    }
    i = 0;
    cur = list->head;
    while (cur != NULL) {
        printf("  [%d] ", i);
        if (printer != NULL) {
            printer(cur->data);
        }
        cur = cur->next;
        i++;
    }
}

void list_print_reverse(const List *list, ListPrint printer)
{
    const ListNode *cur;
    int i;

    if (list == NULL) {
        return;
    }
    i = list->size - 1;
    cur = list->tail;
    while (cur != NULL) {
        printf("  [%d] ", i);
        if (printer != NULL) {
            printer(cur->data);
        }
        cur = cur->prev;
        i--;
    }
}
