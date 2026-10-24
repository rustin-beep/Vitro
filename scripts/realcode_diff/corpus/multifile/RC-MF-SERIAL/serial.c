#include "serial.h"
#include <string.h>

int serial_crc16(const unsigned char *data, int length)
{
    unsigned int crc = 0xffffu;
    int i;
    int bit;

    if (data == NULL) {
        return 0;
    }
    for (i = 0; i < length; i++) {
        crc ^= (unsigned int)data[i] << 8;
        for (bit = 0; bit < 8; bit++) {
            if ((crc & 0x8000u) != 0u) {
                crc = ((crc << 1) ^ 0x1021u) & 0xffffu;
            } else {
                crc = (crc << 1) & 0xffffu;
            }
        }
    }
    return (int)crc;
}

int serial_pack(unsigned char command, const unsigned char *payload, int length,
                unsigned char *out, int capacity)
{
    unsigned char frame[SERIAL_MAX_FRAME];
    int total;
    int crc;

    if (out == NULL || length < 0 || length > SERIAL_MAX_PAYLOAD) {
        return -1;
    }
    total = SERIAL_HEADER_SIZE + length + 3;
    if (capacity < total) {
        return -2;
    }
    frame[0] = (unsigned char)(SERIAL_MAGIC & 0xffu);
    frame[1] = (unsigned char)((SERIAL_MAGIC >> 8) & 0xffu);
    frame[2] = (unsigned char)length;
    frame[3] = command;
    if (length > 0 && payload != NULL) {
        memcpy(frame + 4, payload, (size_t)length);
    }
    crc = serial_crc16(frame + 2, length + 2);
    frame[4 + length] = (unsigned char)(crc & 0xffu);
    frame[5 + length] = (unsigned char)((crc >> 8) & 0xffu);
    frame[6 + length] = SERIAL_TRAILER;
    memcpy(out, frame, (size_t)total);
    return total;
}

int serial_unpack(const unsigned char *data, int length, SerialFrame *frame)
{
    int payload_length;
    int crc_stored;
    int crc_computed;

    if (data == NULL || frame == NULL) {
        return -1;
    }
    memset(frame, 0, sizeof(SerialFrame));
    if (length < SERIAL_HEADER_SIZE + 3) {
        return -2;
    }
    if (data[0] != (unsigned char)(SERIAL_MAGIC & 0xffu) ||
        data[1] != (unsigned char)((SERIAL_MAGIC >> 8) & 0xffu)) {
        return -3;
    }
    payload_length = (int)data[2];
    if (payload_length > SERIAL_MAX_PAYLOAD) {
        return -4;
    }
    if (length < SERIAL_HEADER_SIZE + payload_length + 3) {
        return -5;
    }
    frame->magic = SERIAL_MAGIC;
    frame->length = (unsigned char)payload_length;
    frame->command = data[3];
    if (payload_length > 0) {
        memcpy(frame->payload, data + 4, (size_t)payload_length);
    }
    crc_stored = (int)data[4 + payload_length] | ((int)data[5 + payload_length] << 8);
    crc_computed = serial_crc16(data + 2, payload_length + 2);
    frame->crc = (unsigned int)crc_stored;
    frame->trailer = data[6 + payload_length];
    if (crc_stored != crc_computed) {
        frame->valid = 0;
        return -6;
    }
    if (frame->trailer != SERIAL_TRAILER) {
        frame->valid = 0;
        return -7;
    }
    frame->valid = 1;
    return 0;
}

int serial_stream_parse(const unsigned char *stream, int length, SerialFrame *frames,
                        int max_frames, int *skipped)
{
    int offset = 0;
    int count = 0;
    int noise = 0;

    if (stream == NULL || frames == NULL) {
        return -1;
    }
    while (offset + SERIAL_HEADER_SIZE < length) {
        int payload_length;
        int total;
        if (stream[offset] != (unsigned char)(SERIAL_MAGIC & 0xffu) ||
            stream[offset + 1] != (unsigned char)((SERIAL_MAGIC >> 8) & 0xffu)) {
            offset++;
            noise++;
            continue;
        }
        payload_length = (int)stream[offset + 2];
        total = SERIAL_HEADER_SIZE + payload_length + 3;
        if (offset + total > length) {
            noise += length - offset;
            break;
        }
        if (count < max_frames) {
            serial_unpack(stream + offset, total, &frames[count]);
            count++;
        }
        offset += total;
    }
    if (skipped != NULL) {
        *skipped = noise;
    }
    return count;
}
