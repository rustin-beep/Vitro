union U { int i; double d; char c; long long q; };
int main(void) {
    union U u;
    u.i = 1;
    u.d = 1.5;
    u.c = 65;
    u.q = 42;
    return u.i;
}
