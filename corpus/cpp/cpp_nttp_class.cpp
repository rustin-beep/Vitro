#include <stdio.h>

template<typename T, int N>
class Array {
public:
    T data[N];
    int size() { return N; }
};

int main() {
    Array<int, 5> a;
    printf("%d\n", a.size());
    return 0;
}
