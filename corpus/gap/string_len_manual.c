// @category: string_storage_bug
int main() { char* s = "hello"; int len = 0; while (s[len]) len++; printf("%d", len); return 0; }
