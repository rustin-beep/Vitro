#include <stdio.h>

void countAndSay(int n, char* out) {
    char cur[5000];
    char nxt[5000];
    cur[0] = '1';
    cur[1] = '\0';
    for (int i = 2; i <= n; i++) {
        int j = 0;
        int k = 0;
        while (cur[j] != '\0') {
            char c = cur[j];
            int cnt = 0;
            while (cur[j] != '\0' && cur[j] == c) {
                cnt++;
                j++;
            }
            nxt[k++] = cnt + '0';
            nxt[k++] = c;
        }
        nxt[k] = '\0';
        int p = 0;
        while (nxt[p] != '\0') {
            cur[p] = nxt[p];
            p++;
        }
        cur[p] = '\0';
    }
    int p = 0;
    while (cur[p] != '\0') {
        out[p] = cur[p];
        p++;
    }
    out[p] = '\0';
}

int main() {
    char buf[5000];
    countAndSay(1, buf);
    printf("%s\n", buf);
    countAndSay(4, buf);
    printf("%s\n", buf);
    return 0;
}
