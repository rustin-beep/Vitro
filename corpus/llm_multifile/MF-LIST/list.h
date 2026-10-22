#ifndef LIST_H
#define LIST_H

typedef struct ListNode {
    void *data;
    struct ListNode *prev;
    struct ListNode *next;
} ListNode;

typedef struct {
    ListNode *head;
    ListNode *tail;
    int size;
} List;

typedef int (*ListCmp)(const void *a, const void *b);
typedef void (*ListPrint)(const void *value);

#define LIST_OK            0
#define LIST_ERR_NULL    (-1)
#define LIST_ERR_INDEX   (-2)
#define LIST_ERR_ALLOC   (-3)

/* number of nodes released by list_destroy; defined in list.c, shared through this header */
extern int list_freed_count;

List *list_create(void);
void list_destroy(List *list);

int list_push_back(List *list, void *data);
int list_push_front(List *list, void *data);
int list_insert_at(List *list, int index, void *data);
int list_remove_at(List *list, int index);

ListNode *list_find(List *list, const void *key, ListCmp cmp);
void list_reverse(List *list);
void list_sort(List *list, ListCmp cmp);

int list_size(const List *list);
void list_print(const List *list, ListPrint printer);
void list_print_reverse(const List *list, ListPrint printer);

#endif /* LIST_H */
