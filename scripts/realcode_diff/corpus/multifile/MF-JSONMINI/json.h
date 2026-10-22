#ifndef JSON_H
#define JSON_H

#include <stddef.h>

#define JSON_MAX_KEY 32
#define JSON_MAX_STRING 64
#define JSON_MAX_MEMBERS 8
#define JSON_MAX_DEPTH 8

typedef enum {
    JSON_NULL = 0,
    JSON_BOOL = 1,
    JSON_NUMBER = 2,
    JSON_STRING = 3,
    JSON_ARRAY = 4,
    JSON_OBJECT = 5
} JsonType;

typedef struct JsonValue JsonValue;

typedef struct {
    char key[JSON_MAX_KEY];
    JsonValue *value;
} JsonMember;

struct JsonValue {
    JsonType type;
    int boolean;
    double number;
    char string[JSON_MAX_STRING];
    JsonMember members[JSON_MAX_MEMBERS];
    int member_count;
    JsonValue *items[JSON_MAX_MEMBERS];
    int item_count;
};

JsonValue *json_parse(const char *text, char *error, size_t cap);
void json_free(JsonValue *value);
int json_serialize(const JsonValue *value, char *out, size_t cap);
JsonValue *json_find(const JsonValue *root, const char *path);
int json_get_number(const JsonValue *root, const char *path, double *out);
int json_get_string(const JsonValue *root, const char *path, char *out, size_t cap);
void json_print(const JsonValue *value, int indent);
void json_print_paths(const JsonValue *value, const char *prefix, int depth);
const char *json_type_name(JsonType type);

#endif /* JSON_H */
