typedef struct { double d; char c; } S;
int main(void) {
    S s;
    S *p = &s;
    p->d = 2.5;
    p->c = 66;
    return s.d > 0 ? 0 : 1;
}
