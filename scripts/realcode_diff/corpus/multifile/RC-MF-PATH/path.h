#ifndef PATH_H
#define PATH_H

#include <stddef.h>

#define PATH_MAX 256

void path_normalize(const char *input, char *out, size_t cap);
void path_join(const char *base, const char *tail, char *out, size_t cap);
void path_basename(const char *path, char *out, size_t cap);
void path_dirname(const char *path, char *out, size_t cap);
void path_extname(const char *path, char *out, size_t cap);
int path_is_absolute(const char *path);
int path_wildcard_match(const char *pattern, const char *path);
int path_relative(const char *from, const char *to, char *out, size_t cap);

#endif /* PATH_H */
