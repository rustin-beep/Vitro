#include "proto.h"
#include <stdio.h>
#include <string.h>

int proto_encode_varint(unsigned long value, unsigned char *buffer, int capacity)
{
    int written = 0;

    while (1) {
        if (written >= capacity) {
            return -1;
        }
        if (value < 0x80ul) {
            buffer[written++] = (unsigned char)value;
            return written;
        }
        buffer[written++] = (unsigned char)((value & 0x7ful) | 0x80ul);
        value >>= 7;
    }
}

int proto_decode_varint(const unsigned char *buffer, int length, unsigned long *value,
                        int *consumed)
{
    unsigned long result = 0;
    int shift = 0;
    int i = 0;

    while (i < length) {
        unsigned char byte = buffer[i];
        result |= ((unsigned long)(byte & 0x7ful)) << shift;
        i++;
        if ((byte & 0x80u) == 0u) {
            *value = result;
            if (consumed != NULL) {
                *consumed = i;
            }
            return 0;
        }
        shift += 7;
        if (shift > 63) {
            return -1;
        }
    }
    return -2;
}

int proto_skip_field(const unsigned char *buffer, int length, ProtoType type)
{
    switch (type) {
        case PROTO_VARINT: {
            unsigned long value = 0;
            int consumed = 0;
            if (proto_decode_varint(buffer, length, &value, &consumed) != 0) {
                return -1;
            }
            return consumed;
        }
        case PROTO_BOOL:
            return (length >= 1) ? 1 : -1;
        case PROTO_INT32:
            return (length >= 4) ? 4 : -1;
        case PROTO_STRING: {
            unsigned long size = 0;
            int consumed = 0;
            if (proto_decode_varint(buffer, length, &size, &consumed) != 0) {
                return -1;
            }
            if ((long)consumed + (long)size > (long)length) {
                return -1;
            }
            return consumed + (int)size;
        }
        default:
            return -1;
    }
}

int proto_encode(const ProtoMessage *message, unsigned char *buffer, int capacity)
{
    int offset = 0;
    int i;

    for (i = 0; i < message->field_count; i++) {
        const ProtoField *field = &message->fields[i];
        int written;
        unsigned char tag;

        if (offset + 2 > capacity) {
            return -1;
        }
        tag = (unsigned char)(((unsigned int)field->number << 3) | (unsigned int)field->type);
        buffer[offset++] = tag;
        switch (field->type) {
            case PROTO_VARINT:
            case PROTO_BOOL: {
                unsigned long value = (field->type == PROTO_BOOL)
                                          ? (unsigned long)field->bool_value
                                          : (unsigned long)field->number_value;
                written = proto_encode_varint(value, buffer + offset, capacity - offset);
                if (written < 0) {
                    return -1;
                }
                offset += written;
                break;
            }
            case PROTO_INT32: {
                int k;
                if (offset + 4 > capacity) {
                    return -1;
                }
                for (k = 0; k < 4; k++) {
                    buffer[offset + k] = (unsigned char)((field->number_value >> (k * 8)) & 0xff);
                }
                offset += 4;
                break;
            }
            case PROTO_STRING: {
                size_t length = strlen(field->string_value);
                written = proto_encode_varint((unsigned long)length, buffer + offset,
                                             capacity - offset);
                if (written < 0) {
                    return -1;
                }
                offset += written;
                if (offset + (int)length > capacity) {
                    return -1;
                }
                memcpy(buffer + offset, field->string_value, length);
                offset += (int)length;
                break;
            }
            default:
                return -1;
        }
    }
    return offset;
}

int proto_decode(const unsigned char *buffer, int length, ProtoMessage *message,
                 int *skipped_bytes)
{
    int offset = 0;
    int skipped = 0;

    memset(message, 0, sizeof(ProtoMessage));
    while (offset < length) {
        unsigned char tag = buffer[offset];
        int number = (int)(tag >> 3);
        ProtoType type = (ProtoType)(tag & 0x07u);
        int consumed = 0;
        ProtoField field;

        offset++;
        memset(&field, 0, sizeof field);
        field.number = number;
        field.type = type;
        switch (type) {
            case PROTO_VARINT:
            case PROTO_BOOL: {
                unsigned long value = 0;
                if (proto_decode_varint(buffer + offset, length - offset, &value,
                                        &consumed) != 0) {
                    return -1;
                }
                if (type == PROTO_BOOL) {
                    field.bool_value = (value != 0ul) ? 1 : 0;
                } else {
                    field.number_value = (int)value;
                }
                offset += consumed;
                break;
            }
            case PROTO_INT32: {
                int k;
                int value = 0;
                if (offset + 4 > length) {
                    return -1;
                }
                for (k = 0; k < 4; k++) {
                    value |= (int)buffer[offset + k] << (k * 8);
                }
                offset += 4;
                field.number_value = value;
                break;
            }
            case PROTO_STRING: {
                unsigned long size = 0;
                if (proto_decode_varint(buffer + offset, length - offset, &size,
                                        &consumed) != 0) {
                    return -1;
                }
                offset += consumed;
                if (offset + (int)size > length) {
                    return -1;
                }
                if ((int)size >= PROTO_MAX_STRING) {
                    return -1;
                }
                memcpy(field.string_value, buffer + offset, (size_t)size);
                field.string_value[size] = '\0';
                offset += (int)size;
                break;
            }
            default: {
                int used = proto_skip_field(buffer + offset, length - offset, type);
                if (used < 0) {
                    return -1;
                }
                skipped += used + 1;
                offset += used;
                continue;
            }
        }
        if (message->field_count < PROTO_MAX_FIELDS) {
            message->fields[message->field_count] = field;
            message->field_count++;
        }
    }
    if (skipped_bytes != NULL) {
        *skipped_bytes = skipped;
    }
    return message->field_count;
}

void proto_print(const ProtoMessage *message)
{
    int i;

    for (i = 0; i < message->field_count; i++) {
        const ProtoField *field = &message->fields[i];
        printf("    field %d type=%d", field->number, (int)field->type);
        if (field->type == PROTO_STRING) {
            printf(" value=\"%s\"", field->string_value);
        } else if (field->type == PROTO_BOOL) {
            printf(" value=%s", field->bool_value ? "true" : "false");
        } else {
            printf(" value=%d", field->number_value);
        }
        printf("\n");
    }
}

void proto_hex_dump(const unsigned char *data, int length, int max_bytes)
{
    int i;
    int limit;

    if (data == NULL) {
        return;
    }
    limit = (length < max_bytes) ? length : max_bytes;
    printf("  ");
    for (i = 0; i < limit; i++) {
        printf("%02x ", data[i]);
    }
    printf("\n");
}
