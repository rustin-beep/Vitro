#include "json.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

typedef struct {
    const char *text;
    size_t position;
    int depth;
    char *error;
    size_t error_cap;
    int failed;
} JsonParser;

const char *json_type_name(JsonType type)
{
    switch (type) {
        case JSON_NULL:
            return "null";
        case JSON_BOOL:
            return "bool";
        case JSON_NUMBER:
            return "number";
        case JSON_STRING:
            return "string";
        case JSON_ARRAY:
            return "array";
        case JSON_OBJECT:
            return "object";
        default:
            return "unknown";
    }
}

static void json_fail(JsonParser *parser, const char *message)
{
    if (parser->failed) {
        return;
    }
    parser->failed = 1;
    if (parser->error != NULL && parser->error_cap > 0) {
        snprintf(parser->error, parser->error_cap, "position %lu: %s",
                 (unsigned long)parser->position, message);
    }
}

static void json_skip_space(JsonParser *parser)
{
    while (parser->text[parser->position] == ' ' ||
           parser->text[parser->position] == '\t' ||
           parser->text[parser->position] == '\n' ||
           parser->text[parser->position] == '\r') {
        parser->position++;
    }
}

static JsonValue *json_new(JsonType type)
{
    JsonValue *value = (JsonValue *)malloc(sizeof(JsonValue));

    if (value == NULL) {
        return NULL;
    }
    memset(value, 0, sizeof(JsonValue));
    value->type = type;
    return value;
}

static int json_parse_value(JsonParser *parser, JsonValue **out);

static int json_parse_string(JsonParser *parser, char *out, size_t cap)
{
    size_t length = 0;

    if (parser->text[parser->position] != '"') {
        json_fail(parser, "a string was expected");
        return -1;
    }
    parser->position++;
    while (parser->text[parser->position] != '"') {
        char c = parser->text[parser->position];
        if (c == '\0') {
            json_fail(parser, "the string is not closed");
            return -1;
        }
        if (c == '\\') {
            char escape = parser->text[parser->position + 1];
            parser->position += 2;
            switch (escape) {
                case 'n':
                    c = '\n';
                    break;
                case 't':
                    c = '\t';
                    break;
                case 'r':
                    c = '\r';
                    break;
                case 'b':
                    c = '\b';
                    break;
                case 'f':
                    c = '\f';
                    break;
                case '"':
                    c = '"';
                    break;
                case '\\':
                    c = '\\';
                    break;
                case '/':
                    c = '/';
                    break;
                case 'u': {
                    unsigned int code = 0;
                    int i;
                    for (i = 0; i < 4; i++) {
                        char digit = parser->text[parser->position + i];
                        code = code * 16u;
                        if (digit >= '0' && digit <= '9') {
                            code += (unsigned int)(digit - '0');
                        } else if (digit >= 'a' && digit <= 'f') {
                            code += (unsigned int)(digit - 'a' + 10);
                        } else if (digit >= 'A' && digit <= 'F') {
                            code += (unsigned int)(digit - 'A' + 10);
                        } else {
                            json_fail(parser, "a unicode escape needs four hex digits");
                            return -1;
                        }
                    }
                    parser->position += 4;
                    if (length + 1 < cap) {
                        out[length++] = (char)(code & 0x7fu);
                    }
                    continue;
                }
                default:
                    json_fail(parser, "unknown escape sequence");
                    return -1;
            }
        } else {
            parser->position++;
        }
        if (length + 1 < cap) {
            out[length++] = c;
        }
    }
    parser->position++;
    out[length] = '\0';
    return 0;
}

