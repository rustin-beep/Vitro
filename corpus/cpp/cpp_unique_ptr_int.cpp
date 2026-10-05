#include <stdio.h>
template<class T>
class unique_ptr {
    T* p;
public:
    unique_ptr(T* x) : p(x) {}
    T* get() { return p; }
    T* release() { T* t = p; p = (T*)0; return t; }
    ~unique_ptr() { if (p) delete p; }
};
int main() {
    unique_ptr<int> p(new int(42));
    printf("%d\n", *p.get());
    int* r = p.release();
    delete r;
    printf("0\n");
    return 0;
}
