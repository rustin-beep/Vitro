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

struct Point {
    int x;
    int y;
};

int main() {
    vector<Point> v;
    Point p1;
    p1.x = 1;
    p1.y = 2;
    v.push_back(p1);
    Point p2;
    p2.x = 3;
    p2.y = 4;
    v.push_back(p2);
    for (int i = 0; i < v.size(); i++) {
        Point p = v.get(i);
        printf("%d %d\n", p.x, p.y);
    }
    return 0;
}
