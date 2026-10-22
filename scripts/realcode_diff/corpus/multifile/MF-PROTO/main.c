#include <stdio.h>
#include <string.h>
#include "proto.h"

static void set_varint(ProtoMessage *message, int number, int value)
{
    ProtoField *field = &message->fields[message->field_count++];

    memset(field, 0, sizeof(ProtoField));
    field->number = number;
    field->type = PROTO_VARINT;
    field->number_value = value;
}

static void set_int32(ProtoMessage *message, int number, int value)
{
    ProtoField *field = &message->fields[message->field_count++];

    memset(field, 0, sizeof(ProtoField));
    field->number = number;
    field->type = PROTO_INT32;
    field->number_value = value;
}

static void set_string(ProtoMessage *message, int number, const char *value)
{
    ProtoField *field = &message->fields[message->field_count++];

    memset(field, 0, sizeof(ProtoField));
    field->number = number;
    field->type = PROTO_STRING;
    {
        size_t n = strlen(value);
        if (n > PROTO_MAX_STRING - 1) {
            n = PROTO_MAX_STRING - 1;
        }
        memcpy(field->string_value, value, n);
        field->string_value[n] = '\0';
    }
}

static void set_bool_field(ProtoMessage *message, int number, int value)
{
    ProtoField *field = &message->fields[message->field_count++];

    memset(field, 0, sizeof(ProtoField));
    field->number = number;
    field->type = PROTO_BOOL;
    field->bool_value = value;
}

int main(void)
{
    ProtoMessage messages[3];
    ProtoMessage decoded;
    unsigned char buffer[PROTO_MAX_BUFFER];
    int lengths[3];
    int total_bytes = 0;
    int total_fields = 0;
    int i;

    memset(messages, 0, sizeof messages);
    set_varint(&messages[0], 1, 150);
    set_string(&messages[0], 2, "hello");
    set_int32(&messages[0], 3, -42);

    set_varint(&messages[1], 1, 7);
    set_varint(&messages[1], 1, 8);
    set_varint(&messages[1], 1, 9);
    set_bool_field(&messages[1], 4, 1);

    set_string(&messages[2], 5, "vitro");
    set_int32(&messages[2], 6, 2026);

    printf("=== three messages ===\n");
    for (i = 0; i < 3; i++) {
        int skipped = 0;
        int length = proto_encode(&messages[i], buffer, (int)sizeof buffer);
        printf("  message %d fields=%d bytes=%d\n", i + 1, messages[i].field_count, length);
        proto_hex_dump(buffer, length, 32);
        proto_decode(buffer, length, &decoded, &skipped);
        proto_print(&decoded);
        printf("    decoded fields=%d skipped=%d\n", decoded.field_count, skipped);
        total_bytes += length;
        total_fields += messages[i].field_count;
        lengths[i] = length;
    }
    printf("  total encoded bytes=%d total fields=%d\n", total_bytes, total_fields);
    (void)lengths;

    printf("=== unknown field number is skipped ===\n");
    {
        unsigned char with_unknown[32];
        int length = 0;
        int skipped = 0;
        int count;

        with_unknown[length++] = (unsigned char)((9 << 3) | PROTO_VARINT);
        with_unknown[length++] = 0x2a;
        with_unknown[length++] = (unsigned char)((10 << 3) | PROTO_STRING);
        with_unknown[length++] = 0x03;
        with_unknown[length++] = 'a';
        with_unknown[length++] = 'b';
        with_unknown[length++] = 'c';
        with_unknown[length++] = (unsigned char)((1 << 3) | PROTO_VARINT);
        with_unknown[length++] = 0x63;
        proto_hex_dump(with_unknown, length, 32);
        count = proto_decode(with_unknown, length, &decoded, &skipped);
        printf("  decoded fields=%d skipped bytes=%d\n", count, skipped);
        proto_print(&decoded);
    }

    printf("=== varint sizes ===\n");
    {
        static const unsigned long VALUES[5] = { 1ul, 127ul, 128ul, 16383ul, 16384ul };
        for (i = 0; i < 5; i++) {
            unsigned char bytes[8];
            int length = proto_encode_varint(VALUES[i], bytes, (int)sizeof bytes);
            printf("  value=%-6lu bytes=%d\n", VALUES[i], length);
        }
    }
    printf("=== done ===\n");
    return 0;
}
