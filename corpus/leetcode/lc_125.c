#include <stdio.h>
#include <ctype.h>

int isPalindrome(char* s) {
    int left = 0;
    int right = 0;
    while (s[right] != '\0') right++;
    right--;
    while (left < right) {
        while (left < right && !isalnum(s[left])) left++;
        while (left < right && !isalnum(s[right])) right--;
        char lc = s[left];
        char rc = s[right];
        if (lc >= 'A' && lc <= 'Z') lc = lc - 'A' + 'a';
        if (rc >= 'A' && rc <= 'Z') rc = rc - 'A' + 'a';
        if (lc != rc) return 0;
        left++;
        right--;
    }
    return 1;
}

int main() {
    printf("%d\n", isPalindrome("A man, a plan, a canal: Panama"));
    printf("%d\n", isPalindrome("race a car"));
    printf("%d\n", isPalindrome(" "));
    return 0;
}
