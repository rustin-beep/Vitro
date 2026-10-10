// @category: baseline
#include <stdio.h>
#include <stdarg.h>
void emit(const char* fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vprintf(fmt, ap);
    va_end(ap);
}
int main() {
    emit("%d %s %c", 42, "hi", 'A');
    return 0;
}
