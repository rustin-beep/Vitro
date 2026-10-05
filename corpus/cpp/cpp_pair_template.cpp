#include <stdio.h>
template<class T, class U>
class Pair {
public:
    T first;
    U second;
    Pair(T a, U b) : first(a), second(b) {}
};
int main() {
    Pair<int, char> p(1, 'a');
    printf("%d %c\n", p.first, p.second);
    Pair<int, int> q(2, 10);
    printf("%d %d\n", q.first, q.second);
    return 0;
}
