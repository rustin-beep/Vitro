/*
 * @category: libc_scanf
 * sscanf 变参尾参 &struct.member 定型（#161 修复锚，2026-10-18）：
 * 旧 check_builtin_sscanf 只查前两参，尾参 Addr(Member) 零定型回写，
 * codegen 取址 get_member_offset 按 object.ty=Void 落 0，成员偏移丢失
 * ——写入落基址（局部/全局双形态）+ 连发滞后形态全收。clang 真值对拍。
 */
#include <stdio.h>

typedef struct {
    int id;
    char cls;
} Row;

Row g;

void fill(Row *p, int id, char cls) {
    p->id = id;
    p->cls = cls;
}

int main(void) {
    /* 局部 struct 成员地址作 %c 目标 */
    Row r;
    r.id = 1;
    r.cls = 'N';
    int n1 = sscanf("A", "%c", &r.cls);
    printf("n1=%d id=%d cls=%c\n", n1, r.id, r.cls);

    /* 全局 struct 成员地址（赋值走 StoreMemByte，不受全局 char 粒度病影响） */
    g.id = 7;
    g.cls = 'N';
    int n2 = sscanf("B", "%c", &g.cls);
    printf("n2=%d id=%d cls=%c\n", n2, g.id, g.cls);

    /* 连发三形态（旧滞后写形态——第 N 次写到第 N-1 次目标） */
    char a = '0', b = '0';
    int n3 = sscanf("C", "%c", &a);
    int n4 = sscanf("D", "%c", &b);
    printf("n3=%d n4=%d a=%c b=%c\n", n3, n4, a, b);

    /* 四转换链（issue 原形态：TRAP 面） */
    Row s;
    s.id = 0;
    s.cls = 'X';
    char name[16];
    name[0] = 0;
    double score = 0.0;
    int n5 = sscanf("42|Zhang|95.5|A", "%d|%15[^|]|%lf|%c", &s.id, name, &score, &s.cls);
    printf("n5=%d id=%d name=%s score=%.1f cls=%c\n", n5, s.id, name, score, s.cls);

    /* %d 写 struct int 成员（对照组） */
    fill(&r, 3, 'Z');
    int n6 = sscanf("99", "%d", &r.id);
    printf("n6=%d id=%d cls=%c\n", n6, r.id, r.cls);
    return 0;
}
