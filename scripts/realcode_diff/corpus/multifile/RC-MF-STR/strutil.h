#ifndef STRUTIL_H
#define STRUTIL_H

#include <stddef.h>

#define STR_OK              0
#define STR_ERR_NULL      (-1)
#define STR_ERR_NOT_FOUND (-2)
#define STR_ERR_TOOBIG    (-3)
#define STR_ERR_EMPTY     (-4)

/* in-place trim of leading/trailing whitespace; returns the new length or an error code */
int str_trim(char *s);

/* number of non-empty fields separated by sep; returns an error code for NULL input */
int str_split_count(const char *s, char sep);

/* in-place replacement of every needle; s needs room for strlen(s) * strlen(repl) + 1 bytes */
int str_replace_all(char *s, const char *needle, const char *repl);

/* 1 when s starts/ends with the given text, 0 otherwise, negative on NULL input */
int str_starts_with(const char *s, const char *prefix);
int str_ends_with(const char *s, const char *suffix);

/* in-place character reversal */
void str_reverse(char *s);

/* in-place case conversion; returns the number of converted characters */
int str_to_upper(char *s);
int str_to_lower(char *s);

/* counting and searching helpers; negative index / error code when not found */
int str_count_char(const char *s, char c);
int str_index_of(const char *s, char c);

/* bounded copy; returns STR_ERR_TOOBIG when the source does not fit into cap */
int str_copy_bounded(char *dst, size_t cap, const char *src);

#endif /* STRUTIL_H */
