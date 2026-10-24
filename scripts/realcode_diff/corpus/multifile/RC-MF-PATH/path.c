#include "path.h"
#include <stdio.h>
#include <string.h>
#include <ctype.h>

static void path_copy(char *dst, size_t cap, const char *src)
{
    size_t n;

    if (dst == NULL || src == NULL || cap == 0) {
        return;
    }
    n = strlen(src);
    if (n > cap - 1) {
        n = cap - 1;
    }
    memcpy(dst, src, n);
    dst[n] = '\0';
}

static int path_is_separator(char c)
{
    return (c == '/' || c == '\\') ? 1 : 0;
}

void path_normalize(const char *input, char *out, size_t cap)
{
    char parts[16][PATH_MAX];
    int part_count = 0;
    int absolute;
    size_t i = 0;
    size_t length;
    size_t position = 0;
    int k;

    if (out == NULL || cap == 0) {
        return;
    }
    out[0] = '\0';
    if (input == NULL) {
        return;
    }
    length = strlen(input);
    absolute = (length > 0 && path_is_separator(input[0])) ? 1 : 0;
    while (i < length) {
        size_t start = i;
        size_t part_length;
        while (i < length && !path_is_separator(input[i])) {
            i++;
        }
        part_length = i - start;
        if (part_length > 0) {
            char part[PATH_MAX];
            if (part_length >= PATH_MAX) {
                part_length = PATH_MAX - 1;
            }
            memcpy(part, input + start, part_length);
            part[part_length] = '\0';
            if (strcmp(part, ".") == 0) {
                /* the current directory is dropped */
            } else if (strcmp(part, "..") == 0) {
                if (part_count > 0 && strcmp(parts[part_count - 1], "..") != 0) {
                    part_count--;
                } else if (!absolute && part_count == 0 && part_count < 16) {
                    memcpy(parts[part_count], "..", 3);
                    part_count++;
                }
            } else if (part_count < 16) {
                memcpy(parts[part_count], part, part_length + 1);
                part_count++;
            }
        }
        while (i < length && path_is_separator(input[i])) {
            i++;
        }
    }
    if (absolute && position + 1 < cap) {
        out[position++] = '/';
    }
    out[position] = '\0';
    for (k = 0; k < part_count; k++) {
        size_t part_length = strlen(parts[k]);
        if (k > 0 && position + 1 < cap) {
            out[position++] = '/';
        }
        if (position + part_length + 1 > cap) {
            break;
        }
        memcpy(out + position, parts[k], part_length);
        position += part_length;
        out[position] = '\0';
    }
    if (position == 0 && cap > 1) {
        out[0] = '.';
        out[1] = '\0';
    }
}

void path_join(const char *base, const char *tail, char *out, size_t cap)
{
    char buffer[PATH_MAX * 2];
    size_t length = 0;

    if (out == NULL || cap == 0) {
        return;
    }
    out[0] = '\0';
    if (base != NULL) {
        length = strlen(base);
        if (length >= sizeof buffer) {
            length = sizeof buffer - 1;
        }
        memcpy(buffer, base, length);
        buffer[length] = '\0';
    }
    if (tail != NULL && tail[0] != '\0') {
        if (length > 0 && !path_is_separator(buffer[length - 1]) && tail[0] != '/') {
            if (length + 1 < sizeof buffer) {
                buffer[length++] = '/';
                buffer[length] = '\0';
            }
        }
        {
            size_t tail_length = strlen(tail);
            if (length + tail_length + 1 >= sizeof buffer) {
                tail_length = sizeof buffer - length - 1;
            }
            memcpy(buffer + length, tail, tail_length);
            length += tail_length;
            buffer[length] = '\0';
        }
    }
    path_normalize(buffer, out, cap);
}

void path_basename(const char *path, char *out, size_t cap)
{
    size_t i;
    size_t length;

    if (out == NULL || cap == 0) {
        return;
    }
    out[0] = '\0';
    if (path == NULL) {
        return;
    }
    length = strlen(path);
    i = length;
    while (i > 0 && !path_is_separator(path[i - 1])) {
        i--;
    }
    path_copy(out, cap, path + i);
}

void path_dirname(const char *path, char *out, size_t cap)
{
    size_t i;
    size_t length;

    if (out == NULL || cap == 0) {
        return;
    }
    out[0] = '\0';
    if (path == NULL) {
        return;
    }
    length = strlen(path);
    i = length;
    while (i > 0 && !path_is_separator(path[i - 1])) {
        i--;
    }
    if (i == 0) {
        path_copy(out, cap, ".");
        return;
    }
    while (i > 1 && path_is_separator(path[i - 1])) {
        i--;
    }
    if (i >= cap) {
        i = cap - 1;
    }
    memcpy(out, path, i);
    out[i] = '\0';
}

