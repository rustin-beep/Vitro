#include <stdio.h>
template<class T>
class Array {
    T data[10];
public:
    Array() {
        for (int i = 0; i < 10; i++) data[i] = 0;
    }
    void set(int i, T v) { data[i] = v; }
    T get(int i) { return data[i]; }
};
int main() {
    Array<int> a;
    for (int i = 0; i < 5; i++) a.set(i, i * 2);
    for (int i = 0; i < 5; i++) printf("%d\n", a.get(i));
    return 0;
}
