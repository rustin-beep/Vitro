#include <stdio.h>
#include <string.h>

int wordBreak(char* s, char** wordDict, int wordDictSize) {
    int n = strlen(s);
    int dp[100] = {0};
    dp[0] = 1;

    for (int i = 1; i <= n; i++) {
        for (int j = 0; j < wordDictSize; j++) {
            int len = strlen(wordDict[j]);
            if (i >= len && dp[i - len] && strncmp(s + i - len, wordDict[j], len) == 0) {
                dp[i] = 1;
                break;
            }
        }
    }

    return dp[n];
}

int main() {
    char* dict1[] = {"leet", "code"};
    printf("%d\n", wordBreak("leetcode", dict1, 2));

    char* dict2[] = {"apple", "pen"};
    printf("%d\n", wordBreak("applepenapple", dict2, 2));

    char* dict3[] = {"cats", "dog", "sand", "and", "cat"};
    printf("%d\n", wordBreak("catsandog", dict3, 5));

    return 0;
}
