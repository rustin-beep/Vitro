#include <stdio.h>
template<class T>
class list {
    struct Node { T data; Node* next; };
    Node* head;
    Node* tail;
    int n;
public:
    list() : head((Node*)0), tail((Node*)0), n(0) {}
    void push_back(T x) {
        Node* node = new Node;
        node->data = x;
        node->next = (Node*)0;
        if (tail) { tail->next = node; } else { head = node; }
        tail = node;
        n++;
    }
    T get(int i) {
        Node* p = head;
        for (int j = 0; j < i; j++) p = p->next;
        return p->data;
    }
    int size() { return n; }
    ~list() {
        Node* p = head;
        while (p) { Node* q = p; p = p->next; delete q; }
    }
};
int main() {
    list<int> l;
    l.push_back(3);
    l.push_back(1);
    l.push_back(4);
    for (int i = 0; i < l.size(); i++) printf("%d\n", l.get(i));
    return 0;
}
