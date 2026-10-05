#include <stdio.h>
class List {
    struct Node { int v; Node* next; };
    Node* head;
public:
    List() { head = (Node*)0; }
    void prepend(int x) {
        Node* n = new Node;
        n->v = x;
        n->next = head;
        head = n;
    }
    void print() {
        Node* p = head;
        while (p) { printf("%d\n", p->v); p = p->next; }
    }
    ~List() {
        Node* p = head;
        while (p) { Node* q = p; p = p->next; delete q; }
    }
};
int main() {
    List l;
    l.prepend(3);
    l.prepend(2);
    l.prepend(1);
    l.print();
    return 0;
}
