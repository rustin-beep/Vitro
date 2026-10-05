#include <stdio.h>
#include <stdio.h>

int squareSum(int n) {
    int sum = 0;
    while (n > 0) {
        int d = n % 10;
        sum += d * d;
        n /= 10;
    }
    return sum;
}

int isHappy(int n) {
    int slow = n, fast = n;
    do {
        slow = squareSum(slow);
        fast = squareSum(squareSum(fast));
    } while (slow != fast);
    return slow == 1;
}

int main(void) {
    printf("%d\n", isHappy(19));
    printf("%d\n", isHappy(2));
    return 0;
}
