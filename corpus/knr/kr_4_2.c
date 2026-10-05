#include <stdio.h>
double myatof(char s[]) {
    double val, power;
    int i, sign;
    for (i = 0; s[i] == ' ' || s[i] == '\t' || s[i] == '\n'; i++)
        ;
    sign = (s[i] == '-') ? -1 : 1;
    if (s[i] == '+' || s[i] == '-')
        i++;
    for (val = 0.0; s[i] >= '0' && s[i] <= '9'; i++)
        val = 10.0 * val + (s[i] - '0');
    if (s[i] == '.')
        i++;
    for (power = 1.0; s[i] >= '0' && s[i] <= '9'; i++) {
        val = 10.0 * val + (s[i] - '0');
        power *= 10.0;
    }
    return sign * val / power;
}
int main() {
    printf("%.3f\n", myatof("123.456"));
    printf("%.3f\n", myatof("-0.5"));
    return 0;
}
