#ifndef RLE_H
#define RLE_H

#include <stddef.h>

#define RLE_MAX_RUN 255
#define RLE_PAIR_SIZE 2

/* compresses into "run length, value" pairs, returns the number of bytes or -1 */
int rle_compress(const unsigned char *input, int input_len, unsigned char *output, int output_cap);

/* expands the pairs again, returns the number of bytes or -1 */
int rle_decompress(const unsigned char *input, int input_len, unsigned char *output, int output_cap);

/* number of bytes the compressed form needs */
int rle_compressed_size(const unsigned char *input, int input_len);

void rle_hex_dump(const unsigned char *data, int length, int max_bytes);

extern int rle_ops;

#endif /* RLE_H */
