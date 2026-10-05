#include <stdio.h>
class A {
public:
    int id;
    A() { id = 0; }
    void set(int x) { id = x; }
};
int main() {
    A arr[3];
    for (int i = 0; i < 3; i++) arr[i].set(i + 1);
    for (int i = 0; i < 3; i++) printf("%d\n", arr[i].id);
    return 0;
}
