#include <stdio.h>
#include <string.h>
#include "path.h"

#define PATH_CASES 8
#define WILDCARD_CASES 6
#define RELATIVE_COUNT 4

static const char *const PATHS[PATH_CASES] = {
    "/usr/local/lib/libfoo.so",
    "/usr/local/../share/./data.txt",
    "docs/readme.md",
    "docs/",
    "archive.tar.gz",
    "/a/b/c/../../d/e",
    "./relative/../file.c",
    "/"
};

static const char *const WILDCARDS[WILDCARD_CASES][2] = {
    { "*.c", "main.c" },
    { "*.c", "src/main.c" },
    { "doc?.md", "docs.md" },
    { "data/*/file", "data/2024/file" },
    { "*", "anything.txt" },
    { "*.md", "readme.txt" }
};

static const char *const RELATIVE_CASES[RELATIVE_COUNT][2] = {
    { "/home/user/project", "/home/user/project/src/main.c" },
    { "/home/user/project", "/home/user/docs/readme.md" },
    { "/a/b", "/a/c/d" },
    { "/a/b/c", "/a/b/c" }
};

static const char *const EXPECTED_NORMALIZE[PATH_CASES] = {
    "/usr/local/lib/libfoo.so",
    "/usr/share/data.txt",
    "docs/readme.md",
    "docs",
    "archive.tar.gz",
    "/a/d/e",
    "file.c",
    "/"
};

int main(void)
{
    char buffer[PATH_MAX];
    int passed = 0;
    int total = 0;
    int i;

    printf("=== eight fixed paths ===\n");
    for (i = 0; i < PATH_CASES; i++) {
        path_normalize(PATHS[i], buffer, sizeof buffer);
        printf("  %-28s -> %s\n", PATHS[i], buffer);
        path_basename(PATHS[i], buffer, sizeof buffer);
        printf("      basename=%s", buffer);
        path_dirname(PATHS[i], buffer, sizeof buffer);
        printf(" dirname=%s", buffer);
        path_extname(PATHS[i], buffer, sizeof buffer);
        printf(" ext=%s\n", buffer);
        printf("      absolute=%d\n", path_is_absolute(PATHS[i]));
        total++;
        {
            char normalized[PATH_MAX];
            path_normalize(PATHS[i], normalized, sizeof normalized);
            if (strcmp(normalized, EXPECTED_NORMALIZE[i]) == 0) {
                passed++;
            }
        }
    }

    printf("=== join ===\n");
    path_join("/usr/local", "lib/libfoo.so", buffer, sizeof buffer);
    printf("  join(/usr/local, lib/libfoo.so) = %s\n", buffer);
    path_join("docs", "../notes.txt", buffer, sizeof buffer);
    printf("  join(docs, ../notes.txt) = %s\n", buffer);
    path_join("/a/b/", "c", buffer, sizeof buffer);
    printf("  join(/a/b/, c) = %s\n", buffer);

    printf("=== wildcard matching ===\n");
    for (i = 0; i < WILDCARD_CASES; i++) {
        int matched = path_wildcard_match(WILDCARDS[i][0], WILDCARDS[i][1]);
        printf("  pattern=%-12s path=%-18s match=%d\n", WILDCARDS[i][0],
               WILDCARDS[i][1], matched);
        total++;
    }

    printf("=== relative paths ===\n");
    for (i = 0; i < RELATIVE_COUNT; i++) {
        path_relative(RELATIVE_CASES[i][0], RELATIVE_CASES[i][1], buffer, sizeof buffer);
        printf("  from=%-24s to=%-28s relative=%s\n", RELATIVE_CASES[i][0],
               RELATIVE_CASES[i][1], buffer);
        total++;
    }

    printf("=== result ===\n");
    printf("  normalize_checks=%d/%d total_tests=%d\n", passed, PATH_CASES, total);
    printf("=== done ===\n");
    return 0;
}
