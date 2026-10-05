#include <stdio.h>
template<class T>
class unique_ptr {
    T* p;
public:
    unique_ptr() { p = (T*)0; }
    ~unique_ptr() { if (p) delete p; }
    T* get() { return p; }
    void reset(T* x) { if (p) delete p; p = x; }
};
int main() {
    unique_ptr<int> a;
    a.reset(new int);
    *a.get() = 42;
    printf("%d\n", *a.get());
    a.reset(new int);
    *a.get() = 100;
    printf("%d\n", *a.get());
    return 0;
}
