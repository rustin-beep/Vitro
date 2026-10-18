// sscanf scanset 转换 %[...]（#149 红锚，2026-10-18）：否定式 %[^;]/
// %[^,]、正向集合、中缀 `-` 范围语义（%[a-z]）、width 限制、赋值抑制、
// 首位 `]` 字面成员、与 %d/%s 混排。修复前 `[` 被当格式字母、集合内容
// 当字面字符——scanset 起全链失配（matched 停在其前）。
#include <stdio.h>
int main(void) {
    char name[32] = "";
    char word[32] = "";
    int id = -1;
    int a = -1;
    int b = -1;
    const char *s = "id=1001;name=Alice;score=95.5";
    double score = 0;
    int n1 = sscanf(s, "id=%d;name=%[^;];score=%lf", &id, name, &score);
    printf("n1=%d id=%d name=%s score=%g\n", n1, id, name, score);
    int n2 = sscanf("Alice,95,88", "%[^,],%d,%d", name, &a, &b);
    printf("n2=%d name=%s a=%d b=%d\n", n2, name, a, b);
    int n3 = sscanf("abc123", "%[a-z]", word);
    printf("n3=%d word=%s\n", n3, word);
    int n4 = sscanf("Alice;Bob", "%*[^;];%[^\n]", word);
    printf("n4=%d word=%s\n", n4, word);
    int n5 = sscanf("]x", "%[]x]", word);
    printf("n5=%d word=%s\n", n5, word);
    return 0;
}
