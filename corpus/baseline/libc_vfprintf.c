// @category: baseline
#include <stdio.h>
#include <stdarg.h>
void emit(FILE* f, const char* fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vfprintf(f, fmt, ap);
    va_end(ap);
}
int main() {
    FILE* f = fopen("vf_tmp.txt", "w");
    if (!f) { return 1; }
    emit(f, "x=%d y=%.1f", 7, 2.5);
    fclose(f);
    FILE* r = fopen("vf_tmp.txt", "r");
    char buf[32];
    if (!r || !fgets(buf, 32, r)) { return 2; }
    printf("%s", buf);
    return 0;
}
