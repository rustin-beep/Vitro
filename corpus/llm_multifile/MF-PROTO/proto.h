#ifndef PROTO_H
#define PROTO_H

#include <stddef.h>

#define PROTO_MAX_FIELDS 16
#define PROTO_MAX_STRING 32
#define PROTO_MAX_BUFFER 256

typedef enum {
    PROTO_VARINT = 0,
    PROTO_INT32 = 1,
    PROTO_STRING = 2,
    PROTO_BOOL = 3
} ProtoType;

typedef struct {
    int number;
    ProtoType type;
    int number_value;
    char string_value[PROTO_MAX_STRING];
    int bool_value;
} ProtoField;

typedef struct {
    ProtoField fields[PROTO_MAX_FIELDS];
    int field_count;
} ProtoMessage;

int proto_encode(const ProtoMessage *message, unsigned char *buffer, int capacity);
int proto_decode(const unsigned char *buffer, int length, ProtoMessage *message,
                 int *skipped_bytes);
int proto_encode_varint(unsigned long value, unsigned char *buffer, int capacity);
int proto_decode_varint(const unsigned char *buffer, int length, unsigned long *value,
                        int *consumed);
int proto_skip_field(const unsigned char *buffer, int length, ProtoType type);
void proto_print(const ProtoMessage *message);
void proto_hex_dump(const unsigned char *data, int length, int max_bytes);

#endif /* PROTO_H */
