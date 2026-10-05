#include <stdio.h>
#include <string.h>

void signature(const char* s, int* sig) {
    for (int i = 0; i < 26; i++) {
        sig[i] = 0;
    }
    int n = strlen(s);
    for (int i = 0; i < n; i++) {
        sig[s[i] - 'a']++;
    }
}

int same_sig(int* a, int* b) {
    for (int i = 0; i < 26; i++) {
        if (a[i] != b[i]) {
            return 0;
        }
    }
    return 1;
}

int main() {
    char* strs[] = {"eat", "tea", "tan", "ate", "nat", "bat"};
    int n = 6;
    int sigs[6][26];
    int visited[6] = {0};

    for (int i = 0; i < n; i++) {
        signature(strs[i], sigs[i]);
    }

    for (int i = 0; i < n; i++) {
        if (visited[i]) {
            continue;
        }
        printf("%s", strs[i]);
        visited[i] = 1;
        for (int j = i + 1; j < n; j++) {
            if (!visited[j] && same_sig(sigs[i], sigs[j])) {
                printf(" %s", strs[j]);
                visited[j] = 1;
            }
        }
        printf("\n");
    }

    return 0;
}
