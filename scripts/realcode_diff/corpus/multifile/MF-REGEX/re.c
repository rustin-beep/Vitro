#include "re.h"

int re_ops = 0;
#include <string.h>

/* furthest position that a partial match reached, used as failure position */
static int re_furthest = 0;

const char *re_elem_name(ReElemType type)
{
    switch (type) {
        case RE_CHAR:
            return "CHAR";
        case RE_ANY:
            return "ANY";
        case RE_CLASS:
            return "CLASS";
        case RE_STAR:
            return "STAR";
        case RE_OPT:
            return "OPT";
        case RE_BOL:
            return "BOL";
        case RE_EOL:
            return "EOL";
        default:
            return "UNKNOWN";
    }
}

int re_compile(RePattern *pattern, const char *text)
{
    int i = 0;

    if (pattern == NULL || text == NULL) {
        return -1;
    }
    pattern->count = 0;
    while (text[i] != '\0') {
        ReElem elem;
        char c = text[i];
        if (pattern->count >= RE_MAX_ELEMS) {
            return -2;
        }
        elem.type = RE_CHAR;
        elem.ch = c;
        elem.lo = c;
        elem.hi = c;
        if (c == '.') {
            elem.type = RE_ANY;
            elem.ch = '.';
        } else if (c == '^') {
            elem.type = RE_BOL;
            elem.ch = '^';
        } else if (c == '$') {
            elem.type = RE_EOL;
            elem.ch = '$';
        } else if (c == '*') {
            elem.type = RE_STAR;
            elem.ch = '*';
        } else if (c == '?') {
            elem.type = RE_OPT;
            elem.ch = '?';
        } else if (c == '[') {
            int j = i + 1;
            if (text[j] == '\0') {
                return -3;
            }
            elem.type = RE_CLASS;
            elem.lo = text[j];
            elem.hi = text[j];
            if (text[j + 1] == '-' && text[j + 2] != '\0' && text[j + 2] != ']') {
                elem.hi = text[j + 2];
                j += 2;
            }
            if (text[j + 1] == ']') {
                j++;
            } else {
                return -4;
            }
            elem.ch = '[';
            i = j;
        }
        pattern->elems[pattern->count] = elem;
        re_ops++;
        pattern->count++;
        i++;
    }
    return pattern->count;
}

static int re_atom_matches(const RePattern *pattern, int index, const char *text, int pos, int *next)
{
    const ReElem *elem = &pattern->elems[index];
    char c;

    if (elem->type == RE_BOL) {
        if (pos != 0) {
            return 0;
        }
        *next = pos;
        return 1;
    }
    if (elem->type == RE_EOL) {
        if (text[pos] != '\0') {
            return 0;
        }
        *next = pos;
        return 1;
    }
    c = text[pos];
    if (c == '\0') {
        return 0;
    }
    if (elem->type == RE_ANY) {
        *next = pos + 1;
        if (*next > re_furthest) {
            re_furthest = *next;
        }
        return 1;
    }
    if (elem->type == RE_CLASS) {
        if (c < elem->lo || c > elem->hi) {
            return 0;
        }
        *next = pos + 1;
        if (*next > re_furthest) {
            re_furthest = *next;
        }
        return 1;
    }
    if (elem->type == RE_CHAR) {
        if (c != elem->ch) {
            return 0;
        }
        *next = pos + 1;
        if (*next > re_furthest) {
            re_furthest = *next;
        }
        return 1;
    }
    return 0;
}

static int re_match_from(const RePattern *pattern, int index, const char *text, int pos,
                         int *end, long *steps)
{
    ReElemType quantifier = RE_CHAR;
    int next_index;
    int atom_index = index;

    if (index >= pattern->count) {
        *end = pos;
        return 1;
    }
    (*steps)++;
    if (index + 1 < pattern->count) {
        ReElemType following = pattern->elems[index + 1].type;
        if (following == RE_STAR || following == RE_OPT) {
            quantifier = following;
            next_index = index + 2;
        } else {
            next_index = index + 1;
        }
    } else {
        next_index = index + 1;
    }
    if (quantifier == RE_STAR) {
        int current = pos;
        if (re_match_from(pattern, next_index, text, current, end, steps)) {
            return 1;
        }
        for (;;) {
            int next = current;
            if (!re_atom_matches(pattern, atom_index, text, current, &next)) {
                break;
            }
            current = next;
            if (re_match_from(pattern, next_index, text, current, end, steps)) {
                return 1;
            }
        }
        return 0;
    }
    if (quantifier == RE_OPT) {
        int next = pos;
        if (re_match_from(pattern, next_index, text, pos, end, steps)) {
            return 1;
        }
        if (re_atom_matches(pattern, atom_index, text, pos, &next)) {
            return re_match_from(pattern, next_index, text, next, end, steps);
        }
        return 0;
    }
    {
        int next = pos;
        if (!re_atom_matches(pattern, atom_index, text, pos, &next)) {
            return 0;
        }
        if (next > re_furthest) {
            re_furthest = next;
        }
        return re_match_from(pattern, next_index, text, next, end, steps);
    }
}

int re_match(const RePattern *pattern, const char *text, int *start, int *end, long *steps)
{
    int len;
    int pos;
    long counter = 0;

    if (pattern == NULL || text == NULL) {
        return 0;
    }
    len = (int)strlen(text);
    re_furthest = 0;
    for (pos = 0; pos <= len; pos++) {
        int stop = pos;
        counter = 0;
        if (re_match_from(pattern, 0, text, pos, &stop, &counter)) {
            if (start != NULL) {
                *start = pos;
            }
            if (end != NULL) {
                *end = stop;
            }
            if (steps != NULL) {
                *steps = counter;
            }
            return 1;
        }
    }
    if (start != NULL) {
        *start = re_furthest;
    }
    if (end != NULL) {
        *end = -1;
    }
    if (steps != NULL) {
        *steps = counter;
    }
    return 0;
}
