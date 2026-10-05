#include <stdio.h>
#include <stdlib.h>
void swap(void *v[], int i, int j) {
    void *temp;
    temp = v[i];
    v[i] = v[j];
    v[j] = temp;
}
void qsortt(void *v[], int left, int right,
           int (*comp)(void *, void *)) {
    int i, last;
    void swap(void *v[], int i, int j);
    if (left >= right)
        return;
    swap(v, left, (left + right) / 2);
    last = left;
    for (i = left + 1; i <= right; i++)
        if ((*comp)(v[i], v[left]) < 0)
            swap(v, ++last, i);
    swap(v, left, last);
    qsortt(v, left, last - 1, comp);
    qsortt(v, last + 1, right, comp);
}
int numcmp(char *s1, char *s2) {
    double v1, v2;
    v1 = atof(s1);
    v2 = atof(s2);
    if (v1 < v2)
        return -1;
    else if (v1 > v2)
        return 1;
    else
        return 0;
}
int strcmp_local(char *s1, char *s2) {
    while (*s1 && *s1 == *s2) { s1++; s2++; }
    return *s1 - *s2;
}
int main() {
    char *lines[] = {"3.14", "-1", "0", "42", "2.71"};
    int nlines = 5;
    qsortt((void **)lines, 0, nlines - 1,
          (int (*)(void *, void *))numcmp);
    for (int i = 0; i < nlines; i++)
        printf("%s ", lines[i]);
    printf("\n");
    return 0;
}
