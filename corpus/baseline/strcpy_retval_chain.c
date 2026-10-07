// strcpy/memcpy 族返回值链式语义（批四 N4 销案的 E2E 语料锚——C 标准：
// strcpy/strcat 返回目标指针、memcpy 返回 dst；引擎旧形态照搬 oracle 的
// 死臂签名）。链式 strcat(strcpy(...)) 只有返回指针正确时才成立。
// 预期（Clang 对拍真值）：stdout = "abcd\n12\n"，退出码 5（'d'-'a' + 2）。
#include <stdio.h>
#include <string.h>

int main() {
    char buf[16];
    char *p = strcat(strcpy(buf, "ab"), "cd");
    printf("%s\n", p);
    int m[2] = {1, 2};
    int n[2];
    memcpy(n, m, sizeof(m));
    printf("%d%d\n", n[0], n[1]);
    return p[3] - 'a' + n[1];
}
