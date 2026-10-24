#ifndef SERIAL_H
#define SERIAL_H

#include <stddef.h>

#define SERIAL_MAGIC 0xaa55u
#define SERIAL_HEADER_SIZE 6
#define SERIAL_TRAILER 0x0du
#define SERIAL_MAX_PAYLOAD 128
#define SERIAL_MAX_FRAME (SERIAL_HEADER_SIZE + SERIAL_MAX_PAYLOAD + 3)

typedef struct {
    unsigned int magic;
    unsigned char length;
    unsigned char command;
    unsigned char payload[SERIAL_MAX_PAYLOAD];
    unsigned int crc;
    unsigned char trailer;
    int valid;
} SerialFrame;

int serial_pack(unsigned char command, const unsigned char *payload, int length,
                unsigned char *out, int capacity);
int serial_unpack(const unsigned char *data, int length, SerialFrame *frame);
int serial_crc16(const unsigned char *data, int length);
int serial_stream_parse(const unsigned char *stream, int length, SerialFrame *frames,
                        int max_frames, int *skipped);

#endif /* SERIAL_H */