static int json_parse_object(JsonParser *parser, JsonValue *value)
{
    parser->position++;
    json_skip_space(parser);
    if (parser->text[parser->position] == '}') {
        parser->position++;
        return 0;
    }
    for (;;) {
        char key[JSON_MAX_KEY];
        JsonValue *child;
        json_skip_space(parser);
        if (json_parse_string(parser, key, sizeof key) != 0) {
            return -1;
        }
        json_skip_space(parser);
        if (parser->text[parser->position] != ':') {
            json_fail(parser, "a colon was expected");
            return -1;
        }
        parser->position++;
        if (json_parse_value(parser, &child) != 0) {
            return -1;
        }
        if (value->member_count < JSON_MAX_MEMBERS) {
            {
                size_t n = strlen(key);
                if (n > JSON_MAX_KEY - 1) {
                    n = JSON_MAX_KEY - 1;
                }
                memcpy(value->members[value->member_count].key, key, n);
                value->members[value->member_count].key[n] = '\0';
            }
            value->members[value->member_count].value = child;
            value->member_count++;
        } else {
            json_free(child);
        }
        json_skip_space(parser);
        if (parser->text[parser->position] == ',') {
            parser->position++;
            continue;
        }
        if (parser->text[parser->position] == '}') {
            parser->position++;
            return 0;
        }
        json_fail(parser, "a comma or a closing brace was expected");
        return -1;
    }
}

static int json_parse_array(JsonParser *parser, JsonValue *value)
{
    parser->position++;
    json_skip_space(parser);
    if (parser->text[parser->position] == ']') {
        parser->position++;
        return 0;
    }
    for (;;) {
        JsonValue *child;
        if (json_parse_value(parser, &child) != 0) {
            return -1;
        }
        if (value->item_count < JSON_MAX_MEMBERS) {
            value->items[value->item_count] = child;
            value->item_count++;
        } else {
            json_free(child);
        }
        json_skip_space(parser);
        if (parser->text[parser->position] == ',') {
            parser->position++;
            continue;
        }
        if (parser->text[parser->position] == ']') {
            parser->position++;
            return 0;
        }
        json_fail(parser, "a comma or a closing bracket was expected");
        return -1;
    }
}

static int json_parse_value(JsonParser *parser, JsonValue **out)
{
    char c;

    if (parser->depth >= JSON_MAX_DEPTH) {
        json_fail(parser, "the document is nested too deeply");
        return -1;
    }
    json_skip_space(parser);
    c = parser->text[parser->position];
    if (c == '{') {
        JsonValue *value = json_new(JSON_OBJECT);
        if (value == NULL) {
            json_fail(parser, "out of memory");
            return -1;
        }
        parser->depth++;
        if (json_parse_object(parser, value) != 0) {
            json_free(value);
            return -1;
        }
        parser->depth--;
        *out = value;
        return 0;
    }
    if (c == '[') {
        JsonValue *value = json_new(JSON_ARRAY);
        if (value == NULL) {
            json_fail(parser, "out of memory");
            return -1;
        }
        parser->depth++;
        if (json_parse_array(parser, value) != 0) {
            json_free(value);
            return -1;
        }
        parser->depth--;
        *out = value;
        return 0;
    }
    if (c == '"') {
        JsonValue *value = json_new(JSON_STRING);
        if (value == NULL) {
            json_fail(parser, "out of memory");
            return -1;
        }
        if (json_parse_string(parser, value->string, sizeof value->string) != 0) {
            json_free(value);
            return -1;
        }
        *out = value;
        return 0;
    }
    if (strncmp(parser->text + parser->position, "true", 4) == 0) {
        JsonValue *value = json_new(JSON_BOOL);
        if (value == NULL) {
            json_fail(parser, "out of memory");
            return -1;
        }
        value->boolean = 1;
        parser->position += 4;
        *out = value;
        return 0;
    }
    if (strncmp(parser->text + parser->position, "false", 5) == 0) {
        JsonValue *value = json_new(JSON_BOOL);
        if (value == NULL) {
            json_fail(parser, "out of memory");
            return -1;
        }
        value->boolean = 0;
        parser->position += 5;
        *out = value;
        return 0;
    }
    if (strncmp(parser->text + parser->position, "null", 4) == 0) {
        JsonValue *value = json_new(JSON_NULL);
        if (value == NULL) {
            json_fail(parser, "out of memory");
            return -1;
        }
        parser->position += 4;
        *out = value;
        return 0;
    }
    if (c == '-' || isdigit((unsigned char)c)) {
        JsonValue *value = json_new(JSON_NUMBER);
        int sign = 1;
        double result = 0.0;
        if (value == NULL) {
            json_fail(parser, "out of memory");
            return -1;
        }
        if (c == '-') {
            sign = -1;
            parser->position++;
        }
        while (isdigit((unsigned char)parser->text[parser->position])) {
            result = result * 10.0 + (double)(parser->text[parser->position] - '0');
            parser->position++;
        }
        if (parser->text[parser->position] == '.') {
            double factor = 0.1;
            parser->position++;
            while (isdigit((unsigned char)parser->text[parser->position])) {
                result += (double)(parser->text[parser->position] - '0') * factor;
                factor *= 0.1;
                parser->position++;
            }
        }
        value->number = result * (double)sign;
        *out = value;
        return 0;
    }
    json_fail(parser, "an unexpected character was found");
    return -1;
}

