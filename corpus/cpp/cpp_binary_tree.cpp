#include <stdio.h>
struct Node { int v; Node* left; Node* right; };
Node* new_node(int x) {
    Node* p = new Node;
    p->v = x;
    p->left = p->right = (Node*)0;
    return p;
}
Node* tree_insert(Node* p, int x) {
    if (!p) return new_node(x);
    if (x < p->v) p->left = tree_insert(p->left, x);
    else p->right = tree_insert(p->right, x);
    return p;
}
void tree_inorder(Node* p) {
    if (p) { tree_inorder(p->left); printf("%d\n", p->v); tree_inorder(p->right); }
}
void tree_clear(Node* p) {
    if (p) { tree_clear(p->left); tree_clear(p->right); delete p; }
}
class Tree {
    Node* root;
public:
    Tree() { root = (Node*)0; }
    void add(int x) { root = tree_insert(root, x); }
    void print() { tree_inorder(root); }
    ~Tree() { tree_clear(root); }
};
int main() {
    Tree t;
    t.add(5);
    t.add(3);
    t.add(7);
    t.print();
    return 0;
}
