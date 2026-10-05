#include <stdio.h>
#include <string.h>
#define MAXLINES 10
char *lineptr[MAXLINES];
int readlines(char *lineptr[], int nlines);
void writelines(char *lineptr[], int nlines);
void qsortt(void *lineptr[], int left, int right,
           int (*comp)(void *, void *));
int numcmp(char *, char *);
int strcmp_local(char *s1, char *s2) {
    while (*s1 && *s1 == *s2) { s1++; s2++; }
    return *s1 - *s2;
}
int main() {
    int nlines;
    char *lines[] = {"3", "1", "4", "1", "5"};
    nlines = 5;
    for (int i = 0; i < nlines; i++) lineptr[i] = lines[i];
    qsortt((void **)lineptr, 0, nlines - 1,
          (int (*)(void *, void *))strcmp_local);
    writelines(lineptr, nlines);
    return 0;
}
void qsortt(void *v[], int left, int right,
           int (*comp)(void *, void *)) {
    int i, last;
    void swap(void *v[], int, int);
    if (left >= right) return;
    swap(v, left, (left + right) / 2);
    last = left;
    for (i = left + 1; i <= right; i++)
        if ((*comp)(v[i], v[left]) < 0)
            swap(v, ++last, i);
    swap(v, left, last);
    qsortt(v, left, last - 1, comp);
    qsortt(v, last + 1, right, comp);
}
void swap(void *v[], int i, int j) {
    void *temp;
    temp = v[i];
    v[i] = v[j];
    v[j] = temp;
}
void writelines(char *lineptr[], int nlines) {
    int i;
    for (i = 0; i < nlines; i++)
        printf("%s\n", lineptr[i]);
}
