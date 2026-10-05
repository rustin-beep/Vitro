// @category: baseline
#include <stdio.h>
#include <stdlib.h>

enum Color { RED, BLACK };

struct RBNode {
    int data;
    enum Color color;
    struct RBNode* left;
    struct RBNode* right;
    struct RBNode* parent;
};

struct RBNode* createNode(int data) {
    struct RBNode* node = (struct RBNode*)malloc(sizeof(struct RBNode));
    node->data = data;
    node->color = RED;
    node->left = node->right = node->parent = NULL;
    return node;
}

struct RBNode* leftRotate(struct RBNode* root, struct RBNode* x) {
    struct RBNode* y = x->right;
    x->right = y->left;
    if (y->left) y->left->parent = x;
    y->parent = x->parent;
    if (!x->parent) root = y;
    else if (x == x->parent->left) x->parent->left = y;
    else x->parent->right = y;
    y->left = x;
    x->parent = y;
    return root;
}

struct RBNode* rightRotate(struct RBNode* root, struct RBNode* y) {
    struct RBNode* x = y->left;
    y->left = x->right;
    if (x->right) x->right->parent = y;
    x->parent = y->parent;
    if (!y->parent) root = x;
    else if (y == y->parent->left) y->parent->left = x;
    else y->parent->right = x;
    x->right = y;
    y->parent = x;
    return root;
}

struct RBNode* fixInsert(struct RBNode* root, struct RBNode* z) {
    while (z->parent && z->parent->color == RED) {
        if (z->parent == z->parent->parent->left) {
            struct RBNode* y = z->parent->parent->right;
            if (y && y->color == RED) {
                z->parent->color = BLACK;
                y->color = BLACK;
                z->parent->parent->color = RED;
                z = z->parent->parent;
            } else {
                if (z == z->parent->right) {
                    z = z->parent;
                    root = leftRotate(root, z);
                }
                z->parent->color = BLACK;
                z->parent->parent->color = RED;
                root = rightRotate(root, z->parent->parent);
            }
        } else {
            struct RBNode* y = z->parent->parent->left;
            if (y && y->color == RED) {
                z->parent->color = BLACK;
                y->color = BLACK;
                z->parent->parent->color = RED;
                z = z->parent->parent;
            } else {
                if (z == z->parent->left) {
                    z = z->parent;
                    root = rightRotate(root, z);
                }
                z->parent->color = BLACK;
                z->parent->parent->color = RED;
                root = leftRotate(root, z->parent->parent);
            }
        }
    }
    root->color = BLACK;
    return root;
}

struct RBNode* insert(struct RBNode* root, int data) {
    struct RBNode* z = createNode(data);
    struct RBNode* y = NULL;
    struct RBNode* x = root;
    while (x) {
        y = x;
        if (z->data < x->data) x = x->left;
        else x = x->right;
    }
    z->parent = y;
    if (!y) root = z;
    else if (z->data < y->data) y->left = z;
    else y->right = z;
    return fixInsert(root, z);
}

void inorder(struct RBNode* root) {
    if (root) {
        inorder(root->left);
        printf("%d ", root->data);
        inorder(root->right);
    }
}

int main() {
    struct RBNode* root = NULL;
    root = insert(root, 7);
    root = insert(root, 3);
    root = insert(root, 18);
    root = insert(root, 10);
    root = insert(root, 22);
    inorder(root);
    printf("\n");
    return 0;
}

