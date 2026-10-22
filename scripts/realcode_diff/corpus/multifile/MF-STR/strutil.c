#include "strutil.h"
#include <ctype.h>
#include <stdlib.h>
#include <string.h>

int str_trim(char *s)
{
    size_t n;
    size_t start;
    size_t end;

    if (s == NULL) {
        return STR_ERR_NULL;
    }
    n = strlen(s);
    start = 0;
    while (start < n && isspace((unsigned char)s[start])) {
        start++;
    }
    end = n;
    while (end > start && isspace((unsigned char)s[end - 1])) {
        end--;
    }
    if (start > 0) {
        memmove(s, s + start, end - start);
    }
    s[end - start] = '\0';
    return (int)(end - start);
}

int str_split_count(const char *s, char sep)
{
    int count;
    int in_field;

    if (s == NULL) {
        return STR_ERR_NULL;
    }
    count = 0;
    in_field = 0;
    for (const char *p = s; *p != '\0'; p++) {
        if (*p == sep) {
            in_field = 0;
        } else if (in_field == 0) {
            in_field = 1;
            count++;
        }
    }
    return count;
}

int str_replace_all(char *s, const char *needle, const char *repl)
{
    size_t nlen;
    size_t rlen;
    size_t slen;
    char *out;
    size_t oi;
    size_t i;
    int count;

    if (s == NULL || needle == NULL || repl == NULL) {
        return STR_ERR_NULL;
    }
    if (needle[0] == '\0') {
        return STR_ERR_EMPTY;
    }
    nlen = strlen(needle);
    rlen = strlen(repl);
    slen = strlen(s);
    out = (char *)malloc(slen * rlen + rlen + 1);
    if (out == NULL) {
        return STR_ERR_TOOBIG;
    }
    oi = 0;
    i = 0;
    count = 0;
    while (i < slen) {
        if (i + nlen <= slen && memcmp(s + i, needle, nlen) == 0) {
            memcpy(out + oi, repl, rlen);
            oi += rlen;
            i += nlen;
            count++;
        } else {
            out[oi] = s[i];
            oi++;
            i++;
        }
    }
    out[oi] = '\0';
    memcpy(s, out, oi + 1);
    free(out);
    return count;
}

int str_starts_with(const char *s, const char *prefix)
{
    size_t n;

    if (s == NULL || prefix == NULL) {
        return STR_ERR_NULL;
    }
    n = strlen(prefix);
    if (n == 0) {
        return 1;
    }
    if (strlen(s) < n) {
        return 0;
    }
    return strncmp(s, prefix, n) == 0 ? 1 : 0;
}

int str_ends_with(const char *s, const char *suffix)
{
    size_t slen;
    size_t xlen;

    if (s == NULL || suffix == NULL) {
        return STR_ERR_NULL;
    }
    slen = strlen(s);
    xlen = strlen(suffix);
    if (xlen == 0) {
        return 1;
    }
    if (slen < xlen) {
        return 0;
    }
    return strncmp(s + slen - xlen, suffix, xlen) == 0 ? 1 : 0;
}

void str_reverse(char *s)
{
    size_t n;
    size_t i;

    if (s == NULL) {
        return;
    }
    n = strlen(s);
    if (n < 2) {
        return;
    }
    i = 0;
    while (i < n / 2) {
        char tmp = s[i];
        s[i] = s[n - 1 - i];
        s[n - 1 - i] = tmp;
        i++;
    }
}

int str_to_upper(char *s)
{
    int changed;

    if (s == NULL) {
        return STR_ERR_NULL;
    }
    changed = 0;
    for (char *p = s; *p != '\0'; p++) {
        if (*p >= 'a' && *p <= 'z') {
            *p = (char)(*p - 'a' + 'A');
            changed++;
        }
    }
    return changed;
}

int str_to_lower(char *s)
{
    int changed;

    if (s == NULL) {
        return STR_ERR_NULL;
    }
    changed = 0;
    for (char *p = s; *p != '\0'; p++) {
        if (*p >= 'A' && *p <= 'Z') {
            *p = (char)(*p - 'A' + 'a');
            changed++;
        }
    }
    return changed;
}

int str_count_char(const char *s, char c)
{
    int count;

    if (s == NULL) {
        return STR_ERR_NULL;
    }
    count = 0;
    for (const char *p = s; *p != '\0'; p++) {
        if (*p == c) {
            count++;
        }
    }
    return count;
}

int str_index_of(const char *s, char c)
{
    int index;

    if (s == NULL) {
        return STR_ERR_NULL;
    }
    index = 0;
    for (const char *p = s; *p != '\0'; p++) {
        if (*p == c) {
            return index;
        }
        index++;
    }
    return STR_ERR_NOT_FOUND;
}

int str_copy_bounded(char *dst, size_t cap, const char *src)
{
    size_t n;

    if (dst == NULL || src == NULL) {
        return STR_ERR_NULL;
    }
    if (cap == 0) {
        return STR_ERR_TOOBIG;
    }
    n = strlen(src);
    if (n + 1 > cap) {
        memcpy(dst, src, cap - 1);
        dst[cap - 1] = '\0';
        return STR_ERR_TOOBIG;
    }
    memcpy(dst, src, n + 1);
    return STR_OK;
}
