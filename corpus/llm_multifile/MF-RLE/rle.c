#include "rle.h"

int rle_ops = 0;
#include <stdio.h>
#include <string.h>

int rle_compressed_size(const unsigned char *input, int input_len)
{
    int i = 0;
    int pairs = 0;

    if (input == NULL || input_len < 0) {
        return -1;
    }
    while (i < input_len) {
        int run = 1;
        while (i + run < input_len && input[i + run] == input[i] && run < RLE_MAX_RUN) {
            run++;
        }
        pairs++;
        i += run;
    }
    return pairs * RLE_PAIR_SIZE;
}

int rle_compress(const unsigned char *input, int input_len, unsigned char *output, int output_cap)
{
    int i = 0;
    int written = 0;

    if (input == NULL || output == NULL || input_len < 0 || output_cap < 0) {
        return -1;
    }
    while (i < input_len) {
        int run = 1;
        while (i + run < input_len && input[i + run] == input[i] && run < RLE_MAX_RUN) {
            run++;
        }
        if (written + RLE_PAIR_SIZE > output_cap) {
            return -2;
        }
        output[written] = (unsigned char)run;
        output[written + 1] = input[i];
        written += RLE_PAIR_SIZE;
        rle_ops++;
        i += run;
    }
    return written;
}

int rle_decompress(const unsigned char *input, int input_len, unsigned char *output, int output_cap)
{
    int i = 0;
    int written = 0;

    if (input == NULL || output == NULL || input_len < 0 || output_cap < 0) {
        return -1;
    }
    while (i + 1 < input_len) {
        int run = (int)input[i];
        unsigned char value = input[i + 1];
        int k;
        if (run < 1) {
            return -3;
        }
        if (written + run > output_cap) {
            return -2;
        }
        for (k = 0; k < run; k++) {
            output[written] = value;
            written++;
        }
        i += RLE_PAIR_SIZE;
    }
    if (i != input_len) {
        return -4;
    }
    return written;
}

void rle_hex_dump(const unsigned char *data, int length, int max_bytes)
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
