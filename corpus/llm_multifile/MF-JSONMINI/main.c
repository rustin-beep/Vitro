#include <stdio.h>
#include <string.h>
#include "json.h"

static const char *const DOCUMENT =
    "{\"name\": \"vitro\", \"version\": 3, \"debug\": false, \"tags\": [\"c\", \"vm\", \"2026\"],"
    " \"owner\": {\"team\": \"core\", \"size\": 4, \"remote\": {\"host\": \"localhost\","
    " \"port\": 8080}}, \"note\": \"line\\nbreak \\\"quoted\\\"\", \"nothing\": null}";

static const char *const QUERIES[5] = {
    "name",
    "version",
    "owner.team",
    "owner.remote.port",
    "owner.missing"
};

int main(void)
{
    char error[80];
    char buffer[1024];
    char text[64];
    JsonValue *root;
    int i;

    printf("=== parse ===\n");
    root = json_parse(DOCUMENT, error, sizeof error);
    if (root == NULL) {
        printf("  parse error: %s\n", error);
        return 1;
    }
    printf("  document length=%d parsed=%s\n", (int)strlen(DOCUMENT), "yes");

    printf("=== tree ===\n");
    json_print(root, 0);

    printf("=== key paths ===\n");
    json_print_paths(root, "", 0);

    printf("=== queries ===\n");
    for (i = 0; i < 5; i++) {
        double number = 0.0;
        if (json_get_number(root, QUERIES[i], &number) == 0) {
            printf("  %-20s number=%g\n", QUERIES[i], number);
        } else if (json_get_string(root, QUERIES[i], text, sizeof text) == 0) {
            printf("  %-20s string=%s\n", QUERIES[i], text);
        } else {
            printf("  %-20s not found\n", QUERIES[i]);
        }
    }

    printf("=== serialize ===\n");
    if (json_serialize(root, buffer, sizeof buffer) > 0) {
        printf("  %s\n", buffer);
    }

    printf("=== syntax error ===\n");
    {
        char broken[64];
        JsonValue *bad;
        memcpy(broken, "{\"a\": 1, \"b\": }", 15);
        bad = json_parse(broken, error, sizeof error);
        printf("  parsed=%s error=%s\n", (bad != NULL) ? "yes" : "no", error);
        if (bad != NULL) {
            json_free(bad);
        }
        memcpy(broken, "{\"a\": [1, 2, }", 14);
        bad = json_parse(broken, error, sizeof error);
        printf("  parsed=%s error=%s\n", (bad != NULL) ? "yes" : "no", error);
        if (bad != NULL) {
            json_free(bad);
        }
    }

    json_free(root);
    printf("=== done ===\n");
    return 0;
}
