#include <stdio.h>
template<class T>
class vector {
    int n; int m; T* a;
public:
    vector() { n=0; m=0; a=(T*)0; }
    void push_back(T x) {
        if (n==m) { m=m?m*2:2; T* na=new T[m]; for(int i=0;i<n;i++)na[i]=a[i]; delete[] a; a=na; }
        a[n++]=x;
    }
    T get(int i){return a[i];}
    int size(){return n;}
    ~vector(){delete[] a;}
};
void twoSum(int* nums, int numsSize, int target, int* out) {
    for (int i = 0; i < numsSize; i++)
        for (int j = i + 1; j < numsSize; j++)
            if (nums[i] + nums[j] == target) { out[0] = i; out[1] = j; return; }
}
int main() {
    int nums[] = {2, 7, 11, 15};
    int r[2];
    twoSum(nums, 4, 9, r);
    printf("%d %d\n", r[0], r[1]);
    return 0;
}
