#include <stdio.h>
#include <stdio.h>

int isPalindrome(int x) {
    if (x < 0 || (x % 10 == 0 && x != 0)) return 0;
    int reverted = 0;
    while (x > reverted) {
        reverted = reverted * 10 + x % 10;
        x /= 10;
    }
    return x == reverted || x == reverted / 10;
}

int main(void) {
    printf("%d\n", isPalindrome(121));
    printf("%d\n", isPalindrome(-121));
    printf("%d\n", isPalindrome(10));
    printf("%d\n", isPalindrome(12321));
    return 0;
}
