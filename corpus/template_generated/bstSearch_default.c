// @category: baseline
#include <stdio.h>
#include <stdlib.h>

struct TreeNode {
    int val;
    struct TreeNode* left;
    struct TreeNode* right;
};

struct TreeNode* createNode(int val) {
    struct TreeNode* node = (struct TreeNode*)malloc(sizeof(struct TreeNode));
    node->val = val;
    node->left = NULL;
    node->right = NULL;
    return node;
}

struct TreeNode* insert(struct TreeNode* root, int val) {
    if (root == NULL) return createNode(val);
    if (val < root->val)
        root->left = insert(root->left, val);
    else
        root->right = insert(root->right, val);
    return root;
}

struct TreeNode* search(struct TreeNode* root, int key) {
    if (root == NULL || root->val == key) return root;
    if (key < root->val)
        return search(root->left, key);
    else
        return search(root->right, key);
}

int main() {
    struct TreeNode* root = NULL;
    root = insert(root, 5);
    insert(root, 3);
    insert(root, 7);
    insert(root, 1);
    insert(root, 9);
    struct TreeNode* res = search(root, 7);
    if (res != NULL)
        printf("Found %d\n", res->val);
    else
        printf("Not found\n");
    return 0;
}

