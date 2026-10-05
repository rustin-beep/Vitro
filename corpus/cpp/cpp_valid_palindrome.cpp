#include <stdio.h>
#include <ctype.h>
int isPalindrome(char* s) {
    int l = 0, r = 0;
    while (s[r]) r++;
    r--;
    while (l < r) {
        while (l < r && !isalnum(s[l])) l++;
        while (l < r && !isalnum(s[r])) r--;
        if (tolower(s[l]) != tolower(s[r])) return 0;
        l++; r--;
    }
    return 1;
}
int main() {
    printf("%d\n", isPalindrome("A man, a plan, a canal: Panama"));
    return 0;
}
