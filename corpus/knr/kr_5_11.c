#include <stdio.h>
int main() {
    char *month_name(int n);
    printf("%s\n", month_name(2));
    printf("%s\n", month_name(12));
    return 0;
}
char *month_name(int n) {
    static char *name[] = {
        "Illegal month",
        "January", "February", "March",
        "April", "May", "June",
        "July", "August", "September",
        "October", "November", "December"
    };
    return (n < 1 || n > 12) ? name[0] : name[n];
}
