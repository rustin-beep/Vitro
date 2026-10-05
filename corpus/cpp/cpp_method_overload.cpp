#include <stdio.h>
struct Node {
    int val;
    Node* left;
    Node* right;
};
class Tree {
    Node* root;
    Node* insert(Node* n, int x) {
        if (!n) {
            Node* t = new Node;
            t->val = x;
            t->left = (Node*)0;
            t->right = (Node*)0;
            return t;
        }
        if (x < n->val) n->left = insert(n->left, x);
        else n->right = insert(n->right, x);
        return n;
    }
    void print(Node* n) {
        if (!n) return;
        print(n->left);
        printf("%d\n", n->val);
        print(n->right);
    }
public:
    Tree() { root = (Node*)0; }
    void insert(int x) { root = insert(root, x); }
    void print() { print(root); }
};
int main() {
    Tree t;
    t.insert(5);
    t.insert(3);
    t.insert(7);
    t.print();
    return 0;
}
