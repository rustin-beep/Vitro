#include <stdio.h>
#include <string.h>
#include "serial.h"

static void hex_dump(const unsigned char *data, int length)
{
    int i;

    printf("  ");
    for (i = 0; i < length; i++) {
        printf("%02x ", data[i]);
    }
    printf("\n");
}

int main(void)
{
    static const char *const PAYLOADS[5] = { "a", "hello", "12345678", "payload-16-byt", "x" };
    static const unsigned char COMMANDS[5] = { 0x01, 0x02, 0x10, 0x20, 0xff };
    unsigned char stream[512];
    SerialFrame frames[8];
    int stream_length = 0;
    int total_payload = 0;
    int total_bytes = 0;
    int i;

    printf("=== five frames ===\n");
    for (i = 0; i < 5; i++) {
        unsigned char frame[SERIAL_MAX_FRAME];
        int length = serial_pack(COMMANDS[i], (const unsigned char *)PAYLOADS[i],
                                 (int)strlen(PAYLOADS[i]), frame, (int)sizeof frame);
        SerialFrame parsed;
        int rc = serial_unpack(frame, length, &parsed);
        printf("  frame %d command=0x%02x payload=%-16s bytes=%d crc=0x%04x unpack_rc=%d valid=%d\n",
               i + 1, COMMANDS[i], PAYLOADS[i], length, parsed.crc, rc, parsed.valid);
        hex_dump(frame, length < 16 ? length : 16);
        memcpy(stream + stream_length, frame, (size_t)length);
        stream_length += length;
        total_bytes += length;
        total_payload += (int)strlen(PAYLOADS[i]);
    }
    printf("  total bytes=%d total payload bytes=%d overhead=%d\n",
           total_bytes, total_payload, total_bytes - total_payload);

    printf("=== stream with noise ===\n");
    {
        unsigned char noisy[600];
        int noisy_length = 0;
        int skipped = 0;
        int count;

        noisy[noisy_length++] = 0x00;
        noisy[noisy_length++] = 0x11;
        memcpy(noisy + noisy_length, stream, (size_t)stream_length);
        noisy_length += stream_length;
        noisy[noisy_length++] = 0x7f;
        noisy[noisy_length++] = 0x55;
        count = serial_stream_parse(noisy, noisy_length, frames, 8, &skipped);
        printf("  parsed frames=%d skipped noise bytes=%d\n", count, skipped);
        for (i = 0; i < count; i++) {
            printf("    frame %d command=0x%02x length=%d valid=%d\n",
                   i + 1, frames[i].command, frames[i].length, frames[i].valid);
        }
    }

    printf("=== broken frames ===\n");
    {
        unsigned char broken[SERIAL_MAX_FRAME];
        int length = serial_pack(0x42, (const unsigned char *)"payload", 7, broken,
                                 (int)sizeof broken);
        SerialFrame frame;
        int rc;
        broken[8] = (unsigned char)(broken[8] ^ 0x01);
        rc = serial_unpack(broken, length, &frame);
        printf("  crc error rc=%d valid=%d\n", rc, frame.valid);
        length = serial_pack(0x42, (const unsigned char *)"payload", 7, broken,
                             (int)sizeof broken);
        broken[length - 1] = 0x00;
        rc = serial_unpack(broken, length, &frame);
        printf("  trailer error rc=%d valid=%d\n", rc, frame.valid);
        length = serial_pack(0x42, (const unsigned char *)"payload", 7, broken,
                             (int)sizeof broken);
        broken[0] = 0x00;
        rc = serial_unpack(broken, length, &frame);
        printf("  magic error rc=%d valid=%d\n", rc, frame.valid);
    }
    printf("=== done ===\n");
    return 0;
}