JsonValue *json_parse(const char *text, char *error, size_t cap)
{
    JsonParser parser;
    JsonValue *root = NULL;

    if (text == NULL) {
        return NULL;
    }
    parser.text = text;
    parser.position = 0;
    parser.depth = 0;
    parser.error = error;
    parser.error_cap = cap;
    parser.failed = 0;
    if (error != NULL && cap > 0) {
        error[0] = '\0';
    }
    if (json_parse_value(&parser, &root) != 0) {
        return NULL;
    }
    json_skip_space(&parser);
    return root;
}

void json_free(JsonValue *value)
{
    int i;

    if (value == NULL) {
        return;
    }
    for (i = 0; i < value->member_count; i++) {
        json_free(value->members[i].value);
    }
    for (i = 0; i < value->item_count; i++) {
        json_free(value->items[i]);
    }
    free(value);
}

JsonValue *json_find(const JsonValue *root, const char *path)
{
    const JsonValue *current = root;
    const char *segment = path;
    char key[JSON_MAX_KEY];
    int i;

    if (root == NULL || path == NULL) {
        return NULL;
    }
    while (*segment != '\0' && current != NULL) {
        size_t length = 0;
        while (segment[length] != '\0' && segment[length] != '.') {
            length++;
        }
        if (length >= JSON_MAX_KEY) {
            length = JSON_MAX_KEY - 1;
        }
        memcpy(key, segment, length);
        key[length] = '\0';
        if (current->type == JSON_OBJECT) {
            const JsonValue *next = NULL;
            for (i = 0; i < current->member_count; i++) {
                if (strcmp(current->members[i].key, key) == 0) {
                    next = current->members[i].value;
                    break;
                }
            }
            current = next;
        } else if (current->type == JSON_ARRAY) {
            int index = atoi(key);
            if (index < 0 || index >= current->item_count) {
                return NULL;
            }
            current = current->items[index];
        } else {
            return NULL;
        }
        segment += length;
        if (*segment == '.') {
            segment++;
        }
    }
    return (JsonValue *)current;
}

int json_get_number(const JsonValue *root, const char *path, double *out)
{
    const JsonValue *value = json_find(root, path);

    if (value == NULL || value->type != JSON_NUMBER || out == NULL) {
        return -1;
    }
    *out = value->number;
    return 0;
}

int json_get_string(const JsonValue *root, const char *path, char *out, size_t cap)
{
    const JsonValue *value = json_find(root, path);

    if (value == NULL || value->type != JSON_STRING || out == NULL || cap == 0) {
        return -1;
    }
    {
        size_t n = strlen(value->string);
        if (n > cap - 1) {
            n = cap - 1;
        }
        memcpy(out, value->string, n);
        out[n] = '\0';
    }
    return 0;
}

