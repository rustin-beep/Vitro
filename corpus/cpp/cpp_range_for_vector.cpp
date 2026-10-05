#include <stdio.h>
template<class T>
class vector {
    int n;
    int m;
    T* a;
public:
    vector() { n = 0; m = 0; a = (T*)0; }
    void push_back(T x) {
        if (n == m) { m = m ? m * 2 : 2; T* na = new T[m]; for (int i=0;i<n;i++) na[i]=a[i]; delete[] a; a = na; }
        a[n++] = x;
    }
    int size() { return n; }
    T get(int i) { return a[i]; }
    ~vector() { delete[] a; }
};
int main() {
    vector<int> v;
    v.push_back(3);
    v.push_back(1);
    v.push_back(4);
    int sum = 0;
    for (int i = 0; i < v.size(); i++) sum = sum + v.get(i);
    printf("%d\n", sum);
    return 0;
}
