#include <stdio.h>
#include <string.h>

void decode(char* s) {
    int len = strlen(s);
    char str_stack[10][100];
    int str_top = -1;
    int num_stack[10];
    int num_top = -1;
    char current[100] = "";
    int cur_len = 0;

    for (int i = 0; i < len; i++) {
        char ch = s[i];
        if (ch >= '0' && ch <= '9') {
            int num = 0;
            while (i < len && s[i] >= '0' && s[i] <= '9') {
                num = num * 10 + (s[i] - '0');
                i++;
            }
            i--;
            num_top++;
            num_stack[num_top] = num;
        } else if (ch == '[') {
            str_top++;
            strcpy(str_stack[str_top], current);
            cur_len = 0;
            current[0] = '\0';
        } else if (ch == ']') {
            int repeat = num_stack[num_top--];
            char prev[100];
            strcpy(prev, str_stack[str_top--]);
            char repeated[100] = "";
            for (int k = 0; k < repeat; k++) {
                strcat(repeated, current);
            }
            strcpy(current, prev);
            strcat(current, repeated);
            cur_len = strlen(current);
        } else {
            current[cur_len++] = ch;
            current[cur_len] = '\0';
        }
    }

    printf("%s\n", current);
}

int main() {
    decode("3[a]2[bc]");
    decode("3[a2[c]]");
    decode("2[abc]3[cd]ef");
    return 0;
}
