#include <stdio.h>
class string {
    char* s;
    int len;
public:
    string() { s = new char[1]; s[0] = '\0'; len = 0; }
    void append(char c) {
        char* ns = new char[len + 2];
        for (int i = 0; i < len; i++) ns[i] = s[i];
        ns[len] = c;
        ns[len + 1] = '\0';
        delete[] s;
        s = ns;
        len++;
    }
    int size() { return len; }
    char get(int i) { return s[i]; }
    ~string() { delete[] s; }
};
int main() {
    string s;
    s.append('h');
    s.append('i');
    for (int i = 0; i < s.size(); i++) printf("%c", s.get(i));
    printf("\n");
    return 0;
}
