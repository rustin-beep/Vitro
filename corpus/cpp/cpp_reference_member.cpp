#include <stdio.h>
class Counter {
public:
    int value;
    Counter() { value = 0; }
    int& get() { return value; }
};
int main() {
    Counter c;
    c.get() = 25;
    printf("%d\n", c.value);
    return 0;
}
