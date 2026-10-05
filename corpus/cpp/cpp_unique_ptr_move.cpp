#include <stdio.h>
template<class T>
class unique_ptr {
    T* p;
public:
    unique_ptr(T* x) : p(x) {}
    void move_from(unique_ptr<T>& o) { p = o.p; o.p = (T*)0; }
    T* get() { return p; }
    ~unique_ptr() { if (p) delete p; }
};
int main() {
    unique_ptr<int> a(new int(7));
    unique_ptr<int> b((int*)0);
    b.move_from(a);
    printf("%d\n", *b.get());
    printf("%d\n", a.get() ? 1 : 0);
    return 0;
}
