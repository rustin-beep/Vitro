#include <stdio.h>
#include <string.h>
#include "rle.h"

#define DATA_SIZE 64

static unsigned int lcg_state = 987654321u;

static unsigned int lcg_next(void)
{
    lcg_state = lcg_state * 1103515245u + 12345u;
    return (lcg_state >> 16) & 0x7fffu;
}

static void run_case(const char *label, const unsigned char *data, int length)
{
    unsigned char compressed[256];
    unsigned char restored[256];
    int packed;
    int unpacked;
    int same;
    double ratio;
    int i;

    packed = rle_compress(data, length, compressed, (int)sizeof compressed);
    unpacked = rle_decompress(compressed, packed, restored, (int)sizeof restored);
    same = 1;
    if (unpacked != length) {
        same = 0;
    } else {
        for (i = 0; i < length; i++) {
            if (restored[i] != data[i]) {
                same = 0;
            }
        }
    }
    ratio = (length == 0) ? 0.0 : (double)packed / (double)length;
    printf("  %-18s original=%3d compressed=%3d restored=%3d round_trip=%s ratio=%.3f\n",
           label, length, packed, unpacked, same ? "ok" : "broken", ratio);
    printf("    compressed bytes:");
    rle_hex_dump(compressed, packed, 16);
}

int main(void)
{
    unsigned char identical[DATA_SIZE];
    unsigned char alternating[DATA_SIZE];
    unsigned char random_data[DATA_SIZE];
    unsigned char mixed[DATA_SIZE];
    unsigned char empty[4];
    unsigned char single[4];
    int i;

    for (i = 0; i < DATA_SIZE; i++) {
        identical[i] = 0x5a;
        alternating[i] = (unsigned char)((i % 2 == 0) ? 0xaa : 0x55);
        random_data[i] = (unsigned char)(lcg_next() & 0xffu);
        mixed[i] = (unsigned char)((i % 5 == 0) ? 0x00 : ((i % 7 == 0) ? 0xff : (unsigned char)i));
    }
    empty[0] = 0;
    single[0] = 0x42;

    printf("=== run length encoding ===\n");
    run_case("all identical", identical, DATA_SIZE);
    run_case("alternating", alternating, DATA_SIZE);
    run_case("lcg random", random_data, DATA_SIZE);
    run_case("mixed 00/ff", mixed, DATA_SIZE);

    printf("=== edge cases ===\n");
    run_case("empty input", empty, 0);
    run_case("single byte", single, 1);
    {
        unsigned char long_run[300];
        unsigned char compressed[1024];
        unsigned char restored[1024];
        for (i = 0; i < 300; i++) {
            long_run[i] = 0x77;
        }
        {
            int packed = rle_compress(long_run, 300, compressed, (int)sizeof compressed);
            int unpacked = rle_decompress(compressed, packed, restored, (int)sizeof restored);
            printf("  %-18s original=300 compressed=%3d restored=%3d (run split at %d)\n",
                   "run longer than 255", packed, unpacked, RLE_MAX_RUN);
        }
    }

    printf("=== size prediction ===\n");
    printf("  predicted_all_identical=%d predicted_alternating=%d\n",
           rle_compressed_size(identical, DATA_SIZE), rle_compressed_size(alternating, DATA_SIZE));
    printf("  predicted_empty=%d\n", rle_compressed_size(empty, 0));
    printf("  rle_ops=%d\n", rle_ops);
    return 0;
}
