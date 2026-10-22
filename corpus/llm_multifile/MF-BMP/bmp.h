#ifndef BMP_H
#define BMP_H

#include <stddef.h>

#define BMP_FILE_HEADER_SIZE 14
#define BMP_INFO_HEADER_SIZE 40
#define BMP_BPP 24
#define BMP_ALIGNMENT 4

typedef struct {
    int width;
    int height;
    int bits_per_pixel;
    int data_offset;
    int file_size;
    int row_stride;
} BmpInfo;

typedef struct {
    unsigned char b;
    unsigned char g;
    unsigned char r;
} BmpPixel;

/* writes a 24 bit uncompressed BMP, returns the byte count or -1 */
int bmp_build(unsigned char *buf, int cap, const BmpPixel *pixels, int width, int height);

/* parses a BMP file image, returns 0 on success */
int bmp_parse(const unsigned char *buf, int length, BmpInfo *info, BmpPixel *pixels, int max_pixels);

/* number of bytes the file needs for the given size */
int bmp_theoretical_size(int width, int height);

int bmp_to_grayscale(const BmpPixel *in, BmpPixel *out, int count);
int bmp_flip_horizontal(const BmpPixel *in, BmpPixel *out, int width, int height);

void bmp_hex_dump(const unsigned char *data, int length, int max_bytes);
void bmp_print_pixels(const BmpPixel *pixels, int count, int max_pixels);

extern int bmp_ops;

#endif /* BMP_H */
