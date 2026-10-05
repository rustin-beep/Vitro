#include <stdio.h>

struct TreeNode {
    int val;
    struct TreeNode *left;
    struct TreeNode *right;
};

int sumOfLeftLeaves(struct TreeNode* root) {
    if (root == NULL) return 0;
    int sum = 0;
    if (root->left != NULL && root->left->left == NULL && root->left->right == NULL) {
        sum += root->left->val;
    }
    sum += sumOfLeftLeaves(root->left);
    sum += sumOfLeftLeaves(root->right);
    return sum;
}

int main(void) {
    // [3,9,20,null,null,15,7]
    struct TreeNode n[5];
    n[0].val = 3; n[0].left = &n[1]; n[0].right = &n[2];
    n[1].val = 9; n[1].left = NULL; n[1].right = NULL;
    n[2].val = 20; n[2].left = &n[3]; n[2].right = &n[4];
    n[3].val = 15; n[3].left = NULL; n[3].right = NULL;
    n[4].val = 7; n[4].left = NULL; n[4].right = NULL;
    printf("%d\n", sumOfLeftLeaves(&n[0]));

    // [1]
    struct TreeNode n2;
    n2.val = 1; n2.left = NULL; n2.right = NULL;
    printf("%d\n", sumOfLeftLeaves(&n2));
    return 0;
}
