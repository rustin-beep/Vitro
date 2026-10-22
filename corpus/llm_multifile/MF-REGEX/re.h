#ifndef RE_H
#define RE_H

#define RE_MAX_ELEMS 32
#define RE_MAX_TEXT 128

typedef enum {
    RE_CHAR = 0,
    RE_ANY = 1,
    RE_CLASS = 2,
    RE_STAR = 3,
    RE_OPT = 4,
    RE_BOL = 5,
    RE_EOL = 6
} ReElemType;

typedef struct {
    ReElemType type;
    char ch;
    char lo;
    char hi;
} ReElem;

typedef struct {
    ReElem elems[RE_MAX_ELEMS];
    int count;
} RePattern;

/* compiles a pattern, returns the number of elements or -1 */
int re_compile(RePattern *pattern, const char *text);

/* matches the text, returns 1 on success and fills start, end and the step counter */
int re_match(const RePattern *pattern, const char *text, int *start, int *end, long *steps);

const char *re_elem_name(ReElemType type);

extern int re_ops;

#endif /* RE_H */
