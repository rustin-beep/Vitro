// @category: baseline
#include <stdio.h>
#include <stdarg.h>
int fmt_n(char* buf, int size, const char* fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(buf, size, fmt, ap);
    va_end(ap);
    return n;
}
int main() {
    char buf[32];
    int n = fmt_n(buf, 32, "%s-%d", "id", 99);
    printf("%d %s", n, buf);
    return 0;
}