static int json_serialize_value(const JsonValue *value, char *out, size_t cap, size_t *position)
{
    int i;

    if (value == NULL) {
        return -1;
    }
    switch (value->type) {
        case JSON_NULL:
            if (*position + 5 >= cap) {
                return -1;
            }
            memcpy(out + *position, "null", 4);
            *position += 4;
            return 0;
        case JSON_BOOL:
            if (*position + 6 >= cap) {
                return -1;
            }
            if (value->boolean) {
                memcpy(out + *position, "true", 4);
                *position += 4;
            } else {
                memcpy(out + *position, "false", 5);
                *position += 5;
            }
            return 0;
        case JSON_NUMBER: {
            int written = snprintf(out + *position, cap - *position, "%g", value->number);
            if (written < 0) {
                return -1;
            }
            *position += (size_t)written;
            return 0;
        }
        case JSON_STRING:
            if (*position + 2 >= cap) {
                return -1;
            }
            out[(*position)++] = '"';
            for (i = 0; value->string[i] != '\0'; i++) {
                if (*position + 2 >= cap) {
                    return -1;
                }
                if (value->string[i] == '"' || value->string[i] == '\\') {
                    out[(*position)++] = '\\';
                }
                out[(*position)++] = value->string[i];
            }
            out[(*position)++] = '"';
            out[*position] = '\0';
            return 0;
        case JSON_ARRAY:
            if (*position + 2 >= cap) {
                return -1;
            }
            out[(*position)++] = '[';
            for (i = 0; i < value->item_count; i++) {
                if (i > 0) {
                    out[(*position)++] = ',';
                }
                out[*position] = '\0';
                if (json_serialize_value(value->items[i], out, cap, position) != 0) {
                    return -1;
                }
            }
            if (*position + 2 >= cap) {
                return -1;
            }
            out[(*position)++] = ']';
            out[*position] = '\0';
            return 0;
        case JSON_OBJECT:
            if (*position + 2 >= cap) {
                return -1;
            }
            out[(*position)++] = '{';
            for (i = 0; i < value->member_count; i++) {
                if (i > 0) {
                    out[(*position)++] = ',';
                }
                if (*position + JSON_MAX_KEY + 4 >= cap) {
                    return -1;
                }
                out[(*position)++] = '"';
                {
                    size_t n = strlen(value->members[i].key);
                    memcpy(out + *position, value->members[i].key, n);
                    *position += n;
                }
                out[(*position)++] = '"';
                out[(*position)++] = ':';
                out[*position] = '\0';
                if (json_serialize_value(value->members[i].value, out, cap, position) != 0) {
                    return -1;
                }
            }
            if (*position + 2 >= cap) {
                return -1;
            }
            out[(*position)++] = '}';
            out[*position] = '\0';
            return 0;
        default:
            return -1;
    }
}

int json_serialize(const JsonValue *value, char *out, size_t cap)
{
    size_t position = 0;

    if (value == NULL || out == NULL || cap == 0) {
        return -1;
    }
    out[0] = '\0';
    if (json_serialize_value(value, out, cap, &position) != 0) {
        return -1;
    }
    return (int)position;
}

void json_print(const JsonValue *value, int indent)
{
    int i;

    if (value == NULL) {
        printf("%*s(null)\n", indent * 2, "");
        return;
    }
    switch (value->type) {
        case JSON_NULL:
            printf("%*snull\n", indent * 2, "");
            break;
        case JSON_BOOL:
            printf("%*s%s\n", indent * 2, "", value->boolean ? "true" : "false");
            break;
        case JSON_NUMBER:
            printf("%*s%g\n", indent * 2, "", value->number);
            break;
        case JSON_STRING:
            printf("%*s\"%s\"\n", indent * 2, "", value->string);
            break;
        case JSON_ARRAY:
            printf("%*sarray with %d items\n", indent * 2, "", value->item_count);
            for (i = 0; i < value->item_count; i++) {
                json_print(value->items[i], indent + 1);
            }
            break;
        case JSON_OBJECT:
            printf("%*sobject with %d members\n", indent * 2, "", value->member_count);
            for (i = 0; i < value->member_count; i++) {
                printf("%*s%s:\n", (indent + 1) * 2, "", value->members[i].key);
                json_print(value->members[i].value, indent + 2);
            }
            break;
        default:
            break;
    }
}

void json_print_paths(const JsonValue *value, const char *prefix, int depth)
{
    int i;
    char path[JSON_MAX_KEY * 2];

    if (value == NULL || depth > JSON_MAX_DEPTH) {
        return;
    }
    if (value->type == JSON_OBJECT) {
        for (i = 0; i < value->member_count; i++) {
            if (prefix[0] == '\0') {
                snprintf(path, sizeof path, "%s", value->members[i].key);
            } else {
                snprintf(path, sizeof path, "%s.%s", prefix, value->members[i].key);
            }
            printf("  path %s\n", path);
            json_print_paths(value->members[i].value, path, depth + 1);
        }
    } else if (value->type == JSON_ARRAY) {
        for (i = 0; i < value->item_count; i++) {
            snprintf(path, sizeof path, "%s[%d]", prefix, i);
            printf("  path %s\n", path);
            json_print_paths(value->items[i], path, depth + 1);
        }
    }
}
