#include <stdio.h>
#include <stdlib.h>

struct TreeNode {
    int val;
    struct TreeNode* left;
    struct TreeNode* right;
};

int hasPathSum(struct TreeNode* root, int targetSum) {
    if (root == NULL) return 0;
    if (root->left == NULL && root->right == NULL) {
        return root->val == targetSum;
    }
    int remain = targetSum - root->val;
    return hasPathSum(root->left, remain) || hasPathSum(root->right, remain);
}

struct TreeNode* newNode(int val) {
    struct TreeNode* n = (struct TreeNode*)malloc(sizeof(struct TreeNode));
    n->val = val;
    n->left = NULL;
    n->right = NULL;
    return n;
}

void freeTree(struct TreeNode* root) {
    if (root == NULL) return;
    freeTree(root->left);
    freeTree(root->right);
    free(root);
}

int main() {
    struct TreeNode* root = newNode(5);
    root->left = newNode(4);
    root->right = newNode(8);
    root->left->left = newNode(11);
    root->right->left = newNode(13);
    root->right->right = newNode(4);
    root->left->left->left = newNode(7);
    root->left->left->right = newNode(2);
    root->right->right->right = newNode(1);
    printf("%d\n", hasPathSum(root, 22));
    printf("%d\n", hasPathSum(root, 5));
    freeTree(root);

    root = newNode(1);
    root->left = newNode(2);
    root->right = newNode(3);
    printf("%d\n", hasPathSum(root, 5));
    freeTree(root);

    printf("%d\n", hasPathSum(NULL, 0));

    return 0;
}
