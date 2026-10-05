// @category: baseline
#include <stdio.h>
#include <stdlib.h>

struct Term {
    int coef;
    int exp;
    struct Term* next;
};

struct Term* createTerm(int c, int e) {
    struct Term* node = (struct Term*)malloc(sizeof(struct Term));
    node->coef = c;
    node->exp = e;
    node->next = NULL;
    return node;
}

struct Term* addPoly(struct Term* pa, struct Term* pb) {
    struct Term dummy;
    struct Term* tail = &dummy;
    dummy.next = NULL;
    while (pa && pb) {
        if (pa->exp > pb->exp) {
            tail->next = createTerm(pa->coef, pa->exp);
            pa = pa->next;
        } else if (pa->exp < pb->exp) {
            tail->next = createTerm(pb->coef, pb->exp);
            pb = pb->next;
        } else {
            int sum = pa->coef + pb->coef;
            if (sum != 0)
                tail->next = createTerm(sum, pa->exp);
            pa = pa->next;
            pb = pb->next;
        }
        if (tail->next) tail = tail->next;
    }
    while (pa) {
        tail->next = createTerm(pa->coef, pa->exp);
        tail = tail->next; pa = pa->next;
    }
    while (pb) {
        tail->next = createTerm(pb->coef, pb->exp);
        tail = tail->next; pb = pb->next;
    }
    return dummy.next;
}

void printPoly(struct Term* p) {
    while (p) {
        printf("%dx^%d ", p->coef, p->exp);
        p = p->next;
    }
    printf("\n");
}

int main() {
    struct Term* pa = createTerm(3, 3);
    pa->next = createTerm(2, 1);
    pa->next->next = createTerm(1, 0);
    struct Term* pb = createTerm(4, 3);
    pb->next = createTerm(-2, 1);
    struct Term* pc = addPoly(pa, pb);
    printPoly(pc);
    return 0;
}

