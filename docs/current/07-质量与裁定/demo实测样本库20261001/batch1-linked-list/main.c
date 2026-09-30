#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define NAME_LEN 32

/* ---------- 数据结构 ---------- */
typedef struct Student {
    int    id;
    char   name[NAME_LEN];
    float  score;
    struct Student *next;
} Student;

/* ---------- 创建节点 ---------- */
static Student *create_node(int id, const char *name, float score)
{
    Student *node = (Student *)malloc(sizeof(Student));
    if (node == NULL) {
        fprintf(stderr, "内存分配失败\n");
        exit(EXIT_FAILURE);
    }
    node->id = id;
    strncpy(node->name, name, NAME_LEN - 1);
    node->name[NAME_LEN - 1] = '\0';
    node->score = score;
    node->next  = NULL;
    return node;
}

/* ---------- 头插法插入 ---------- */
static void insert(Student **head, int id, const char *name, float score)
{
    Student *node = create_node(id, name, score);
    node->next = *head;
    *head = node;
}

/* ---------- 按学号删除，返回 1 成功 / 0 未找到 ---------- */
static int remove_by_id(Student **head, int id)
{
    Student *cur = *head, *prev = NULL;

    while (cur != NULL && cur->id != id) {
        prev = cur;
        cur  = cur->next;
    }
    if (cur == NULL)
        return 0;                 /* 没找到 */

    if (prev == NULL)
        *head = cur->next;        /* 删的是头节点 */
    else
        prev->next = cur->next;

    free(cur);
    return 1;
}

/* ---------- 按学号查找 ---------- */
static Student *find_by_id(Student *head, int id)
{
    Student *p;
    for (p = head; p != NULL; p = p->next)
        if (p->id == id)
            return p;
    return NULL;
}

/* ---------- 按成绩从高到低排序（交换节点内容） ---------- */
static void sort_by_score(Student *head)
{
    Student *i, *j;
    for (i = head; i != NULL; i = i->next) {
        for (j = i->next; j != NULL; j = j->next) {
            if (j->score > i->score) {
                int   tid = i->id;   i->id    = j->id;    j->id    = tid;
                float ts  = i->score;i->score = j->score; j->score = ts;

                char tn[NAME_LEN];
                strcpy(tn, i->name);
                strcpy(i->name, j->name);
                strcpy(j->name, tn);
            }
        }
    }
}

/* ---------- 打印全部 ---------- */
static void print_list(const Student *head)
{
    const Student *p;
    printf("%-8s %-16s %-6s\n", "学号", "姓名", "成绩");
    printf("------------------------------------\n");
    for (p = head; p != NULL; p = p->next)
        printf("%-8d %-16s %-6.1f\n", p->id, p->name, p->score);
    printf("------------------------------------\n");
}

/* ---------- 释放整条链表 ---------- */
static void free_list(Student **head)
{
    Student *p = *head;
    while (p != NULL) {
        Student *next = p->next;
        free(p);
        p = next;
    }
    *head = NULL;
}

/* ---------- 主函数演示 ---------- */
int main(void)
{
    Student *list = NULL;

    insert(&list, 1003, "王小明", 88.5f);
    insert(&list, 1001, "李雷",   92.0f);
    insert(&list, 1004, "韩梅梅", 76.5f);
    insert(&list, 1002, "张三",   59.0f);

    printf(">>> 原始数据\n");
    print_list(list);

    printf("\n>>> 查找学号 1004\n");
    Student *s = find_by_id(list, 1004);
    if (s != NULL)
        printf("找到: %d %s %.1f\n", s->id, s->name, s->score);
    else
        printf("未找到\n");

    printf("\n>>> 删除学号 1003\n");
    if (remove_by_id(&list, 1003))
        printf("删除成功\n");
    else
        printf("删除失败：学号不存在\n");

    printf("\n>>> 按成绩降序排列\n");
    sort_by_score(list);
    print_list(list);

    free_list(&list);
    return 0;
}
