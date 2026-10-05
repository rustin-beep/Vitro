#include <stdio.h>
template<class T>
class vector {
    int size_;
    int cap_;
    T* data;
public:
    vector() : size_(0), cap_(0), data((T*)0) {}
    void push_back(T x) {
        if (size_ >= cap_) {
            int nc = cap_ == 0 ? 4 : cap_ * 2;
            T* nd = new T[nc];
            for (int i = 0; i < size_; i++) nd[i] = data[i];
            delete[] data;
            data = nd;
            cap_ = nc;
        }
        data[size_++] = x;
    }
    T get(int i) { return data[i]; }
    int size() { return size_; }
    ~vector() { delete[] data; }
};
int main() {
    vector<int> v;
    v.push_back(3);
    v.push_back(1);
    v.push_back(4);
    for (int i = 0; i < v.size(); i++) printf("%d\n", v.get(i));
    return 0;
}
