typedef unsigned int size_t;
// #76 缺口 5（2026-10-13）：ptrdiff_t 随 stdio.h 传递——真 C 的 stdio.h
// 因内部使用引入 <stddef.h>（clang/gcc「只 include stdio.h 用 ptrdiff_t」
// 双 ACCEPT 佐证）；旧漏致 E2003，显式 include stddef.h 是绕法非正解
typedef int ptrdiff_t;
typedef void* FILE;

int printf(const char* fmt);
int scanf(const char* fmt);
int sprintf(char* buf, const char* fmt);
int snprintf(char* buf, int size, const char* fmt);
int sscanf(const char* str, const char* fmt);
int fprintf(FILE* stream, const char* fmt);
int vprintf(const char* fmt, char* ap);
int vfprintf(FILE* stream, const char* fmt, char* ap);
int vsnprintf(char* buf, int size, const char* fmt, char* ap);
int getchar(void);
int putchar(int c);
int puts(const char* s);
FILE* fopen(const char* path, const char* mode);
int fclose(FILE* stream);
int fread(void* ptr, int size, int nmemb, FILE* stream);
int fwrite(void* ptr, int size, int nmemb, FILE* stream);
int feof(FILE* stream);
char* fgets(char* s, int n, FILE* stream);
int fputs(const char* s, FILE* stream);
int ungetc(int c, FILE* stream);
int fgetc(FILE* stream);
int fputc(int c, FILE* stream);
int fseek(FILE* stream, int offset, int whence);
int ftell(FILE* stream);
void rewind(FILE* stream);
int fflush(FILE* stream);
void perror(const char* s);
void clearerr(FILE* stream);
int remove(const char* pathname);
int rename(const char* oldpath, const char* newpath);