void path_extname(const char *path, char *out, size_t cap)
{
    char name[PATH_MAX];
    const char *dot;

    if (out == NULL || cap == 0) {
        return;
    }
    out[0] = '\0';
    path_basename(path, name, sizeof name);
    dot = strrchr(name, '.');
    if (dot == NULL || dot == name) {
        return;
    }
    path_copy(out, cap, dot);
}

int path_is_absolute(const char *path)
{
    if (path == NULL || path[0] == '\0') {
        return 0;
    }
    return path_is_separator(path[0]) ? 1 : 0;
}

static int path_match_segment(const char *pattern, const char *text)
{
    if (*pattern == '\0') {
        return (*text == '\0') ? 1 : 0;
    }
    if (*pattern == '*') {
        while (pattern[1] == '*') {
            pattern++;
        }
        if (pattern[1] == '\0') {
            return 1;
        }
        while (*text != '\0') {
            if (path_match_segment(pattern + 1, text)) {
                return 1;
            }
            text++;
        }
        return path_match_segment(pattern + 1, text);
    }
    if (*text == '\0') {
        return 0;
    }
    if (*pattern == '?' || *pattern == *text) {
        return path_match_segment(pattern + 1, text + 1);
    }
    return 0;
}

int path_wildcard_match(const char *pattern, const char *path)
{
    if (pattern == NULL || path == NULL) {
        return 0;
    }
    if (*pattern == '\0') {
        return (*path == '\0') ? 1 : 0;
    }
    if (*pattern == '*' && path_is_separator(path[0])) {
        return 0;
    }
    if (!path_is_separator(*pattern) && path_is_separator(*path)) {
        return 0;
    }
    if (path_is_separator(*pattern)) {
        while (path[0] == '/') {
            path++;
        }
        while (*pattern == '/') {
            pattern++;
        }
        return path_wildcard_match(pattern, path);
    }
    return path_match_segment(pattern, path);
}

int path_relative(const char *from, const char *to, char *out, size_t cap)
{
    char from_parts[16][PATH_MAX];
    char to_parts[16][PATH_MAX];
    char buffer[PATH_MAX];
    int from_count = 0;
    int to_count = 0;
    int i;
    int common = 0;
    size_t position = 0;

    if (out == NULL || cap == 0) {
        return -1;
    }
    out[0] = '\0';
    if (from == NULL || to == NULL) {
        return -1;
    }
    path_normalize(from, buffer, sizeof buffer);
    {
        size_t i2 = 0;
        while (buffer[i2] != '\0' && from_count < 16) {
            size_t start = i2;
            while (buffer[i2] != '\0' && buffer[i2] != '/') {
                i2++;
            }
            if (i2 > start) {
                path_copy(from_parts[from_count], PATH_MAX, buffer + start);
                from_count++;
            }
            while (buffer[i2] == '/') {
                i2++;
            }
        }
    }
    path_normalize(to, buffer, sizeof buffer);
    {
        size_t i2 = 0;
        while (buffer[i2] != '\0' && to_count < 16) {
            size_t start = i2;
            while (buffer[i2] != '\0' && buffer[i2] != '/') {
                i2++;
            }
            if (i2 > start) {
                path_copy(to_parts[to_count], PATH_MAX, buffer + start);
                to_count++;
            }
            while (buffer[i2] == '/') {
                i2++;
            }
        }
    }
    while (common < from_count && common < to_count &&
           strcmp(from_parts[common], to_parts[common]) == 0) {
        common++;
    }
    for (i = common; i < from_count; i++) {
        if (position + 3 < cap) {
            out[position++] = '.';
            out[position++] = '.';
            out[position++] = '/';
            out[position] = '\0';
        }
    }
    for (i = common; i < to_count; i++) {
        size_t part_length = strlen(to_parts[i]);
        if (position + part_length + 2 > cap) {
            break;
        }
        memcpy(out + position, to_parts[i], part_length);
        position += part_length;
        out[position++] = '/';
        out[position] = '\0';
    }
    if (position > 0 && out[position - 1] == '/') {
        out[position - 1] = '\0';
    }
    if (position == 0 && cap > 1) {
        out[0] = '.';
        out[1] = '\0';
    }
    return 0;
}
