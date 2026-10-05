#include <stdio.h>
float fahr_to_celsius(float fahr) {
    return (5.0/9.0) * (fahr - 32.0);
}
int main() {
    for (float fahr = 0; fahr <= 300; fahr += 20)
        printf("%3.0f %6.1f\n", fahr, fahr_to_celsius(fahr));
    return 0;
}
