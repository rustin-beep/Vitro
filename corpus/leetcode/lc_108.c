#include <stdio.h>
#include <stdlib.h>

struct TreeNode {
    int val;
    struct TreeNode* left;
    struct TreeNode* right;
};

struct TreeNode* build(int* nums, int left, int right) {
    if (left > right) return NULL;
    int mid = left + (right - left) / 2;
    struct TreeNode* root = (struct TreeNode*)malloc(sizeof(struct TreeNode));
    root->val = nums[mid];
    root->left = build(nums, left, mid - 1);
    root->right = build(nums, mid + 1, right);
    return root;
}

struct TreeNode* sortedArrayToBST(int* nums, int numsSize) {
    return build(nums, 0, numsSize - 1);
}

void inorder(struct TreeNode* root) {
    if (root == NULL) return;
    inorder(root->left);
    printf("%d ", root->val);
    inorder(root->right);
}

void printInorder(struct TreeNode* root) {
    inorder(root);
    printf("\n");
}

void freeTree(struct TreeNode* root) {
    if (root == NULL) return;
    freeTree(root->left);
    freeTree(root->right);
    free(root);
}

int main() {
    int nums1[] = {-10, -3, 0, 5, 9};
    struct TreeNode* root1 = sortedArrayToBST(nums1, 5);
    printInorder(root1);
    freeTree(root1);

    int nums2[] = {1, 3};
    struct TreeNode* root2 = sortedArrayToBST(nums2, 2);
    printInorder(root2);
    freeTree(root2);

    return 0;
}
