// @category: baseline
#include <stdio.h>
#include <stdlib.h>

struct AVLNode {
    int data;
    struct AVLNode* lchild;
    struct AVLNode* rchild;
    int bf;
};

struct AVLNode* createNode(int data) {
    struct AVLNode* node = (struct AVLNode*)malloc(sizeof(struct AVLNode));
    node->data = data;
    node->lchild = NULL;
    node->rchild = NULL;
    node->bf = 0;
    return node;
}

void R_Rotate(struct AVLNode** p) {
    struct AVLNode* lc = (*p)->lchild;
    (*p)->lchild = lc->rchild;
    lc->rchild = *p;
    *p = lc;
}

void L_Rotate(struct AVLNode** p) {
    struct AVLNode* rc = (*p)->rchild;
    (*p)->rchild = rc->lchild;
    rc->lchild = *p;
    *p = rc;
}

void LeftBalance(struct AVLNode** T) {
    struct AVLNode* lc = (*T)->lchild;
    switch (lc->bf) {
        case 1:
            (*T)->bf = lc->bf = 0;
            R_Rotate(T);
            break;
        case -1: {
            struct AVLNode* rd = lc->rchild;
            switch (rd->bf) {
                case 1: (*T)->bf = -1; lc->bf = 0; break;
                case 0: (*T)->bf = lc->bf = 0; break;
                case -1: (*T)->bf = 0; lc->bf = 1; break;
            }
            rd->bf = 0;
            L_Rotate(&((*T)->lchild));
            R_Rotate(T);
            break;
        }
    }
}

void RightBalance(struct AVLNode** T) {
    struct AVLNode* rc = (*T)->rchild;
    switch (rc->bf) {
        case -1:
            (*T)->bf = rc->bf = 0;
            L_Rotate(T);
            break;
        case 1: {
            struct AVLNode* ld = rc->lchild;
            switch (ld->bf) {
                case 1: (*T)->bf = 0; rc->bf = -1; break;
                case 0: (*T)->bf = rc->bf = 0; break;
                case -1: (*T)->bf = 1; rc->bf = 0; break;
            }
            ld->bf = 0;
            R_Rotate(&((*T)->rchild));
            L_Rotate(T);
            break;
        }
    }
}

int InsertAVL(struct AVLNode** T, int e) {
    if (*T == NULL) {
        *T = createNode(e);
        return 1;
    }
    if (e == (*T)->data) return 0;
    else if (e < (*T)->data) {
        if (!InsertAVL(&((*T)->lchild), e)) return 0;
        switch ((*T)->bf) {
            case 1: LeftBalance(T); break;
            case 0: (*T)->bf = 1; break;
            case -1: (*T)->bf = 0; break;
        }
    } else {
        if (!InsertAVL(&((*T)->rchild), e)) return 0;
        switch ((*T)->bf) {
            case -1: RightBalance(T); break;
            case 0: (*T)->bf = -1; break;
            case 1: (*T)->bf = 0; break;
        }
    }
    return 1;
}

void inorder(struct AVLNode* T) {
    if (T) {
        inorder(T->lchild);
        printf("%d ", T->data);
        inorder(T->rchild);
    }
}

int main() {
    struct AVLNode* T = NULL;
    InsertAVL(&T, 3);
    InsertAVL(&T, 2);
    InsertAVL(&T, 1);
    InsertAVL(&T, 4);
    InsertAVL(&T, 5);
    inorder(T);
    printf("\n");
    return 0;
}

